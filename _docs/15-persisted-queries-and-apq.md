---
title: "Persisted queries and APQ"
order: 15
part: "Performance & Safety"
description: "Replacing query text with a SHA-256 hash: Apollo's APQ handshake, hashes that do not match their text, persisted queries over GET, trusted documents as an allowlist, and where each stack resolves the document."
duration: "13 min read"
---

## Learning objectives

By the end of this chapter you can:

- Walk a client through Apollo's three-step `persistedQuery` handshake and explain why the server recomputes `sha256Hash` instead of trusting the client's claim.
- Serve a persisted query over `GET` with the hash and variables in the URL, while keeping a mutation off `GET` with a `405`/`400` refusal.
- Contrast APQ's open registration with trusted documents' build-time manifest, and state which one functions as an allowlist.
- Bound a persisted-document store (Caffeine, `LRUCache`) and reason about what an eviction costs a client versus what it protects the server from.
- Wire the hash-to-text resolution seam on each stack: a Vert.x route in front of SmallRye, a `SchemaExtension` inside Strawberry.

## Why this matters

A query that no longer costs extra source calls still costs something on every request: the client sends the whole text, the server hashes it, finds it in a cache or parses and validates it, and only then executes. A `POST` to one URL also can't be cached by anything between the client and the server, and the `GET` form that could be cached needs a URL that carries a document. Replacing the document with its hash fixes both.

Four services run in `examples/15-persisted-queries/`: an APQ instance and a trusted instance per stack. The depth and cost limits are left out so the protocol shows alone; a production service carries both.

## Sending the same text every time

Variables make a query a constant: the text stays fixed, the inputs change, and a server can cache the parse. Parsing and validating needs only the document and the schema, and it costs CPU on every request that arrives with text the server has already seen.

The bytes matter too. The `CargoDetail` operation, a cargo with its itinerary, seven events and three fragments, is 580 characters, and a 624-byte request body with its variables. The same request by hash is 163 bytes. The difference grows with the document, since clients ship documents of several kilobytes when fragments from many components add up. A small document gains little: the four-cargo page is 191 bytes as plain text and 132 as a hash, because the `extensions` wrapper is most of what remains.

A hash buys three things, each with its own price:

| Gain | Price |
|---|---|
| **Bytes on the wire.** The client sends 64 hexadecimal characters instead of the document. | A registration round trip the first time the server hasn't seen the hash. |
| **A URL a cache can key.** The hash fits in a `GET` URL with the variables, so a cache or CDN can store the response. | `GET` carries only queries, and every part of the URL is visible in logs. |
| **An allowlist.** If the server accepts only hashes it already knows, text it hasn't been given can't run. | A deploy step: documents must reach the server before the client that sends them. |

The first two come from Automatic Persisted Queries (APQ), Apollo's protocol. The third is a different arrangement of the same hash, called trusted documents.

## The APQ handshake

The protocol has one extension, `extensions.persistedQuery`, with two fields: `version`, which is 1, and `sha256Hash`, the lowercase hexadecimal SHA-256 of the exact query text. A client walks three cases in order the first time it sends a document.

{% include excalidraw.html file="15-apq-handshake" alt="Three horizontal lanes show three round trips. In the first, a client POST of 163 bytes carries variables and a sha256Hash; the server looks the hash up and finds nothing, and answers 200 with PersistedQueryNotFound in 99 bytes and no data. In the second, a POST of 756 bytes carries the text, variables and the hash; the server recomputes the hash, finds a match, stores the text and executes, and answers 200 with 2,412 bytes of data. In the third, a GET with a 204-byte URL and no body carries the variables and the hash; the server finds the stored text, executes as if the text had been sent, and answers 200 with the same 2,412 bytes. A note says the plain POST of the same document and variables is 624 bytes." caption="Figure 15.1: The APQ handshake for one document: a miss, a registration, and a hit by GET. The counts are request-body and response-body bytes measured with curl on the Quarkus instance." %}

1. **The client sends the hash alone.** The server has never seen it, so it answers with an error whose code is `PERSISTED_QUERY_NOT_FOUND` and whose message is `PersistedQueryNotFound`. Both stacks answer `200` with no `data` (Strawberry writes `"data": null`), and no source is called.
2. **The client repeats the request with the hash and the text.** The server recomputes the hash of the text. If it matches, the server stores the text under the hash and executes the operation.
3. **From then on the hash alone is enough.** The server finds the text and executes it, and the source calls match the full request's, key for key.

