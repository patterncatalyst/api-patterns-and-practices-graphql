---
title: "The N+1 problem and DataLoaders"
order: 13
part: "Data Fetching at Scale"
description: "Counting the source calls a four-cargo page costs, batching them one call per owner, the DataLoader contract and its tick, SmallRye @Source List batch resolvers against Strawberry DataLoaders, per-field against per-key loaders, bulk source operations, and what one failing key does to its batch."
duration: "16 min read"
---

## Learning objectives

By the end of this chapter you can:

- Count an N+1 fan-out field by field, from one `listCargos` call to 29 source calls for a four-cargo page.
- Batch per-field resolvers into one bulk call per owner per level using `@Source List<...>` on Quarkus and a `DataLoader` on Python.
- Apply the DataLoader contract — keys in, values out in the same order, missing keys as null, failures per key, cache scoped to one request.
- Explain why SmallRye's per-method loaders cost more calls (8) than Strawberry's per-key loaders (6) for the same query.
- Scope a loader's cache to a single request so a write like `registerHandlingEvent` is never served stale data by a stale cache.

## Why this matters

Chapter 12 ended on a number. A page of four cargos, each with its itinerary legs, their voyages and locations, and its delivery status, cost 29 source calls. Nothing in that query was unusual. This chapter takes the number apart, shows where each call comes from, and brings it to 8 on Quarkus and 6 on Python without changing a field of the schema.

The code is in `examples/13-dataloaders/`. It starts from the Chapter 12 example, so the seed, the keyset cursors, the exposed and masked errors and the deprecation of Chapter 11 are all there. Every source gains a bulk operation next to its single-key one, SmallRye batches with `@Source List<...>` resolvers, and Strawberry batches with DataLoaders built once per request. The schema is the one Chapter 12 served, and `verify.sh` diffs it against the canonical SDL to prove it.

## Counting the N+1

The name comes from databases: one query for a list, then one more for each of its N rows. A GraphQL server does the same thing by construction. A resolver is called once per field occurrence, so a field under a list is called once per list item, and each call that reads a source is a round trip.

The query in `verify.sh` is the one Chapter 12 measured:

```graphql
{ cargos(first: 4) { edges { node { trackingId
    itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } }
    delivery { transportStatus } } } } }
```

Figure 13.1 counts the calls field by field. The page is one `listCargos` call. Each edge's `node` loads its cargo, four calls. The itinerary and the delivery both read the routing source, so four cargos make eight `getItinerary` calls, and each delivery also reads its events, four more. The four cargos have one, none, one and two legs, which makes four legs with a voyage and two locations each: four `getVoyage` calls and eight `getLocation` calls. The total is 1 + 4 + 8 + 4 + 4 + 8 = 29.

{% include excalidraw.html file="13-n-plus-one-fanout" alt="The tree reads from left to right. The field cargos(first: 4) calls listCargos once. Its CargoEdge.node field calls getCargo four times. Cargo.itinerary calls getItinerary four times, and Cargo.delivery calls getItinerary four times and listEvents four times. Below the itinerary, Leg.voyage calls getVoyage four times with the keys V300A, V300A, V100S and V200E, Leg.loadLocation calls getLocation four times with SGSIN, SGSIN, USNYC and DEHAM, and Leg.unloadLocation calls getLocation four times with CNSHA, CNSHA, DEHAM and NLRTM. The repeated keys are highlighted: V300A, SGSIN and CNSHA twice each, DEHAM once on each side, and every cargo's itinerary twice." caption="Figure 13.1 — The four-cargo query before batching: one call per field occurrence, 29 in all. The highlighted keys are fetched more than once in one request." %}

Several of those calls ask for the same thing. `V300A` is fetched twice because two cargos share a route, and every cargo's itinerary is fetched twice because two fields need it. Chapter 7 showed the smallest version of this, two aliases on one leg costing four voyage calls, and Chapter 1 predicted the large one: a cargo with six legs and twelve events resolves twenty-four locations one at a time. The cost grows with the data, and the client controls the data.

## Batching by owner

The fix starts from what the engine already does. A field's resolver runs only after its parent has resolved, and siblings run together (Chapter 6), so the fields that want the same owner are asked for at about the same moment. Instead of one call per field, make one call per owner for all the keys asked at that moment.

