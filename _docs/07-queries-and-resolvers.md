---
title: "Queries and resolvers"
order: 7
part: "Execution: Resolvers, Queries & Mutations"
description: "What a resolver receives and returns, how a parent value becomes a child's argument and then a source key, how Delivery is derived from handling events, and how variables, aliases, fragments and @include and @skip change which sources a query calls."
duration: "13 min read"
---

## Learning objectives

By the end of this chapter you can:

- Trace how a resolver's four inputs (parent, arguments, context, and info) flow from `Query.cargo` through `Cargo.itinerary` and into a source call.
- Derive a computed field like `Cargo.delivery` from independent fetches run concurrently with `Uni.combine().all()` / `asyncio.gather`, instead of reading it from a stored source.
- Use variables, aliases, fragments, and `@include`/`@skip` to change which fields (and therefore which source calls) a document makes.
- Explain why `Context` holds request-scoped state like the execution id, and why it must never carry data shared across requests.
- Recognize the repeated-fetch smell where two selections of the same field (e.g. `Leg.voyage`) cost two source calls, as the problem DataLoader batching solves.

## Why this matters

A resolver is an ordinary function with four inputs and one output, and the cost of a GraphQL server comes from how those functions pass values to each other: the parent's data becomes the child's argument, and the argument becomes a key into a source.

The code is in `examples/07-queries-resolvers/`. It keeps asynchronous sources with 250 ms latency, a source-call log and a per-request id. A new `handling` source returns the events recorded for a cargo, and `Cargo.delivery` is computed from those events and the itinerary instead of read from a `delivery` source, which is removed.

## Anatomy of a resolver

Every resolver receives the same four inputs, spelled differently by each stack.

- **The parent** is the object the field is selected on. For a root field it is the root value and is usually ignored. For `Cargo.itinerary` it is the `Cargo` that `Query.cargo` returned.
- **The arguments** are the values written in the document for that field, after coercion. `Query.cargo` takes `trackingId`; `Cargo.itinerary` takes none.
- **The context** is state that belongs to the request, not to a field: here the request id and the sources.
- **The info** describes the field being resolved: its name, its path in the response, the fields selected beneath it and the schema.

{% include excalidraw.html file="07-resolver-anatomy" alt="Four boxes on the left, labelled parent, arguments, context and info, each showing the Java and Python spelling of that input. Arrows from the four boxes lead to a highlighted box in the middle, Cargo.itinerary, which reads the tracking id from the parent and calls routing.getItinerary. The parent arrow is amber and labelled ABC123. A final amber arrow labelled engine completes it leads to a box on the right, the return value, an Itinerary or null, as a Uni in Java or a coroutine in Python." caption="Figure 7.1: The four inputs of a resolver. Cargo.itinerary uses the parent, takes no arguments, and returns a value the engine completes." %}

On Quarkus the resolver is a method in the `@GraphQLApi` class. A method whose first parameter is annotated `@Source` is a field of that parent type, and a method annotated `@Query` is a root field. Plain parameters are arguments, named with `@Name`. The SmallRye `Context` is filled in by the engine and carries request and field information: `getExecutionId()`, `getFieldName()`, `getPath()` and `getSelectedFields()`. On Python a resolver is a method on the type, `self` is the parent, typed parameters are the arguments, and `info` carries the field details and the context the router's `context_getter` built.

{% include codetabs.html langs="Quarkus|Python" %}

```java
    @Description("The planned route. Null until the routing service has assigned one.")
    public Uni<Itinerary> itinerary(@Source Cargo cargo, Context context) {
        return routing.getItinerary(context.getExecutionId(), cargo.trackingId().value());
    }
```

```python
    @strawberry.field(
        description="The planned route. Null until the routing service has assigned one."
    )
    async def itinerary(self, info: Info[TrackingContext]) -> Itinerary | None:
        return await info.context.routing.get_itinerary(self.tracking_id)
```

