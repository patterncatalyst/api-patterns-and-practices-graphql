# Ch3 - SDL and the type system

The tracking view's object graph, served from an in-memory seed on both stacks. The
chapter walks the type system (scalars, enums, objects, the `Node` interface, wrappers)
and this example proves each part on the wire.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves:

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
(Chapter 21). The objects are embedded: a `Leg` holds its `Voyage` and `Location`
directly, and each cargo's `Delivery` is a stored constant. The only resolvers are the
four `Query` fields.

Quarkus (`quarkus/`) and Python (`python/`) each build their schema **code-first** and
serve identical data.

## Run it

```bash
bash examples/03-sdl-type-system/verify.sh
```

`verify.sh` brings both services up with `docker compose`, queries every served field of
`ABC123` and `XYZ789`, checks the other root fields, `Node` dispatch and the validation
failures, reads the enums, the `Node` interface and the scalars through introspection,
diffs each live schema against `contracts/schema/` and tears the stack down. It prints
`PASS` only if the checks hold on **both** stacks. It needs Docker Engine with the
`docker compose` plugin and Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/03-sdl-type-system/compose.yaml up -d --build
curl -s localhost:8130/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ node(id: \"loc_NLRTM\") { __typename ... on Location { unLocode name } } }"}'
docker compose -f examples/03-sdl-type-system/compose.yaml down -v
```

Use port `8131` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8130`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8131`.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8130 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8131 | `/graphql` (health at `/health`) |

Compose project `gql-ch03-sdl`, containers `ch03-sdl-*`. Telemetry is off by default. Add the
observability file (`docker compose -f compose.yaml -f compose.observability.yaml up --build`) to
send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so run
one example's observability stack at a time.

## The seed

| Object | Values |
|---|---|
| Locations (`loc_<code>`) | USNYC New York US, NLRTM Rotterdam NL, DEHAM Hamburg DE, SGSIN Singapore SG, CNSHA Shanghai CN |
| Voyages (`voy_<number>`) | V100S USNYC to DEHAM, 2026-10-01T08:00:00Z to 2026-10-09T14:00:00Z. V200E DEHAM to NLRTM, 2026-10-10T06:00:00Z to 2026-10-11T18:00:00Z. V300A SGSIN to CNSHA, 2026-11-02T04:00:00Z to 2026-11-06T10:00:00Z |
| `cargo_ABC123` | "Palletized electronics", USNYC to NLRTM, deadline 2026-10-15T00:00:00Z, two legs (V100S, V200E), `ONBOARD_CARRIER`, `ROUTED`, last known USNYC, current voyage V100S, ETA 2026-10-11T18:00:00Z, next UNLOAD at DEHAM on V100S |
| `cargo_XYZ789` | "Frozen seafood", SGSIN to NLRTM, deadline 2026-11-20T00:00:00Z, no itinerary, `NOT_RECEIVED`, `NOT_ROUTED`, nothing else known, next RECEIVE at SGSIN |

## On the wire

`verify.sh` asserts, on each stack:

| Check | Expected |
|---|---|
| `cargo(trackingId: "ABC123")`, every served field | the seed values; `DateTime` as `YYYY-MM-DDTHH:MM:SSZ`; enums as names; `misdirected` `false` |
| `cargo(trackingId: "XYZ789")` | `itinerary`, `lastKnownLocation`, `currentVoyage`, `estimatedTimeOfArrival` and `nextExpectedActivity.voyage` all `null`; no `errors` |
| `location(unLocode: "DEHAM")` | `loc_DEHAM`, `Hamburg`, `DE` |
| `voyage(voyageNumber: "V100S")` | `voy_V100S`; `schedule[0]` USNYC to DEHAM, `2026-10-01T08:00:00Z` and `2026-10-09T14:00:00Z` |
| `location(unLocode: "ZZZZZ")`, `voyage(voyageNumber: "V999X")`, `node(id: "nope")` | `null`, no `errors` |
| `node(id: "loc_NLRTM")`, `cargo_ABC123`, `voy_V200E` | `Location` / `NLRTM`, `Cargo` / `ABC123`, `Voyage` / `V200E` |
| `node(id: "loc_NLRTM") { __typename ... on Cargo { trackingId } }` | exactly `{"__typename":"Location"}` |
| `node(id: "loc_NLRTM") { unLocode }` | HTTP 200, `errors` naming `unLocode`, no `data` |
| `cargo { origin }` | HTTP 200, `errors` naming `origin`, no `data` |
| `cargo { trackingId { x } }` | HTTP 200, `errors`, no `data` |
| `location(unLocode: 123)` and a variable `123` | `errors`, no `data` |
| `TransportStatus`, `RoutingStatus`, `HandlingEventType` | kind `ENUM`; the value sets below |
| `Node` | kind `INTERFACE`; possible types `Cargo`, `Location`, `Voyage` |
| `DateTime`, `UnLocode`, `TrackingId` | kind `SCALAR`; `specifiedByURL` `https://www.rfc-editor.org/rfc/rfc3339`, `https://unece.org/trade/uncefact/unlocode`, `null` |
| live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice) |

