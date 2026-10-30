---
title: "The execution model"
order: 6
part: "Execution: Resolvers, Queries & Mutations"
description: "What happens between a POST to /graphql and the JSON that comes back: parse, validate, coerce variables, then walk the selection set, with sibling fields running together, top-level mutation fields running one at a time, and every claim read off a source-call log on both stacks."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Walk a GraphQL request through its four stages: parse, validate, coerce variables, execute.
- Explain why sibling fields may run concurrently while top-level `Mutation` fields execute serially.
- Read a source-call log to verify, rather than assume, resolver ordering and overlap.
- Compare blocking and asynchronous resolver styles (a plain return value vs. `Uni`, a blocking `def` vs. `async def`) and their effect on thread and event-loop occupancy.
- Map the GraphQL-over-HTTP status-code recommendations to what SmallRye and Strawberry return in practice.

## Why this matters

The schema chapters described its types, its wrappers and the contract that keeps two stacks aligned. This chapter follows a request through the engine that serves it. A GraphQL server does not run a query the way a database runs SQL. It parses text, checks it against the schema, converts its inputs, and then calls ordinary functions, one per field, in an order the specification mostly leaves to the engine. Knowing that order tells you which calls a selection costs, which of them wait for each other, and what a failed request leaves behind.

The code is in `examples/06-execution-model/`. It builds on the existing schema example and changes where the data comes from: five sources (booking, routing, voyage, location, delivery) stand in for the services that own it, each call takes 250 ms, and every call is written to a log that the example serves at `/debug/source-calls`. `verify.sh` reads that log after each query, so each claim below about order and overlap is observed on both stacks. The log is a lab tool and is off unless `TRACKING_DEBUG_ENDPOINTS=true`.

{% include excalidraw.html file="06-request-phases" alt="A row of six boxes joined by arrows from left to right: POST /graphql carrying query, variables and operationName; Parse, text to a document; Validate, document against the schema; Coerce variables, JSON values to declared types; Execute, highlighted, which walks the selection and calls resolvers; and Response with data, errors or both. Dashed arrows run from Parse, Validate and Coerce variables down to a highlighted Request error box that reads errors, no data, and zero source calls. A double-headed arrow joins Execute to a Sources box listing booking, routing, voyage, location and delivery." caption="Figure 6.1: Three stages run before any resolver. A failure in one of them ends the request with errors, no data and no source calls; only Execute reaches the sources." %}

## A request is a document plus inputs

