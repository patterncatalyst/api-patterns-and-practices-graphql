---
title: "Mutations and input types"
order: 8
part: "Execution: Resolvers, Queries & Mutations"
description: "How registerHandlingEvent takes a typed input object, rejects malformed input as a request error and broken domain rules as userErrors data, returns the event with a recomputed delivery, runs aliased mutation fields in order, and stays safe to retry with an idempotency key."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Declare a typed `RegisterHandlingEventInput` input object and explain why input types can only hold scalars, enums, and other inputs.
- Distinguish a coercion failure (caught by the engine before any resolver runs) from a domain failure returned as `userErrors` data.
- Design a mutation payload (`RegisterHandlingEventPayload`) that re-reads derived state like `Cargo.delivery` in the same round trip.
- Rely on the engine's serial execution of top-level mutation fields to run two aliased `registerHandlingEvent` calls in document order.
- Make a mutation safe to retry with a client-supplied `idempotencyKey` checked and inserted atomically in one step.

## Why this matters

Seven chapters read data. This one writes it. The tracking view has exactly one mutation, `registerHandlingEvent`, and it carries most of what a write in GraphQL needs: a typed input object, two different ways to say no, a payload that hands the changed cargo back, the engine's rule that mutation fields run in order, and a key that makes a retry safe. You will meet each on the running stacks, and each claim is something `verify.sh` asserts.

The code is in `examples/08-mutations/`. It starts from the resolver example and keeps its asynchronous sources, the source-call log and the derived `Delivery`. The handling data changes from a fixed list into a store that requests write to, `HandlingEvent` and the mutation types join the schema, and `Query.node` resolves `evt_*` ids. The store is in memory, so every run of `verify.sh` starts from a fresh stack, and `README.md` covers how to drive it.

## Why the write surface is one field

The decision framework put writes with their owners: the service that holds the data enforces its validation, idempotency and transactional rules, and a second implementation in an aggregation layer is a second place to get them wrong. The canonical schema says as much in its description of `Mutation`: the write surface is small because writes belong to the owning services. Booking a cargo stays a REST call.

`registerHandlingEvent` is the exception because of what the caller wants back. A terminal app that reports "unloaded at Hamburg" also wants the cargo's new state, and a mutation can return it in the same round trip, shaped by the caller's selection. In the example the handling store stands in for the owning service. The mutation validates, hands the event to the store through `handling.appendEvent`, and reads the result back through the same sources the queries use. It does not become a second system of record.

## Input types

An input type is an object type for arguments. It uses the keyword `input`, and its fields are data, not resolvers. That is why an input field can hold only a scalar, an enum or another input type: an object type's fields can take arguments and run resolvers, an interface or a union needs a runtime type to pick a branch, and none of that has a meaning for a value that arrives as JSON. The canonical SDL already showed the definition. Here it is again with each field's job:

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

Four fields are required: which cargo, what kind of handling, where, and when it happened. `voyageNumber` is optional because a `RECEIVE` has no voyage, and `idempotencyKey` is optional because a client that never retries does not need one. The `location` field is a `UnLocode` and not a `Location` because an input names a place, and the server resolves the name.

Nullability propagation raised the third state that inputs have: an absent field and an explicit `null` are different inputs. For these two fields the mutation treats them alike, and `verify.sh` does not depend on the difference. A client that sends `"voyageNumber": null` on a `LOAD` gets `VOYAGE_REQUIRED`, exactly as when it omits the field. The stacks still differ in how they let you tell the two apart, which shows in the declaration.

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
        @Description("Client-supplied key making retries safe: ...") String idempotencyKey) {}
```

```python
@strawberry.input(description="Input for `Mutation.registerHandlingEvent`.")
class RegisterHandlingEventInput:
    tracking_id: TrackingId = strawberry.field(description="The cargo that was handled.")
    type: HandlingEventType = strawberry.field(description="What kind of handling occurred.")
    location: UnLocode = strawberry.field(description="Where it occurred.")
    voyage_number: strawberry.Maybe[str | None] = strawberry.field(
        description="The voyage number; required for LOAD and UNLOAD, forbidden otherwise."
    )
    completion_time: datetime = strawberry.field(description="When the handling actually happened.")
    idempotency_key: strawberry.Maybe[str | None] = strawberry.field(description="Client-supplied key ...")