A resolver returns a value, or something that becomes one (`Uni`, a coroutine), and the engine completes it against the declared type. Neither touches the response. The specification describes the same contract as `ResolveFieldValue(objectType, objectValue, fieldName, argumentValues)`; context and info are what each engine adds.

## Default resolvers

Most fields have no resolver of their own. `Cargo.description`, `Cargo.origin` and `Cargo.routeSpecification` come from the booking record that `Query.cargo` returned, and the engine reads them as properties of the parent: a record accessor on Quarkus, an attribute on Python.

```graphql
{ cargo(trackingId: "ABC123") { description } }
```

The log for this query is exactly `booking.getCargo:ABC123` on both stacks. The rule for placing a field is a question about who owns the data. If the booking record already carries it, leave it a property. If another service owns it, make it a resolver, as `Cargo.itinerary` is, and the cost becomes visible in the log.

## Root resolvers and arguments

The root fields are `cargo`, `location`, `voyage` and `node`. Each takes one argument, hands it to a source as the key, and returns `null` when the source has nothing, because the contract makes each result nullable. A lookup that finds nothing is an answer, not a failure.

```graphql
{ voyage(voyageNumber: "V999X") { number } }
```

Both stacks answer `{"data":{"voyage":null}}` with no `errors`, and so does `cargo(trackingId: "NOPE99")`. A client can tell "no such voyage" from "the voyage service failed", which arrives as an entry in `errors`.

`Query.node` dispatches on the prefix of the id, `cargo_`, `loc_` or `voy_`, and calls the matching source. A root resolver can choose among sources but still maps one argument to one key.

## The resolver chain

A query is a chain of such calls. Follow `cargo { itinerary { legs { voyage { number } } } }`.

{% include excalidraw.html file="07-resolver-chain" alt="A row of boxes from left to right. Query.cargo, highlighted, takes the argument trackingId ABC123 and calls booking.getCargo, drawn below it. It returns a Cargo box. An amber arrow labelled parent leads to Cargo.itinerary, highlighted, which calls routing.getItinerary for ABC123, drawn below it. It returns an Itinerary box with two legs. Two amber arrows labelled leg 0 and leg 1 lead to two highlighted resolvers, legs[0].voyage and legs[1].voyage, which call voyage.getVoyage for V100S and V200E in two source boxes to their right. Millisecond offsets from a real run appear under each source." caption="Figure 7.2: The resolver chain for one query. The parent value feeds the child resolver, the child derives a key from it, and the key goes to a source. The two voyage lookups start together." %}

`Query.cargo` passes `ABC123` to `booking.getCargo`. The `Cargo` that comes back is the parent of `itinerary`, which reads `trackingId` from it and calls `routing.getItinerary`. The `Itinerary` holds two `Leg` values, each with a voyage number, and the engine runs `Leg.voyage` once per list item with that leg as the parent. Each resolver gets its input from the one above it, and none knows about the one below. On Quarkus, 250 ms sources produced this log, with the request id shortened to its position:

```text
booking   getCargo      ABC123  start +   0  end + 254
routing   getItinerary  ABC123  start + 265  end + 516
voyage    getVoyage     V100S   start + 522  end + 773
voyage    getVoyage     V200E   start + 522  end + 776
```

The order is the dependency: the itinerary is the only place the voyage numbers exist, so no voyage call can start before it ends. The overlap is the list: items of one list are siblings. The query's latency is three levels of 250 ms, whatever the number of legs.

## Computed fields

`Delivery` is not a record any service stores. It is a view of three facts: what the customer asked for (the route specification), what routing planned (the itinerary) and what has happened (the handling events). The derived values for `ABC123` and `XYZ789` equal the constants served before. The derivation takes the last handling event, the one with the greatest completion time, and reads the state off it.

