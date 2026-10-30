---
title: "Caching"
order: 16
part: "Performance & Safety"
description: "Four places to keep an answer: the client's normalized cache, an HTTP cache that persisted GET URLs make possible, field-level caches under the server's loaders, and the sources. Cache-Control decided per response, an nginx edge that bypasses on Authorization, TTLs, invalidation on registerHandlingEvent, and why the identity of the caller belongs in every key."
duration: "16 min read"
---

## Learning objectives

By the end of this chapter you can:

- Place an answer in the right one of four cache layers (client normalized cache, HTTP edge, server field caches, source of record), and name what evicts each.
- Decide `Cache-Control: public, max-age=300` vs. `no-store` per response from the chapter's four-test policy: `GET`, no errors, reference-only data, no `Authorization`.
- Configure an nginx edge with `proxy_cache_bypass` and `proxy_no_cache` keyed on `$http_authorization` so a cached response never leaks to another caller.
- Invalidate a field-level cache (`@CacheInvalidate`, `cache.pop`) in the correct order relative to a write, so a mutation payload never reads a stale value.
- Explain why identity must be in a cache key or the value must never be stored, and why whole-response caching inside the server doesn't pay off here.

## Why this matters

Persisted queries turn a document into a hash, and a hash fits in a URL. That is the precondition for everything in this chapter. A `POST` to `/graphql` carries its question in a body that no intermediary reads, so nothing between the client and the server can reuse an answer. A `GET` with a hash and variables in the URL can be reused by anything that keys on the URL, and the rest of the stack can reuse answers too.

The code is in `examples/16-caching/`. It starts from the persisted-queries example in APQ mode only, so the schema, the seed, the error contract and the persisted-query code are unchanged. What is new is an nginx cache in front of each stack, a `Cache-Control` decision for every response, and three field-level caches inside each server. The chapter does not repeat the query-cost limits, and a production service would carry both.

## Four places to keep an answer

A GraphQL service has four places where an answer can be kept, and each one has its own key and its own way of losing an entry. Figure 16.1 lists them in the order a request meets them.

{% include excalidraw.html file="16-cache-layers" alt="Four boxes run left to right. The client cache is keyed by typename and id and an entry is replaced by a newer response for the same object. The edge, nginx proxy_cache, is keyed by method and URL, stores what Cache-Control allows, skips requests with Authorization or responses marked no-store, and drops an entry when max-age passes. The server's field caches are keyed by voyage number, UN/LOCODE and tracking id, and entries are removed by TTL or by a write through registerHandlingEvent. The sources are the owners of the data, the system of record, and every call to them is logged. Arrows between the boxes are labelled GET, miss and miss. A dashed box below says the DataLoader loader cache lasts one request and shares nothing between requests." caption="Figure 16.1: The four places to keep an answer, nearest the caller first, with what each one keys on and what removes an entry." %}

- **The client's normalized cache** stores objects by `__typename` and `id`, the identity Global Object Identification gave every `Node`. A response for one query updates the objects that a different query shows, which is how a mutation payload refreshes a screen. Client integration builds it.
- **The edge** keeps whole responses by method and URL. It is the layer that persisted `GET`s make possible, and the one this chapter runs as nginx.
- **The server's field caches** keep what a source returned, by the source's own key. They sit under the loaders: the per-request DataLoader cache inside a loader lives for one request, and these outlive it.
- **The sources** are the owners. They are the system of record, and every other layer is a copy of what they said.

That last point frames the sections that follow. Martin Kleppmann and Chris Riccomini separate systems of record from derived data in *Designing Data-Intensive Applications*, 2nd edition. A cache is derived data: it can be thrown away and rebuilt from the source, and the only question is how stale a copy may be before someone is harmed. Each layer below answers that question with a time limit, an event, or both.

## The client's normalized cache

The client cache needs nothing from the server beyond what the schema already has. Global Object Identification made `id` stable and unique across the graph, and a client that selects `id` and `__typename` on every object can store each object once. When a later response contains the same `Cargo`, the client replaces the stored fields and every view that reads them updates. The `nodes` query refreshes a known set of objects in one request, and a mutation payload that returns the changed object updates the cache without a refetch.

