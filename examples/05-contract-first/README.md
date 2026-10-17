# Ch5 - Schema-first and contract-first

The Ch3 object graph on both stacks, plus the loop that keeps the code-first schemas aligned with the contract:
each stack exports the SDL it builds, the exports and the live introspection are diffed
against the canonical SDL, and five kinds of seeded drift prove that the diff fails when it
should.

## The served slice

The slice is the one Ch3 serves, from the same in-memory seed (healthy cargos `ABC123` and
`XYZ789` only):

- `Query.cargo`, `Query.location`, `Query.voyage` and `Query.node`.
- `Cargo`, `RouteSpecification`, `Itinerary`, `Leg`, `Voyage`, `CarrierMovement`,
  `Delivery`, `HandlingActivity` and `Location`, with `Node` implemented by `Cargo`,
  `Location` and `Voyage`.
- The enums `TransportStatus`, `RoutingStatus` and `HandlingEventType`.
- The scalars `TrackingId`, `UnLocode` and `DateTime`.

Not served yet: `Query.cargos`, `Cargo.handlingHistory` and the connection types (Chapter 12),
`Mutation` and the types behind it (Chapter 8), and `Subscription` (Chapter 21). Objects are
embedded, as in Chapter 3; the only resolvers are the four `Query` fields.

Two things are new:

- **The export.** Quarkus serves its schema at `GET /graphql/schema.graphql`. Python runs
  `strawberry export-schema app.schema:schema` inside the container.
- **The gate.** `verify.sh` diffs the exports and the introspected schemas against
  `contracts/schema/` with the pinned `graphql-inspector`, compares the two exports with each
  other, lints the canonical SDL, and seeds drift into copies of each export.

## Run it

```bash
bash examples/05-contract-first/verify.sh
```

`verify.sh` brings both services up with `docker compose`, checks the Ch3 values and the
scalar `specifiedByURL`s, exports each schema, runs the conformance checks on the exports and
on the live endpoints, compares the two exports, runs `npm --prefix contracts run lint`,
seeds the five drifts into copies of each export, and tears the stack down. It prints `PASS`
only if everything holds on **both** stacks. It needs Docker Engine with the `docker compose`
plugin and Node/npm (for the pinned `graphql-inspector` and GraphQL ESLint in `contracts/`).
The scratch directory it creates for the exports is removed on exit.

To explore by hand:

```bash
docker compose -f examples/05-contract-first/compose.yaml up -d --build
curl -fsS localhost:8150/graphql/schema.graphql | head -20
docker compose -p gql-ch05-contract exec -T python strawberry export-schema app.schema:schema | head -20
cd contracts && npx --no-install graphql-inspector diff http://localhost:8151/graphql 'schema/**/*.graphql'
docker compose -f ../examples/05-contract-first/compose.yaml down -v
```

For a non-container run: `cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8150`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8151` (then
`uv run strawberry export-schema app.schema:schema`).

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8150 | `/graphql`, export at `/graphql/schema.graphql` (health at `/q/health`) |
| Python | 8080 | 8151 | `/graphql` (health at `/health`) |

Compose project `gql-ch05-contract`, containers `ch05-contract-*`. Telemetry is off by default. Add
the observability file (`docker compose -f compose.yaml -f compose.observability.yaml up --build`)
to send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so
run one example's observability stack at a time.

## On the wire

`verify.sh` asserts, on each stack:

| Check | Expected |
|---|---|
| `cargo(trackingId: "ABC123") { trackingId delivery { transportStatus } }` | `ABC123`, `ONBOARD_CARRIER`, no `errors` |
| `__type(name: "TrackingId")`, `"UnLocode"`, `"DateTime"` | kind `SCALAR`; `specifiedByURL` `null`, `https://unece.org/trade/uncefact/unlocode`, `https://www.rfc-editor.org/rfc/rfc3339` |
| the exported SDL | non-empty, contains `type Cargo implements Node`, declares `scalar DateTime` and `scalar UnLocode` |
| the Quarkus export | contains no `@specifiedBy` |
| the Python export | contains `scalar UnLocode @specifiedBy(url: "https://unece.org/trade/uncefact/unlocode")` |
| export vs `contracts/schema/**/*.graphql` | no breaking change in either direction beyond the slice, no changed description |
| live introspection vs `contracts/schema/**/*.graphql` | the same |
| the Quarkus export vs the Python export | identical after the framework filter |
| `npm --prefix contracts run lint` | exit 0 |