Figure 13.2 shows the result for the same query. The page is still one call. The four cargos load in one `getCargos` call. Their itineraries and events load in one `getItineraries` call and one `listEventsFor` call. The voyages of the legs are one `getVoyages` call, and the locations are one `getLocations` call. A call waits for the call its keys come from, because those keys are in its results, and calls whose keys come from the same place run together.

{% include excalidraw.html file="13-batched-load" alt="The same tree appears with one bulk call per level on the Python stack. The call listCargos is followed by getCargos with four keys. From it, the calls getItineraries with four keys and listEventsFor with four keys. From getItineraries, getVoyages with the keys V100S, V200E and V300A, and getLocations with the keys CNSHA, DEHAM, NLRTM, SGSIN and USNYC. A note says Quarkus makes eight calls for the same query." caption="Figure 13.2 — The same query with one bulk call per level: six calls on Python. Quarkus makes eight, for a reason Figure 13.4 shows." %}

The number of calls now follows the number of fields in the selection, not the number of cargos. `verify.sh` pages two cargos and five cargos with the same selection and gets the same totals as four on both stacks. Chapter 6's execution model, siblings together and children after their parent, is what makes this possible. Martin Kleppmann and Chris Riccomini show in *Designing Data-Intensive Applications*, 2nd edition, in its discussion of response time, how a request that makes several backend calls is as slow as the slowest of them (tail latency amplification); batching cuts the number of calls each request waits on.

## The DataLoader contract

The tool that implements this is the DataLoader, an idea Facebook developed in 2010 for batching reads from its key-value back ends, before GraphQL, and published in 2015 as the JavaScript `dataloader` library. Its contract is small:

- **Keys in, values out, same order.** A loader's function receives a list of keys and returns a list of values of the same length, in the same order. The caller of `load(key)` gets the value at its key's position.
- **Not found is a value.** An unknown key gets `null` at its position. `nodes(ids: ["voy_V999X", "voy_V100S"])` returns `[null, {Voyage V100S}]` with no error, and the one `getVoyages` call carries both keys.
- **Failure can be per key.** A key's slot may hold a failure instead of a value. Whether that spares the other keys depends on the implementation, which is the last section's subject.
- **Keys are deduplicated and cached within a request.** Asking for the same key twice in one request costs one lookup. The cache lives as long as the loader and no longer.

The last point carries the safety rule of the whole chapter. A cache that outlives a request serves stale data to the next one, and the handling store in this example changes between requests. A loader belongs to one request. It is created when the request starts and dropped when it ends, which the example proves with a write: after a handling event is registered, both the mutation's payload and a fresh query report the new status.

## The tick

A loader has to decide when to stop collecting keys and make the call. Each stack answers with a tick: a point in the execution when every field that is going to ask at this level has already asked.

On Strawberry the tick is the event loop's next turn. `DataLoader.load` returns a future and, for the first key of a new batch, schedules the dispatch with `loop.call_soon`. Every resolver that runs before the loop's next turn adds its key to the same batch. When the dispatch runs, the loader calls its function once with the distinct keys. A resolver that awaited a loader resumes after its batch returns, and its children start the next level.

On Quarkus the tick belongs to graphql-java. SmallRye turns a resolver with a `@Source List<...>` parameter into a batch data fetcher, which uses a loader from the java-dataloader library, one per such method per request. The engine dispatches a level's loaders once the fields of that level have been fetched. The mechanism differs, and the observable result is the same: one call per loader per batch. graphql-java holds a level's dispatch until the whole level above has completed, so on Quarkus the voyages also wait for the delivery batch. Strawberry has no such barrier.

Figure 13.3 is drawn from one real run of the four-cargo query on the Python stack, from the source-call log at `/debug/source-calls`. The thin ticks are the `load` calls queued before each dispatch. The bars are the bulk calls, and each starts as the call its keys come from ends. The lower lane is not measured. It places Chapter 12's four `getCargo` calls at the cargo level's interval: they ran together too, so the wall time was the same, but each was a call to the booking service.

{% include excalidraw.html file="13-dataloader-tick" alt="The timeline spans zero to one thousand milliseconds in four lanes and a lower comparison lane. The call listCargos runs from zero to about 250. getCargos with four keys runs from 250 to 500, preceded by four thin ticks. getItineraries and listEventsFor, each with four keys, run together from 500 to 750, preceded by eight and four ticks. getVoyages with three keys and getLocations with five keys run together from 750 to 1000, preceded by four and eight ticks. The lower lane shows four dashed getCargo bars for Chapter 12, placed over the cargo level's 250 to 500 interval and not measured." caption="Figure 13.3 — One request on the Python stack, from its source-call log. Loads queue during a tick, one bulk call follows, and the next level starts when it returns." %}

