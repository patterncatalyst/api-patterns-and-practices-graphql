# Ch7 - Queries and resolvers

The tracking view's cargo graph with `Cargo.delivery` derived from handling events and the
itinerary instead of stored. Every source-backed field is still asynchronous, each source call
still takes 250 ms and is written to the source-call log, and the example proves each claim of the
chapter by reading that log: which sources a resolver chain calls and with which keys, what the
derived `Delivery` costs, what `@include` and `@skip` prune, and what a repeated field fetches
twice.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves the same types as
Chapters 3 to 6:

- `Query.cargo`, `Query.location`, `Query.voyage` and `Query.node`.
- `Cargo`, `RouteSpecification`, `Itinerary`, `Leg`, `Voyage` (`id`, `number`, `schedule`),
  `CarrierMovement`, `Delivery` (all seven fields), `HandlingActivity`, `Location` and the `Node`
  interface.
- The enums `TransportStatus`, `RoutingStatus` and `HandlingEventType`, and the scalars
  `TrackingId`, `UnLocode` and `DateTime`.

Not served yet: `Query.cargos`, `Cargo.handlingHistory` and the connection types (Chapter 12),
`Mutation` and the types behind it (Chapter 8), and `Subscription` (Chapter 21).

What changes from Chapter 6 is `Cargo.delivery`. The `delivery` source is gone; a `handling` source
returns the events recorded for a cargo, and the resolver derives the `Delivery` from them, the
itinerary and the booking record:

| Source | Operation | Read by |
|---|---|---|
| booking | `getCargo(trackingId)` | `Query.cargo`, `Query.node` for `cargo_*` ids |
| routing | `getItinerary(trackingId)` | `Cargo.itinerary`, `Cargo.delivery` |
| voyage | `getVoyage(number)` | `Query.voyage`, `Query.node` for `voy_*` ids, `Leg.voyage` |
| location | `getLocation(unLocode)` | `Query.location`, `Query.node` for `loc_*` ids, `Leg.loadLocation`, `Leg.unloadLocation` |
| handling | `listEvents(trackingId)` | `Cargo.delivery` |

`ABC123` has two events, `evt_1` (`RECEIVE` at `USNYC`, completed `2026-09-30T16:00:00Z`) and `evt_2`
(`LOAD` at `USNYC` on `V100S`, completed `2026-10-01T08:30:00Z`); `XYZ789` has none. Registration time
is completion time plus five minutes. The events are stored records, not a GraphQL type: `HandlingEvent`
joins the schema in Chapter 8.

### The derivation

The last event is the one with the greatest completion time (a tie goes to the later registration).

| Last event | `transportStatus` | `currentVoyage` | `nextExpectedActivity` |
|---|---|---|---|
| none | `NOT_RECEIVED` | null | `RECEIVE` at the route's origin |
| `RECEIVE` | `IN_PORT` | null | `LOAD` at leg 0's load location on leg 0's voyage (null without an itinerary) |
| `LOAD` at L on V | `ONBOARD_CARRIER` | V | `UNLOAD` at the matching leg's unload location on V |
| `UNLOAD` at L on V | `IN_PORT` | null | `CLAIM` at L if L is the route's destination, else `LOAD` at the next leg's load location on its voyage |
| `CUSTOMS` | `IN_PORT` | null | null |
| `CLAIM` | `CLAIMED` | null | null |

- `lastKnownLocation` is the last event's location.
- `routingStatus` is `NOT_ROUTED` without an itinerary, `MISROUTED` when the first leg does not load at
  the origin or the last leg does not unload at the destination, and `ROUTED` otherwise.
- `misdirected` is true when the last event is a `LOAD` or `UNLOAD` that matches no leg by location
  and voyage. It is false when `NOT_ROUTED` and for the other event types.
- `estimatedTimeOfArrival` is the itinerary's `finalArrivalDate` when `ROUTED` and not misdirected,
  otherwise null.
- An activity that needs a leg the itinerary does not have is null.

