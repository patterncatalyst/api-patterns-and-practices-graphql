# Ch10 - Schema design patterns

The tracking view's schema, checked against its own conventions. The example adds one root field,
`Query.nodes`, and proves each claim of the chapter against both stacks: every `Node` implementer
refetches to the same object by its id, `nodes` keeps the order of its ids and puts `null` at an
unknown one, and the naming, input, payload and description conventions hold in the live schema of
each stack, not only in the canonical SDL.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything Chapter 8
served, plus:

- `Query.nodes(ids: [ID!]!): [Node]!`, with the canonical descriptions.

The slice predates the deprecation that Chapter 11 introduces. It serves `Itinerary.finalArrivalDate`
without the `@deprecated` directive and does not serve `Itinerary.finalArrivalTime`. Conformance
still passes: a field missing from the slice is a slice removal, and a missing deprecation is a
non-breaking difference. `Query.cargos` and `Cargo.handlingHistory` (Chapter 12) and `Subscription`
(Chapter 21) are not served.

The data is the Chapter 8 seed, unchanged: `ABC123` and `XYZ789`, and the handling store with
`evt_1` and `evt_2`.

| Source | Operation | Read by |
|---|---|---|
| booking | `getCargo(trackingId)` | `Query.cargo`, `Query.node` and `Query.nodes` for `cargo_*` ids |
| location | `getLocation(unLocode)` | `Query.location`, `Leg` locations, `loc_*` ids |
| voyage | `getVoyage(number)` | `Query.voyage`, `Leg.voyage`, `voy_*` ids |
| handling | `getEvent(id)` | `evt_*` ids |
| routing, handling | `getItinerary`, `listEvents` | `Cargo.itinerary`, `Cargo.delivery` |

`node` and `nodes` share one helper, `resolveNode` (Quarkus) and `resolve_node` (Python). Each id is
one source call. An unrecognised id makes none. Nothing deduplicates, so a repeated id is fetched
twice; Chapter 13 batches these calls.

## Run it

```bash
bash examples/10-schema-design/verify.sh
```

