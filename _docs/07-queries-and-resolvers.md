---
title: "Queries and resolvers"
order: 7
part: "Execution: Resolvers, Queries & Mutations"
description: "What a resolver receives and returns, how a parent value becomes a child's arguments and then a source key, how Delivery is derived from handling events instead of stored, and how variables, aliases, fragments and the @include and @skip directives change which sources a query calls."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Trace how a resolver's four inputs (parent, arguments, context, and info) flow from `Query.cargo` through `Cargo.itinerary` and into a source call.
- Derive a computed field like `Cargo.delivery` from independent fetches run concurrently with `Uni.combine().all()` / `asyncio.gather`, instead of reading it from a stored source.
- Use variables, aliases, fragments, and `@include`/`@skip` to change which fields (and therefore which source calls) a document makes.
- Explain why `Context` holds request-scoped state like the execution id, and why it must never carry data shared across requests.
- Recognize the repeated-fetch smell where two selections of the same field (e.g. `Leg.voyage`) cost two source calls, as the problem DataLoader batching solves.

## Why this matters

The execution model followed a request through the engine and stopped at the point where the engine calls a resolver. A resolver is an ordinary function with four inputs and one output, and the whole shape of a GraphQL server's cost comes from how those functions pass values to each other: the parent's data becomes the child's argument, and the argument becomes a key into a source. You will see that chain on the running stacks, replace the stored `Delivery` of earlier chapters with one derived from handling events, and then use variables, aliases, fragments and directives to see which of them change the calls a query makes.

The code is in `examples/07-queries-resolvers/`. It starts from the execution-model example and keeps its asynchronous sources, the source-call log and the per-request id. Two things change. A new `handling` source returns the events recorded for a cargo, and `Cargo.delivery` is computed from those events and the itinerary instead of read from a `delivery` source, which is removed. `verify.sh` asserts every value in the "On the wire" section on both stacks, and `README.md` covers how to drive it.

## Anatomy of a resolver

Every resolver receives the same four inputs, spelled differently by each stack.

- **The parent** is the object the field is selected on. For a root field it is the root value and is usually ignored. For `Cargo.itinerary` it is the `Cargo` that `Query.cargo` returned.
- **The arguments** are the values written in the document for that field, after coercion. `Query.cargo` takes `trackingId`; `Cargo.itinerary` takes none.
- **The context** is state that belongs to the request, not to a field: here the request id and the five sources.
- **The info** describes the field being resolved: its name, its path in the response, the fields selected beneath it and the schema.

{% include excalidraw.html file="07-resolver-anatomy" alt="Four boxes on the left, labelled parent, arguments, context and info, each showing the Java and Python spelling of that input. Arrows from the four boxes lead to a highlighted box in the middle, Cargo.itinerary, which reads the tracking id from the parent and calls routing.getItinerary. The parent arrow is amber and labelled ABC123. A final amber arrow labelled engine completes it leads to a box on the right, the return value, an Itinerary or null, as a Uni in Java or a coroutine in Python." caption="Figure 7.1: The four inputs of a resolver. Cargo.itinerary uses the parent, takes no arguments, and returns a value the engine completes." %}

On Quarkus the resolver is a method in the `@GraphQLApi` class. A method whose first parameter is annotated `@Source` is a field of that parent type; a method annotated `@Query` is a root field. Plain parameters are arguments, named with `@Name`. The SmallRye `Context` is a parameter the engine fills in, and it carries both the request-level and the field-level information: `getExecutionId()`, `getFieldName()`, `getPath()` and `getSelectedFields()` are all on it. On Python a resolver is a method on the type, `self` is the parent, typed parameters are the arguments, and `info` carries the field details and the context that the router's `context_getter` built.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Description("The planned route. Null until the routing service has assigned one.")
public Uni<Itinerary> itinerary(@Source Cargo cargo, Context context) {
    return routing.getItinerary(context.getExecutionId(), cargo.trackingId().value());
}
```

```python
@strawberry.field(description="The planned route. Null until the routing service has assigned one.")
async def itinerary(self, info: Info[TrackingContext]) -> Itinerary | None:
    return await info.context.routing.get_itinerary(self.tracking_id)