The server never trusts the hash it receives. It computes `sha256(text)` itself when text arrives.

## Hashes that do not match

A client could send the hash of one document with the text of another. If the server stored the pair as sent, the next client to ask for that hash would run the wrong document, and a request that looks like a cache hit for a harmless query would execute something else. So the server recomputes the hash and refuses a mismatch. Both stacks answer with the same error, carry no data, call no source and store nothing:

```json
{"errors":[{"message":"provided sha does not match query","extensions":{"code":"BAD_USER_INPUT"}}]}
```

Python adds `"data": null`, as for every request error.

## Over GET

A hash makes the `GET` form practical. The request has no body: the variables and the extensions travel in the URL, each as URL-encoded JSON.

```bash
curl -G localhost:8250/graphql -H 'Accept: application/json' \
  --data-urlencode 'variables={"id":"ABC123"}' \
  --data-urlencode 'extensions={"persistedQuery":{"version":1,"sha256Hash":"<TrackCargo hash>"}}'
```

The parameter names are GraphQL-over-HTTP's. Leaving out `query` is not, because the specification requires it on `GET`; the hash-only form is Apollo's convention, and the persisted-documents proposal is not in the current draft. Apollo's own client sends hashed queries as `GET` when configured to and keeps mutations and full-text requests on `POST`.

Three details matter when something else sits in front of the server:

- **Quarkus turns `GET` on in configuration:** `quarkus.smallrye-graphql.http.get.enabled=true`.
- **Strawberry answers a `GET` by its `Accept` header.** A `GET` with no `query` parameter is treated as a browser asking for GraphiQL when `Accept` includes `text/html` or `*/*`, and Strawberry answers `200 text/html` with the IDE. A hash-only request has no `query` parameter by design, so the client must send `Accept: application/json`. Apollo Client 4 sends `application/graphql-response+json,application/json;q=0.9`, which passes. Apollo Client 3 sends `*/*`, and a bare `curl` does too, so both get the IDE. Quarkus answers `*/*` with JSON and `Accept: text/html` with `406`. When a cached persisted `GET` returns something other than JSON, check `Accept` first.
- **`operationName` on `GET`.** An empty `operationName` is treated as absent. A non-empty one must name an operation in the document, or the Quarkus route answers `400` with `BAD_USER_INPUT`. For a single-operation document the route hands the request on without `operationName`, so a GET by hash that carries its name still works.

### A mutation stays off GET

A mutation received over `GET` must be refused with a 4xx status and must not run. The GraphQL-over-HTTP specification recommends `405 Method Not Allowed` with an `Allow` header. A `GET` can be triggered by a link, an image tag or a prefetching browser, and a write behind it would need no cooperation from the user.

Strawberry answers `400` with the plain text `mutations are not allowed when using GET`. On Quarkus the persisted-document route applies the rule to every `GET` before it hands the request on, for persisted and plain text alike: it refuses a `GET` whose selected operation is not a query with `405`, `Allow: POST` and the same text. Neither stack writes anything.

## APQ is not an allowlist

Read the handshake as an attacker would. Step 2 accepts any text that matches its own hash, and anyone can compute a SHA-256. APQ lets any client register any document, and the hash does nothing to limit what runs. It is a bandwidth and caching tool. It is also a way to fill the server's store: a client that registers documents without end forces the server to keep them, or to evict the ones other clients rely on.

Bound the store. Both stacks keep 1,000 documents: Caffeine through `quarkus.cache.caffeine."persisted-documents".maximum-size=1000` on Quarkus, and `cachetools.LRUCache(maxsize=1000)` on Python. Register 1,100 distinct documents on each APQ instance and ask for all of them by hash, and exactly 1,000 resolve. On Python, which evicts the least recently used, the 100 that don't are the first 100 registered. Caffeine's admission policy is Window TinyLFU, not LRU, so only the count is predictable on Quarkus. An evicted hash isn't an outage: the client treats it like a first request and sends the text again. It is a cost, and an attacker who can register documents can force it on everyone.

