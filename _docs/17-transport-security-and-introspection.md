---
title: "Transport security and introspection control"
order: 17
part: "Security"
description: "Serving GraphQL over TLS from framework configuration with generated certificates, each stack's protocol floor, HSTS, public against internal instances, turning off introspection, field suggestions, the IDE and GET, closing the form and text/plain CSRF paths, CORS for one origin, size and token limits, and checking the contract without a public schema."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Terminate TLS in-process on both stacks and state each framework's protocol floor: Quarkus's TLS 1.3-only default versus Python's `ssl`-module TLS 1.2 minimum.
- Turn off introspection (`Introspection.enabledJvmWide(false)`, `DisableIntrospection`) and field suggestions on a public instance while keeping an internal instance for contract checks.
- Close the CSRF-relevant paths a browser can send without a preflight: `text/plain`, form-encoded and multipart `POST`s, and a mutation over `GET`.
- Configure CORS for exactly one trusted origin and explain why it is not a substitute for the content-type guard.
- Bound request body size and token count at the HTTP and parser layers, before any GraphQL rule runs.

## Why this matters

The DataLoader batching chapter ended with a server that answers a four-cargo page in six or eight source calls. Every request so far has crossed the wire in clear text, and any caller could ask the server for its whole schema. This chapter closes both. The tracking view moves behind TLS, and the instance the public reaches stops describing itself.

The code is in `examples/17-transport-security/`. It starts from the DataLoader batching example, so the schema, the seed and the masked errors are unchanged. Each stack's image is deployed twice: a public instance with introspection, field suggestions, the IDE and GET queries off, and an internal instance that leaves introspection on. `verify.sh` generates a certificate authority, runs all four instances over HTTPS and asserts what each refuses and allows.

## What the transport must guarantee

A GraphQL request carries the same secrets a REST request does, to one URL. Authentication puts a bearer token in the `Authorization` header; a token sent over plain HTTP is a token any router on the path can copy. The transport has to give three things: the client knows it reached the server it meant to reach, nobody on the path can read the exchange, and nobody can change it. TLS 1.3 (RFC 8446) is the protocol that provides all three, and every other control here assumes it.

Two further problems are specific to GraphQL. The schema is queryable by default, so an attacker with no credentials can ask what exists. And a browser can be made to send a request to your endpoint from a page on another origin, so the server must not trust a request just because the browser attached its cookies. The sections below follow the order a request meets them. Figure 17.1 shows the gates.

{% include excalidraw.html file="17-hardened-request-path" alt="A row of seven gates a request to a public instance passes in order: TLS, CORS, Content-Type, Body size, Parse, Validate and Execute. A dashed arrow from each gate leads to its refusal. TLS ends the handshake, with Quarkus accepting TLS 1.3 only and Python accepting 1.2 and up. CORS sends no Allow-Origin header, with 403 on Quarkus and 400 on Python. Content-Type answers 415 on Quarkus and 400 on Python, and form and text/plain posts never run. Body size answers 413 at 64K on Quarkus and 200 on Python, where the limit is set at a fronting proxy. Parse returns errors and no data, at 15000 tokens on Quarkus and 5000 on Python. Validate refuses __schema and __type on both stacks with errors and no data, and offers no Did you mean hint; on Quarkus the refusal comes at execution start, before the first resolver. Execute masks every error except the exposed codes." caption="Figure 17.1: The gates in front of a public instance, and what each refusal looks like on each stack. A refused request makes no source call." %}

## TLS in the framework

Both stacks terminate TLS in the process. A reverse proxy or a service mesh can do it instead, and later chapters on deployment topology return to that, but in-process configuration shows what each framework decides for you.

Quarkus reads a certificate and key through its TLS registry. The settings are in `application.properties`:

```properties
quarkus.tls.key-store.pem.tls.cert=/certs/tls.crt
quarkus.tls.key-store.pem.tls.key=/certs/tls.key
quarkus.http.ssl-port=8443
quarkus.http.insecure-requests=disabled
quarkus.http.header."Strict-Transport-Security".value=max-age=31536000
```

Uvicorn takes the same two files as command-line options in the Containerfile:

```dockerfile
ENTRYPOINT ["opentelemetry-instrument", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8443", \
    "--ssl-certfile", "/certs/tls.crt", "--ssl-keyfile", "/certs/tls.key"]
```

