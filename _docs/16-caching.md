---
title: "Caching"
order: 16
part: "Performance & Safety"
description: "Four places to keep an answer: the client's normalized cache, an HTTP edge fed by persisted GET URLs, field caches under the loaders, and the sources, with Cache-Control decided per response and invalidation on write."
duration: "13 min read"
---

## Learning objectives

By the end of this chapter you can:

- Place an answer in the right one of four cache layers (client normalized cache, HTTP edge, server field caches, source of record), and name what evicts each.
- Decide `Cache-Control: public, max-age=300` vs. `no-store` per response from a four-test policy: `GET`, no errors, reference-only data, no `Authorization`.
- Configure an nginx edge with `proxy_cache_bypass` and `proxy_no_cache` keyed on `$http_authorization` so a cached response never leaks to another caller.
- Invalidate a field-level cache (`@CacheInvalidate`, `cache.pop`) in the correct order relative to a write, so a mutation payload never reads a stale value.
- Explain why identity must be in a cache key or the value must never be stored, and why whole-response caching inside the server doesn't pay off here.

## Why this matters

A `POST` to `/graphql` carries its question in a body that no intermediary reads, so nothing between the client and the server can reuse an answer. A persisted `GET`, with a hash and variables in the URL, can be reused by anything that keys on the URL, and the rest of the stack can reuse answers too.

In `examples/16-caching/` each stack runs in APQ mode behind an nginx cache, with a `Cache-Control` decision for every response and three field-level caches inside each server. The query-cost limits are left out; a production service carries both.

## Four places to keep an answer

Each place has its own key and its own way of losing an entry.

{% include excalidraw.html file="16-cache-layers" alt="Four boxes run left to right. The client cache is keyed by typename and id and an entry is replaced by a newer response for the same object. The edge, nginx proxy_cache, is keyed by method and URL, stores what Cache-Control allows, skips requests with Authorization or responses marked no-store, and drops an entry when max-age passes. The server's field caches are keyed by voyage number, UN/LOCODE and tracking id, and entries are removed by TTL or by a write through registerHandlingEvent. The sources are the owners of the data, the system of record, and every call to them is logged. Arrows between the boxes are labelled GET, miss and miss. A dashed box below says the DataLoader loader cache lasts one request and shares nothing between requests." caption="Figure 16.1: The four places to keep an answer, nearest the caller first, with what each one keys on and what removes an entry." %}

| Layer | Key | Removed by |
|---|---|---|
| Client normalized cache | `__typename` and `id` | a newer response for the same object |
| Edge (nginx) | method and URL | `max-age` passing; never stores `no-store` or `Authorization` requests |
| Server field caches | the source's own key (voyage number, UN/LOCODE, tracking id) | TTL, or a write through `registerHandlingEvent` |
| Sources | the owners' own | n/a: the system of record |

The per-request DataLoader cache lives for one request. The field caches sit under the loaders and outlive it.

Kleppmann and Riccomini separate systems of record from derived data in *Designing Data-Intensive Applications*, 2nd edition. A cache is derived data: it can be thrown away and rebuilt from the source, and the only question is how stale a copy may be before someone is harmed. Each layer answers with a time limit, an event, or both.

## The client's normalized cache

The `id` of every `Node` is stable and unique across the graph, so a client that selects `id` and `__typename` on every object can store each object once. When a later response contains the same `Cargo`, the client replaces the stored fields and every view that reads them updates. The `nodes` query refreshes a known set of objects in one request, and a mutation payload that returns the changed object updates the cache without a refetch.

The server's part is to keep `id` stable and to return the changed object from a mutation, as `registerHandlingEvent` does with `cargo { id delivery { transportStatus } }`.

## Caching at the edge needs GET

An HTTP cache keys on the request method and the URL. RFC 9111, in "Storing Responses in Caches", lets a cache store a response only when the request method is one it understands, and nginx stores `GET` and `HEAD` and nothing else unless told to. Even where a cache will store a `POST` response, the request body isn't part of the key, so two different documents posted to one URL would collide.

