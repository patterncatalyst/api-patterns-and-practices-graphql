# Ch16 - Caching

Three places to keep an answer on both stacks, in front of the Chapter 15 persisted-query code:
an nginx HTTP cache that stores a persisted `GET` of reference data, a `Cache-Control` decision made
for every response, and field-level source caches inside the server with a TTL and invalidation on
`registerHandlingEvent`. Quarkus uses `quarkus-cache` (Caffeine) through its annotations and its
`Cache` API; Python uses `cachetools.TTLCache`. The client's normalized cache is the fourth place and
is prose only (Chapter 22). `verify.sh` runs every case below on both stacks.

This example does not repeat Chapter 14's limits; production would. The persisted-document route carries
Chapter 15's trusted-mode code, but this example runs APQ mode only.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything in it
except `Subscription`, which Chapter 21 builds: the schema, seed, cursors, error contract, batching
and APQ are Chapter 15's (APQ mode only: the trusted instances and their ports are not run here), and
`assert_sdl_conforms` proves the schema is unchanged. What is new:

| Layer | Where | What it keys on | What removes an entry |
|---|---|---|---|
| edge | nginx `proxy_cache`, `edge/nginx.conf` | method, upstream and URL | the response's `max-age` (300 s) |
| response policy | `CachePolicy` (Quarkus `@AfterExecute`, Python `SchemaExtension`) | decides `Cache-Control` per response | not a cache |
| `voyages`, `locations` | `quarkus-cache` / `TTLCache`, at the sources | voyage number, UN/LOCODE | 300 s |
| `handling-events` | the same, at `listEventsFor` | tracking id | 20 s here (60 s default), and `registerHandlingEvent` |

`persisted-documents.json` is carried over from Chapter 15. Here `verify.sh` reads the text and hash
of three operations from it; nothing mounts it.

### The cache policy

A response is `Cache-Control: public, max-age=300` when the request is a `GET`, the result has no
errors, every root field is `location`, `voyage` or `__typename`, and there is no `Authorization`
header. Every `public` response also carries `Vary: Accept`, so the edge stores one entry per `Accept`
value. Everything else is `no-store`, including the Chapter 15 refusals such as
`PersistedQueryNotFound`.

### Source caches

- **Reference data** (`voyages`, `locations`): the single-key reads (`getVoyage`, `getLocation`) and
  the bulk reads (`getVoyages`, `getLocations`) share one cache each, so a bulk read warms the
  single-key path and the other way round. A bulk read asks the cache for each key, calls the owner
  once for the misses, stores what it gets and keeps the order asked. Only found values are stored.
- **Handling events** (`handling-events`): `listEventsFor` is cached per tracking id with a short TTL.
  `registerHandlingEvent` evicts the cargo's entry after the append and before the payload reads the
  cargo, so the payload is fresh.
- The loaders from Chapter 13 are unchanged and still per request. The caches live under them, at the
  sources.
- **A hit is not a source call.** Only calls to the owners are logged, so a request answered from a
  cache leaves no entry, and a bulk read that is partly cached logs only the missing keys.
- A cache entry that depends on the caller needs the caller in its key. Nothing here does: reference
  data is the same for everyone, and a cargo's events are read only after the booking source has
  returned the cargo.

## Run it

```bash
bash examples/16-caching/verify.sh
```

`verify.sh` brings the three services up with `docker compose`, runs the cases below in a fixed order,
diffs each stack's live schema against `contracts/schema/` and tears the stack down. It prints `PASS`
only if every check holds on **both** stacks. It needs Docker Engine with the `docker compose` plugin
and Node/npm (for the pinned `graphql-inspector` in `contracts/`). The expiry case sleeps 21 seconds per
stack.

To explore by hand:

```bash
docker compose -f examples/16-caching/compose.yaml up -d --build
H=$(printf '%s' 'query PortName($code: UnLocode!) { location(unLocode: $code) { name } }' | sha256sum | cut -d' ' -f1)
# register the document by POST (APQ step two), then read it by GET through the edge
curl -s localhost:8260/graphql -H 'Content-Type: application/json' \
  -d "{\"query\":\"query PortName(\$code: UnLocode!) { location(unLocode: \$code) { name } }\",\"variables\":{\"code\":\"USNYC\"},\"extensions\":{\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}}"
for i in 1 2; do
  curl -s -D - -o /dev/null -G localhost:8262/graphql -H 'Accept: application/json' \
    --data-urlencode 'variables={"code":"USNYC"}' \
    --data-urlencode "extensions={\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}" | grep -iE '^(cache-control|x-cache-status)'
done
docker compose -f examples/16-caching/compose.yaml down -v
```

Use `8261` (direct) and `8263` (edge) for Python. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8260`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8261`. The handling TTL is
`TRACKING_HANDLING_CACHE_TTL` on Quarkus (a duration such as `20S`) and
`TRACKING_HANDLING_CACHE_TTL_SECONDS` on Python; compose sets 20 seconds.

