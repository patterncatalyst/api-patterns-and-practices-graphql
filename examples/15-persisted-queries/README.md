# Ch15 - Persisted queries and APQ

Apollo's Automatic Persisted Queries (APQ) and trusted documents on both stacks. A client sends a
SHA-256 hash in `extensions.persistedQuery` instead of the query text; the server resolves the hash,
or asks for the text, or (in trusted mode) refuses text it was not given in advance. Quarkus does
this in a Vert.x route in front of SmallRye GraphQL; Python does it in a Strawberry
`SchemaExtension`. `verify.sh` runs the handshake, persisted queries over GET, a mutation by hash over GET,
and the trusted instances on both stacks.

This example does not repeat Chapter 14's limits; production would.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything in it
except `Subscription`, which Chapter 21 builds: the schema, seed, cursors, error contract and
batching are Chapter 13's, and `assert_sdl_conforms` proves the schema is unchanged. What is new is
in front of the engine.

| Instance | Quarkus | Python | Mode | Introspection |
|---|---|---|---|---|
| APQ | 8250 | 8251 | clients register documents at run time | allowed; **the contract checks run here** |
| trusted | 8252 | 8253 | only `persisted-documents.json` runs | refused, like any text outside the manifest |

The two instances of a stack run one image (one build, two containers), and each has its own
in-memory handling store.

### The protocol

| Request | Result |
|---|---|
| hash, no text, hash unknown | `PERSISTED_QUERY_NOT_FOUND`, message `PersistedQueryNotFound` |
| hash and text, hash matches | the text is stored (APQ mode) and executed |
| hash and text, hash does not match | `BAD_USER_INPUT`, message `provided sha does not match query` |
| hash, no text, hash known | the stored or manifest text is executed |
| trusted mode, text not in the manifest (with or without a hash) | `PERSISTED_QUERY_REQUIRED`, message `only persisted documents are accepted` |

Every refusal is a request error: no `data` (Python sends `"data": null`), HTTP 200, and no source call.
The hash is the lowercase hex SHA-256 of the exact query text, and the server recomputes it.

### The manifest

`persisted-documents.json` is an Apollo persisted-query manifest
(`{"format":"apollo-persisted-query-manifest","version":1,"operations":[{id,name,type,body}]}`) with three
operations: `TrackCargo`, `PortName` and `RegisterHandling`. `verify.sh` checks each `id` against
`sha256(body)`. Only the trusted services mount it (`:ro,z`).

## Run it

```bash
bash examples/15-persisted-queries/verify.sh
```

`verify.sh` brings all four services up with `docker compose`, runs the cases below in a fixed order,
diffs each APQ instance's live schema against `contracts/schema/` and tears the stack down. It prints
`PASS` only if every check holds on **both** stacks. It needs Docker Engine with the `docker compose`
plugin and Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/15-persisted-queries/compose.yaml up -d --build
H=$(printf '%s' '{ cargo(trackingId: "ABC123") { trackingId } }' | sha256sum | cut -d' ' -f1)
curl -s localhost:8250/graphql -H 'Content-Type: application/json' \
  -d "{\"extensions\":{\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}}"        # PersistedQueryNotFound
curl -s localhost:8250/graphql -H 'Content-Type: application/json' \
  -d "{\"query\":\"{ cargo(trackingId: \\\"ABC123\\\") { trackingId } }\",\"extensions\":{\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}}"
curl -s -G localhost:8250/graphql -H 'Accept: application/json' \
  --data-urlencode "extensions={\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}"   # by GET
docker compose -f examples/15-persisted-queries/compose.yaml down -v
```

Use ports `8251` (APQ) and `8253` (trusted) for Python. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8250`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8251`. Trusted mode takes
`TRACKING_DOCUMENTS_MODE=trusted TRACKING_DOCUMENTS_MANIFEST=<path>`.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the
log and answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`. The
endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it). A persisted query makes
exactly the source calls of its full text, and every refusal makes none.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus APQ | 8080 | 8250 | `/graphql` (health at `/q/health`) |
| Python APQ | 8080 | 8251 | `/graphql` (health at `/health`) |
| Quarkus trusted | 8080 | 8252 | `/graphql` |
| Python trusted | 8080 | 8253 | `/graphql` |