Enum value sets: `TransportStatus` is `NOT_RECEIVED, IN_PORT, ONBOARD_CARRIER, CLAIMED,
UNKNOWN`; `RoutingStatus` is `NOT_ROUTED, ROUTED, MISROUTED`; `HandlingEventType` is
`RECEIVE, LOAD, UNLOAD, CUSTOMS, CLAIM`. Strawberry lists values in declaration order and
SmallRye lists them alphabetically, so `verify.sh` compares the sets.

Validation messages differ by stack and are not compared. For
`node(id: "loc_NLRTM") { unLocode }` Quarkus answers `Validation error
(FieldUndefined@[node/unLocode]) : Field 'unLocode' in type 'Node' is undefined` and
omits `data`; Python answers `Cannot query field 'unLocode' on type 'Node'. Did you mean
to use an inline fragment on 'Location'?` with `"data":null`.

Pinned versions: Quarkus platform 3.40.1 (SmallRye GraphQL 2.18.5), Strawberry 0.335.0,
FastAPI 0.143.2, uvicorn 0.54.0, on `ubi10/openjdk-25:1.24-16` (JDK 25) and
`ubi10/python-314-minimal:10.2-1791928506` (Python 3.14). The Python dependencies are
locked in `python/uv.lock`.

## Code-first notes

**Quarkus.** `@Type` records, `@Interface Node` with `getId()` implemented explicitly by
`Cargo`, `Location` and `Voyage` (SmallRye maps interface fields from getter-named
methods), `@Id` for `ID`, `@NonNull` for `T!` (a primitive `boolean` is `Boolean!` with no
annotation), `List<@NonNull Leg>` for `[Leg!]`, and `@Description` on types, fields,
arguments and enum constants. `java.time.Instant` maps to SmallRye's built-in `DateTime`
scalar. `TrackingId` and `UnLocode` are `@CustomScalar` records implementing
`CustomStringScalar`.

Observed with SmallRye GraphQL 2.18.5:

- `Instant` serializes as `2026-10-01T08:00:00Z`, whole seconds, suffix `Z`.
- SmallRye's defaults append ` (ISO-8601)` to the description of every date-typed field and
  describe the scalar itself as "Scalar for DateTime" with no `specifiedByURL`.
- `@Description` on enum constants reaches introspection and the printed SDL.
- Enum values come back in alphabetical order, not declaration order: SmallRye reads the
  constants from its build-time index (Jandex), which sorts fields by name.
- Types rebuilt with graphql-java's `SchemaTransformer` need each interface's type
  resolver to return the rebuilt types, so that `... on Location` matches.

`ContractSchemaDetails` covers the descriptions, the URLs and the resolvers. It observes the schema builder
(`quarkus.smallrye-graphql.events.enabled=true`), sets the `Query` description, the
`DateTime` description and `specifiedByURL`, the `UnLocode` `specifiedByURL`, strips the
` (ISO-8601)` suffix, and re-points each interface's type resolver at the type in the
executing schema. The canonical SDL is never edited to match a framework.

**Python.** `@strawberry.type` and `@strawberry.interface` classes in `app/model.py`,
the seed in `app/data.py`, the root fields in `app/schema.py`. Fields are non-null unless
the annotation says `| None`, `list[Leg]` is `[Leg!]!`, and snake_case becomes camelCase
(`un_locode` is `unLocode`). Enums use `strawberry.enum_value(..., description=...)`.
Fields are annotated with Python types (`TrackingId` and `UnLocode` are `NewType`
strings, timestamps the plain `datetime`), and `SCALAR_MAP` in `app/model.py`, passed as
`strawberry.Schema(..., config=StrawberryConfig(scalar_map=SCALAR_MAP))`, maps each type
to its `strawberry.scalar(name=...)` definition. For `datetime` that replaces Strawberry's
built-in `DateTime` with a serializer that writes UTC with a `Z` suffix and a parser that
rejects non-strings and datetimes without an offset. `scalar_map` is Strawberry's
current form for registering custom scalars.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/03-sdl-type-system-architecture.py`) show the compose
topology: a client sending selections to each stack, both stacks diffed against the
canonical SDL, and the opt-in `compose.observability.yaml` override.