For `ABC123` and `XYZ789` the derived values equal the constants Chapters 3 to 6 served. The rules
live in one class that calls no source (`DeliveryDerivation` on Quarkus, `app/derivation.py` on
Python); the resolver fetches `routing.getItinerary` and `handling.listEvents` together and passes
them in.

## Run it

```bash
bash examples/07-queries-resolvers/verify.sh
```

`verify.sh` brings both services up with `docker compose`, resets the log before each case, runs
the queries below, reads the log back, diffs each live schema against `contracts/schema/` and tears
the stack down. It prints `PASS` only if every check holds on **both** stacks. It needs Docker
Engine with the `docker compose` plugin and Node/npm (for the pinned `graphql-inspector` in
`contracts/`). It asserts order and overlap of 250 ms windows, never a duration.

To explore by hand:

```bash
docker compose -f examples/07-queries-resolvers/compose.yaml up -d --build
curl -s -X DELETE localhost:8170/debug/source-calls
curl -s localhost:8170/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { itinerary { legs { loadLocation { unLocode } } } delivery { transportStatus } } }"}'
curl -s localhost:8170/debug/source-calls
docker compose -f examples/07-queries-resolvers/compose.yaml down -v
```

Use port `8171` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8170`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8171`. Set
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
| Quarkus | 8080 | 8170 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8171 | `/graphql` (health at `/health`) |

Compose project `gql-ch07-resolvers`, containers `ch07-resolvers-*`. Telemetry is off by default.
Add the observability file (`docker compose -f compose.yaml -f compose.observability.yaml up
--build`) to send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and
3200, so run one example's observability stack at a time.

## On the wire

`verify.sh` asserts, on each stack, after `DELETE /debug/source-calls`:

| Query | Expected |
|---|---|
| `cargo(ABC123) { itinerary { legs { voyage { number } } } }` | `V100S`, `V200E`; the log is exactly `booking.getCargo:ABC123`, `routing.getItinerary:ABC123`, `voyage.getVoyage:V100S`, `voyage.getVoyage:V200E`; `getCargo` ends before `getItinerary` starts; `getItinerary` ends before each voyage call starts; the two voyage calls overlap; one `request` id |
| `cargo(ABC123) { delivery { transportStatus routingStatus misdirected lastKnownLocation { unLocode } currentVoyage { number } estimatedTimeOfArrival nextExpectedActivity { type location { unLocode } voyage { number } } } }` | `{"transportStatus":"ONBOARD_CARRIER","routingStatus":"ROUTED","misdirected":false,"lastKnownLocation":{"unLocode":"USNYC"},"currentVoyage":{"number":"V100S"},"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V100S"}}}`; the log is exactly `booking.getCargo:ABC123`, `routing.getItinerary:ABC123`, `handling.listEvents:ABC123`; `getCargo` ends before `listEvents` starts; `getItinerary` and `listEvents` overlap |
| the same selection for `XYZ789` | `{"transportStatus":"NOT_RECEIVED","routingStatus":"NOT_ROUTED","misdirected":false,"lastKnownLocation":null,"currentVoyage":null,"estimatedTimeOfArrival":null,"nextExpectedActivity":{"type":"RECEIVE","location":{"unLocode":"SGSIN"},"voyage":null}}`; the same three calls with key `XYZ789` |
| `cargo(ABC123) { description }` | `Palletized electronics`; the log is exactly `booking.getCargo:ABC123` |
| `cargo(trackingId: "NOPE99")`, `voyage(voyageNumber: "V999X")` | `data.cargo` and `data.voyage` are null; no `errors` |
| `query($t: TrackingId! = "ABC123") { cargo(trackingId: $t) { trackingId } }` | `ABC123` with no variables; `XYZ789` with `{"t":"XYZ789"}` |
| `{ ny: location(unLocode: "USNYC") { name } rtm: location(unLocode: "NLRTM") { name } }` | `New York`, `Rotterdam`; the two `getLocation` calls overlap |
| `origin { ...Place } destination { ...Place }`, `fragment Place on Location { unLocode name country }` | `{"unLocode":"USNYC","name":"New York","country":"US"}` and `{"unLocode":"NLRTM","name":"Rotterdam","country":"NL"}` |
| `node(id: "loc_NLRTM") { __typename ... on Location { name } }` | `{"__typename":"Location","name":"Rotterdam"}` |
| `query($full: Boolean!) { cargo(ABC123) { trackingId itinerary @include(if: $full) { legs { loadTime } } delivery @skip(if: $full) { transportStatus } } }` with `full` false | no `itinerary` key; `delivery.transportStatus` is `ONBOARD_CARRIER`; the log is `booking.getCargo`, `routing.getItinerary`, `handling.listEvents` for `ABC123` |
| the same with `full` true | `itinerary.legs.0.loadTime` is `2026-10-01T08:00:00Z`; no `delivery` key; the log is `booking.getCargo`, `routing.getItinerary`; no `handling.*` call |
| a second request without a reset | the log holds at least two distinct `request` ids |
| `cargo(ABC123) { itinerary { legs { a: voyage { number } b: voyage { number } } } }` | four `voyage.getVoyage` calls (two legs by two aliases; no per-request cache) |
| `cargo(ABC123) { itinerary { finalArrivalDate } delivery { transportStatus } }` | two `routing.getItinerary` calls, one from each field |
| `voyage(voyageNumber: "V100S") { schedule { departureLocation { unLocode } arrivalTime } }` | `USNYC`, `2026-10-09T14:00:00Z` |
| `__type` of `TrackingId`, `UnLocode`, `DateTime` | `SCALAR`; `specifiedByURL` null, `https://unece.org/trade/uncefact/unlocode`, `https://www.rfc-editor.org/rfc/rfc3339` |
| live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice) |