```

SmallRye binds a Java record directly. The name takes one explicit setting. SmallRye derives an input type's name from the class and appends `Input`, and this record's name already ends in `Input`, so the derived name would be `RegisterHandlingEventInputInput`. The explicit `@Input("RegisterHandlingEventInput")` pins the contract's name, and the conformance check would flag any other. A field is required when it is `@NonNull` and nullable otherwise.

Strawberry takes the opposite default: a field is required unless the annotation says `| None`. The canonical schema gives the optional fields no default, so the example declares them as `strawberry.Maybe[str | None]` with no default, which prints a plain `String`. Spelling the field `voyage_number: str | None = None` would print `voyageNumber: String = null` in the SDL, and the conformance diff classifies an added default as a dangerous change, not a breaking one, as the contract-first conformance check warned. It is the type the Strawberry documentation recommends for optional input fields, because an absent field arrives as `None` and a sent value as `Some(value)`, so a resolver that needs the difference between "not sent" and "sent null" can see it. This mutation does not need that difference, so it unwraps both to `None`. A plain `str | None` with no default also prints no default; `Maybe` is the choice that keeps the distinction available. Since the conformance check cannot see the difference, step 11 of `verify.sh` asserts that every `defaultValue` of the input type is JSON `null`.

## Coercion: the first line of defence

Before any resolver runs, the engine checks the input against its type. This is the coercion step the execution model places ahead of resolver execution, and the specification describes it under "Coercing Variable Values" for variables and "Input Coercion" for values written in the document. It rejects what the type system can express: a value of the wrong kind, an enum value that does not exist, a required field that is missing, a field the input type does not have.

`verify.sh` sends five such requests, each as a variable so the input travels as JSON:

| Input | What is wrong |
|---|---|
| no `type` | a required field is missing |
| `"type": "TELEPORT"` | not a value of `HandlingEventType` |
| `"location": 123` | `UnLocode` accepts only a string |
| `"completionTime": "yesterday"` | not an RFC 3339 date-time |
| an extra field `"weightKg": 1` | `RegisterHandlingEventInput` has no such field |

All five come back with errors and no data, and the source-call log is empty: no resolver ran, so nothing was looked up, validated or written. Because the engine, not the code, makes this check, it is the same on any mutation the schema adds later, and the only thing a resolver author owes it is the type declaration. The shape of the failure differs by stack. Quarkus omits the `data` key, as the specification says a request error should. Strawberry sends `"data": null`, which `assert_no_data` treats as the same thing. Both answer HTTP 200. To the `Accept: application/json` that `verify.sh` sends, both label the body `application/json`; to a client that accepts any type, such as the plain `curl` under "On the wire", Quarkus answers `application/graphql-response+json`.

The date-time case is where the stacks differ most. Strawberry rejects `yesterday` during coercion with a single error that names the scalar, and does so whether it is a variable or a literal in the document. SmallRye converts the `DateTime` inside an input object later, when it binds the argument to the record, which is after validation and inside execution. The response carries two errors, one that quotes the input object and one reporting that `registerHandlingEvent`, a non-null field, produced null, and `data` is `null`. The older editions of the specification call this kind of failure a "field error"; the current term is an "execution error", and it is what bubbles up here, through the non-null payload type that null propagation describes. The outcome is the same as for the other four cases: errors, no data, no resolver body, no write. A client should not depend on the difference in shape, and a design that needs a clean message for a bad date-time would validate the string in the resolver and return a `userError`, at the price of declaring the field as `String`.

## Domain validation as data

Coercion knows types. It does not know that `NOPE99` is not a cargo, or that a `LOAD` needs a voyage. Those are domain rules, and they fail differently: the response is a normal result in which `userErrors` is not empty.

```graphql
type UserError {
  code: UserErrorCode!
  message: String!
  field: [String!]
}
```

Each failure has a stable `code` a program can switch on, a `message` a person can read, and a `field` path that names the input field. The path starts at `input` because that is the argument's name, and it is `null` when a failure concerns the input as a whole. The resolver collects every applicable failure in a fixed order, so a client fixes a form in one round trip and not one field at a time.

| Order | Code | Rule |
|---|---|---|
| 1 | `UNKNOWN_CARGO` | no cargo has that tracking id |
| 2 | `UNKNOWN_LOCATION` | no location has that UN/LOCODE |
| 3 | `VOYAGE_REQUIRED`, `VOYAGE_NOT_ALLOWED`, `UNKNOWN_VOYAGE` | a `LOAD` or `UNLOAD` needs a voyage that exists; the other types must not name one |
| 4 | `INVALID_COMPLETION_TIME` | after the server clock |

`NOPE99` at `ZZZZZ` returns `UNKNOWN_CARGO` with `["input","trackingId"]` and then `UNKNOWN_LOCATION` with `["input","location"]`, in that order, on both stacks. A failure leaves `handlingEvent` and `cargo` null and writes nothing, which the log confirms: no `appendEvent` call. The three lookups run together, so a rejected request costs one source window, not three.

{% include excalidraw.html file="08-errors-vs-usererrors" alt="Two panels side by side. The left panel, a coercion failure for a type of TELEPORT, shows a dashed box for data, absent on Quarkus and null on Strawberry, and a highlighted box for errors[0] with a message and locations but no path. A box below says the failure is raised by the engine before the resolver runs, with HTTP 200 on both stacks. The right panel, a domain failure for a LOAD without a voyage, shows a highlighted box for data.registerHandlingEvent with handlingEvent and cargo null, a highlighted box for userErrors[0] with code VOYAGE_REQUIRED and field input, voyageNumber, and a box saying the result is returned by the resolver as an ordinary value with no errors key." caption="Figure 8.1: Two kinds of failure, two places in the response. The engine reports a malformed request in errors; the resolver reports a refused input in userErrors." %}

Why not throw, and let the failure appear in the top-level `errors`? Because the two arrays mean different things to a client. `errors` says the request could not be run as written or the server failed: a developer's problem, usually the same for every user, and a monitor counts it. `userErrors` says the server understood the request and refused this input: a user's problem, expected, and part of the contract. A typed list lets a client render `VOYAGE_REQUIRED` next to the voyage field, where an exception message would be text to display or parse. Error handling sets out the conventions for both, including the alternative of modelling the result as a union of success and error types, and why this book does not.

## The payload and the re-read

A mutation field returns a payload type, not the bare event. `RegisterHandlingEventPayload` has three fields: `handlingEvent`, `cargo` and `userErrors`. On success the first two are set and `userErrors` is `[]`. On a refusal it is the other way around.

The `cargo` field is the reason the mutation is in the graph. `Cargo.delivery` is a resolver that derives the delivery state from `handling.listEvents` and the itinerary, as the earlier resolver chapter built it, and the payload's `cargo` is an ordinary `Cargo`. The write happens first, then the engine resolves the payload's fields, so `delivery` reads the store after the new event is in it. The client gets the new state without a second request and without computing it. An UNLOAD at Hamburg on `V100S` moves `ABC123` from `ONBOARD_CARRIER` to `IN_PORT`, and the next expected activity from `UNLOAD` at `DEHAM` to `LOAD` at `DEHAM` on `V200E`, which is the `UNLOAD` row of the derivation table in the example's README.

{% include excalidraw.html file="08-mutation-flow" alt="A row of seven boxes from left to right: Variables, Input coercion, Domain validation, Key lookup, appendEvent, Re-read and Payload. Amber arrows join them. Dashed arrows lead down from Input coercion to a box labelled errors with nothing written, and from Domain validation to a box labelled userErrors with nothing written. An amber arrow leads down from Key lookup to a box labelled Key hit, the original event, nothing written, and from there up to the Re-read box." caption="Figure 8.2: The path of one registerHandlingEvent call. Coercion belongs to the engine; validation, lookup, append and re-read run in the resolver, and a key hit skips the append." %}

The re-read has a cost, and the log shows it. A successful registration makes a lookup window for the cargo, the location and the voyage together, a window for the key, a window for the append, and then the payload's own reads: `listEvents` and `getItinerary` for the delivery, and the location and voyage of the event. Each is 250 ms in the example. A client that needs only an acknowledgment can select only `handlingEvent { id }`, and the delivery is never derived, because an unselected field costs nothing. That is the same selection-driven saving the execution model measured.

The event itself is a `Node`, so `node(id: "evt_3")` refetches it. `HandlingEvent.cargo` is nullable: the contract says it is null when the cargo service is unavailable, which makes the event usable when its cargo is not.

## Mutation fields run in order

The execution model stated the rule from the specification's "Normal and Serial Execution": the top-level fields of a mutation run one at a time, in the order written, each completely before the next. Figure 6.4 drew it and promised a measurement. This is the measurement, with two aliased fields in one document.

```graphql
mutation($a: RegisterHandlingEventInput!, $b: RegisterHandlingEventInput!) {
  a: registerHandlingEvent(input: $a) { handlingEvent { id } cargo { delivery { transportStatus ... } } }
  b: registerHandlingEvent(input: $b) { handlingEvent { id } cargo { delivery { transportStatus ... } } }
}
```

Field `a` loads `ABC123` onto `V200E` at Hamburg and `b` unloads it at Rotterdam. `b` is only meaningful once `a` has landed. Two independent observations show the order, and either would fail on an engine that ran them together:

- **The log.** `appendEvent:evt_4` ends before `appendEvent:evt_5` starts, and so does `findByIdempotencyKey:k-003`, the first thing `b` does. A parallel engine would have started `b`'s lookup at the same time as `a`'s.
- **The payload of `a`.** Its `cargo.delivery` is `ONBOARD_CARRIER` on `V200E`, next `UNLOAD` at `NLRTM`. If `b` had run first or alongside, `a` would show `IN_PORT` and the next activity `CLAIM`. `b`'s payload shows exactly that.

```text
findByIdempotencyKey   k-002  +   0 to + 251
appendEvent            evt_4  + 251 to + 502
listEvents             ABC123 + 506 to + 757
findByIdempotencyKey   k-003  +1015 to +1265
appendEvent            evt_5  +1265 to +1516
listEvents             ABC123 +1520 to +1771
```

The gap between `a`'s last call and `b`'s first is the rest of `a`'s payload, the location and voyage reads. graphql-java, under SmallRye, runs the mutation root with a serial strategy, and graphql-core runs it through `execute_fields_serially`; the log shows both do. Below the root nothing is serial: the fields inside `a`'s payload are siblings again and may overlap, which they do. Query fields have no such guarantee, so a client that needs ordered writes must send them in one mutation, and a client that sends two mutations in two requests has no ordering at all.

## Retries and `idempotencyKey`

A mutation changes state, so a retry is dangerous. A client sends a request, the server records the event, the response is lost, and the client, seeing a timeout, sends it again. Without help the store now holds two events for one handling, and the second is wrong. The cargo's derived state may even change, because the duplicate is the new last event.

The canonical input has the answer: `idempotencyKey`, a string the client chooses and repeats on every retry of the same intent. The rule is that a repeated request with the same key returns the originally recorded event instead of recording a second one. The implementation has two steps, and the second is the one that matters.

1. **Look the key up.** `handling.findByIdempotencyKey` returns the event the key already produced, if any. A hit skips the write.
2. **Insert only if absent, atomically.** `handling.appendEvent` checks the key and inserts the event in one indivisible step. It is the only step that can be trusted, because the lookup and the insert are separate calls, and two requests that arrive together can both miss the lookup.

{% include codetabs.html langs="Quarkus|Python" %}

```java
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