`verify.sh` asserts the order and the overlap from the log and never a duration. On both stacks `listCargos` ends before `getCargos` starts, `getCargos` ends before `listEventsFor` starts, and `getVoyages` overlaps the location call or calls. On Quarkus `listEventsFor` also ends before `getVoyages` starts, the level barrier. On Python `getItineraries` ends before `getVoyages` starts, and `getItineraries` overlaps `listEventsFor`. All of it sits under one request id.

## Batching on SmallRye

A SmallRye field resolver that takes `@Source Leg` is called once per leg. Change the parameter to `@Source List<Leg>` and SmallRye calls it once per level with all the legs the level collected, and the method returns one value per leg in the same order. The batch resolver for `Leg.voyage`, next to the Python resolver that uses a loader:

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Description("The voyage that carries this leg. Null when the voyage service is unavailable.")
public Uni<List<Voyage>> voyage(@Source List<Leg> legs, Context context) {
    return voyages.getVoyages(context.getExecutionId(), legs.stream().map(Leg::voyageNumber).toList())
            .map(Outcome::values);
}
```

```python
@strawberry.field(
    description="The voyage that carries this leg. Null when the voyage service is unavailable."
)
async def voyage(self, info: Info[TrackingContext]) -> Voyage | None:
    return await info.context.loaders.voyage.load(self.voyage_number)
```

The Quarkus method is the whole implementation. There is no loader to declare or register; the batching is the `List` in the signature. Three details were checked on the pinned versions. A batch method may return `Uni<List<T>>`, and the field keeps type `T`. It accepts the SmallRye `Context`, and `getExecutionId()` read at entry is the request's id, the same one every other resolver sees. And `@NonNull` on a batch method makes the field non-null, not the list: `loadLocation` is still `Location!`. The conformance check confirms that no batch method changed the schema.

The two aliases of Chapter 7, `a: voyage` and `b: voyage` on the same leg, ask the same loader for the same leg. The loader's cache key is the source object, `Leg` is a record with value equality, and the two loads become one. The log shows one `getVoyages` call, `V100S+V200E`, where Chapter 7 counted four.

`Query.nodes` is the exception. A root field has no parents for the engine to collect, so there is nothing to batch with `@Source`. It groups its own ids by prefix and calls one bulk operation per type: five ids make three calls, `booking.getCargos` for `ABC123+XYZ789`, `location.getLocations` for `DEHAM+NLRTM` and `voyage.getVoyages` for `V100S`, down from five. The order of the answer is the order of the ids, and an unknown id is null at its position. Chapter 10's list with `cargo_ABC123` twice costs three calls instead of four: the duplicate travels once. Events have no bulk read, so each `evt_` id is still its own `getEvent` call.

## DataLoaders on Strawberry

Strawberry's `DataLoader` is built from a function, so the example builds five of them, one per kind of key, in `app/loaders.py`. The Quarkus tab is the bulk source operation the batch method calls; the Python tab is the load function over the same operation, inside `Loaders.for_request`, and the loader that wraps it:

{% include codetabs.html langs="Quarkus|Python" %}

```java
public Uni<List<Outcome<Voyage>>> getVoyages(String request, List<String> numbers) {
    return calls.callBatch(request, "voyage", "getVoyages", numbers, data::voyage);
}
```

```python
class Loaders:
    ...

    @classmethod
    def for_request(
        cls,
        booking: BookingSource,
        routing: RoutingSource,
        voyage: VoyageSource,
        location: LocationSource,
        handling: HandlingSource,
    ) -> Loaders:
        ...

        async def load_voyages(keys: list[str]) -> list[Voyage | None | Exception]:
            return _in_key_order(await voyage.get_voyages(keys))

        ...

        return cls(
            ...
            voyage=DataLoader(load_fn=load_voyages),
            ...
        )