```

Both resolvers do the same three things: read the key from the parent, call the source, and give the result back to the engine. Neither touches the response. A resolver returns a value, or something that becomes one (`Uni`, a coroutine), and the engine completes it against the declared type, per the execution model's "Value Completion" step. The spec's "Value Resolution" step describes the same contract as `ResolveFieldValue(objectType, objectValue, fieldName, argumentValues)`; the context and the info are what each engine adds to that signature.

## Default resolvers

Most fields have no resolver of their own. `Cargo.description`, `Cargo.origin` and `Cargo.routeSpecification` come from the booking record that `Query.cargo` returned, and the engine reads them as properties of the parent: a record accessor on Quarkus, an attribute on Python. That default resolver is the reason the execution model's first check costs one call. It is also the line between fields that cost something and fields that do not.

```graphql
{ cargo(trackingId: "ABC123") { description } }
```

The log for this query is exactly `booking.getCargo:ABC123` on both stacks. The rule for placing a field is therefore a question about who owns the data. If the booking record already carries it, leave it a property. If another service owns it, make it a resolver, as `Cargo.itinerary` is, and the cost becomes visible in the log and, later, in the chapters on batching and cost limits.

## Root resolvers and arguments

The four root fields are `cargo`, `location`, `voyage` and `node`. Each takes one argument, hands it to a source as the key, and returns `null` when the source has nothing, because the contract makes each result nullable: "Null when no such cargo exists." A lookup that finds nothing is an answer, not a failure.

```graphql
{ voyage(voyageNumber: "V999X") { number } }
```

Both stacks answer `{"data":{"voyage":null}}` with no `errors`. The same holds for `cargo(trackingId: "NOPE99")`. Nullability propagation explained why the nullable root is the first fuse in the tracking schema; here it is the reason a client can distinguish "no such voyage" from "the voyage service failed", which would arrive as an entry in `errors`.

`Query.node` dispatches on the prefix of the id, `cargo_`, `loc_` or `voy_`, and calls the matching source. The canonical SDL introduced it as the Relay refetch field. In this chapter it shows that a root resolver can choose among sources, but still maps one argument to one key.

## The resolver chain

A query is a chain of such calls. Take the selection `cargo { itinerary { legs { voyage { number } } } }` and follow the values.

{% include excalidraw.html file="07-resolver-chain" alt="A row of boxes from left to right. Query.cargo, highlighted, takes the argument trackingId ABC123 and calls booking.getCargo, drawn below it. It returns a Cargo box. An amber arrow labelled parent leads to Cargo.itinerary, highlighted, which calls routing.getItinerary for ABC123, drawn below it. It returns an Itinerary box with two legs. Two amber arrows labelled leg 0 and leg 1 lead to two highlighted resolvers, legs[0].voyage and legs[1].voyage, which call voyage.getVoyage for V100S and V200E in two source boxes to their right. Millisecond offsets from a real run appear under each source." caption="Figure 7.2: The resolver chain for one query. The parent value feeds the child resolver, the child derives a key from it, and the key goes to a source. The two voyage lookups start together." %}

`Query.cargo` receives the argument `ABC123` from the document and passes it to `booking.getCargo`. The `Cargo` that comes back is the parent of `itinerary`, and the resolver reads `trackingId` from it and calls `routing.getItinerary`. The `Itinerary` holds two `Leg` values, each with a voyage number, and the engine runs `Leg.voyage` once per list item with that leg as the parent. Each resolver gets its input from the one above it, and no resolver knows about the one below.

On Quarkus, a run with 250 ms sources produced this log, with the request id shortened to its position:

```text
booking   getCargo      ABC123  start +   0  end + 254
routing   getItinerary  ABC123  start + 265  end + 516
voyage    getVoyage     V100S   start + 522  end + 773
voyage    getVoyage     V200E   start + 522  end + 776
```

`verify.sh` asserts the four calls as a set, then that `getItinerary` ends before either voyage call starts, and that the two voyage calls overlap. The order is the dependency: the itinerary is the only place the voyage numbers exist, so no voyage call can start before it ends. The overlap is the list: items of one list are siblings, and the execution model's rule for siblings applies to them. The query's latency is three levels of 250 ms, whatever the number of legs.

## Computed fields

`Delivery` is not a record any service stores. It is a view of three facts: what the customer asked for (the route specification), what routing planned (the itinerary) and what has happened (the handling events). Earlier chapters served it as constants so that the type system and the engine could be taught first. Here it is derived, and the values must not change: `verify.sh` asserts that the derived `Delivery` for `ABC123` and `XYZ789` equals exactly the constant value served earlier.

The derivation takes the last handling event, the one with the greatest completion time, and reads the state off it.

| Last event | `transportStatus` | `currentVoyage` | `nextExpectedActivity` |
|---|---|---|---|
| none | `NOT_RECEIVED` | none | `RECEIVE` at the route's origin |
| `RECEIVE` | `IN_PORT` | none | `LOAD` on the first leg |
| `LOAD` at L on V | `ONBOARD_CARRIER` | V | `UNLOAD` at the matching leg's end |
| `UNLOAD` at L on V | `IN_PORT` | none | `CLAIM` at L if L is the destination, else `LOAD` on the next leg |
| `CUSTOMS` | `IN_PORT` | none | none |
| `CLAIM` | `CLAIMED` | none | none |

`lastKnownLocation` is that event's location. `routingStatus` is `NOT_ROUTED` without an itinerary, `MISROUTED` when the first leg does not load at the origin or the last leg does not unload at the destination, and `ROUTED` otherwise. `misdirected` is true when the last load or unload does not match a leg by location and voyage. The estimate, `estimatedTimeOfArrival`, is the itinerary's final arrival date only when the cargo is `ROUTED` and not misdirected. `ABC123` has two events, a `RECEIVE` in New York and a `LOAD` on `V100S`, so it is `ONBOARD_CARRIER` on `V100S`, and the leg that matches the load ends with an `UNLOAD` in Hamburg. `XYZ789` has none, so it is `NOT_RECEIVED` with a `RECEIVE` expected in Singapore.

Where the derivation lives is a design decision with two parts. The rules live in one class that takes plain values and calls no source: `DeliveryDerivation` on both stacks (`app/derivation.py` on Python). It can be tested without a request, and the table above is its documentation. The resolver is only the glue that fetches the inputs.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@NonNull
@Description("Delivery status derived from handling history.")
public Uni<Delivery> delivery(@Source Cargo cargo, Context context) {
    String request = context.getExecutionId();
    String trackingId = cargo.trackingId().value();
    return Uni.combine()
            .all()
            .unis(routing.getItinerary(request, trackingId), handling.listEvents(request, trackingId))
            .with((itinerary, events) -> derivation.derive(cargo, itinerary, events));
}
```