| Last event | `transportStatus` | `currentVoyage` | `nextExpectedActivity` |
|---|---|---|---|
| none | `NOT_RECEIVED` | none | `RECEIVE` at the route's origin |
| `RECEIVE` | `IN_PORT` | none | `LOAD` on the first leg |
| `LOAD` at L on V | `ONBOARD_CARRIER` | V | `UNLOAD` at the matching leg's end |
| `UNLOAD` at L on V | `IN_PORT` | none | `CLAIM` at L if L is the destination, else `LOAD` on the next leg |
| `CUSTOMS` | `IN_PORT` | none | none |
| `CLAIM` | `CLAIMED` | none | none |

`lastKnownLocation` is that event's location. `routingStatus` is `NOT_ROUTED` without an itinerary, `MISROUTED` when the first leg doesn't load at the origin or the last leg doesn't unload at the destination, and `ROUTED` otherwise. `misdirected` is true when the last load or unload matches no leg by location and voyage. `estimatedTimeOfArrival` is the itinerary's final arrival date only when the cargo is `ROUTED` and not misdirected. `ABC123` has a `RECEIVE` in New York and a `LOAD` on `V100S`, so it is `ONBOARD_CARRIER` on `V100S`, with an `UNLOAD` in Hamburg next. `XYZ789` has no events, so it is `NOT_RECEIVED` with a `RECEIVE` expected in Singapore.

The rules live in one class that takes plain values and calls no source: `DeliveryDerivation` on both stacks (`app/derivation.py` on Python). It can be tested without a request. The resolver is only the glue that fetches the inputs.

{% include codetabs.html langs="Quarkus|Python" %}

```java
    @NonNull
    @Description("Delivery status derived from handling history.")
    public Uni<Delivery> delivery(@Source Cargo cargo, Context context) {
        String request = context.getExecutionId();
        String trackingId = cargo.trackingId().value();
        // The two inputs are independent, so they are fetched together; the
        // derivation itself calls no source.
        return Uni.combine()
                .all()
                .unis(routing.getItinerary(request, trackingId), handling.listEvents(request, trackingId))
                .with((itinerary, events) -> derivation.derive(cargo, itinerary, events));
    }
```

```python
    @strawberry.field(description="Delivery status derived from handling history.")
    async def delivery(self, info: Info[TrackingContext]) -> Delivery:
        # The two inputs are independent, so they are fetched together; the
        # derivation itself calls no source.
        itinerary, events = await asyncio.gather(
            info.context.routing.get_itinerary(self.tracking_id),
            info.context.handling.list_events(self.tracking_id),
        )
        return info.context.derivation.derive(self, itinerary, events)
```

The two fetches are independent, so the resolver starts both. The log shows `getItinerary` and `listEvents` overlapping after `getCargo` ends, and awaiting them one after the other would add 250 ms to every query that selects `delivery`. The resolver fetches the itinerary itself instead of reading it from the parent: a `Cargo` carries no itinerary, and reaching for a value another field fetched would couple two resolvers through hidden state.

The alternative is a derived field in the source: a `delivery` service that does this work. That is right when several clients of the service share the derivation. Here the tracking view owns the rule because it combines facts from routing and handling that no single service holds. The cost is a dependency on two sources for one field, so a slow handling service slows every query that selects `delivery`.

## Variables and defaults

A variable keeps a document fixed while its inputs change. It is declared with a type after the operation name, used with `$`, and may carry a default.

```graphql
query($t: TrackingId! = "ABC123") { cargo(trackingId: $t) { trackingId } }
```

With no `variables`, both stacks answer `ABC123`. With `{"t":"XYZ789"}` they answer `XYZ789`, since a supplied value wins. The default belongs to the operation, not the schema: the schema's argument is `TrackingId!` with no default.

Both stacks can give an argument a schema-level default, `@DefaultValue("V100S")` on the SmallRye parameter and `= "V100S"` after the `Annotated[...]` parameter in Strawberry, but they print it differently. Strawberry keeps the wrapper (`voyageNumber: String! = "V100S"`), and the diff reports the added default only as dangerous, which the conformance check doesn't fail. SmallRye prints `voyageNumber: String = "V100S"`, a nullable argument with a default, and the check reports that as breaking. Send documents with variables: the server can parse and validate once, and a persisted query can refer to the document by hash.