```

The loaders are created per request in the context getter, which FastAPI calls once for each request:

```python
return TrackingContext(
    request_id,
    booking,
    routing,
    voyage,
    location,
    handling,
    _DERIVATION,
    Loaders.for_request(booking, routing, voyage, location, handling),
)
```

Because the loaders hang off the request's context, they cannot be shared between requests by accident. A loader at module level would be shared by every request, its cache would outlive them, and a handling event registered in one request would stay invisible to the next. The request-scope case in `verify.sh` runs the same query twice and finds two request ids, each with its own full set of calls: 6 and 6 on Python, 8 and 8 on Quarkus, nothing carried over.

The bulk operations on both stacks answer one outcome per key. The Python source returns an `Outcome` with a value or an error, and the loader function turns each into the value or the exception instance at that key's position. Strawberry then fails only the `load` of a key whose slot holds an exception. It raises `WrongNumberOfResultsReturned` if the function returns a list of the wrong length, which is the contract's first rule enforced.

## Per field versus per key

The two stacks disagree on one count, and the disagreement is structural. Quarkus makes 8 calls for the four-cargo query and Python makes 6.

SmallRye has one loader per batch method, keyed by the parent object. `Leg.loadLocation` and `Leg.unloadLocation` are two methods, so they have two loaders, and each makes its own `getLocations` call: `DEHAM+SGSIN+USNYC` for the load side and `CNSHA+DEHAM+NLRTM` for the unload side. `DEHAM` travels in both. For the same reason `Cargo.itinerary` and `Cargo.delivery` each have a loader and each call `getItineraries` with the same four cargos. That is the two extra calls.

Strawberry's loaders are keyed by the value that identifies the thing, a UN/LOCODE or a tracking id, and any field that wants a location uses the one location loader. `loadLocation` and `unloadLocation` share it, so `DEHAM` is one key loaded once, and the single call carries all five codes. `Cargo.itinerary` and `Cargo.delivery` share the itinerary loader. The same applies to Chapter 7's pair, an itinerary and a delivery on one cargo: one routing call on Python and two on Quarkus.

{% include excalidraw.html file="13-per-field-vs-per-key" alt="Two panels compare the stacks. On the left, SmallRye gives Leg.loadLocation and Leg.unloadLocation each a loader keyed by Leg, and each makes its own getLocations call, one for DEHAM, SGSIN and USNYC and one for CNSHA, DEHAM and NLRTM. A note says DEHAM travels in both calls, two calls in total. On the right, Strawberry has both fields use one location loader keyed by code, and a single getLocations call carries CNSHA, DEHAM, NLRTM, SGSIN and USNYC. A note says one call in total." caption="Figure 13.4 — The same fields on both stacks: one loader per field keyed by the parent on SmallRye, one loader per kind of key on Strawberry." %}

Both counts are fixed by the shape of the query and do not grow with the page. The Quarkus difference is the price of using the framework's own batching, one loader per batch method. It is a constant, not a multiplier, and the N+1 is gone. Sharing one loader across fields would mean a hand-built request-scoped cache, which the example leaves out. Chapter 16 covers caching at the request and response level. The example accepts the two extra calls and shows them.

## Where batching sits

Batching only helps if the owner can answer in bulk. Each source in the example gained a bulk operation next to its single-key one: `getCargos`, `getItineraries`, `getVoyages`, `getLocations` and `listEventsFor`. A bulk operation takes a list of keys and returns one outcome per key, in order: the value, null for an unknown key, or the failure that key alone hit. The log records the call once, under the sorted distinct keys joined with `+`, so `V100S+V200E+V300A` is one call for three voyages.

The single-key operations stay for the places that have only one key: `Query.cargo`, `Query.voyage`, `Query.location`, `Query.node` and the mutation. No resolver below a list calls them, and the case that counts Q_FAN asserts it: zero `getCargo`, `getItinerary`, `listEvents`, `getVoyage` and `getLocation` calls.

An owner may cap how many keys one call accepts. Strawberry's `DataLoader` takes a `max_batch_size` that splits a large batch into several calls, and a bulk operation behind a service with such a cap should set it. The example's sources have no cap and the example does not set one.

The history fan-out of Chapter 1 shows the same rule on a different shape. Seven events of `DEF456`, each with a location and, for four of them, a voyage, cost 7 + 4 calls in Chapter 12. Now they cost one `getLocations` call for `DEHAM+NLRTM+USNYC` and one `getVoyages` call for `V100S+V200E`, on both stacks. The three events without a voyage never reach the voyage service, so the resolver asks only for the keys it has. The same holds for Chapter 1's twenty-four locations, a cargo with six legs and twelve events resolved one at a time. The count follows the fields of the selection, not the number of legs and events: asking `DEF456` for its legs' load and unload locations and its history's event locations, eleven lookups before batching, makes three `getLocations` calls on Quarkus, one per location field, and one on Python. Each event's `cargo` batches the same way: seven events of `DEF456` make one `getCargos` call.

## A failing key in a batch

`GHI345` is the cargo the booking service lists and cannot load. That makes it the test of the contract's third rule. `cargos(last: 2)` returns the last page, `ABC123` and `GHI345`, and the two nodes load in one `getCargos` call with `ABC123+GHI345`. What happens next differs by stack, and Figure 13.5 shows both.

On Strawberry, the loader function returns `[Cargo ABC123, SourceUnavailable]`, with the exception instance at `GHI345`'s position. Only that key fails. The response has one execution error (older editions of the specification call it a field error), with the path `["cargos","edges",1,"node"]`, the code `SERVICE_UNAVAILABLE` and the message `booking service unavailable`. Edge 0 resolves as `ABC123`, and the failed edge's node is null: Chapter 12's fuse, now behind a batch.

On Quarkus, a batch method returns one list, so a failure is the failure of the whole `Uni`. `Outcome.values` throws the first failure and every parent in the batch gets it. The response has two errors, one at each edge's `node` path, both with the code `SERVICE_UNAVAILABLE`, and both nodes are null, `ABC123`'s included.

{% include excalidraw.html file="13-batch-blast-radius" alt="Two panels show a bulk getCargos call for ABC123 and GHI345 in which GHI345 fails. On the left, Strawberry returns the cargo ABC123 and a SourceUnavailable exception in the second position, so edge 0 resolves and edge 1's node is null, with one error at the path cargos, edges, 1, node. On the right, SmallRye resolves the batch as one result, so both edges' nodes are null, with two errors, one per path, both with the code SERVICE_UNAVAILABLE." caption="Figure 13.5 — One failing key in a batch: one null node on Strawberry, every node in the batch on SmallRye." %}

The example keeps the Quarkus behaviour as it is. The two outcomes follow from how each stack resolves a batch, and the choice they imply is where failures should be caught. A source whose keys can fail on their own, and whose clients need the other keys, should handle that inside the batch method or give the field a type that can hold a failure. The error codes themselves are Chapter 9's, and the null that stops at `node` is Chapter 12's. Chapter 6 and Chapter 9 cover the HTTP status that carries either response.

## Scope: one request

Everything here lives and dies with a request. The cache inside each loader makes a repeated key within one request free, and it is dropped with the request. That is why the handling write case passes: `registerHandlingEvent` for an unload of `ABC123` at `DEHAM` returns `evt_10`, the payload's `delivery.transportStatus` is `IN_PORT`, and a separate query a moment later says the same.

A cache that spans requests is a different tool with different obligations: expiry, invalidation when a write lands, and keys that include who is asking. Chapter 16 builds caching at the request and response levels and deals with those. A DataLoader is not the place to start.

## On the wire

Start the stack. Quarkus is on `8230` and Python on `8231`, and compose sets `TRACKING_SOURCE_LATENCY_MS=250` and `TRACKING_DEBUG_ENDPOINTS=true`.

```bash
docker compose -f examples/13-dataloaders/compose.yaml up -d --build
Q() {
  curl -s localhost:${2:-8230}/graphql -H 'Content-Type: application/json' \
    -d "$(python3 -I -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"; echo
}
LOG() {
  curl -s localhost:${1:-8230}/debug/source-calls | python3 -I -c 'import json,sys
for c in json.load(sys.stdin)["calls"]: print("%s.%s:%s" % (c["source"], c["op"], c["key"]))'
}
```

Reset the log, send the four-cargo query to the Python stack and read the log:

```bash
curl -s -X DELETE localhost:8231/debug/source-calls
Q '{ cargos(first: 4) { edges { node { trackingId itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } } delivery { transportStatus } } } } }' 8231 >/dev/null
LOG 8231
```

```text
booking.listCargos:*
booking.getCargos:DEF456+STU678+VWX901+XYZ789
routing.getItineraries:DEF456+STU678+VWX901+XYZ789
handling.listEventsFor:DEF456+STU678+VWX901+XYZ789
voyage.getVoyages:V100S+V200E+V300A
location.getLocations:CNSHA+DEHAM+NLRTM+SGSIN+USNYC
```

Quarkus logs eight calls for the same request, with the itinerary key and the two location keys twice:

```text
booking.listCargos:*
booking.getCargos:DEF456+STU678+VWX901+XYZ789
routing.getItineraries:DEF456+STU678+VWX901+XYZ789
handling.listEventsFor:DEF456+STU678+VWX901+XYZ789
routing.getItineraries:DEF456+STU678+VWX901+XYZ789
location.getLocations:DEHAM+SGSIN+USNYC
voyage.getVoyages:V100S+V200E+V300A
location.getLocations:CNSHA+DEHAM+NLRTM
```

The `nodes` fan-out, five ids and three calls:

```bash
curl -s -X DELETE localhost:8231/debug/source-calls
Q '{ nodes(ids: ["cargo_ABC123", "cargo_XYZ789", "loc_DEHAM", "loc_NLRTM", "voy_V100S"]) { __typename id } }' 8231
LOG 8231
```

```text
{"data":{"nodes":[{"__typename":"Cargo","id":"cargo_ABC123"},{"__typename":"Cargo","id":"cargo_XYZ789"},{"__typename":"Location","id":"loc_DEHAM"},{"__typename":"Location","id":"loc_NLRTM"},{"__typename":"Voyage","id":"voy_V100S"}]}}
booking.getCargos:ABC123+XYZ789
location.getLocations:DEHAM+NLRTM
voyage.getVoyages:V100S
```

The failing key, as each stack answers it. Quarkus:

```bash
Q '{ cargos(last: 2) { edges { node { trackingId } } } }' 8230
```

```json
{"errors":[{"message":"booking service unavailable","locations":[{"line":1,"column":29}],"path":["cargos","edges",0,"node"],"extensions":{"code":"SERVICE_UNAVAILABLE"}},{"message":"booking service unavailable","locations":[{"line":1,"column":29}],"path":["cargos","edges",1,"node"],"extensions":{"code":"SERVICE_UNAVAILABLE"}}],"data":{"cargos":{"edges":[{"node":null},{"node":null}]}}}
```

Python:

```bash
Q '{ cargos(last: 2) { edges { node { trackingId } } } }' 8231
```

```json
{"data":{"cargos":{"edges":[{"node":{"trackingId":"ABC123"}},{"node":null}]}},"errors":[{"message":"booking service unavailable","locations":[{"line":1,"column":29}],"path":["cargos","edges",1,"node"],"extensions":{"code":"SERVICE_UNAVAILABLE"}}]}
```

Stop the stack and remove its state when done:

```bash
docker compose -f examples/13-dataloaders/compose.yaml down -v
```

Timestamps and column numbers can differ by stack. The keys, counts, paths and codes do not, except where the table says so.

| Check | Quarkus | Python |
|---|---|---|
| first cursor of `cargos(first: 2)` | base64url of `cargo\|v1\|2026-09-29T09:00:00Z\|VWX901` | the same |
| four-cargo query | `VWX901`, `XYZ789`, `STU678`, `DEF456`; 8 calls | the same data; 6 calls |
| bulk keys | `getCargos` and `listEventsFor` `DEF456+STU678+VWX901+XYZ789`; `getVoyages` `V100S+V200E+V300A`; `getItineraries` that key twice; `getLocations` `DEHAM+SGSIN+USNYC` and `CNSHA+DEHAM+NLRTM` | the same four keys; `getItineraries` once; `getLocations` `CNSHA+DEHAM+NLRTM+SGSIN+USNYC` once |
| single-key fan-out | 0 `getCargo`, `getItinerary`, `listEvents`, `getVoyage`, `getLocation` | the same |
| page size | two and five cargos make the same total as four | the same |
| order | `listCargos` before `getCargos` before `listEventsFor` before `getVoyages`; voyage and both location calls overlap; one request id | `listCargos` before `getCargos` before `listEventsFor`; `getItineraries` before `getVoyages`; `getItineraries` overlaps `listEventsFor`; `getVoyages` overlaps the location call |
| alias pair | one `getVoyages` call, `V100S+V200E`; all four aliases carry their voyage | the same |
| itinerary and delivery | 2 `getItineraries` calls, `ABC123` each | 1 |
| `DEF456` history, `first: 7` | one `getLocations` `DEHAM+NLRTM+USNYC`, one `getVoyages` `V100S+V200E`, plus `pageEvents` and the root `getCargo`; voyages `null,null,V200E,V200E,V100S,V100S,null` | the same |
| `nodes`, five ids | types and ids in the order asked; three calls | the same |
| `nodes` with `cargo_ABC123` twice and `nope` | `[Cargo, Location, null, Voyage, Cargo]` by position; three calls: `getCargos` `ABC123`, `getLocations` `NLRTM`, `getVoyages` `V200E` (Chapter 10: four) | the same |
| history, each event's `cargo` | `getCargo` `DEF456`, `pageEvents` `DEF456`, one `getCargos` `DEF456` | the same |
| `DEF456` legs' locations and history locations | three `getLocations` calls, one per location field | one `getLocations` call |
| two requests | two request ids; 16 calls, 8 each | 12 calls, 6 each |
| `voyage(voyageNumber: "V999X")` | null, no error, one `getVoyage` `V999X` | the same |
| `nodes(ids: ["voy_V999X", "voy_V100S"])` | `[null, {Voyage V100S}]`; one `getVoyages` `V100S+V999X` | the same |
| `cargos(last: 2)` | `listCargos`, one `getCargos` `ABC123+GHI345`; 2 errors at `edges.0.node` and `edges.1.node`, both `SERVICE_UNAVAILABLE`; both nodes null | the same two calls; 1 error at `edges.1.node`, `SERVICE_UNAVAILABLE`, `booking service unavailable`; node 0 is `ABC123` |
| unload of `ABC123` at `DEHAM` on `V100S`, `2026-10-09T15:00:00Z` | `evt_10`; payload and fresh query say `IN_PORT` | the same |
| deprecation and schema | `finalArrivalDate` deprecated with ``Use `finalArrivalTime`.``; conforms to `contracts/schema/`; only `Subscription` is unserved | the same |

`bash examples/13-dataloaders/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Batching is where the <em>aggregation across sources</em> axis of Chapter 2 pays its bill: a graph that joins many owners must fetch from each in bulk, or every list multiplies every owner's load. The <em>operational and security cost</em> axis decides the scope and the limits: a loader belongs to one request, a bulk operation takes a bounded list of keys, and a batch that mixes keys from different clients must not leak between them, which is why nothing here outlives a request. The <em>contract and evolution style</em> axis is untouched, because batching changed no field, argument or nullability. The tracking view therefore batches every source-backed field under a list, with <code>@Source List</code> resolvers on SmallRye and per-request DataLoaders on Strawberry, accepts the two extra calls that per-field loaders cost on Quarkus, and leaves caching across requests to Chapter 16.</p></div>