The server's part is to keep `id` stable and to return the changed object from a mutation, which `registerHandlingEvent` does with `cargo { id delivery { transportStatus } }`. Client integration shows the client side. The remaining sections cover the three layers the server runs.

## Caching at the edge needs GET

An HTTP cache keys on the request method and the URL. RFC 9111, in its section "Storing Responses in Caches", lets a cache store a response only when the request method is one the cache understands, and nginx stores `GET` and `HEAD` and nothing else unless told to. Even where a cache is willing to store a `POST` response, the request body is not part of the key, so two different documents posted to one URL would collide. That is the reason the opening REST-to-GraphQL comparison gave for GraphQL's missing HTTP caching.

The persisted-query `GET` removes the obstacle. The URL carries the hash, the variables and the operation name, so it identifies the question the way a REST path identifies a resource. Figure 16.2 follows one such request through the edge twice.

{% include excalidraw.html file="16-edge-cache-hit" alt="Two bands show the same GET twice. In the first, a client sends GET slash graphql with variables code USNYC, the extensions carrying the hash, and Accept application/json. nginx on port 8262 has no entry for the URL, reports X-Cache-Status MISS and stores the answer. Quarkus on port 8260 answers with Cache-Control public, max-age 300, after one source call to the location owner, location.getLocation USNYC. In the second band the same GET reaches nginx, which finds a fresh entry, reports X-Cache-Status HIT and answers from the cache. The Quarkus box and the location owner box are dashed and labelled not reached and zero source calls. A note says both responses carry the same body and that the stacks differ only in header case." caption="Figure 16.2: A persisted GET of reference data: stored by the first request and answered by the second, with no call to the server or the owner." %}

Three details of the setup matter.

**The request must say it wants JSON.** Persisted queries showed that Strawberry answers a hash-only `GET` with its IDE page when `Accept` includes `text/html` or `*/*`. nginx forwards `Accept` as sent, so the client must send `Accept: application/json`, and the example's `verify.sh` does. The IDE page carries no `Cache-Control`, so the edge never stores it. Every `public` response carries `Vary: Accept`, as part of the policy, and nginx stores one entry per `Accept` value: a `*/*` request that Quarkus answers as `application/graphql-response+json` does not fill the entry that a later `Accept: application/json` request is served from.

**The key needs the origin.** The two listeners share one cache zone and `$host` carries no port, so a key of scheme, method, host and URI would answer the Python listener with the Quarkus entry. The key includes the upstream. Any cache that fronts several origins needs the origin in its key.

**Nothing is stored on nginx's say-so.** The example sets no `proxy_cache_valid`, so a response with no `Cache-Control` or `Expires` is never stored. The server must opt in, which leads to the next section.

## Deciding Cache-Control per response

`Cache-Control` is the server's statement about who may keep a response and for how long. RFC 9111's section "Cache-Control" defines the directives, and the two the example uses are `public, max-age=300`, meaning any cache may keep the response for 300 seconds, and `no-store`, meaning no cache may keep it at all.

GraphQL has no per-URL answer to "how long", because one URL path carries every document. The decision has to look at the operation and the result. The example makes it in one place per stack, from four tests in order, drawn in Figure 16.3.

{% include excalidraw.html file="16-cache-policy-decision" alt="A vertical chain of four questions, each answered yes to continue and no to leave. The first asks whether the request is a GET, because a POST body is not part of any cache key. The second asks whether execution finished without errors, because an error describes one request. The third asks whether all root fields are reference data, which are location, voyage and __typename. The fourth asks whether there is no Authorization header, because what a caller may read can depend on who asks. Four arrows labelled no run to a box on the right that reads Cache-Control no-store, and a note says a PersistedQueryNotFound refusal is no-store too. The yes arrow from the fourth question leads to a highlighted box reading Cache-Control public, max-age 300." caption="Figure 16.3: The Cache-Control decision: four tests, and any no ends in no-store." %}

