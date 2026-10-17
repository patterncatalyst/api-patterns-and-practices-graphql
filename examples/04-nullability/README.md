# Ch4 - Nullability and null propagation

The Ch3 slice of the tracking view, with the fields that cross a service boundary turned
into resolvers over sources, and three seeded cargos whose sources fail in three ways. The
chapter explains what a failed or empty field does to the rest of the response, and this
example proves it on the wire on both stacks.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves the same
types as Chapter 3:

- `Query.cargo`, `Query.location`, `Query.voyage` and `Query.node`.
- `Cargo` with `id`, `trackingId`, `description`, `origin`, `destination`,
  `routeSpecification`, `delivery` and `itinerary`.
- `RouteSpecification`, `Itinerary`, `Leg`, `Voyage` (`id`, `number`, `schedule`),
  `CarrierMovement`, `Delivery` (all seven fields) and `HandlingActivity`.
- `Location` and the `Node` interface (implemented by `Cargo`, `Location` and `Voyage`).
- The enums `TransportStatus`, `RoutingStatus` and `HandlingEventType`.
- The scalars `TrackingId`, `UnLocode` and `DateTime`.

Not served yet: `Query.cargos`, `Cargo.handlingHistory` and the connection types
(Chapter 12), `Mutation` and the types behind it (Chapter 8), and `Subscription`
(Chapter 21).

What changes from Chapter 3 is where four fields get their values. A `Leg` stores
`voyageNumber`, `loadUnLocode` and `unloadUnLocode`, none of which is a GraphQL field.
`Leg.voyage`, `Leg.loadLocation`, `Leg.unloadLocation` and `Cargo.delivery` are resolvers
that call `VoyageSource`, `LocationSource` and `DeliverySource`. Resolvers are synchronous.
There is no latency in this chapter.

## Run it

```bash
bash examples/04-nullability/verify.sh
```

