# Ch17 - Transport security and introspection control

Both stacks serve the tracking view over HTTPS only, from framework configuration: the Quarkus TLS
registry and uvicorn's `--ssl-*` options. Each stack's image is deployed twice. The **public**
instance (Quarkus 8270, Python 8271) is hardened: introspection, field suggestions, the IDE and GET
queries are off. The **internal** instance (Quarkus 8272, Python 8273) leaves introspection on, and
it is the one `verify.sh` diffs against the canonical SDL. Certificates are generated at run time
and never committed. `verify.sh` asserts the protocol floor on each stack, HSTS, introspection,
suggestions, the IDE, the CSRF content types, CORS and the size limits.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. Every instance serves everything in it
except `Subscription`, which Chapter 21 builds: the schema, seed, cursors, error contract and
`finalArrivalTime` deprecation are Chapter 13's. This example does not repeat Chapter 14's depth and
cost limits; production would. The contract check (`assert_sdl_conforms`) runs against the internal
instances, because a public instance refuses introspection.

## Run it

```bash
bash examples/17-transport-security/verify.sh
```

`verify.sh` generates a CA and a server certificate into a scratch directory with `gen-certs.sh`,
brings the four services up with `docker compose`, runs the cases below in a fixed order on both
stacks, diffs each internal schema against `contracts/schema/` and tears the stack down. It prints
`PASS` only if every check holds. It needs Docker Engine with the `docker compose` plugin, `openssl`
and Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand, generate the certificates once (the `certs/` directory is git-ignored):

```bash
examples/17-transport-security/gen-certs.sh examples/17-transport-security/certs
docker compose -f examples/17-transport-security/compose.yaml up -d --build
curl -s --cacert examples/17-transport-security/certs/ca.crt https://localhost:8270/graphql \
  -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}'
docker compose -f examples/17-transport-security/compose.yaml down -v
```

The certificates are valid for two days. The server certificate carries the names `localhost`,
`quarkus`, `python`, `quarkus-internal`, `python-internal` and `127.0.0.1`. The key file is mode 0644
because the containers read it as uid 185 and 1001; it is a lab fixture, and a real key is never
committed or world-readable. `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it) serves
`/debug/source-calls` on every instance, which `verify.sh` uses to show that a refused request made
no source call; leave it off outside the lab.

## Ports

| Instance | Container | Host | Settings |
|---|---|---|---|
| Quarkus, public | 8443 | 8270 | `TRACKING_INTROSPECTION_ENABLED=false` |
| Python, public | 8443 | 8271 | `TRACKING_PUBLIC=true` |
| Quarkus, internal | 8443 | 8272 | introspection on |
| Python, internal | 8443 | 8273 | `TRACKING_PUBLIC=false` |

Compose project `gql-ch17-transport`, containers `ch17-transport-*`. The two instances of a stack
share one image (`gql-ch17-transport-quarkus:local`, `gql-ch17-transport-python:local`); compose
builds it once. Telemetry is off by default. Add the observability file (`docker compose -f
compose.yaml -f compose.observability.yaml up --build`) to send it to LGTM, which publishes the
fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so run one example's observability stack at
a time.

## On the wire

Each value below is asserted by `verify.sh` against both stacks, with `LGTM_CACERT` set to the
generated CA unless the row says otherwise.

| Case | Request | Quarkus | Python |
|---|---|---|---|
| TLS verified | `{ __typename }` over https, all four instances | `Query` | `Query` |
| no CA | the same request without `--cacert` | curl exit 60 | curl exit 60 |
| name check | `--resolve <stack>:<port>:127.0.0.1` and `https://<stack>:<port>/` | 200 | 200 |
| wrong name | `https://wrong.example` | curl exit 60 | curl exit 60 |
| plain http | `http://localhost:<port>` | curl exit 52 | curl exit 52 |
| TLS 1.3 client | `--tlsv1.3` | 200 | 200 |
| TLS 1.2 client | `--tlsv1.2 --tls-max 1.2` | handshake fails (curl exit 35) | 200 |
| HSTS | any response | `strict-transport-security: max-age=31536000` | the same |
| introspection, public | `{ __schema { queryType { name } } }`, `{ __schema { __typename } }` | error `Introspection has been disabled for this request`, no `data` | error `GraphQL introspection has been disabled`, `data` null |
| introspection, public | `{ __type(name: "Cargo") { __typename } }` and the same for `NoSuchType` | the same error for both, no type information | the same error for both |
| validation probe, public | `... on Cargo` and `... on NoSuchType` in a fragment | a spread error naming `Cargo`; `Unknown type` | the same two messages |
| meta field | `{ __typename }` on public | `Query` | `Query` |
| introspection, internal | `__schema`, `__type(name: "Cargo")` | `Query`, `Cargo` | the same |
| suggestions | `cargo(trackingId: "ABC123") { trackingI }` | ``Field 'trackingI' in type 'Cargo' is undefined``; no `Did you mean` on public or internal | public: ``Cannot query field 'trackingI' on type 'Cargo'.``; internal adds ``Did you mean 'trackingId'?`` |
| schema document | `GET /graphql/schema.graphql` | 404 on both instances (build-time setting) | 404 |
| IDE | `GET /graphql`, `Accept: text/html`, public | 406, no HTML | 404, no HTML |
| IDE, internal | the same | 406 | 200, GraphiQL page |
| CSRF | POST of the mutation JSON as `text/plain`, `application/x-www-form-urlencoded`, `multipart/form-data` | 415 | 400, body contains `Unsupported content type` |
| CSRF | the same with the `Content-Type` header removed | 415 | 400 |
| no write | the source-call log after each refused request | 0 calls | 0 calls |
| GET | `GET ?query=mutation...`; `GET ?query={ __typename }` on public | 405; 405 | 400; 400 |
| GET, internal | `GET ?query=mutation...` | 405 | 400 |
| control | `Content-Type: application/json; charset=utf-8` | 200 | 200 |
| CORS | preflight, `Origin: https://tracking.example.com`, `Access-Control-Request-Method: POST` | `access-control-allow-origin: https://tracking.example.com`, methods `POST` | the same |
| CORS | preflight from `https://evil.example` | 403, no `access-control-allow-origin` | 400, no `access-control-allow-origin` |
| CORS | actual POST with `Origin: https://evil.example` | 403, no source call | 200, the app answers |
| CORS credentials | the allowed-origin preflight | `access-control-allow-credentials: true` | header absent |
| size | POST of a 100 KB body (a comment in a valid query) | 413 | 200, `Query` (limit set at a fronting proxy) |
| tokens | POST of a 16000-token list in a 32 KB body | 200, error `Unparseable input document` | 200, error `Document contains more than 5000 tokens` |
| masked errors | `cargo(trackingId: "GHI345")` on public | `SERVICE_UNAVAILABLE`, `booking service unavailable` | the same |
| write | register `UNLOAD` for `ABC123` as `application/json` on public | `evt_10`: the refused attempts wrote nothing | the same |
| schema | internal instances | conforms to `contracts/schema/`; only `Subscription` unserved; `finalArrivalDate` deprecated | the same |