```python
@strawberry.field(description="Delivery status derived from handling history.")
async def delivery(self, info: Info[TrackingContext]) -> Delivery:
    itinerary, events = await asyncio.gather(
        info.context.routing.get_itinerary(self.tracking_id),
        info.context.handling.list_events(self.tracking_id),
    )
    return info.context.derivation.derive(self, itinerary, events)
```

The two fetches do not depend on each other, so the resolver starts both: `Uni.combine().all()` on Quarkus, `asyncio.gather` on Python. The log confirms it, with `getItinerary` and `listEvents` overlapping after `getCargo` ends. This is the execution model's sibling rule applied inside one resolver, and a resolver that awaited them one after the other would add 250 ms to every query that selects `delivery`. The resolver gets the itinerary from the routing source, not from the parent: a parent `Cargo` carries no itinerary, and reaching for a value some other field fetched would couple two resolvers through hidden state.

The alternative is a derived field in the source, a `delivery` service that does this work and returns the result. That is the right answer when the derivation is shared by several clients of the service, and the earlier chapters' `DeliverySource` modeled it. Here the tracking view owns the rule because it combines facts from routing and handling that no single service holds. The cost is visible: the tracking view now depends on two sources for one field, and a slow handling service slows every query that selects `delivery`.

## Variables and defaults

