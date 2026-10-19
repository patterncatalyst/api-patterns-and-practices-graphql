---
title: "Persisted queries and APQ"
order: 15
part: "Performance & Safety"
description: "Replacing query text with a SHA-256 hash: Apollo's three-step APQ handshake, hashes that do not match their text, persisted queries over GET and the mutation that must stay off it, trusted documents as an allowlist, and where each stack resolves the document: a Vert.x route in front of SmallRye, a SchemaExtension in Strawberry."
duration: "16 min read"
---

## Learning objectives

By the end of this chapter you can:

- Walk a client through Apollo's three-step `persistedQuery` handshake and explain why the server recomputes `sha256Hash` instead of trusting the client's claim.
- Serve a persisted query over `GET` with the hash and variables in the URL, while keeping a mutation off `GET` with a `405`/`400` refusal.
- Contrast APQ's open registration with trusted documents' build-time manifest, and state which one functions as an allowlist.
- Bound a persisted-document store (Caffeine, `LRUCache`) and reason about what an eviction costs a client versus what it protects the server from.
- Wire the hash-to-text resolution seam on each stack: a Vert.x route in front of SmallRye, a `SchemaExtension` inside Strawberry.

## Why this matters

Chapter 13 ended with a query that had stopped costing source calls. It still costs something on every request: the client sends the whole text, the server hashes it, finds it in a cache or parses and validates it, and only then executes. Chapter 1 pointed at the other side of the same cost. A `POST` to one URL cannot be cached by anything between the client and the server, and the `GET` form that could be cached needs a URL that carries a document. This chapter replaces the document with its hash.

The code is in `examples/15-persisted-queries/`. It starts from the Chapter 13 example, so the schema, the seed and the error contract are unchanged, and adds the protocol in front of each engine. Four services run: an APQ instance and a trusted instance per stack, from one image each. The chapter does not repeat Chapter 14's limits, and a production service would carry both.

## Sending the same text every time

Chapter 1 described variables as the reason a query can be a constant: the text stays fixed, the inputs change, and a server can cache the parse. Chapter 6 priced what the server does with that text. Parsing and validating a document needs only the document and the schema, and it costs CPU on every request that arrives with text the server has already seen.

The bytes matter too. The example's `CargoDetail` operation, a cargo with its itinerary, seven events and three fragments, is 580 characters. Sent with its variables it is a 624-byte request body. The same request by hash is 163 bytes, and the difference grows with the document: clients ship documents of several kilobytes because fragments from many components add up. A small document gains little. Chapter 13's four-cargo page is 191 bytes as plain text and 132 as a hash, because the `extensions` wrapper is most of what remains.

A hash buys three things, each with its own price:

- **Bytes on the wire.** The client sends 64 hexadecimal characters instead of the document. The price is a registration round trip the first time the server has not seen the hash.
- **A URL a cache can key.** The hash fits in a `GET` URL with the variables, so a cache or a CDN can store the response. The price is that `GET` carries only queries, and that every part of the URL is visible in logs.
- **An allowlist.** If the server accepts only hashes it already knows, text it has not been given cannot run at all. The price is a deploy step: the documents must reach the server before the client that sends them.

The first two come from Automatic Persisted Queries, Apollo's protocol. The third is a different arrangement of the same hash, called trusted documents, and the chapter treats them as two modes because they answer different questions.

## The APQ handshake

The protocol has one extension, `extensions.persistedQuery`, with two fields: `version`, which is 1, and `sha256Hash`, the lowercase hexadecimal SHA-256 of the exact query text. The server's behaviour has three cases, and a client walks through them in order the first time it sends a document.

Figure 15.1 follows `CargoDetail` through them on the Quarkus instance, with the byte counts curl measured.

{% include excalidraw.html file="15-apq-handshake" alt="Three horizontal lanes show three round trips. In the first, a client POST of 163 bytes carries variables and a sha256Hash; the server looks the hash up and finds nothing, and answers 200 with PersistedQueryNotFound in 99 bytes and no data. In the second, a POST of 756 bytes carries the text, variables and the hash; the server recomputes the hash, finds a match, stores the text and executes, and answers 200 with 2,412 bytes of data. In the third, a GET with a 204-byte URL and no body carries the variables and the hash; the server finds the stored text, executes as if the text had been sent, and answers 200 with the same 2,412 bytes. A note says the plain POST of the same document and variables is 624 bytes." caption="Figure 15.1 — The APQ handshake for one document: a miss, a registration, and a hit by GET. The counts are request-body and response-body bytes measured with curl on the Quarkus instance." %}