`ConcurrentHashMap.computeIfAbsent` runs its function at most once per key, atomically, so exactly one caller creates the event and the others receive it. The `created` flag tells the source whether this call wrote. On Python the `asyncio.Lock` serializes the section. Nothing awaits between the check and the insert, so the single-threaded event loop would already make it indivisible; the lock states the invariant and keeps it true the day someone adds an `await` there, such as a database call.

The proof is a race. `verify.sh` fires eight identical requests at once with the key `k-par`. All eight return the same id, `evt_8`. The log holds eight `findByIdempotencyKey` calls and exactly one `appendEvent`. The requests arrive inside one source window, so their lookups run before the write lands and miss, and `verify.sh` checks that at least two did, which proves the race took place. `node(id: "evt_9")` is null. The lookup alone would have written eight events; the atomic step is what makes the guarantee. A call that loses the race writes nothing and logs nothing, so every `appendEvent` entry in the log means one new event.

{% include excalidraw.html file="08-idempotent-replay" alt="A timeline with three lanes. In the first lane, the first request with key k-001 shows a lookup that misses, an appendEvent that writes evt_3, and a dashed box where the response is lost. An amber arrow labelled retry leads to the second lane, where a lookup with the same key hits evt_3 and a re-read of the cargo returns evt_3, with the note store: evt_3 only. The third lane, a retry without a key, shows dashed boxes for no lookup and an appendEvent that writes evt_4, with the note store: evt_3 and evt_4." caption="Figure 8.3: The same retry with and without a key. With one, the second request becomes a read; without one, the store cannot tell a retry from a second event." %}