A variable lets a document stay fixed while its inputs change. It is declared with a type after the operation name, used with `$`, and may carry a default.

```graphql
query($t: TrackingId! = "ABC123") { cargo(trackingId: $t) { trackingId } }
```

With no `variables` in the request, both stacks answer `ABC123`. With `{"t":"XYZ789"}` they answer `XYZ789`, since a supplied value wins over the default. The default belongs to the operation, not to the schema: the schema's argument is `TrackingId!` and has no default, which is what the canonical SDL says. Both stacks can give an argument a schema-level default, `@DefaultValue("V100S")` on the SmallRye parameter and `= "V100S"` after the `Annotated[...]` parameter in Strawberry, and nothing in this slice needs one. They differ in what they print. Strawberry keeps the wrapper, `voyageNumber: String! = "V100S"`, and the diff reports the added default only as a dangerous change, which the conformance check does not fail. SmallRye prints `voyageNumber: String = "V100S"`, a nullable argument with a default, and the check reports that as breaking. The execution model already covered where coercion happens. The point here is that a document with variables is the form a client should send, because the server can parse and validate it once and a persisted query can later refer to it by hash.

## Aliases

Each field in a response sits under a key, and two fields with the same name and different arguments would want the same key. An alias gives a field another response key, so one document can ask for the same field twice with different arguments.

```graphql
{ ny: location(unLocode: "USNYC") { name } rtm: location(unLocode: "NLRTM") { name } }
```

Both stacks answer `{"data":{"ny":{"name":"New York"},"rtm":{"name":"Rotterdam"}}}`. The spec's "Field Alias" section defines the rule, and the "Field Collection" step of execution is what merges fields that share a response key. Two aliased root fields are siblings, so the log shows two `location.getLocation` calls that overlap: one round trip for the client, two lookups for the server, running together. An alias also appears in an error's `path`, where nullability propagation showed it names the aliased key.

## Fragments

A fragment names a selection set so that several places can reuse it. A named fragment has a type condition, and a spread applies it.

```graphql
{ cargo(trackingId: "ABC123") { origin { ...Place } destination { ...Place } } }
fragment Place on Location { unLocode name country }
```

Both stacks answer with `origin` as `{"unLocode":"USNYC","name":"New York","country":"US"}` and `destination` as `{"unLocode":"NLRTM","name":"Rotterdam","country":"NL"}`, the same seed data returned for the two locations. A fragment is a unit of reuse for the client, not for the server: after "Field Collection" the spread is expanded in place, so the engine sees the same fields as if they were written twice. An inline fragment, `... on Location { name }`, applies a type condition without naming the selection, and it is how a client selects fields of one implementer under an interface:

```graphql
{ node(id: "loc_NLRTM") { __typename ... on Location { name } } }
```

returns `{"__typename":"Location","name":"Rotterdam"}`, and a `... on Cargo` fragment in the same selection would contribute nothing, as the type system already showed. The spec covers both in "Fragments" and "Inline Fragments".

## `@include` and `@skip`

Two built-in directives take a boolean and decide whether a field takes part in the query at all. `@include(if: true)` keeps a field and `@skip(if: true)` drops it. Because the boolean can be a variable, one document serves two views.

```graphql
query($full: Boolean!) {
  cargo(trackingId: "ABC123") {
    trackingId
    itinerary @include(if: $full) { legs { loadTime } }
    delivery @skip(if: $full) { transportStatus }
  }
}
```

The spec places this in "Field Collection": a field excluded by either directive is dropped before execution reaches it, so its resolver never runs and its sources are never called. Figure 7.3 shows the two runs.

{% include excalidraw.html file="07-directive-pruning" alt="Two panels side by side that run the same document. In the left panel, full is false: cargo is resolved, the itinerary field is drawn dashed as not collected and not resolved, and the delivery field is resolved. Below, a highlighted box lists three calls made, booking.getCargo, routing.getItinerary and handling.listEvents, and a dashed box lists one call avoided, a second routing.getItinerary. In the right panel, full is true: itinerary is resolved and delivery is dashed. A highlighted box lists two calls made, booking.getCargo and routing.getItinerary, and a dashed box lists two calls avoided, handling.listEvents and routing.getItinerary as an input." caption="Figure 7.3: The same document with full set to false and to true. The pruned branch is dashed, and the calls it would have made never reach a source." %}

