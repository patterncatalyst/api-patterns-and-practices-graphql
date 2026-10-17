# Ch13 - The N+1 problem and DataLoaders

The 29 source calls that a four-cargo page cost in Chapter 12 become bulk calls: 8 on Quarkus and 6 on
Python. Quarkus batches with SmallRye `@Source List<...>` resolvers; Python batches with Strawberry
`DataLoader`s built once per request. Every source gains a bulk operation whose log key is the sorted
distinct keys joined with `+`. `verify.sh` counts the calls on both stacks, shows where the stacks
differ, and asserts what one failing key does to its batch on each.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything in it
except `Subscription`, which Chapter 21 builds. The schema is the one Chapter 12 serves: batch methods
and loaders change how fields are fetched, not which fields exist, and `assert_sdl_conforms` proves it.
The seed, the cursors, the error contract and the `finalArrivalTime` deprecation are Chapter 12's;
Chapter 11 explains the deprecation.

### Bulk source operations

| Source | Single-key operation (root fields, mutation) | Bulk operation | Log key |
|---|---|---|---|
| `booking` | `getCargo` | `getCargos` | sorted distinct tracking ids joined with `+` |
| `routing` | `getItinerary` | `getItineraries` | the same |
| `handling` | `listEvents` | `listEventsFor` | the same |
| `voyage` | `getVoyage` | `getVoyages` | sorted distinct voyage numbers joined with `+` |
| `location` | `getLocation` | `getLocations` | sorted distinct UN/LOCODEs joined with `+` |

A bulk operation answers one outcome per requested key, in the order asked: the value, `null` for an
unknown key, or the failure the owner reported for that key. `booking.getCargos` reports
`SourceUnavailable("booking service unavailable")` for `GHI345` and a value for every other key. The
single-key operations remain for `Query.cargo`, `Query.location`, `Query.voyage`, `Query.node` and the
mutation, which have no parents to collect.

## Run it

```bash
bash examples/13-dataloaders/verify.sh
```

`verify.sh` brings both services up with `docker compose`, runs the cases below in a fixed order,
diffs each live schema against `contracts/schema/` and tears the stack down. It prints `PASS` only if
every check holds on **both** stacks. It needs Docker Engine with the `docker compose` plugin and
Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/13-dataloaders/compose.yaml up -d --build
curl -s localhost:8230/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ nodes(ids: [\"cargo_ABC123\", \"loc_DEHAM\"]) { __typename id } }"}'
curl -s localhost:8230/debug/source-calls
docker compose -f examples/13-dataloaders/compose.yaml down -v
```

Use port `8231` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8230`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8231`. Set
`TRACKING_SOURCE_LATENCY_MS=250 TRACKING_DEBUG_ENDPOINTS=true` for the behaviour compose gives;
both default to off.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the
log and answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`
(monotonic milliseconds). A bulk call is one entry whose key joins its keys with `+`. The endpoints
answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it) and sit beside `/graphql`, so the
GraphQL schema is the same with them on or off.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8230 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8231 | `/graphql` (health at `/health`) |

Compose project `gql-ch13-dataloaders`, containers `ch13-dataloaders-*`. Telemetry is off by
default. Add the observability file (`docker compose -f compose.yaml -f compose.observability.yaml
up --build`) to send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100
and 3200, so run one example's observability stack at a time.

## On the wire

Each value below is asserted by `verify.sh`. Counts are for the 250 ms latency compose sets.

| Case | Request | Quarkus | Python |
|---|---|---|---|
| cursor | `cargos(first: 2)` | first cursor is base64url of `cargo\|v1\|2026-09-29T09:00:00Z\|VWX901` | the same |
| Q_FAN | `cargos(first: 4)` with itinerary legs (voyage, both locations) and delivery | data as Chapter 12; **8** calls; routing and location each run twice | data as Chapter 12; **6** calls |
| Q_FAN keys | | `getCargos`, `listEventsFor` `DEF456+STU678+VWX901+XYZ789`; `getVoyages` `V100S+V200E+V300A`; `getItineraries` that key twice; `getLocations` `DEHAM+SGSIN+USNYC` and `CNSHA+DEHAM+NLRTM` | the same four keys; `getItineraries` once; `getLocations` once, `CNSHA+DEHAM+NLRTM+SGSIN+USNYC` |
| no single-key calls | | `getCargo`, `getItinerary`, `listEvents`, `getVoyage`, `getLocation` all 0 | the same |
| tick | the log of Q_FAN | `listCargos` ends before `getCargos` starts, which ends before `listEventsFor`, which ends before `getVoyages` (graphql-java dispatches a level after the whole level above completed); `getVoyages` overlaps both location calls, which overlap each other; one request id | `listCargos` before `getCargos` before `listEventsFor`; `getItineraries` before `getVoyages`; `getItineraries` overlaps `listEventsFor`; `getVoyages` overlaps the location call; one request id |
| alias pair | `cargo(ABC123) { itinerary { legs { a: voyage b: voyage } } }` | one `getVoyages` call, `V100S+V200E` (Chapter 7: four calls) | the same |
| itinerary and delivery | `cargo(ABC123) { itinerary { finalArrivalTime } delivery { transportStatus } }` | two `getItineraries` calls, key `ABC123` each | one |
| history | `cargo(DEF456) { handlingHistory(first: 7) { edges { node { id location voyage } } } }` | `pageEvents` once, `getLocations` `DEHAM+NLRTM+USNYC`, `getVoyages` `V100S+V200E` (Chapter 12: 7 + 4 calls), plus the root `getCargo` | the same |
| `nodes` | `cargo_ABC123`, `cargo_XYZ789`, `loc_DEHAM`, `loc_NLRTM`, `voy_V100S` | three calls: `getCargos` `ABC123+XYZ789`, `getLocations` `DEHAM+NLRTM`, `getVoyages` `V100S` (Chapter 12: 5); order and types as asked | the same |
| `nodes` with a duplicate | `cargo_ABC123`, `loc_NLRTM`, `nope`, `voy_V200E`, `cargo_ABC123` | `[Cargo, Location, null, Voyage, Cargo]` by position; three calls: `getCargos` `ABC123`, `getLocations` `NLRTM`, `getVoyages` `V200E` (Chapter 10: four) | the same |
| history, each event's `cargo` | `cargo(DEF456) { handlingHistory(first: 7) { edges { node { cargo { trackingId } } } } }` | `getCargo` `DEF456`, `pageEvents` `DEF456`, one `getCargos` `DEF456` | the same |
| Chapter 1's locations | `cargo(DEF456)`: legs' load and unload locations, history locations | three `getLocations` calls, one per location field | one `getLocations` call |
| request scope | Q_FAN twice | two request ids, 16 calls, 8 each | 12 calls, 6 each |
| not found | `voyage(voyageNumber: "V999X")`; `nodes(ids: ["voy_V999X", "voy_V100S"])` | `null`, one `getVoyage`; `[null, Voyage V100S]`, one `getVoyages` `V100S+V999X` | the same |
| blast radius | `cargos(last: 2) { edges { node { trackingId } } }` | `listCargos` and one `getCargos` `ABC123+GHI345`; 2 errors, paths `["cargos","edges",0,"node"]` and `[...,1,"node"]`, both `SERVICE_UNAVAILABLE`, both nodes null | the same two calls; 1 error, path `["cargos","edges",1,"node"]`, node 0 is `ABC123`, node 1 null |
| write | register `UNLOAD` `DEHAM` `V100S` `2026-10-09T15:00:00Z` for `ABC123` | `evt_10`; payload and a fresh request both say `IN_PORT` | the same |
| schema | live schema | conforms to `contracts/schema/`; deprecation of `finalArrivalDate` present | the same |

