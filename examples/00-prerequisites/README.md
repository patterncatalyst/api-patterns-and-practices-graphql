# Ch0 - Prerequisites SKELETON: Query.cargo (canned)

The minimal both-stack skeleton that proves the toolchain works, before later
chapters put real resolvers behind it. The contract is the only thing that
matters here:

- `contracts/schema/shipping/*.graphql` - the canonical SDL. This chapter serves
  one slice of it: `Query.cargo(trackingId: TrackingId!): Cargo`, with `Cargo`
  limited to `id`, `trackingId`, `description`, `origin` and `destination`, the
  `Location` type (`id`, `unLocode`, `name`, `country`), the `Node` interface
  and the `TrackingId` and `UnLocode` scalars. Every type, field, nullability
  and description in the slice matches the canonical SDL.

Quarkus (`quarkus/`, host port 8080) and Python (`python/`, host port 8081)
each build their own schema **code-first** and both return the same canned
cargo - no persistence, nothing computed from the request. The chapter proves
that the build, the HTTP endpoint, introspection and Compose all work, and that
the code-first schema agrees with the canonical SDL.

## Run it

```bash
cd examples/00-prerequisites
./verify.sh
```

This brings both services up with `docker compose`, waits for each `/graphql`
endpoint to answer `{ __typename }`, queries `cargo(trackingId: "ABC123")`,
asserts every returned value, asserts an unknown id returns `null` and that a
missing argument or a number for `TrackingId` returns a top-level error, asserts
`TrackingId` and `UnLocode` are scalars in the live schema with the canonical
`@specifiedBy` URL, diffs the live schema against
`contracts/schema/` with GraphQL Inspector, and tears the stack down. It prints
`PASS` only if the checks hold for **both** stacks. It needs Docker Engine with
the `docker compose` plugin and Node/npm (for the pinned `graphql-inspector` in
`contracts/`; `verify.sh` runs `npm ci` there if it is missing).

To poke at it by hand instead:

```bash
docker compose up --build
curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { description origin { unLocode name } destination { unLocode name } } }"}'
docker compose down -v
```

Swap `8080` for `8081` to hit the Python stack - same query, same answer.
`compose.yaml` fixes the project name to `gql-ch00-prereq`, the same one
`verify.sh` uses, so a manual run and a `verify.sh` run never collide.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8080 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8081 | `/graphql` (health at `/health`) |

Later chapters use `8100 + 10*NN` for Quarkus and the next port for Python
(`NN` is the chapter number), so no two examples collide with each other or with
this skeleton.

Telemetry is off by default (`QUARKUS_OTEL_SDK_DISABLED` and `OTEL_SDK_DISABLED` are `true`).
Add the observability file to switch the SDKs on and send traces to the Grafana LGTM stack:

```bash
docker compose -f compose.yaml -f compose.observability.yaml up --build
```

## The canned response

`Query.cargo(trackingId: "ABC123")` is hardcoded identically on both stacks:

```
cargo.id                = "cargo_ABC123"
cargo.trackingId        = "ABC123"
cargo.description       = "Palletized electronics"
cargo.origin            = { id: "loc_USNYC", unLocode: "USNYC", name: "New York",  country: "US" }
cargo.destination       = { id: "loc_NLRTM", unLocode: "NLRTM", name: "Rotterdam", country: "NL" }
```

Any other tracking id returns `cargo: null`: `Query.cargo` is nullable in the
canonical SDL, so "not found" is data, not an error.

## Code-first: no codegen, one contract

The gRPC series generates stubs from the `.proto`; GraphQL frameworks go the
other way. Each stack builds its schema from code and the canonical SDL is the
yardstick the live schema is measured against:

- **Quarkus**: `@GraphQLApi` + `@Query` (`TrackingApi`), `@Type` records
  (`Cargo`, `Location`), the `@Interface` `Node`, `@Description` and `@NonNull`
  for documentation and nullability, and `@CustomScalar` classes implementing
  `CustomStringScalar` for `TrackingId` and `UnLocode`. Two details of the SDL
  are set in code: the `Query` type's description (SmallRye's default is
  "Query root") and `@specifiedBy` on `UnLocode`. `ContractSchemaDetails`
  sets both by observing the graphql-java schema builder, the CDI event SmallRye
  fires before it builds the schema
  (`quarkus.smallrye-graphql.events.enabled=true`). SmallRye maps an interface's
  fields from getter-named methods, so `Cargo` and `Location` implement
  `Node.getId()` explicitly. SmallRye Health serves `/q/health`.
- **Python**: `@strawberry.type` / `@strawberry.interface` classes,
  `strawberry.ID`, `strawberry.scalar` definitions for the two custom scalars
  (`NewType` strings mapped through `StrawberryConfig.scalar_map`), mounted with
  `strawberry.fastapi.GraphQLRouter` on FastAPI. Fields are non-null unless typed
  `| None`; Strawberry maps `tracking_id` to `trackingId`. The scalars accept
  only JSON strings, matching SmallRye's `CustomStringScalar`.

The Containerfiles use this directory's `quarkus/` and `python/` as the build
context, so no contract file is copied into an image. For a local, non-container
run: `cd quarkus && mvn quarkus:dev`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8081`.

## On the wire

Introspection is on, so any GraphQL client or `graphql-inspector` can read the
live schema:

```bash
cd contracts && npx graphql-inspector diff http://localhost:8080/graphql "schema/**/*.graphql"
```

`verify.sh` asserts the canned values field by field (see above), then:

| Check | Expected |
|---|---|
| unknown tracking id | `data.cargo == null`, no `errors` |
| `cargo` without `trackingId` | HTTP 200, non-empty top-level `errors`, no `data` |
| `cargo` without `trackingId` | the error message names `trackingId` |
| `trackingId` passed as the number `123` | non-empty top-level `errors`, no `data` |
| `__type(name: "TrackingId").kind` (and `UnLocode`) | `SCALAR` |
| `__type(name: "UnLocode").specifiedByURL` | `https://unece.org/trade/uncefact/unlocode` (`null` for `TrackingId`) |
| live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice) |

Pinned versions: Quarkus platform 3.40.1, SmallRye GraphQL as managed by that
platform, Strawberry 0.335.0, FastAPI 0.143.2, uvicorn 0.54.0, on
`ubi10/openjdk-25:1.24-16` (JDK 25) and `ubi10/python-314-minimal:10.2-1791928506`
(Python 3.14). The Python dependencies are locked in `python/uv.lock`.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/00-prerequisites-architecture.py`) show the skeleton's compose topology: a client
calling `Query.cargo` on each stack over its own port, both stacks diffed
against the canonical SDL, and the opt-in `compose.observability.yaml` override.
