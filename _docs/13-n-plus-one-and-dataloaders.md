---
title: "The N+1 problem and DataLoaders"
order: 13
part: "Data Fetching at Scale"
description: "Counting the source calls a four-cargo page costs, batching them one call per owner, the DataLoader contract and its tick, SmallRye @Source List batch resolvers against Strawberry DataLoaders, per-field against per-key loaders, and what one failing key does to its batch."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Count an N+1 fan-out field by field, from one `listCargos` call to 29 source calls for a four-cargo page.
- Batch per-field resolvers into one bulk call per owner per level using `@Source List<...>` on Quarkus and a `DataLoader` on Python.
- Apply the DataLoader contract: keys in, values out in the same order, missing keys as null, failures per key, cache scoped to one request.
- Explain why SmallRye's per-method loaders cost more calls (8) than Strawberry's per-key loaders (6) for the same query.
- Scope a loader's cache to a single request so a write like `registerHandlingEvent` is never served stale data by a stale cache.

## Why this matters

A page of four cargos, each with its itinerary legs, their voyages and locations, and its delivery status, costs 29 source calls. Nothing in that query is unusual. Batching brings it to 8 on Quarkus and 6 on Python without changing a field of the schema.

Every source gains a bulk operation next to its single-key one. SmallRye batches with `@Source List<...>` resolvers, and Strawberry batches with DataLoaders built once per request.

## Counting the N+1

The name comes from databases: one query for a list, then one more for each of its N rows. A GraphQL server does the same by construction. A resolver is called once per field occurrence, so a field under a list is called once per item, and each call that reads a source is a round trip.

```graphql
{ cargos(first: 4) { edges { node { trackingId
    itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } }
    delivery { transportStatus } } } } }
```

Figure 13.1 counts the calls field by field. The page is one `listCargos` call. Each edge's `node` loads its cargo: four calls. The itinerary and the delivery both read the routing source, so four cargos make eight `getItinerary` calls, and each delivery also reads its events: four more. The four cargos have one, none, one and two legs, which makes four legs with a voyage and two locations each: four `getVoyage` calls and eight `getLocation` calls. The total is 1 + 4 + 8 + 4 + 4 + 8 = 29.

{% include excalidraw.html file="13-n-plus-one-fanout" alt="The tree reads from left to right. The field cargos(first: 4) calls listCargos once. Its CargoEdge.node field calls getCargo four times. Cargo.itinerary calls getItinerary four times, and Cargo.delivery calls getItinerary four times and listEvents four times. Below the itinerary, Leg.voyage calls getVoyage four times with the keys V300A, V300A, V100S and V200E, Leg.loadLocation calls getLocation four times with SGSIN, SGSIN, USNYC and DEHAM, and Leg.unloadLocation calls getLocation four times with CNSHA, CNSHA, DEHAM and NLRTM. The repeated keys are highlighted: V300A, SGSIN and CNSHA twice each, DEHAM once on each side, and every cargo's itinerary twice." caption="Figure 13.1: The four-cargo query before batching: one call per field occurrence, 29 in all. The highlighted keys are fetched more than once in one request." %}

Several of those calls ask for the same thing. `V300A` is fetched twice because two cargos share a route, and every cargo's itinerary is fetched twice because two fields need it. A cargo with six legs and twelve events resolves twenty-four locations one at a time. The cost grows with the data, and the client controls the data.

## Pattern: DataLoader batching

### The problem

A resolver runs once per field occurrence, so a list of N items multiplies every source behind its fields by N, and the same key is fetched again wherever two fields want it.

### The solution

**A DataLoader collects the keys asked for during one tick of execution, makes one bulk call per owner for all of them, and hands each caller the value at its key's position.**

A field's resolver runs only after its parent has resolved, and siblings run together, so the fields that want the same owner ask at about the same moment. One call per owner replaces one call per field.

