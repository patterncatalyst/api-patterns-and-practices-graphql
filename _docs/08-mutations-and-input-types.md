---
title: "Mutations and input types"
order: 8
part: "Execution: Resolvers, Queries & Mutations"
description: "registerHandlingEvent takes a typed input object, rejects malformed input as a request error and broken domain rules as userErrors data, returns the event with a recomputed delivery, runs aliased mutation fields in order, and stays safe to retry with an idempotency key."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Declare a typed `RegisterHandlingEventInput` input object and explain why input types can only hold scalars, enums, and other inputs.
- Distinguish a coercion failure (caught by the engine before any resolver runs) from a domain failure returned as `userErrors` data.
- Design a mutation payload (`RegisterHandlingEventPayload`) that re-reads derived state like `Cargo.delivery` in the same round trip.
- Rely on the engine's serial execution of top-level mutation fields to run two aliased `registerHandlingEvent` calls in document order.
- Make a mutation safe to retry with a client-supplied `idempotencyKey` checked and inserted atomically in one step.

## Why this matters

The tracking view has one mutation, `registerHandlingEvent`, and it carries most of what a write in GraphQL needs: a typed input object, two ways to say no, a payload that hands the changed cargo back, the engine's rule that mutation fields run in order, and a key that makes a retry safe. The handling data is an in-memory store that requests write to, and `Query.node` resolves `evt_*` ids.

## One write, owned elsewhere

The service that holds the data enforces its validation, idempotency and transactional rules. A second implementation in an aggregation layer is a second place to get them wrong, so the write surface stays small and booking a cargo stays a REST call.

`registerHandlingEvent` is the exception because of what the caller wants back. A terminal app that reports "unloaded at Hamburg" also wants the cargo's new state, and a mutation returns it in the same round trip, shaped by the caller's selection. The mutation validates, hands the event to the store through `handling.appendEvent`, and reads the result back through the sources the queries use. It never becomes a second system of record.

## Input types

An input type is an object type for arguments, declared with the keyword `input`. Its fields are data, not resolvers, so a field can hold only a scalar, an enum or another input type. Object fields take arguments and run resolvers, interfaces and unions need a runtime type to pick a branch, and none of that means anything for a value that arrives as JSON.

```graphql
input RegisterHandlingEventInput {
  trackingId: TrackingId!
  type: HandlingEventType!
  location: UnLocode!
  voyageNumber: String
  completionTime: DateTime!
  idempotencyKey: String
}
```

Four fields are required: which cargo, what kind of handling, where, and when. `voyageNumber` is optional because a `RECEIVE` has no voyage, and `idempotencyKey` because a client that never retries doesn't need one. `location` is a `UnLocode`, not a `Location`: an input names a place and the server resolves it.

An absent field and an explicit `null` are different inputs. This mutation treats them alike (`"voyageNumber": null` on a `LOAD` gets `VOYAGE_REQUIRED`, as when the field is omitted), but the stacks differ in how they let you tell them apart.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Input("RegisterHandlingEventInput")
@Description("Input for `Mutation.registerHandlingEvent`.")
public record RegisterHandlingEventInput(
        @NonNull @Description("The cargo that was handled.") TrackingId trackingId,
        @NonNull @Description("What kind of handling occurred.") HandlingEventType type,
        @NonNull @Description("Where it occurred.") UnLocode location,
        @Description("The voyage number; required for LOAD and UNLOAD, forbidden otherwise.") String voyageNumber,
        @NonNull @Description("When the handling actually happened.") Instant completionTime,
        @Description(
                        "Client-supplied key making retries safe: a repeated request with the same key returns the originally recorded event instead of recording a second one.")
                String idempotencyKey) {}
```

```python
@strawberry.input(description="Input for `Mutation.registerHandlingEvent`.")
class RegisterHandlingEventInput:
    tracking_id: TrackingId = strawberry.field(description="The cargo that was handled.")
    type: HandlingEventType = strawberry.field(description="What kind of handling occurred.")
    location: UnLocode = strawberry.field(description="Where it occurred.")
    # Optional input fields are strawberry.Maybe: an absent field arrives as
    # None, a sent value as Some(value), and the SDL prints neither a default
    # nor "= null" (a plain `str | None = None` prints `= null`).
    voyage_number: strawberry.Maybe[str | None] = strawberry.field(
        description="The voyage number; required for LOAD and UNLOAD, forbidden otherwise."
    )
    completion_time: datetime = strawberry.field(
        description="When the handling actually happened."
    )
    idempotency_key: strawberry.Maybe[str | None] = strawberry.field(
        description=(
            "Client-supplied key making retries safe: a repeated request with the same key "
            "returns the originally recorded event instead of recording a second one."
        )
    )
