# Ch20 - Federation and schema composition

The tracking view split by ownership into a cargo subgraph and a handling subgraph, each on both stacks
(SmallRye GraphQL on Quarkus, Strawberry on FastAPI). A composer turns a pair of subgraphs into a
supergraph file, and two Hive Gateways serve the two pairs: gateway A composes cargo on Quarkus with
handling on Python, gateway B the reverse. `verify.sh` asserts the subgraph contract directly, the
composition gate with two failing fixtures, the query plan of one query counted from the subgraphs'
source-call logs, a mutation and its payload across subgraphs, the canonical contract through both
gateways, and what a client sees when a subgraph is down.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. Each gateway serves all of it except
`Query.node`, `Query.nodes` and `Subscription`. `node` and `nodes` would need entity interfaces to
dispatch across subgraphs, and `Subscription` is Chapter 21. Federation directives live only in the
subgraph schemas and the fixtures, never in `contracts/`.

| Subgraph | Owns | Entities and references |
|---|---|---|
| cargo | `Query.cargo`, `cargos`, `location`, `voyage`; `Cargo.{id, trackingId, description, origin, destination, routeSpecification, itinerary}`; `Location`, `Voyage`, `CarrierMovement`, `RouteSpecification`, `Itinerary`, `Leg`, `CargoConnection`, `CargoEdge` | `Cargo @key(trackingId)`, `Location @key(unLocode)`, `Voyage @key(number)`, all resolvable |
| handling | `Mutation.registerHandlingEvent`; `Cargo.{trackingId, handlingHistory, delivery}`; `HandlingEvent`, its connection and edge, `Delivery`, `HandlingActivity`, `TransportStatus`, the mutation's input, payload and `UserError` | `Cargo @key(trackingId)`, `HandlingEvent @key(id)`; `Location @key(unLocode, resolvable: false)` and `Voyage @key(number, resolvable: false)` as references |
| both | `Node`, the scalars, `RoutingStatus`, `PageInfo @shareable`; every description copied from the canonical SDL | |

Both subgraphs read the booking and routing sources of Chapter 13: the delivery state compares a cargo's
itinerary with its handling history. The cargo subgraph exposes them as types; the handling subgraph
keeps the route specification and the itinerary behind its `delivery` field. Both declare Federation 2.7
with a schema-level `@link` that imports `@key` and `@shareable`.

## Layout

| Path | What it is |
|---|---|
| `quarkus/cargo/`, `quarkus/handling/` | The two Quarkus subgraphs: SmallRye GraphQL with `@Key`, `@Shareable`, `@Resolver` and `@Link` |
| `python/cargo/`, `python/handling/` | The two Python subgraphs: `strawberry.federation` with `keys=[...]` and `resolve_reference` |
| `gateway/` | One Node project and one image with two roles: `compose-supergraph.mjs` (the composer) and `hive-gateway` (the gateway). `package-lock.json` is committed and the image installs with `npm ci` |
| `fixtures/` | `cargo.graphql`, a copy of the cargo subgraph's SDL, and two handling subgraph SDLs with one mistake each |
| `compose.yaml`, `verify.sh`, `architecture.svg` | Topology, verification, diagram |

## Run it

```bash
bash examples/20-federation/verify.sh
```

