# Ch11 - Evolution and versioning

The tracking view's schema, changed the way a schema with clients has to change. The example serves
`Itinerary.finalArrivalTime` beside `Itinerary.finalArrivalDate`, which is deprecated in its favour, on
both stacks. `verify.sh` proves the deprecated field still executes and that introspection flags it
and hides it by default, then runs the breaking-change gate, `contracts/scripts/breaking.sh`, on
fixture copies of the contract: safe, dangerous and breaking changes, the strict mode, and the
deliberate removal of a deprecated field.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything Chapter 10
served, including `Query.nodes`, plus:

- `Itinerary.finalArrivalTime: DateTime!`, the replacement;
- `Itinerary.finalArrivalDate: DateTime! @deprecated(reason: "Use `finalArrivalTime`.")`, still served.

Both fields return the same instant, and `Cargo.delivery` derives the arrival from `finalArrivalTime`.
`Query.cargos` and `Cargo.handlingHistory` (Chapter 12) and `Subscription` (Chapter 21) are not
served, which is a slice removal, so conformance still passes.

The data is the Chapter 8 seed, unchanged: `ABC123` and `XYZ789`, and the handling store with `evt_1`
and `evt_2`. For `ABC123` both fields are `2026-10-11T18:00:00Z`.

The two stacks differ from the contract in nothing but the slice. `assert_sdl_conforms` does not
compare deprecation state (the loss of `@deprecated` is a safe change), so `verify.sh` also calls
`assert_deprecated` and `assert_not_deprecated` on each stack.

## Run it

```bash
bash examples/11-evolution/verify.sh
```

`verify.sh` brings both services up with `docker compose`, runs the GraphQL ESLint rules on the
canonical SDL, runs the deprecation checks on each stack, diffs each live schema against
`contracts/schema/`, runs the gate on the fixtures below and tears the stack down. It prints `PASS`
only if every check holds. It needs Docker Engine with the `docker compose` plugin and Node/npm (for
the pinned tools in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/11-evolution/compose.yaml up -d --build
curl -s localhost:8210/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ __type(name: \"Itinerary\") { fields(includeDeprecated: true) { name isDeprecated deprecationReason } } }"}'
docker compose -f examples/11-evolution/compose.yaml down -v
```

Use port `8211` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8210`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8211`. Set
`TRACKING_SOURCE_LATENCY_MS=250 TRACKING_DEBUG_ENDPOINTS=true` to get the compose behaviour. The
compose sets 250; the default of 0 adds no delay.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears it and
answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`. The endpoints
answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it) and are plain HTTP resources beside
`/graphql`. Leave them off anywhere else. This chapter does not assert on the log.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8210 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8211 | `/graphql` (health at `/health`) |

Compose project `gql-ch11-evolution`, containers `ch11-evolution-*`. Telemetry is off by default.
Add the observability file (`docker compose -f compose.yaml -f compose.observability.yaml up
--build`) to send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and
3200, so run one example's observability stack at a time.

## On the wire

`verify.sh` runs the first group on each stack and the gate cases once.

| Step | Request | Expected |
|---|---|---|
| 1. Both fields | `cargo(trackingId: "ABC123") { itinerary { finalArrivalTime finalArrivalDate } }` | both `2026-10-11T18:00:00Z`; no `errors`; the response does not contain `deprecat` |
| | `itinerary { finalArrivalDate }` alone; `delivery { estimatedTimeOfArrival }` | `2026-10-11T18:00:00Z` |
| 2. Flags | `Itinerary.finalArrivalDate` through `assert_deprecated` | `isDeprecated` true; reason exactly ``Use `finalArrivalTime`.`` |
| | `Itinerary.finalArrivalTime` through `assert_not_deprecated` | `isDeprecated` false |
| | `isDeprecated` over every field, argument, input field and enum value | exactly `Itinerary.finalArrivalDate` |
| 3. Hidden by default | `__type(name: "Itinerary") { fields { name } }`; with `includeDeprecated: false` | `finalArrivalTime`, `legs` |
| | `fields(includeDeprecated: true)` | `finalArrivalDate`, `finalArrivalTime`, `legs` |
| | a selection the schema lacks, `finalArrivalDay` | status 200 or 400, an error naming the field, no `data` |
| 4. Conformance | live schema vs `contracts/schema/` | no breaking change either way and no description change (slice) |
| 5. Gate | the fixtures below | the exit codes and change lines below |
| 6. Lint | `npm --prefix contracts run lint` | exit 0 |
| 7. Scalars | `__type` of `TrackingId`, `UnLocode`, `DateTime` | `SCALAR`; `specifiedByURL` null, `https://unece.org/trade/uncefact/unlocode`, `https://www.rfc-editor.org/rfc/rfc3339` |

