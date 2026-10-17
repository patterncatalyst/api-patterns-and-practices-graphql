# Ch12 - Connections and pagination

Two growing lists of the tracking view become Relay connections: `Query.cargos` and
`Cargo.handlingHistory`, both with opaque keyset cursors. The example starts from the Chapter 9
example (so the exposed and masked error machinery is still there), carries `Query.nodes` from
Chapter 10 and the `finalArrivalTime` deprecation from Chapter 11, and drops the Chapter 9 fault
seeds. `verify.sh` pages forward and backward on both stacks, compares the first cursor byte for
byte with a literal it computes itself, registers a late event to show a page stay stable, feeds
bad arguments and foreign cursors, reads the failing edge, and counts the source calls a page of
hydrated cargos costs.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything in it
except `Subscription`, which Chapter 21 builds. New here: `Query.cargos` and `Cargo.handlingHistory`
with `CargoConnection`, `CargoEdge`, `HandlingEventConnection`, `HandlingEventEdge` and `PageInfo`.

### The seed

| # (newest first) | trackingId | route | bookedAt | routingStatus (stored, and derived) |
|---|---|---|---|---|
| 1 | `VWX901` Furniture | SGSIN to CNSHA | 2026-09-29T09:00:00Z | `ROUTED` |
| 2 | `XYZ789` Frozen seafood | SGSIN to NLRTM | 2026-09-28T09:00:00Z | `NOT_ROUTED` |
| 3 | `STU678` Rubber goods | SGSIN to NLRTM | 2026-09-27T09:00:00Z | `MISROUTED` (its one leg ends in CNSHA) |
| 4 | `DEF456` Auto parts | USNYC to NLRTM | 2026-09-26T09:00:00Z | `ROUTED` |
| 5 | `ABC123` Palletized electronics | USNYC to NLRTM | 2026-09-25T09:00:00Z | `ROUTED` |
| 6 | `GHI345` Medical supplies | USNYC to DEHAM | 2026-09-24T09:00:00Z | `NOT_ROUTED` |

`bookedAt` is private to the booking index, not a schema field. `DEF456` has seven events,
`evt_3` to `evt_9`, ending in a `CLAIM`; `ABC123` has `evt_1` and `evt_2`. The one fault:
`booking.getCargo("GHI345")` fails with the exposed `SourceUnavailable("booking service unavailable")`,
code `SERVICE_UNAVAILABLE`, while the booking **index** still lists it.

### Ordering, cursors and page rules

| | `cargos` | `handlingHistory` |
|---|---|---|
| order | `bookedAt` descending, then `trackingId` descending | `completionTime` descending, then the number in `evt_<n>` descending |
| cursor plaintext | `cargo\|v1\|<bookedAt>\|<trackingId>` | `evt\|v1\|<completionTime>\|<n>` |
| encoding | URL-safe base64, no padding, of the UTF-8 text | the same |
| source operation | `booking.listCargos`, log key the `routingStatus` or `*` | `handling.pageEvents`, log key the tracking id |

Page size is 10 when neither `first` nor `last` is given. Each must be between 0 and 50, and the two
cannot be combined. A decoder rejects a wrong prefix, an unknown version, a wrong field count, a time
that is not the exact text the encoder writes, and any base64 that is not the canonical unpadded form.

### The error contract

| `extensions.code` | Raised for | Message | Shown |
|---|---|---|---|
| `SERVICE_UNAVAILABLE` | the `GHI345` outage | `booking service unavailable` | yes |
| `BAD_USER_INPUT` | `first must be between 0 and 50`, `last must be between 0 and 50`, `first and last cannot be combined`, `after is not a valid cursor for this connection`, `before is not a valid cursor for this connection` | as listed | yes |
| none | anything unexpected | `Internal server error.` | masked |