`verify.sh` brings the stack up with `docker compose`, runs the cases below in a fixed order, diffs both
gateways against `contracts/schema/` and tears the stack down. It prints `PASS` only if every check
holds. It needs Docker Engine with the `docker compose` plugin and Node/npm (for the pinned
`graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/20-federation/compose.yaml up -d --build
curl -s localhost:8300/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { description delivery { transportStatus } } }"}'
curl -s localhost:8302/debug/source-calls
docker compose -f examples/20-federation/compose.yaml down -v
```

## Composition

Composition is a build step. `compose-supergraph.mjs` (about 50 lines, `graphql` and
`@theguild/federation-composition` only) reads each subgraph's `{ _service { sdl } }` from a URL
(`--subgraph name=url`) or an SDL file (`--file name=path`), calls `composeServices`, and writes one
supergraph file (`--out`). On a composition error it prints one line per error, `<code>: <message>`, and
exits `1` without writing a file. In compose, `composer-a` and `composer-b` are two one-shot instances of
one service definition. Each waits for its two subgraphs to be healthy and writes `supergraph-a.graphql` or
`supergraph-b.graphql` to the `supergraph` volume; each gateway starts after its composer completes
successfully and loads the file read-only.

To compose a fixture by hand, with the stack up:

```bash
docker compose -f examples/20-federation/compose.yaml run --rm -T composer-a --out /tmp/rejected.graphql \
  --file cargo=/fixtures/cargo.graphql --file handling=/fixtures/handling-key-type-conflict.graphql
```

## The source-call log (lab only)

`GET /debug/source-calls` on a subgraph answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE`
clears the log and answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`.
A bulk call is one entry whose key joins its keys with `+`. The endpoints answer only when
`TRACKING_DEBUG_ENDPOINTS=true` (compose sets it) and sit beside `/graphql`, so the GraphQL schema is the
same with them on or off. The `request` of an entry identifies one HTTP request to that subgraph, so the
number of distinct values after one client request is the number of subgraph fetches.

## Ports

| Service | Container | Host | Endpoint |
|---|---|---|---|
| gateway-a (cargo Quarkus, handling Python) | 4000 | 8300 | `/graphql` (readiness at `/readiness`) |
| gateway-b (cargo Python, handling Quarkus) | 4000 | 8301 | `/graphql` |
| cargo subgraph, Quarkus | 8080 | 8302 | `/graphql` (health at `/q/health`) |
| cargo subgraph, Python | 8080 | 8303 | `/graphql` (health at `/health`) |
| handling subgraph, Quarkus | 8080 | 8304 | `/graphql` |
| handling subgraph, Python | 8080 | 8305 | `/graphql` |
| composer-a, composer-b | | | none (one-shot) |

This chapter departs from "Quarkus first, Python second" for the gateways: its ports are the two gateways
at `8300` and `8301`, then the four subgraphs in the order above. Compose project `gql-ch20-federation`,
containers `ch20-federation-*`. The example sends no telemetry; Chapter 19 covers observability.

## On the wire

Each value below is asserted by `verify.sh`. Source calls are counted at 100 ms of source latency, which
compose sets; the counts do not depend on it.

| Case | Request | Gateway A / the subgraphs it composes | Gateway B / the subgraphs it composes |
|---|---|---|---|
| subgraph SDL | `_service { sdl }` on each subgraph | `Cargo @key(fields: "trackingId")`; handling's `Location` and `Voyage` have `resolvable: false`; `@link` to Federation 2.7; `PageInfo @shareable`; the cargo subgraph has no `handlingHistory` or mutation | the same |
| entities, direct | `_entities` of `ABC123` and `ZZZ999` | cargo: `[{description: "Palletized electronics"}, null]`, one `getCargos` `ABC123+ZZZ999`; handling: `ONBOARD_CARRIER`, null | the same |
| entities, locations | five `Location` representations, `DEHAM` twice | one `location.getLocations:DEHAM+NLRTM+SGSIN+USNYC` in one request; names in order | the same |
| entities, voyages | `V100S`, `V999X` | `[V100S, null]` | the same |
| composition | both pairs, at startup | `composer-a` and `composer-b` exit 0 | |
| fixture 1 | `handling-key-type-conflict.graphql` (`Location.unLocode: String!`) | exit 1, `FIELD_TYPE_MISMATCH` | |
| fixture 2 | `handling-unshared-pageinfo.graphql` (`PageInfo` without `@shareable`) | exit 1, `INVALID_FIELD_SHARING` | |
| `TrackCargo(ABC123)` | `description`, itinerary load locations, `delivery`, two events | `Palletized electronics`; `New York`, `Hamburg`; `ONBOARD_CARRIER`, `New York`; `LOAD`, `RECEIVE` at `New York` | the same |
| the plan | the logs after that one request | cargo: 2 request ids, `booking.getCargo:ABC123`, `routing.getItineraries:ABC123`, `location.getLocations:DEHAM+USNYC` and `location.getLocations:USNYC`; handling: 1 request id, `booking.getCargos:ABC123`, `handling.pageEvents:ABC123`, `routing.getItineraries:ABC123`, `handling.listEventsFor:ABC123` | the same |
| DEF456's history | `handlingHistory(first: 7)` with `location { name }` | cargo: 2 request ids, one `location.getLocations:DEHAM+NLRTM+USNYC` | the same |
| `cargos(first: 10)` | GHI345 is the sixth edge | 6 errors, one per edge, all nodes null; `SERVICE_UNAVAILABLE` and `booking service unavailable` at `["cargos","edges",5,"node"]` | 1 error at edge 5; five nodes resolved |
| write | `registerHandlingEvent` `UNLOAD` `DEHAM` `V100S` for `ABC123`, key `ch20-reg-a1`, with `cargo { description delivery }` | `evt_10`, `Palletized electronics`, `IN_PORT`, one `handling.appendEvent:evt_10`, one cargo-subgraph `booking.getCargos:ABC123`; a repeat returns `evt_10` and writes nothing | the same |
| schema | each gateway's introspected schema | conforms to `contracts/schema/`; only `Query.node`, `Query.nodes` and `Subscription` unserved; `finalArrivalDate` deprecated; `UnLocode` and `DateTime` have their `specifiedByURL`; `Node` has four possible types | the same |
| no federation surface | `__schema { directives }`, `Query` fields | `include`, `skip`, `deprecated`, `specifiedBy`, `oneOf`; `cargo`, `cargos`, `location`, `voyage` | the same |
| a subgraph stopped | `TrackCargo` with the handling subgraph stopped | `data.cargo` null, an error at `["cargo","delivery"]`; `location(NLRTM)` still `Rotterdam`; `cargo { description itinerary }` still resolves | the same |

## Code-first notes

The example runs on the pinned versions: Quarkus 3.40.1 with SmallRye GraphQL 2.18.5 on graphql-java 25.0
and the federation support of `federation-graphql-java-support` 6.2.1; Strawberry 0.335.0 on graphql-core
3.3.0; Hive Gateway 2.15.2 and `@theguild/federation-composition` 0.27.0 on UBI Node 24, with `graphql`
16.14.2.

**Entity resolvers.** On SmallRye a `@Resolver` method takes one `List` parameter named after the key field
and, with `quarkus.smallrye-graphql.federation.batch-resolving-enabled=true`, is called once per
`_entities` request with the keys of every representation of its type. The key parameter is a `List<String>`:
the representation's value is a plain string, and the scalar types of the schema stay on the fields. On
Strawberry `resolve_reference` is called once per representation with the key fields as keyword
arguments named as on the wire (`trackingId`, `unLocode`), and the request's `DataLoader` batches the
calls. Both stacks give the same log: one bulk call per type per request.

**References.** `@Key(fields = @FieldSet("unLocode"), resolvable = false)` and
`Key(fields="unLocode", resolvable=False)` print `resolvable: false`, and the handling subgraph's
`Location` and `Voyage` records carry only their key. The delivery derivation builds them from the
seed's UN/LOCODEs and voyage numbers, so the handling subgraph makes no call to the location or voyage
service for a reference.

**`Node` across subgraphs.** `Node` is defined in both subgraphs with `Cargo`, `Location` and `Voyage`
implementing it in the cargo subgraph and `HandlingEvent` in the handling subgraph. Composition accepts the
split, and the gateway lists all four as possible types of `Node`.

**Contract details on SmallRye.** `ContractSchemaDetails` carries the same details as in earlier chapters
(root descriptions, the `specifiedBy` URLs, the date description, the deprecation reason). Because
SmallRye completes the federated schema first, the observer takes the `GraphQL.Builder` event instead of
the `GraphQLSchema.Builder` event, transforms the finished schema, and answers `_service { sdl }` with the
federation SDL of the transformed schema. The SDL opens with the schema-level `@link`, and each scalar's
`@specifiedBy` URL is added to it, which is what a composer reads.

**The gateway.** Hive Gateway 2.15.2 loads the supergraph file with `hive-gateway supergraph <file>`. Its
readiness endpoint is `/readiness`. It adds `extensions.serviceName` to an error that a subgraph reported
and keeps the subgraph's `extensions.code`. Its API schema carries no federation directive, so
`assert_sdl_conforms` runs with the default filters. The image is `ubi10/nodejs-24` for the build and
`ubi10/nodejs-24-minimal` for the runtime; the minimal image has `node`, which the health check uses.

**Query plan.** The counts in the table come from the run. The gateway plans three fetches for
`TrackCargo` (cargo, handling, cargo), and `verify.sh` reads them as request ids in the subgraphs' logs.
A different gateway version could plan differently; the figure and the assertions are for 2.15.2.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/20-federation-architecture.py`) show the compose topology: a client of
two gateways, four subgraphs, the two one-shot composers and the supergraph volume.