{% include excalidraw.html file="15-apq-vs-trusted" alt="Two columns compare the modes in four rows. In APQ mode, any client registers a document by sending the hash with the text, the server accepts any text that matches its own hash, an attacker can register any text and fill the bounded store, and caches see short GET URLs once registered. In trusted mode, the build pipeline registers documents from the client's manifest, the server accepts manifest documents by hash or by exact text and answers PERSISTED_QUERY_REQUIRED for other text, an attacker can run nothing new and nothing is stored, and caches see short GET URLs with no registration miss. The attacker row is highlighted in both columns." caption="Figure 15.2: APQ and trusted documents compare on who registers, what the server accepts, what an attacker can do and what a cache sees." %}

### Trusted documents

Trusted documents move registration to the build. The client's build extracts its operations, computes their hashes and publishes a manifest, and the server loads the manifest at start. The server then treats the manifest as the whole truth: it runs documents it lists, by hash or by exact text, and refuses everything else. The Security page on graphql.org describes the idea under "Trusted documents" and states the limit: it works when you control the clients, and it can't protect a public API whose operations aren't known in advance.

The manifest, `persisted-documents.json`, uses Apollo's persisted-query manifest format: an `operations` list of `id` (the SHA-256), `name`, `type` and `body`. It holds `TrackCargo`, `PortName` and `RegisterHandling`. The trusted services mount it read-only and read it once at start. They behave as follows (ports 8252 and 8253):

- `PortName` by hash, never registered, returns `Rotterdam`, by `POST` and by `GET`. The manifest is the store.
- The text of `PortName` without a hash is accepted, because its hash is in the manifest.
- `{ __typename }`, with or without its hash, answers `PERSISTED_QUERY_REQUIRED` with `only persisted documents are accepted`, no data and no source call. A registration attempt is refused, not stored.
- An unknown hash is `PERSISTED_QUERY_NOT_FOUND`, including a hash another instance registered at run time.
- Introspection is refused like any other text the manifest doesn't hold, so contract checks run against the APQ instances.
- A mutation in the manifest runs by hash over `POST`: `RegisterHandling` registers `evt_10`.
- Text sent another way is held to the same rule. A `query` URL parameter on a `POST` or `GET` doesn't replace the document, and on Quarkus an `application/graphql` body is checked like a JSON `query` while any other body type gets `400`. The route also refuses any request on `/graphql` that carries an `Upgrade` header with `400` in both modes, because only HTTP is served here.

A client that can't register has no registration miss, so a cold cache sees the same short URL as a warm one. That is what favors trusted mode for caching.

## Where the document is resolved

Both stacks turn a hash into text before the engine looks for it.

On **Strawberry**, the HTTP layer accepts a request whose `query` is null and passes `extensions` on in the execution context. `SchemaExtension.on_operation` runs before Strawberry looks for the text, so the extension sets `execution_context.query` and the request proceeds as if the client had sent it. An `ExposedError` raised before the `yield` ends the operation with a request error.

On **Quarkus**, a Vert.x route registered ahead of SmallRye's reads the hash, resolves the text, and re-enters SmallRye with `rc.reroute(...)`, passing the text as a `query` URL parameter. SmallRye reads URL parameters for `GET` when `http.get.enabled` is on, and merges them over the body for `POST` when `http.post.queryparameters.enabled` is on. The route doesn't touch Vert.x internals.

{% include excalidraw.html file="15-persisted-document-seam" alt="Two lanes show the path of a hash-only request through each stack. In the Quarkus lane, a Vert.x route at order minus ten reads extensions.persistedQuery.sha256Hash, resolves the hash from the manifest and then the quarkus-cache store, checks on a GET that the selected operation is a query, and reroutes to slash graphql with the text as a query parameter. SmallRye's route then sees a query, the extensions having been read before it, and parses, validates and executes, with the parsed document cached by text. In the Python lane, the GraphQLRouter view accepts a null query and passes extensions on, the PersistedQueries extension's on_operation sets execution_context.query from the hash, Strawberry finds the query set, ParserCache and ValidationCache reuse the parse and validation of text seen before, and the operation executes, with the check for GET applied there. The steps that implement Apollo's protocol are highlighted." caption="Figure 15.3: Where a persisted document is resolved: a Vert.x route in front of SmallRye on Quarkus, an extension inside Strawberry on Python." %}