Replay returns the original even when the retry differs. A request with `k-001` and a `completionTime` of `16:00` returns `evt_3` with its original `15:00`. That is a design choice, and its price is that a client reusing a key for a different intent is answered with the old event and no signal that the input differed. A stricter server compares the stored input and rejects a mismatch; the example does not. A request with no key gets a new event each time: two identical `CUSTOMS` registrations are `evt_6` and `evt_7`. The example's key space is also one global map that never expires. A production store would scope a key to the caller, expire it after a window, and keep the key and the event in the same transaction.

## Mutations and HTTP

A GraphQL operation travels over HTTP, and GraphQL over HTTP allows a query on `GET`, with the query and variables in the URL. It does not allow a mutation there. The "GET" section of the specification says a server must refuse a mutation received that way with a 4xx status and halt execution, and recommends 405 (Method Not Allowed). A note adds that a 405 must carry an `Allow` header, which RFC 9110 requires of every 405 response. The reason is the web's own contract: `GET` is safe, so proxies, prefetchers and caches may repeat it or answer it from memory, and a state change must never hide behind it.

`verify.sh` sends the step 7 mutation by `GET` and observes the following, and the example asserts what each stack does:

| | Status | Body | Executed |
|---|---|---|---|
| Quarkus | 405 | empty, no `Allow` header | no |
| Python | 400 | text, `mutations are not allowed when using GET` | no |