`verify.sh` brings both services up with `docker compose`, runs the GraphQL ESLint rules on the
canonical SDL, runs the cases below on each stack, diffs each live schema against `contracts/schema/`
and tears the stack down. It prints `PASS` only if every check holds on both stacks. It needs Docker
Engine with the `docker compose` plugin and Node/npm (for the pinned tools in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/10-schema-design/compose.yaml up -d --build
curl -s localhost:8200/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ nodes(ids: [\"cargo_ABC123\", \"loc_NLRTM\", \"nope\"]) { __typename id } }"}'
docker compose -f examples/10-schema-design/compose.yaml down -v
```

Use port `8201` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8200`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8201`. Set
`TRACKING_SOURCE_LATENCY_MS=250 TRACKING_DEBUG_ENDPOINTS=true` to get the compose behaviour. The
compose sets 250; the default of 0 adds no delay.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears it and
answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`. The endpoints
answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it) and are plain HTTP resources beside
`/graphql`. Leave them off anywhere else.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8200 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8201 | `/graphql` (health at `/health`) |

Port 8200 is HashiCorp Vault's default port. If it is in use on your machine, change the published
port in `compose.yaml` and the URL in `verify.sh`.

Compose project `gql-ch10-design`, containers `ch10-design-*`. Telemetry is off by default. Add the
observability file (`docker compose -f compose.yaml -f compose.observability.yaml up --build`) to
send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so run
one example's observability stack at a time.

## On the wire

`verify.sh` runs these in order on each stack.

| Step | Request | Expected |
|---|---|---|
| 1. Refetch | `cargo(trackingId: "ABC123") { id }`, then `node(id:)` with that id | `cargo_ABC123`; `__typename` `Cargo`; `trackingId` `ABC123` |
| | the first leg's `loadLocation { id }`, then `node(id:)` | `loc_USNYC`; `Location`; `unLocode` `USNYC` |
| | the second leg's `voyage { id }`, then `node(id:)` | `voy_V200E`; `Voyage`; `number` `V200E` |
| | `node(id: "evt_1") { id }`, then `node(id:)` | `evt_1`; `HandlingEvent`; `type` `RECEIVE` |
| 2. `nodes` | `nodes(ids: ["cargo_ABC123", "loc_NLRTM", "nope", "voy_V200E", "cargo_ABC123"]) { __typename }` | `Cargo`, `Location`, `null`, `Voyage`, `Cargo`; no `errors` |
| | the source-call log of that request | exactly `booking.getCargo:ABC123`, `location.getLocation:NLRTM`, `voyage.getVoyage:V200E`, `booking.getCargo:ABC123` |
| | ids `voy_V200E`, `evt_1`, `loc_NLRTM`, `cargo_ABC123` with `id` and one inline fragment per type | `V200E`, `RECEIVE`, `NLRTM`, `ABC123` in that order |
| 3. Empty | `nodes(ids: []) { id }` | `[]`; no source call |
| | `nodes(ids: ["cargo", "evt", "cargo_"]) { id }` | `[null, null, null]`; no source call |
| 4. Implementers | `__type(name: "Node") { possibleTypes { name } }`, sorted | `Cargo`, `HandlingEvent`, `Location`, `Voyage` |
| | `Query.nodes` in introspection | `[Node]!`; argument `ids` `[ID!]!`; the canonical description |
| 5. Conventions | one `__schema` request per stack, read by a stdlib checker | no offenders (see below) |
| 6. Lint | `npm --prefix contracts run lint` | exit 0 |
| 7. Payload | `registerHandlingEvent`, `RECEIVE` at `USNYC` with `V100S` | no `errors`; `handlingEvent` null; `[{"code":"VOYAGE_NOT_ALLOWED","field":["input","voyageNumber"]}]` |
| 8. Scalars, conformance | `__type` of `TrackingId`, `UnLocode`, `DateTime`; live schema vs `contracts/schema/` | `SCALAR`; `specifiedByURL` null, `https://unece.org/trade/uncefact/unlocode`, `https://www.rfc-editor.org/rfc/rfc3339`; no breaking change either way and no description change (slice) |

The convention checker asserts, for every type outside `__*`, the built-in scalars and
`LGTM_SDL_FRAMEWORK_TYPES`: PascalCase type names; camelCase field, argument and input field names;
enum values matching `^[A-Z][A-Z0-9_]*$`; every input object ending in `Input`; every `Mutation` field
taking exactly one argument `input` of a non-null input object and returning a non-null object named
`...Payload`; a non-empty description on every type, field, argument, input field and enum value;
and `id: ID!` on every implementer of `Node`. It prints one line per offender.

Pinned versions: Quarkus platform 3.40.1 (SmallRye GraphQL 2.18.5), Strawberry 0.335.0 (graphql-core
3.3.0), FastAPI 0.143.2, uvicorn 0.54.0, pydantic-settings 2.16.0, on `ubi10/openjdk-25:1.24-16`
(JDK 25) and `ubi10/python-314-minimal:10.2-1791928506` (Python 3.14). The Python dependencies are
locked in `python/uv.lock`.

## Code-first notes

**Quarkus.**

- `@Query` on `TrackingApi.nodes`, returning `Uni<List<Node>>` with `@NonNull`; the elements are
  nullable, so the SDL is `[Node]!`. The body maps each id through `resolveNode` and joins with
  `Uni.join().all(...).andFailFast()`, which keeps the order of the list. An empty list returns
  `Uni.createFrom().item(List.of())`.
- The `ids` argument is declared `List<@NonNull String>`, and `ContractSchemaDetails`, the schema
  observer the examples already use, gives it the contract's type `[ID!]!`. Introspection and
  `/graphql/schema.graphql` both report `[ID!]!`.
- `ContractSchemaDetails.withCurrentTypes` keeps interface type resolution in step with the
  transformed schema, so a fragment on a `Node` implementer matches.

**Python.**

- `Query.nodes` is `async def` and uses `asyncio.gather` over `resolve_node`, a module-level
  function in `app/schema.py` that `node` also calls. `gather` returns results in argument order.
- The argument type `list[strawberry.ID]` prints `[ID!]!`; the return type `list[Node | None]` prints
  `[Node]!`.

**`@oneOf` check (prose only, not served).** The GraphQL specification's September 2025 edition
defines "OneOf Input Objects". Strawberry 0.335.0: `@strawberry.input(one_of=True)` with fields
declared `str | None = strawberry.UNSET` prints `input CargoBy @oneOf { trackingId: String id: String }`
and rejects a request that sets both fields with `OneOf Input Object 'CargoBy' must specify exactly
one key.` SmallRye GraphQL 2.18.5
ships the annotation `io.smallrye.graphql.api.OneOf`; this example does not exercise it.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/10-schema-design-architecture.py`) show the compose topology: a client
sending queries to each stack, both stacks diffed against the canonical SDL, and the opt-in `compose.observability.yaml` override.