Figure 13.2 shows the result for the same query. The page is still one call. The four cargos load in one `getCargos` call, their itineraries and events in one `getItineraries` and one `listEventsFor`, the voyages in one `getVoyages`, and the locations in one `getLocations`. A call waits for the call its keys come from, and calls whose keys come from the same place run together.

{% include excalidraw.html file="13-batched-load" alt="The same tree appears with one bulk call per level on the Python stack. The call listCargos is followed by getCargos with four keys. From it, the calls getItineraries with four keys and listEventsFor with four keys. From getItineraries, getVoyages with the keys V100S, V200E and V300A, and getLocations with the keys CNSHA, DEHAM, NLRTM, SGSIN and USNYC. A note says Quarkus makes eight calls for the same query." caption="Figure 13.2: The same query with one bulk call per level: six calls on Python. Quarkus makes eight, for a reason Figure 13.4 shows." %}

The number of calls now follows the number of fields in the selection, not the number of cargos: two cargos and five cargos with the same selection make the same totals as four. Kleppmann and Riccomini show in *Designing Data-Intensive Applications*, 2nd edition, how a request that makes several backend calls is as slow as the slowest of them (tail latency amplification). Batching cuts the number of calls each request waits on.

### The contract

The idea was developed at Facebook in 2010 for batching reads from key-value back ends, before GraphQL, and published in 2015 as the JavaScript `dataloader` library. Its contract is small:

- **Keys in, values out, same order.** The loader function receives a list of keys and returns a list of values of the same length, in the same order.
- **Not found is a value.** An unknown key gets `null` at its position. `nodes(ids: ["voy_V999X", "voy_V100S"])` returns `[null, {Voyage V100S}]` with no error, and one `getVoyages` call carries both keys.
- **Failure can be per key.** A key's slot may hold a failure instead of a value. Whether that spares the other keys depends on the implementation, covered below.
- **Keys are deduplicated and cached within a request.** Asking for the same key twice costs one lookup. The cache lives as long as the loader and no longer.

The last rule is the safety rule. A cache that outlives a request serves stale data to the next one, and the handling store changes between requests. A loader belongs to one request: created when it starts, dropped when it ends. After `registerHandlingEvent` for an unload of `ABC123` at `DEHAM`, the mutation's payload and a fresh query both report `IN_PORT`.

### The tick

A loader has to decide when to stop collecting keys and make the call. Each stack answers with a tick: a point in execution when every field that is going to ask at this level has already asked.

On Strawberry the tick is the event loop's next turn. `DataLoader.load` returns a future and, for the first key of a new batch, schedules the dispatch with `loop.call_soon`. Every resolver that runs before the loop's next turn adds its key to the same batch, and the loader function is called once with the distinct keys.

On Quarkus the tick belongs to graphql-java. SmallRye turns a resolver with a `@Source List<...>` parameter into a batch data fetcher backed by a loader from the java-dataloader library, one per such method per request. The engine dispatches a level's loaders once the fields of that level have been fetched. graphql-java holds a level's dispatch until the whole level above has completed, so on Quarkus the voyages also wait for the delivery batch. Strawberry has no such barrier.

{% include excalidraw.html file="13-dataloader-tick" alt="The timeline spans zero to one thousand milliseconds in four lanes and a lower comparison lane. The call listCargos runs from zero to about 250. getCargos with four keys runs from 250 to 500, preceded by four thin ticks. getItineraries and listEventsFor, each with four keys, run together from 500 to 750, preceded by eight and four ticks. getVoyages with three keys and getLocations with five keys run together from 750 to 1000, preceded by four and eight ticks. The lower lane shows four dashed getCargo bars from the earlier pagination example, placed over the cargo level's 250 to 500 interval and not measured." caption="Figure 13.3: One request on the Python stack, from its source-call log. Loads queue during a tick, one bulk call follows, and the next level starts when it returns." %}

### How Quarkus and Python model it