Over HTTP a request is a JSON object with three members: `query`, the document text; `variables`, a JSON object of inputs; and `operationName`, which says which operation to run. The document can hold several operations and any number of fragments. The server runs exactly one operation, chosen by the `GetOperation` step of "Executing Requests" in the [GraphQL specification](https://spec.graphql.org/): the named one, or the only one when the document holds a single operation and no name is given. With several operations and no name, the specification says to raise a request error.

The example sends `query A { cargo(trackingId: "ABC123") { trackingId } } query B { ... }` with no `operationName`. SmallRye rejects it with `Must provide operation name if query contains multiple operations.`, no `data` and no source call, as the specification describes. Strawberry 0.335.0 runs the first operation and answers `ABC123`, because its execution context takes the first operation's name when the request has none. Both answer `XYZ789` when `operationName` is `B`, and only `booking.getCargo:XYZ789` appears in the log. The portable habit is to send `operationName` whenever a document holds more than one operation. It also gives each request a name in logs and traces.

A request error is the specification's term for a failure before execution starts. The current edition says "request error" and "execution error", where older editions said "field error" for the second. The three stages below are where request errors come from.

## Parse

Parsing turns the text into a document: a tree of operations, selection sets, fields, arguments and fragments. The only thing it checks is syntax. An unclosed brace, a missing name or a stray character stops the request, and nothing after parsing runs.

```graphql
{ cargo(trackingId: "ABC123") { trackingId }
```

Quarkus answers `Unparseable input document` and omits `data`. Python answers `Syntax Error: Expected Name, found <EOF>.` with `"data":null`. The specification says `data` should not be present for a request error; Strawberry sends the key with a null value, so a client should test for absent or null. Both stacks answer HTTP 200 with `Accept: application/json`, and the log is empty on both, because no resolver was reached. A document that fails to parse also tells the server nothing about which fields it wanted, so there is nothing to execute partially.

## Validate

Validation checks the parsed document against the schema without touching any data. The specification lists the rules in its "Validation" section: every field exists on the type it is selected from, every object-typed field has a selection set and every leaf has none, arguments match their declared types, fragments are defined and used, fragment spreads do not form a cycle, and variables are declared, used and compatible with their positions. The type-system chapter showed three of these on the wire.

```graphql
{ cargo(trackingId: "ABC123") { ...A } }
fragment A on Cargo { ...B }
fragment B on Cargo { ...A }
```

A fragment cycle would make execution unbounded, so validation rejects it. Quarkus reports `Validation error (FragmentCycle@[A]) : Fragment cycles not allowed` for each fragment in the cycle. Python reports `Cannot spread fragment 'A' within itself via 'B'.` An unknown field, `cargo { weight }`, fails the same way. All three leave the log empty. Validation needs only the document and the schema, so a client can fix the document and send it again with no risk of having changed anything. It also costs CPU on every request, which is why persisted queries and query-cost limits both start here.

## Coerce variables

Variables arrive as JSON, and JSON has fewer types than GraphQL. Coercion converts each variable to the type its declaration names: a JSON string becomes a `TrackingId` through the scalar's input coercion, a missing optional variable takes its default, and a JSON `123` offered to a string scalar is an error. The section is "Coercing Variable Values", and it runs before execution because the engine will not call a resolver with an argument it cannot trust.

```graphql
query($t: TrackingId!) { cargo(trackingId: $t) { trackingId } }
```

With `{"t":123}`, Quarkus answers `Variable 't' has an invalid value: SRGQL000013: Expected type [String or class extending class com.patterncatalyst.shipping.tracking.TrackingId] but was [BigDecimal].` and Python answers `Variable '$t' has invalid value: Expected value of type 'TrackingId', but encountered error 'expected a string, got int'; found: 123.` Both fail before any source call. The literal form of the same mistake, `location(unLocode: 123)`, was rejected in validation under the type system's scalar-coercion rules, so a literal fails in the second stage and a variable in the third. The difference matters when you read a failure: a variable error names the variable, and the value that caused it is in the request body, not in the document.

## Execute: walking the selection set

Execution starts with the root selection set and the root value. The specification's algorithms, from "Executing Operations" down to "Executing Fields", reduce to a loop with three steps.

1. **Collect fields.** "Field Collection" groups the selection set by response key. Fields with the same key merge, fragments are expanded when their type condition applies, and `@skip` and `@include` drop the fields they exclude. Collection happens before any resolver runs, so a pruned field never costs a call.
2. **Resolve each field.** The resolver receives the parent value (the object the previous step produced), the field's arguments and the request context, and returns the field's value, or something that will become it.
3. **Complete the value.** "Value Completion" checks the result against the field's type. A leaf is serialized, a list is completed item by item, an object is walked with the sub-selection as its selection set and the value as its parent, and a null in a non-null position is an error that null propagation carries upward.

Figure 6.2 shows the walk for the query that the example's second check sends: `cargo { itinerary { legs { loadLocation { unLocode } } } delivery { transportStatus } }`.

{% include excalidraw.html file="06-field-walk" alt="A tree of resolver calls, left to right. A Query root value box leads to box 1, cargo, which calls booking.getCargo for ABC123. Two arrows labelled Cargo lead from box 1 to box 2, itinerary, which calls routing.getItinerary for ABC123, and to box 3, delivery, which calls delivery.getDelivery for ABC123. An arrow labelled Itinerary leads from box 2 to a plain box, legs, that makes no source call. Two arrows labelled Leg 0 and Leg 1 lead from legs to boxes 4 and 5, the loadLocation of each leg, which call location.getLocation for USNYC and DEHAM." caption="Figure 6.2: Field walk for one query. Each box is a resolver call and each edge label is the parent value the child receives. Boxes 2 and 3 start together, and so do 4 and 5." %}

Resolver 1 is `Query.cargo`. It calls `booking.getCargo` and returns a `Cargo`, which becomes the parent for `itinerary` and `delivery`. Neither field's resolver is passed the tracking id as an argument: each reads it from the parent. Resolver 2 returns an `Itinerary` whose `legs` list needs no call of its own, because the routing source returned the legs with the itinerary. Each `Leg` carries a voyage number and two UN/LOCODEs, and `loadLocation` turns the code into a `Location`. The first check in `verify.sh` shows the other side of the same rule: `cargo { trackingId description }` makes exactly one call, `booking.getCargo:ABC123`, because `description` is a property of the booking record and has no resolver of its own.

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
@strawberry.type
class Leg:
    load_un_locode: strawberry.Private[str]   # what routing returns; not in the schema

    @strawberry.field(description="Where the cargo is loaded.")
    async def load_location(self, info: Info[TrackingContext]) -> Location:
        return await info.context.location.get_location(self.load_un_locode)
```

In SmallRye a `@Source` parameter is the parent value, and the method lives in the `@GraphQLApi` class beside the root fields. A `Uni` is Mutiny's lazy single-value type: the method returns a description of the work, and the engine subscribes to it. The record components `Leg` uses for the codes are marked `@Ignore`, which keeps them out of the schema. In Strawberry the parent is `self`, `strawberry.Private` keeps a field out of the schema, and `info.context` is whatever the router's `context_getter` returned.

### One request id across every call

The source-call log is only useful if it can say which request a call belongs to. Each stack gets that id from a different place, and each has to take it at the right moment.

On Quarkus the id is `Context#getExecutionId()`, the SmallRye `Context` passed to the resolver as a parameter. A resolver reads it at method entry, while it is still running for its request, and passes it to the source as an argument. The continuation of a delayed `Uni` runs later and on a different thread, where request-scoped state is not guaranteed to be the same request's. On Python the id is a uuid4 created once per request:

```python
def get_context(calls: Annotated[SourceCalls, Depends(get_calls)]) -> TrackingContext:
    request_id = str(uuid.uuid4())
    return TrackingContext(request_id, BookingSource(calls, request_id), ...)

app.include_router(GraphQLRouter(schema, context_getter=get_context), prefix="/graphql")
```

Every resolver of the request sees the same `info.context`, so the five sources it holds are all bound to one id. The context has other uses, covered together with resolver arguments and the info object. The check `assert_single_request` confirms one id on every call of a query, and `assert_distinct_requests` confirms that two queries do not share one.

## Sibling fields may run in parallel

The REST/RPC comparison earlier mentioned that sibling fields may run concurrently. The wording of "Normal and Serial Execution" in the specification is that the executor can run the entries of a collected fields map "in whatever order it chooses (normally in parallel)", because field resolution is expected to be free of side effects. That is a permission, not a promise. Whether two siblings overlap depends on the engine and on how the resolvers are written, so the example measures it.

The second check sends the Figure 6.2 query and asserts three things from the log: `booking.getCargo` ends before `routing.getItinerary` and `delivery.getDelivery` start, the two overlap, and the two `getLocation` calls overlap. Figure 6.3 draws one run on Quarkus.

{% include excalidraw.html file="06-parallel-siblings" alt="A timeline with a horizontal axis marked 0, 250, 500 and 750 milliseconds and four lanes. In the booking lane a bar for getCargo ABC123 runs from 0 to about 250. In the routing lane a bar for getItinerary runs from about 255 to 506, and in the delivery lane a bar for getDelivery starts at about 257 and ends at about 516, so the two overlap. In the location lane two bars, USNYC and DEHAM, both run from about 514 to about 766. A separate dashed lane labelled sequential shows getItinerary from 0 to 250 followed by getDelivery from 250 to 500." caption="Figure 6.3: Sibling resolvers overlapping in time, drawn from the source-call log of one Quarkus run. The dashed lane shows the same two calls from blocking resolvers on one event loop." %}

The same query on the Python stack shows the same shape: after `getCargo` ends, `getItinerary` and `getDelivery` start together, and when they end, both `getLocation` calls start together. Total time follows the depth of the tree, three levels of 250 ms, and not the five calls. Doubling the number of siblings at one level would add nothing to the total, and adding a level would add 250 ms.

What makes siblings overlap is that the resolver gives control back while it waits. Both of the stacks' idioms do that, and each has a way to lose it.

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
async def call[T](self, request, source, op, key, lookup: Callable[[], T]) -> T:
    start_ms = _now_ms()
    try:
        await asyncio.sleep(self._latency)
        return lookup()
    finally:
        self._calls.append(SourceCall(request, source, op, key, start_ms, _now_ms()))
```

`Uni.deferred` delays the clock until the engine subscribes, `delayIt().by(...)` waits on a timer without holding a thread, and `eventually` writes the entry whether the call produced a value, a null or an error. The Python version does the same with `await asyncio.sleep` and a `finally`. The example wraps the delay in `afterLatency`, which applies the timer only when the configured latency is above zero. Both record `startMs` and `endMs` from a monotonic clock, so the checks compare them with `<` and `<=` and never subtract them.

Resolver style decides what a waiting call costs. These two observations are not part of `verify.sh`.

- **Strawberry, `def` resolvers that block.** The same two resolvers written as plain `def` with a blocking sleep run one after the other, 250 ms each, on the event loop, and a blocking call also holds every other request on that loop for as long as it runs. graphql-core awaits coroutines together, and a function that never yields has no point at which to overlap.
- **SmallRye, resolvers that return a plain value.** These are blocking methods, and SmallRye gives each call its own worker thread (`executor-thread-1` and `-2` in the run). They overlap, with a worker thread held for the length of each call. A `Uni` resolver is subscribed on a Vert.x event-loop thread and resumes there after the timer, so it holds no thread while it waits.

So the stacks differ in a way that matters when the pool is small: Quarkus runs a blocking resolver on a worker thread and spends a thread per call, and on Python a blocking resolver occupies the event loop. In both, a resolver that is asynchronous end to end is the one that scales with the number of concurrent requests instead of with the number of threads. The DataLoader pattern turns the next step, many sibling calls that want the same data, into batching.

## Top-level mutation fields run serially

For a mutation the specification changes the rule. "Normal and Serial Execution" says the fields of a mutation's root selection set are executed serially, in the order written, and each field is executed completely, nested selections included, before the next begins. Nothing below that level changes: the fields inside one mutation field's payload are siblings again and may run together.

```graphql
mutation {
  a: registerHandlingEvent(input: { ... }) { cargo { delivery { transportStatus } } }
  b: registerHandlingEvent(input: { ... }) { cargo { delivery { transportStatus } } }
}
```

The aliases are needed because two fields with one name and different arguments would collide. The reason for the serial rule is that mutations have side effects, and `b` may depend on what `a` wrote. When `a` registers a load event and `b` registers the matching unload, `b` is only valid if `a` has landed, and `a`'s payload shows the state before `b` ran. Query fields get no such guarantee, which is why a client that needs ordering has to use a mutation. Figure 6.4 draws the rule.

{% include excalidraw.html file="06-serial-mutation" alt="A timeline with two lanes for the mutation fields a and b, both named registerHandlingEvent. In lane a an append event bar is followed by a payload re-read bar. A vertical line and an amber arrow marked a is finished lead to lane b, where an append event bar and a payload re-read bar start only after a is complete. A third lane, if a and b were query fields, shows two dashed bars labelled a and b starting together." caption="Figure 6.4: Top-level mutation fields run serially: b starts only after a, payload included, is complete. The timing is schematic; the mutations chapter measures it." %}

graphql-java, the engine under SmallRye, has a serial execution strategy for mutations (`AsyncSerialExecutionStrategy`), and graphql-core runs the root fields of a mutation through `execute_fields_serially`. This chapter's example has no mutation yet, so it does not assert any of this. The mutations chapter adds `registerHandlingEvent` and asserts the rule on both stacks with two independent observations: the order of appends in the source-call log, and the payload of `a` showing state that `b` has not touched.

## Assembling the response

Execution ends with a map: the response keys, in order, each holding the completed value of its field. The specification's "Serialized Map Ordering" says the response map should follow the order of the selection set, and a response key is the alias when the field has one and the field name otherwise.

```graphql
{ b: cargo(trackingId: "XYZ789") { trackingId } a: cargo(trackingId: "ABC123") { trackingId } }
```

Both stacks answer `{"data":{"b":{"trackingId":"XYZ789"},"a":{"trackingId":"ABC123"}}}`, with `b` before `a`, although `a` sorts first alphabetically and either `getCargo` call might have finished first. The log shows the two calls overlapping, so completion order is not under the client's control. Selection order is, and that is the only order a client can rely on. `verify.sh` asserts the key order with `json_keys`, which reads keys in document order.

{% include excalidraw.html file="06-response-assembly" alt="Two boxes on the left, Finished 1st for a: cargo ABC123 and Finished 2nd for b: cargo XYZ789. Amber arrows cross to two slot boxes in the middle, labelled b, first in the selection, and a, second in the selection. Both slots point to a box on the right showing data with keys b and a in selection order, named by alias. A dashed box below it, errors with message and path, points up to the data box with the note path names the failed field, and is marked as present only when a resolver failed." caption="Figure 6.5: Resolver results flow into data in selection order, with aliases as keys. errors sits beside data and names the failed field by path." %}

`errors` sits beside `data`. When a resolver fails, the spec's "Handling Execution Errors" has the engine record an error whose `path` names the failed field, null the field, and continue with its siblings, so partial `data` comes back with `errors`. Null propagation carried that null upward through non-null fields, and error handling turns these errors into a contract. A request error has no `data` at all, as the first three stages showed.

## Meta fields cost nothing

Fields whose names begin with two underscores belong to the engine, not to a resolver. `__typename` returns the name of the object type the selection set is applied to, and `__schema` and `__type` answer from the schema itself. `{ __typename }` returns `{"data":{"__typename":"Query"}}` on both stacks with an empty source-call log, which is the useful property of a meta field: it is answered after validation without a resolver, so it can sit in any selection set, including on an interface where resolving the runtime type relies on it, and it never adds a call. It is also a cheap way to check that a deployment parses, validates and executes a request end to end. Introspection is the same mechanism with a larger payload, and disabling it is covered under transport security.

## Status codes

GraphQL-over-HTTP, the working draft in the [Bibliography](../../bibliography/), takes up status codes in "Status Codes". For an `application/graphql-response+json` response it makes one rule mandatory: a result without a `data` entry is a request error, and the server must answer with a 4xx or 5xx status. The codes it recommends are 400 when the document cannot be parsed, and 422 when validation fails, when the operation cannot be determined or when variables cannot be coerced. A result that executed is 200 without errors, and 294 (a code the draft defines for partial success) when `errors` sits beside `data`. A server must also support that media type. A client that accepts only `application/json` is a legacy client under the draft, and the draft asks servers to apply the same status codes to it, except that a 2xx response keeps the `application/json` media type. The point of the status code is that a gateway, a load balancer or a log can tell a rejected request from an executed one without reading the body.

The two stacks, as observed by `verify.sh`, answer as follows:

| Request | Quarkus | Python |
|---|---|---|
| Parse error, `Accept: application/json` | 200, `data` absent | 200, `"data":null` |
| Unknown field, `Accept: application/json` | 200 | 200 |
| Unknown field, `Accept: application/graphql-response+json` | 200 with that content type | 200 with `application/json` |

Every request error in this chapter came back as HTTP 200: parse, validation and coercion on both stacks, and the missing `operationName` on Quarkus, the one stack that raised it. Quarkus acknowledges the new media type in the `Content-Type` header and answers 200 with no `data`; the draft recommends a 4xx for that case. Strawberry answers `application/json`, the media type the draft assigns to a legacy client. A client therefore reads the body to detect a request error on either stack: `errors` present and `data` absent or null. A gateway in front of the service that wants the 4xx semantics can add them. The observed values belong to the pinned versions, SmallRye GraphQL 2.18.5 and Strawberry 0.335.0, and `verify.sh` asserts them so that a change on upgrade is visible.

## On the wire

Start the stack. Quarkus is on `8160` and Python on `8161`, and compose sets `TRACKING_SOURCE_LATENCY_MS=250` and `TRACKING_DEBUG_ENDPOINTS=true`. Reset the log, send a query that selects only a booking field, and read the log:

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

One call, to the one source whose data the selection needs. Now the Figure 6.2 query, after another reset:

```bash
curl -s localhost:8160/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { itinerary { legs { loadLocation { unLocode } } } delivery { transportStatus } } }"}'
curl -s localhost:8160/debug/source-calls
```

```json
{"data":{"cargo":{"itinerary":{"legs":[{"loadLocation":{"unLocode":"USNYC"}},{"loadLocation":{"unLocode":"DEHAM"}}]},"delivery":{"transportStatus":"ONBOARD_CARRIER"}}}}
{"calls":[{"request":"16323002361","source":"booking","op":"getCargo","key":"ABC123","startMs":509,"endMs":760},{"request":"16323002361","source":"routing","op":"getItinerary","key":"ABC123","startMs":762,"endMs":1013},{"request":"16323002361","source":"delivery","op":"getDelivery","key":"ABC123","startMs":763,"endMs":1025},{"request":"16323002361","source":"location","op":"getLocation","key":"USNYC","startMs":1021,"endMs":1272},{"request":"16323002361","source":"location","op":"getLocation","key":"DEHAM","startMs":1023,"endMs":1274}]}
```

The request id, the `startMs` and `endMs` values differ on every run and on the Python stack, where the id is a uuid4. What stays the same is the shape: `booking.getCargo` ends before `getItinerary` and `getDelivery` start, those two overlap, and the two `getLocation` calls overlap. A failed request leaves the log empty. With the unclosed-brace document from the Parse section:

```bash
curl -s -X DELETE localhost:8161/debug/source-calls
curl -s -w '  [HTTP %{http_code}]\n' localhost:8161/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId }"}'
curl -s localhost:8161/debug/source-calls
```

```text
{"data":null,"errors":[{"message":"Syntax Error: Expected Name, found <EOF>.","locations":[{"line":1,"column":45}]}]}  [HTTP 200]
{"calls":[]}
```

| Check | Expected |
|---|---|
| `cargo { trackingId description }` | `Palletized electronics`; the log is exactly `booking.getCargo:ABC123`; no `routing.*` or `delivery.*` calls |
| `cargo { itinerary { legs { loadLocation } } delivery }` | `USNYC`, `DEHAM`, `ONBOARD_CARRIER`; exactly the five calls above; `getCargo` before `getItinerary` and before `getDelivery`; `getItinerary` before `getLocation:USNYC`; `getItinerary` overlaps `getDelivery`; the two `getLocation` calls overlap; one `request` id |
| `{ b: cargo(XYZ789) ... a: cargo(ABC123) ... }` | `data` keys `b,a`; the two `getCargo` calls overlap; one `request` id; a later request has a different one |
| parse error, unknown field `weight`, fragment cycle, `{"t":123}` for `TrackingId!` | `errors`, no `data`, zero source calls; HTTP 200 on both stacks |
| unknown field with `Accept: application/graphql-response+json` | Quarkus `200 application/graphql-response+json`; Python `200 application/json` |
| two operations, no `operationName` | Quarkus: `errors`, no `data`, zero calls. Python: runs the first operation, one `booking.getCargo:ABC123` call |
| the same document, `operationName` `B` | `XYZ789`; the log is exactly `booking.getCargo:XYZ789` |
| `{ __typename }` | `Query`; zero calls |
| `__type` of `TrackingId`, `UnLocode`, `DateTime` | `SCALAR`; `specifiedByURL` null, `https://unece.org/trade/uncefact/unlocode`, `https://www.rfc-editor.org/rfc/rfc3339` |
| live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice); the debug endpoints add nothing to it |