## Aliases

Two fields with one name and different arguments would want the same response key. An alias gives a field another key, so one document can ask for the same field twice.

```graphql
{ ny: location(unLocode: "USNYC") { name } rtm: location(unLocode: "NLRTM") { name } }
```

Both stacks answer `{"data":{"ny":{"name":"New York"},"rtm":{"name":"Rotterdam"}}}`. "Field Collection" merges fields that share a response key. Two aliased root fields are siblings, so the log shows two overlapping `location.getLocation` calls: one round trip for the client, two lookups for the server, running together. An alias also names the key in an error's `path`.

## Fragments

A fragment names a selection set so several places can reuse it, and a spread applies it.

```graphql
{ cargo(trackingId: "ABC123") { origin { ...Place } destination { ...Place } } }
fragment Place on Location { unLocode name country }
```

Both stacks answer `origin` as `{"unLocode":"USNYC","name":"New York","country":"US"}` and `destination` as `{"unLocode":"NLRTM","name":"Rotterdam","country":"NL"}`. A fragment is reuse for the client, not the server: after "Field Collection" the spread is expanded in place, so the engine sees the same fields as if they were written twice. An inline fragment, `... on Location { name }`, applies a type condition without naming the selection, and selects fields of one implementer under an interface:

```graphql
{ node(id: "loc_NLRTM") { __typename ... on Location { name } } }
```

This returns `{"__typename":"Location","name":"Rotterdam"}`, and a `... on Cargo` fragment in the same selection would contribute nothing.

## `@include` and `@skip`

Two built-in directives take a boolean and decide whether a field takes part in the query. `@include(if: true)` keeps a field and `@skip(if: true)` drops it. The boolean can be a variable, so one document serves two views.

```graphql
query($full: Boolean!) {
  cargo(trackingId: "ABC123") {
    trackingId
    itinerary @include(if: $full) { legs { loadTime } }
    delivery @skip(if: $full) { transportStatus }
  }
}
```

"Field Collection" drops an excluded field before execution reaches it, so its resolver never runs and its sources are never called.

{% include excalidraw.html file="07-directive-pruning" alt="Two panels side by side that run the same document. In the left panel, full is false: cargo is resolved, the itinerary field is drawn dashed as not collected and not resolved, and the delivery field is resolved. Below, a highlighted box lists three calls made, booking.getCargo, routing.getItinerary and handling.listEvents, and a dashed box lists one call avoided, a second routing.getItinerary. In the right panel, full is true: itinerary is resolved and delivery is dashed. A highlighted box lists two calls made, booking.getCargo and routing.getItinerary, and a dashed box lists two calls avoided, handling.listEvents and routing.getItinerary as an input." caption="Figure 7.3: The same document with full set to false and to true. The pruned branch is dashed, and the calls it would have made never reach a source." %}

With `full` false the response has no `itinerary` key, `delivery.transportStatus` is `ONBOARD_CARRIER`, and the log is `booking.getCargo`, `routing.getItinerary` and `handling.listEvents`. With `full` true the response has `itinerary` with `loadTime` `2026-10-01T08:00:00Z` for the first leg and no `delivery` key, and the log is `booking.getCargo` and `routing.getItinerary`, with no `handling` call.

`routing.getItinerary` appears in both runs for different reasons: an input of the derivation in the first, the `itinerary` field itself in the second. Selecting `itinerary` and `delivery` together makes two `routing.getItinerary:ABC123` calls, one from each field. Pruning doesn't make a resolver cheaper. It decides which resolvers run, and the client makes that decision, which is why a variable-driven document gives a mobile screen a lighter view than a desktop one.

## Request context

The context is the one object every resolver of a request shares. On Quarkus each resolver reads `Context#getExecutionId()` at entry and passes the id to the source. On Python the router's `context_getter` builds a `TrackingContext` per request.

{% include codetabs.html langs="Quarkus|Python" %}