Masking stays an allowlist. Quarkus: `BadUserInputException` is annotated `@ErrorCode("BAD_USER_INPUT")`
and appended to `quarkus.smallrye-graphql.show-runtime-exception-message` beside
`SourceUnavailableException`. Python: `BadUserInput(ExposedError)` with code `BAD_USER_INPUT`.
On Quarkus, `quarkus.class-loading.removed-resources` drops the service file that registers both
built-in SmallRye error providers (`ErrorCodeExtensionProvider` and
`ExceptionNameErrorExtensionProvider`), so `DeclaredErrorCodeProvider` is the only source of
`extensions.code`; the server log records the exception, not the GraphQL path or a request id.

## Run it

```bash
bash examples/12-pagination/verify.sh
```

`verify.sh` brings both services up with `docker compose`, runs the cases below in a fixed order
(handling state carries forward: `evt_10` and three more events are registered for `DEF456`), diffs
each live schema against `contracts/schema/` and tears the stack down. It prints `PASS` only if every
check holds on **both** stacks. It needs Docker Engine with the `docker compose` plugin and Node/npm
(for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/12-pagination/compose.yaml up -d --build
curl -s localhost:8220/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargos(first: 2) { edges { cursor node { trackingId } } pageInfo { hasNextPage endCursor } totalCount } }"}'
docker compose -f examples/12-pagination/compose.yaml down -v
```

Use port `8221` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8220`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8221`. Set
`TRACKING_SOURCE_LATENCY_MS=250 TRACKING_DEBUG_ENDPOINTS=true` for the behaviour compose gives;
both default to off.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the
log and answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`
(monotonic milliseconds). The endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets
it) and sit beside `/graphql`, so the GraphQL schema is the same with them on or off. This chapter
uses the log to show that a filter reaches the index once and to count the calls a page costs.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8220 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8221 | `/graphql` (health at `/health`) |

Compose project `gql-ch12-pagination`, containers `ch12-pagination-*`. Telemetry is off by default.
Add the observability file (`docker compose -f compose.yaml -f compose.observability.yaml up
--build`) to send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and
3200, so run one example's observability stack at a time.

## On the wire

Each value below is asserted by `verify.sh` on both stacks.

| Case | Request | Response |
|---|---|---|
| history | `ABC123` `handlingHistory(first: 2)` | `evt_2`, `evt_1`; `hasNextPage` false |
| forward | `cargos(first: 2)` and each `after: endCursor` | `VWX901, XYZ789` (true, false); `STU678, DEF456` (true, true); `ABC123`, null node (false, true); `totalCount` 6; `startCursor` is `edges[0].cursor`, `endCursor` is the last edge's |
| cursor | first cargo cursor | base64url of `cargo\|v1\|2026-09-29T09:00:00Z\|VWX901`, equal to the literal `verify.sh` computes, on both stacks; no `VWX901`, `2026` or `=` inside any cursor |
| backward | `last: 2, before:` cursor of `ABC123`; `last: 2` | `STU678, DEF456` (true, true); `ABC123`, null node (false, true) |
| filters | `routingStatus` `MISROUTED`, `NOT_ROUTED`, `ROUTED` | `[STU678]` total 1; `[XYZ789, null]` total 2; `[VWX901, DEF456, ABC123]` total 3; stored equals derived; one `booking.listCargos` call keyed by the filter |
| empty page | `first: 0` | no edges, null cursors, next true, prev false, total 6 |
| fuse | page 3 | 1 error, path `["cargos","edges",1,"node"]`, `booking service unavailable`, `SERVICE_UNAVAILABLE`; node null; cursor kept; `ABC123` resolved |
| bad arguments | `first` -1 and 51, `last` 51, `first` with `last`, bad cursors, an event cursor on `cargos`, a cargo cursor on `handlingHistory` | 1 error each, `BAD_USER_INPUT`, the exact message; `cargos` failures null `data`, `handlingHistory` failures null `cargo`; `first: 50` is allowed |
| insert | `DEF456` history by 3, register `evt_10`, continue | `evt_9, evt_8, evt_7` (total 7); `evt_6, evt_5, evt_4`; `evt_3`; fresh page `evt_9, evt_8, evt_10` (total 8) |
| ends | `last: 2` of the history | `evt_4, evt_3`; next false, prev true |
| default size | three more events, then no arguments | 10 edges, next true, total 11; delivery `CLAIMED` |
| defaults | `args { defaultValue }` | all null on both fields |
| N+1 | `cargos(first: 4)` with itinerary legs and delivery | 29 calls: `listCargos` 1, `getCargo` 4, `getItinerary` 8, `listEvents` 4, `getVoyage` 4 (`V300A, V300A, V100S, V200E`), `getLocation` 8 |
| `nodes` | five ids | 5 calls; `cargo`, `evt`, `cargo_` give `[null,null,null]`, no call |
| deprecation | `Itinerary.finalArrivalDate`, `finalArrivalTime` | deprecated with ``Use `finalArrivalTime`.``; not deprecated; both `2026-10-11T18:00:00Z` for `DEF456` |
| schema | live schema | conforms to `contracts/schema/`; only `Subscription` is unserved |