The rule is narrow. Only `location` and `voyage` are reference data: facts about the world that change on a timescale of days. A cargo's delivery status changes with every handling event, and `cargo` is therefore never public. The policy is allowed to be wrong in the safe direction, and a response it calls `no-store` costs one more request to the server.

Each framework has a place to run this after execution. On Quarkus, the CDI event `@AfterExecute` fires once the result is known and before the response is written, and the observer puts the header on the Vert.x response. Strawberry's `SchemaExtension.on_operation` wraps the whole operation, and the extension writes the header on the response FastAPI sends.

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

A refusal carries its own policy. The persisted-queries extension refuses an unknown hash before execution, and the policy code that runs after the `yield` belongs to operations that complete. The Python extension therefore sets `no-store` first and replaces it after the `yield` when the result qualifies. On Quarkus the persisted-document route answers the refusal itself, before the `@AfterExecute` observer runs, and sets `no-store` on its own response. An unknown hash then comes back `no-store` on both stacks, and a client that registers the document a moment later does not meet a cache that remembers the refusal.

The chapter does not adopt field-level hints such as Apollo's `@cacheControl` directive, which attaches a maximum age to a type or a field and lets the server compute the minimum over what a response touched. The canonical schema has no such directive, and the contract-first approach to schema design settled that caching policy lives outside the SDL. A per-root-field list in code is the same idea at a smaller scale.

## The edge itself

The edge is `registry.access.redhat.com/ubi10/nginx-126:10.1-1779165744` with one mounted file. It runs as uid 1001, so the pid file, the five temporary paths and the cache all live under `/tmp`, and the file is mounted `:ro,z` so that an SELinux host relabels it. The directives that matter:

```nginx
proxy_cache         graphql;
proxy_cache_methods GET HEAD;
proxy_cache_key     "$scheme$request_method$proxy_host$request_uri";
proxy_no_cache      $http_authorization;
proxy_cache_bypass  $http_authorization;
add_header         X-Cache-Status $upstream_cache_status always;
```

`proxy_cache_bypass` makes a request that carries `Authorization` skip the lookup, and `proxy_no_cache` keeps its response out of the store. The status header says what happened: `MISS`, `HIT`, or `BYPASS`. nginx adds no `Age` header, so the example asserts `X-Cache-Status`. A Varnish cache would report `Age`, and either one honours `max-age` and `no-store` from the origin.

The reason for the bypass is in the key. The URL says nothing about who asked. If a response that depended on the caller were stored under a URL, the next caller would receive it. The tracking view's reference data does not depend on the caller, and authentication and authorization add callers that do, with operations that return only the cargos a shipper owns. The rule is to bypass shared caches whenever an `Authorization` header is present, and to give every response that came from a caller's own data a `no-store`, which the policy above does through its fourth test. RFC 9111's section "Storing Responses to Authenticated Requests" lets a shared cache store an authenticated response when it carries `public`, which is why the policy never sends `public` to a request with `Authorization`. The alternative is to add the caller to the key, and an edge that keys on identity stores one copy per caller and gains little.

## Caching inside the server

The third layer keeps what a source returned, across requests. DataLoader batching turned a request's reads into one call per kind of key and left the cache inside the loader to repeat nothing within a request. A field-level cache sits one level lower, at the bulk source, and answers keys it already holds so that only the misses reach the owner.

The example has three caches:

- `voyages` and `locations` hold reference data for 300 seconds.
- `handling-events` holds a cargo's event list under its tracking id. The TTL is 60 seconds by default and 20 seconds in the lab, so that the expiry case does not wait a minute.

The loaders are unchanged. They still batch every `load` of a tick into one call, and the call now goes to a source that checks a cache first. The log of calls to the owners records only what reached them, so a call that a cache answered leaves no entry. A bulk read answered in part by the cache logs only the missing keys. The DataLoader batch key rule carries over: sorted distinct keys joined with `+`, now the misses only.

