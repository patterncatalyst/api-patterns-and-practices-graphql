# Ch8 - Mutations and input types

The tracking view's first write. `Mutation.registerHandlingEvent` records a handling event for a
cargo and returns the event together with the cargo, whose `delivery` is derived again after the
write. The example proves each claim of the chapter against both stacks: malformed input is a
request error and writes nothing, a broken domain rule is `userErrors` data and writes nothing, a
repeated `idempotencyKey` returns the original event, two aliased mutation fields run in order, a
mutation over `GET` is refused, and eight parallel requests with one key record one event.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything
Chapter 7 served, plus:

- `Mutation.registerHandlingEvent(input: RegisterHandlingEventInput!): RegisterHandlingEventPayload!`
- `RegisterHandlingEventInput`, `RegisterHandlingEventPayload`, `UserError` and `UserErrorCode`.
- `HandlingEvent`, with all eight fields, including the nullable `cargo`, and `Query.node` resolving
  `evt_*` ids.

After this chapter the stacks serve all of `Query` except `Query.cargos` and
`Cargo.handlingHistory` (the connection types, Chapter 12), and all of `Mutation`. `Subscription`
arrives in Chapter 21.

| Source | Operation | Read or written by |
|---|---|---|
| booking | `getCargo(trackingId)` | `Query.cargo`, validation, the payload's `cargo`, `HandlingEvent.cargo` |
| routing | `getItinerary(trackingId)` | `Cargo.itinerary`, `Cargo.delivery` |
| voyage | `getVoyage(number)` | `Query.voyage`, validation, `Leg.voyage`, `HandlingEvent.voyage` |
| location | `getLocation(unLocode)` | `Query.location`, validation, `HandlingEvent.location` |
| handling | `listEvents(trackingId)` | `Cargo.delivery` |
| handling | `getEvent(id)` | `Query.node` for `evt_*` ids |
| handling | `findByIdempotencyKey(key)` | `registerHandlingEvent`, only when the input carries a key |
| handling | `appendEvent(...)` | `registerHandlingEvent`; the log key is the new event's id |

The store is in memory and shared by every request. `ABC123` starts with `evt_1` (`RECEIVE`) and
`evt_2` (`LOAD` on `V100S`). New ids are `evt_<n>`, sequential after the seed: `evt_3` is the first.
`registrationTime` is the server clock in whole seconds.

### What `registerHandlingEvent` does

1. Looks up the cargo, the location and, for a `LOAD` or `UNLOAD` that names one, the voyage, all at
   once.
2. Collects every domain failure, in the order `trackingId`, `location`, `voyageNumber`,
   `completionTime`. Any failure returns a payload with `userErrors`, a null `handlingEvent` and a
   null `cargo`, and writes nothing.

   | Code | `field` | Rule |
   |---|---|---|
   | `UNKNOWN_CARGO` | `["input","trackingId"]` | no such cargo |
   | `UNKNOWN_LOCATION` | `["input","location"]` | no such location |
   | `VOYAGE_REQUIRED` | `["input","voyageNumber"]` | `LOAD` or `UNLOAD` without a voyage |
   | `VOYAGE_NOT_ALLOWED` | `["input","voyageNumber"]` | `RECEIVE`, `CUSTOMS` or `CLAIM` with a voyage |
   | `UNKNOWN_VOYAGE` | `["input","voyageNumber"]` | `LOAD` or `UNLOAD` on a voyage that does not exist |
   | `INVALID_COMPLETION_TIME` | `["input","completionTime"]` | after the server clock |

3. With an `idempotencyKey`, calls `handling.findByIdempotencyKey`; a hit is the result.
4. Otherwise calls `handling.appendEvent`, which checks the key and inserts the event as one atomic
   step, so two requests with the same key cannot both write.
5. Returns the event and the booking record. `Cargo.delivery` is a resolver, so it runs after the
   write and derives the state again from `handling.listEvents`.

`appendEvent` is logged only when it wrote. A call that lost a race to the same key writes nothing
and leaves no entry, so every `appendEvent` entry in the log means one new event.

## Run it

```bash
bash examples/08-mutations/verify.sh
```

`verify.sh` brings both services up with `docker compose`, runs the cases below in a fixed order,
reads the source-call log back, diffs each live schema against `contracts/schema/` and tears the stack
down. The handling store is in memory and the steps depend on each other (`evt_3` is the first new
id), so every run must start from a fresh stack; the script creates one. It prints `PASS` only if
every check holds on **both** stacks. It needs Docker Engine with the `docker compose` plugin and
Node/npm (for the pinned `graphql-inspector` in `contracts/`). It asserts order and overlap of 250 ms
windows, never a duration.

To explore by hand:

```bash
docker compose -f examples/08-mutations/compose.yaml up -d --build
curl -s localhost:8180/graphql -H 'Content-Type: application/json' -d '{
  "query": "mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id type } cargo { delivery { transportStatus } } userErrors { code field } } }",
  "variables": {"i": {"trackingId": "ABC123", "type": "UNLOAD", "location": "DEHAM", "voyageNumber": "V100S", "completionTime": "2026-10-09T15:00:00Z", "idempotencyKey": "k-001"}}}'
docker compose -f examples/08-mutations/compose.yaml down -v
```

Use port `8181` for the Python stack. Restart the stack to reset the store. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8180`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8181`. Set
`TRACKING_SOURCE_LATENCY_MS=250 TRACKING_DEBUG_ENDPOINTS=true` to get the same behaviour as compose;
both default to off.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the
log and answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`
(monotonic milliseconds). The endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets
it) and are plain HTTP resources beside `/graphql`, so the GraphQL schema is the same with them on or
off. Leave them off anywhere else.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8180 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8181 | `/graphql` (health at `/health`) |

Compose project `gql-ch08-mutations`, containers `ch08-mutations-*`. Telemetry is off by default.
Add the observability file (`docker compose -f compose.yaml -f compose.observability.yaml up
--build`) to send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and
3200, so run one example's observability stack at a time.

## On the wire

`verify.sh` runs these in order on each stack, on a fresh store. "Input" is the variable `$i` of
`mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { ... } }`.

| Step | Input | Expected |
|---|---|---|
| 1. Coercion, five cases | `type` missing; `type: "TELEPORT"`; `location: 123`; `completionTime: "yesterday"`; an extra field `weightKg: 1` | errors present, no `data` (absent or null), and not one source call |
| 2. Domain failures, five cases | `ABC123` `LOAD` at `DEHAM`, no voyage | `[{"code":"VOYAGE_REQUIRED","field":["input","voyageNumber"]}]` |
| | `ABC123` `RECEIVE` at `USNYC` with `V100S` | `VOYAGE_NOT_ALLOWED` |
| | `ABC123` `LOAD` at `DEHAM` on `V999X` | `UNKNOWN_VOYAGE` |
| | `ABC123` `CUSTOMS` at `NLRTM`, `2099-01-01T00:00:00Z` | `INVALID_COMPLETION_TIME`, `["input","completionTime"]` |
| | `NOPE99` `CUSTOMS` at `ZZZZZ` | `[UNKNOWN_CARGO ["input","trackingId"], UNKNOWN_LOCATION ["input","location"]]`, in that order |
| | each of the five | no top-level `errors`; `handlingEvent` and `cargo` null; non-empty `message`; no `appendEvent` call |
| | `node(id: "evt_3")` afterwards | null: the ten failures wrote nothing |
| 3. Success | `UNLOAD`, `ABC123`, `DEHAM`, `V100S`, `2026-10-09T15:00:00Z`, key `k-001` | `handlingEvent` `evt_3`, `UNLOAD`, `ABC123`, `DEHAM`, `V100S`, `2026-10-09T15:00:00Z`; `cargo.delivery` `{"transportStatus":"IN_PORT","lastKnownLocation":{"unLocode":"DEHAM"},"currentVoyage":null,"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"LOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V200E"}}}`; `userErrors` `[]`; one `appendEvent:evt_3`, after `findByIdempotencyKey:k-001` |
| 4. Replay | the same input and `k-001` | `evt_3`; no `appendEvent` call |
| 5. Same key, other time | `completionTime` `2026-10-09T16:00:00Z`, key `k-001` | `evt_3` with `completionTime` `2026-10-09T15:00:00Z`; no `appendEvent` call |
| 6. Serial pair | one document: `a:` `LOAD` `DEHAM` `V200E` `2026-10-10T06:30:00Z` `k-002`, then `b:` `UNLOAD` `NLRTM` `V200E` `2026-10-11T18:30:00Z` `k-003` | `a` is `evt_4`, `b` is `evt_5`; `a.cargo.delivery` `{"transportStatus":"ONBOARD_CARRIER","currentVoyage":{"number":"V200E"},"nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"NLRTM"},"voyage":{"number":"V200E"}}}`; `b.cargo.delivery` `{"transportStatus":"IN_PORT","lastKnownLocation":{"unLocode":"NLRTM"},"currentVoyage":null,"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"CLAIM","location":{"unLocode":"NLRTM"},"voyage":null}}`; `data` keys `a,b`; `appendEvent:evt_4` ends before `appendEvent:evt_5` starts, and before `findByIdempotencyKey:k-003` starts |
| 7. No key, twice | `CUSTOMS`, `ABC123`, `NLRTM`, `2026-10-12T09:00:00Z`, no key, sent twice | `evt_6`, then `evt_7`; one append each; no `findByIdempotencyKey` call |
| 8. Mutation over `GET` | the step 7 mutation as a `GET` query string | status 405 on Quarkus, 400 on Python; no source call; `node(id: "evt_8")` null afterwards |
| 9. Node | `node(id: "evt_3") { __typename ... on HandlingEvent { type cargo { trackingId } } }` | `{"__typename":"HandlingEvent","type":"UNLOAD","cargo":{"trackingId":"ABC123"}}` |
| 10. Parallel | eight simultaneous requests, `CLAIM`, `ABC123`, `NLRTM`, `2026-10-13T09:00:00Z`, key `k-par` | all eight return `evt_8`; eight `findByIdempotencyKey` calls and one `appendEvent`; at least two lookups end before the write does (the race took place); `node(id: "evt_9")` null |
| 11. Input defaults | `__type(name: "RegisterHandlingEventInput") { inputFields { name defaultValue } }` | six fields (`completionTime`, `idempotencyKey`, `location`, `trackingId`, `type`, `voyageNumber`), every `defaultValue` null |
| 12. Scalars | `__type` of `TrackingId`, `UnLocode`, `DateTime` | `SCALAR`; `specifiedByURL` null, `https://unece.org/trade/uncefact/unlocode`, `https://www.rfc-editor.org/rfc/rfc3339` |
| 13. Conformance | live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice) |