`verify.sh` brings both services up with `docker compose`, queries the healthy cargos, drives
each fault seed, checks aliases, input-side nullability and the wrapper chains through
introspection, diffs each live schema against `contracts/schema/` and tears the stack down.
It prints `PASS` only if the checks hold on **both** stacks. It needs Docker Engine with the
`docker compose` plugin and Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/04-nullability/compose.yaml up -d --build
curl -s localhost:8140/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"MNO901\") { trackingId itinerary { legs { loadLocation { unLocode } voyage { number } } } } }"}'
docker compose -f examples/04-nullability/compose.yaml down -v
```

Use port `8141` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8140`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8141`.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8140 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8141 | `/graphql` (health at `/health`) |

Compose project `gql-ch04-null`, containers `ch04-null-*`. Telemetry is off by default. Add the
observability file (`docker compose -f compose.yaml -f compose.observability.yaml up --build`) to
send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so run
one example's observability stack at a time.

## The seed

The locations, voyages, `cargo_ABC123` and `cargo_XYZ789` are those of Chapter 3. Three
cargos are added, each with one fault. All three are `USNYC` to `NLRTM` with one leg
(`ABC123`'s itinerary for `PQR234`), delivery `NOT_RECEIVED` and `ROUTED`.

| Cargo | Fault | Which source |
|---|---|---|
| `cargo_JKL567`, "Machine parts" | its one leg is on voyage `V404X` | the voyage source raises "voyage service unavailable" |
| `cargo_MNO901`, "Textiles" | its one leg loads at `XXBAD` | the location source returns null (a dangling reference) |
| `cargo_PQR234`, "Coffee beans" | none in the data | the delivery source raises for `PQR234` |

## On the wire

`verify.sh` asserts, on each stack:

| Check | Expected |
|---|---|
| `XYZ789`, `itinerary` | `null`, no `errors` |
| `JKL567`, `cargo { trackingId itinerary { legs { loadLocation { unLocode } voyage { number } } } }` | 1 error with path `["cargo","itinerary","legs",0,"voyage"]`; `legs[0].voyage` is `null`; `loadLocation.unLocode` is `USNYC`; `trackingId` is `JKL567` |
| `MNO901`, same selection | `data.cargo.itinerary` is `null`; `trackingId` is `MNO901`; 1 error with path `["cargo","itinerary","legs",0,"loadLocation"]` whose message contains `loadLocation` |
| `PQR234`, `cargo { trackingId delivery { transportStatus } }` | `data.cargo` is `null` (`data` is `{"cargo":null}`); 1 error with path `["cargo","delivery"]` |
| `{ ok: cargo(trackingId: "ABC123") {...} bad: cargo(trackingId: "PQR234") {...} }` | `data.ok.trackingId` is `ABC123`; `data.bad` is `null`; 1 error with path `["bad","delivery"]` |
| `PQR234` without `delivery` | no `errors` |
| `cargo(trackingId: null)`; `query($t: TrackingId) { cargo(trackingId: $t) ... }`; `$t: TrackingId!` given `null` | `errors`, no `data` |
| `query @experimental_disableErrorPropagation` on `MNO901` | Quarkus: `loadLocation` stays `null`, `voyage.number` is `V100S`, same error path. Python: unknown directive, `errors`, no `data` |
| `Itinerary.legs`, `Leg.voyage`, `Leg.loadLocation`, `Cargo.delivery`, `Cargo.itinerary` | `NON_NULL>LIST>NON_NULL>OBJECT(Leg)`, `OBJECT(Voyage)`, `NON_NULL>OBJECT(Location)`, `NON_NULL>OBJECT(Delivery)`, `OBJECT(Itinerary)` |
| `node(id: "cargo_ABC123")` and `loc_NLRTM` with `... on` fragments | `Cargo` / `ABC123`, `Location` / `NLRTM` |
| live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice) |

The error messages are not compared across stacks, except that the `MNO901` message contains
`loadLocation`. For a thrown exception SmallRye answers `"System error"` with classification
`DataFetchingException` and Strawberry passes `str(exc)`, `"voyage service unavailable"`.
For a null in a non-null position SmallRye answers `The field at path
'/cargo/itinerary/legs[0]/loadLocation' was declared as a non null type, ...` and graphql-core
answers `Cannot return null for non-nullable field Leg.loadLocation.` Chapter 9 covers
what an error message should carry.

Pinned versions: Quarkus platform 3.40.1 (SmallRye GraphQL 2.18.5), Strawberry 0.335.0,
FastAPI 0.143.2, uvicorn 0.54.0, on `ubi10/openjdk-25:1.24-16` (JDK 25) and
`ubi10/python-314-minimal:10.2-1791928506` (Python 3.14). The Python dependencies are
locked in `python/uv.lock`.

## Code-first notes

**Quarkus.** `Leg` and `Cargo` are records. The stored keys of `Leg` carry `@Ignore`, so
they are not fields. The four resolvers are `@Source` methods in the `@GraphQLApi`
`TrackingApi`: `voyage(@Source Leg leg)` returns `Voyage` (nullable, the default),
`loadLocation`, `unloadLocation` and `delivery` carry `@NonNull`. A Java type is nullable
unless annotated, a primitive `boolean` is `Boolean!`, and the contract's `[Leg!]!` is
`@NonNull List<@NonNull Leg>`. `io.smallrye.graphql.api.DefaultNonNull` (on a class or a
package) flips the default for everything inside it and `io.smallrye.graphql.api.Nullable`
flips one position back; both are marked experimental, and this example keeps explicit
`@NonNull`. Sources are `@ApplicationScoped` beans injected through the constructor. A
source that throws gives `"System error"`: SmallRye hides unchecked-exception messages by
default.

**Python.** `Leg` keeps its stored keys as `strawberry.Private[str]` fields, which are not
part of the schema, and defines `voyage`, `load_location` and `unload_location` as
`@strawberry.field` methods that call the sources in `app/sources.py`. `Cargo.delivery` is a
method the same way. The types that need sources are in `app/graph.py`, the others in
`app/model.py`. Fields are non-null unless the annotation says `| None`, and `list[Leg]` is
`[Leg!]!`; `list[Leg | None] | None` would be `[Leg]`. A raised exception becomes an error
with `str(exc)` as its message.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/04-nullability-architecture.py`) show the compose
topology: a client sending selections to each stack, both stacks diffed against the
canonical SDL, and the opt-in `compose.observability.yaml` override.