Each stack uses the cache its framework provides. On Quarkus, `quarkus-cache` is Caffeine behind annotations. `@CacheResult` on the single-key read caches the item, and `@CacheKey` leaves the request id out of the key. The bulk read takes the keys itself, because an annotation caches one call per distinct argument and a bulk call takes many. It asks the cache for each key with `getIfPresent`, calls the owner once for the misses, and `put`s what it gets. On Python, `cachetools.TTLCache` is a mapping with an expiry, and the same split is a few lines around it.

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

The effect on DataLoader batching's fan-out is visible in the counts. The first run of the four-cargo query makes the same 6 calls on Python and 8 on Quarkus, with fewer keys in them. A second run inside the TTL makes 3 on Python and 4 on Quarkus: the booking page, the cargos and the itineraries, which no cache holds. The voyage, location and handling calls are gone. The two cached kinds do not behave the same way. Voyages and locations are static for the lifetime of the process, while handling events change when a write lands.

**Where the stacks differ.** On Quarkus, `@CacheResult` stores the result for an unknown key as well, so a second read of an unknown voyage makes no call: the single-key path remembers "unknown" for the TTL, which is negative caching. The bulk path, and Python, store only found values. A production service chooses whether a missing voyage may be remembered.

## Invalidating on write

A TTL alone answers "how stale" with a number, and that number is wrong for a user who has just registered an event and reads it back. `registerHandlingEvent` returns a payload with the cargo's new `delivery.transportStatus`. If the handling cache still held the old event list, the payload would say `ONBOARD_CARRIER` for the event it had just recorded.

The fix is to evict the cargo's entry after the append succeeds and before the payload reads the cargo. Figure 16.4 shows the sequence the example's case asserts.

{% include excalidraw.html file="16-invalidation-on-write" alt="Six boxes in a loop of two rows. Step one reads the delivery of cargo ABC123, finds handling-events ABC123 empty, makes one listEventsFor call and returns ONBOARD_CARRIER. Step two reads it again, finds the entry and makes zero handling calls. Step three registers an UNLOAD at DEHAM on V100S with one appendEvent call that returns evt_10. Step four, highlighted, evicts the entry for ABC123 after the append and before the payload reads the cargo. Step five, highlighted, reads the payload's delivery, finds the entry missing, makes one listEventsFor call that refills it and returns IN_PORT. Step six reads the cargo again, finds the entry and makes zero handling calls, returning IN_PORT. Notes say that without step four the payload would answer ONBOARD_CARRIER and that the TTL bounds staleness from writers that never call this service." caption="Figure 16.4: Invalidation on write: the entry is evicted after the append and before the payload re-reads, so the payload and every later read agree." %}

The eviction is one call in each stack. On Quarkus it is `@CacheInvalidate(cacheName = "handling-events")` on a method of `HandlingSource`, which `HandlingRegistration` chains between the append and the cargo read. On Python it is `self.cache.pop(tracking_id, None)`, called in `registration.py` at the same point. The cargo's next `delivery` read misses, makes one `listEventsFor` call for `ABC123`, and refills the entry, so the read after that makes no call.

The ordering is the whole design. Evicting before the append would let a concurrent reader refill the entry with the old list. Evicting after the payload read would hand the payload the old list. Even in the right order, a reader that started before the write and finishes after the eviction can store the old list again. That race is rare and bounded, and it is the first reason for the next section.

## Expiry as the backstop

Eviction on write covers the writers this service knows about. It does not cover a batch import into the handling service, or a second API that writes to the same store. Both change the system of record and neither calls `evict`. The TTL is what bounds how long a copy can disagree with it, and it also bounds the race above.

A TTL is a choice about harm. Reference data changes rarely and does little damage when it is a few minutes behind, so 300 seconds is cheap. A cargo's events matter to the person looking at the cargo, so the example's production default is 60 seconds, and the lab's 20 seconds exists so the chapter can show the entry expiring: the expiry case reads a cargo, sleeps 21 seconds, reads it again, and sees one `handling.listEventsFor` call for the key. A deployment sets these numbers from the business, and the same data can have a short TTL in one service and a long one in another.

## What changes with replicas

Everything above lives in the process that owns it. With one replica per stack that is enough. With several, each replica holds its own copy: a write that lands on replica A evicts A's entry, and replica B keeps serving the old list until its TTL passes. The edge has the same property, one cache per nginx.

