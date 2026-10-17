# Ch6 - The execution model

The tracking view's cargo graph with every source-backed field resolved asynchronously, each
source call delayed by 250 ms and written to a source-call log. The chapter follows one request
through parse, validate, coerce and execute, and this example proves each stage on the wire by
reading that log: which sources a selection calls, in what order, and which calls overlap.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves the same types as
Chapter 3:

- `Query.cargo`, `Query.location`, `Query.voyage` and `Query.node`.
- `Cargo`, `RouteSpecification`, `Itinerary`, `Leg`, `Voyage` (`id`, `number`, `schedule`),
  `CarrierMovement`, `Delivery` (all seven fields), `HandlingActivity`, `Location` and the `Node`
  interface.
- The enums `TransportStatus`, `RoutingStatus` and `HandlingEventType`, and the scalars
  `TrackingId`, `UnLocode` and `DateTime`.

Not served yet: `Query.cargos`, `Cargo.handlingHistory` and the connection types (Chapter 12),
`Mutation` and the types behind it (Chapter 8), and `Subscription` (Chapter 21).

What changes from Chapter 3 is where the data comes from. Five sources stand in for the services
that own it, and every field that reads one is a resolver:

| Source | Operation | Read by |
|---|---|---|
| booking | `getCargo(trackingId)` | `Query.cargo`, `Query.node` for `cargo_*` ids |
| routing | `getItinerary(trackingId)` | `Cargo.itinerary` |
| voyage | `getVoyage(number)` | `Query.voyage`, `Query.node` for `voy_*` ids, `Leg.voyage` |
| location | `getLocation(unLocode)` | `Query.location`, `Query.node` for `loc_*` ids, `Leg.loadLocation`, `Leg.unloadLocation` |
| delivery | `getDelivery(trackingId)` | `Cargo.delivery` (the stored constants of Chapter 3) |

The booking record carries `description`, `origin`, `destination` and `routeSpecification`, so
selecting them costs no further call. A leg carries a voyage number and two UN/LOCODEs, and the
three `Leg` resolvers turn them into objects.

Each call takes `TRACKING_SOURCE_LATENCY_MS` (250 in `compose.yaml`; 0 when unset) without holding
a thread: a Mutiny `Uni` on Quarkus, `await asyncio.sleep` on Python. Each call is recorded in the
**source-call log**.

## Run it

```bash
bash examples/06-execution-model/verify.sh
```

`verify.sh` brings both services up with `docker compose`, resets the log before each case, runs
the queries below, reads the log back, diffs each live schema against `contracts/schema/` and tears
the stack down. It prints `PASS` only if every check holds on **both** stacks. It needs Docker
Engine with the `docker compose` plugin and Node/npm (for the pinned `graphql-inspector` in
`contracts/`). It asserts order and overlap of 250 ms windows, never a duration.

To explore by hand:

```bash
docker compose -f examples/06-execution-model/compose.yaml up -d --build
curl -s -X DELETE localhost:8160/debug/source-calls
curl -s localhost:8160/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { itinerary { legs { loadLocation { unLocode } } } delivery { transportStatus } } }"}'
curl -s localhost:8160/debug/source-calls
docker compose -f examples/06-execution-model/compose.yaml down -v
```

Use port `8161` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8160`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8161`. Set
`TRACKING_SOURCE_LATENCY_MS=250 TRACKING_DEBUG_ENDPOINTS=true` to get the same behaviour as
compose; both default to off.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`. `DELETE` clears the
log and answers `204`. Each entry:

| Field | Meaning |
|---|---|
| `request` | The id of the request that made the call: SmallRye's execution id on Quarkus, a uuid4 on Python |
| `source`, `op`, `key` | Which source, which operation, and the lookup key, such as `booking`, `getCargo`, `ABC123` |
| `startMs`, `endMs` | Monotonic milliseconds since the process started |

These endpoints exist for verification. They answer only when `TRACKING_DEBUG_ENDPOINTS=true`
(compose sets it) and otherwise answer 404 (Quarkus) or are not mounted (Python). Leave them off
anywhere else. They are plain HTTP resources beside `/graphql`, so the GraphQL schema is the same
with them on or off; the conformance check proves it.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8160 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8161 | `/graphql` (health at `/health`) |

Compose project `gql-ch06-exec`, containers `ch06-exec-*`. Telemetry is off by default. Add the
observability file (`docker compose -f compose.yaml -f compose.observability.yaml up --build`) to
send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so run
one example's observability stack at a time.

## On the wire

`verify.sh` asserts, on each stack, after `DELETE /debug/source-calls`:

| Query | Expected |
|---|---|
| `cargo(trackingId: "ABC123") { trackingId description }` | `description` is `Palletized electronics`; the log is exactly `booking.getCargo:ABC123`; no `routing.*` and no `delivery.*` calls |
| `cargo(ABC123) { itinerary { legs { loadLocation { unLocode } } } delivery { transportStatus } }` | `USNYC` and `DEHAM`, `ONBOARD_CARRIER`; the log is exactly `booking.getCargo:ABC123`, `routing.getItinerary:ABC123`, `delivery.getDelivery:ABC123`, `location.getLocation:USNYC`, `location.getLocation:DEHAM`; `getCargo` ends before `getItinerary` and `getDelivery` start; `getItinerary` ends before `getLocation:USNYC` starts; `getItinerary` and `getDelivery` overlap; the two `getLocation` calls overlap; one `request` id on every entry |
| `{ b: cargo(XYZ789) { trackingId } a: cargo(ABC123) { trackingId } }` | `data` keys are `b,a`; the two `getCargo` calls overlap; one `request` id. A following request has a different `request` id |
| parse error (unclosed brace) | HTTP 200 on both stacks, `errors`, no `data`, zero source calls |
| unknown field `weight` | HTTP 200, `errors` naming `weight`, no `data`, zero calls |
| fragment cycle `A` and `B` | `errors`, no `data`, zero calls |
| `$t: TrackingId!` given `123` | `errors`, no `data`, zero calls |
| validation error with `Accept: application/graphql-response+json` | Quarkus: `200 application/graphql-response+json`. Python: `200 application/json` |
| two operations `A`, `B`, no `operationName` | Quarkus: `errors`, no `data`, zero calls. Python: runs the first operation (`ABC123`, one `booking.getCargo:ABC123` call) |
| the same document with `operationName` `B` | `XYZ789`; the log is exactly `booking.getCargo:XYZ789` |
| `{ __typename }` | `Query`; zero calls |
| `__type` of `TrackingId`, `UnLocode`, `DateTime` | `SCALAR`; `specifiedByURL` null, `https://unece.org/trade/uncefact/unlocode`, `https://www.rfc-editor.org/rfc/rfc3339` |
| live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice) |

