# Ch21 - Real-time: subscriptions vs SSE vs WebSockets

`Subscription.cargoHandled` completes the canonical SDL. Both stacks serve it over WebSocket with
`graphql-transport-ws` (and the older `graphql-ws`), Strawberry also serves it over GraphQL-over-SSE
(`graphql-sse`), and both stacks serve a plain SSE feed that resumes from `Last-Event-ID`. A small
Python client on `gql[websockets]` runs on the compose network and reads the subscription;
neither server carries protocol code of its own. `verify.sh` registers handling events, reads each
transport's frames, and asserts order, per-event execution, cleanup and resume on both stacks.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL, and this chapter serves all of it:
`assert_sdl_equals` compares each live schema with it in both directions. The new field is

```graphql
type Subscription {
  cargoHandled(trackingId: TrackingId!): HandlingEvent!
}
```

The rest is Chapter 13's tracking view: the same seed, the same asynchronous sources and source-call
log, SmallRye `@Source List` batch resolvers on Quarkus and DataLoaders on Python. The first new
registration is `evt_10`.

### Where each transport is served

| Transport | Quarkus (port 8310) | Python (port 8311) |
|---|---|---|
| `graphql-transport-ws` on `/graphql` | yes | yes |
| `graphql-ws` (the older subprotocol) on `/graphql` | yes | yes |
| `graphql-sse`: `POST /graphql` with `Accept: text/event-stream` | not served; subscriptions use WebSocket | yes |
| plain SSE feed `GET /events/cargos/{trackingId}` | yes | yes |

## Run it

```bash
bash examples/21-real-time/verify.sh
```

`verify.sh` brings both services up with `docker compose`, builds and runs the subscription client on
the compose network, runs the cases below in a fixed order, and tears the stack down. It prints `PASS`
only if every check holds on **both** stacks. It needs Docker Engine with the `docker compose` plugin
and Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/21-real-time/compose.yaml up -d --build
# a subscriber: two events for ABC123, with the frames on stderr
docker compose -f examples/21-real-time/compose.yaml run --rm -T client \
  --url ws://python:8080/graphql --tracking-id ABC123 --count 2 --frames
