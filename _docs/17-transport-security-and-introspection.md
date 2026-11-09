---
title: "Transport security and introspection control"
order: 17
part: "Security"
description: "TLS from framework configuration, each stack's protocol floor, public and internal instances, introspection and field suggestions off, the form and text/plain CSRF paths closed, one CORS origin, and size and token limits."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Terminate TLS in-process on both stacks and state each framework's protocol floor: Quarkus's TLS 1.3-only default versus Python's `ssl`-module TLS 1.2 minimum.
- Turn off introspection (`Introspection.enabledJvmWide(false)`, `DisableIntrospection`) and field suggestions on a public instance while keeping an internal instance for contract checks.
- Close the CSRF-relevant paths a browser can send without a preflight: `text/plain`, form-encoded and multipart `POST`s, and a mutation over `GET`.
- Configure CORS for exactly one trusted origin and explain why it is not a substitute for the content-type guard.
- Bound request body size and token count at the HTTP and parser layers, before any GraphQL rule runs.

## Why this matters

A GraphQL request carries the same secrets a REST request does, to one URL. A bearer token sent over plain HTTP is a token any router on the path can copy. TLS 1.3 (RFC 8446) gives the client proof it reached the right server, and keeps the exchange unreadable and unchangeable on the way.

Two problems are specific to GraphQL. The schema is queryable by default, so an anonymous caller can ask what exists. And a browser can be made to send a request to your endpoint from a page on another origin, with the visitor's cookies attached. The controls below follow the order a request meets them.

{% include excalidraw.html file="17-hardened-request-path" alt="A row of seven gates a request to a public instance passes in order: TLS, CORS, Content-Type, Body size, Parse, Validate and Execute. A dashed arrow from each gate leads to its refusal. TLS ends the handshake, with Quarkus accepting TLS 1.3 only and Python accepting 1.2 and up. CORS sends no Allow-Origin header, with 403 on Quarkus and 400 on Python. Content-Type answers 415 on Quarkus and 400 on Python, and form and text/plain posts never run. Body size answers 413 at 64K on Quarkus and 200 on Python, where the limit is set at a fronting proxy. Parse returns errors and no data, at 15000 tokens on Quarkus and 5000 on Python. Validate refuses __schema and __type on both stacks with errors and no data, and offers no Did you mean hint; on Quarkus the refusal comes at execution start, before the first resolver. Execute masks every error except the exposed codes." caption="Figure 17.1: The gates in front of a public instance, and what each refusal looks like on each stack. A refused request makes no source call." %}

Each stack's image is deployed twice: a public instance with introspection, field suggestions, the IDE and GET queries off, and an internal instance that leaves introspection on. Both start from the same schema and masked errors.

## TLS in the framework

Both stacks terminate TLS in the process. A reverse proxy or service mesh can do it instead; in-process configuration shows what each framework decides for you.

Quarkus reads a certificate and key through its TLS registry:

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

`insecure-requests=disabled` closes the plain-HTTP port, so a client that forgets the `s` gets a dropped connection (curl exit 52) instead of a readable response. Uvicorn speaks TLS on its one port, so plain HTTP there fails the same way.

The stacks differ in the oldest protocol they accept:

| | Quarkus | Python |
|---|---|---|
| Default floor | TLS 1.3 only (`quarkus.tls.protocols`) | TLS 1.2 (the `ssl` module's default) |
| A TLS 1.2 client | handshake fails, `protocol version` alert (curl exit 35) | succeeds |
| To change it | list TLS 1.2 in `quarkus.tls.protocols` | build the `SSLContext` with uvicorn's `ssl_context_factory`, or terminate TLS at a proxy |

State the floor you intend, and test it with a TLS 1.2-only client.

HSTS (RFC 6797) tells a browser to use HTTPS for the host for the stated number of seconds, even if a link says `http://`. Quarkus sets the header with `quarkus.http.header`; Python sets it in a small `@app.middleware("http")` function. Both answer `strict-transport-security: max-age=31536000`.

### Certificates for a lab

A key committed to a repository is public, so none is committed. `gen-certs.sh` runs `openssl` and writes a two-day certificate authority and a server certificate signed by it, with the names `localhost`, `quarkus`, `python`, `quarkus-internal`, `python-internal` and `127.0.0.1`. The `certs/` directory is git-ignored, and `verify.sh` generates its own set into a scratch directory, mounts it read-only at `/certs` and deletes it on exit.

The client trusts only `ca.crt`. Without the CA, or when the name does not match the certificate (`wrong.example` resolved to `127.0.0.1`), curl fails with exit 60; the names in the certificate succeed. Production replaces the lab authority with a public or internal CA, and the application configuration does not change.

## Introspection is a map

Introspection lets any client ask a schema for its types, fields and arguments. That is how GraphiQL completes a query and how a code generator reads the contract. It is also a map for someone with no business knowing the territory: `Cargo` names `handlingHistory`, the mutation names `registerHandlingEvent`, and an anonymous caller reads all of it in one request.

Anonymous callers get no introspection, but your own tools, in CI and on developer machines, need it. So deploy one image twice and let configuration decide.

{% include excalidraw.html file="17-public-vs-internal-endpoints" alt="One image per stack is deployed twice. The public instance on ports 8270 and 8271 has introspection off, so __schema and __type are refused on both stacks, with field suggestions, the IDE and GET queries off as well, and it is reached by browsers and partners. The internal instance on ports 8272 and 8273 has introspection on, suggestions, IDE and GET on for Python, and it is reached by CI and developers, who run assert_sdl_conforms against it. A dashed box shows that an SDL export at build time can feed CI instead, with no endpoint." caption="Figure 17.2: The same image deployed as a public and an internal instance. Only the internal one answers a schema query, and the contract check points at it." %}

On Quarkus, graphql-java's `Introspection.enabledJvmWide(false)` is called at startup when `tracking.introspection.enabled` is false. Each instance runs in its own JVM, so the flag applies per instance. On Python the schema is built by a function that takes a flag.

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
    """Build the schema for a public (hardened) or an internal instance.

    Every extension is passed as a factory (``functools.partial``) or a class, so
    each request gets its own instance. ``MaskErrors`` is an allowlist (see
    app/errors.py). ``MaxTokensLimiter`` makes graphql-core stop parsing a document
    past 5000 tokens. On a public instance ``DisableIntrospection`` rejects
    ``__schema`` and ``__type`` at validation, and ``disable_field_suggestions``
    drops the "Did you mean ..." hint that would otherwise name a real field.
    """
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

Both refuse the root fields `__schema` and `__type` with an `errors` array and no data. The wording differs: graphql-java answers `Introspection has been disabled for this request` (classification `IntrospectionDisabled`), and Strawberry reports `GraphQL introspection has been disabled, but the requested query contained the field '__schema'.` `__type(name: "Cargo")` and `__type(name: "NoSuchType")` get identical responses, and `{ __typename }` still answers `Query`, because `__typename` belongs to every selection set and is not part of the schema map.

Introspection has a second door. SmallRye can serve the schema at `/graphql/schema.graphql`, but `quarkus.smallrye-graphql.schema-available` is fixed at build time, so one image cannot have it on for one instance and off for the other. Set it false for both and read the internal instance by introspection. The IDE is a third door, covered below.

Turning introspection off hides the schema map, not the type names a validator reveals: a fragment `... on NoSuchType` answers `Unknown type`, while `... on Cargo` produces a different error that names `Cargo`. A persisted-queries allowlist governs which names a client can send at all.

### Suggestions reveal names

An error message can teach the schema too. graphql-core adds a hint when a field does not exist: querying `trackingI` on `Cargo` answers `Cannot query field 'trackingI' on type 'Cargo'. Did you mean 'trackingId'?` An attacker probes names with a dictionary and lets the server finish each guess, which is how tools recover the schema of a server that disabled introspection.

The public Python instance sets `disable_field_suggestions=True`, and the same request answers without the hint. graphql-java never suggests: its message is ``Validation error (FieldUndefined@[cargo/trackingI]) : Field 'trackingI' in type 'Cargo' is undefined``, so there is nothing to switch off on Quarkus.

The IDE follows the same rule. Strawberry serves GraphiQL for a browser GET on the GraphQL path, so the router is built with `graphql_ide=None if settings.public else "graphiql"` (shown below). On the public instance a GET with `Accept: text/html` answers 404 and no page, and the internal Python instance answers 200 with GraphiQL. SmallRye refuses `Accept: text/html` with 406 before it looks at the method, on both instances. `GET /graphql/schema.graphql` answers 404 everywhere.

## CSRF for an API that takes JSON

A page on `https://evil.example` can make a visitor's browser send a POST to your API without a preflight, when the method and headers are CORS-safelisted and `Content-Type` is `text/plain`, `application/x-www-form-urlencoded` or `multipart/form-data` (the Fetch standard's "CORS protocol" section). The browser attaches the visitor's cookies. A server that reads such a body as JSON runs the mutation as the visitor. `application/json` forces a preflight, so a JSON API is safe only if it refuses everything else.