```

SmallRye binds a Java record directly. It derives an input type's name from the class and appends `Input`, so `RegisterHandlingEventInput` would become `RegisterHandlingEventInputInput`; the explicit `@Input("RegisterHandlingEventInput")` pins the contract's name. A field is required when it is `@NonNull`.

Strawberry takes the opposite default: a field is required unless the annotation says `| None`. Writing `voyage_number: str | None = None` would print `voyageNumber: String = null` in the SDL, and the conformance diff classifies an added default as a dangerous change. `strawberry.Maybe[str | None]` with no default prints a plain `String` and keeps "not sent" (`None`) apart from "sent" (`Some(value)`), which the Strawberry documentation recommends for optional input fields. This mutation unwraps both to `None`.

## Coercion: the first line of defense

Before any resolver runs, the engine checks the input against its type: "Coercing Variable Values" for variables and "Input Coercion" for literals in the specification. It rejects what the type system can express.

| Input | What is wrong |
|---|---|
| no `type` | a required field is missing |
| `"type": "TELEPORT"` | not a value of `HandlingEventType` |
| `"location": 123` | `UnLocode` accepts only a string |
| `"completionTime": "yesterday"` | not an RFC 3339 date-time |
| an extra field `"weightKg": 1` | `RegisterHandlingEventInput` has no such field |

Each comes back with errors and no data, and no resolver ran, so nothing was looked up, validated or written. The check belongs to the engine, so it is the same on any mutation added later. The resolver author owes it only the type declaration.

Quarkus omits the `data` key, as the specification says a request error should. Strawberry sends `"data": null`. Both answer HTTP 200.

The date-time case differs most. Strawberry rejects `yesterday` during coercion with one error naming the scalar, whether it is a variable or a literal. SmallRye converts the `DateTime` inside an input object later, when it binds the argument to the record, which is after validation and inside execution. The response carries two errors, one quoting the input object and one reporting that the non-null `registerHandlingEvent` produced null, and `data` is `null`. The outcome matches the other four: errors, no data, no write. A client should not depend on the shape. A design that needs a clean message for a bad date-time declares the field as `String`, validates it in the resolver and returns a `userError`.

## Domain validation as data

Coercion knows types. It doesn't know that `NOPE99` is not a cargo or that a `LOAD` needs a voyage. Those domain rules fail differently: the response is a normal result in which `userErrors` is not empty.

```graphql
type UserError {
  code: UserErrorCode!
  message: String!
  field: [String!]
}
```

Each failure has a stable `code` a program switches on, a `message` a person reads, and a `field` path that starts at `input`, the argument's name. The path is `null` when the failure concerns the input as a whole. The resolver collects every applicable failure in a fixed order, so a client fixes a form in one round trip.

| Order | Code | Rule |
|---|---|---|
| 1 | `UNKNOWN_CARGO` | no cargo has that tracking id |
| 2 | `UNKNOWN_LOCATION` | no location has that UN/LOCODE |
| 3 | `VOYAGE_REQUIRED`, `VOYAGE_NOT_ALLOWED`, `UNKNOWN_VOYAGE` | a `LOAD` or `UNLOAD` needs a voyage that exists; the other types must not name one |
| 4 | `INVALID_COMPLETION_TIME` | after the server clock |

`NOPE99` at `ZZZZZ` returns `UNKNOWN_CARGO` at `["input","trackingId"]` and then `UNKNOWN_LOCATION` at `["input","location"]`, on both stacks. `handlingEvent` and `cargo` are null and nothing is written. The three lookups run together, so a rejected request costs one source window, not three.

{% include excalidraw.html file="08-errors-vs-usererrors" alt="Two panels side by side. Left, a coercion failure for a type of TELEPORT: data is absent on Quarkus and null on Strawberry, errors[0] has a message and locations but no path, and the engine raises it before the resolver runs. Right, a domain failure for a LOAD without a voyage: data.registerHandlingEvent has handlingEvent and cargo null and userErrors[0] with code VOYAGE_REQUIRED and field input, voyageNumber, returned by the resolver with no errors key." caption="Figure 8.1: Two kinds of failure, two places in the response. The engine reports a malformed request in errors; the resolver reports a refused input in userErrors." %}

Why not throw and let the failure appear in `errors`? The two arrays mean different things. `errors` says the request couldn't run as written or the server failed: a developer's problem, usually the same for every user, and something a monitor counts. `userErrors` says the server understood the request and refused this input: a user's problem, expected, and part of the contract. A typed list lets a client render `VOYAGE_REQUIRED` next to the voyage field, where an exception message is text to display or parse.

## The payload and the re-read

A mutation returns a payload type, not the bare event. `RegisterHandlingEventPayload` has `handlingEvent`, `cargo` and `userErrors`. On success the first two are set and `userErrors` is `[]`; on a refusal it is the other way around.

`cargo` is why the mutation is in the graph. `Cargo.delivery` is a resolver that derives the delivery state from `handling.listEvents` and the itinerary, and the payload's `cargo` is an ordinary `Cargo`. The write happens first, then the engine resolves the payload's fields, so `delivery` reads the store after the new event is in it. An `UNLOAD` at Hamburg on `V100S` moves `ABC123` from `ONBOARD_CARRIER` to `IN_PORT`, and the next expected activity from `UNLOAD` at `DEHAM` to `LOAD` at `DEHAM` on `V200E`. The client gets the new state without a second request and without computing it.

{% include excalidraw.html file="08-mutation-flow" alt="A row of seven boxes from left to right: Variables, Input coercion, Domain validation, Key lookup, appendEvent, Re-read and Payload. Dashed arrows lead down from Input coercion to a box labelled errors and from Domain validation to a box labelled userErrors, both with nothing written. An arrow leads down from Key lookup to a box labelled Key hit, the original event, nothing written, and from there up to Re-read." caption="Figure 8.2: The path of one registerHandlingEvent call. Coercion belongs to the engine; validation, lookup, append and re-read run in the resolver, and a key hit skips the append." %}

The re-read has a cost. A successful registration makes a lookup window for the cargo, location and voyage together, a window for the key, a window for the append, and then the payload's own reads: `listEvents` and `getItinerary` for the delivery, and the event's location and voyage. Each costs 250 ms here. A client that needs only an acknowledgment selects `handlingEvent { id }`, and the delivery is never derived, because an unselected field costs nothing.

The event is a `Node`, so `node(id: "evt_3")` refetches it. `HandlingEvent.cargo` is nullable: it is null when the cargo service is unavailable, which keeps the event usable when its cargo is not.

## Mutation fields run in order

The specification's "Normal and Serial Execution" says the top-level fields of a mutation run one at a time, in the order written, each completely before the next. Two aliased fields in one document show it.

```graphql
mutation($a: RegisterHandlingEventInput!, $b: RegisterHandlingEventInput!) {
  a: registerHandlingEvent(input: $a) { handlingEvent { id } cargo { delivery { transportStatus ... } } }
  b: registerHandlingEvent(input: $b) { handlingEvent { id } cargo { delivery { transportStatus ... } } }
}
```

Field `a` loads `ABC123` onto `V200E` at Hamburg and `b` unloads it at Rotterdam, which is only meaningful once `a` has landed. The source-call log shows the order:

```text
findByIdempotencyKey   k-002  +   0 to + 251
appendEvent            evt_4  + 251 to + 502
listEvents             ABC123 + 506 to + 757
findByIdempotencyKey   k-003  +1015 to +1265
appendEvent            evt_5  +1265 to +1516
listEvents             ABC123 +1520 to +1771
```

`b`'s key lookup starts after `a`'s append ends. The payloads agree: `a`'s `cargo.delivery` is `ONBOARD_CARRIER` on `V200E` with next activity `UNLOAD` at `NLRTM`, where an engine that ran `b` first would show `IN_PORT` and `CLAIM`. SmallRye's graphql-java runs the mutation root with a serial strategy and Strawberry's graphql-core uses `execute_fields_serially`.

Below the root nothing is serial: fields inside `a`'s payload are siblings again and may overlap. Query fields have no such guarantee. A client that needs ordered writes sends them in one mutation, and two mutations in two requests have no ordering at all.

## Retries and idempotencyKey

A client sends a request, the server records the event, the response is lost, and the client retries on timeout. Without help the store holds two events for one handling, and because the duplicate is the new last event, the cargo's derived state may change too.

**`idempotencyKey` is a string the client chooses and repeats on every retry of the same intent. A repeated request with the same key returns the originally recorded event instead of recording a second one.** The implementation has two steps, and the second matters.

1. **Look the key up.** `handling.findByIdempotencyKey` returns the event the key already produced. A hit skips the write.
2. **Insert only if absent, atomically.** `handling.appendEvent` checks the key and inserts in one indivisible step. The lookup and the insert are separate calls, and two requests that arrive together can both miss the lookup, so only the atomic step can be trusted.

{% include codetabs.html langs="Quarkus|Python" %}

```java
    /**
     * Records the event. With a key, a second call with the same key returns the
     * first event and writes nothing; without one, every call writes.
     */
    public Appended append(NewHandling handling, String idempotencyKey) {
        if (idempotencyKey == null) {
            return new Appended(insert(handling, now()), true);
        }
        AtomicBoolean created = new AtomicBoolean();
        HandlingRecord event = byIdempotencyKey.computeIfAbsent(idempotencyKey, key -> {
            created.set(true);
            return insert(handling, now());
        });
        return new Appended(event, created.get());
    }