Compose project `gql-ch15-persisted`, containers `ch15-persisted-*`. Telemetry is off by default.
Add the observability file (`docker compose -f compose.yaml -f compose.observability.yaml up
--build`) to send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and
3200, so run one example's observability stack at a time.

## On the wire

Each value below is asserted by `verify.sh`. `H_TRACK`, `H_PORT` and `H_REG` are the SHA-256 of the
manifest bodies of `TrackCargo`, `PortName` and `RegisterHandling`.

| Case | Request | Quarkus | Python |
|---|---|---|---|
| manifest | each `operations[].id` | equals `sha256(body)` | the same |
| handshake 1 | POST `{"variables":{"id":"ABC123"},"extensions":{...H_TRACK}}` | 200, no `data`, one error `PersistedQueryNotFound`, `PERSISTED_QUERY_NOT_FOUND`, no `path`; 0 source calls | the same, plus `"data": null` |
| handshake 2 | the same with `query` | `cargo.trackingId` `ABC123`, `ONBOARD_CARRIER` | the same |
| handshake 3 | hash only again | the same data; the same source-call keys as handshake 2 | the same |
| list query by hash | Chapter 13's `Q_FAN` by hash | same data and same calls as the full text (8 on Quarkus, 6 on Python) | the same |
| size | `CargoDetail` (580 characters, three fragments), variables `{"id":"DEF456"}` | request body exactly 624 bytes with text, exactly 163 bytes by hash (756 bytes on the registering request) | the same |
| mismatch | `TrackCargo` text with `H_PORT` | `BAD_USER_INPUT`, `provided sha does not match query`; 0 calls | the same |
| GET by hash | `?variables={"id":"ABC123"}&extensions=...` with `Accept: application/json` | 200, the same data | the same |
| GET by hash, with `operationName` | the `TrackCargo` hash with `&operationName=TrackCargo` | 200, `ABC123` | the same |
| GET, unknown hash | `H_PORT` | `PersistedQueryNotFound`; 0 calls | the same |
| GET and POST, literal `%` and `+` | `"A+B%41 C"` in the document text, in a variable and in a document sent by hash over GET and over POST; `"100%"` in a document sent by hash over POST and GET | the source receives `A+B%41 C` (and `D+E%42 F` for the variable); `100%` gives 200 | the same |
| GET mutation by hash | `RegisterHandling` registered by POST with invalid input (`userErrors` `VOYAGE_NOT_ALLOWED`), then sent by GET | **405**, `Allow: POST`, text `mutations are not allowed when using GET`; 0 `appendEvent` | **400**, text `mutations are not allowed when using GET`; 0 `appendEvent` |
| GET mutation, text | `query=<RegisterHandling text>` with input that would be accepted | the same 405; nothing written | the same 400; nothing written |
| GET, malformed variants | a variant of the `mutation` document; a document that does not parse | **405**, nothing written; **400**, no data, 0 calls | **400**, nothing written; 200 with a syntax error, 0 calls |
| mutation by hash | POST `H_REG`, UNLOAD DEHAM V100S `2026-10-09T15:00:00Z` for `ABC123`, key `k-apq-1` | `evt_10`, `IN_PORT`; the repeat by hash returns `evt_10` with 0 `appendEvent` | the same |
| trusted, manifest hash | `H_PORT` never registered, `{"code":"NLRTM"}`, by POST and by GET | `location.name` `Rotterdam` | the same |
| trusted, text | `{ __typename }`; the same with its hash; `{ __schema { queryType { name } } }` | `PERSISTED_QUERY_REQUIRED`, `only persisted documents are accepted`, no data, 0 calls; status 200 | the same |
| trusted, `application/graphql` | the introspection text as an `application/graphql` body | `PERSISTED_QUERY_REQUIRED`, 0 calls | 400 `Unsupported content type`, 0 calls |
| trusted, `?query=` | `?query={ __typename }` on a POST with a manifest body, and on a GET | `PERSISTED_QUERY_REQUIRED`, 0 calls | the same |
| trusted, unknown hash | `sha256('never registered')`; the hash of the refused `{ __typename }`; a hash registered on the APQ instance | `PERSISTED_QUERY_NOT_FOUND` | the same |
| trusted, manifest text | `PortName` text with no hash | `Rotterdam` | the same |
| trusted, `application/graphql` manifest text | `PortName` as an `application/graphql` body | `Rotterdam`; a `text/plain` body gets 400 | 400 `Unsupported content type` (not asserted) |
| WebSocket upgrade | `Upgrade: websocket`; `Upgrade: foo` then `Upgrade: websocket`; an empty `Upgrade:` then `Upgrade: websocket`, on `/graphql`, `graphql-transport-ws`, on 8250 and 8252; a mutation is sent if the upgrade succeeds | 400; 0 `appendEvent`; 0 source calls | not asserted |
| GET, `operationName` that matches nothing | the single-operation `RegisterHandling` mutation by text and by hash, with `operationName=Nope` and with `operationName=`, on 8250, 8252, 8251 and 8253 | `Nope`: **400**, `BAD_USER_INPUT`, `operationName does not match an operation in the document`; empty: **405**; no `data`; 0 `appendEvent` | **400**, no `data`; 0 `appendEvent` |
| GET with a form body | `GET /graphql` with `Content-Type: application/x-www-form-urlencoded` | answered | answered |
| trusted, empty `application/graphql` | an empty `application/graphql` POST on 8252 | `PERSISTED_QUERY_REQUIRED`, 0 calls | not run |
| trusted, mutation | `H_REG` by POST | `evt_10` | the same |
| bounded store | 1100 distinct documents registered, then resolved by hash | exactly 1000 still resolve | exactly 1000 still resolve; the unresolved ones are indices 0 to 99 |
| schema | live APQ schema | conforms to `contracts/schema/`; `finalArrivalDate` deprecated; only `Subscription` is unserved | the same |