There are two ways out. A shared cache, such as Valkey, the BSD-licensed fork of Redis that the Linux Foundation hosts, holds one copy for every replica and moves the eviction to a place all of them see. Or each replica keeps its own cache, and a write publishes an eviction on a channel that every replica subscribes to. Both add a moving part and a network hop to every read. The example runs neither, because a single replica has nothing to share. The Docker Compose and Kubernetes deployments later in the book run replicas, and the choice is made there.

## Why not cache whole responses in the server

The server could also keep complete responses, keyed by document, variables and caller. The chapter does not build it, for three reasons.

- **The key is large.** It needs the document or its hash, the variables, the operation name and the identity of the caller, and a GraphQL server has no URL to lean on.
- **Invalidation cannot see inside.** A stored response is a blob. When a handling event is registered, the server cannot tell which stored responses contain that cargo without parsing every one.
- **The edge already does it for public reads.** Responses that every caller may share are exactly the ones the edge stores, keyed by a URL that already exists. Responses that depend on the caller are the ones a server cache would have to key by identity, and that is a cache with one entry per caller.

The opening REST-to-GraphQL comparison mentioned response-level caching inside the server as an option. This chapter's answer is that the response level belongs at the edge for public data, and that the server caches fields, where the keys are small and an event can name what to remove.

## Identity belongs in the key

Every cache above holds data that is the same for every caller. Reference data is. A cargo's event list is reached only after the booking source has returned the cargo, so a caller who may not see the cargo never reaches its entry. That is why none of the example's keys contain an identity. The rule for anything else is simple: a stored value that varies by caller needs the caller in its key, or must not be stored. Authentication and authorization introduce the identity and the ownership rule that sit under these caches, and they rely on the rule this chapter's edge applies: bypass shared caches for any request that carries `Authorization`.

## On the wire

Every value below is asserted by `verify.sh` on both stacks. Direct ports are 8260 (Quarkus) and 8261 (Python); the edge is 8262 and 8263. The `H` below is the hash of the `PortName` document in the example's manifest.

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

The two `GET`s print `Cache-Control: public, max-age=300` with `X-Cache-Status: MISS`, then `HIT`. The bearer request prints `Cache-Control: no-store` and `X-Cache-Status: BYPASS`. The cases run in a fixed order, because the earlier ones warm the keys the later counts expect.

| Check | Quarkus | Python |
|---|---|---|
| edge, first GET | `public, max-age=300`, `MISS`, `New York`; one call, `location.getLocation:USNYC` | the same |
| edge, second GET | `HIT`, `public, max-age=300`, the same body, 0 source calls | the same |
| edge, `Vary: Accept` | a `*/*` GET, then `Accept: application/json` for the same URL: `MISS` with `Content-Type: application/json`, then `HIT` | the same, with `Accept: application/graphql-response+json` first, because `*/*` gets the IDE page |
| single-key voyage twice | first `voyage.getVoyage:V200E`; second 0 `voyage` calls | the same |
| four-cargo query, run 1 | 8 calls; `voyage.getVoyages` `V100S+V300A` | 6 calls; `voyage.getVoyages` `V100S+V300A` |
| four-cargo query, run 2 | 4 calls, none to `voyage`, `location`, `handling` | 3 calls, the same exclusions |
| `Cache-Control`, direct | GET `PortName`: `public, max-age=300`; the same by POST, a `TrackCargo` GET, an error GET, a GET with `Authorization`, an unknown hash: `no-store` | the same |
| edge, never stored | `TrackCargo` twice, an error twice, an unknown hash twice: never `HIT`; 2 `booking.getCargo` calls | the same |
| edge, bypass | `BYPASS`, `no-store`, the same data | the same |
| expiry | read, `sleep 21`, read: one `handling.listEventsFor:XYZ789` call | the same |
| invalidation | second read 0 `handling` calls; mutation `evt_10`, `IN_PORT`, one `listEventsFor:ABC123`; next read `IN_PORT`, 0 calls | the same |