## Where this goes next

This chapter counted 29 source calls for a four-cargo page and brought them to 8 on Quarkus and 6 on Python: bulk source operations, one loader per field on SmallRye and one per kind of key on Strawberry, a tick that collects a level's keys, a missing key as a null, per-request scope, and a failing key that costs one node on one stack and the whole batch on the other.

Chapter 14 treats the page size and the selection depth as inputs to query cost. Batching bounds the number of calls a selection makes, and cost analysis bounds the selection itself.

For the batching rules, read the [graphql-java documentation on batching](https://www.graphql-java.com/documentation/batching/) and the java-dataloader project it builds on, and the Strawberry guide to [DataLoaders](https://strawberry.rocks/docs/guides/dataloaders). The SmallRye side is in the Quarkus [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) and the [SmallRye GraphQL documentation](https://smallrye.io/smallrye-graphql/). Samer Buna's *GraphQL in Action* covers caching and batching with DataLoader in "Optimizing data fetching". Martin Kleppmann and Chris Riccomini's *Designing Data-Intensive Applications*, 2nd edition, covers the cost of fanning one request out to many backend calls. Both books are on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- [graphql-java — documentation on batching](https://www.graphql-java.com/documentation/batching/) and the java-dataloader project it builds on.
- [Strawberry — DataLoaders guide](https://strawberry.rocks/docs/guides/dataloaders).
- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd ed. (O'Reilly, 2026) — tail latency amplification, why a request is as slow as its slowest backend call.
- Samer Buna, *GraphQL in Action* (Manning, 2021) — caching and batching with DataLoader, in "Optimizing data fetching."
- *Cloud Native Design Patterns*, "Composition" — batching by owner as the general form of aggregation across sources.
