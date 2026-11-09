---
title: "The execution model"
order: 6
part: "Execution: Resolvers, Queries & Mutations"
description: "What happens between a POST to /graphql and the JSON that comes back: parse, validate, coerce variables, then walk the selection set. Sibling fields run together, top-level mutation fields run one at a time, and both stacks' source-call logs show it."
duration: "13 min read"
---

## Learning objectives

By the end of this chapter you can:

- Walk a GraphQL request through its four stages: parse, validate, coerce variables, execute.
- Explain why sibling fields may run concurrently while top-level `Mutation` fields execute serially.
- Read a source-call log to verify, rather than assume, resolver ordering and overlap.
- Compare blocking and asynchronous resolver styles (a plain return value vs. `Uni`, a blocking `def` vs. `async def`) and their effect on thread and event-loop occupancy.
- Map the GraphQL-over-HTTP status-code recommendations to what SmallRye and Strawberry return in practice.

## Why this matters

A GraphQL server doesn't run a query the way a database runs SQL. It parses text, checks it against the schema, converts its inputs, then calls ordinary functions, one per field, in an order the specification mostly leaves to the engine. Knowing that order tells you which calls a selection costs, which of them wait for each other, and what a failed request leaves behind.

Five sources (booking, routing, voyage, location, delivery) stand behind the schema. Each call takes 250 ms and is written to a log served at `/debug/source-calls`, so order and overlap are read off the log instead of assumed. The log is a lab tool and is off unless `TRACKING_DEBUG_ENDPOINTS=true`.

{% include excalidraw.html file="06-request-phases" alt="A row of six boxes joined by arrows from left to right: POST /graphql carrying query, variables and operationName; Parse, text to a document; Validate, document against the schema; Coerce variables, JSON values to declared types; Execute, highlighted, which walks the selection and calls resolvers; and Response with data, errors or both. Dashed arrows run from Parse, Validate and Coerce variables down to a highlighted Request error box that reads errors, no data, and zero source calls. A double-headed arrow joins Execute to a Sources box listing booking, routing, voyage, location and delivery." caption="Figure 6.1: Three stages run before any resolver. A failure in one of them ends the request with errors, no data and no source calls; only Execute reaches the sources." %}

## A request is a document plus inputs