```

```python
    async def append(self, handling: NewHandling, idempotency_key: str | None) -> Appended:
        """Record the event. With a key, a second call with the same key returns
        the first event and writes nothing; without one, every call writes."""
        async with self._lock:
            if idempotency_key is not None and (
                existing := self._by_idempotency_key.get(idempotency_key)
            ):
                return Appended(existing, created=False)
            event = self._insert(handling, _now())
            if idempotency_key is not None:
                self._by_idempotency_key[idempotency_key] = event
            return Appended(event, created=True)
```

`ConcurrentHashMap.computeIfAbsent` runs its function at most once per key, so exactly one caller creates the event and the others receive it. On Python the `asyncio.Lock` serializes the section. Nothing awaits between the check and the insert, so the event loop would already make it indivisible; the lock keeps the invariant true the day someone adds an `await` there, such as a database call.

Eight identical requests fired at once with one key all return the same event, and the log holds eight key lookups and exactly one append. The lookups run inside one source window, before the write lands, so several miss. The lookup alone would have written eight events.

{% include excalidraw.html file="08-idempotent-replay" alt="A timeline with three lanes. First request with key k-001: a lookup misses, appendEvent writes evt_3, and the response is lost. A retry arrow leads to the second lane, where a lookup with the same key hits evt_3 and the re-read returns it; the store holds evt_3 only. The third lane, a retry without a key, has no lookup and appendEvent writes evt_4; the store holds evt_3 and evt_4." caption="Figure 8.3: The same retry with and without a key. With one, the second request becomes a read; without one, the store cannot tell a retry from a second event." %}

A replay returns the original even when the retry differs: `k-001` with a `completionTime` of `16:00` returns `evt_3` with its original `15:00`. A client that reuses a key for a different intent gets the old event with no signal that the input differed. A stricter server compares the stored input and rejects a mismatch; this one doesn't. A request with no key gets a new event each time. The key space is one global map that never expires. A production store scopes a key to the caller, expires it after a window, and keeps the key and the event in the same transaction.

## Mutations and HTTP

GraphQL over HTTP allows a query on `GET`, with the query and variables in the URL, but not a mutation. A server must refuse a mutation received that way with a 4xx status and halt execution, and it is recommended to answer 405 (Method Not Allowed) with an `Allow` header, which RFC 9110 requires of every 405. `GET` is safe, so proxies, prefetchers and caches may repeat it or answer it from memory, and a state change must never hide behind it.

| | Status | Body | Executed |
|---|---|---|---|
| Quarkus | 405 | empty, no `Allow` header | no |
| Python | 400 | text, `mutations are not allowed when using GET` | no |

Both meet the mandatory part: a 4xx and no execution. It makes no difference to a client that sends mutations by `POST`, as every GraphQL client library does. It matters to a gateway or cache in front of the service.

## Naming and shape conventions

Four habits keep a mutation's evolution additive.

- **Verb then noun.** `registerHandlingEvent` names the action, and the types follow: `RegisterHandlingEventInput`, `RegisterHandlingEventPayload`.
- **One `input` argument.** A new optional field on the input is an additive change, a long argument list is awkward to pass and validate, and the `field` path in a `UserError` reads `input` and then the field name.
- **A payload per mutation.** Returning `Boolean` or the bare event leaves no room for `userErrors` or the cargo, and adding them later changes the return type, which breaks clients.
- **A key you control for retries.** The Relay convention's `clientMutationId` is echoed back to correlate a response with a request but doesn't make a retry safe. `idempotencyKey` does, so the tracking view uses it and leaves `clientMutationId` out.

Adding a required field to an input is a breaking change and adding an optional one is safe, which is why `voyageNumber` and `idempotencyKey` are optional from the start.

> **🤖 Explore with your agent**
>
> "In `examples/08-mutations/`, add a `CANCEL_HANDLING` value to `HandlingEventType` and a `NOT_CANCELLABLE` value to `UserErrorCode`. Reject a cancel for a cargo with no events as a `userErrors` entry at `["input","trackingId"]`, not as a thrown error, and keep malformed input rejected by coercion. Return the recomputed `Cargo.delivery` in `RegisterHandlingEventPayload` and keep `idempotencyKey` replay working on both the Quarkus and Python stacks."
>
> Check: send a `CANCEL_HANDLING` for `XYZ789`, which has no events, on ports 8180 and 8181. The reply carries `userErrors` with code `NOT_CANCELLABLE` and no `errors` key, and `curl localhost:8180/debug/source-calls` shows no `appendEvent`.

## Build, run, observe

Quarkus is on `8180` and Python on `8181`, and the store starts with `evt_1` and `evt_2` on `ABC123`.

```bash
docker compose -f examples/08-mutations/compose.yaml up -d --build
Q='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id type completionTime } cargo { delivery { transportStatus lastKnownLocation { unLocode } currentVoyage { number } nextExpectedActivity { type location { unLocode } voyage { number } } } } userErrors { code field message } } }'
reg() { curl -s localhost:8180/graphql -H 'Content-Type: application/json' -d "$(python3 -I -c 'import json,sys; print(json.dumps({"query": sys.argv[1], "variables": {"i": json.loads(sys.argv[2])}}))' "$Q" "$1")"; echo; }
```

A coercion failure first, with a value the enum doesn't have:

```bash
reg '{"trackingId":"ABC123","type":"TELEPORT","location":"DEHAM","completionTime":"2026-10-09T15:00:00Z"}'
```

```json
{"errors":[{"message":"Variable 'i' has an invalid value: Invalid input for enum 'HandlingEventType'. No value found for name 'TELEPORT'","locations":[{"line":1,"column":10}],"extensions":{"classification":"ValidationError"}}]}
```

Python answers `{"data":null,"errors":[{"message":"Variable '$i' has invalid value at .type: Value 'TELEPORT' does not exist in 'HandlingEventType' enum.", ...}]}`: the same failure, a different message. Then two domain failures, which both stacks answer byte for byte:

```bash
reg '{"trackingId":"ABC123","type":"LOAD","location":"DEHAM","completionTime":"2026-10-09T15:00:00Z"}'
reg '{"trackingId":"NOPE99","type":"CUSTOMS","location":"ZZZZZ","completionTime":"2026-10-09T15:00:00Z"}'
```

```json
{"data":{"registerHandlingEvent":{"handlingEvent":null,"cargo":null,"userErrors":[{"code":"VOYAGE_REQUIRED","field":["input","voyageNumber"],"message":"LOAD events must name a voyage."}]}}}
{"data":{"registerHandlingEvent":{"handlingEvent":null,"cargo":null,"userErrors":[{"code":"UNKNOWN_CARGO","field":["input","trackingId"],"message":"No cargo has tracking id NOPE99."},{"code":"UNKNOWN_LOCATION","field":["input","location"],"message":"No location has UN/LOCODE ZZZZZ."}]}}}
```

A success with a key, then the same request with a different `completionTime`:

```bash
reg '{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z","idempotencyKey":"k-001"}'
reg '{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T16:00:00Z","idempotencyKey":"k-001"}'
```

```json
{"data":{"registerHandlingEvent":{"handlingEvent":{"id":"evt_3","type":"UNLOAD","completionTime":"2026-10-09T15:00:00Z"},"cargo":{"delivery":{"transportStatus":"IN_PORT","lastKnownLocation":{"unLocode":"DEHAM"},"currentVoyage":null,"nextExpectedActivity":{"type":"LOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V200E"}}}},"userErrors":[]}}}
{"data":{"registerHandlingEvent":{"handlingEvent":{"id":"evt_3","type":"UNLOAD","completionTime":"2026-10-09T15:00:00Z"},"cargo":{"delivery":{"transportStatus":"IN_PORT","lastKnownLocation":{"unLocode":"DEHAM"},"currentVoyage":null,"nextExpectedActivity":{"type":"LOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V200E"}}}},"userErrors":[]}}}
```

The responses are identical: the second is the replay, with the original time and no `appendEvent` in the log. The serial pair is one document with the aliases `a` and `b`, each with its own input variable; its handling log is the six-line listing above:

```bash
PAIR='mutation($a: RegisterHandlingEventInput!, $b: RegisterHandlingEventInput!) { a: registerHandlingEvent(input: $a) { handlingEvent { id } cargo { delivery { transportStatus currentVoyage { number } nextExpectedActivity { type location { unLocode } } } } } b: registerHandlingEvent(input: $b) { handlingEvent { id } cargo { delivery { transportStatus lastKnownLocation { unLocode } nextExpectedActivity { type location { unLocode } } } } } }'
curl -s localhost:8180/graphql -H 'Content-Type: application/json' -d "$(python3 -I -c 'import json,sys; print(json.dumps({"query": sys.argv[1], "variables": {"a": json.loads(sys.argv[2]), "b": json.loads(sys.argv[3])}}))' "$PAIR" '{"trackingId":"ABC123","type":"LOAD","location":"DEHAM","voyageNumber":"V200E","completionTime":"2026-10-10T06:30:00Z","idempotencyKey":"k-002"}' '{"trackingId":"ABC123","type":"UNLOAD","location":"NLRTM","voyageNumber":"V200E","completionTime":"2026-10-11T18:30:00Z","idempotencyKey":"k-003"}')"; echo
```

Then the `GET` refusal and the race:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -G localhost:8180/graphql --data-urlencode 'query=mutation { registerHandlingEvent(input: {trackingId: "ABC123", type: CUSTOMS, location: "NLRTM", completionTime: "2026-10-12T09:00:00Z"}) { handlingEvent { id } } }'
for i in 1 2 3 4 5 6 7 8; do reg '{"trackingId":"ABC123","type":"CLAIM","location":"NLRTM","completionTime":"2026-10-13T09:00:00Z","idempotencyKey":"k-par"}' & done; wait
```