`bash examples/16-caching/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Caching is where the decision framework's <em>caching needs</em> axis gets its answer, and each layer answers it differently. Public reference data goes to the edge through persisted <code>GET</code>s with an explicit <code>Cache-Control</code>. Source reads go to field caches with a TTL and an eviction on write. Anything that depends on the caller stays out of shared caches. The <em>operational and security cost</em> axis is the price: every cache is derived data whose staleness is a decision, and the identity of the caller must be in every key or out of every store. The <em>aggregation across sources</em> axis sets the payoff, because the loaders' batched calls become even fewer when the cache answers part of the batch. The tracking view therefore caches reference data for 300 seconds at both the edge and the server, caches handling events briefly and evicts them on every registration, never stores a response for a request that carries <code>Authorization</code>, and runs no shared cache until there are replicas to share one.</p></div>

## Review

- Four cache layers hold an answer, each with its own key and its own eviction: client normalized cache, HTTP edge, server field caches, and the sources of record.
- A `Cache-Control` decision runs per response from a four-test policy (`GET`, no errors, reference-only data, no `Authorization`), issuing `public, max-age=300` or `no-store`.
- An nginx edge caches persisted `GET`s by method and URL, keyed to the upstream origin, and bypasses the cache on any `Authorization` header.
- Field-level caches (`@CacheResult`/`@CacheInvalidate` on Quarkus, `cachetools.TTLCache` on Python) sit under the DataLoader loaders and cut source calls on a cache hit.
- `registerHandlingEvent` evicts a cargo's handling-events entry after the append and before the payload reads the cargo, so the mutation response and every later read agree.
- Identity never enters a shared cache key: reference data is cached because it is the same for every caller, and anything that varies by caller stays out of shared caches or carries `no-store`.

## Where this goes next

This chapter put answers where they are cheapest to reuse. It named four layers, made persisted `GET`s cacheable with a `Cache-Control` decided per response, ran an nginx edge that bypasses on `Authorization`, cached source reads with a TTL under the DataLoader loaders, and evicted on `registerHandlingEvent` so the payload stays fresh. It left a shared cache for the replica chapters.

Transport security and introspection control come next: the same service runs over TLS with certificates generated at run time, a public endpoint separates from an internal one, and introspection and field suggestions turn off where a public client could read them. Authentication and authorization then add the caller: tokens from Keycloak, ownership checks in the booking source, and the first responses that must never reach a shared cache.

For HTTP caching, read RFC 9111, "HTTP Caching", especially the sections "Storing Responses in Caches" and "Cache-Control", and the section "Safe Methods" of RFC 9110, "HTTP Semantics", for why `GET` is the method a cache may reuse. For the data-systems frame, read *Designing Data-Intensive Applications*, 2nd edition, on systems of record and derived data, and the chapter "Optimizing data fetching" in Samer Buna's *GraphQL in Action*. The implementations are in the nginx [`ngx_http_proxy_module`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html) reference (the `proxy_cache` directives), the Quarkus [Application data caching](https://quarkus.io/guides/cache) guide, and the [cachetools](https://cachetools.readthedocs.io/) documentation. For contrast, Apollo's documentation on caching describes the `@cacheControl` directive this chapter does not adopt, and the [Valkey](https://valkey.io/) project is the shared cache named above.

## For deeper coverage

- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd edition (O'Reilly): systems of record versus derived data, the frame this chapter's four layers all answer to.
- Samer Buna, *GraphQL in Action* (Manning, 2021), chapter "Optimizing data fetching": the field-level caching this chapter implements under the loaders.
- Cloud Native Design Patterns, chapter "Appendix L: Caching": the general cache-layer and invalidation patterns this chapter applies to GraphQL specifically.
- RFC 9111, "HTTP Caching": `Cache-Control`, `Storing Responses in Caches`, and the rules the nginx edge enforces.
- [nginx `ngx_http_proxy_module` reference](https://nginx.org/en/docs/http/ngx_http_proxy_module.html): the `proxy_cache`, `proxy_cache_bypass` and `proxy_no_cache` directives this chapter's edge configuration uses.