### The gate fixtures

No fixture file is committed. Each case copies `contracts/schema` to a base and a new directory,
applies the edit to the new side (the base for case 2) and runs `breaking.sh` with `BASE_DIR`, `NEW_DIR`
and `BREAKING_RULES` through `assert_gate`. An edit replaces text that occurs exactly once in its file,
and a fixture that does not apply fails the run. The needle is a full change line from the tool's
output, including its mark. Needles are matched with the harness's own `lib.sh:` lines excluded.

| # | Case | Edit | Rules | Exit | Change line |
|---|---|---|---|---|---|
| 1 | no change | none | | 0 | `No changes detected` |
| 2 | the real Chapter 11 change | base: the contract without `finalArrivalTime` and `@deprecated` | | 0 | `✔  Field Itinerary.finalArrivalDate is deprecated`, `✔  Field finalArrivalTime was added to object type Itinerary` |
| 3 | safe: add field | `timeZone: String` with a description, added to `Location` | | 0 | `✔  Field timeZone was added to object type Location` |
| 4 | safe: optional input field | `operatorId: String` added to `RegisterHandlingEventInput` | | 0 | `✔  Input field operatorId of type String was added to input object type RegisterHandlingEventInput` |
| 5 | safe: tighten output | `itinerary: Itinerary` to `Itinerary!` on `Cargo` | | 0 | `✔  Field Cargo.itinerary changed type from Itinerary to Itinerary!` |
| 6 | dangerous: enum value | `TRANSSHIP` added to `HandlingEventType` | | 0 | `⚠  Enum value TRANSSHIP was added to enum HandlingEventType` |
| 7 | dangerous, strict | the same edit | `dangerousBreaking` | 1 | `✖  Enum value TRANSSHIP was added to enum HandlingEventType` |
| 8 | dangerous: optional argument | `destination: UnLocode` added to `Query.cargos` | | 0 | `⚠  Argument destination: UnLocode added to field Query.cargos` |
| 9 | breaking: remove field | `Leg.unloadTime` and its description deleted | | 1 | `✖  Field unloadTime was removed from object type Leg` |
| 10 | breaking: loosen output | `trackingId: TrackingId!` to `TrackingId` on `Cargo` | | 1 | `✖  Field Cargo.trackingId changed type from TrackingId! to TrackingId` |
| 11 | breaking: required input | `operatorId: String!` added to the input | | 1 | `✖  Input field operatorId of type String! was added to input object type RegisterHandlingEventInput` |
| 12 | breaking: remove enum value | `UNKNOWN` deleted from `TransportStatus` | | 1 | `✖  Enum value UNKNOWN was removed from enum TransportStatus` |
| 13 | lifecycle: remove the deprecated field | `finalArrivalDate` and its description deleted | | 1 | `✖  Field finalArrivalDate (deprecated) was removed from object type Itinerary` |
| 14 | lifecycle: deliberate removal | the same edit | `suppressRemovalOfDeprecatedField` | 0 | `⚠  Field finalArrivalDate (deprecated) was removed from object type Itinerary` |
| 15 | breaking: tighten input | `voyageNumber: String` to `String!` | | 1 | `✖  Input field RegisterHandlingEventInput.voyageNumber changed type from String to String!` |
| 16 | safe: loosen input | `completionTime: DateTime!` to `DateTime` | | 0 | `✔  Input field RegisterHandlingEventInput.completionTime changed type from DateTime! to DateTime` |
| 17 | dangerous: union member | a union `SearchResult = Cargo \| Location` in both directories; `Voyage` added in the new one | | 0 | `⚠  Member Voyage was added to Union type SearchResult` |
| 18 | dangerous: type gains an interface | `Leg implements Node` with an `id` field | | 0 | `⚠  Leg object implements Node interface` |
| 19 | safe: new implementer | a new type `Vessel implements Node` | | 0 | `✔  Type Vessel was added` |
| 20 | deprecation is outside conformance | the contract without `@deprecated` | | 0 | `✔  Field Itinerary.finalArrivalDate is no longer deprecated`; `assert_sdl_conforms` also passes |