`verify.sh` asserts both runs from the log. With `full` false the response has no `itinerary` key, `delivery.transportStatus` is `ONBOARD_CARRIER`, and the log is `booking.getCargo`, `routing.getItinerary` and `handling.listEvents`. With `full` true the response has `itinerary` with `loadTime` `2026-10-01T08:00:00Z` for the first leg and no `delivery` key, and the log is `booking.getCargo` and `routing.getItinerary`, with no `handling` call at all.

The `routing.getItinerary` call appears in both runs, but for different reasons: in the first it is an input of the derivation, in the second it is the `itinerary` field itself. The saving is what a query with both fields would have paid. Selecting `itinerary` and `delivery` together makes two `routing.getItinerary:ABC123` calls, one from each field, and the check asserts that count. Pruning does not make a resolver cheaper. It decides which resolvers run, and the client, not the server, makes that decision, which is why a variable-driven document is the practical way to give a mobile screen a lighter view than a desktop one.

## Request context

The context is the one object every resolver of a request shares. The execution model introduced it for one purpose, the request id that tags every source call, and this chapter's example uses it that way throughout: on Quarkus each resolver reads `Context#getExecutionId()` at entry and passes the id to the source, and on Python the router's `context_getter` builds a `TrackingContext` per request.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Query
public Uni<Cargo> cargo(@Name("trackingId") @NonNull TrackingId trackingId, Context context) {
    return booking.getCargo(context.getExecutionId(), trackingId.value());
}
```

```python
class TrackingContext(BaseContext):
    def __init__(self, request_id, booking, routing, voyage, location, handling, derivation) -> None:
        super().__init__()
        self.request_id = request_id
        self.handling = handling
        ...