`bash examples/06-execution-model/verify.sh` runs all of it on both stacks and prints `PASS` only when both hold. It asserts order and overlap of 250 ms windows and never a duration, so a slow machine does not fail it.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>The execution model is where the <em>operational and security cost</em> axis of the decision framework becomes concrete. A GraphQL endpoint runs whatever document a caller sends, and parse, validation and coercion are the three places where that work can be refused before any data is touched, which is also where depth limits, cost limits and persisted queries attach later. The <em>aggregation across sources</em> axis shows in the log: one query fans out to several owners, and the latency of the answer is the depth of the tree, so an asynchronous resolver style that lets siblings overlap is what makes aggregation affordable. The <em>read and write balance</em> axis appears in the serial rule, a cost that only mutations pay, and a reason to keep ordered, dependent writes in mutations rather than in chained queries. The <em>contract and evolution style</em> axis shows in the status codes: the draft recommends a 4xx for a request error and both stacks answer 200, so the contract with clients is the body of the response, and the tracking view treats errors and absent data as the signal and never the status line. The tracking view sends <code>operationName</code> on every multi-operation document, because one stack rejects an ambiguous request and the other runs the first operation.</p></div>

## Review

- A request runs through four stages in order: parse checks syntax, validate checks the document against the schema, coerce variables converts JSON inputs to their declared types, and execute walks the selection set and calls resolvers. A failure in any of the first three stages produces a request error with no `data` and zero source calls.
- Sibling fields are permitted, not guaranteed, to run concurrently under the specification's "Normal and Serial Execution" wording, and both stacks' examples show them overlapping in practice. Top-level `Mutation` fields execute serially instead, each one finishing its nested selection before the next begins, because a later field may depend on what an earlier one wrote.
- The example's source-call log, read from `/debug/source-calls`, records a start and end timestamp for every source call, and `verify.sh` asserts ordering and overlap from those timestamps rather than assuming behavior from elapsed time.
- A resolver that returns a `Uni` or is declared `async def` yields control while it waits, which is what lets sibling resolvers overlap; a blocking resolver instead holds a worker thread for its duration on Quarkus or occupies the whole event loop on Python, so resolver style sets how the server scales with concurrent requests.
- The GraphQL-over-HTTP draft recommends a 4xx or 5xx status for a request error, but SmallRye and Strawberry both answer HTTP 200 for every request error this chapter observed, so a client has to read `errors` and `data` in the body to detect a failure instead of trusting the status line.