## Code-first notes

The checks below ran on the pinned versions (SmallRye GraphQL 2.18.5 on graphql-java 25.0, Quarkus 3.40.1,
Vert.x 4.5; Strawberry 0.335.0 on graphql-core 3.3.0).

**How the protocol is implemented.** The example implements Apollo's protocol with a small route on Quarkus and a small extension on Python.

- On Quarkus, `PersistedDocumentRoute` is a Vert.x route in front of SmallRye's. It reads
  `extensions.persistedQuery`, resolves the hash to a document and reroutes to `/graphql` with the text
  as a `query` parameter.
- On Python, the `PersistedQueries` extension sits in `SchemaExtension.on_operation`, which runs before
  the query is looked for, and sets `execution_context.query`. Strawberry's `ParserCache` and
  `ValidationCache` reuse work for text already seen.

**The route runs before SmallRye's.** `router.route("/graphql").order(-10)` matches the
exact path only: `GET /graphql/schema.graphql` still answers `200 text/plain` with the SDL.

**`rc.reroute` with a query string.** On Vert.x 4.5 the rerouted request carries
the parameters, and SmallRye receives the merged request. For POST, the body's `variables` and
`operationName` survive and the `query` parameter is merged over the body; for GET, the URL's own
parameters are re-sent with `query` added. No `RoutingContextInternal` access is needed.

**A mutation over GET is refused.** GraphQL over HTTP, "GET", requires a server to refuse a mutation
sent over GET with a 4xx and recommends 405 with `Allow: POST`. A link or image tag can trigger a GET, so
a write behind it would need no cooperation from the user. `PersistedDocumentRoute.proceed` enforces the
rule for every GET before handing the request on: it parses the document with graphql-java's `Parser`
and refuses a GET whose selected operation is not a query, with `405`, `Allow: POST`, plain text
`mutations are not allowed when using GET`. Strawberry refuses with `400` and the same text.

**A `BodyHandler` on POST.** The route adds one in front of SmallRye's, on POST only, created with
`BodyHandler.create(false)` so that file uploads stay off. The rerouted POST still reaches SmallRye with
its body, and a GET that carries a body is answered like any other GET.