1. **The client sends the hash alone.** The server has never seen it, so it answers with an error whose code is `PERSISTED_QUERY_NOT_FOUND` and whose message is `PersistedQueryNotFound`. Both stacks answer `200` with no `data` (Strawberry writes `"data": null`), and no source is called.
2. **The client repeats the request with the hash and the text.** The server recomputes the hash of the text. If it matches, the server stores the text under the hash and executes the operation.
3. **From then on the hash alone is enough.** The server finds the text and executes it. The response is the one the full request would have produced, and `verify.sh` compares the source-call log of the hash-only request with the full one, key for key.

The server never trusts the hash it receives. It computes `sha256(text)` itself when text arrives, which is why the next case exists.

## Hashes that do not match

A client could send the hash of one document with the text of another. If the server stored the pair as sent, the next client to ask for that hash would run the wrong document, and a request that looks like a cache hit for a harmless query would execute something else. So the server recomputes the hash and refuses a mismatch. Both stacks answer with the same error:

```json
{"errors":[{"message":"provided sha does not match query","extensions":{"code":"BAD_USER_INPUT"}}]}
```

That is the code the example already uses for a value that passed coercion and is still unacceptable, and it carries no data and calls no source. Nothing is stored. Python adds `"data": null`, as for every request error.

## Over GET

A hash makes the `GET` form practical. The request has no body: the variables and the extensions travel in the URL, each as URL-encoded JSON.

```bash
curl -G localhost:8250/graphql -H 'Accept: application/json' \
  --data-urlencode 'variables={"id":"ABC123"}' \
  --data-urlencode 'extensions={"persistedQuery":{"version":1,"sha256Hash":"<TrackCargo hash>"}}'
```

The parameter names are GraphQL-over-HTTP's; leaving out `query` is not, because the specification requires it on `GET`. The hash-only form is Apollo's convention on top of the standard parameters, and the persisted-documents proposal is not in the current draft. Apollo's own client sends hashed queries as `GET` when configured to and keeps mutations and full-text requests on `POST`.

Three details of the example matter when something else sits in front of it.

**Quarkus turns `GET` on in configuration.** The example sets `quarkus.smallrye-graphql.http.get.enabled=true`, and the next section shows how a mutation stays off `GET`. **Strawberry answers a `GET` by its `Accept` header.** A `GET` with no `query` parameter is treated as a browser asking for GraphiQL when `Accept` includes `text/html` or `*/*`, and Strawberry answers `200 text/html` with the IDE. The hash-only request has no `query` parameter by design, so a client must send `Accept: application/json`. Apollo Client 4 sends `application/graphql-response+json,application/json;q=0.9`, which passes, and `verify.sh` sends `application/json`. Apollo Client 3 sends `*/*`, and a hash-only `GET` from it would get Strawberry's IDE. A bare `curl` sends `*/*` too and receives a page of HTML. Quarkus answers `*/*` with JSON and `Accept: text/html` with `406`. When a cached persisted `GET` returns something other than JSON, the `Accept` header is the first thing to check, and Chapter 16 returns to it.

**GET and `operationName`.** An empty `operationName` is treated as absent, and a non-empty one must name an operation in the document, or the Quarkus route answers `400` with `BAD_USER_INPUT`. For a single-operation document the operation is already determined, so the route hands the request on without `operationName`; a GET by hash that carries its name still works.

### A mutation stays off GET

Chapter 1 and Chapter 8 settled the rule: a mutation received over `GET` must be refused with a 4xx status and must not run. The specification's section "GET" recommends `405 Method Not Allowed` with an `Allow` header. A `GET` can be triggered by a link, an image tag or a prefetching browser, and a write behind it would need no cooperation from the user.

`verify.sh` registers `RegisterHandling` by `POST` with input that fails validation, and then sends the same hash by `GET`. Both stacks refuse it and write nothing. Strawberry answers `400` with the plain text `mutations are not allowed when using GET`.