Both refuse, and the log shows no source call. Both meet the mandatory part: a 4xx, and no execution. Quarkus answers the recommended 405 without an `Allow` header. Strawberry answers 400, a 4xx other than the recommended one, with a plain-text body. Neither matters to a client that sends mutations by `POST`, which is what every GraphQL client library does. It matters to a gateway or a cache in front of the service, which is why persisted queries and caching return to `GET`.

## Naming and shape conventions

Four habits keep a mutation's evolution additive.

- **Verb then noun.** `registerHandlingEvent` names the action, and the type names follow: `RegisterHandlingEventInput`, `RegisterHandlingEventPayload`. A reader finds the input and the payload from the field name.
- **One `input` argument.** A single input object means a new optional field is an additive change. A new argument on a field is also additive, but a long argument list is awkward to pass and to validate, and the `field` path in a `UserError` reads `input` and then the field name.
- **A payload per mutation.** Returning `Boolean` or the bare event leaves no room for `userErrors` or for the cargo, and adding them later changes the return type, which breaks clients. A payload that starts as a wrapper can grow.
- **A key you control for retries.** The Relay mutation convention has a `clientMutationId` that the server echoes back. It correlates a response with a request but does not make a retry safe. `idempotencyKey` does the work that matters here, so the tracking view uses it and leaves `clientMutationId` out.