**Extension order and masking.** `[MaskErrors, PersistedQueries, ParserCache,
ValidationCache]` works. An `ExposedError` raised in `on_operation` before `yield` ends the operation
with a request error; its message and `extensions.code` reach the client, with `"data": null`. A
hash-only **GET** gets Strawberry's IDE when `Accept` includes `text/html` or `*/*`: Strawberry treats a
GET with no `query` parameter and such an `Accept` as a browser asking for GraphiQL, and answers
`200 text/html` (with `graphql_ide=None`, `404`). Clients send
`Accept: application/json`, as `verify.sh` does. Apollo Client 4 sends
`application/graphql-response+json,application/json;q=0.9`, which passes. Apollo Client 3 sends `*/*`,
which gets Strawberry's IDE for a hash-only GET. Quarkus answers `*/*` with JSON and `Accept: text/html`
with `406`. Chapter 16 returns to it for cached GET URLs.

**GET and `operationName`.** An empty `operationName` is treated as absent. A non-empty one must name an
operation in the document, or the route answers `400` with `BAD_USER_INPUT` and `operationName does not
match an operation in the document`, by text and by hash, in both modes. For a single-operation
document the operation is already determined, so the route hands the request on without
`operationName`; for a document with several, it hands on only the checked name. `verify.sh` sends a
GET by hash with a matching name and asserts it works, and sends a single-operation mutation with
`operationName=Nope` and with an empty one, by text and by hash, asserting no data and 0 `appendEvent`.

**The route enforces GraphQL-over-HTTP's rules for every request it hands on.** On GET the document is
parsed and a document that does not parse gets `400`. The checked text is what the route hands on, so
the text that was checked and hashed is the text that runs. In trusted mode a POST body must be a JSON object or `application/graphql` text,
and the manifest text is what runs. Trusted mode covers every transport the endpoint serves; this
example serves HTTP only, so the route refuses any request on `/graphql` that carries an `Upgrade`
header in both modes (Chapter 21 covers WebSockets).

**Request sizes.** `curl -w '%{size_upload}'`, `CargoDetail` with variables
`{"id":"DEF456"}`: plain POST 624 bytes, hash plus text 756, hash alone 163, and the GET has a 204-byte
request target and no body. Responses: 2,412 bytes of data on both stacks; `PersistedQueryNotFound` is
99 bytes on Quarkus and 111 on Python. `Q_FAN` (178 characters) is too small to show a saving: 191
bytes plain, 132 by hash.

**The re-entry marker.** A request is passed through on re-entry by a flag on the `RoutingContext`,
not by a `query` URL parameter. A `query` URL parameter on a first-hand request is client input,
so it is treated as the text and checked like any other.

**Bounded stores.** Both stores hold 1000 documents. Caffeine
(`quarkus.cache.caffeine."persisted-documents".maximum-size=1000`) held exactly 1000 of 1100 after
the registrations; `cachetools.LRUCache(maxsize=1000)` held exactly 1000 and evicted indices 0 to 99,
the 100 oldest. Caffeine is Window TinyLFU, not LRU, so which documents it evicts is its own policy. An evicted
hash answers `PersistedQueryNotFound`, and the client repeats the handshake.

**Quarkus notes.**

- `tracking.documents.manifest` is an `Optional<String>`: an empty `${ENV:}` default counts as a missing
  value in MicroProfile Config, so the property is not defined in `application.properties`.
- `@Observes Router` is Quarkus' hook for the Vert.x router; it needs no `quarkus-vertx-http` import
  beyond what SmallRye brings.
- The `trusted` instance refuses `wait_for_graphql`'s `{ __typename }` probe, so `verify.sh` waits on
  its health endpoint.

**Strawberry notes.**

- Every extension is passed as a factory (`functools.partial`), so each request has its own instance.
- `PersistedDocuments` is built once at import from `Settings`; `LRUCache` is not thread-safe, and
  every access runs on the event loop between awaits.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/15-persisted-queries-architecture.py`) show the compose topology: a client
reaching the four services, the two trusted services reading the manifest, and the APQ instances diffed
against the canonical SDL.