Observed differences, asserted per stack:

| | Quarkus | Python |
|---|---|---|
| Mutation over `GET` | `405`, empty body, no `Allow` header | `400`, `text/plain` body `mutations are not allowed when using GET` |
| Variable coercion failure | no `data` key | `"data": null` |
| `completionTime: "yesterday"` | SmallRye converts a `DateTime` inside an input object while binding the argument, after validation: two errors (`argument 'input' ... is not a valid ...` and a null-in-non-null error for `registerHandlingEvent`) and `"data": null`; the resolver never runs | one error naming `DateTime` and `yesterday`, at variable coercion |

Pinned versions: Quarkus platform 3.40.1 (SmallRye GraphQL 2.18.5), Strawberry 0.335.0 (graphql-core
3.3.0), FastAPI 0.143.2, uvicorn 0.54.0, pydantic-settings 2.16.0, on `ubi10/openjdk-25:1.24-16`
(JDK 25) and `ubi10/python-314-minimal:10.2-1791928506` (Python 3.14). The Python dependencies are
locked in `python/uv.lock`.

## Code-first notes

**Quarkus.**

- `@Mutation` on `HandlingApi.registerHandlingEvent`, which returns `Uni<RegisterHandlingEventPayload>`
  and takes the SmallRye `Context` for the execution id.
- The input is a record annotated `@Input("RegisterHandlingEventInput")`. Record binding works
  without a no-arg constructor or setters. The name is explicit because SmallRye appends `Input` to
  the name it derives, and the record's own name already ends in `Input`; the derived name would be
  `RegisterHandlingEventInputInput`, and the conformance check would flag it.
- Required fields are `@NonNull`; the two optional fields are plain `String`, which are nullable.
  `UserError.field` is `List<@NonNull String>`: a nullable list of non-null strings.
- `HandlingStore` holds the events and the idempotency index. The key is one
  `ConcurrentHashMap.computeIfAbsent` call, so the check and the insert are atomic.
  `HandlingSource.appendEvent` goes through `SourceCalls.write`, which logs an entry only when the
  call wrote.
- `HandlingEvent` keeps `unLocode` and `voyageNumber` out of the schema with `@Ignore`; `HandlingApi`
  resolves `location`, `voyage` and `cargo` with `@Source` methods, as `Leg` does in `TrackingApi`.
- `ContractSchemaDetails` also sets the `Mutation` root description (SmallRye's default is "Mutation
  root") and strips SmallRye's default " (ISO-8601)" suffix from the description of `DateTime` input
  fields, the same as for output fields.

**Python.**

- `@strawberry.mutation` on `Mutation.register_handling_event`; the domain logic is in
  `app/registration.py`.
- The input is `@strawberry.input`. Its two optional fields are `strawberry.Maybe[str | None]`
  with no default: an absent field arrives as `None`, a sent value as `Some(value)`, and the SDL
  prints neither a default nor `= null`. A plain `str | None = None` prints `= null`, and the
  introspection `defaultValue` is the string `"null"`. The conformance diff does not fail on that
  (it is a dangerous change, not a breaking one), so step 11 asserts every `defaultValue` is null.
  A plain `str | None` with no default also prints no default; `Maybe` is what the Strawberry
  documentation recommends, because it keeps absent and null apart.
- `HandlingStore` in `app/handling.py` holds the events and the index; `append` takes an
  `asyncio.Lock`. Nothing awaits between the check and the insert, so the event loop alone would
  already make that step indivisible; the lock states the invariant and keeps it true if a later
  change adds an await (a database call) inside it.
- `SourceCalls.write` logs an entry only when `HandlingStore.append` reports it wrote.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/08-mutations-architecture.py`) show the compose topology: a client
sending queries and mutations to each stack, the source-call log each stack serves, both stacks
diffed against the canonical SDL, and the opt-in `compose.observability.yaml` override.