On Quarkus the persisted-document route applies the rule to every `GET` before it hands the request on, for persisted and plain text alike: it refuses a `GET` whose selected operation is not a query with `405`, `Allow: POST` and the same text, and the source-call log shows no `appendEvent`.

## APQ is not an allowlist

Read the three handshake steps as an attacker would. Step 2 accepts any text that matches its own hash, and anyone can compute a SHA-256. APQ therefore lets any client register any document, and the hash does nothing to limit what runs. It is a bandwidth and caching tool. It is also a way to fill the server's store: a client that registers documents without end forces the server to keep them, or to evict the ones other clients rely on.

The example bounds the store. Both stacks keep 1,000 documents: Caffeine through `quarkus.cache.caffeine."persisted-documents".maximum-size=1000` on Quarkus, and `cachetools.LRUCache(maxsize=1000)` on Python. `verify.sh` registers 1,100 distinct documents on each APQ instance and then asks for all of them by hash. Exactly 1,000 resolve on both. On Python, which evicts the least recently used, the 100 that do not are the first 100 registered. Caffeine's admission policy is Window TinyLFU, not LRU, so the example asserts only the count on Quarkus. An unresolved hash answers `PersistedQueryNotFound`. An evicted hash is not an outage, because the client treats it like a first request and sends the text again. It is a cost, and an attacker who can register documents can force it on everyone.

Figure 15.2 sets the two modes side by side.

{% include excalidraw.html file="15-apq-vs-trusted" alt="Two columns compare the modes in four rows. In APQ mode, any client registers a document by sending the hash with the text, the server accepts any text that matches its own hash, an attacker can register any text and fill the bounded store, and caches see short GET URLs once registered. In trusted mode, the build pipeline registers documents from the client's manifest, the server accepts manifest documents by hash or by exact text and answers PERSISTED_QUERY_REQUIRED for other text, an attacker can run nothing new and nothing is stored, and caches see short GET URLs with no registration miss. The attacker row is highlighted in both columns." caption="Figure 15.2 — APQ and trusted documents compare on who registers, what the server accepts, what an attacker can do and what a cache sees." %}

### Trusted documents

Trusted documents move registration to the build. The client's build extracts its operations, computes their hashes and publishes a manifest, and the server loads the manifest at start. The server then treats the manifest as the whole truth: it runs documents it lists, by hash or by exact text, and it refuses everything else. The Security page on graphql.org describes the idea in its section "Trusted documents", and it states the limit: it works when you control the clients, and it cannot protect a public API whose operations are not known in advance.

The example's manifest, `persisted-documents.json`, uses Apollo's persisted-query manifest format: an `operations` list of `id` (the SHA-256), `name`, `type` and `body`. It holds three operations, `TrackCargo`, `PortName` and `RegisterHandling`, and `verify.sh` first checks that each `id` is the SHA-256 of its `body`. The two trusted services mount it read-only and read it once at start.

What the trusted instances do, as `verify.sh` asserts it on 8252 and 8253:

- `PortName` by hash, never registered, returns `Rotterdam`, by `POST` and by `GET`. The manifest is the store.
- The text of `PortName` without a hash is accepted, because its hash is in the manifest.
- `{ __typename }`, with or without its hash, answers `PERSISTED_QUERY_REQUIRED` with the message `only persisted documents are accepted`, no data and no source call. A registration attempt is refused, not stored: the same hash alone is still unknown afterwards.
- An unknown hash is `PERSISTED_QUERY_NOT_FOUND`, including a hash another instance registered at run time.
- `{ __schema { queryType { name } } }` is refused like any other text. Introspection is not special here: it is a document the manifest does not hold. The contract checks therefore run against the APQ instances, which allow introspection, and the README says so.
- A mutation in the manifest runs by hash over `POST`: `RegisterHandling` registers `evt_10`.
- Text sent another way is held to the same rule. A `query` URL parameter on a `POST` or a `GET` does not replace the document, and on Quarkus an `application/graphql` body is checked like a JSON `query` and any other body type gets `400`. Trusted mode covers every transport the endpoint serves. This example serves HTTP only, so the route refuses any request on `/graphql` that carries an `Upgrade` header with `400` in both modes; Chapter 21 covers WebSockets.