A SmallRye field resolver that takes `@Source Leg` is called once per leg. Change the parameter to `@Source List<Leg>` and SmallRye calls it once per level with all the legs the level collected; the method returns one value per leg in the same order.

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

The Quarkus method is the whole implementation: no loader to declare or register, because the batching is the `List` in the signature. A batch method may return `Uni<List<T>>` and the field keeps type `T`. It accepts the SmallRye `Context`, and `getExecutionId()` is the request's id. `@NonNull` on a batch method makes the field non-null, not the list, so `loadLocation` is still `Location!`.

Two aliases on the same leg, `a: voyage` and `b: voyage`, ask the same loader for the same leg. The cache key is the source object, `Leg` is a record with value equality, and the two loads become one `getVoyages` call, `V100S+V200E`, where unbatched resolvers counted four.

`Query.nodes` is the exception. A root field has no parents for the engine to collect, so there is nothing to batch with `@Source`. It groups its own ids by prefix and calls one bulk operation per type: five ids make three calls, `booking.getCargos` for `ABC123+XYZ789`, `location.getLocations` for `DEHAM+NLRTM` and `voyage.getVoyages` for `V100S`. The answer keeps the order of the ids, and an unknown id is null at its position. Events have no bulk read, so each `evt_` id is still its own `getEvent` call.

Strawberry's `DataLoader` is built from a function, so `app/loaders.py` builds five, one per kind of key. The Quarkus tab is the bulk source operation the batch method calls. The Python tab is `Loaders`, whose `for_request` wraps each bulk operation in a load function and a `DataLoader`:

{% include codetabs.html langs="Quarkus|Python" %}

```java
    public Uni<List<Outcome<Voyage>>> getVoyages(String request, List<String> numbers) {
        return calls.callBatch(request, "voyage", "getVoyages", numbers, data::voyage);
    }
```