Pruning does not make the `routing.getItinerary` call disappear when `full` is false: `delivery` calls it
as an input. What it saves is the second routing call that selecting both fields would make, and, when
`full` is true, the whole derivation and its `handling.listEvents` call. The repeated fetch is left in;
Chapter 13 batches it and this log is the evidence it uses.

Pinned versions: Quarkus platform 3.40.1 (SmallRye GraphQL 2.18.5), Strawberry 0.335.0 (graphql-core
3.3.0), FastAPI 0.143.2, uvicorn 0.54.0, pydantic-settings 2.16.0, on `ubi10/openjdk-25:1.24-16`
(JDK 25) and `ubi10/python-314-minimal:10.2-1791928506` (Python 3.14). The Python dependencies are
locked in `python/uv.lock`.

## Code-first notes

**Quarkus.** Resolvers that read a source return `Uni<T>` on `@Query` methods and `@Source` field
methods in `TrackingApi`; each takes the SmallRye `io.smallrye.graphql.api.Context` and reads
`getExecutionId()` at entry, passing the id to the source. `Cargo.delivery` combines the routing and
handling lookups with `Uni.combine().all().unis(...).with(...)` and hands the results to
`DeliveryDerivation`, an `@ApplicationScoped` bean built on `TrackingData`'s reference data.
`HandlingRecord` is returned by no resolver, so it is not in the schema. The `Context` also carries
the field-level information (`getFieldName()`, `getPath()`, `getSelectedFields()`). Constructor
injection is used throughout, `Cargo` has no component for `itinerary` or `delivery`, and
`ContractSchemaDetails` is unchanged from Chapter 3, including `withCurrentTypes`.

**Python.** `async def` resolvers on `Cargo`, `Leg` and `Query`, reading sources through
`info.context`. `Cargo.delivery` awaits `asyncio.gather` over the routing and handling sources and calls
`info.context.derivation.derive(...)`. `DeliveryDerivation` (`app/derivation.py`) holds the location
and voyage reference maps and is created once in `app/deps.py`; `app/context.py` imports it for type
checking only, which keeps the model, the sources and the context free of import cycles.
`app/handling.py` holds the stored event record. `Settings` (pydantic-settings, `TRACKING_` prefix)
reads the two environment variables; the debug router is included only when
`TRACKING_DEBUG_ENDPOINTS=true`.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/07-queries-resolvers-architecture.py`) show the compose topology: a
client sending queries to each stack, the source-call log each stack serves, both stacks diffed
against the canonical SDL, and the opt-in `compose.observability.yaml` override.