Figure 15.2's last row is the one that favours trusted mode for caching: a client that cannot register has no registration miss, so a cold cache sees the same short URL as a warm one.

## Where the document is resolved

Both stacks need a place to turn a hash into text before the engine looks for it. The example implements Apollo's protocol in a small piece of code on each stack.

On **Strawberry**, the HTTP layer accepts a request whose `query` is null and passes `extensions` on in the execution context, so an extension can supply the query. `SchemaExtension.on_operation` runs before Strawberry parses or looks for the text, so the extension sets `execution_context.query` and the rest of the request proceeds as if the client had sent it. An `ExposedError` raised before the `yield` ends the operation with a request error.

On **Quarkus**, the example resolves the hash one step earlier, in the HTTP router, before SmallRye sees the request.

A Vert.x route registered ahead of SmallRye's reads the hash, resolves the text, and re-enters SmallRye with `rc.reroute(...)`, passing the text as a `query` URL parameter. SmallRye accepts URL parameters when `http.post.queryparameters.enabled` is on, merging them over the body for `POST`, and reads them for `GET` when `http.get.enabled` is on. The route does not touch Vert.x internals. Figure 15.3 puts the two paths side by side.

{% include excalidraw.html file="15-persisted-document-seam" alt="Two lanes show the path of a hash-only request through each stack. In the Quarkus lane, a Vert.x route at order minus ten reads extensions.persistedQuery.sha256Hash, resolves the hash from the manifest and then the quarkus-cache store, checks on a GET that the selected operation is a query, and reroutes to slash graphql with the text as a query parameter. SmallRye's route then sees a query, the extensions having been read before it, and parses, validates and executes, with the parsed document cached by text. In the Python lane, the GraphQLRouter view accepts a null query and passes extensions on, the PersistedQueries extension's on_operation sets execution_context.query from the hash, Strawberry finds the query set, ParserCache and ValidationCache reuse the parse and validation of text seen before, and the operation executes, with the check for GET applied there. The steps that implement Apollo's protocol are highlighted." caption="Figure 15.3 — Where a persisted document is resolved: a Vert.x route in front of SmallRye on Quarkus, an extension inside Strawberry on Python." %}

Both are small, and they are the only pieces of protocol code in the chapter. The Quarkus tab shows the router registration and the branch that resolves a hash alone; the Python tab shows the resolver for every case and the extension that calls it:

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

The wiring is the only place the protocol touches anything else. On Quarkus it is configuration, with `PersistedDocumentRoute` discovered as an ordinary bean. On Python it is two entries in the schema's extension list, written as factories so that each request gets its own extension instance:

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

Three decisions in the Quarkus route keep the checked text and the executed text the same.

- **Re-entry is marked in the request context, not by the URL.** A client controls the URL, so a `query` parameter cannot be what marks a request as re-entered. The route sets a flag on the `RoutingContext` before it reroutes and trusts only that. A `query` parameter on a first-hand request is treated as the text, and goes through the same checks.
- **The text is the URL parameter if present, otherwise the body's.** That follows SmallRye's own precedence, so the route checks the document that would run.
- **A `GET` is parsed before it is passed on.** The guard in "A mutation stays off GET" needs the operation type of the selected operation, which graphql-java's `Parser` gives for the cost of a parse. A document that does not parse gets `400`, and the checked text is what the route sends on. The handler receives exactly the checked text on `GET` and on `POST`.

## Storing documents

Each stack keeps its documents in a bounded store, and each engine also keeps a second cache that the store can be mistaken for.

The **store** maps a hash to text. It is the thing APQ fills and trusted mode never writes. On Quarkus it is a `quarkus-cache` named `persisted-documents`, which is Caffeine with the size cap above. On Python it is an `LRUCache` inside `PersistedDocuments`, beside the manifest. When it evicts, the handshake repeats.