The persisted `GET` removes the obstacle. The URL carries the hash, the variables and the operation name, so it identifies the question the way a REST path identifies a resource.

{% include excalidraw.html file="16-edge-cache-hit" alt="Two bands show the same GET twice. In the first, a client sends GET slash graphql with variables code USNYC, the extensions carrying the hash, and Accept application/json. nginx on port 8262 has no entry for the URL, reports X-Cache-Status MISS and stores the answer. Quarkus on port 8260 answers with Cache-Control public, max-age 300, after one source call to the location owner, location.getLocation USNYC. In the second band the same GET reaches nginx, which finds a fresh entry, reports X-Cache-Status HIT and answers from the cache. The Quarkus box and the location owner box are dashed and labelled not reached and zero source calls. A note says both responses carry the same body and that the stacks differ only in header case." caption="Figure 16.2: A persisted GET of reference data: stored by the first request and answered by the second, with no call to the server or the owner." %}

Three details of the setup matter:

- **The request must say it wants JSON.** Strawberry answers a hash-only `GET` with its IDE page when `Accept` includes `text/html` or `*/*`, and nginx forwards `Accept` as sent, so the client must send `Accept: application/json`. The IDE page carries no `Cache-Control`, so it is never stored. Every `public` response carries `Vary: Accept`, and nginx stores one entry per `Accept` value: a `*/*` request that Quarkus answers as `application/graphql-response+json` doesn't fill the entry that a later `Accept: application/json` request is served from.
- **The key needs the origin.** The two listeners share one cache zone and `$host` carries no port, so a key of scheme, method, host and URI would answer the Python listener with the Quarkus entry. Any cache that fronts several origins needs the origin in its key.
- **Nothing is stored on nginx's say-so.** There is no `proxy_cache_valid`, so a response with no `Cache-Control` or `Expires` is never stored. The server must opt in.

## Deciding Cache-Control per response

`Cache-Control` is the server's statement about who may keep a response and for how long. RFC 9111's "Cache-Control" section defines the directives. `public, max-age=300` lets any cache keep the response for 300 seconds, and `no-store` forbids any cache to keep it.

One URL path carries every document, so the decision has to look at the operation and the result. Four tests run in order, and any no ends in `no-store`.

{% include excalidraw.html file="16-cache-policy-decision" alt="A vertical chain of four questions, each answered yes to continue and no to leave. The first asks whether the request is a GET, because a POST body is not part of any cache key. The second asks whether execution finished without errors, because an error describes one request. The third asks whether all root fields are reference data, which are location, voyage and __typename. The fourth asks whether there is no Authorization header, because what a caller may read can depend on who asks. Four arrows labelled no run to a box on the right that reads Cache-Control no-store, and a note says a PersistedQueryNotFound refusal is no-store too. The yes arrow from the fourth question leads to a highlighted box reading Cache-Control public, max-age 300." caption="Figure 16.3: The Cache-Control decision: four tests, and any no ends in no-store." %}

Only `location` and `voyage` are reference data: facts about the world that change on a timescale of days. A cargo's delivery status changes with every handling event, so `cargo` is never public. The policy may be wrong in the safe direction, and a response it calls `no-store` costs one more request to the server.

Each framework has a place to run this after execution. On Quarkus, the CDI event `@AfterExecute` fires once the result is known and before the response is written. Strawberry's `SchemaExtension.on_operation` wraps the whole operation.

{% include codetabs.html langs="Quarkus|Python" %}

```java
    void decide(@Observes @AfterExecute Context context) {
        RoutingContext routing = currentRequest.getCurrent();
        if (routing == null || routing.response().headWritten()) {
            return;
        }
        String policy = policyFor(routing, context);
        routing.response().putHeader("Cache-Control", policy);
        if (PUBLIC.equals(policy)) {
            // The body depends on the Accept header, so a cache keeps one entry per Accept value.
            routing.response().putHeader("Vary", "Accept");
        }
    }

    private static String policyFor(RoutingContext routing, Context context) {
        boolean get = HttpMethod.GET.equals(routing.request().method());
        boolean anonymous = routing.request().getHeader("Authorization") == null;
        ExecutionResult result = context.unwrap(ExecutionResult.class);
        boolean clean = result != null && result.getErrors().isEmpty();
        boolean reference = onlyReferenceData(context.unwrap(Document.class), context.getOperationName().orElse(null));
        return get && anonymous && clean && reference ? PUBLIC : NO_STORE;
    }
```