```java
    @Query
    @Description("Look up one cargo by its tracking id. Null when no such cargo exists.")
    public Uni<Cargo> cargo(
            @Name("trackingId") @NonNull @Description("The tracking id issued at booking.") TrackingId trackingId,
            Context context) {
        return booking.getCargo(context.getExecutionId(), trackingId.value());
    }
```

```python
class TrackingContext(BaseContext):
    def __init__(
        self,
        request_id: str,
        booking: BookingSource,
        routing: RoutingSource,
        voyage: VoyageSource,
        location: LocationSource,
        handling: HandlingSource,
        derivation: DeliveryDerivation,
    ) -> None:
        super().__init__()
        self.request_id = request_id
        self.booking = booking
        self.routing = routing
        self.voyage = voyage
        self.location = location
        self.handling = handling
        self.derivation = derivation
```

| Belongs in the context | Belongs elsewhere |
|---|---|
| Anything scoped to a request and shared across fields: the caller's identity once authentication exists, a per-request cache or batching loader, the request id for tracing | Anything shared across requests, in an application-scoped bean or a module-level object |

The derivation object is an example of the second column: it holds reference data and no request state, so Python builds it once and the context only points at it. Every resolver of one request sees one context, and two requests never share one.

## The repeated-fetch smell

Nothing caches within a request, and a resolver is called once per field occurrence, so two selections of the same field fetch the same data twice.

```graphql
{ cargo(trackingId: "ABC123") { itinerary { legs { a: voyage { number } b: voyage { number } } } } }
```

Two legs and two aliases make four `voyage.getVoyage` calls, two for `V100S` and two for `V200E`, on both stacks. The aliases are artificial, but the same shape arises without them: a page that shows a leg's voyage in a header and again in a detail card, or a list of cargos that share a voyage, does the same work for every place the voyage appears.

The smell stays in place because the four-call count is the number batching reduces. The fix has three parts: a loader that batches the keys a level asks for into one call, a cache scoped to the request context so repeated keys cost nothing, and a decision about where batching sits relative to the sources. DataLoader batching builds them.

> **🤖 Explore with your agent**
>
> "In `examples/07-queries-resolvers`, add a `Cargo.estimatedDaysInTransit` computed field on both stacks. Derive it in `DeliveryDerivation` from the itinerary and the last handling event so the rule takes plain values and calls no source, and fetch the itinerary and `handling.listEvents` together with `Uni.combine().all()` on Quarkus and `asyncio.gather` on Python. Then query it beside `delivery` and tell me how many `routing.getItinerary` calls the log shows."
>
> Check: `curl localhost:8170/debug/source-calls` shows `getItinerary` and `listEvents` with overlapping windows, and a second `getItinerary` call appears when `itinerary` and the new field are selected together.

## Build, run, observe

Quarkus is on `8170` and Python on `8171`, and compose sets `TRACKING_SOURCE_LATENCY_MS=250` and `TRACKING_DEBUG_ENDPOINTS=true`. Reset the log, send the chain query and read the log:

```bash
docker compose -f examples/07-queries-resolvers/compose.yaml up -d --build
curl -s -X DELETE -w '%{http_code}\n' localhost:8170/debug/source-calls
curl -s localhost:8170/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { itinerary { legs { voyage { number } } } } }"}'
curl -s localhost:8170/debug/source-calls
```

```json
204
{"data":{"cargo":{"itinerary":{"legs":[{"voyage":{"number":"V100S"}},{"voyage":{"number":"V200E"}}]}}}}
{"calls":[{"request":"21107852851","source":"booking","op":"getCargo","key":"ABC123","startMs":34,"endMs":288},{"request":"21107852851","source":"routing","op":"getItinerary","key":"ABC123","startMs":301,"endMs":552},{"request":"21107852851","source":"voyage","op":"getVoyage","key":"V100S","startMs":559,"endMs":811},{"request":"21107852851","source":"voyage","op":"getVoyage","key":"V200E","startMs":560,"endMs":814}]}
```