The **parse caches** map text to a parsed, validated document, and they exist with or without persisted queries. SmallRye keeps the parsed document in its own `QueryCache`, which graphql-java consults through its `PreparsedDocumentProvider` hook, described in the execution page of the graphql-java documentation under "Query Caching". Strawberry has `ParserCache` and `ValidationCache` extensions, each an LRU of 128 entries by default and each passed as a class so that every request gets its own instance. They matter more with persisted queries, because the hash makes every request for a document identical text. Chapter 6 priced parsing and validation per request; here the second request for a document pays neither.

The two layers also fail differently. Losing a stored text costs a round trip. Losing a parsed document costs CPU on the server and nothing on the wire.

## Persisted documents and limits

Chapter 14 bounds what one document may do: its depth, its aliases and its cost. A persisted document does not change that analysis, and the two controls cover different attackers.

In **trusted mode** the limits become a backstop. Every document that can run was written by your developers and reviewed, so the attacks Chapter 14 rejects cannot arrive as new text. A mistake in one of your own documents can still be expensive, and the limits catch it, but they are no longer the main defence.

In **APQ mode** they are as necessary as before. Anyone can register a document that floods a query with aliases, and the hash does not make it cheaper. The example leaves the limits out so that each chapter shows one concern, and the README says that production carries both.

## Operating them

A manifest is a deployment artefact with its own order of operations.

- **The manifest deploys before the client.** A client that sends a hash the server does not yet hold gets `PersistedQueryNotFound`. In APQ mode it recovers by sending the text. In trusted mode there is no recovery, so the new manifest must be live before the build that uses it.
- **Never remove a hash a live client sends.** Old mobile and web builds stay in use for months. Retire a document only when the telemetry says no client sends it.
- **Give every document an operation name.** Each manifest entry has a `name`, and the log or trace of a request by hash would otherwise carry only 64 characters of hex. Chapter 19 builds observability on operation names, and a persisted document is the one place a name is guaranteed to exist.
- **Treat the hash as part of the contract.** Any change to the text, even whitespace, changes the hash. Generate the manifest from the source and never edit a body by hand, and `verify.sh`'s manifest check is the same rule enforced.

## On the wire

Every value below is asserted by `verify.sh`, which runs on both stacks. APQ cases use ports 8250 and 8251; trusted cases use 8252 and 8253. `H_TRACK`, `H_PORT` and `H_REG` are the SHA-256 of the manifest bodies.

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

Counts and keys do not vary by stack, except where the table says so.

| Check | Quarkus | Python |
|---|---|---|
| manifest | each `id` equals `sha256(body)` | the same |
| handshake 1, hash only | 200, no `data`; `PersistedQueryNotFound`, `PERSISTED_QUERY_NOT_FOUND`; 0 calls | the same, with `"data": null` |
| handshake 2, hash and text | `ABC123`, `ONBOARD_CARRIER` | the same |
| handshake 3, hash only | the same data; the same source-call keys as handshake 2 | the same |
| list query by hash | the data of Chapter 13's four-cargo page; the same calls as its full text | the same |
| size, `CargoDetail` | exactly 624 bytes with text, exactly 163 by hash | the same |
| mismatch | `BAD_USER_INPUT`, `provided sha does not match query`; 0 calls | the same |
| GET by hash | 200, the same data | the same |
| GET by hash with `operationName` | 200, `ABC123` | the same |
| GET, unknown hash | `PersistedQueryNotFound`; 0 calls | the same |
| `GET` and `POST`, literal `%` and `+` | the source receives `A+B%41 C` from the text and by hash over `GET` and over `POST`, `D+E%42 F` from a variable, and a `100%` document by hash answers `200` | the same |
| `GET`, `operationName` that matches nothing | a single-operation mutation by text and by hash with `operationName=Nope`: `400`, `BAD_USER_INPUT`; with an empty name: `405`; no `data`, 0 `appendEvent` | `400`, no `data`, 0 `appendEvent` |
| GET mutation by hash, and as text | `405`, `Allow: POST`, `mutations are not allowed when using GET`; 0 `appendEvent` | `400`, the same text; 0 `appendEvent` |
| GET, malformed variants | a variant of the mutation: `405`, nothing written; a document that does not parse: `400`, 0 calls | `400`, nothing written; a syntax error, 0 calls |
| mutation by hash over POST | `evt_10`, `IN_PORT`; the same key by hash again returns `evt_10`, 0 `appendEvent` | the same |
| trusted, manifest hash | `Rotterdam` by POST and GET | the same |
| trusted, other text | `{ __typename }`, its hash with it, and introspection: `PERSISTED_QUERY_REQUIRED`, `only persisted documents are accepted`, 0 calls | the same |
| trusted, other transports | an `application/graphql` introspection body and a `?query=` on `POST` and `GET`: `PERSISTED_QUERY_REQUIRED`, 0 calls; an empty `application/graphql` body: `PERSISTED_QUERY_REQUIRED`; a WebSocket upgrade, with one `Upgrade` header or two: `400`, 0 `appendEvent`, 0 calls | `?query=` the same; `application/graphql` is `400` |
| trusted, unknown hash | `PERSISTED_QUERY_NOT_FOUND`, including a hash registered on the APQ instance | the same |
| trusted, manifest text and mutation | `Rotterdam`, also as an `application/graphql` body; `evt_10` by hash | `Rotterdam`; `evt_10` by hash |
| bounded store | 1,100 registered, exactly 1,000 resolve | the same; the 100 that do not are the first 100 registered |
| schema, on the APQ instance | conforms to `contracts/schema/`; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