`insecure-requests=disabled` closes the plain-HTTP port, so a client that forgets the `s` gets a dropped connection instead of a readable response. Uvicorn speaks TLS on its one port, so a plain-HTTP request there is not understood either. `verify.sh` asserts that curl fails against `http://localhost:8270` and `http://localhost:8271` with exit 52.

The stacks differ in the oldest protocol they accept. The Quarkus TLS registry defaults to TLS 1.3 only (`quarkus.tls.protocols`), so a client limited to TLS 1.2 fails the handshake with a `protocol version` alert (curl exit 35). Uvicorn hands the files to Python's `ssl` module, whose default minimum is TLS 1.2, so the same client succeeds. Both accept TLS 1.3. `verify.sh` runs `curl --tlsv1.2 --tls-max 1.2` against both and asserts the difference. Each floor is the stack's default. On Uvicorn the minimum version is set by building the `SSLContext` with uvicorn's programmatic `ssl_context_factory`, or by terminating TLS at a proxy. A Quarkus deployment that must serve old clients can list TLS 1.2 in `quarkus.tls.protocols`. State the floor you intend, and test it.

HSTS (RFC 6797) tells a browser to use HTTPS for the host for the stated number of seconds, even if a link or a typed address says `http://`. Quarkus sets the header with `quarkus.http.header`. Python sets it in a small `@app.middleware("http")` function. Both answer `strict-transport-security: max-age=31536000`, and `verify.sh` reads it back.

## Certificates for a lab

A TLS example needs a certificate, and a certificate needs a private key. A key committed to a repository is public, so nothing here is committed. `gen-certs.sh` runs `openssl` and writes a two-day certificate authority, and a server certificate signed by it, into a directory it is given. The server certificate carries the names `localhost`, `quarkus`, `python`, `quarkus-internal`, `python-internal` and `127.0.0.1`. The directory `certs/` is git-ignored, and `verify.sh` generates its own set into a scratch directory, exports `CERT_DIR` for compose to mount read-only at `/certs`, and deletes it on exit.

The client trusts only `ca.crt`. curl takes it with `--cacert`, and the harness takes it from `LGTM_CACERT`, which it also passes to `graphql-inspector` as `NODE_EXTRA_CA_CERTS`. Three cases in `verify.sh` show that verification is real. Without the CA, curl fails with exit 60. A request to `wrong.example` resolved to `127.0.0.1` also fails with exit 60, because no subject name matches. A request to the name `quarkus` or `python`, resolved the same way, succeeds, because that name is in the certificate. Production replaces the lab authority with a certificate from a public or an internal CA; the application configuration does not change.

## Introspection is a map