## Code-first notes

Checked on the pinned versions (SmallRye GraphQL 2.18.5 on graphql-java 25.0, Quarkus 3.40.1;
Strawberry 0.335.0 on graphql-core 3.3.0, uvicorn 0.54.0).

**`assert_sdl_conforms` over https.** `graphql-inspector` reads the internal instances over TLS when
`LGTM_CACERT` is set (the harness exports it as `NODE_EXTRA_CA_CERTS`) and passes on both stacks.
Without the variable it fails with `unable to verify the first certificate`.

**JSON bodies only.** A GraphQL endpoint should accept only JSON request bodies. The GraphQL-over-HTTP
draft recommends 415 for an unsupported Content-Type, and the OWASP CSRF cheat sheet recommends
disallowing simple content types, because a browser sends `text/plain`, form-encoded and multipart
POSTs cross-origin without a preflight. `ContentTypeGuard` is a Vert.x filter registered through
Quarkus's `Filters` event; it answers 415 for any POST to `/graphql` that is not `application/json` or
`application/graphql-response+json`.
On Python, Strawberry's content-type check answers `400 Unsupported content type`.

**Introspection.** `IntrospectionSwitch` turns it off with graphql-java's `Introspection.enabledJvmWide(false)`,
called at startup when `tracking.introspection.enabled` is false (`TRACKING_INTROSPECTION_ENABLED=false`
on the public instance; each instance is its own JVM). `__schema` and `__type` are then refused with
`Introspection has been disabled for this request` and no `data` key, a real and an unknown type name
answer identically, and `__typename` still answers. Strawberry's `DisableIntrospection` reports each
introspection field it finds by name and sends `"data": null`.

**Suggestions.** graphql-java's `FieldUndefined` message never suggests a name, so there is nothing to
switch off on Quarkus. graphql-core's `Did you mean` is on by default; `disable_field_suggestions` in
`StrawberryConfig` removes it.

**The IDE.** Strawberry serves GraphiQL for `GET /graphql` with `Accept: text/html` unless
`graphql_ide=None`; on the public instance the same request answers 404 `Not Found`. SmallRye's UI is
not part of a production build (`ui.always-include` is false), and `GET` is off, so the same
request answers 406.
`schema-available=false` is a build-time property: the schema document is off on both Quarkus
instances.

**Token limits differ.** On Quarkus the parser applies graphql-java's default operation limit of 15000 tokens, and `verify.sh` asserts the 16000-token body. Python sets
`MaxTokensLimiter(max_token_count=5000)`.

**Body size.** `quarkus.http.limits.max-body-size=64K` answers 413 before the body is parsed. Over
HTTP/2, which curl negotiates by default with ALPN, `verify.sh` sends that case with `--http1.1` so
the 413 arrives as a plain response. On Uvicorn the body limit is set at a fronting proxy
(`client_max_body_size` in nginx).

**TLS floors.** The Quarkus TLS registry defaults to TLS 1.3 only (`quarkus.tls.protocols`). uvicorn
passes the key and certificate to Python's `ssl` module, whose default minimum is TLS 1.2.

**CORS.** Quarkus answers a preflight from an unknown origin with 403 and Python's `CORSMiddleware`
with 400. Neither sends `access-control-allow-origin`. Quarkus also sends
`access-control-allow-credentials: true` for the allowed origin and Python sends no such header;
`verify.sh` asserts both.

**Two instances, one image.** Compose builds the first service of each pair and starts the second from
the same image name with `pull_policy: never` and `depends_on`; one build serves both.

**Strawberry notes.** Extensions are passed as factories (`functools.partial`) or classes, so each
request gets its own instance (an instance is deprecated in 0.335.0). `schema_for(public)` in
`app/schema.py` builds the two variants.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/17-transport-security-architecture.py`) show the compose topology: a client
that trusts only the generated CA, the four instances, the certificates mounted from a scratch
directory, the two internal instances diffed against the canonical SDL, and the opt-in `compose.observability.yaml` override.