Over HTTP a request is a JSON object with `query`, the document text; `variables`, a JSON object of inputs; and `operationName`, which says which operation to run. A document can hold several operations and any number of fragments, and the server runs exactly one. The `GetOperation` step of "Executing Requests" in the [GraphQL specification](https://spec.graphql.org/) picks the named one, or the only one when there's a single operation and no name. With several operations and no name, the specification says to raise a request error.

The stacks diverge here. Given `query A { cargo(trackingId: "ABC123") { trackingId } } query B { ... }` with no `operationName`, SmallRye rejects the request with `Must provide operation name if query contains multiple operations.`, no `data` and no source call. Strawberry runs the first operation and answers `ABC123`. Both answer `XYZ789` when `operationName` is `B`, and only `booking.getCargo:XYZ789` appears in the log. Send `operationName` whenever a document holds more than one operation. It also names each request in logs and traces.

A **request error** is the specification's term for a failure before execution starts, and the current edition calls a failure inside a resolver an **execution error** (older editions said "field error"). Three stages produce request errors.

## Parse

Parsing turns the text into a document: a tree of operations, selection sets, fields, arguments and fragments. It checks syntax only. An unclosed brace, a missing name or a stray character stops the request.

```graphql
{ cargo(trackingId: "ABC123") { trackingId }
```

Quarkus answers `Unparseable input document` and omits `data`. Python answers `Syntax Error: Expected Name, found <EOF>.` with `"data":null`. The specification says `data` should be absent for a request error, but Strawberry sends the key with a null value, so a client should test for absent or null. Both answer HTTP 200 and leave the log empty, because no resolver was reached.

## Validate

Validation checks the document against the schema without touching data. The rules in the specification's "Validation" section include: every field exists on the type it is selected from, every object-typed field has a selection set and every leaf has none, arguments match their declared types, fragments are defined, used and acyclic, and variables are declared, used and compatible with their positions.

```graphql
{ cargo(trackingId: "ABC123") { ...A } }
fragment A on Cargo { ...B }
fragment B on Cargo { ...A }
```

A fragment cycle would make execution unbounded, so validation rejects it. Quarkus reports `Validation error (FragmentCycle@[A]) : Fragment cycles not allowed` for each fragment in the cycle. Python reports `Cannot spread fragment 'A' within itself via 'B'.` An unknown field such as `cargo { weight }` fails the same way, and the log stays empty. Validation needs only the document and the schema, so a client can fix the document and resend it with no risk of having changed anything. It costs CPU on every request, which is where persisted queries and query-cost limits attach.

## Coerce variables

Variables arrive as JSON, which has fewer types than GraphQL. Coercion converts each variable to its declared type: a JSON string becomes a `TrackingId` through the scalar's input coercion, a missing optional variable takes its default, and a JSON `123` offered to a string scalar is an error. The engine won't call a resolver with an argument it can't trust, so this runs before execution.

```graphql
query($t: TrackingId!) { cargo(trackingId: $t) { trackingId } }
```

With `{"t":123}`, Quarkus answers `Variable 't' has an invalid value: SRGQL000013: Expected type [String or class extending class com.patterncatalyst.shipping.tracking.TrackingId] but was [BigDecimal].` and Python answers `Variable '$t' has invalid value: Expected value of type 'TrackingId', but encountered error 'expected a string, got int'; found: 123.` Both fail before any source call. The same mistake as a literal, `location(unLocode: 123)`, is rejected in validation, so a literal fails in the second stage and a variable in the third. A variable error names the variable, and the offending value is in the request body, not the document.

## Execute: walking the selection set

Execution starts with the root selection set and the root value. The specification's algorithms, from "Executing Operations" to "Executing Fields", reduce to three steps.

1. **Collect fields.** "Field Collection" groups the selection set by response key. Fields with the same key merge, fragments expand when their type condition applies, and `@skip` and `@include` drop what they exclude. This happens before any resolver runs, so a pruned field never costs a call.
2. **Resolve each field.** The resolver receives the parent value, the field's arguments and the request context, and returns the value or something that becomes it.
3. **Complete the value.** "Value Completion" checks the result against the field's type. A leaf is serialized, a list is completed item by item, an object is walked with the sub-selection as its selection set and the value as its parent, and a null in a non-null position is an error that null propagation carries upward.

Take `cargo { itinerary { legs { loadLocation { unLocode } } } delivery { transportStatus } }`.

{% include excalidraw.html file="06-field-walk" alt="A tree of resolver calls, left to right. A Query root value box leads to box 1, cargo, which calls booking.getCargo for ABC123. Two arrows labelled Cargo lead from box 1 to box 2, itinerary, which calls routing.getItinerary for ABC123, and to box 3, delivery, which calls delivery.getDelivery for ABC123. An arrow labelled Itinerary leads from box 2 to a plain box, legs, that makes no source call. Two arrows labelled Leg 0 and Leg 1 lead from legs to boxes 4 and 5, the loadLocation of each leg, which call location.getLocation for USNYC and DEHAM." caption="Figure 6.2: Field walk for one query. Each box is a resolver call and each edge label is the parent value the child receives. Boxes 2 and 3 start together, and so do 4 and 5." %}

`Query.cargo` calls `booking.getCargo` and returns a `Cargo`, the parent of `itinerary` and `delivery`. Neither takes the tracking id as an argument: each reads it from the parent. `itinerary` returns an `Itinerary` whose `legs` list needs no call of its own, because routing returned the legs with the itinerary. `loadLocation` turns each leg's UN/LOCODE into a `Location`. A selection such as `cargo { trackingId description }` makes exactly one call, `booking.getCargo:ABC123`, because `description` is a property of the booking record and has no resolver.

{% include codetabs.html langs="Quarkus|Python" %}

```java
    @Description("The planned route. Null until the routing service has assigned one.")
    public Uni<Itinerary> itinerary(@Source Cargo cargo, Context context) {
        return routing.getItinerary(context.getExecutionId(), cargo.trackingId().value());
    }

    @NonNull
    @Description("Where the cargo is loaded.")
    public Uni<Location> loadLocation(@Source Leg leg, Context context) {
        return locations.getLocation(context.getExecutionId(), leg.loadUnLocode());
    }
```

```python
    @strawberry.field(description="Where the cargo is loaded.")
    async def load_location(self, info: Info[TrackingContext]) -> Location:
        return await info.context.location.get_location(self.load_un_locode)
```

In SmallRye a `@Source` parameter is the parent value, and the method lives in the `@GraphQLApi` class beside the root fields. A `Uni` is Mutiny's lazy single-value type: the method returns a description of the work and the engine subscribes to it. The record components `Leg` uses for the codes are marked `@Ignore`, which keeps them out of the schema. In Strawberry the parent is `self`, `strawberry.Private` keeps a field out of the schema, and `info.context` is whatever the router's `context_getter` returned.

### One request id across every call

The log has to say which request a call belongs to, and each stack gets the id from a different place.

On Quarkus the id is `Context#getExecutionId()`, the SmallRye `Context` passed to the resolver. Read it at method entry, while the resolver still runs for its request, and pass it to the source as an argument. The continuation of a delayed `Uni` runs later on a different thread, where request-scoped state isn't guaranteed to be the same request's. On Python a uuid4 is created once per request in the router's context getter:

```python
def get_context(calls: Annotated[SourceCalls, Depends(get_calls)]) -> TrackingContext:
    request_id = str(uuid.uuid4())
    return TrackingContext(
        request_id,
        BookingSource(calls, request_id),
        RoutingSource(calls, request_id),
        VoyageSource(calls, request_id),
        LocationSource(calls, request_id),
        DeliverySource(calls, request_id),
    )
```

Every resolver of the request sees the same `info.context`, so all five sources are bound to one id.

## Sibling fields may run in parallel

"Normal and Serial Execution" in the specification says the executor can run the entries of a collected fields map "in whatever order it chooses (normally in parallel)", because field resolution is expected to be free of side effects. That is a permission, not a promise. Whether siblings overlap depends on the engine and on how the resolvers are written.

On the field-walk query, `booking.getCargo` ends before `routing.getItinerary` and `delivery.getDelivery` start, those two overlap, and the two `getLocation` calls overlap.

{% include excalidraw.html file="06-parallel-siblings" alt="A timeline with a horizontal axis marked 0, 250, 500 and 750 milliseconds and four lanes. In the booking lane a bar for getCargo ABC123 runs from 0 to about 250. In the routing lane a bar for getItinerary runs from about 255 to 506, and in the delivery lane a bar for getDelivery starts at about 257 and ends at about 516, so the two overlap. In the location lane two bars, USNYC and DEHAM, both run from about 514 to about 766. A separate dashed lane labelled sequential shows getItinerary from 0 to 250 followed by getDelivery from 250 to 500." caption="Figure 6.3: Sibling resolvers overlapping in time, drawn from the source-call log of one Quarkus run. The dashed lane shows the same two calls from blocking resolvers on one event loop." %}

Python shows the same shape. Total time follows the depth of the tree, three levels of 250 ms, not the five calls. Doubling the siblings at one level adds nothing, and adding a level adds 250 ms.

Siblings overlap when the resolver gives control back while it waits. Each stack's idiom does that:

{% include codetabs.html langs="Quarkus|Python" %}

```java
    public <T> Uni<T> call(String request, String source, String op, String key, Supplier<T> lookup) {
        return Uni.createFrom().deferred(() -> {
            long startMs = nowMs();
            return afterLatency(Uni.createFrom().item(lookup))
                    .eventually(() -> calls.add(new SourceCall(request, source, op, key, startMs, nowMs())));
        });
    }
```

```python
    async def call[T](
        self, request: str, source: str, op: str, key: str, lookup: Callable[[], T]
    ) -> T:
        """Run ``lookup`` after the latency; log the call when it ends, however it ends."""
        start_ms = _now_ms()
        try:
            await asyncio.sleep(self._latency)
            return lookup()
        finally:
            self._calls.append(SourceCall(request, source, op, key, start_ms, _now_ms()))
```

`Uni.deferred` starts the clock when the engine subscribes, the timer waits without holding a thread, and `eventually` writes the log entry whether the call produced a value, a null or an error. Python does the same with `await asyncio.sleep` and a `finally`. Both record start and end from a monotonic clock.

Resolver style decides what a waiting call costs:

| Style | Behavior |
|---|---|
| SmallRye, returns a `Uni` | Subscribed on a Vert.x event-loop thread and resumed there after the timer. Holds no thread while waiting. |
| SmallRye, returns a plain value | A blocking method. Each call gets its own worker thread (`executor-thread-1` and `-2` in one run). Calls overlap, with a thread held for each. |
| Strawberry, `async def` | Awaited together by graphql-core. Overlaps without holding anything. |
| Strawberry, plain `def` that blocks | Runs one after another, 250 ms each, on the event loop, and holds every other request on that loop meanwhile. A function that never yields has no point at which to overlap. |

So Quarkus spends a worker thread per blocking call, and on Python a blocking resolver occupies the event loop. A resolver that is asynchronous end to end scales with concurrent requests instead of with threads. Many sibling calls that want the same data are the next problem, which DataLoader batching addresses.

## Top-level mutation fields run serially

For a mutation the rule changes. "Normal and Serial Execution" says the fields of a mutation's root selection set execute serially, in the order written, and each completes, nested selections included, before the next begins. Below that level nothing changes: the fields inside one mutation field's payload are siblings again.

```graphql
mutation {
  a: registerHandlingEvent(input: { ... }) { cargo { delivery { transportStatus } } }
  b: registerHandlingEvent(input: { ... }) { cargo { delivery { transportStatus } } }
}
```

The aliases are needed because two fields with one name and different arguments would collide. The serial rule exists because mutations have side effects and `b` may depend on what `a` wrote: if `a` registers a load event and `b` the matching unload, `b` is only valid once `a` has landed. Query fields get no such guarantee, so a client that needs ordering must use a mutation.

{% include excalidraw.html file="06-serial-mutation" alt="A timeline with two lanes for the mutation fields a and b, both named registerHandlingEvent. In lane a an append event bar is followed by a payload re-read bar. A vertical line and an amber arrow marked a is finished lead to lane b, where an append event bar and a payload re-read bar start only after a is complete. A third lane, if a and b were query fields, shows two dashed bars labelled a and b starting together." caption="Figure 6.4: Top-level mutation fields run serially: b starts only after a, payload included, is complete. The timing is schematic." %}

graphql-java, the engine under SmallRye, has a serial execution strategy for mutations (`AsyncSerialExecutionStrategy`), and graphql-core runs a mutation's root fields through `execute_fields_serially`.

## Assembling the response

Execution ends with a map: the response keys, in order, each holding the completed value of its field. "Serialized Map Ordering" says the map should follow the order of the selection set, and a response key is the alias when there is one and the field name otherwise.

```graphql
{ b: cargo(trackingId: "XYZ789") { trackingId } a: cargo(trackingId: "ABC123") { trackingId } }
```

Both stacks answer `{"data":{"b":{"trackingId":"XYZ789"},"a":{"trackingId":"ABC123"}}}`, with `b` before `a`, although `a` sorts first alphabetically and either `getCargo` call might finish first. Selection order is the only order a client can rely on.

{% include excalidraw.html file="06-response-assembly" alt="Two boxes on the left, Finished 1st for a: cargo ABC123 and Finished 2nd for b: cargo XYZ789. Amber arrows cross to two slot boxes in the middle, labelled b, first in the selection, and a, second in the selection. Both slots point to a box on the right showing data with keys b and a in selection order, named by alias. A dashed box below it, errors with message and path, points up to the data box with the note path names the failed field, and is marked as present only when a resolver failed." caption="Figure 6.5: Resolver results flow into data in selection order, with aliases as keys. errors sits beside data and names the failed field by path." %}

`errors` sits beside `data`. When a resolver fails, "Handling Execution Errors" has the engine record an error whose `path` names the failed field, null the field, and continue with its siblings, so partial `data` comes back with `errors`. A request error has no `data` at all.

## Meta fields cost nothing

Fields whose names begin with two underscores belong to the engine. `__typename` returns the name of the object type the selection set is applied to, and `__schema` and `__type` answer from the schema. `{ __typename }` returns `{"data":{"__typename":"Query"}}` on both stacks with an empty log: it is answered after validation without a resolver, so it can sit in any selection set and never adds a call. It also checks that a deployment parses, validates and executes a request end to end.

## Status codes

GraphQL-over-HTTP, the working draft listed in the [Bibliography](../../bibliography/), covers this under "Status Codes". For an `application/graphql-response+json` response one rule is mandatory: a result without a `data` entry is a request error, and the server must answer with a 4xx or 5xx status. It recommends 400 when the document can't be parsed, and 422 when validation fails, the operation can't be determined or variables can't be coerced. A result that executed is 200 without errors, and 294, a partial-success code the draft defines itself and recommends only with its own media type, when `errors` sits beside `data`. A server must support that media type. A client that accepts only `application/json` is a legacy client, and the draft asks servers to apply the same status codes to it, except that a 2xx response keeps the `application/json` media type. A gateway, load balancer or log can then tell a rejected request from an executed one without reading the body.

Both stacks answer HTTP 200 for every request error above: parse, validation and coercion on both, and the missing `operationName` on Quarkus.

| Request | Quarkus | Python |
|---|---|---|
| Parse error, `Accept: application/json` | 200, `data` absent | 200, `"data":null` |
| Unknown field, `Accept: application/json` | 200 | 200 |
| Unknown field, `Accept: application/graphql-response+json` | 200 with that content type | 200 with `application/json` |

Quarkus acknowledges the new media type in `Content-Type` but answers 200 with no `data`, where the draft recommends a 4xx. Strawberry answers `application/json`. A client therefore detects a request error from the body on either stack: `errors` present and `data` absent or null. A gateway that wants the 4xx semantics can add them. These values belong to SmallRye GraphQL 2.18.5 and Strawberry 0.335.0, and they're asserted so that a change on upgrade is visible.

> **🤖 Explore with your agent**
>
> "In `examples/06-execution-model`, add a `Cargo.handlingCount` field that calls a new `handling.countEvents` source with a 250 ms latency, on both stacks. Write it as a `Uni` on Quarkus and `async def` on Python, take the request id at method entry, and query it together with `itinerary` so the two sibling calls overlap in `/debug/source-calls`. Then show what the log looks like if the Python version is a plain `def` that blocks."
>
> Check: `curl localhost:8160/debug/source-calls` shows `getItinerary` and `countEvents` with overlapping `startMs` and `endMs` windows, and the blocking variant shows them one after the other.

## Build, run, observe

Quarkus is on `8160` and Python on `8161`, and compose sets `TRACKING_SOURCE_LATENCY_MS=250` and `TRACKING_DEBUG_ENDPOINTS=true`. Reset the log, send a query that selects only a booking field, and read the log:

```bash
docker compose -f examples/06-execution-model/compose.yaml up -d --build
curl -s -X DELETE -w '%{http_code}\n' localhost:8160/debug/source-calls
curl -s localhost:8160/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId description } }"}'
curl -s localhost:8160/debug/source-calls
```

```json
204
{"data":{"cargo":{"trackingId":"ABC123","description":"Palletized electronics"}}}
{"calls":[{"request":"16323002360","source":"booking","op":"getCargo","key":"ABC123","startMs":98,"endMs":351}]}
```

One call, to the one source whose data the selection needs. Now the field-walk query, after another reset:

```bash
curl -s localhost:8160/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { itinerary { legs { loadLocation { unLocode } } } delivery { transportStatus } } }"}'
curl -s localhost:8160/debug/source-calls
```

```json
{"data":{"cargo":{"itinerary":{"legs":[{"loadLocation":{"unLocode":"USNYC"}},{"loadLocation":{"unLocode":"DEHAM"}}]},"delivery":{"transportStatus":"ONBOARD_CARRIER"}}}}
{"calls":[{"request":"16323002361","source":"booking","op":"getCargo","key":"ABC123","startMs":509,"endMs":760},{"request":"16323002361","source":"routing","op":"getItinerary","key":"ABC123","startMs":762,"endMs":1013},{"request":"16323002361","source":"delivery","op":"getDelivery","key":"ABC123","startMs":763,"endMs":1025},{"request":"16323002361","source":"location","op":"getLocation","key":"USNYC","startMs":1021,"endMs":1272},{"request":"16323002361","source":"location","op":"getLocation","key":"DEHAM","startMs":1023,"endMs":1274}]}
```

The request id and timings differ on every run and on Python, where the id is a uuid4. The shape holds: `getCargo` ends before `getItinerary` and `getDelivery` start, those two overlap, and the two `getLocation` calls overlap. A failed request leaves the log empty. With the unclosed-brace document:

```bash
curl -s -X DELETE localhost:8161/debug/source-calls
curl -s -w '  [HTTP %{http_code}]\n' localhost:8161/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId }"}'
curl -s localhost:8161/debug/source-calls
```

```text
{"data":null,"errors":[{"message":"Syntax Error: Expected Name, found <EOF>.","locations":[{"line":1,"column":45}]}]}  [HTTP 200]
{"calls":[]}
```

`bash examples/06-execution-model/verify.sh` runs all of this on both stacks and prints `PASS` only when both hold. It compares order and overlap of the 250 ms windows and never a duration, so a slow machine doesn't fail it.

Experiments:

- **Drop the operation name.** Send two operations with no `operationName`. Quarkus returns `errors` with no `data` and no source call. Python runs the first operation and makes one `booking.getCargo:ABC123` call.
- **Select `__typename` alone.** `{ __typename }` returns `Query` with an empty log.
- **Ask for a different `Accept` type.** An unknown field with `Accept: application/graphql-response+json` returns `200 application/graphql-response+json` on Quarkus and `200 application/json` on Python.

> **Decision**
>
> Parse, validation and coercion are where a document can be refused before any data is touched, so cost controls attach there. Write resolvers asynchronous end to end (`Uni` on Quarkus, `async def` on Python) so siblings overlap and latency follows the depth of the tree, not the call count. Keep ordered, dependent writes in one mutation, never in chained queries. Send `operationName` on every multi-operation document, and treat `errors` with absent or null `data` as the request-error signal, never the status line.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): "Implementing schema resolvers" covers the resolver execution model. Listed on the [Bibliography](../../bibliography/) page.
- [GraphQL specification](https://spec.graphql.org/): "Executing Requests", "Coercing Variable Values", "Executing Selection Sets" with "Normal and Serial Execution" and "Field Collection", and "Handling Execution Errors", in that order. The GraphQL over HTTP draft covers "Status Codes".
- *Cloud Native Design Patterns*, [Protocols in Depth](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/14-appendix-a-protocols/): the HTTP semantics and status-code conventions behind the GraphQL-over-HTTP comparison.
- [SmallRye GraphQL](https://quarkus.io/guides/smallrye-graphql): the Mutiny (`Uni`) resolver model the Quarkus examples use.
