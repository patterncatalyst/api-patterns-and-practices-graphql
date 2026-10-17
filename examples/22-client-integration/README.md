# Ch22 - Client integration

Three clients call the tracking view of Chapter 13: Apollo Client with a normalized cache and
GraphQL Code Generator types (TypeScript on Node 24), `gql` with local schema validation (Python), and
the SmallRye GraphQL typesafe and dynamic clients (Java). Each runs as a one-off container on the compose
network against both servers. The servers are Chapter 13's, unchanged apart from names and ports, so this
chapter adds client code and no server code.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. Both servers serve everything in it except
`Subscription`, which Chapter 21 builds, exactly as in Chapter 13. The clients reach the SDL through
`build.additional_contexts` (`schema: ../../contracts/schema`), so no copy of `contracts/schema/` lives in
this example. Telemetry is off in the compose file (`OTEL_SDK_DISABLED`); Chapter 19 turns it on.

## The clients

| Client | Directory | What it shows |
|---|---|---|
| `js-client` | `clients/js/` | `@apollo/client` 4.3.4 with an `InMemoryCache`. `TrackCargo` is one request; `TrackCargoBrief`, a subset of it, is answered from the cache; `cache.extract()` holds one `Cargo:cargo_ABC123` entry and `Location:` entries keyed by id; the `RegisterHandling` payload updates the cached cargo and a cache-only `readQuery` shows `IN_PORT`; `ListCargos` with `errorPolicy: "all"` resolves with both `data` and `error`. |
| `codegen-check` | `clients/js/` (build stage) | `codegen.fail.ts` points the same codegen at `fixtures/cargo-weight.graphql`, which selects `Cargo.weight`; codegen exits 1 and writes nothing. |
| `python-client` | `clients/python/` | `gql` 4.4.0 over httpx. A `Client` built with the canonical SDL validates each document before sending it; `gql.dsl` builds a `location` query from the schema; a document selecting `Cargo.weight` is refused locally, and the response with data and errors for `cargos(first: 10)` is read from `TransportQueryError`. |
| `java-client` | `clients/java/` | Quarkus command mode with `quarkus-smallrye-graphql-client`. `TrackingClient` is a `@GraphQLClientApi` interface; the node of each `CargoEdge` is an `ErrorOr`; `registerHandlingEvent` is a `@Mutation`; `DynamicGraphQLClient` runs a document built with `Document`, `Operation` and `Field`. |

Every client sends `X-Client-Name` (`ch22-js`, `ch22-python`, `ch22-java`) and `X-Client-Version`. Chapter 19
reads the header; this chapter's servers leave it unread, so nothing asserts it here.

The JS client's code generation is part of the image build: `npm ci` from the committed
`package-lock.json`, `npm run codegen` against `/schema`, `npm run typecheck`, then the runtime stage
(`ubi10/nodejs-24-minimal`) runs `node src/main.ts`. Node 24 strips the type annotations and runs the
TypeScript files as they are.

## Run it

```bash
bash examples/22-client-integration/verify.sh
```

`verify.sh` brings both servers up with `docker compose`, checks that code generation refuses the
`Cargo.weight` document, runs the three clients against each server in a fixed order, diffs each live
schema against `contracts/schema/` and tears the stack down. It prints `PASS` only if every check holds on
**both** stacks. It needs Docker Engine with the `docker compose` plugin and Node/npm (for the pinned
`graphql-inspector` in `contracts/`).

The order matters because the servers keep state: the JS client registers `evt_10` for `ABC123`, the
Python client then reads `ABC123` as `IN_PORT`, and the Java client registers `evt_11` for `VWX901`.

To explore by hand:

```bash
cd examples/22-client-integration
docker compose up -d --build
docker compose --profile client run --rm --build js-client http://quarkus:8080/graphql
docker compose --profile client run --rm --build python-client http://python:8080/graphql
docker compose --profile client run --rm --build -e TRACKING_URL=http://quarkus:8080/graphql java-client
docker compose down -v
```