`bash examples/15-persisted-queries/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Persisted documents answer two axes of Chapter 2 at once. The <em>caching needs</em> axis gets a short, stable <code>GET</code> URL that intermediaries can key, and the <em>operational and security cost</em> axis gets either less parsing and fewer bytes (APQ) or an allowlist (trusted documents). The <em>contract and evolution style</em> axis is the price: a hash is part of the contract between a client build and a server, so manifests deploy before clients and live hashes are never removed. The tracking view therefore runs trusted documents for its own clients, whose operations are known at build time, runs APQ only where clients cannot be enumerated and pairs it with Chapter 14's limits, keeps mutations on <code>POST</code>, and implements Apollo's protocol in a few lines of code on each stack.</p></div>

## Where this goes next

This chapter turned a document into a hash. It walked APQ's three steps, refused a hash that does not match its text, served persisted queries over `GET` and kept mutations off it, contrasted APQ with trusted documents, and placed the resolution at the seam where a hash becomes text on each stack.

Chapter 16 builds on the `GET` URLs this chapter makes: it puts an HTTP cache in front of each stack, sets `Cache-Control` per response, and caches fields inside the server. The hash-only `GET` and its `Accept` header are what that cache keys on.

For the protocol, read Apollo's [Automatic Persisted Queries](https://www.apollographql.com/docs/apollo-server/performance/apq) and the [persisted queries and the manifest format](https://www.apollographql.com/docs/graphos/platform/security/persisted-queries#manifest-format) in GraphOS. For trusted documents, read the "Trusted documents" section of the [Security](https://graphql.org/learn/security/) page on graphql.org. For `GET` and its rules, read the "GET" section of the [GraphQL over HTTP](https://http-spec.graphql.org/draft/) specification. The engine side is in the "Query Caching" section of the graphql-java [execution documentation](https://www.graphql-java.com/documentation/execution), the Strawberry pages on [schema extensions](https://strawberry.rocks/docs/guides/extensions), [ParserCache](https://strawberry.rocks/docs/extensions/parser-cache) and [ValidationCache](https://strawberry.rocks/docs/extensions/validation-cache), and the Quarkus [HTTP reference](https://quarkus.io/guides/http-reference) and [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql).

## For deeper coverage

- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022) — end-to-end clients, pagination and the manifest-style thinking behind a build-time document list.
- Samer Buna, *GraphQL in Action* (Manning, 2021) — resolvers and data fetching, the execution path a persisted query still runs once resolved.
- Cloud Native Design Patterns, chapter "Appendix L: Caching" — the general caching-by-key discipline that a hash-keyed `GET` URL plugs into.
- [Apollo Automatic Persisted Queries](https://www.apollographql.com/docs/apollo-server/performance/apq) and the [GraphOS persisted-queries manifest format](https://www.apollographql.com/docs/graphos/platform/security/persisted-queries#manifest-format) — the protocol and the manifest this chapter implements.
- graphql.org Security page, "Trusted documents" section — the allowlist model this chapter contrasts with APQ.