## On the wire

Start the stack. Quarkus is on `8180` and Python on `8181`, and the store starts with `evt_1` and `evt_2` on `ABC123`.

```bash
docker compose -f examples/08-mutations/compose.yaml up -d --build
Q='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id type completionTime } cargo { delivery { transportStatus lastKnownLocation { unLocode } currentVoyage { number } nextExpectedActivity { type location { unLocode } voyage { number } } } } userErrors { code field message } } }'
reg() { curl -s localhost:8180/graphql -H 'Content-Type: application/json' -d "$(python3 -I -c 'import json,sys; print(json.dumps({"query": sys.argv[1], "variables": {"i": json.loads(sys.argv[2])}}))' "$Q" "$1")"; echo; }
```

A coercion failure first. The input is well formed JSON with a value the enum does not have:

```bash
reg '{"trackingId":"ABC123","type":"TELEPORT","location":"DEHAM","completionTime":"2026-10-09T15:00:00Z"}'
```

```json
{"errors":[{"message":"Variable 'i' has an invalid value: Invalid input for enum 'HandlingEventType'. No value found for name 'TELEPORT'","locations":[{"line":1,"column":10}],"extensions":{"classification":"ValidationError"}}]}
```

Python answers `{"data":null,"errors":[{"message":"Variable '$i' has invalid value at .type: Value 'TELEPORT' does not exist in 'HandlingEventType' enum.","locations":[{"line":1,"column":10}]}]}`: the same failure, a different message, and a `data` that is `null`. Then two domain failures:

```bash
reg '{"trackingId":"ABC123","type":"LOAD","location":"DEHAM","completionTime":"2026-10-09T15:00:00Z"}'
reg '{"trackingId":"NOPE99","type":"CUSTOMS","location":"ZZZZZ","completionTime":"2026-10-09T15:00:00Z"}'
```

```json
{"data":{"registerHandlingEvent":{"handlingEvent":null,"cargo":null,"userErrors":[{"code":"VOYAGE_REQUIRED","field":["input","voyageNumber"],"message":"LOAD events must name a voyage."}]}}}
{"data":{"registerHandlingEvent":{"handlingEvent":null,"cargo":null,"userErrors":[{"code":"UNKNOWN_CARGO","field":["input","trackingId"],"message":"No cargo has tracking id NOPE99."},{"code":"UNKNOWN_LOCATION","field":["input","location"],"message":"No location has UN/LOCODE ZZZZZ."}]}}}
```

Both stacks answer these byte for byte. Now a success with a key, and the same request sent again with a different `completionTime`:

```bash
reg '{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z","idempotencyKey":"k-001"}'
reg '{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T16:00:00Z","idempotencyKey":"k-001"}'
```

```json
{"data":{"registerHandlingEvent":{"handlingEvent":{"id":"evt_3","type":"UNLOAD","completionTime":"2026-10-09T15:00:00Z"},"cargo":{"delivery":{"transportStatus":"IN_PORT","lastKnownLocation":{"unLocode":"DEHAM"},"currentVoyage":null,"nextExpectedActivity":{"type":"LOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V200E"}}}},"userErrors":[]}}}
{"data":{"registerHandlingEvent":{"handlingEvent":{"id":"evt_3","type":"UNLOAD","completionTime":"2026-10-09T15:00:00Z"},"cargo":{"delivery":{"transportStatus":"IN_PORT","lastKnownLocation":{"unLocode":"DEHAM"},"currentVoyage":null,"nextExpectedActivity":{"type":"LOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V200E"}}}},"userErrors":[]}}}
```

The two responses are identical. The second is the replay: `evt_3`, the original time, and no `appendEvent` call in the log. The serial pair is one document with the aliases `a` and `b`, each with its own input variable:

```bash
PAIR='mutation($a: RegisterHandlingEventInput!, $b: RegisterHandlingEventInput!) { a: registerHandlingEvent(input: $a) { handlingEvent { id } cargo { delivery { transportStatus currentVoyage { number } nextExpectedActivity { type location { unLocode } } } } } b: registerHandlingEvent(input: $b) { handlingEvent { id } cargo { delivery { transportStatus lastKnownLocation { unLocode } nextExpectedActivity { type location { unLocode } } } } } }'
curl -s localhost:8180/graphql -H 'Content-Type: application/json' -d "$(python3 -I -c 'import json,sys; print(json.dumps({"query": sys.argv[1], "variables": {"a": json.loads(sys.argv[2]), "b": json.loads(sys.argv[3])}}))' "$PAIR" '{"trackingId":"ABC123","type":"LOAD","location":"DEHAM","voyageNumber":"V200E","completionTime":"2026-10-10T06:30:00Z","idempotencyKey":"k-002"}' '{"trackingId":"ABC123","type":"UNLOAD","location":"NLRTM","voyageNumber":"V200E","completionTime":"2026-10-11T18:30:00Z","idempotencyKey":"k-003"}')"; echo
```


```json
{"data":{"a":{"handlingEvent":{"id":"evt_4"},"cargo":{"delivery":{"transportStatus":"ONBOARD_CARRIER","currentVoyage":{"number":"V200E"},"nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"NLRTM"}}}}},"b":{"handlingEvent":{"id":"evt_5"},"cargo":{"delivery":{"transportStatus":"IN_PORT","lastKnownLocation":{"unLocode":"NLRTM"},"nextExpectedActivity":{"type":"CLAIM","location":{"unLocode":"NLRTM"}}}}}}}
```