Each client prints one JSON line per step. The image build logs share the stream.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the log and
answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`. The endpoints answer
only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it). `verify.sh` counts the distinct request ids
in the log to show how many requests reached the server.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8320 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8321 | `/graphql` (health at `/health`) |

Compose project `gql-ch22-clients`, containers `ch22-clients-*`. The clients publish no port.

## On the wire

Each value below is asserted by `verify.sh`. Counts are for the 250 ms latency compose sets.

| Case | Quarkus | Python |
|---|---|---|
| codegen on `fixtures/cargo-weight.graphql` | exit 1, `Cannot query field "weight" on type "Cargo"`, no files generated | |
| JS `TrackCargo(ABC123)` | `ONBOARD_CARRIER`, `fetches` 1 | the same |
| JS `TrackCargoBrief(ABC123)` | `ONBOARD_CARRIER`, `fetches` still 1 | the same |
| JS `cache.extract()` | `Cargo:cargo_ABC123`; `Location:loc_NLRTM`, `Location:loc_USNYC` | the same |
| JS `RegisterHandling` (`UNLOAD` `DEHAM` `V100S` `2026-10-09T15:00:00Z`) | `evt_10`, no `userErrors`, cache-only read `IN_PORT`, `fetches` 2 | the same |
| JS `ListCargos` with `errorPolicy: "all"` | 6 edges, 6 null nodes, 6 errors (`CombinedGraphQLErrors`), `fetches` 3 | 6 edges, 1 null node, 1 error |
| server log of the JS run | three request ids, one `handling.appendEvent` | the same |
| Python `TrackCargo(ABC123)` | `ABC123`, `Palletized electronics`, `IN_PORT` | the same |
| Python `gql.dsl` `location(unLocode: "NLRTM") { name }` | `Rotterdam` | the same |
| Python document selecting `Cargo.weight` | refused locally: `Cannot query field 'weight' on type 'Cargo'.`; 0 sent | the same |
| Python `cargos(first: 10)` | 6 edges, 6 null nodes, 6 errors `SERVICE_UNAVAILABLE` | 6 edges, 1 null node, 1 error at `["cargos","edges",5,"node"]` |
| Python client requests | 3 sent (the refused document is not one of them), 3 request ids at the server | the same |
| Java typesafe `cargo(ABC123)` | `ABC123`, `Palletized electronics`, `IN_PORT` | the same |
| Java `CargoPage` with `ErrorOr` nodes | 6 edges, 0 present, 6 edges with the error `booking service unavailable` | 6 edges, 5 present, 1 edge with that error |
| Java typesafe `registerHandlingEvent` (`RECEIVE` `SGSIN` for `VWX901`, `2026-10-09T10:00:00Z`) | `evt_11`, `IN_PORT`, no `userErrors`, one `handling.appendEvent` | the same |
| Java dynamic `location(unLocode: "NLRTM") { name }` | `Rotterdam` | the same |
| schema | conforms to `contracts/schema/`; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

The two stacks differ in the three page rows by design. SmallRye resolves the cargo loads of one page as a batch and
reports a failure at every edge of that batch; Strawberry's loader fails only the key that failed
(Chapter 13). A client reads the same partial response either way: the nodes that loaded are in `data`, and
each error names its path.

## Code-first notes

The clients run on the pinned versions: Apollo Client 4.3.4 on RxJS 7.8.2 and graphql 16.14.2, GraphQL
Code Generator CLI 7.4.6 with the client preset 6.2.3, TypeScript 7.0.2 on Node 24.21; `gql` 4.4.0 on
graphql-core 3.3.0 and httpx 0.28.1; SmallRye GraphQL client 2.18.5 on Quarkus 3.40.1.

**Apollo Client.** `HttpLink` takes the `fetch` implementation as an option, so `countingFetch` wraps the
global one and counts every request that leaves the client. The cache is `new InMemoryCache({ typePolicies:
{ Delivery: { merge: true } } })`: `Delivery` has no id, so a policy that merges its fields lets the
mutation payload, which selects only `transportStatus`, update the stored object without dropping
`routingStatus`. `client.query` returns `{ data }`; `client.readQuery` reads the cache only.

**GraphQL Code Generator.** The `client` preset writes `src/gql/graphql.ts` with one typed document per
operation (`TrackCargoDocument`, `TrackCargoBriefDocument`, `RegisterHandlingDocument`, `ListCargosDocument`) and the result and
variable types. `importExtension: ".ts"` makes the generated files import each other with their extension,
which is how Node's type stripping and `tsc` (with `allowImportingTsExtensions`) both read them. The custom
scalars map to `string` through `scalars`. `fragmentMasking: false` keeps fragment data plain.

**`gql`.** `Client(transport=..., schema=sdl)` takes the SDL text, so `session.execute` validates the
document against it first and raises a `GraphQLError` for the document that selects `weight`. A response
that carries errors raises `TransportQueryError`, whose `data` and `errors` attributes hold the two parts of
the response. `HTTPXAsyncTransport` passes `event_hooks` to httpx; the hook counts the requests.

**SmallRye typesafe client.** A class the client treats as a scalar needs a static `of(String)` factory and
a `toString()` that writes the value; `@Name("TrackingId")` on the class gives the variable's declared type.
The input record carries `@Input("RegisterHandlingEventInput")`. The return types define the selection, so
`CargoSummary` selects `trackingId` only. `ErrorOr<CargoSummary>` holds either the value or the errors
reported at the node's path. The configuration key `tracking` supplies the URL
(`${TRACKING_URL}`) and the `X-Client-Name` header.

**SmallRye dynamic client.** `DynamicGraphQLClient` is injected with `@GraphQLClient("tracking")`, reads
the same configuration key, and `executeSync(document)` returns a `Response` whose `getData()` is a JSON
object.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/22-client-integration-architecture.py`) show the compose topology: the three
client containers and the code-generation stage, the two servers, and the canonical schema reaching the
client builds as a build context.