{% include codetabs.html langs="Quarkus|Python" %}

```java
    void init(@Observes Router router) {
        router.route("/graphql").order(-100).handler(PersistedDocumentRoute::refuseUpgrade);
        router.route(HttpMethod.POST, "/graphql").order(-10).handler(BodyHandler.create(false));
        router.route("/graphql").order(-10).handler(this::resolve);
    }

        // ... the request has a hash and no text:
        String known = manifest.get(hash);
        if (known == null && !trusted) {
            CompletableFuture<Object> stored = documents.as(CaffeineCache.class).getIfPresent(hash);
            known = stored == null ? null : (String) stored.getNow(null);
        }
        if (known == null) {
            refuse(rc, "PERSISTED_QUERY_NOT_FOUND", "PersistedQueryNotFound");
            return;
        }
        proceed(rc, known, true);
```

```python
    def resolve(self, query: str | None, extensions: dict[str, Any] | None) -> str | None:
        """The query text to execute, or an ExposedError that refuses the request."""
        persisted = (extensions or {}).get("persistedQuery")
        digest = persisted.get("sha256Hash") if isinstance(persisted, dict) else None

        if digest is None:
            if self.trusted and query is not None and sha256_hex(query) not in self.manifest:
                raise PersistedQueryRequired
            return query

        if query is None:
            found = self.lookup(digest)
            if found is None:
                raise PersistedQueryNotFound
            return found

        # The server recomputes the hash: a client-supplied one is a claim, not a key.
        if sha256_hex(query) != digest:
            raise BadUserInput("provided sha does not match query")
        if self.trusted:
            if digest not in self.manifest:
                raise PersistedQueryRequired
        else:
            self.store[digest] = query
        return query


class PersistedQueries(SchemaExtension):
    """Resolve ``extensions.persistedQuery`` before Strawberry looks for the query.

    Raising before the ``yield`` ends the operation with a request error and no
    data. The exception is an ``ExposedError``, so its message and code reach
    the client.
    """

    def __init__(self, *, documents: PersistedDocuments) -> None:
        super().__init__()
        self.documents = documents

    def on_operation(self) -> Iterator[None]:
        context = self.execution_context
        context.query = self.documents.resolve(context.query, context.operation_extensions)
        yield
```

On Quarkus the wiring is configuration, with `PersistedDocumentRoute` discovered as an ordinary bean. On Python it is two entries in the schema's extension list, written as factories so each request gets its own extension instance:

{% include codetabs.html langs="Quarkus|Python" %}

```properties
quarkus.smallrye-graphql.http.get.enabled=true
quarkus.smallrye-graphql.http.post.queryparameters.enabled=true
quarkus.cache.caffeine."persisted-documents".maximum-size=1000
```

```python
schema = strawberry.Schema(
    query=Query,
    mutation=Mutation,
    config=StrawberryConfig(scalar_map=SCALAR_MAP),
    extensions=[
        partial(MaskErrors, should_mask_error=should_mask, error_message="Internal server error."),
        partial(PersistedQueries, documents=documents),
        ParserCache,
        ValidationCache,
    ],
)
```

Three decisions in the Quarkus route keep the checked text and the executed text the same:

- **Re-entry is marked in the request context, not by the URL.** A client controls the URL, so a `query` parameter can't mark a request as re-entered. The route sets a flag on the `RoutingContext` before it reroutes and trusts only that. A `query` parameter on a first-hand request is treated as the text and goes through the same checks.
- **The text is the URL parameter if present, otherwise the body's.** That follows SmallRye's own precedence, so the route checks the document that would run.
- **A `GET` is parsed before it is passed on.** The mutation guard needs the operation type of the selected operation, which graphql-java's `Parser` gives for the cost of a parse. A document that doesn't parse gets `400`, and the route sends on exactly the checked text on `GET` and on `POST`.

## Storing documents

Each stack keeps its documents in a bounded store, and each engine also keeps a second cache that the store can be mistaken for.