```python
    def on_operation(self) -> Iterator[None]:
        context = self.execution_context
        response = context.context.response
        # The default comes first, so a request refused before execution (a hash the server does not
        # know) still carries a policy: the code after this yield runs for operations that complete.
        response.headers["Cache-Control"] = NO_STORE
        yield
        request = context.context.request
        result = context.result
        if (
            request.method == "GET"
            and "authorization" not in request.headers
            and result is not None
            and not result.errors
            and self._only_reference_data()
        ):
            response.headers["Cache-Control"] = PUBLIC
            # The body depends on the Accept header, so a cache keeps one entry per Accept value.
            response.headers["Vary"] = "Accept"
```

A refusal carries its own policy. The persisted-queries extension refuses an unknown hash before execution, so the Python extension sets `no-store` first and replaces it after the `yield` when the result qualifies. On Quarkus the persisted-document route answers the refusal itself, before the `@AfterExecute` observer runs, and sets `no-store` on its own response. An unknown hash comes back `no-store` on both stacks, so a client that registers the document a moment later doesn't meet a cache that remembers the refusal.

Field-level hints such as Apollo's `@cacheControl` directive attach a maximum age to a type or field and let the server compute the minimum over what a response touched. The canonical schema has no such directive, and caching policy lives outside the SDL here. A per-root-field list in code is the same idea at a smaller scale.

## The edge itself

The edge is `registry.access.redhat.com/ubi10/nginx-126:10.1-1779165744` with one mounted file, `edge/nginx.conf`. It runs as uid 1001, so the pid file, the five temporary paths and the cache live under `/tmp`, and the file is mounted `:ro,z` so an SELinux host relabels it.

```nginx
proxy_cache         graphql;
proxy_cache_methods GET HEAD;
proxy_cache_key     "$scheme$request_method$proxy_host$request_uri";
proxy_no_cache      $http_authorization;
proxy_cache_bypass  $http_authorization;

proxy_http_version 1.1;
proxy_set_header   Host $host;
add_header         X-Cache-Status $upstream_cache_status always;
```

`proxy_cache_bypass` makes a request that carries `Authorization` skip the lookup, and `proxy_no_cache` keeps its response out of the store. The status header says what happened: `MISS`, `HIT` or `BYPASS`. nginx adds no `Age` header, so `X-Cache-Status` is what to check; Varnish would report `Age`, and either honors `max-age` and `no-store` from the origin.

The reason for the bypass is in the key. The URL says nothing about who asked, and a stored response that depended on the caller would go to the next caller. Reference data doesn't depend on the caller, but authentication and authorization add operations that do, such as returning only the cargos a shipper owns. So bypass shared caches whenever `Authorization` is present, and give any response built from a caller's own data `no-store`, which the fourth test does. RFC 9111's "Storing Responses to Authenticated Requests" lets a shared cache store an authenticated response when it carries `public`, which is why the policy never sends `public` to a request with `Authorization`. The alternative is to add the caller to the key, and an edge that keys on identity stores one copy per caller and gains little.

## Caching inside the server

A field-level cache sits at the bulk source, under the DataLoader loaders. It answers the keys it holds so that only the misses reach the owner. The loaders still batch every `load` of a tick into one call, and the batch key is now the sorted distinct misses joined with `+`. A call that a cache answered leaves no entry in the log of calls to the owners.

There are three caches:

| Cache | Holds | TTL |
|---|---|---|
| `voyages`, `locations` | reference data | 300 seconds |
| `handling-events` | a cargo's event list under its tracking id | 60 seconds; 20 in the lab so expiry doesn't wait a minute |