```

The context is the right place for anything scoped to a request and shared across fields: the caller's identity once authentication exists, a per-request cache or a batching loader, and the request id for tracing. It is the wrong place for something shared across requests, which belongs in an application-scoped bean or a module-level object. The derivation object is an example: it holds reference data and no request state, so Python builds it once and the context only points at it. `verify.sh` asserts `assert_single_request` on the chain's calls, which proves every resolver of one request saw one context, and `assert_distinct_requests` on a second request, which proves contexts do not leak between requests.

## The repeated-fetch smell

The resolver design so far has a cost the log makes visible. Nothing caches within a request, and a resolver is called once per field occurrence, so two selections of the same field fetch the same data twice.

```graphql
{ cargo(trackingId: "ABC123") { itinerary { legs { a: voyage { number } b: voyage { number } } } } }
```

Two legs and two aliases make four `voyage.getVoyage` calls, two of them for `V100S` and two for `V200E`. Both stacks do this, and `verify.sh` asserts the count of four. The aliases are artificial, but the same shape arises without them. A page that shows a leg's voyage in a header and again in a detail card, or a list of cargos that share a voyage, does the same work for each place the voyage appears.

This chapter leaves the smell in place. The fix has several parts: a loader that batches the keys a level asks for into one call, a cache scoped to the request context so repeated keys cost nothing, and a decision about where the batching sits relative to the sources. DataLoader batching builds them, and the four-call count here is the number that batching reduces. Fixing it early would hide the cost the next chapters need to measure.

## On the wire

Start the stack. Quarkus is on `8170` and Python on `8171`, and compose sets `TRACKING_SOURCE_LATENCY_MS=250` and `TRACKING_DEBUG_ENDPOINTS=true`. Reset the log, send the chain query and read the log:

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

Four calls, one request id, and the two voyage calls start one millisecond apart. Python answers the same body, with a uuid4 as the request id and the two voyage calls starting together. Now the derived delivery, after a reset:

```bash
curl -s localhost:8170/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { delivery { transportStatus routingStatus misdirected lastKnownLocation { unLocode } currentVoyage { number } estimatedTimeOfArrival nextExpectedActivity { type location { unLocode } voyage { number } } } } }"}'
curl -s localhost:8170/debug/source-calls
```

```json
{"data":{"cargo":{"delivery":{"transportStatus":"ONBOARD_CARRIER","routingStatus":"ROUTED","misdirected":false,"lastKnownLocation":{"unLocode":"USNYC"},"currentVoyage":{"number":"V100S"},"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V100S"}}}}}}
{"calls":[{"request":"21107852852","source":"booking","op":"getCargo","key":"ABC123","startMs":969,"endMs":1220},{"request":"21107852852","source":"routing","op":"getItinerary","key":"ABC123","startMs":1234,"endMs":1486},{"request":"21107852852","source":"handling","op":"listEvents","key":"ABC123","startMs":1234,"endMs":1486}]}
```

The delivery is the earlier constant, now computed, and `getItinerary` and `listEvents` start together. The same query for `XYZ789` on both stacks answers:

```json
{"data":{"cargo":{"delivery":{"transportStatus":"NOT_RECEIVED","routingStatus":"NOT_ROUTED","misdirected":false,"lastKnownLocation":null,"currentVoyage":null,"estimatedTimeOfArrival":null,"nextExpectedActivity":{"type":"RECEIVE","location":{"unLocode":"SGSIN"},"voyage":null}}}}}
```

Pruning, with the document from the previous section and `{"full":false}` and then `{"full":true}`:

```json
{"data":{"cargo":{"trackingId":"ABC123","delivery":{"transportStatus":"ONBOARD_CARRIER"}}}}
{"data":{"cargo":{"trackingId":"ABC123","itinerary":{"legs":[{"loadTime":"2026-10-01T08:00:00Z"},{"loadTime":"2026-10-10T06:00:00Z"}]}}}}
```

The log for the first is `booking.getCargo:ABC123`, `routing.getItinerary:ABC123`, `handling.listEvents:ABC123`, and for the second only the first two. The request ids, `startMs` and `endMs` differ on every run. What stays the same is the keys, the order and the overlap.

| Check | Expected |
|---|---|
| `cargo { itinerary { legs { voyage { number } } } }` | `V100S`, `V200E`; exactly `booking.getCargo:ABC123`, `routing.getItinerary:ABC123`, `voyage.getVoyage:V100S`, `voyage.getVoyage:V200E`; `getCargo` before `getItinerary`, `getItinerary` before each voyage call; the two voyage calls overlap; one `request` id |
| `cargo { delivery { ... } }` for `ABC123` | the whole object above; exactly `booking.getCargo:ABC123`, `routing.getItinerary:ABC123`, `handling.listEvents:ABC123`; `getCargo` before `listEvents`; `getItinerary` overlaps `listEvents` |
| the same for `XYZ789` | the `NOT_RECEIVED` object above; the same three calls with key `XYZ789` |
| `cargo { description }` | `Palletized electronics`; the log is exactly `booking.getCargo:ABC123` |
| `cargo(trackingId: "NOPE99")`, `voyage(voyageNumber: "V999X")` | `data.cargo` and `data.voyage` are `null`, no `errors` |
| `query($t: TrackingId! = "ABC123")` with no variables, then `{"t":"XYZ789"}` | `ABC123`, then `XYZ789` |
| `ny: location(USNYC)`, `rtm: location(NLRTM)` | `New York`, `Rotterdam`; the two `getLocation` calls overlap |
| `...Place` on `origin` and `destination` | `USNYC` / `New York` / `US` and `NLRTM` / `Rotterdam` / `NL` |
| `node(id: "loc_NLRTM") { __typename ... on Location { name } }` | `Location`, `Rotterdam` |
| `@include` / `@skip` with `full` false | no `itinerary` key; `delivery.transportStatus` is `ONBOARD_CARRIER`; calls: booking, routing, handling |
| the same with `full` true | `itinerary.legs.0.loadTime` is `2026-10-01T08:00:00Z`; no `delivery` key; calls: booking, routing; no `handling.*` call |
| a second request without a reset | the log holds at least two distinct `request` ids |
| two aliases of `Leg.voyage` over two legs | four `voyage.getVoyage` calls; `itinerary` and `delivery` together make two `routing.getItinerary` calls |
| `voyage(V100S) { schedule { departureLocation { unLocode } arrivalTime } }` | `USNYC`, `2026-10-09T14:00:00Z` |
| `__type` of `TrackingId`, `UnLocode`, `DateTime` | `SCALAR`; `specifiedByURL` null, `https://unece.org/trade/uncefact/unlocode`, `https://www.rfc-editor.org/rfc/rfc3339` |
| live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice) |