Case 6 is run a second time with `GITHUB_ACTIONS=true` and asserts exit 0 and a
`::warning title=Dangerous schema change::` line that carries the change line.

Each needle is the text the tool printed, which writes names without quotes (`Field timeZone was
added to object type Location`). The classes are as the tool reports them, including
`itinerary: Itinerary!` as safe (a check mark), which Chapter 5 uses to show that only the
two-direction conformance check sees the tightening as drift.

Pinned versions: Quarkus platform 3.40.1 (SmallRye GraphQL 2.18.5, graphql-java 25.0), Strawberry
0.335.0 (graphql-core 3.3.0), FastAPI 0.143.2, uvicorn 0.54.0, pydantic-settings 2.16.0, on
`ubi10/openjdk-25:1.24-16` (JDK 25) and `ubi10/python-314-minimal:10.2-1791928506` (Python 3.14).
`graphql-inspector` is `@graphql-inspector/cli` 7.0.1 from `contracts/package.json`. The Python
dependencies are locked in `python/uv.lock`.

## Code-first notes

**Deprecation (Quarkus).**

- `@io.smallrye.graphql.api.Deprecated(reason = "Use `finalArrivalTime`.")` on the record component
  is the one place the reason is written. SmallRye's schema builder records it as a `deprecated`
  directive on the field, and `ContractSchemaDetails` applies it with graphql-java's own
  `field.deprecate(reason)` for each field whose directive carries a reason. Introspection then
  reports `isDeprecated: true` with exactly ``Use `finalArrivalTime`.``.
- `@java.lang.Deprecated` carries no reason, so the example uses the SmallRye annotation.
- `quarkus.smallrye-graphql.schema-include-directives=true` prints the applied `@deprecated` in
  `/graphql/schema.graphql`. `verify.sh` reads introspection, as `assert_sdl_conforms` does.
- SmallRye registers its own `@deprecated` definition (`reason: String`); conformance does not compare directive definitions.
- `ContractSchemaDetails` already trims the generated ` (ISO-8601)` suffix from the description of every
  `DateTime` field, so the new `finalArrivalTime` needs no extra handling.
- `ContractSchemaDetails.withCurrentTypes` keeps interface type resolution in step with the
  transformed schema, so a fragment on a `Node` implementer matches.

**Python.**

- `strawberry.field(description=..., deprecation_reason="Use `finalArrivalTime`.")` is enough.
  Strawberry 0.335.0 prints `@deprecated(reason: ...)` in the exported SDL and introspection reports
  the reason.
- `Itinerary` declares `final_arrival_time` before `final_arrival_date`; `data.py` sets both from
  the same instant and `derivation.py` reads `final_arrival_time`.

**Both stacks.** `fields` returns the names in each stack's own order (Quarkus: `finalArrivalDate`,
`legs`, `finalArrivalTime`; Python: `legs`, `finalArrivalTime`, `finalArrivalDate`), so `verify.sh`
compares them sorted.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/11-evolution-architecture.py`) show the compose topology: a client
sending queries to each stack, both stacks diffed against the canonical SDL, the temporary gate
fixtures and `breaking.sh`, and the opt-in `compose.observability.yaml` override.