Each stack uses its framework's cache. On Quarkus, `quarkus-cache` is Caffeine behind annotations. `@CacheResult` on the single-key read caches the item, and `@CacheKey` leaves the request id out of the key. The bulk read takes the keys itself, because an annotation caches one call per distinct argument and a bulk call takes many: it asks the cache for each key with `getIfPresent`, calls the owner once for the misses, and `put`s what it gets. On Python, `cachetools.TTLCache` is a mapping with an expiry, and the same split is a few lines around it.

{% include codetabs.html langs="Quarkus|Python" %}

```java
    @CacheResult(cacheName = "voyages")
    public Uni<Voyage> getVoyage(String request, @CacheKey String number) {
        return calls.call(request, "voyage", "getVoyage", number, () -> data.voyage(number));
    }

    public Uni<List<Outcome<Voyage>>> getVoyages(String request, List<String> numbers) {
        return BulkCache.through(
                cache,
                Voyage.class,
                numbers,
                misses -> calls.callBatch(request, "voyage", "getVoyages", misses, data::voyage));
    }
```

```python
    async def get_voyages(self, numbers: Sequence[str]) -> list[Outcome[Voyage]]:
        """Many voyages in one call: one outcome per voyage number, in the
        order asked; ``None`` when unknown. Only the cache misses reach the owner."""
        return await _through(
            self.cache,
            numbers,
            lambda misses: self.calls.call_batch(
                self.request, "voyage", "getVoyages", misses, data.VOYAGES.get
            ),
        )

    async def get_voyage(self, number: str) -> Voyage | None:
        if (cached := self.cache.get(number)) is not None:
            return cached
        found = await self.calls.call(
            self.request, "voyage", "getVoyage", number, lambda: data.VOYAGES.get(number)
        )
        if found is not None:
            self.cache[number] = found
        return found
```

The first run of the four-cargo query makes 8 calls on Quarkus and 6 on Python, with fewer keys in them. A second run inside the TTL makes 4 on Quarkus and 3 on Python: the booking page, the cargos and the itineraries, which no cache holds. The voyage, location and handling calls are gone. Voyages and locations are static for the life of the process, while handling events change when a write lands.

**Where the stacks differ.** On Quarkus, `@CacheResult` stores the result for an unknown key as well, so a second read of an unknown voyage makes no call: the single-key path does negative caching for the TTL. The bulk path, and Python, store only found values. Decide whether a missing voyage may be remembered.

## Invalidating on write

A TTL alone answers "how stale" with a number, and that number is wrong for a user who has just registered an event and reads it back. `registerHandlingEvent` returns a payload with the cargo's new `delivery.transportStatus`. If the handling cache still held the old event list, the payload would say `ONBOARD_CARRIER` for the event it had just recorded.

The fix is to evict the cargo's entry after the append succeeds and before the payload reads the cargo.

{% include excalidraw.html file="16-invalidation-on-write" alt="Six boxes in a loop of two rows. Step one reads the delivery of cargo ABC123, finds handling-events ABC123 empty, makes one listEventsFor call and returns ONBOARD_CARRIER. Step two reads it again, finds the entry and makes zero handling calls. Step three registers an UNLOAD at DEHAM on V100S with one appendEvent call that returns evt_10. Step four, highlighted, evicts the entry for ABC123 after the append and before the payload reads the cargo. Step five, highlighted, reads the payload's delivery, finds the entry missing, makes one listEventsFor call that refills it and returns IN_PORT. Step six reads the cargo again, finds the entry and makes zero handling calls, returning IN_PORT. Notes say that without step four the payload would answer ONBOARD_CARRIER and that the TTL bounds staleness from writers that never call this service." caption="Figure 16.4: Invalidation on write: the entry is evicted after the append and before the payload re-reads, so the payload and every later read agree." %}

On Quarkus the eviction is `@CacheInvalidate(cacheName = "handling-events")` on a method of `HandlingSource`, which `HandlingRegistration` chains between the append and the cargo read. On Python it is `self.cache.pop(tracking_id, None)` in `registration.py` at the same point. The cargo's next `delivery` read misses, makes one `listEventsFor` call for `ABC123`, refills the entry, and the read after that makes no call.