```python
@dataclass(frozen=True, slots=True)
class Loaders:
    cargo: DataLoader[str, Cargo | None]
    itinerary: DataLoader[str, Itinerary | None]
    events: DataLoader[str, list[HandlingRecord]]
    voyage: DataLoader[str, Voyage | None]
    location: DataLoader[str, Location | None]

    @classmethod
    def for_request(
        cls,
        booking: BookingSource,
        routing: RoutingSource,
        voyage: VoyageSource,
        location: LocationSource,
        handling: HandlingSource,
    ) -> Loaders:
        """New loaders over this request's sources."""

        async def load_cargos(keys: list[str]) -> list[Cargo | None | Exception]:
            return _in_key_order(await booking.get_cargos(keys))

        async def load_itineraries(keys: list[str]) -> list[Itinerary | None | Exception]:
            return _in_key_order(await routing.get_itineraries(keys))

        async def load_events(keys: list[str]) -> list[list[HandlingRecord] | None | Exception]:
            return _in_key_order(await handling.list_events_for(keys))

        async def load_voyages(keys: list[str]) -> list[Voyage | None | Exception]:
            return _in_key_order(await voyage.get_voyages(keys))

        async def load_locations(keys: list[str]) -> list[Location | None | Exception]:
            return _in_key_order(await location.get_locations(keys))

        return cls(
            cargo=DataLoader(load_fn=load_cargos),
            itinerary=DataLoader(load_fn=load_itineraries),
            events=DataLoader(load_fn=load_events),
            voyage=DataLoader(load_fn=load_voyages),
            location=DataLoader(load_fn=load_locations),
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

Because the loaders hang off the request's context, they can't be shared between requests by accident. A loader at module level would be shared by every request, its cache would outlive them, and a handling event registered in one request would stay invisible to the next.

The bulk operations on both stacks answer one outcome per key. The Python source returns an `Outcome` with a value or an error, and the loader function turns each into the value or the exception instance at that key's position. Strawberry then fails only the `load` of a key whose slot holds an exception, and raises `WrongNumberOfResultsReturned` if the function returns a list of the wrong length.

## Per field versus per key

The stacks disagree on one count, and the disagreement is structural: Quarkus makes 8 calls for the four-cargo query and Python makes 6.

| | SmallRye | Strawberry |
|---|---|---|
| Loader keyed by | the parent object, one loader per batch method | the identifying value (a UN/LOCODE, a tracking id), one loader per kind of key |
| `loadLocation` and `unloadLocation` | two loaders, two `getLocations` calls, `DEHAM+SGSIN+USNYC` and `CNSHA+DEHAM+NLRTM`; `DEHAM` travels in both | one location loader, one call with all five codes |
| `Cargo.itinerary` and `Cargo.delivery` | two loaders, two `getItineraries` calls with the same four cargos | one shared itinerary loader |
| Calls for the four-cargo query | 8 | 6 |

{% include excalidraw.html file="13-per-field-vs-per-key" alt="Two panels compare the stacks. On the left, SmallRye gives Leg.loadLocation and Leg.unloadLocation each a loader keyed by Leg, and each makes its own getLocations call, one for DEHAM, SGSIN and USNYC and one for CNSHA, DEHAM and NLRTM. A note says DEHAM travels in both calls, two calls in total. On the right, Strawberry has both fields use one location loader keyed by code, and a single getLocations call carries CNSHA, DEHAM, NLRTM, SGSIN and USNYC. A note says one call in total." caption="Figure 13.4: The same fields on both stacks: one loader per field keyed by the parent on SmallRye, one loader per kind of key on Strawberry." %}

Both counts are fixed by the shape of the query and don't grow with the page. The two extra Quarkus calls are the price of the framework's own batching, one loader per batch method: a constant, not a multiplier. Sharing one loader across fields would mean a hand-built request-scoped cache.

## Where batching sits

Batching only helps if the owner can answer in bulk. Each source gained a bulk operation next to its single-key one: `getCargos`, `getItineraries`, `getVoyages`, `getLocations` and `listEventsFor`. A bulk operation takes a list of keys and returns one outcome per key, in order: the value, null for an unknown key, or the failure that key alone hit. The source-call log records the call once, under the sorted distinct keys joined with `+`.

The single-key operations stay for places that have only one key: `Query.cargo`, `Query.voyage`, `Query.location`, `Query.node` and the mutation. No resolver below a list calls them.

An owner may cap how many keys one call accepts. Strawberry's `DataLoader` takes a `max_batch_size` that splits a large batch into several calls; a bulk operation behind a service with such a cap should set it. The sources here have no cap.

The same rule fixes the history fan-out. Seven events of `DEF456`, each with a location and, for four of them, a voyage, cost 7 + 4 calls unbatched. Batched, they cost one `getLocations` call for `DEHAM+NLRTM+USNYC` and one `getVoyages` call for `V100S+V200E`. The three events without a voyage never reach the voyage service, because the resolver asks only for the keys it has. Each event's `cargo` batches the same way: one `getCargos` call.

## A failing key in a batch

`GHI345` is the cargo the booking service lists and can't load, which tests the contract's third rule. `cargos(last: 2)` returns `ABC123` and `GHI345`, and the two nodes load in one `getCargos` call with `ABC123+GHI345`.

On Strawberry, the loader function returns `[Cargo ABC123, SourceUnavailable]`, with the exception instance at `GHI345`'s position. Only that key fails: one error with the path `["cargos","edges",1,"node"]` and the code `SERVICE_UNAVAILABLE`, edge 0 resolves as `ABC123`, and the failed node is null.

On Quarkus, a batch method returns one list, so a failure is the failure of the whole `Uni`. `Outcome.values` throws the first failure and every parent in the batch gets it: two errors, one at each edge's `node` path, and both nodes null, `ABC123`'s included.

{% include excalidraw.html file="13-batch-blast-radius" alt="Two panels show a bulk getCargos call for ABC123 and GHI345 in which GHI345 fails. On the left, Strawberry returns the cargo ABC123 and a SourceUnavailable exception in the second position, so edge 0 resolves and edge 1's node is null, with one error at the path cargos, edges, 1, node. On the right, SmallRye resolves the batch as one result, so both edges' nodes are null, with two errors, one per path, both with the code SERVICE_UNAVAILABLE." caption="Figure 13.5: One failing key in a batch: one null node on Strawberry, every node in the batch on SmallRye." %}

The two outcomes follow from how each stack resolves a batch. A source whose keys can fail on their own, and whose clients need the other keys, should handle the failure inside the batch method or give the field a type that can hold a failure.

## Scope: one request

The cache inside each loader makes a repeated key within one request free, and it is dropped with the request. A cache that spans requests is a different tool with different obligations: expiry, invalidation when a write lands, and keys that include who is asking. A DataLoader is not the place to start.

> **🤖 Explore with your agent**
>
> "In examples/13-dataloaders, add `Leg.carrier: String` backed by a bulk `getCarriers` operation on a source, batched one call per owner per level: a `@Source List<Leg>` resolver on Quarkus and a request-scoped DataLoader built in `Loaders.for_request` on Python. Return one outcome per key in key order, with null for an unknown key."
>
> Check: reset `/debug/source-calls` on ports 8230 and 8231, run the four-cargo query with `carrier` selected, and confirm the log shows one `getCarriers` call whatever the page size.

## Build, run, observe

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

Timestamps and column numbers can differ by stack. The keys, counts, paths and codes don't.

`bash examples/13-dataloaders/verify.sh` runs the whole sequence on both stacks and prints `PASS` when both agree. It passes when the four-cargo query makes 8 calls on Quarkus and 6 on Python, no resolver below a list makes a single-key call, and the failing-key responses match the shapes above. Experiments:

- Select the same four-cargo page with two cargos and with five: the call totals stay the same as for four.
- Run the four-cargo query twice: two request ids, each with its full set of calls (16 on Quarkus, 12 on Python), nothing carried over.
- Query `nodes(ids: ["cargo_ABC123", "loc_NLRTM", "nope", "voy_V200E", "cargo_ABC123"])`: `[Cargo, Location, null, Voyage, Cargo]` by position, in three calls (`getCargos` `ABC123`, `getLocations` `NLRTM`, `getVoyages` `V200E`) where unbatched code made four.
- Query `voyage(voyageNumber: "V999X")`: null, no error, one `getVoyage` call for `V999X`.
- Ask `DEF456` for its legs' load and unload locations and its history's event locations: three `getLocations` calls on Quarkus, one per location field, and one on Python.

> **Decision**
>
> Batching is where the aggregation across sources axis of the decision framework pays its bill: a graph that joins many owners must fetch from each in bulk, or every list multiplies every owner's load. The operational and security cost axis decides the scope and the limits: a loader belongs to one request, a bulk operation takes a bounded list of keys, and a batch that mixes keys from different clients must not leak between them. Batching changes no field, argument or nullability, so the contract and evolution axis is untouched. The tracking view batches every source-backed field under a list, with `@Source List` resolvers on SmallRye and per-request DataLoaders on Strawberry, accepts the two extra calls that per-field loaders cost on Quarkus, and leaves caching across requests for later.

## For deeper coverage

- [graphql-java: documentation on batching](https://www.graphql-java.com/documentation/batching/) and the java-dataloader project it builds on.
- [Strawberry: DataLoaders guide](https://strawberry.rocks/docs/guides/dataloaders).
- Quarkus [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) and the [SmallRye GraphQL documentation](https://smallrye.io/smallrye-graphql/).
- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd ed. (O'Reilly, 2026): tail latency amplification, why a request is as slow as its slowest backend call. Listed on the [Bibliography](../../bibliography/) page.
- Samer Buna, *GraphQL in Action* (Manning, 2021): caching and batching with DataLoader, in "Optimizing data fetching."
- *Cloud Native Design Patterns*, "Composition": batching by owner as the general form of aggregation across sources.