# in another shell: register events (see verify.sh for the mutation)
curl -N localhost:8310/events/cargos/ABC123            # the plain SSE feed
curl -s localhost:8311/debug/subscribers               # live subscriptions
docker compose -f examples/21-real-time/compose.yaml down -v
```

`client/subscribe.py` takes `--url`, `--subprotocol` (`graphql-transport-ws` or `graphql-ws`),
`--tracking-id`, `--count`, `--timeout`, `--query FILE` and `--frames`. It prints one JSON line per
`next` payload, `{"error": [...]}` for a GraphQL error and `{"complete": true}` when the server
completes; it exits 0 after `--count` events, 1 on an error and 2 on timeout. With `--frames` the
frames gql exchanges (`>>>` sent, `<<<` received) go to stderr.

## The subscriber registry and the source-call log (lab only)

`GET /debug/subscribers` answers `{"graphql": {"ABC123": 1}, "sse": {"ABC123": 0}}`: the live
subscriptions per channel and tracking id. `graphql` counts `Subscription.cargoHandled` on every
transport; `sse` counts the plain feed. A cargo that has had a subscriber stays listed, at 0, after
the last one leaves. `verify.sh` waits on this count before every registration, so the subscription
exists before the event it must hear, and ends every case with the count back at 0.

`GET /debug/source-calls` is Chapter 13's log: `200 {"calls":[...]}`, `DELETE` clears it. Both
endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it) and sit beside
`/graphql`, so the schema is the same with them on or off.

## Ports

| Stack | Container | Host | Endpoints |
|---|---|---|---|
| Quarkus | 8080 | 8310 | `/graphql` (HTTP and WebSocket), `/events/cargos/{id}`, health at `/q/health` |
| Python | 8080 | 8311 | `/graphql` (HTTP, WebSocket and SSE), `/events/cargos/{id}`, health at `/health` |

The `client` service publishes no port. Compose project `gql-ch21-real-time`, containers
`ch21-real-time-*`. Telemetry is off by default. Add the observability file (`docker compose -f
compose.yaml -f compose.observability.yaml up --build`) to send it to LGTM, which publishes the
fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so run one example's observability stack at
a time.

## On the wire

Each value below is asserted by `verify.sh` unless marked. The registrations are `REG_A1` (ABC123 `UNLOAD` at
`DEHAM` on `V100S`, `2026-10-09T15:00:00Z`), `REG_D1` (DEF456 `CUSTOMS` at `NLRTM`) and `REG_A2`
(ABC123 `LOAD` at `DEHAM` on `V100S`, `2026-10-09T18:00:00Z`).

| Case | Quarkus | Python |
|---|---|---|
| schema | `assert_sdl_equals`: the live schema equals the canonical SDL; `finalArrivalDate` is deprecated | the same |
| invalid document | `cargoHandled { weight }` over `graphql-transport-ws`: an `error` frame naming `weight`, client exit 1, no subscriber | the same |
| `graphql-transport-ws` | subscribe ABC123, count 2; `REG_A1` is `evt_10`, `REG_D1` is `evt_11`, `REG_A2` is `evt_12`; the client prints exactly `evt_10` then `evt_12`, `location.name` `Hamburg` both times, `transportStatus` `IN_PORT` then `ONBOARD_CARRIER`; DEF456's event never arrives | the same |
| frames | `connection_init`, `connection_ack`, `subscribe`, `next`, `next`, `complete` | the same |
| per-event execution | two events make two `booking.getCargos`, two `location.getLocations` (`DEHAM` each), two `routing.getItineraries` and two `handling.listEventsFor`; those eight calls share one request id | the same |
| live order | three registrations sent at once, count 3: the ids arrive in registration order | the same |
| cleanup | `/debug/subscribers` `.graphql.ABC123` is 0 within 5 s of the client's `complete`, and within 5 s of `docker kill` on a client that asked for five events and read one | the same |
| `graphql-ws` | subscribe with the older subprotocol; one event; frames `connection_init`, `connection_ack`, `start`, `data`, `stop`, `connection_terminate` | the same |
| GraphQL over SSE | not served | `POST /graphql` with `Accept: text/event-stream`: `Content-Type: text/event-stream`; one `event: next` whose `data.data.cargoHandled.id` is the new event id; the count returns to 0 |
| plain SSE feed | `GET /events/cargos/ABC123`: `Content-Type: text/event-stream`; one `event: handled` whose `id` is the new event id and whose data is `{"id","trackingId":"ABC123","type":"CUSTOMS","location":"DEHAM","completionTime":"2026-10-09T22:00:00Z"}` | the same |
| resume | `Last-Event-ID: evt_10` replays `evt_12` to `evt_18`, then the live `evt_19`; each id once, in order | replays `evt_12` to `evt_19`, then the live `evt_20` |
| lagging subscriber | a queue of 100 per watcher (not exercised by `verify.sh`) | 102 appends to a fresh store before the subscriber reads again: the next result is the error `Internal server error.`, and the registry is back to 0 |

## Code-first notes

The example runs on the pinned versions (SmallRye GraphQL 2.18.5 on graphql-java 25.0, Mutiny, Quarkus
3.40.1; Strawberry 0.335.0 on graphql-core 3.3.0, FastAPI 0.143.2, uvicorn 0.54.0 with its `standard`
extra, which brings the WebSocket implementation; `gql` 4.4.0 with `websockets` 17.2).

**The event path.** The handling store broadcasts each new event after it is stored and never for an
idempotent replay. On Quarkus the store owns a Mutiny `BroadcastProcessor`; `watch` gives each subscriber
a `UnicastProcessor` over an `ArrayBlockingQueue` of 100, joined before any replay is read; the watcher leaves the broadcast when its subscriber ends. On Python the
store keeps an `asyncio.Queue(maxsize=100)` per watcher in a registry. Both stacks serve the GraphQL
subscription and the plain feed from the same `watch`, so the two cannot disagree about an event.

**Execution per event.** SmallRye executes the selection set once per emitted `HandlingEvent`, and its
`@Source List` batch resolvers receive that event. Strawberry executes the selection set once per value
the async generator yields. A subscription is one long request: its source calls share one request id,
and every event makes one bulk read for each field that reads a source.

**Loaders per event.** A DataLoader caches by key for its lifetime, and a subscription outlives its
events, so each event must start with empty loaders or `Cargo.delivery` would be answered from the first
event's reads. On Quarkus a graphql-java `Instrumentation` (`EventLoaders`) clears the loaders in
`beginSubscribedFieldEvent`, which graphql-java calls before each event; it is installed through the
`GraphQL.Builder` event, the seam Chapter 14 uses. On Python the generator calls
`info.context.begin_event()` after it receives each record, which replaces the context's loaders; the
generator resumes only after the previous event was executed and sent.

**Context on a WebSocket.** Strawberry builds the context once per connection. `get_calls` and
`get_store` take a Starlette `HTTPConnection`, the base of both `Request` and `WebSocket`, so one set of
dependencies serves HTTP, SSE and WebSocket.

**Transports.** SmallRye GraphQL speaks `graphql-transport-ws` and `graphql-ws` on `/graphql` by
default. Strawberry's `GraphQLRouter(subscription_protocols=...)` lists the protocols it serves; the
example names all three (`GRAPHQL_TRANSPORT_WS_PROTOCOL`, `GRAPHQL_WS_PROTOCOL`, `GRAPHQL_SSE_PROTOCOL`).
The WebSocket upgrade needs a WebSocket implementation in the ASGI server, which is why the image installs
`uvicorn[standard]`.

**Plain SSE.** Quarkus REST produces `MediaType.SERVER_SENT_EVENTS` from a `Multi<OutboundSseEvent>`
built with the injected `Sse`, so each event carries `id:` and `event:`. FastAPI's `EventSourceResponse`
and `ServerSentEvent(id=..., event=..., data=...)` do the same from an async generator. `Last-Event-ID`
is read as a header; the feed replays the cargo's events registered after that id in registration order
(`evt_<n>` ids are issued in that order), then continues live. The subscriber joins the broadcast first
and the live stream skips ids already replayed.

**The client.** `client/subscribe.py` builds a `gql` `Client` over `WebsocketsTransport(url,
subprotocols=[...])` and iterates `session.subscribe(...)`; a subscription document that fails
validation raises `TransportQueryError`, which the script prints as `{"error": [...]}`. It runs in a UBI
10 Python 3.14 image with uv, from `uv.lock` (`gql` 4.4.0, `websockets` 17.2). `verify.sh` runs it with
`compose_run`, so that stdout holds only the client's lines.

**Schema details.** Both stacks give `Subscription` the contract's description. On Quarkus
`ContractSchemaDetails` sets it with the other root descriptions; Strawberry takes it from the type's
`description`. `assert_sdl_equals` ignores one directive line, the `@deprecated` that the canonical file
declares on `Itinerary.finalArrivalDate` and that introspection reports as state; `assert_deprecated`
asserts the state itself.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/21-real-time-architecture.py`) show the compose topology: `verify.sh` and
the subscription client reaching each stack, both stacks diffed against the canonical SDL, and the
opt-in `compose.observability.yaml` override.