## Code-first notes

The example runs on the pinned versions (SmallRye GraphQL 2.18.5 on graphql-java 25.0 and java-dataloader,
Quarkus 3.40.1; Strawberry 0.335.0 on graphql-core 3.3.0).

**`Uni<List<T>>` on a batch method.** `Uni<List<Cargo>> node(@Source
List<CargoEdge> edges, Context context)` is a batch resolver and the field keeps its type.

**`Context` on a batch method.** `getExecutionId()` read at method entry
is the same id as in the other resolvers of the request: `assert_single_request` holds for Q_FAN, whose
eight calls come from six batch methods and one single-key root field.

**`@NonNull` on a batch method.** `@NonNull Uni<List<Location>> loadLocation(@Source
List<Leg> legs, ...)` gives `loadLocation: Location!`, not `[Location!]!`; the list is the batch
wrapper, not the field's type. `assert_sdl_conforms` passes with the batch methods in place, so no
field, argument or nullability changed.

**The alias pair.** `a: voyage` and `b: voyage` on the same leg share one loader (a loader
is per field per request, and the alias is not part of the field). The legs are the cache keys: the
default `DataLoader` options leave the cache on, with the source object as the key, and `Leg` is a record
with value equality. The batch holds 2 legs for the alias pair
and 3 legs for Q_FAN, whose four legs include two equal ones (`VWX901` and `STU678` share
a route). `verify.sh` asserts the visible effect: one `getVoyages` call,
`V100S+V200E`.

**Dispatch with `Uni` parents.** One batch per field per level. The Q_FAN log
shows `getCargos`, then `getItineraries` (twice) and `listEventsFor` together, then `getVoyages` and
both `getLocations` together: no level splits into several batches. The two `getItineraries` calls and the two `getLocations` calls are two
loaders each, which is the cost of one loader per field.

**Blast radius.** A batch method returns one list, so an exception ends the whole batch. With
`GHI345` in the batch of two edge nodes, SmallRye reports one error per parent, at its own path, and
both nodes are null, including `ABC123`'s. The example asserts this as the SmallRye behaviour. Python's loader receives the exception *instance* at `GHI345`'s position in
the list and fails only that key.

**Strawberry notes.**

- `Loaders` is a frozen dataclass built by `Loaders.for_request(...)` in `app/deps.get_context`, so
  each request has its own loaders and caches. `app/context.py` imports `Loaders` for type checking only.
- A `DataLoader` created outside a running event loop is fine: it takes the loop lazily, on the first
  `load()`, and `get_context` builds the loaders before any resolver runs.
- Dispatch is `loop.call_soon`: every `load()` made before the loop's next turn joins one batch. A
  `gather` of resolvers starts all of them before that turn, so `nodes` batches its ids.

**Quarkus notes.**

- `Outcome<T>` is the bulk operations' per-key answer; `Outcome.values(...)` throws the first failure,
  which fails the batch's `Uni`.
- `Query.nodes` is a root field and has no parents for the engine to collect, so it groups its ids by
  prefix and calls one bulk operation per type. Events have no bulk read and stay one call each.
- `HandlingEvent.voyage` asks the voyage service only for the events that have a voyage and puts the
  results back in order.
- The deprecation handling in `ContractSchemaDetails` is carried over from Chapter 12; Chapter 11
  explains it.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/13-dataloaders-architecture.py`) show the compose topology: a client
sending queries to each stack, both stacks diffed against the canonical SDL, and the opt-in `compose.observability.yaml` override.