A GraphQL endpoint should accept only JSON request bodies. The GraphQL-over-HTTP draft recommends 415 for an unsupported Content-Type, and the OWASP CSRF cheat sheet recommends disallowing simple content types. Quarkus enforces it with a Vert.x filter registered through the `Filters` event of `quarkus-vertx-http` (what `@RouteFilter` is built on), which runs before every route. On Python, Strawberry's own content-type check does the same work.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@ApplicationScoped
public class ContentTypeGuard {

    private static final Set<String> JSON = Set.of("application/json", "application/graphql-response+json");

    void register(@Observes Filters filters) {
        // Filters run before every route; among filters, higher priority runs first.
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

    private static boolean isJson(String contentType) {
        if (contentType == null) {
            return false;
        }
        int semicolon = contentType.indexOf(';');
        String mediaType = (semicolon < 0 ? contentType : contentType.substring(0, semicolon))
                .trim().toLowerCase(Locale.ROOT);
        return JSON.contains(mediaType);
    }
}
```

```python
app.include_router(
    GraphQLRouter(
        schema_for(settings.public),
        context_getter=get_context,
        # No IDE and no GET queries on a public instance. GET stays a read-only
        # path: Strawberry answers a GET mutation with an error either way.
        graphql_ide=None if settings.public else "graphiql",
        allow_queries_via_get=not settings.public,
    ),
    prefix="/graphql",
)
```

A POST to `/graphql` with any other media type, or none, is refused before parsing: Quarkus answers 415, Strawberry 400 `Unsupported content type`. A `charset` parameter is ignored, so `application/json; charset=utf-8` passes, and the draft's response type `application/graphql-response+json` is accepted too. A refused mutation makes no source call and writes nothing.

GET gets the same treatment. A mutation must never travel in a URL, which can be linked, prefetched and logged, and the draft requires a server to refuse one over GET. Both public instances turn GET queries off: Quarkus because `http.get.enabled` defaults to false (405), Python through `allow_queries_via_get=not settings.public` (400). The internal Python instance allows GET queries and still refuses a mutation. Persisted queries turn GET back on for that read path, which carries a different threat model.

## CORS for the one origin that needs it

CORS is permission for a browser to let a page on one origin read a response from another. It is not authentication, and curl reaches a server that lacks it. The default is nobody, and the configuration lists the one origin the product needs.

```properties
quarkus.http.cors.enabled=true
quarkus.http.cors.origins=https://tracking.example.com
quarkus.http.cors.methods=POST
quarkus.http.cors.headers=content-type,authorization
```

Python gets the equivalent from FastAPI's `CORSMiddleware` with the same origin, `POST` and the same two headers. The `authorization` header lets the bearer token travel from the one trusted page. The two stacks diverge on a hostile origin:

| Request | Quarkus | Python |
|---|---|---|
| Preflight from the allowed origin | `access-control-allow-origin` and `allow-methods: POST` | the same |
| Preflight from `https://evil.example` | 403, no allow-origin header | 400, no allow-origin header |
| Actual POST from `https://evil.example` | 403, no source call | 200: `CORSMiddleware` only sets response headers and passes the request on |

CORS stops a hostile page from reading a response and from sending a non-simple request. A simple request goes out without a preflight, and whether the server refuses it depends on its own checks. The content-type guard refuses the simple content types whatever the origin. You need both.

## Size limits

A large body costs memory and time before any GraphQL rule runs, and a document of a hundred thousand tokens costs the parser. The stacks bound these differently.

| Limit | Quarkus | Python |
|---|---|---|
| Body size | `quarkus.http.limits.max-body-size=64K`; a larger POST gets 413 before parsing (curl negotiates HTTP/2 over TLS, so send it with `--http1.1` to see a plain 413) | none in Uvicorn; set `client_max_body_size` in nginx or the ingress equivalent. A 100 KB comment passes, because a comment is not a token |
| Token count | graphql-java's default of 15000; a 16000-token body answers `Unparseable input document` | `MaxTokensLimiter` at 5000; a 16000-token body fits in 32 KB and answers `Syntax Error: Document contains more than 5000 tokens. Parsing aborted.` |

Query cost analysis lowers the Quarkus limit to 5000 through graphql-java's `ParserOptions` and adds depth, alias and cost limits on top of these.

Every request-level refusal of a GraphQL document, the introspection error, the token limit and the unparseable document, answers 200 with an `errors` array and no data on both stacks. The GraphQL-over-HTTP draft recommends a 4xx there; clients read the body accordingly. The content-type, size and CORS gates are HTTP-level refusals and send their own status.

## Checking the contract without public introspection

`assert_sdl_conforms` compares the live schema with the canonical SDL by introspection, and a public instance now refuses that query. Run the check in one of two places:

- **The internal instance.** It runs the same image with introspection on and is not reachable from the internet. CI starts it, reads it over TLS with the generated CA and diffs it against `contracts/schema/`. The only difference from the canonical SDL is the unserved `Subscription` type.
- **A build-time export.** A code-first build prints its schema and CI diffs the file, so no endpoint needs introspection. It costs one build step and is the cleaner answer when the schema is known before the service starts.

Neither proves the public instance serves the same schema as the internal one. They share an image and differ by environment variables, so the public refusals show the switch is on.

> **Decision**
>
> Transport security turns the operational and security cost axis into configuration: certificates to issue and rotate, an internal instance to run, and an IDE and introspection the public loses. A contract-first schema can be exported at build time, so removing public introspection costs the tooling nothing. Serve HTTPS only with the floor you state, send HSTS, run a public and an internal instance from one image, refuse introspection, suggestions and every non-JSON POST on the public one, allow one CORS origin, bound body and tokens, and check the contract on the internal instance.

> **🤖 Explore with your agent**
>
> "In examples/17-transport-security, change the CORS origin on both stacks from https://tracking.example.com to https://ops.example.com, in application.properties and in the Python CORSMiddleware setup. Then review ContentTypeGuard and the GraphQLRouter settings against the rule that a public instance never answers introspection, suggestions, GET queries or non-JSON POSTs, and report any gap."
>
> Check: run `bash examples/17-transport-security/verify.sh`, then send a preflight with `Origin: https://tracking.example.com` and expect no allow-origin header.

## Build, run, observe

```bash
bash examples/17-transport-security/verify.sh
```

`verify.sh` generates a CA, runs all four instances over HTTPS (Quarkus public 8270, Python public 8271, Quarkus internal 8272, Python internal 8273) and prints `PASS` when each stack refuses and allows what the sections above describe.

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

- Send the mutation as `text/plain`, as a form or with no `Content-Type`: Quarkus answers 415 and Python 400, and no source call is made.
- Add `--tlsv1.2 --tls-max 1.2` to a curl call: it fails on Quarkus (exit 35) and succeeds on Python.
- Query `trackingI` on `Cargo` against 8271 and 8273: the internal instance adds `Did you mean 'trackingId'?`.
- Post a 100 KB body to the public Quarkus instance with `--http1.1`: 413. The same body on Python returns `Query`.
- Send `Origin: https://evil.example` on a POST: Quarkus answers 403, Python 200.

## For deeper coverage

- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): attacks on GraphQL servers, introspection and schema design for security. Listed on the [Bibliography](../../bibliography/) page.
- Cloud Native Design Patterns, chapter "Security": the broader transport and access-control patterns that TLS, CORS and introspection controls sit inside.
- RFC 8446 (TLS 1.3), RFC 6797 (HSTS) and the GraphQL specification's "Introspection" section.
- The [GraphQL over HTTP draft](https://http-spec.graphql.org/draft/): request and response media types and status codes. The Fetch standard's "CORS protocol" section defines simple requests and preflight.
- [OWASP GraphQL Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html): "Introspection + GraphiQL", "Don't Return Excessive Errors".
- [OWASP Cross-Site Request Forgery Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html): "Disallowing simple content types", the rule behind the content-type guard.
- Quarkus: [TLS registry reference](https://quarkus.io/guides/tls-registry-reference), [HTTP reference](https://quarkus.io/guides/http-reference) for CORS, limits and headers, and the [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) for `schema-available`.
- Python: Strawberry [DisableIntrospection](https://strawberry.rocks/docs/extensions/disable-introspection) and [schema configuration](https://strawberry.rocks/docs/types/schema-configurations), uvicorn [settings](https://uvicorn.dev/settings/) for the SSL options, and the FastAPI guide to [CORS](https://fastapi.tiangolo.com/tutorial/cors/).