The status is `405` on `8180` and `400` on `8181`. The eight parallel responses all carry the same event id, and the handling counts are `{'findByIdempotencyKey': 8, 'appendEvent': 1, 'listEvents': 8}`.

`bash examples/08-mutations/verify.sh` runs the whole sequence on both stacks, each from a fresh store, and prints `PASS` only when both hold. Experiments:

- **Send the mutation by `GET`.** Quarkus answers 405 and Python 400, and neither executes it.
- **Reuse a key with a new `completionTime`.** The reply is the original event with its original time.
- **Drop the key from the parallel loop.** Without `idempotencyKey` every request is a new event.

> **Decision**
>
> Keep a write in the graph only when the caller wants a shaped read of the result back in the same round trip, and leave bulk and booking writes with their owners. Reject malformed input through coercion as a request error and refused input as `userErrors` data, give every mutation one `input` argument and its own payload type, run ordered writes in one mutation, and require an `idempotencyKey`, made atomic in the store, from any client that retries.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): "Implementing mutations."
- [GraphQL specification: Input Objects, Input Coercion, Normal and Serial Execution](https://spec.graphql.org/): why input fields can't carry resolvers and why mutation root fields run in order.
- [GraphQL over HTTP: "GET"](https://http-spec.graphql.org/draft/): why a mutation must be refused on a safe HTTP method.
- *Cloud Native Design Patterns*, "Data": read/write separation and why a write stays with the service that owns it.
- *Cloud Native Design Patterns*, "Balancing Coupling" (Appendix G): the idempotency-key and retry-safety concerns behind `registerHandlingEvent`.
- The [Bibliography](../../bibliography/) page lists the books.