`bash examples/07-queries-resolvers/verify.sh` runs all of it on both stacks and prints `PASS` only when both hold. As with the execution model's checks, it asserts keys, order and overlap, never a duration.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Resolvers are where the <em>aggregation across sources</em> axis of the decision framework turns into code. Each field that crosses a service boundary is a resolver, the derived <code>Delivery</code> combines facts from two of them, and the log shows the price: one query is several calls whose depth sets its latency. The <em>client diversity and shape variance</em> axis shows in variables, aliases, fragments and directives, which let one schema serve many views and let the client, not the server, decide what runs. The <em>operational and security cost</em> axis shows in the repeated fetch: nothing here limits or batches what a document can ask for, so four calls for two legs is the cost of an open selection, and DataLoader batching with query-cost limits bring the controls. The <em>team ownership and federation</em> axis shows in where <code>Delivery</code> is derived: the tracking view owns the rule because no single service holds all three inputs, and it takes on the dependency. The tracking view derives in a plain class, fetches independent inputs together, keeps request state in the context, and leaves the repeated fetch visible until it can be measured.</p></div>

## Review

- A resolver's four inputs (parent, arguments, context, and info) flow from `Query.cargo` through `Cargo.itinerary` and into a source call.
- `Cargo.delivery` is derived from independent fetches run concurrently with `Uni.combine().all()` / `asyncio.gather`, rather than read from a stored source.
- Variables, aliases, fragments, and `@include`/`@skip` change which fields, and therefore which source calls, a document makes.
- `Context` holds request-scoped state like the execution id, and never carries data shared across requests.
- The repeated-fetch smell, where two selections of the same field (e.g. `Leg.voyage`) cost two source calls, is the problem DataLoader batching solves.

## Where this goes next

This chapter looked inside the resolver: its four inputs, the chain that turns a parent value into a source key, the derived `Delivery` that replaced a stored one, and the effect of variables, aliases, fragments and directives on the calls a query makes. The repeated fetch is still in the example, and the source-call log is how a later chapter will prove it gone.

The next example builds on this one and adds the first mutation, `registerHandlingEvent`. Its payload re-reads the cargo and its delivery, so a new handling event changes the derived `Delivery` that this chapter computes: an `UNLOAD` in Hamburg moves `ABC123` from `ONBOARD_CARRIER` to `IN_PORT` with a `LOAD` on `V200E` expected next, and an `UNLOAD` in Rotterdam, the destination, makes the next expected activity `CLAIM`. Error handling gives execution errors a contract, and DataLoader batching takes care of the voyage lookups.

For the formal definitions, read "Executing Fields", "Field Collection", "Field Alias", "Fragments", "Inline Fragments", "Variables" and the built-in `@skip` and `@include` directives in the [GraphQL specification](https://spec.graphql.org/). Samer Buna's *GraphQL in Action* covers resolvers and operations in "Customizing and organizing GraphQL operations", "Implementing schema resolvers" and "Working with database models and relations"; the book is listed on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): resolvers and operations, in "Customizing and organizing GraphQL operations," "Implementing schema resolvers," and "Working with database models and relations."
- [GraphQL specification: Executing Fields, Field Collection, Variables](https://spec.graphql.org/): the formal contract behind a resolver's four inputs and the directive-pruning rules this chapter exercises.
- *Cloud Native Design Patterns*, "Composition": aggregation across sources and where it belongs, the pattern `Cargo.delivery` applies at the field level.
- [Quarkus SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) and [Strawberry documentation](https://strawberry.rocks/docs): the `Context`/`Info` objects and `@Source`/resolver method shapes used on each stack.