| Cache | Maps | On eviction | Quarkus | Python |
|---|---|---|---|---|
| Store | hash to text; APQ fills it, trusted mode never writes it | the handshake repeats: one round trip | `quarkus-cache` named `persisted-documents` (Caffeine) | `LRUCache` in `PersistedDocuments`, beside the manifest |
| Parse caches | text to parsed, validated document; exist with or without persisted queries | CPU on the server, nothing on the wire | SmallRye's `QueryCache`, through graphql-java's `PreparsedDocumentProvider` ("Query Caching" in the execution documentation) | `ParserCache` and `ValidationCache` extensions, 128 entries each by default, passed as classes so each request gets its own instance |

The parse caches matter more with persisted queries, because the hash makes every request for a document identical text: the second request for a document pays neither parsing nor validation.

## Persisted documents and limits

Query cost analysis bounds what one document may do. A persisted document doesn't change that analysis, and the two controls cover different attackers.

In **trusted mode** the limits become a backstop. Every document that can run was written and reviewed by your developers, so the attacks the depth and cost limits reject can't arrive as new text. A mistake in one of your own documents can still be expensive, and the limits catch it. In **APQ mode** the limits are as necessary as before: anyone can register a document that floods a query with aliases, and the hash doesn't make it cheaper.

## Operating them

A manifest is a deployment artifact with its own order of operations.

- **The manifest deploys before the client.** A client that sends a hash the server doesn't yet hold gets `PersistedQueryNotFound`. In APQ mode it recovers by sending the text. In trusted mode there's no recovery, so the new manifest must be live before the build that uses it.
- **Never remove a hash a live client sends.** Old mobile and web builds stay in use for months. Retire a document only when telemetry says no client sends it.
- **Give every document an operation name.** The log or trace of a request by hash would otherwise carry only 64 characters of hex. A persisted document is the one place a name is guaranteed to exist.
- **Treat the hash as part of the contract.** Any change to the text, even whitespace, changes the hash. Generate the manifest from the source and never edit a body by hand.

| Decide | Rule |
|---|---|
| Clients you control (your own web and mobile builds) | Trusted documents, mutations on `POST` |
| Clients you can't enumerate | APQ with a bounded store, paired with depth and cost limits |
| Cacheable reads | A hash-only `GET` with `Accept: application/json` |

> **Decision**
>
> Persisted documents answer two axes at once. Caching needs get a short, stable `GET` URL an intermediary can key; operational and security cost gets fewer bytes and less parsing (APQ) or an allowlist (trusted documents). The price falls on the contract and evolution axis: a hash is part of the contract between a client build and a server, so manifests deploy before clients and live hashes are never removed. Run trusted documents for clients whose operations are known at build time, APQ with depth and cost limits only where clients can't be enumerated, and keep mutations on `POST`.

> **🤖 Explore with your agent**
>
> "In examples/15-persisted-queries, take the three operations in persisted-documents.json (TrackCargo, PortName, RegisterHandling) and say which of them the trusted instances on ports 8252 (Quarkus) and 8253 (Python) may run by hash over GET under the rule that a mutation never runs over GET. Then send each by hash over GET with curl and report the status code and body from both stacks."
>
> Check: PortName and TrackCargo return data on both stacks; RegisterHandling returns 405 with `Allow: POST` on Quarkus and 400 on Python, both with `mutations are not allowed when using GET`, and no `evt_10` is written.

## Build, run, observe

```bash
docker compose -f examples/15-persisted-queries/compose.yaml up -d --build
H=$(printf '%s' '{ cargo(trackingId: "ABC123") { trackingId } }' | sha256sum | cut -d' ' -f1)
# 1. hash only: PersistedQueryNotFound
curl -s localhost:8250/graphql -H 'Content-Type: application/json' \
  -d "{\"extensions\":{\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}}"
# 2. hash and text: stored and executed
curl -s localhost:8250/graphql -H 'Content-Type: application/json' \
  -d "{\"query\":\"{ cargo(trackingId: \\\"ABC123\\\") { trackingId } }\",\"extensions\":{\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}}"
# 3. hash only, by GET
curl -s -G localhost:8250/graphql -H 'Accept: application/json' \
  --data-urlencode "extensions={\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H\"}}"
docker compose -f examples/15-persisted-queries/compose.yaml down -v
```