Its handling log is the six-line listing in the serial section. Then the `GET` refusal and the race:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -G localhost:8180/graphql --data-urlencode 'query=mutation { registerHandlingEvent(input: {trackingId: "ABC123", type: CUSTOMS, location: "NLRTM", completionTime: "2026-10-12T09:00:00Z"}) { handlingEvent { id } } }'
curl -s localhost:8180/graphql -H 'Content-Type: application/json' -d '{"query":"{ node(id: \"evt_6\") { __typename } }"}'; echo
for i in 1 2 3 4 5 6 7 8; do reg '{"trackingId":"ABC123","type":"CLAIM","location":"NLRTM","completionTime":"2026-10-13T09:00:00Z","idempotencyKey":"k-par"}' & done; wait
```

```text
405
{"data":{"node":null}}
```

The status is `400` on port `8181`. The eight parallel responses all carry `"id":"evt_6"`, and the handling counts `verify.sh` prints from the log are `{'findByIdempotencyKey': 8, 'appendEvent': 1, 'listEvents': 8}`. Request ids and timestamps differ on every run. The ids, codes, paths, order and counts do not.

| Check | Expected |
|---|---|
| five coercion failures: no `type`, `"TELEPORT"`, `"location": 123`, `"yesterday"`, an extra `weightKg` | errors, no data, no source call |
| five domain failures | no `errors`; `handlingEvent` and `cargo` null; the codes and paths above; non-empty `message`; no `appendEvent`; `node(id: "evt_3")` still null |
| `UNLOAD` at `DEHAM` on `V100S`, key `k-001` | `evt_3`; delivery `IN_PORT`, last location `DEHAM`, no current voyage, next `LOAD` at `DEHAM` on `V200E`; `userErrors` `[]`; one append after the key lookup |
| the same key again, then with `16:00` | `evt_3`, completion `2026-10-09T15:00:00Z`; no append |
| serial pair `k-002`, `k-003` | `evt_4` then `evt_5`; `a` `ONBOARD_CARRIER` on `V200E` with next `UNLOAD` at `NLRTM`; `b` `IN_PORT` at `NLRTM`, next `CLAIM`, ETA `2026-10-11T18:00:00Z`; `data` keys `a,b`; `evt_4` appended before `evt_5`, and before `k-003` was looked up |
| `CUSTOMS` at `NLRTM`, no key, twice | `evt_6`, then `evt_7`, one append each |
| the same mutation by `GET` | `405` on Quarkus, `400` on Python; no source call; `node(id: "evt_8")` null |
| `node(id: "evt_3") { __typename ... on HandlingEvent { type cargo { trackingId } } }` | `HandlingEvent`, `UNLOAD`, `ABC123` |
| eight parallel requests, key `k-par` | all `evt_8`; eight key lookups, at least two before the write, one append; `node(id: "evt_9")` null |
| `inputFields { name defaultValue }` of `RegisterHandlingEventInput` | six fields, every `defaultValue` null |
| `TrackingId`, `UnLocode`, `DateTime` scalars | `SCALAR`; `specifiedByURL` null, UNECE UN/LOCODE page, RFC 3339 |
| live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice) |

`bash examples/08-mutations/verify.sh` runs the whole sequence on both stacks, starts each from a fresh store, and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>The mutation is where the <em>read and write balance</em> axis of the decision framework becomes code: one write, in the schema because the caller wants the recomputed <code>Cargo</code> back in the same round trip, and a payload that returns it. The <em>contract and evolution style</em> axis shows in the input and the payload: one <code>input</code> argument, a payload type that can grow, and <code>UserErrorCode</code> values that clients switch on, all additive to extend. The <em>operational and security cost</em> axis shows in retries and HTTP: an <code>idempotencyKey</code> made atomic in the store, a mutation refused over <code>GET</code>, and a per-call cost that the log makes visible. The <em>team ownership</em> axis shows in where the write goes: the tracking view validates and delegates to the handling store, which stands for the owner, and does not become a second system of record. The tracking view rejects malformed input as a request error and a refused input as <code>userErrors</code> data, runs ordered writes in one mutation, requires a key from any client that retries, and leaves bulk and booking writes with their owners.</p></div>

## Review

- `RegisterHandlingEventInput` is a typed input object; input types can only hold scalars, enums, and other inputs because their fields are data, not resolvers.
- A coercion failure is caught by the engine before any resolver runs, while a domain failure is returned as `userErrors` data from inside the resolver.
- `RegisterHandlingEventPayload` re-reads derived state like `Cargo.delivery` in the same round trip, so a client never asks twice.
- The engine's serial execution of top-level mutation fields runs two aliased `registerHandlingEvent` calls in document order, each fully before the next.
- A client-supplied `idempotencyKey`, checked and inserted atomically in one step, makes a mutation safe to retry.

## Where this goes next

This chapter added the write path: an input type with its coercion, domain failures as data, a payload that re-reads the cargo, the serial rule observed on both stacks, and an idempotency key that holds under a race. Two things it leaves open. The two kinds of failure get a full contract in error handling, which covers `errors` and `extensions`, the union-of-results alternative, and what a message should say. The new `HandlingEvent` type becomes the node of the Relay connection built for `Cargo.handlingHistory`.

The next example starts from this one and gives execution errors the same attention that `userErrors` received here. The breaking-change gate treats adding a required field to an input as a breaking change and adding an optional one as safe, which is why `voyageNumber` and `idempotencyKey` are optional from the start.

For the formal definitions, read "Input Objects", "Input Coercion", "Coercing Variable Values" and "Normal and Serial Execution" in the [GraphQL specification](https://spec.graphql.org/), and "GET" in GraphQL over HTTP. Samer Buna's *GraphQL in Action* covers the same ground in "Implementing mutations"; the book is listed on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): "Implementing mutations."
- [GraphQL specification: Input Objects, Input Coercion, Normal and Serial Execution](https://spec.graphql.org/): why input fields can't carry resolvers and why mutation root fields run in order.
- [GraphQL over HTTP: "GET"](https://http-spec.graphql.org/draft/): why a mutation must be refused on a safe HTTP method.
- *Cloud Native Design Patterns*, "Data": read/write separation and why a write stays with the service that owns it.
- *Cloud Native Design Patterns*, "Balancing Coupling" (Appendix G): the idempotency-key and retry-safety concerns behind `registerHandlingEvent`.