Error messages differ by stack and are not compared. For the unknown field Quarkus answers
`Validation error (FieldUndefined@[cargo/weight]) : Field 'weight' in type 'Cargo' is undefined`
and omits `data`; Python answers `Cannot query field 'weight' on type 'Cargo'.` with
`"data":null`.

Pinned versions: Quarkus platform 3.40.1 (SmallRye GraphQL 2.18.5), Strawberry 0.335.0 (graphql-core
3.3.0), FastAPI 0.143.2, uvicorn 0.54.0, pydantic-settings 2.16.0, on `ubi10/openjdk-25:1.24-16`
(JDK 25) and `ubi10/python-314-minimal:10.2-1791928506` (Python 3.14). The Python dependencies are
locked in `python/uv.lock`.

## Code-first notes

**Quarkus.** Resolvers that read a source return `Uni<T>`, Mutiny's lazy single-value type, on
both `@Query` methods and `@Source` field methods in `TrackingApi`. `@Source` methods hold the
fields another service owns (`Cargo.itinerary`, `Cargo.delivery`, `Leg.voyage`,
`Leg.loadLocation`, `Leg.unloadLocation`); the matching record components are not in the schema
(`@Ignore` on `Leg`'s codes, no component on `Cargo`). A method takes the SmallRye
`io.smallrye.graphql.api.Context` as a parameter and reads `getExecutionId()` at entry; that id is
passed to the source as an argument because the continuation of a delayed `Uni` does not resume on
the request's thread. `SourceCalls.call` wraps a lookup in
`Uni.createFrom().deferred(...)`, an `afterLatency` step that applies `onItem().delayIt().by(latency)` and applies it only when the latency is above zero, and `.eventually(...)`, so the clock
starts when the engine subscribes and the entry is written when the call ends. `DebugResource` is a
`quarkus-rest-jackson` resource. `ContractSchemaDetails` is unchanged from Chapter 3, including
`withCurrentTypes`.

Observed with SmallRye GraphQL 2.18.5 (not part of `verify.sh`):

- `Uni` resolvers are subscribed on a Vert.x event-loop thread and resume there after the delay;
  no worker thread is held while the call waits. Sibling `Uni` fields overlap.
- A resolver that returns a plain value is a blocking method: SmallRye runs each call on its own
  worker thread (`executor-thread-N`), so two blocking siblings also overlap, at the cost of one
  worker thread each for the length of the call.

**Python.** `async def` resolvers on `Cargo`, `Leg` and `Query`, reading sources through
`info.context`. `GraphQLRouter(schema, context_getter=get_context)` builds a `TrackingContext` per
request (`app/deps.py`) holding a uuid4 `request_id` and the five sources bound to it, so every
call of one request carries one id. graphql-core awaits sibling coroutines together, so sibling
fields overlap. `Settings` (pydantic-settings, `TRACKING_` prefix) reads the two environment
variables; the debug router is included only when `TRACKING_DEBUG_ENDPOINTS=true`.

Observed with Strawberry 0.335.0 (not part of `verify.sh`): the same two resolvers written as
plain `def` with a blocking call run one after the other, 250 ms each, on the event loop. When no
`operationName` is sent, Strawberry runs the first operation of the document, because its
execution context takes the first operation's name when none is sent; SmallRye rejects the request,
as the specification's `GetOperation` describes.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/06-execution-model-architecture.py`) show the compose topology: a
client sending queries to each stack, the source-call log each stack serves, both stacks diffed
against the canonical SDL, and the opt-in `compose.observability.yaml` override.