Four calls, one request id, and the two voyage calls start one millisecond apart. Python answers the same body with a uuid4 as the request id. Now the derived delivery, after a reset:

```bash
curl -s localhost:8170/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { delivery { transportStatus routingStatus misdirected lastKnownLocation { unLocode } currentVoyage { number } estimatedTimeOfArrival nextExpectedActivity { type location { unLocode } voyage { number } } } } }"}'
curl -s localhost:8170/debug/source-calls
```

```json
{"data":{"cargo":{"delivery":{"transportStatus":"ONBOARD_CARRIER","routingStatus":"ROUTED","misdirected":false,"lastKnownLocation":{"unLocode":"USNYC"},"currentVoyage":{"number":"V100S"},"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V100S"}}}}}}
{"calls":[{"request":"21107852852","source":"booking","op":"getCargo","key":"ABC123","startMs":969,"endMs":1220},{"request":"21107852852","source":"routing","op":"getItinerary","key":"ABC123","startMs":1234,"endMs":1486},{"request":"21107852852","source":"handling","op":"listEvents","key":"ABC123","startMs":1234,"endMs":1486}]}
```

`getItinerary` and `listEvents` start together. The same query for `XYZ789` on both stacks answers:

```json
{"data":{"cargo":{"delivery":{"transportStatus":"NOT_RECEIVED","routingStatus":"NOT_ROUTED","misdirected":false,"lastKnownLocation":null,"currentVoyage":null,"estimatedTimeOfArrival":null,"nextExpectedActivity":{"type":"RECEIVE","location":{"unLocode":"SGSIN"},"voyage":null}}}}}
```

Pruning, with the `@include`/`@skip` document and `{"full":false}` and then `{"full":true}`:

```json
{"data":{"cargo":{"trackingId":"ABC123","delivery":{"transportStatus":"ONBOARD_CARRIER"}}}}
{"data":{"cargo":{"trackingId":"ABC123","itinerary":{"legs":[{"loadTime":"2026-10-01T08:00:00Z"},{"loadTime":"2026-10-10T06:00:00Z"}]}}}}
```

Request ids and timings differ on every run. The keys, order and overlap don't. `bash examples/07-queries-resolvers/verify.sh` runs all of this on both stacks and prints `PASS` only when both hold. It compares keys, order and overlap, never a duration.

Experiments:

- **Prune with a variable.** Run the `@include`/`@skip` document with `full` false and then true. The `handling.listEvents` call disappears in the second run.
- **Select both fields.** Ask for `itinerary` and `delivery` together. The log shows two `routing.getItinerary:ABC123` calls.
- **Alias a field twice.** Ask for `a: voyage` and `b: voyage` on each leg. The log shows four `voyage.getVoyage` calls.
- **Look up a missing key.** `cargo(trackingId: "NOPE99")` and `voyage(voyageNumber: "V999X")` return `null` with no `errors`.

> **Decision**
>
> Leave a field a property when the parent's record already carries it, and make it a resolver when another service owns it. Put derivation rules in a plain class that takes values and calls no source, fetch independent inputs together, keep request-scoped state (identity, loaders, the request id) in the context and cross-request state out of it, and leave the repeated fetch visible until batching can measure the fix.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): "Customizing and organizing GraphQL operations," "Implementing schema resolvers," and "Working with database models and relations" cover resolvers and operations. Listed on the [Bibliography](../../bibliography/) page.
- [GraphQL specification](https://spec.graphql.org/): "Executing Fields", "Field Collection", "Field Alias", "Fragments", "Inline Fragments", "Variables" and the built-in `@skip` and `@include` directives.
- *Cloud Native Design Patterns*, "Composition": aggregation across sources, the pattern `Cargo.delivery` applies at the field level.
- [Quarkus SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) and [Strawberry documentation](https://strawberry.rocks/docs): the `Context`/`Info` objects and `@Source`/resolver method shapes used on each stack.