Each seeded drift is a `sed` edit of a copy of the stack's export. The edit must change the
copy (`cmp -s` against the export must report a difference, otherwise the fixture failed to
apply and the run fails), the conformance check must then fail, and graphql-inspector's change
line must contain the needle. Both stacks print the same lines:

| Case | Edit | Needle | Change line |
|---|---|---|---|
| tighten | `itinerary: Itinerary` becomes `Itinerary!` on `Cargo` | `Cargo.itinerary` | `✖  Field Cargo.itinerary changed type from Itinerary! to Itinerary` (live to canonical) |
| loosen | `trackingId: TrackingId!` becomes `TrackingId` on `Cargo` | `Cargo.trackingId` | `✖  Field Cargo.trackingId changed type from TrackingId! to TrackingId` (canonical to live) |
| extra field | `weightKg: Float` added to `Cargo` | `weightKg` | `✖  Field weightKg was removed from object type Cargo` (live to canonical) |
| enum value | `UNKNOWN` (and its description) removed from `TransportStatus` | `UNKNOWN` | `✖  Enum value UNKNOWN was removed from enum TransportStatus` (canonical to live) |
| description | `The public tracking identifier.` becomes `Tracking id.` | `Cargo.trackingId` | `✔  Field Cargo.trackingId description changed from The public tracking identifier. to Tracking id.` (canonical to live) |

The description case is reported with a check mark, not a cross: graphql-inspector counts a
description change as safe. The conformance check fails it anyway, because a changed
description on a field both sides have is drift.

Pinned versions: Quarkus platform 3.40.1 (SmallRye GraphQL 2.18.5), Strawberry 0.335.0 with
the `cli` extra, FastAPI 0.143.2, uvicorn 0.54.0, `graphql-inspector` 7.0.1 and GraphQL
ESLint 4.4.2 (from `contracts/package.json`), on `ubi10/openjdk-25:1.24-16` (JDK 25) and
`ubi10/python-314-minimal:10.2-1791928506` (Python 3.14). The Python dependencies are locked
in `python/uv.lock`.

## Code-first notes

**Quarkus.** The code is the Ch3 code. The one change is in `application.properties`:

```properties
quarkus.smallrye-graphql.schema-include-scalars=true
```

What a run of the exporter showed (SmallRye GraphQL 2.18.5):

- With `schema-include-scalars=true`, `GET /graphql/schema.graphql` declares `DateTime`,
  `TrackingId` and `UnLocode`, so `Cargo`'s references to them resolve in graphql-inspector, plus SmallRye's `BigDecimal` and `BigInteger`,
  which `LGTM_SDL_IGNORE` in `lib.sh` filters by name.
- The export prints no `@specifiedBy` on a scalar; introspection reports `specifiedByURL` for
  `DateTime` and `UnLocode`. `schema-include-directives=true` adds the directive definitions
  (`@constraint`, `@defer`, `@deprecated`, `@include`, `@oneOf`, `@rolesAllowed`, `@skip`,
  `@specifiedBy` and `@experimental_disableErrorPropagation`) and the scalars still print without
  `@specifiedBy`. The
  options `schema-include-introspection-types` and `schema-include-schema-definition` are
  left at their defaults.
- Fields print in alphabetical order. A one-line description prints as a `"…"` string and a
  multi-line one as a `"""` block. The export is
  generated from the schema after `ContractSchemaDetails` has run, so it carries the corrected
  `DateTime` description.

**Python.** `strawberry-graphql[cli]==0.335.0` provides the `strawberry` command. No helper
module is needed: `strawberry export-schema app.schema:schema` prints the SDL of the `schema`
object in `app/schema.py`. The export keeps declaration order, writes descriptions as
`"""` blocks and prints `@specifiedBy` on `DateTime` and `UnLocode`. The command runs inside
the container because the application's code and dependencies live there; the entrypoint's
`opentelemetry-instrument` wrapper is not involved.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/05-contract-first-architecture.py`) show the compose topology:
`verify.sh` on the host, the two stacks, the exported SDL in a temporary directory, the
canonical SDL, and the seeded-drift copies.