## Code-first notes

The example runs on the pinned versions (SmallRye GraphQL 2.18.5 on Quarkus 3.40.1, Strawberry 0.335.0 on
graphql-core 3.3.0).

**`strawberry.Maybe` on resolver arguments.** An argument is typed
`Annotated[strawberry.Maybe[int | None], strawberry.argument(...)]` with a Python default of
`= None`. The SDL prints `first: Int` with no `= null`, an omitted argument arrives as
`None`, a sent one as `Some(value)`, and an explicit `null` as `Some(None)`. `app/pagination.argument`
unwraps it. The plain alternative, `int | None = None`, prints `= null`, a change the SDL diff does not
flag, so `verify.sh` asserts every `defaultValue` is null.

**Plain types instead of `strawberry.relay`.** A `ListConnection` returns offset cursors, base64 of
`arrayconnection:0`, `arrayconnection:1`, with standard base64 padding, so a late insert repeats an
item. Its edge `node` is non-null (`Item!`), so a failing node would null the page; the canonical
`CargoEdge.node` is nullable. It has no `totalCount`, its `PageInfo` description reads "Information to
aid in pagination." instead of the canonical text, and its `Node`/`GlobalID` ids are base64 of
`Type:id` rather than the canonical `cargo_ABC123`. Plain types on both stacks match the contract.

**The deprecation annotation.** `@io.smallrye.graphql.api.Deprecated(reason = ...)` on the
`Itinerary` record component is the single source of the reason, and `ContractSchemaDetails`
applies it with `field.deprecate(reason)`, as in Chapter 11. Python uses
`deprecation_reason="Use `finalArrivalTime`."`. `assert_deprecated` passes on both stacks.

**Quarkus.**

- `Pagination` holds the argument rules, the cursor codec and `slice`. `CargoKey` and `EventKey` are
  `Comparable` records; a slice counts items with a key at or after `after` and after `before`.
- `CargoEdge` keeps `@Ignore String trackingId`; `node` is a `@Source CargoEdge` resolver returning
  `Uni<Cargo>`, nullable, so a failing cargo nulls its edge.
- `HandlingStore` keeps each cargo's events in a `ConcurrentSkipListSet` sorted newest first.
- A resolver may throw before it returns its `Uni`: SmallRye wraps the exception as a fetch
  error with the path `["cargos"]`.

**Python.**

- `app/pagination.py` imports nothing from the app but `app.errors`, so model, sources and seed share it.
- `CargoEdge.tracking_id` is `strawberry.Private`; `node` is an `async` resolver.
- `HandlingStore` keeps each list sorted newest first on insert.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/12-pagination-architecture.py`) show the compose topology: a client
sending queries to each stack, both stacks diffed against the canonical SDL, and the opt-in `compose.observability.yaml` override.