Introspection (the GraphQL specification's "Introspection" section) lets any client ask a schema for its types, fields and arguments. That is how GraphiQL completes your query and how a code generator reads the contract, and it is why the schema in this book is published. It is also a map for a person with no business knowing the territory: the `Cargo` type names `handlingHistory`, the mutation names `registerHandlingEvent`, and an anonymous caller can read all of it in one request. The execution model introduced the meta fields and said this chapter decides when to turn them off.

The decision is by instance. Anonymous callers get no introspection; your own tools, in CI and on developer machines, need it. Figure 17.2 shows one image per stack deployed twice, and the settings that differ.

{% include excalidraw.html file="17-public-vs-internal-endpoints" alt="One image per stack is deployed twice. The public instance on ports 8270 and 8271 has introspection off, so __schema and __type are refused on both stacks, with field suggestions, the IDE and GET queries off as well, and it is reached by browsers and partners. The internal instance on ports 8272 and 8273 has introspection on, suggestions, IDE and GET on for Python, and it is reached by CI and developers, who run assert_sdl_conforms against it. A dashed box shows that an SDL export at build time can feed CI instead, with no endpoint." caption="Figure 17.2: The same image deployed as a public and an internal instance. Only the internal one answers a schema query, and the contract check points at it." %}

On Quarkus, introspection is turned off with graphql-java's `Introspection.enabledJvmWide(false)`, called at startup when `tracking.introspection.enabled` is false. Each instance runs in its own JVM, so the flag applies per instance: the public one sets `TRACKING_INTROSPECTION_ENABLED=false` and the internal one keeps the default. Both root fields, `__schema` and `__type`, are refused, with an `errors` array and no data. On Python the schema is built by a function that takes a flag.

Validation answers differently for known and unknown type names (`... on NoSuchType` answers `Unknown type`). Turning introspection off hides the schema map, and a persisted-queries allowlist governs which names a client can send.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@ApplicationScoped
public class IntrospectionSwitch {

    @ConfigProperty(name = "tracking.introspection.enabled", defaultValue = "true")
    boolean enabled;

    void onStart(@Observes StartupEvent event) {
        if (!enabled) {
            Introspection.enabledJvmWide(false);
        }
    }
}
```

```python
def schema_for(public: bool) -> strawberry.Schema:
    extensions: list = [
        partial(MaskErrors, should_mask_error=should_mask, error_message="Internal server error."),
        partial(MaxTokensLimiter, max_token_count=MAX_TOKENS),
    ]
    if public:
        extensions.append(DisableIntrospection)
    return strawberry.Schema(
        query=Query,
        mutation=Mutation,
        config=StrawberryConfig(scalar_map=SCALAR_MAP, disable_field_suggestions=public),
        extensions=extensions,
    )
```

The refusals read differently. Strawberry's `DisableIntrospection` is a validation rule that reports each field it finds: `GraphQL introspection has been disabled, but the requested query contained the field '__schema'.` graphql-java answers `Introspection has been disabled for this request` with the classification `IntrospectionDisabled`. In both cases the response has errors and no data, `__type(name: "Cargo")` and `__type(name: "NoSuchType")` get identical responses, and `{ __typename }` still answers `Query`, because `__typename` is a property of every selection set and not part of the schema map. `verify.sh` asserts the refusal of `__schema` and of both `__type` lookups, the identical answers, the working `__typename`, and the working introspection on both internal instances.

Introspection has a second door. SmallRye can serve the schema as a document at `/graphql/schema.graphql`. That property, `quarkus.smallrye-graphql.schema-available`, is fixed at build time, so one image cannot have it on for one instance and off for the other. The example sets it false for both, and the internal instance is read by introspection. A browser IDE is a third door, covered below.

## Suggestions reveal names

Turning introspection off is not enough if an error message still teaches the schema. graphql-core adds a hint when a field does not exist: querying `trackingI` on `Cargo` answers `Cannot query field 'trackingI' on type 'Cargo'. Did you mean 'trackingId'?` An attacker can probe names with a dictionary and let the server finish each guess, which is how tools recover a schema from a server that disabled introspection.

The public Python instance sets `disable_field_suggestions=True` in `StrawberryConfig`, and the same request answers `Cannot query field 'trackingI' on type 'Cargo'.` with no hint. `verify.sh` asserts that the public response contains neither `Did you mean` nor the real name, and that the internal one contains `Did you mean 'trackingId'?`, so a regression in either direction fails. graphql-java never suggests anything: its message is ``Validation error (FieldUndefined@[cargo/trackingI]) : Field 'trackingI' in type 'Cargo' is undefined``, and that holds on both Quarkus instances. There is nothing to switch off on that stack, and the check on it is that the text stays free of a hint.

The IDE follows the same rule. Strawberry serves GraphiQL for a browser GET on the GraphQL path, so the router is built with `graphql_ide=None if settings.public else "graphiql"` (shown below). On the public instance a GET with `Accept: text/html` answers 404 and no page. SmallRye refuses `Accept: text/html` with 406 before it looks at the method. The internal Python instance answers 200 with the GraphiQL page.

## CSRF for an API that takes JSON

A browser lets a page on `https://evil.example` send a POST to your API without a preflight when it uses a CORS-safelisted method and only CORS-safelisted request headers (the Fetch standard's "CORS protocol" section), where `Content-Type` is `text/plain`, `application/x-www-form-urlencoded` or `multipart/form-data`. The browser attaches the visitor's cookies. A server that reads such a body as JSON would let the page run a mutation as the visitor. An API that takes `application/json` is safe from this only if it refuses everything else, because JSON is the content type that forces a preflight.

A GraphQL endpoint should accept only JSON request bodies. The GraphQL-over-HTTP draft recommends 415 for an unsupported Content-Type, and the OWASP CSRF cheat sheet recommends disallowing simple content types, because a browser sends `text/plain`, form-encoded and multipart POSTs cross-origin without a preflight. The Quarkus example enforces this with a Vert.x filter, `ContentTypeGuard`, that answers 415. On Python, Strawberry's content-type check answers `400 Unsupported content type`.

`ContentTypeGuard` uses Quarkus's filter API, the `Filters` event of `quarkus-vertx-http` (what `@RouteFilter` is built on), which runs before every route. On Python the router's content-type check does the same work, so the second tab shows the router.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@ApplicationScoped
public class ContentTypeGuard {

    private static final Set<String> JSON = Set.of("application/json", "application/graphql-response+json");

    void register(@Observes Filters filters) {
        filters.register(rc -> {
            if (rc.request().method() == HttpMethod.POST && rc.normalizedPath().startsWith("/graphql")
                    && !isJson(rc.request().getHeader(HttpHeaders.CONTENT_TYPE))) {
                rc.response().setStatusCode(415).putHeader(HttpHeaders.CONTENT_TYPE, "text/plain")
                        .end("Unsupported Media Type: send application/json");
                return;
            }
            rc.next();
        }, 100);
    }
}
```

```python
app.include_router(
    GraphQLRouter(
        schema_for(settings.public),
        context_getter=get_context,
        graphql_ide=None if settings.public else "graphiql",
        allow_queries_via_get=not settings.public,
    ),
    prefix="/graphql",
)
```

A POST to `/graphql` with any other media type, or none, gets 415. A `charset` parameter is ignored, so `application/json; charset=utf-8` passes. The guard uses the GraphQL-over-HTTP draft's request and response media types (https://http-spec.graphql.org/draft/), where the response type `application/graphql-response+json` is also accepted; a client that sends it is not wrong. The draft's "Status Codes" section recommends 415 for an unsupported Content-Type. The Quarkus guard sends 415; Strawberry sends 400, which still refuses before parsing.

`verify.sh` sends the same mutation body as `text/plain`, as a form, as multipart and with the header removed. Quarkus answers 415 and Python 400 each time, and the source-call log stays empty: nothing resolved and nothing was written. The first mutation that is accepted, as `application/json` at the end, is `evt_10`, which proves the refused requests wrote nothing.

GET gets the same treatment. A mutation must never travel in a URL, which can be linked, prefetched and logged, and the GraphQL-over-HTTP draft requires a server to refuse one over GET. Both public instances turn GET queries off: Quarkus because `http.get.enabled` defaults to false and answers 405, Python through `allow_queries_via_get=not settings.public`, which answers 400. The internal Python instance allows GET queries and still refuses a mutation. Persisted queries turn GET back on for that read path, which carries a different threat model.

## CORS for the one origin that needs it

CORS is permission for a browser to let a page on one origin read a response from another. It is not authentication, and curl reaches a server that lacks it. It controls which web pages may call the API with a visitor's browser credentials and read the answer. The default is nobody, and the configuration lists the one origin the product needs.

Quarkus takes it as configuration:

```properties
quarkus.http.cors.enabled=true
quarkus.http.cors.origins=https://tracking.example.com
quarkus.http.cors.methods=POST
quarkus.http.cors.headers=content-type,authorization
```

Python gets the equivalent from FastAPI's `CORSMiddleware` with the same origin, `POST` and the same two headers. A preflight `OPTIONS` from `https://tracking.example.com` asking for `POST` is answered with `access-control-allow-origin: https://tracking.example.com` and `access-control-allow-methods: POST` on both stacks. A preflight from `https://evil.example` gets no `access-control-allow-origin` header: Quarkus answers 403 and Python 400, and the browser blocks the real request. A POST that arrives anyway from an unlisted origin is refused with 403 by Quarkus before any source call; on Python `CORSMiddleware` sets only the CORS response headers and passes the request to the app, which answers 200. The allowed `authorization` header is what lets authentication's bearer token travel from the one trusted page.

CORS and the content-type check do different jobs. CORS stops a hostile page from reading a response and from sending a non-simple request. A simple request is sent without a preflight, and whether the server refuses it depends on its own checks: Quarkus's CORS filter refuses a listed-origins mismatch with 403, while a server without an origin check runs it. The content-type check refuses the simple content types whatever the origin. You need both.

## Size limits

An attacker needs no schema to hurt a server. A large body costs memory and time before any GraphQL rule runs, and a document of a hundred thousand tokens costs the parser. The stacks bound these differently.

Quarkus bounds the body with `quarkus.http.limits.max-body-size=64K`, and a larger POST gets 413 before parsing. The test body is a valid query with a 100 KB comment. curl negotiates HTTP/2 over TLS by default, and `verify.sh` sends that case with `--http1.1` so the 413 arrives as a plain response.

Uvicorn leaves the body size to a fronting proxy. The same 100 KB comment passes on Python and returns `Query`, because a comment is not a token. The production setting is `client_max_body_size` in nginx or the ingress equivalent.

The parser limit is the second bound. Python sets `MaxTokensLimiter` with 5000 tokens: a 16000-token body fits in 32 KB and answers `Syntax Error: Document contains more than 5000 tokens. Parsing aborted.` On Quarkus the parser applies graphql-java's default operation limit of 15000 tokens, and the 16000-token body answers `Unparseable input document`. Query cost analysis sets that limit to 5000 through graphql-java's `ParserOptions` and adds depth, alias and cost limits on top of these.

Every request-level refusal of a GraphQL document here, the introspection error, the token limit, the unparseable document, answers 200 with an `errors` array and no data on both stacks. The GraphQL-over-HTTP draft recommends a 4xx there; both stacks answer 200 with the errors array, and clients read the body accordingly. The content-type, size and CORS gates are HTTP-level refusals and send their own status.

## Checking the contract without public introspection

The contract-first approach made the canonical SDL the contract, and `assert_sdl_conforms` compares the live schema with it by introspection. A public instance now refuses that query, so the check runs elsewhere, in one of two places.

The internal instance is the first. It runs the same image with introspection on and is not reachable from the internet. CI starts it, reads it over TLS with the generated CA, and diffs it against `contracts/schema/`. `verify.sh` does exactly that on ports 8272 and 8273: `assert_sdl_conforms` passes, `finalArrivalDate` is deprecated with its reason, the custom scalars carry their `specifiedByURL`, and the only difference from the canonical SDL is the unserved `Subscription` type.

The second is an export at build time. A code-first build can print its schema and the gate can diff the file, so no endpoint needs introspection. This costs one build step and is the cleaner answer when the schema is known before the service starts. The example uses the internal instance because it shows one image answering two ways.

Neither approach proves that the public instance serves the same schema as the internal one. They share an image and differ by environment variables, which is a small difference, and the public refusals in `verify.sh` show the switch is on.

## On the wire

Run the whole sequence:

```bash
bash examples/17-transport-security/verify.sh
```

To explore by hand, generate the certificates once and trust the CA:

```bash
examples/17-transport-security/gen-certs.sh examples/17-transport-security/certs
docker compose -f examples/17-transport-security/compose.yaml up -d --build
curl -s --cacert examples/17-transport-security/certs/ca.crt https://localhost:8270/graphql \
  -H 'Content-Type: application/json' -d '{"query":"{ __schema { queryType { name } } }"}'
curl -s --cacert examples/17-transport-security/certs/ca.crt https://localhost:8272/graphql \
  -H 'Content-Type: application/json' -d '{"query":"{ __schema { queryType { name } } }"}'
docker compose -f examples/17-transport-security/compose.yaml down -v
```

The first call is refused on the public instance and the second answers `Query` on the internal one. Python is on 8271 and 8273.

| Check | Quarkus | Python |
|---|---|---|
| `{ __typename }` over https, all four instances | `Query` | `Query` |
| without the CA; for `wrong.example`; over plain http | curl exit 60; 60; 52 | the same |
| TLS 1.3 client; TLS 1.2 client | 200; handshake fails (curl exit 35) | 200; 200 |
| HSTS | `max-age=31536000` | the same |
| public `__schema`; `__type` of `Cargo` and of `NoSuchType` | errors, no data, `Introspection has been disabled for this request`; the two `__type` answers match | errors, `data` null, `introspection has been disabled`; the same match |
| public `{ __typename }`; internal `__schema` | `Query`; answers | the same |
| misspelt `trackingI` | ``Field 'trackingI' in type 'Cargo' is undefined``, no `Did you mean` on any instance | public ``Cannot query field 'trackingI' on type 'Cargo'.``; internal adds ``Did you mean 'trackingId'?`` |
| `GET /graphql/schema.graphql`; public `GET /graphql` as `text/html` | 404; 406, no HTML (internal: 406) | 404; 404, no HTML (internal: 200, GraphiQL) |
| mutation as `text/plain`, form, multipart or no `Content-Type` | 415, 0 source calls | 400, `Unsupported content type`, 0 source calls |
| mutation or query by GET on public; mutation by GET on internal | 405 | 400 |
| `application/json; charset=utf-8` | 200 | 200 |
| preflight from the allowed origin; from `https://evil.example` | allow-origin header; 403, no header | allow-origin header; 400, no header |
| actual POST with `Origin: https://evil.example` | 403, no source call | 200, the app answers |
| `... on Cargo` and `... on NoSuchType` fragments | `Cargo` named in a spread error; `Unknown type` | the same two messages |
| 100 KB body | 413 | 200, `Query` |
| 16000-token body | 200, `Unparseable input document` | 200, `Document contains more than 5000 tokens` |
| `cargo(trackingId: "GHI345")` on public | `SERVICE_UNAVAILABLE`, `booking service unavailable` | the same |
| first write, as `application/json` on public | `evt_10` | `evt_10` |
| internal schema | conforms; only `Subscription` unserved | the same |

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Transport security is where the <em>operational and security cost</em> axis of the GraphQL decision framework becomes configuration. Every control has a price on every deployment: certificates to issue and rotate, an internal instance to run, an IDE and introspection that public users lose, and a CORS origin list to keep current. The <em>contract and evolution style</em> axis shapes the compromise: a contract-first schema can be exported at build time, so removing public introspection costs the tooling nothing. The <em>aggregation across sources</em> axis is untouched, because none of this changes how a field is resolved. The tracking view therefore serves HTTPS only with the floor each framework gives, sends HSTS, runs a public and an internal instance from one image, refuses introspection and suggestions on the public one, refuses every POST that is not JSON, allows one CORS origin, bounds the body and the token count, and checks the contract on the internal instance.</p></div>

## Review

- Both stacks terminate TLS in-process, and their protocol floors differ: Quarkus defaults to TLS 1.3 only, and Python's `ssl` module accepts TLS 1.2 and up.
- `Introspection.enabledJvmWide(false)` and Strawberry's `DisableIntrospection` turn off introspection and field suggestions on a public instance while an internal instance keeps them on for contract checks.
- The content-type guard closes the CSRF-relevant paths a browser can send without a preflight: `text/plain`, form-encoded and multipart `POST`s, and a mutation over `GET`.
- CORS is configured for exactly one trusted origin, and it answers a different question than the content-type guard: who may read a response, not what a body may contain.
- Request body size and token count are bounded at the HTTP and parser layers, ahead of any GraphQL rule.

## Where this goes next

This chapter moved the tracking view behind TLS, split each stack into a public and an internal instance, and closed introspection, field suggestions, the IDE, GET and the form and `text/plain` POST path on the public one, with one CORS origin and bounds on body and tokens.

Authentication and authorization put identity on the encrypted channel: Keycloak issues the tokens, each stack validates them, and authorization works per operation, per object and per field.

For the protocols and the stack settings, read RFC 8446 for TLS 1.3, RFC 6797 for HSTS, and the GraphQL specification's "Introspection" section. The [GraphQL over HTTP draft](https://http-spec.graphql.org/draft/) defines the request and response media types and the status codes. The Fetch standard's "CORS protocol" section defines simple requests and preflight. The [OWASP GraphQL Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html) covers introspection, GraphiQL and field suggestions ("Introspection + GraphiQL", "Don't Return Excessive Errors"), and the [OWASP Cross-Site Request Forgery Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html) covers this chapter's check under "Disallowing simple content types". Artur Czemiel's *GraphQL Best Practices* covers attacks on GraphQL servers and schema design for security; the book is listed on the [Bibliography](../../bibliography/) page. Quarkus documents the [TLS registry reference](https://quarkus.io/guides/tls-registry-reference) and the [HTTP reference](https://quarkus.io/guides/http-reference) for CORS, limits and headers, and the [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) for `schema-available`. On the Python side read the Strawberry pages for [DisableIntrospection](https://strawberry.rocks/docs/extensions/disable-introspection) and the [schema configuration](https://strawberry.rocks/docs/types/schema-configurations), the uvicorn [settings](https://uvicorn.dev/settings/) for the SSL options, and the FastAPI guide to [CORS](https://fastapi.tiangolo.com/tutorial/cors/).

## For deeper coverage

- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): attacks on GraphQL servers, introspection and schema design for security.
- Cloud Native Design Patterns, chapter "Security": the broader transport and access-control patterns this chapter's TLS, CORS and introspection controls sit inside.
- [OWASP GraphQL Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html): introspection, GraphiQL and field-suggestion guidance this chapter implements.
- [OWASP Cross-Site Request Forgery Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html): "Disallowing simple content types", the rule behind this chapter's content-type guard.
- RFC 8446 (TLS 1.3) and RFC 6797 (HSTS): the transport guarantees this chapter configures on both stacks.