A hash-only `GET` must send `Accept: application/json`. Strawberry serves its IDE page when `Accept`
includes `text/html` or `*/*`, and nginx forwards the header as sent. That page has no `Cache-Control`,
so the edge never stores it, but the client gets HTML.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the
log and answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`. The
endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it). The log is read on the
direct ports (8260, 8261), never through the edge. A cache hit is not a source call and leaves no entry.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8260 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8261 | `/graphql` (health at `/health`) |
| nginx in front of Quarkus | 8080 | 8262 | `/graphql` |
| nginx in front of Python | 8081 | 8263 | `/graphql` |

Compose project `gql-ch16-caching`, containers `ch16-caching-*`. The edge is
`registry.access.redhat.com/ubi10/nginx-126:10.1-1779165744`, run as uid 1001 with every writable
path under `/tmp`, and `edge/nginx.conf` mounted `:ro,z`. Telemetry is off by default. Add the
observability file (`docker compose -f compose.yaml -f compose.observability.yaml up --build`) to
send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so run
one example's observability stack at a time.

## On the wire

Each value below is asserted by `verify.sh`. The cases run in this order because cache state carries
forward: the earlier cases warm exactly the keys the later counts expect.

| Case | Request | Quarkus | Python |
|---|---|---|---|
| register | POST `PortName`, NLRTM, hash and text | `Rotterdam` | the same |
| edge miss | GET `PortName` USNYC through the edge | `Cache-Control: public, max-age=300`, `X-Cache-Status: MISS`, `New York`; one call, `location.getLocation:USNYC` | the same |
| edge hit | the same GET again | `X-Cache-Status: HIT`, `Cache-Control: public, max-age=300`, the same body, 0 source calls | the same |
| single key | `voyage(voyageNumber: "V200E")` twice | first: `voyage.getVoyage:V200E`; second: 0 `voyage` calls | the same |
| unknown key | `voyage(voyageNumber: "V999X")` twice | 1 `voyage.getVoyage` call | 2 `voyage.getVoyage` calls |
| `Q_FAN` run 1 | Chapter 13's four-cargo page | 8 calls; `location.getLocations` keys `DEHAM+SGSIN` and `CNSHA+DEHAM`; `voyage.getVoyages` `V100S+V300A` | 6 calls; `location.getLocations` `CNSHA+DEHAM+SGSIN`; `voyage.getVoyages` `V100S+V300A` |
| `Q_FAN` run 2 | the same, at once | 4 calls: `booking.listCargos`, `booking.getCargos`, two `routing.getItineraries`; 0 `voyage`, `location`, `handling` | 3 calls: `booking.listCargos`, `booking.getCargos`, `routing.getItineraries`; 0 `voyage`, `location`, `handling` |
| bulk warms single | `voyage(voyageNumber: "V100S")`, never read on its own | 0 `voyage` calls | the same |
| policy, direct | GET `PortName` by hash | `Cache-Control: public, max-age=300` | the same |
| policy, POST | the same document by POST | `no-store` | the same |
| policy, private | GET `TrackCargo` by hash | `no-store` | the same |
| policy, error | GET `{ location(unLocode: "NLRTM") { weight } }` | `no-store` | the same |
| policy, identity | GET `PortName` with `Authorization: Bearer x` | `no-store` | the same |
| policy, refusal | GET of an unregistered hash | `PersistedQueryNotFound`, `no-store` | the same |
| GET guards | a variant of a GET mutation; an unparseable GET document; `+` and `%` in a document and in variables, and in a document sent by hash over POST; `"100%"` by hash over POST; a single-operation mutation with `operationName=Nope` and with `operationName=` by text and by hash on 8260, 8262, 8261 and 8263; a GET with a form body; a WebSocket upgrade with one `Upgrade` header and with two | 405, then 400; 0 `appendEvent`; the text reaches the source unchanged; `Nope` gets 400 and an empty name 405 with no `data`; a GET with a form body answered; a WebSocket upgrade on 8260 gets 400 and the mutation sent over it writes nothing | 400, then 200 with errors; 0 `appendEvent`; the text reaches the source unchanged; 400 for both operation names; a GET with a form body answered |
| edge never stores | GET `TrackCargo` twice; an error GET twice; an unknown hash twice | `no-store`, `X-Cache-Status` never `HIT`; 2 `booking.getCargo` calls for the two `TrackCargo` reads | the same |
| edge, `Vary: Accept` | a `*/*` GET, then `Accept: application/json` for the same URL (DEHAM) | `MISS` with `Content-Type: application/json`, then `HIT` | the same, with `Accept: application/graphql-response+json` first |
| edge, no JSON `Accept` | hash-only GET with curl's default `Accept`, twice, on 8263 | not run | `text/html`, `MISS` both times |
| edge bypass | GET `PortName` NLRTM (MISS, then HIT), then with `Authorization` | `X-Cache-Status: BYPASS`, `Cache-Control: no-store`, the same data | the same |
| expiry | read XYZ789, `sleep 21`, read again | one `handling.listEventsFor:XYZ789` call, then 0 on the next read | the same |
| invalidation | read ABC123 twice, the first within 20 s of the mutation; register UNLOAD DEHAM V100S `2026-10-09T15:00:00Z`; read again | second read: 0 `handling` calls; mutation: `evt_10`, `IN_PORT`, 1 `appendEvent`, one `handling.listEventsFor:ABC123`, 0 `voyage`, 0 `location`; next read `IN_PORT`, 0 `handling` calls | the same |
| edge isolation | GET `PortName` SGSIN on 8262, on 8263, then each again | `MISS`, then `HIT` | `MISS`, then `HIT` |
| schema | live schema, direct port | conforms to `contracts/schema/`; `finalArrivalDate` deprecated; only `Subscription` is unserved | the same |

## Code-first notes

The checks below ran on the pinned versions (SmallRye GraphQL 2.18.5 on graphql-java 25.0, Quarkus 3.40.1,
`quarkus-cache` with Caffeine; Strawberry 0.335.0 on graphql-core 3.3.0, `cachetools` 7.2.2; nginx 1.26.3
from the UBI 10 image).

**`@AfterExecute` can set the header.** It fires after execution and before the response is written, on a
thread where `CurrentVertxRequest#getCurrent()` is the request being answered, so
`response().putHeader("Cache-Control", ...)` lands on the response that is sent. It fires for results with
validation errors, and `Context#unwrap(ExecutionResult.class)` and `unwrap(Document.class)` give the errors and
the parsed document. A Vert.x headers-end handler is not needed. The policy skips the header once the response head has been written, because a header set then would be ignored.

**Refusals carry their own policy.** `PersistedDocumentRoute` answers an unknown hash itself,
before the GraphQL engine runs, and so before `@AfterExecute`, and sets `Cache-Control: no-store` on its own responses (the `PersistedQueryNotFound`
body and the 405 for a mutation over `GET`).

**Refusals on Strawberry.** `PersistedQueries` refuses an unknown hash before execution, and the
`on_operation` code after the `yield` belongs to operations that complete. `CachePolicy` therefore sets
`no-store` before its `yield` and replaces it with the public policy after the `yield` when the result
qualifies, so the refusal carries a header.

**`@CacheResult` on a `Uni`.** It caches the item and skips failures. `@CacheKey` on the voyage number
or UN/LOCODE excludes the `request` argument, so the key is the same for every request (the second
`voyage(V200E)` read makes no call). The entries are the same ones the bulk path writes with
`CaffeineCache#put`, so a bulk read fills the single-key path. A null item (an unknown key) is
cached by the annotation: a second `voyage(voyageNumber: "V999X")` read makes no call on Quarkus, and two
calls on Python, whose caches store only found values. The bulk path stores only found values on both
stacks and treats Quarkus' null marker as a miss. Quarkus therefore remembers "unknown" for the TTL on the
single-key path, which is negative caching, and a production service chooses whether to allow it.

**`@CacheInvalidate` on a `Uni<Void>`** evicts when the `Uni` completes, so
`handling.evict(trackingId)` chained after the append runs before the payload's read.

**nginx on the UBI image.** The image runs the supplied config as uid 1001 with the pid file, the five
temp paths and the cache under `/tmp`. `curl` is present for the healthcheck. nginx honours the upstream's
`max-age` and `no-store`, stores nothing without a `Cache-Control` or `Expires`, and sends no `Age`
header, so the cases assert `X-Cache-Status`. `proxy_no_cache` and `proxy_cache_bypass` on
`$http_authorization` give `BYPASS`.

**The cache key needs the origin.** A key of `"$scheme$request_method$host$request_uri"` has no port
and both listeners share one cache zone, so the Python listener would be answered `HIT` with the Quarkus
entry. The key is `"$scheme$request_method$proxy_host$request_uri"`, so it names the upstream. A shared
cache with several origins needs the origin in its key.

**Race with a concurrent reader.** Eviction removes the entry, but a read that started before the write
and finishes after it can store the old list again. The TTL bounds that staleness. It is the reason the
TTL exists beside the eviction.

**Timing.** Whole seconds only: a 20-second TTL and `sleep 21`. The expiry case sleeps before the invalidation
case so that no entry from earlier cases is near its end, and the invalidation case needs about 3 seconds (of the 20)
between its first read and its last.

**Strawberry notes.**

- Every extension is passed as a class or a factory (`functools.partial`), so each request has its own
  instance.
- `TTLCache` is not thread-safe; every access runs on the event loop between awaits.
- The context's `response` is the response FastAPI sends; headers set there reach the client.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/16-caching-architecture.py`) show the compose topology: a client reaching
the nginx edge, the edge in front of both stacks, and the direct ports.