The order is the design. Evicting before the append lets a concurrent reader refill the entry with the old list. Evicting after the payload read hands the payload the old list. Even in the right order, a reader that started before the write and finishes after the eviction can store the old list again. That race is rare and bounded by the TTL.

## Expiry as the backstop

Eviction on write covers the writers this service knows about. It doesn't cover a batch import into the handling service or a second API that writes to the same store; neither calls the eviction. The TTL bounds how long a copy can disagree with the system of record, and it bounds the race above.

A TTL is a choice about harm. Reference data changes rarely, so 300 seconds is cheap. A cargo's events matter to the person looking at the cargo, so the default is 60 seconds. Set these numbers from the business.

## What changes with replicas

Everything above lives in the process that owns it. With several replicas, each holds its own copy: a write that lands on replica A evicts A's entry, and replica B serves the old list until its TTL passes. The edge has the same property, one cache per nginx. There are two ways out:

- **A shared cache**, such as Valkey, the BSD-licensed fork of Redis hosted by the Linux Foundation, holds one copy for every replica and moves the eviction to a place all of them see.
- **Per-replica caches with a published eviction.** A write publishes an eviction on a channel that every replica subscribes to.

Both add a moving part and a network hop to every read. With one replica, neither is needed.

## Why not cache whole responses in the server

A server could keep complete responses, keyed by document, variables and caller. Don't build it, for three reasons:

- **The key is large.** It needs the document or its hash, the variables, the operation name and the caller's identity, and a GraphQL server has no URL to lean on.
- **Invalidation cannot see inside.** A stored response is a blob. When a handling event is registered, the server can't tell which stored responses contain that cargo without parsing every one.
- **The edge already does it for public reads.** Responses every caller may share are exactly the ones the edge stores, keyed by a URL that already exists. Responses that depend on the caller would need a cache with one entry per caller.

Responses belong at the edge for public data; the server caches fields, where keys are small and an event can name what to remove.

## Identity belongs in the key

Every cache above holds data that is the same for every caller. A cargo's event list is reached only after the booking source has returned the cargo, so a caller who may not see the cargo never reaches its entry. That is why none of the keys contain an identity. The rule for anything else: a stored value that varies by caller needs the caller in its key, or must not be stored. Bypass shared caches for any request that carries `Authorization`.

> **Decision**
>
> Each layer answers the caching-needs axis differently. Public reference data goes to the edge through persisted `GET`s with an explicit `Cache-Control`; source reads go to field caches with a TTL and an eviction on write; anything that depends on the caller stays out of shared caches. The price is operational: every cache is derived data whose staleness is a decision. Cache reference data for 300 seconds at the edge and in the server, cache handling events briefly and evict them on every registration, never store a response to a request that carries `Authorization`, and add a shared cache only when there are replicas to share it.

> **🤖 Explore with your agent**
>
> "In examples/16-caching, check the Cache-Control policy in CachePolicy.java and cache_policy.py against its four tests (GET, no errors, reference-only root fields, no Authorization). Then send the PortName document and the TrackCargo document by persisted GET through the edges on ports 8262 (Quarkus) and 8263 (Python), twice each, and report Cache-Control and X-Cache-Status for every response."
>
> Check: PortName answers `public, max-age=300` with `MISS` then `HIT` on both edges; TrackCargo answers `no-store` and is never a `HIT`.

## Build, run, observe

Direct ports are 8260 (Quarkus) and 8261 (Python); the edges are 8262 and 8263. `H` is the hash of the `PortName` document in the manifest.