## Where this goes next

This chapter followed one request through parse, validate, coerce and execute, showed which calls a selection makes and which of them overlap, and recorded how each stack reports a request that never reached a resolver. The source-call log and the asynchronous sources stay in the example from here on.

Looking inside a resolver covers its parent, arguments, context and info, how a computed field such as `Delivery` is derived, how `@include` and `@skip` prune calls before they happen, and what it costs when two aliases fetch the same voyage twice. That repeated fetch stays visible until batching with DataLoaders removes it. The first mutation example asserts the serial rule from this chapter on both stacks, and execution errors get a contract through the error-handling design.

For the formal definitions, read "Executing Requests", "Coercing Variable Values", "Executing Selection Sets" with its "Normal and Serial Execution" and "Field Collection" subsections, and "Handling Execution Errors" in the [GraphQL specification](https://spec.graphql.org/), and "Status Codes" in GraphQL over HTTP. Samer Buna's *GraphQL in Action* covers the same ground in "Introduction to GraphQL" and "Implementing schema resolvers"; the book is listed on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): "Implementing schema resolvers" covers the resolver execution model traced here with a source-call log.
- Cloud Native Design Patterns: [Protocols in Depth](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/14-appendix-a-protocols/) appendix, for the HTTP semantics and status-code conventions behind the GraphQL-over-HTTP comparison.
- [GraphQL specification: Execution](https://spec.graphql.org/): "Executing Requests," "Coercing Variable Values" and "Handling Execution Errors," in that order.
- [SmallRye GraphQL](https://quarkus.io/guides/smallrye-graphql): the Mutiny (`Uni`)-based resolver model the Quarkus examples here use.