APQ instances answer on 8250 (Quarkus) and 8251 (Python); trusted instances on 8252 and 8253. Run `bash examples/15-persisted-queries/verify.sh` for the whole sequence on both stacks; it prints `PASS` only when both hold.

| Check | Quarkus | Python |
|---|---|---|
| manifest | each `id` equals `sha256(body)` | the same |
| hash only | 200, no `data`; `PersistedQueryNotFound`, `PERSISTED_QUERY_NOT_FOUND`; 0 calls | the same, with `"data": null` |
| hash and text | `ABC123`, `ONBOARD_CARRIER` | the same |
| `CargoDetail` request size | 624 bytes with text, 163 by hash | the same |
| mismatch | `BAD_USER_INPUT`, `provided sha does not match query`; 0 calls | the same |
| GET by hash | 200, the same data | the same |
| GET by hash with `operationName` | 200, `ABC123` | the same |
| literal `%` and `+`, by text and by hash, over `GET` and `POST` | the source receives `A+B%41 C` unchanged | the same |
| GET mutation by hash, and as text | `405`, `Allow: POST`, `mutations are not allowed when using GET`; 0 `appendEvent` | `400`, the same text; 0 `appendEvent` |
| `GET`, `operationName` that matches nothing | `400`, `BAD_USER_INPUT`; with an empty name: `405` | `400`, no `data` |
| `GET`, a document that doesn't parse | `400`, 0 calls | a syntax error, 0 calls |
| mutation by hash over POST | `evt_10`, `IN_PORT`; the same key again returns `evt_10`, 0 `appendEvent` | the same |
| trusted, manifest hash | `Rotterdam` by POST and GET | the same |
| trusted, other text | `{ __typename }`, its hash with it, and introspection: `PERSISTED_QUERY_REQUIRED`; 0 calls | the same |
| trusted, `?query=` | `PERSISTED_QUERY_REQUIRED`; `application/graphql` body checked the same way | `?query=` the same; `application/graphql` is `400` |
| trusted, WebSocket upgrade | `400`, 0 calls | not tested |
| trusted, unknown hash | `PERSISTED_QUERY_NOT_FOUND`, including a hash registered on the APQ instance | the same |
| bounded store | 1,100 registered, exactly 1,000 resolve | the same; the 100 that don't are the first 100 registered |

Experiments:

- Change one character in the text of a hash-and-text request: both stacks answer `BAD_USER_INPUT` and the hash stays unknown.
- Send `RegisterHandling` by hash over `GET` to a trusted instance: Quarkus refuses with `405` and Python with `400`, and nothing is written.
- Send a hash-only `GET` to Strawberry with `Accept: */*` instead of `application/json`: it answers `200 text/html` with the IDE.
- Send `{ __typename }` to a trusted instance, with its own hash: it is refused with `PERSISTED_QUERY_REQUIRED`, and the same hash alone is still unknown afterward.

## For deeper coverage

- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022): end-to-end clients, pagination and the manifest-style thinking behind a build-time document list.
- Samer Buna, *GraphQL in Action* (Manning, 2021): resolvers and data fetching, the execution path a persisted query still runs once resolved.
- Cloud Native Design Patterns, chapter "Appendix L: Caching": the general caching-by-key discipline that a hash-keyed `GET` URL plugs into.
- [Apollo Automatic Persisted Queries](https://www.apollographql.com/docs/apollo-server/performance/apq) and the [GraphOS persisted-queries manifest format](https://www.apollographql.com/docs/graphos/platform/security/persisted-queries#manifest-format): the protocol and the manifest implemented here.
- The "Trusted documents" section of the [Security](https://graphql.org/learn/security/) page on graphql.org: the allowlist model that contrasts with APQ.
- The "GET" section of the [GraphQL over HTTP](https://http-spec.graphql.org/draft/) specification.
- The "Query Caching" section of the graphql-java [execution documentation](https://www.graphql-java.com/documentation/execution); Strawberry's [schema extensions](https://strawberry.rocks/docs/guides/extensions), [ParserCache](https://strawberry.rocks/docs/extensions/parser-cache) and [ValidationCache](https://strawberry.rocks/docs/extensions/validation-cache); the Quarkus [HTTP reference](https://quarkus.io/guides/http-reference) and [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql).