```bash
docker compose -f examples/16-caching/compose.yaml up -d --build
H=$(printf '%s' 'query PortName($code: UnLocode!) { location(unLocode: $code) { name } }' | sha256sum | cut -d' ' -f1)
# register the document by POST: this response is no-store
curl -s -D - localhost:8260/graphql -H 'Content-Type: application/json' \
  -d "{\"query\":\"query PortName(\$code: UnLocode!) { location(unLocode: \$code) { name } }\",\"variables\":{\"code\":\"USNYC\"},\"extensions\":{\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}}"
# the same document by GET, twice, through the edge
for i in 1 2; do
  curl -s -D - -o /dev/null -G localhost:8262/graphql -H 'Accept: application/json' \
    --data-urlencode 'variables={"code":"USNYC"}' \
    --data-urlencode "extensions={\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}" | grep -iE '^(cache-control|x-cache-status)'
done
# with a bearer token the edge steps aside
curl -s -D - -o /dev/null -G localhost:8262/graphql -H 'Accept: application/json' -H 'Authorization: Bearer x' \
  --data-urlencode 'variables={"code":"USNYC"}' \
  --data-urlencode "extensions={\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}" | grep -iE '^(cache-control|x-cache-status)'
docker compose -f examples/16-caching/compose.yaml down -v
```

The two `GET`s print `Cache-Control: public, max-age=300` with `X-Cache-Status: MISS`, then `HIT`. The bearer request prints `Cache-Control: no-store` and `X-Cache-Status: BYPASS`. Run `bash examples/16-caching/verify.sh` for the full sequence on both stacks; it prints `PASS` only when both hold. The cases run in a fixed order, because earlier ones warm the keys that later counts expect.

| Check | Quarkus | Python |
|---|---|---|
| edge, first GET | `public, max-age=300`, `MISS`, `New York`; one call, `location.getLocation:USNYC` | the same |
| edge, second GET | `HIT`, the same body, 0 source calls | the same |
| edge, `Vary: Accept` | a `*/*` GET, then `Accept: application/json` for the same URL: `MISS`, then `HIT` | the same, with `Accept: application/graphql-response+json` first, because `*/*` gets the IDE page |
| single-key voyage twice | first `voyage.getVoyage:V200E`; second 0 `voyage` calls | the same |
| four-cargo query, run 1 | 8 calls; `voyage.getVoyages` `V100S+V300A` | 6 calls; the same key |
| four-cargo query, run 2 | 4 calls, none to `voyage`, `location`, `handling` | 3 calls, the same exclusions |
| `Cache-Control`, direct | GET `PortName`: `public, max-age=300`; the same by POST, a `TrackCargo` GET, an error GET, a GET with `Authorization`, an unknown hash: `no-store` | the same |
| edge, never stored | `TrackCargo`, an error, an unknown hash, each twice: never `HIT`; 2 `booking.getCargo` calls | the same |
| edge, bypass | `BYPASS`, `no-store`, the same data | the same |
| expiry | read, `sleep 21`, read: one `handling.listEventsFor:XYZ789` call | the same |
| invalidation | second read 0 `handling` calls; mutation `evt_10`, `IN_PORT`, one `listEventsFor:ABC123`; next read `IN_PORT`, 0 calls | the same |

Experiments:

- Add `Authorization: Bearer x` to a cached GET: the edge answers `BYPASS` with `Cache-Control: no-store`.
- Read a cargo, wait 21 seconds in the lab, and read again: the entry has expired and one `handling.listEventsFor` call reaches the owner.
- Remove the eviction call and register a handling event: the payload answers `ONBOARD_CARRIER` instead of `IN_PORT`.

## For deeper coverage

- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd edition (O'Reilly): systems of record versus derived data, the frame all four layers answer to.
- Samer Buna, *GraphQL in Action* (Manning, 2021), chapter "Optimizing data fetching": field-level caching under the loaders.
- Cloud Native Design Patterns, chapter "Appendix L: Caching": the general cache-layer and invalidation patterns.
- RFC 9111, "HTTP Caching" ("Storing Responses in Caches", "Cache-Control"), and "Safe Methods" in RFC 9110, "HTTP Semantics", for why `GET` is the method a cache may reuse.
- [nginx `ngx_http_proxy_module` reference](https://nginx.org/en/docs/http/ngx_http_proxy_module.html): the `proxy_cache`, `proxy_cache_bypass` and `proxy_no_cache` directives.
- The Quarkus [Application data caching](https://quarkus.io/guides/cache) guide and the [cachetools](https://cachetools.readthedocs.io/) documentation.
- Apollo's documentation on caching, for the `@cacheControl` directive, and the [Valkey](https://valkey.io/) project.
