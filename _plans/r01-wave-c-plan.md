---
layout: plan
render_with_liquid: false
title: "r01 Wave C Plan — Ch14–Ch18 (Performance & Safety, Security)"
---

# Wave C (S8): Ch14–Ch18, Performance & Safety and Security

**Status: DONE 2026-10-16; Ch14–18 verified, CI green at ef6f8ce. APPROVED by user 2026-10-16. §8 decisions 1 and 2 as recommended (hand-written cost extension and persisted-document code, each commented as the deliberate exception), decision 3 nginx UBI (`ubi10/nginx-126:10.1-1779165744`), decisions 4–8 as recommended. The upstream SmallRye issue on client `extensions` is drafted in `_plans/upstream/`.**

This plan is written for Sonnet executors. Where it gives a value (a port, an id, a cost number, a config key, an error code, a message, a path or an image tag), use exactly that value. Where it says **spike**, check the behaviour on the pinned versions before writing any prose that depends on it, and record what you observe in the example README under "Code-first notes". If a spike contradicts an expected value in this plan, assert what you observed, rewrite the prose to match, and report it. Never weaken an assertion without saying so.

**Precondition.** S7 (Wave B) is done: Ch0 and Ch3–Ch13 are `verified`, CI is green at `f1aff13`, and the wrap commit is `4695122`. Wave C starts from `examples/13-dataloaders/`.

**Facts checked against the local jars and wheels, and against registries (2026-10-16).** These are inputs to the plan. Anything still marked *spike* has not been run.

- **Quarkus 3.40.1 `quarkus-smallrye-graphql` runtime config** (from `META-INF/quarkus-config-doc`):
  - `instrumentation-query-depth` (OptionalInt; the model reports a default of 20, **spike**);
  - `instrumentation-query-complexity` (OptionalInt, no default). Its javadoc says it aborts when "the total number of data fields queried exceeds the defined limit";
  - `parser-max-tokens` (default 15000) and `parser-max-whitespace-tokens` (default 200000);
  - `field-visibility` (default `default`). The special value `no-introspection` disables the introspection fields;
  - `http.get.enabled` (default **false**) and `http.post.queryparameters.enabled` (default false);
  - `schema-available` (default true, **build-time fixed**), `ui.enabled`, `ui.always-include` (default false), `log-payload`, `exclude-null-fields-in-responses`.
- **SmallRye 2.18.5 `ExecutionService.getGraphQL()`** builds a `ChainedInstrumentation` in this order:
  1. `MaxQueryComplexityInstrumentation(int)`, if configured, using graphql-java's default per-field calculator;
  2. `MaxQueryDepthInstrumentation(int)`, if configured;
  3. its own `QueryCache`;
  4. federation tracing, if enabled.

  It then sets `preparsedDocumentProvider(queryCache)` and fires `EventEmitter.fireBeforeGraphQLBuild(GraphQL.Builder)`, which reaches CDI as `@Observes GraphQL.Builder`, before `build()`. `GraphQL.Builder` has no getters. `GraphQL#getInstrumentation()` is public.
- **SmallRye has no persisted-query or APQ support** (no class or string in `smallrye-graphql`, `-cdi`, `quarkus-smallrye-graphql` or `-deployment`). Two details block graphql-java's own APQ support:
  - `ExecutionService.execute` sends `"Missing 'query' field in the request"` when `query` is null or empty, before graphql-java runs;
  - it never calls `ExecutionInput.Builder.extensions(...)`. The client's extensions are kept only in `SmallRyeContext#getExtensionsFromClient()` and `getRequest()`.

  The Quarkus HTTP handler (`SmallRyeGraphQLExecutionHandler`) behaves as follows:
  - `handlePost` answers 400 with the plain text `Missing operation body` when there is no `query`;
  - it JSON-merge-patches URL query parameters over the body when `allowPostWithQueryParameters` is on;
  - `handleGet` needs a `query` parameter and answers 405 when GET is disabled;
  - the body is parsed as a single JSON object, so an array (a batch) is not supported (the exact response is a **spike**).
- **graphql-java 25.0** ships:
  - `graphql.execution.preparsed.persisted.ApolloPersistedQuerySupport`, which reads `ExecutionInput.getExtensions().persistedQuery.sha256Hash`;
  - `PersistedQueryNotFound` (message `PersistedQueryNotFound`);
  - `InMemoryPersistedQueryCache`;
  - `PersistedQuerySupport.PERSISTED_QUERY_MARKER = "PersistedQueryMarker"`;
  - `MaxQueryComplexityInstrumentation(int, FieldComplexityCalculator)`. `FieldComplexityEnvironment#getArguments()` returns the resolved arguments, and `getFieldDefinition()` is available;
  - `MaxQueryDepthInstrumentation(int[, Function<QueryDepthInfo,Boolean>])`, which counts introspection depth (**spike** for the numbers);
  - `NoIntrospectionGraphqlFieldVisibility`, `GoodFaithIntrospection` (on by default; the cause of Wave B's BadFaithIntrospection) and `IntrospectionDisabledError`.
- **SmallRye CDI events** (`io.smallrye.graphql.cdi.event`): `@BeforeExecute`, `@AfterExecute`, `@BeforeDataFetch`, `@AfterDataFetch`, `@ErrorDataFetch`, `@ErrorExecute`. `fireAfterExecute` runs before the response is written (`notifyAndWrite`).
- **Quarkus 3.40.1 `quarkus-vertx-http` config:**
  - `quarkus.http.cors.enabled` (default false), `.origins`, `.methods`, `.headers`, `.access-control-max-age`;
  - `quarkus.http.limits.max-body-size` (default 10240K);
  - `quarkus.http.insecure-requests`, `quarkus.http.ssl-port` (default 8443), `quarkus.http.tls-configuration-name`;
  - `quarkus.http.header."<name>".value` / `.path` / `.methods`;
  - `quarkus.http.filter."<name>".header."<h>"` / `.matches` / `.methods` / `.order`;
  - `quarkus.http.auth.proactive` (default true) and `quarkus.http.auth.permission."<p>".*`.
- **`quarkus-tls-registry` 3.40.1:** `quarkus.tls.key-store.pem."<name>".cert` and `.key`, and `quarkus.tls.protocols`, whose **default is `TLSv1.3` only**.
- **`quarkus-oidc` 3.40.1:** `quarkus.oidc.auth-server-url`, `application-type` (default `service`), `discovery-enabled` (default true), `jwks-path`, `token.issuer`, `token.audience`, `roles.role-claim-path`, `connection-delay`.
- **`quarkus-cache` 3.40.1:**
  - annotations `@CacheResult`, `@CacheInvalidate`, `@CacheInvalidateAll`, `@CacheKey`, `@CacheName`;
  - programmatic `Cache#get/getAsync/invalidate/invalidateIf`, plus `CaffeineCache#getIfPresent/put/keySet/setExpireAfterWrite/setMaximumSize`;
  - config `quarkus.cache.caffeine."<cache>".maximum-size`, `.expire-after-write`, `.expire-after-access`.

  `quarkus-redis-cache` 3.40.1 is also present (not used; see §8 decision 4).
- **Strawberry 0.335.0:**
  - **Extensions:** `QueryDepthLimiter(max_depth, callback, should_ignore)` ignores `__*` fields and reports `'<op>' exceeds maximum operation depth of <n>`; `MaxAliasesLimiter(max_alias_count)` reports `<n> aliases found. Allowed: <max>`; `MaxTokensLimiter(max_token_count)` sets graphql-core's `max_tokens`; `DisableIntrospection` (graphql-core `NoSchemaIntrospectionCustomRule`); `AddValidationRules`; `ParserCache`; `ValidationCache`; `MaskErrors`; `SchemaExtension`. **There is no cost limiter and no persisted-query extension.**
  - **Passing an extension *instance* is deprecated at 0.335.0.** `Schema.__init__` emits a DeprecationWarning (strawberry issue #4369), and the fix is to pass a class or a factory so that each request gets its own instance.
  - **Extension order:** `Schema.execute` runs `extensions_runner.operation()` **before** `_prepare_operation_async`, which raises `MissingQueryError` when `query` is empty. The HTTP layer accepts `query: null` and keeps `extensions` (its comment reads: "query is optional here as it can be added by an extensions (for example an extension for persisted queries)"). `ExecutionContext.operation_extensions` carries the request's `extensions`.
  - **Exceptions in `on_operation`:** an exception raised there before `yield` becomes a `PreExecutionError` (no data); `MissingQueryError`, `CannotGetOperationTypeError` and `InvalidOperationTypeError` re-raise to the HTTP layer as 400.
  - **`StrawberryConfig`:** `disable_field_suggestions: bool = False`, and `batching_config: BatchingConfig | None = None`. With it unset, an array body answers `400 "Batching is not enabled"`; when set, `max_operations` is enforced as `400 "Too many operations"`.
  - **`BasePermission`:** has `message`, `error_extensions`, `error_class` (default `StrawberryGraphQLError`) and `on_unauthorized()`. A `GraphQLError` raised in a resolver is masked by Ch9's `should_mask` unless the predicate allows it (Wave B fact), so the permission classes override `on_unauthorized` to raise `ExposedError` subclasses.
  - **Context:** `strawberry.fastapi.BaseContext` has `request`, `response` and `background_tasks`. Ch13's `TrackingContext` already extends it.
- **Registries (latest stable, 2026-10-16):**
  - Keycloak `quay.io/keycloak/keycloak:26.8.1` (UBI-based, Apache-2.0);
  - Valkey `docker.io/valkey/valkey:9.0.6` (9.2 is RC; BSD-3);
  - nginx UBI `registry.access.redhat.com/ubi10/nginx-126:10.1-1779165744` (newest UBI nginx; upstream nginx stable is 1.30.6);
  - Varnish official `docker.io/library/varnish:9.1.0`;
  - PyPI: PyJWT 2.15.1 (MIT), cryptography 50.0.2, authlib 1.9.1 (BSD-3), cachetools 7.2.2 (MIT), valkey-py 6.2.0 (MIT);
  - UBI `python-314-minimal` has newer tags than the pinned `10.2-1791928506`, which is **not** bumped inside the wave (see §1).
- **Books.** DDIA 2nd ed. (2026): Ch1 is "Trade-offs in Data Systems Architecture" (confirmed; it contains the systems-of-record and derived-data discussion). The Wave B validators verified Ch2 "Defining Nonfunctional Requirements". The other titles are **spikes** (§2 citations).
- The site has 43 figures. Wave C adds 16, for a total of 59.

---

## 1. Approach

### Sequencing (DAG)

| Step | Executor | Owns (exclusive write set) | Depends on |
|---|---|---|---|
| **C0** Harness + CI | Executor 1 | `examples/_lib/lib.sh`, `examples/_lib/README.md`, `.github/workflows/contracts.yml` (the `examples` job's `timeout-minutes` only) | S7 |
| **C1** Ch14 Depth limits and query cost analysis | Executor 2 | `_docs/14-*`, `examples/14-query-cost/**`, `diagrams/14-*.py`, `diagrams/examples/14-*`, `assets/diagrams/14-*` | C0 (copies Ch13) |
| **C2** Ch15 Persisted queries and APQ | Executor 3 | same pattern for `15-*` | C0 (copies Ch13) |
| **C3** Ch16 Caching | Executor 3 (after C2) | `16-*` | C2 (copies Ch15) |
| **C4** Ch17 Transport security and introspection control | Executor 4 | `17-*` | C0 (copies Ch13) |
| **C5** Ch18 AuthN and AuthZ | Executor 5 | `18-*` | C0 (copies Ch13) |
| **CV1…CV5** Validation (Opus), one per chapter | Opus | read-only findings; fixes routed to the owning executor | the chapter's step |
| **CW** Wrap (orchestrator) | orchestrator | `_plans/*`, `_example_pages/index.md`, commits, coverage-matrix flips, the deliberate one-clause fixes in §4 | CV1–CV5 + CI green |

How to run it:
- After C0, run C1, C2, C4 and C5 in parallel (four executors). C3 starts when C2's checkpoint lands. The critical path is three content-bearing steps, C0 → C2 → C3; everything else runs beside it.
- Ch14, Ch17 and Ch18 do not depend on one another or on Ch15/16. Each copies the Ch13 example, which is the newest verified code, carries Ch9's error machinery and Ch13's batching, and serves the whole SDL except `Subscription`. Ch15 copies Ch13 too: persisted documents need no cost limits. Ch16 copies Ch15, because the HTTP cache needs Ch15's GET and hashed-query URLs.
- **Self-contained limits.** Ch15–18 do not carry Ch14's limits. Each chapter's README states this in its slice paragraph ("this example does not repeat Chapter 14's limits; production would"). Wave A/B already set this pattern of one concern per example.
- Each CVn starts as soon as its chapter's checkpoint commit lands.
- At most two repair rounds per chapter. A third failure goes back to the user.

**Executor rules (unchanged from Waves A and B, binding)**
- Write files only. No git.
- Do not touch:
  - `_plans/*`, `coverage-matrix.md`, `_example_pages/`, `scripts/`, `contracts/` (no SDL changes in Wave C, §8 decision 7);
  - `examples/_lib/` (only C0 may);
  - any other chapter's files, including every verified Ch0–Ch13 file.
- Never delete or reinstall `contracts/node_modules`.
- Never `pkill -f` patterns while other executors' stacks run. Five stacks plus Keycloak run concurrently, so stop only your own stack with `docker compose -p <your project> down -v`.
- Before handing back, every executor:
  - runs its own `verify.sh` green;
  - runs `python3 -I scripts/validate.py; echo rc=$?` (do not pipe through `tail`, §9 Wave B);
  - runs `bash scripts/wordcount.sh _docs/NN-*.md`;
  - runs `npm --prefix contracts run lint`;
  - renders every new figure to PNG and **views** it.

**Orchestrator rule.** At each chapter's checkpoint commit, flip that chapter to `draft` in **both** the Topics table (T15–T19) and the Full chapter inventory, **in the same commit** as the chapter. Then push, so that CI runs `verify: NN-*`, the wordcount GATE and `validate.py` against it. A chapter is "verified" only after CVn passes **and** the CI `verify: NN-*` job is green.

**Rejected alternatives (one line each)**
- *A serial Ch14 → Ch18 chain*: it is two steps longer, and the only real dependency is Ch16 on Ch15's GET/hash surface.
- *Ch15–18 built on Ch14*: it couples the limits to every later assertion (introspection depth, alias counts in Ch18 queries) and blocks parallelism.
- *A GraphQL gateway for APQ (Hive Gateway in proxy mode)*: a Node image, Ch20's tool, and an extra moving part for a two-line protocol. Apollo Router is Elastic-licensed, so it is not OSS.
- *Valkey in Ch16*: one replica per stack does not need a shared cache, and the multi-replica case belongs to S11 (§8 decision 4).
- *TLS terminated at a proxy in Ch17*: it hides each framework's own TLS configuration, which is the lesson. The proxy option is taught in prose, and S11 may use it.
- *A `viewer` root field or a `Cargo.shipper` field for Ch18*: the SDL would change to express a rule that lives outside it (Ch5:145). Ownership stays private data, like `bookedAt` in Ch12.
- *graphql-java `instrumentation-query-complexity` as the cost model*: it counts every field as 1, ignores `first`/`ids`, and counts introspection fields. Ch14 shows it and explains why the example does not use it.
- *A hand-written Strawberry cost **validation rule***: validation rules do not see variable values, so `first: $n` could not be costed. The cost check runs in `on_execute` instead (§8 decision 1).

### Example structure

Same as Waves A and B: a self-contained copy per chapter, with package `com.patterncatalyst.shipping.tracking` and Python package `app`. For each chapter, change:
- the artifactId `chNN-quarkus-<slug>`;
- the Python project name `shipping-python-chNN-<slug>`, then **re-run `uv lock`**;
- `quarkus.otel.service.name` / `OTEL_SERVICE_NAME` = `chNN-<slug>-quarkus|python`;
- the container names and the compose `name:`.

Add `python/.ruff_cache/` to each new `.gitignore`. Ch17 also ignores `certs/`.

**Pins** are identical to Wave B: Quarkus platform 3.40.1; Strawberry 0.335.0, FastAPI 0.143.2, uvicorn 0.54.0, uv 0.13.1, pydantic-settings 2.16.0; the OTel pins as in Ch13; `ubi10/openjdk-25:1.24-16` / `-runtime:1.24-16`; `ubi10/python-314-minimal:10.2-1791928506`; `grafana/otel-lgtm:0.36.0`. If a newer stable release exists at execution time, **do not** bump it inside Wave C. Record it in the RESUME POINTER for a separate all-examples chore.

**New pins in Wave C**

| Chapter | Addition | Pin |
|---|---|---|
| 15 | `io.quarkus:quarkus-cache` (persisted-document store) | platform 3.40.1 (BOM) |
| 15, 16 | `cachetools` (Python) | `cachetools==7.2.2` |
| 16 | HTTP cache | `registry.access.redhat.com/ubi10/nginx-126:10.1-1779165744` (§8 decision 3) |
| 18 | `io.quarkus:quarkus-oidc` | platform 3.40.1 (BOM) |
| 18 | JWT validation (Python) | `pyjwt[crypto]==2.15.1` (uv.lock pins `cryptography` 50.0.2) |
| 18 | IdP | `quay.io/keycloak/keycloak:26.8.1` |

**Strawberry extensions are factories in every Wave C chapter.** Write `extensions=[functools.partial(MaskErrors, should_mask_error=should_mask, error_message="Internal server error."), …]`, and do the same for every configured extension. A bare class is fine when it needs no arguments. Ch9–Ch13 still pass an instance and emit the 0.335.0 DeprecationWarning. **Do not edit them.** CW records this in the RESUME POINTER for the all-examples chore (Pitfall C-1).

### How the schema slice grows

| Ch | Base | Adds to the served slice | Behaviour added |
|---|---|---|---|
| 14 | Ch13 | nothing | depth limit, token limit, alias limit (Python), a list-aware cost budget on both stacks, and batch-array refusal; every attack is rejected before any source call |
| 15 | Ch13 | nothing | Apollo APQ (hash handshake, `PersistedQueryNotFound`), a trusted-document allowlist mode, GET enabled on Quarkus, persisted documents usable over GET |
| 16 | Ch15 (APQ mode only) | nothing | `Cache-Control` per response, an nginx HTTP cache in front of each stack, field-level source caches with TTL and invalidation on `registerHandlingEvent` |
| 17 | Ch13 | nothing | in-process TLS with certificates generated at verify time, hardened public vs internal instances (introspection, suggestions, IDE, GET), CORS, content-type/CSRF checks, body/token limits, HSTS |
| 18 | Ch13 | nothing | Keycloak-issued JWTs, operation-level authentication, object-level ownership (a shipper sees only its cargos), field-level `HandlingEvent.registrationTime` for operators, `UNAUTHENTICATED`/`FORBIDDEN` codes, 401 for bad tokens |

Every Wave C stack serves the Ch13 slice: the whole canonical SDL except `Subscription` (Ch21), with `finalArrivalDate` deprecated. `assert_sdl_conforms` and `assert_deprecated` run on every stack against an instance that allows introspection. That instance is the APQ instance in Ch15, the internal instance in Ch17, and the anonymous caller in Ch18.

### Canonical SDL changes

**None** (§8 decision 7). Ownership, roles, costs and cache policy live outside the SDL, as Ch5:145 promised. The `contracts/` diff for Wave C must be empty. Because no SDL changes, no step re-runs the older `verify.sh` scripts for conformance, but CW still runs all of them concurrently (§4).

### Canonical seed data additions

- **Ch14–Ch17:** the Ch13 seed unchanged: the Ch12 table (VWX901, XYZ789, STU678, DEF456, ABC123, GHI345 with the `booking service unavailable` fault), the DEF456 events `evt_3`–`evt_9`, and ABC123's `evt_1`/`evt_2`. The first new registration is `evt_10`.
- **Ch18:** the Ch13 seed plus a private **`owner`** on each booking record, stored in the booking index and never in the schema:

  | trackingId | owner |
  |---|---|
  | VWX901, DEF456, ABC123 | `ACME` |
  | XYZ789, STU678, GHI345 | `GLOBEX` |

- **Ch18 users** in the committed realm `examples/18-authn-authz/keycloak/shipping-realm.json`. The passwords are test fixtures, and the README says so.

  | username | password | realm roles | `shipper` claim |
  |---|---|---|---|
  | `ana` | `ana-fixture-pw` | `shipper` | `ACME` |
  | `bo` | `bo-fixture-pw` | `shipper` | `GLOBEX` |
  | `ops` | `ops-fixture-pw` | `operator` | *(none)* |

  Clients:
  - `tracking-cli`: public, direct access grants enabled for the lab, with an audience mapper adding `tracking-api` and a user-attribute mapper for `shipper`;
  - `other-cli`: public, direct grants, **no** audience mapper, used for the wrong-audience case.

  Realm settings: `accessTokenLifespan: 600`, `sslRequired: "none"` (lab only, stated).

### Error codes (Wave B's codes plus these) — identical strings on both stacks

| `extensions.code` | Raised for | Message (exact) | Ch |
|---|---|---|---|
| `PERSISTED_QUERY_NOT_FOUND` | a hash the server does not know (no query sent) | `PersistedQueryNotFound` (Apollo's text) | 15, 16 |
| `PERSISTED_QUERY_REQUIRED` | query text that is not in the manifest (trusted mode) | `only persisted documents are accepted` | 15 |
| `BAD_USER_INPUT` | the query and the hash disagree | `provided sha does not match query` | 15 |
| `UNAUTHENTICATED` | an anonymous caller reaching an authenticated operation | `authentication required` (Quarkus: **spike** (C5-a); assert the observed message if SmallRye cannot carry this one, and keep the code identical) | 18 |
| `FORBIDDEN` | a caller without the role (`registrationTime`, `registerHandlingEvent`) | `operator role required` (same spike) | 18 |
| *(no code)* | depth/token/alias limits and batch refusal | each engine's own message; request-level rejections get no code, as in Wave B | 14 |
| *(no code)* | the cost budget | `maximum query complexity exceeded <cost> > 1000`. This is graphql-java's text; the Python extension reproduces it byte for byte (spike C1-c confirms the exact format) | 14 |

**HTTP-level (not GraphQL errors).**
- A bad or expired bearer token, or one for the wrong audience, gets `401` plus `WWW-Authenticate: Bearer …` on both stacks (Ch18).
- A refused batch array gets `400` (Python `Batching is not enabled`; Quarkus observed, spike C1-e).
- A body that is too large gets `413` (Quarkus, Ch17).

### Ports, project names, extra services

**Rule:** chapter N owns host ports **8100+10·N … 8100+10·N+9**: Quarkus +0, Python +1, extra services +2…+9. This cannot collide with any existing chapter (0 and 3–13 use 8080/8081 and 8130–8231) or with another Wave C chapter. Internal-only services publish no host port. The block 8200–8209 is Ch10's (it is also HashiCorp Vault's default; already noted there). Container ports are 8080, plus 8443 for TLS in Ch17.

| Ch | dir | Quarkus | Python | extras (host → container) | compose `name:` / `PROJECT` | container prefix | artifactId / Python project |
|---|---|---|---|---|---|---|---|
| 14 | `14-query-cost` | 8240 | 8241 | — | `gql-ch14-query-cost` | `ch14-query-cost-` | `ch14-quarkus-query-cost` / `shipping-python-ch14-query-cost` |
| 15 | `15-persisted-queries` | 8250 (APQ) | 8251 (APQ) | 8252 Quarkus trusted → 8080; 8253 Python trusted → 8080 | `gql-ch15-persisted` | `ch15-persisted-` | `ch15-quarkus-persisted` / `shipping-python-ch15-persisted` |
| 16 | `16-caching` | 8260 | 8261 | 8262 → nginx:8080 (→ quarkus); 8263 → nginx:8081 (→ python) | `gql-ch16-caching` | `ch16-caching-` | `ch16-quarkus-caching` / `shipping-python-ch16-caching` |
| 17 | `17-transport-security` | 8270 → 8443 (public, hardened) | 8271 → 8443 (public, hardened) | 8272 → 8443 Quarkus internal; 8273 → 8443 Python internal | `gql-ch17-transport` | `ch17-transport-` | `ch17-quarkus-transport` / `shipping-python-ch17-transport` |
| 18 | `18-authn-authz` | 8280 | 8281 | 8282 → keycloak:8080 (management port 9000 not published) | `gql-ch18-authn-authz` | `ch18-authn-authz-` | `ch18-quarkus-authn-authz` / `shipping-python-ch18-authn-authz` |

- In Ch15 and Ch17, the second instance per stack reuses the stack's image. Define the build on the first service with `image: gql-ch15-persisted-quarkus:local`; the second service uses the same `image:` with different environment. Spike: compose builds once and starts both.
- The observability profile is copied verbatim, with the note "one example's observability profile at a time" (its 3000/4317/… ports are shared by design).
- **CI and resources.** `ubuntu-latest` (4 vCPU, 16 GB) runs one example per job. Keycloak `start-dev --import-realm` needs about 600 MB and 15–40 s.
  - Ch18's compose gives Keycloak a healthcheck with `start_period: 30s, interval: 5s, retries: 30`, and makes both apps `depends_on: keycloak: condition: service_healthy`.
  - verify.sh calls `wait_for_http http://localhost:8282/realms/shipping 180`.
  - C0 adds `timeout-minutes: 45` to the `examples` job, which covers three attempts with Keycloak pulls.
  - Locally, all Wave C stacks plus Ch0/Ch3–Ch13 must run concurrently. That is about 32 app containers, Keycloak and nginx; acceptance §4 checks it.

---

## 2. Per chapter

**Common to every chapter** (as in Waves A and B):
- **Front matter:**
  - `title` (Ch14 "Depth limits and query cost analysis", Ch15 "Persisted queries and APQ", Ch16 "Caching", Ch17 "Transport security and introspection control", Ch18 "AuthN and AuthZ");
  - `order: N`;
  - `part:` exactly as in the Canonical names table ("Performance & Safety" for Ch14–16, "Security" for Ch17–18);
  - `description`;
  - `duration` (words/200).
- **Length and figures:**
  - 2,800–3,400 prose words (`wordcount.sh`);
  - figures via `{% include excalidraw.html file="NN-slug" alt="…full sentences…" caption="Figure N.M — …" %}`, **numbered by order of appearance**;
  - at least one `{% include codetabs.html langs="Quarkus|Python" %}` followed by a java fence and then a python fence.
- **Last three blocks:** `## On the wire` (curl lines and the exact values `verify.sh` asserts), then the Decision callout naming Ch2's axes, then `## Where this goes next`.
- **Prose rules:**
  - no `{{` or `{%` outside includes and fences;
  - cite books by **verified chapter title** only;
  - cite spec sections by **name**;
  - use the term "execution error";
  - never claim that a server log carries the GraphQL path or a request id (Wave B §9);
  - every Java/Python snippet in prose must exist in the example (Pitfall 27).
- **Diagram specs:** `diagrams/NN-slug.py`; architecture figures are `diagrams/examples/NN-slug-architecture.py` and do not count. Highlighted nodes use `accent`. Data-movement figures drawn from a run name that run in the spec docstring.
- **verify.sh skeleton:** Ch13's:
  - `run_stack_check <stack> <url> …` per stack, then `PASS`;
  - `source_calls_reset` before each counted case;
  - one `__type` per request (BadFaithIntrospection);
  - the scalar `kind`/`specifiedByURL` loop;
  - `assert_deprecated` for `finalArrivalDate`;
  - `assert_sdl_conforms` last;
  - the scratch dir cleaned via `on_exit`;
  - `ensure_contracts_tools` before any direct npm/npx.
- **README sections** (Ch13 order): The served slice, Run it, The source-call log (lab only), Ports, On the wire, Code-first notes (spike results), Diagram.

### Ch14: Depth limits and query cost analysis

**Files:** `_docs/14-depth-limits-and-query-cost.md`, `examples/14-query-cost/` (from Ch13).

**Learning goals.** By the end of the chapter the reader can:
- explain why a client-chosen shape needs bounds that REST endpoints do not;
- describe the amplification attacks (deep nesting, aliases, fragment fan-out, huge pages, token floods, batch arrays) and the text-to-work ratio of each;
- configure each stack's built-in limits (depth, tokens, aliases) and state where in the pipeline each fires;
- define a list-aware cost model (`first`/`last` and `len(ids)` as multipliers, introspection free) and compute it by hand;
- implement the same model on both stacks with each framework's extension point;
- show that every rejection happens before any source call;
- reason about budgets with DDIA's load and tail-latency vocabulary.

**H2 outline**
1. *The client chooses the bill.* Ch1's nested `cargos → handlingHistory → cargo → handlingHistory` query: 300 bytes, 385,151 cost units. Ch12's page cap and Ch13's batching bound calls per field, but not the selection. DDIA "Defining Nonfunctional Requirements" (describing load, response time, percentiles).
2. *Six ways to ask for too much.* Deep, wide (aliases), fragment fan-out, huge page, token flood, batch array (Figure 14.1). Each rejected case has zero source calls.
3. *Where each limit fires.* HTTP body → parse (tokens) → validate (Strawberry depth and aliases) → before execute (graphql-java depth and complexity instrumentation; the Strawberry cost extension) → resolver (Ch12's `BAD_USER_INPUT`) (Figure 14.2).
4. *Depth is not cost.* A 15-deep query of `first: 1` costs 15 and is rejected by depth. Ch1's 11-deep query costs 385,151 and passes depth. Two independent bounds.
5. *A cost model for this schema.* cost(field) = 0 for `__*` fields, otherwise `1 + m × Σ cost(children)`. m = `first` ?? `last` ?? 10 on `cargos` and `handlingHistory`, `len(ids)` on `nodes`, and 1 elsewhere (unpaginated lists such as `legs` are bounded by the domain and say so). Q_FAN = 53, worked through by hand (Figure 14.3).
6. *The budget and its boundary.* 1,000 units: `handlingHistory(first: 5)` under `cargos(first: 50)` costs 901 and runs; `first: 6` costs 1,051 and is rejected (Figure 14.4). How to pick a budget from measured p99 latency per unit.
7. *Cost on SmallRye: graphql-java's calculator.* What `instrumentation-query-complexity` counts (fields, each 1, introspection included) and why the example installs `MaxQueryComplexityInstrumentation` with a `FieldComplexityCalculator` through the `GraphQL.Builder` event, keeping SmallRye's own chain.
8. *Cost on Strawberry: an execution-phase extension.* No built-in cost limiter. A `SchemaExtension.on_execute` walk using graphql-core's `get_argument_values`, which sees variables, whereas validation rules cannot. The same numbers on both stacks.
9. *Aliases, fragments and tokens.* `MaxAliasesLimiter` on Python; on Quarkus, aliases are caught by cost. Fragment fan-out: analysers count each spread, the engine merges, so the estimate errs high, which is the safe side. Token limits protect the parser and the validator (OverlappingFieldsCanBeMerged).
10. *Batches of operations.* Strawberry's `batching_config` is off by default (and `max_operations` when it is on); SmallRye accepts one JSON object only.
11. *Caps that remain.* Ch12's 0..50 page cap still fires for `first: 51` (cost 154 passes the budget); `nodes` is bounded by cost, so 1,000 ids are rejected (Ch10's promise).
12. On the wire / Decision / Where this goes next (persisted documents, Ch15).

**Example design**
- **Quarkus** (`application.properties`):
  ```
  quarkus.smallrye-graphql.instrumentation-query-depth=12
  quarkus.smallrye-graphql.parser-max-tokens=5000
  tracking.query.max-cost=1000
  ```
  - `QueryCost.java`: `@ApplicationScoped`, constructor-injected with `@ConfigProperty(name="tracking.query.max-cost") int maxCost`. It holds:
    ```java
    void addCostLimit(@Observes GraphQL.Builder builder) {
        Instrumentation smallrye = builder.build().getInstrumentation();
        builder.instrumentation(new ChainedInstrumentation(List.of(smallrye,
            new MaxQueryComplexityInstrumentation(maxCost, new TrackingCostCalculator()))));
    }
    ```
    The comment explains that `GraphQL.Builder` has no getter, so the observer reads SmallRye's chain from a throwaway build and appends to it.
    - **Spike C1-a:** the observer fires (`events.enabled=true` is already set);
    - the built GraphQL's instrumentation is SmallRye's chain (depth and QueryCache) and is not double-wrapped;
    - depth rejections still fire first.

    If this approach fails, stop and report. Do not replace the chain blind.
  - `TrackingCostCalculator implements FieldComplexityCalculator`:
    - names starting `__` → 0;
    - `cargos`/`handlingHistory` → `1 + m * child`, with m from `env.getArguments()` `first`, else `last`, else 10;
    - `nodes` → `1 + ids.size() * child`;
    - otherwise `1 + child`.
  - `instrumentation-query-complexity` stays **unset**. The README shows what it would count (spike C1-b: set it to 60 on a scratch run, observe that Q_FAN's field count of 15 passes and that introspection is rejected; record the result).
- **Python** (`app/limits.py`, `app/schema.py`):
  ```python
  extensions=[
      partial(MaskErrors, should_mask_error=should_mask, error_message="Internal server error."),
      partial(MaxTokensLimiter, max_token_count=5000),
      partial(QueryDepthLimiter, max_depth=12),
      partial(MaxAliasesLimiter, max_alias_count=20),
      partial(QueryCostLimiter, max_cost=settings.max_query_cost),   # 1000
  ]
  ```
  - `QueryCostLimiter(SchemaExtension)`. `on_execute`, before `yield`, walks `execution_context.graphql_document`:
    - it uses the selected operation (`get_operation_ast(document, operation_name)`), a fragments map, `schema._schema` types, and `graphql.execution.values.get_argument_values(field_def, field_node, variables)`;
    - field definitions are looked up through `TypeInfo`-free recursion over FieldNode, InlineFragmentNode (type condition) and FragmentSpreadNode;
    - it implements exactly the formula above and raises `GraphQLError(f"maximum query complexity exceeded {cost} > {max_cost}")`.
  - **Spike C1-c:** an exception raised in `on_execute` before `yield` yields no data and no source calls; the message passes `should_mask` (`original_error` is None, so it is not masked; if it is masked, raise a `RequestLimitError(Exception)` that `should_mask` allowlists, without a code); and graphql-java's exact message format, which Python then mirrors.
  - `StrawberryConfig(batching_config=None)` stays the default (stated explicitly in a comment).
- Sources, batching, pagination and seed are unchanged from Ch13.
- **Spikes:**
  - **C1-d:** each engine's depth number for D_DEEP and for the inspector's introspection query. If depth 12 rejects `assert_sdl_conforms` on Quarkus, raise both stacks' limit to the smallest value that passes (≤ 15). Rebuild D_DEEP so that it still exceeds the limit, and explain in prose that graphql-java counts introspection depth while Strawberry skips it.
  - **C1-e:** Quarkus's response to a JSON-array body (status, content type, body text).
  - **C1-f:** graphql-java counts each fragment spread separately (F_FAN = 1025 on both). If it dedupes, assert the observed number and explain.

**Queries** (defined once at the top of `verify.sh`; aliased and fragment queries are generated with `python3 -I`):
- `Q_FAN`: Ch13's. Cost 53.
- `Q_CH1`: `{ cargos(first: 50) { edges { node { handlingHistory(first: 50) { edges { node { cargo { handlingHistory(first: 50) { edges { node { id } } } } } } } } } } }`. Cost 385151, depth 11.
- `D_DEEP`: the 4-cycle with `first: 1` throughout (cargos → edges → node → handlingHistory → edges → node → cargo → handlingHistory → … → node → id), depth 15. Cost 15.
- `Q_WIDE_COST`: `{ cargos(first: 50) { edges { node { handlingHistory(first: 50) { edges { node { id } } } } } } }`. Cost 7651, depth 6.
- `Q_EDGE(n)`: `{ cargos(first: 50) { edges { node { handlingHistory(first: n) { edges { node { id } } } } } } }`. Cost `151 + 150n`; n=5 gives 901, n=6 gives 1051.
- `A_BOMB`: 150 aliases `aK: cargo(trackingId: "ABC123") { delivery { transportStatus } itinerary { legs { voyage { number } } } }`. Cost 1050, about 3,600 tokens.
- `F_FAN`: fragments `F0 on Cargo { trackingId }`, then `Fk on Cargo { ...F(k-1) ...F(k-1) }` for k = 1..10, and `{ cargo(trackingId: "ABC123") { ...F10 } }`. Cost 1025.
- `N_IDS`: `nodes(ids: [1000 × "loc_NLRTM"]) { id }`. Cost 1001.
- `T_FLOOD`: `{ ` followed by 6000 × `__typename `, then `}`.
- `B_ARRAY`: `[{"query":"{ __typename }"},{"query":"{ __typename }"}]`.

**verify.sh assertions (both stacks unless marked).** Each rejection case is preceded by `source_calls_reset` and followed by `assert_source_call_count calls '*' '*' 0`.
1. Legitimate traffic still runs:
   - `Q_FAN`: data shape as in Ch13, and Python 6 / Quarkus 8 calls (Ch13's numbers, unchanged by limits);
   - `assert_sdl_conforms` passes (introspection under the limits);
   - `{ __typename }` answers `Query`.
2. Shallow but expensive:
   - `Q_CH1`: `assert_has_errors`, `assert_no_data`, message exactly `maximum query complexity exceeded 385151 > 1000` on **both** stacks;
   - `Q_WIDE_COST`: `… 7651 > 1000`.
3. Deep but cheap: `D_DEEP` gives `assert_no_data`. The message is per stack: Quarkus `maximum query depth exceeded <d> > 12`; Python `'anonymous' exceeds maximum operation depth of 12`. The `<d>` values come from spike C1-d.
4. The boundary: `Q_EDGE(5)` gives `assert_no_errors` and edges of length 6 (the whole seed); `Q_EDGE(6)` gives `maximum query complexity exceeded 1051 > 1000`.
5. Alias bomb `A_BOMB`: Python message `150 aliases found. Allowed: 20`; Quarkus `maximum query complexity exceeded 1050 > 1000`. Both give `assert_no_data`.
6. Fragment fan-out `F_FAN`: `maximum query complexity exceeded 1025 > 1000`, both (spike C1-f).
7. Huge page:
   - `cargos(first: 5000){edges{node{trackingId}}}` gives `… 15001 > 1000`;
   - `cargos(first: 51){edges{node{trackingId}}}` gives code `BAD_USER_INPUT`, message `first must be between 0 and 50`, `assert_null_at '.data'`, and 0 source calls (the cap fires in the resolver, before the source).
8. `nodes` bounded: `N_IDS` gives `… 1001 > 1000`; `nodes(ids:["loc_NLRTM"]){id}` gives `[{"id":"loc_NLRTM"}]`.
9. Token flood `T_FLOOD`: `assert_no_data`, with per-stack messages. The Python message contains `Document contains more than 5000 tokens`; the Quarkus message contains the graphql-java parser's token-limit text (confirm the needle).
10. Batch array `B_ARRAY` via `gql_raw`: Python `400` with body containing `Batching is not enabled`; Quarkus observed status and body (spike C1-e, expected 4xx). 0 calls.
11. Variables are costed: `query($n: Int) { cargos(first: $n) { edges { node { handlingHistory(first: $n) { edges { node { id } } } } } } }` with `{"n": 50}` gives `… 7651 > 1000`, and with `{"n": 2}` gives no errors (cost 1 + 2×(3+3×2) = 19).
12. Deprecation check; scalar checks; `assert_sdl_conforms`.

**Figures (4)**
- `14-amplification-attacks`: six panels, one per attack, each showing the request text size (bytes) beside the work it would cause (cost or calls), and which limit catches it on each stack.
- `14-limit-pipeline` (data movement): the request flowing HTTP → parse → validate → pre-execute → resolve → sources, with a SmallRye lane and a Strawberry lane. Each limit is placed where it fires, and the rejection arrows end before "sources" (zero calls).
- `14-cost-accumulation` (data movement): the `Q_CH1` tree with each node's cost computed bottom-up (2 → 3 → 151 → 152 → 153 → 154 → 7701 → … → 385151), the ×50 multipliers drawn on the connection edges, and Q_FAN's 53 in a side panel. The budget line is at 1,000.
- `14-cost-budget-boundary`: `Q_EDGE(n)` for n = 1…6 as bars of `151 + 150n` against the 1,000 budget. n=5 (901) runs and n=6 (1051) is rejected. The values are taken from the verify run (stated in the docstring).

**Citations.**
- DDIA 2nd ed. "Defining Nonfunctional Requirements" (load, response-time percentiles; verified in Wave B).
- GraphQL spec "Validation" ("Fragment spreads must not form cycles", "Overlapping fields can be merged") and "Executing Requests".
- graphql-java docs (instrumentation, `MaxQueryComplexityInstrumentation`) and the SmallRye/Quarkus GraphQL guide (configuration reference).
- Strawberry docs: "QueryDepthLimiter", "MaxAliasesLimiter", "MaxTokensLimiter", "Schema extensions", "Batching".
- OWASP GraphQL Cheat Sheet ("Query limiting").
- *GraphQL Best Practices* (its security/performance chapter; **spike:** verify the title against the ToC via the O'Reilly tool before citing).

### Ch15: Persisted queries and APQ

**Files:** `_docs/15-persisted-queries-and-apq.md`, `examples/15-persisted-queries/` (from Ch13).

**Learning goals.** By the end of the chapter the reader can:
- explain what a persisted document buys (bytes on the wire, cacheable GET URLs, parse/validate reuse, an allowlist) and what each variant costs;
- run Apollo's APQ handshake (`extensions.persistedQuery.sha256Hash`, `PersistedQueryNotFound`, register, reuse);
- distinguish APQ (clients register at run time; a bandwidth and caching tool, not a security control) from trusted documents (a build-time manifest; unknown text refused);
- implement persisted documents on both stacks at the seam each framework offers, and state why SmallRye needs an HTTP-layer front;
- send persisted queries over GET and keep mutations off GET.

**H2 outline**
1. *Sending the same text every time.* Ch6:43's validation cost, Ch1's GET point, and the size of Q_FAN against a 64-character hash.
2. *The APQ handshake.* Hash-only → `PersistedQueryNotFound` → hash plus query → stored and executed → hash-only thereafter (Figure 15.1). The hash is SHA-256 hex of the exact query text.
3. *Hashes that lie.* Mismatched hash and text → `BAD_USER_INPUT` `provided sha does not match query`. Why the server recomputes.
4. *Over GET.* `GET /graphql?extensions=…&variables=…`. Quarkus needs `http.get.enabled`. A mutation over GET is still refused (Ch8:210, Ch1:157). Chapter 16 caches these URLs.
5. *APQ is not an allowlist.* Anyone can register any document. Trusted documents: a manifest built with the client (Apollo persisted-query manifest format), loaded at start; unknown text refused with `PERSISTED_QUERY_REQUIRED` (Figure 15.2). The GraphQL-over-HTTP persisted-documents proposal (`documentId`) is mentioned (**spike:** check its status in the current draft and cite by name only if it is present).
6. *Where the document is resolved.*
   - Strawberry: a `SchemaExtension` whose `on_operation` sets `execution_context.query` before parsing, the seam Strawberry's HTTP layer leaves open.
   - SmallRye: no persisted-query support at 2.18.5. The engine rejects a request without `query` before graphql-java runs and never forwards `extensions` to `ExecutionInput`, so graphql-java's own `ApolloPersistedQuerySupport` cannot be reached. A Vert.x route in front resolves the id and re-enters SmallRye with the text (Figure 15.3).
7. *Storing documents.* A bounded store (Caffeine via `quarkus-cache`, `cachetools.LRUCache`), what happens on eviction (the handshake repeats), and Strawberry's `ParserCache`/`ValidationCache` against SmallRye's document `QueryCache`.
8. *Persisted documents and limits.* Trusted documents make Ch14's limits a backstop rather than the main control. APQ does not.
9. *Operating them.* Manifest deploys before the client, never removing a live hash, and an operation name per document for Ch19's telemetry.
10. On the wire / Decision / next.

**Example design**
- **Manifest** `examples/15-persisted-queries/persisted-documents.json` (Apollo manifest format):
  `{"format":"apollo-persisted-query-manifest","version":1,"operations":[{"id":"<sha256>","name":"…","type":"query|mutation","body":"…"}]}`.
  It holds three operations:
  - `TrackCargo` = `query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }`;
  - `PortName` = `query PortName($code: UnLocode!) { location(unLocode: $code) { name } }`;
  - `RegisterHandling` = Ch13's `REGISTER` text with the operation named `RegisterHandling`.

  The ids are computed by the executor with `python3 -I` (`hashlib.sha256(body.encode()).hexdigest()`). It is mounted read-only into both stacks:
  - Quarkus `/deployments/config/persisted-documents.json`;
  - Python `/opt/app-root/src/persisted-documents.json`;
  - mounted with `:ro,z` (lowercase `z`, because two containers share the file).
- **Mode** by environment: `TRACKING_DOCUMENTS_MODE=apq` (services `quarkus`, `python`) or `trusted` (`quarkus-trusted`, `python-trusted`), plus `TRACKING_DOCUMENTS_MANIFEST=<path>`.
- **Quarkus**
  - `pom.xml` adds `quarkus-cache`.
  - Properties:
    ```
    quarkus.smallrye-graphql.http.get.enabled=true
    quarkus.smallrye-graphql.http.post.queryparameters.enabled=true
    quarkus.cache.caffeine."persisted-documents".maximum-size=1000
    tracking.documents.mode=${TRACKING_DOCUMENTS_MODE:apq}
    tracking.documents.manifest=${TRACKING_DOCUMENTS_MANIFEST:}
    ```
  - `PersistedDocumentRoute.java` (`@ApplicationScoped`, constructor injection of `@CacheName("persisted-documents") Cache documents`, the config and a `Manifest` loaded at startup with Jakarta JSON) registers in `void init(@Observes Router router)`:
    ```java
    router.route("/graphql").order(-10).handler(BodyHandler.create()).handler(this::resolve);
    ```
    `resolve`:
    1. The request is passed through (`rc.next()`) when any of these holds:
       - it is not GET or POST;
       - the URL already carries a `query` parameter (a re-entered request);
       - there is no `extensions.persistedQuery` **and** the mode is `apq`.
    2. Otherwise it reads `sha256Hash`.
       - With `query` present: recompute the hash; a mismatch answers `BAD_USER_INPUT`. In apq mode, `documents.as(CaffeineCache.class).put(hash, completedFuture(text))`. In trusted mode, refuse text not in the manifest with `PERSISTED_QUERY_REQUIRED`.
       - With only the hash: look it up (the manifest first, then the store in apq mode). If it is unknown, answer `PERSISTED_QUERY_NOT_FOUND`.
    3. In trusted mode, a request with text and no hash is refused unless `sha256(text)` is in the manifest.
    4. Re-entry: `rc.reroute(method, "/graphql?query=" + urlEncode(text) [+ "&variables=" + urlEncode(json)] [+ "&operationName=" + …])`. For POST, SmallRye merge-patches the URL parameters over the body (`queryparameters.enabled`); for GET, it reads them (`get.enabled`).
    5. Error answers are written directly as `200`, `application/json`, `{"errors":[{"message":…,"extensions":{"code":…}}]}`.

    The class comment states that SmallRye has no persisted-query support (§8 decision 2) and names the two engine facts above.
  - **Spikes:**
    - **C2-a:** our route runs before SmallRye's for `/graphql` and does not match `/graphql/schema.graphql`;
    - **C2-b:** `rc.reroute` with a query string re-parses the parameters, and SmallRye executes the merged request (the body is still readable, or the variables travel in the URL as written above);
    - **C2-c:** a GET of a mutation (by hash) with `get.enabled=true` is refused (record status and body);
    - **C2-d:** a second `BodyHandler` on SmallRye's route is harmless.

    If C2-b fails, stop and report. Do not edit the Vert.x body internals (`RoutingContextInternal`).
- **Python**
  - `pyproject` adds `cachetools==7.2.2`.
  - `app/persisted.py`:
    - `PersistedDocuments` (app-scoped: the mode, a `Manifest` dict loaded at start, an `LRUCache(maxsize=1000)`);
    - exposed errors `PersistedQueryNotFound(ExposedError)` (code `PERSISTED_QUERY_NOT_FOUND`, message `PersistedQueryNotFound`) and `PersistedQueryRequired(ExposedError)`;
    - `BadUserInput` reused for the mismatch.
  - `PersistedQueries(SchemaExtension)`: `__init__(self, *, documents: PersistedDocuments)`. `on_operation` (before `yield`) applies the same rules to `self.execution_context.query` and `self.execution_context.operation_extensions`, and sets `self.execution_context.query` for a resolved hash.
  - Schema: `extensions=[partial(MaskErrors, …), partial(PersistedQueries, documents=documents), ParserCache, ValidationCache]`.
  - **Spike C2-e:** the extension order makes MaskErrors see (and expose) the `ExposedError`s; a hash-only GET passes Strawberry's HTTP layer with `query=None`; a mutation by hash over GET still gets `400 mutations are not allowed when using GET`.
- **Spike C2-f (README):** request body sizes, hash-only POST bytes against full Q_FAN bytes, measured with `curl -w '%{size_upload}'`. Prose uses the measured numbers.

**verify.sh assertions.** APQ cases run on 8250/8251; trusted cases on 8252/8253. `H_TRACK`, `H_PORT` and `H_REG` are computed in verify.sh.
1. Manifest integrity (once): each `operations[].id` equals `sha256_hex(body)`.
2. Handshake (APQ, POST, `{"id":"ABC123"}`):
   - hash-only gives `assert_no_data`, message `PersistedQueryNotFound`, code `PERSISTED_QUERY_NOT_FOUND`, 0 calls;
   - hash plus query gives data `cargo.trackingId` `ABC123`, transportStatus `ONBOARD_CARRIER`;
   - hash-only again gives the same data, `assert_no_errors`, and the same source-call keys as the full request.
3. Mismatch: query `TrackCargo` with hash `H_PORT` gives `BAD_USER_INPUT`, `provided sha does not match query`, 0 calls.
4. GET by hash (APQ, after case 2): `http_any GET "$url?extensions=…&variables=…"` gives 200 and the same data.
5. GET mutation by hash: register `H_REG` by POST first with a validation-failing input (RECEIVE on V100S, which gives `userErrors` VOYAGE_NOT_ALLOWED and 0 `appendEvent`). Then send it by GET: Python 400 containing `mutations are not allowed when using GET`; Quarkus as observed (C2-c). 0 `handling.appendEvent`.
6. Mutation by hash over POST: `RegisterHandling` with UNLOAD DEHAM V100S `2026-10-09T15:00:00Z` for ABC123 gives `evt_10`; a repeat with the same `idempotencyKey` by hash-only returns `evt_10` (the Ch8 semantics hold through APQ).
7. Trusted mode (8252/8253):
   - `H_PORT` hash-only, never registered, gives data `location.name` `Rotterdam` (the manifest is preloaded);
   - the same over GET works;
   - arbitrary text `{ __typename }` gives `PERSISTED_QUERY_REQUIRED`, `only persisted documents are accepted`, `assert_no_data`;
   - hash plus unknown text (registration attempt) gives `PERSISTED_QUERY_REQUIRED`;
   - an unknown hash gives `PERSISTED_QUERY_NOT_FOUND`;
   - the full text of `PortName` without a hash is accepted (its hash is in the manifest);
   - 0 source calls for each refusal.
8. Introspection is refused in trusted mode: `{ __schema { queryType { name } } }` gives `PERSISTED_QUERY_REQUIRED`. Conformance therefore runs on the APQ instance, and the README says why.
9. Deprecation check, scalar checks and `assert_sdl_conforms` on 8250/8251.

**Figures (3)**
- `15-apq-handshake` (data movement): a client/server sequence with three round trips (hash-only → `PersistedQueryNotFound`; hash plus query → data, stored; later GET hash → data), with the bytes on each arrow taken from spike C2-f.
- `15-apq-vs-trusted`: two columns covering who registers (the client at run time / the build pipeline), what the server accepts, what an attacker can do, and the cache-friendliness of each.
- `15-persisted-document-seam` (data movement): Quarkus lane (Vert.x route → resolve id → `reroute` with `query` → SmallRye parse/validate (QueryCache) → execute) beside the Strawberry lane (HTTP view `query=None` → `on_operation` sets `query` → ParserCache/ValidationCache → execute).

**Citations.**
- Apollo "Automatic persisted queries" (protocol, `PERSISTED_QUERY_NOT_FOUND`) and Apollo's persisted-query manifest format.
- graphql.org "Security" / trusted documents (**spike:** page name).
- GraphQL-over-HTTP "GET" (and persisted documents if present).
- graphql-java "Persisted queries" (`ApolloPersistedQuerySupport`).
- Strawberry "Schema extensions" (`on_operation`), "ParserCache", "ValidationCache".
- Quarkus "HTTP reference" (Vert.x Router, `@Observes Router`) and the SmallRye GraphQL config (`http.get.enabled`, `http.post.queryparameters.enabled`).

### Ch16: Caching

**Files:** `_docs/16-caching.md`, `examples/16-caching/` (from Ch15, **APQ mode only**: drop the trusted instances and ports 8252/8253, keep the manifest and the APQ code).

**Learning goals.** By the end of the chapter the reader can:
- name the four cache layers of a GraphQL service (client normalized by `id`, HTTP/CDN for GET, field-level in the server, source) and what each keys on and how it is invalidated;
- explain why POST is not cached by intermediaries and how persisted GETs fix that;
- set `Cache-Control` per response from what the operation touched and whether it erred;
- run an HTTP cache that honours it and bypasses on `Authorization`;
- cache source results across requests with TTL and invalidate on writes (Ch13's deferral);
- reason about staleness, keys that include identity, and when a shared cache is needed (DDIA: caches as derived data).

**H2 outline**
1. *Four places to keep an answer.* Client, edge, server field-level, source (Figure 16.1). Ch13's per-request loader cache is the zeroth: request-level only.
2. *The client's normalized cache.* `id` + `__typename` as keys (Ch10's refetch rule), `nodes` for refreshes, and Ch22 forward. Prose only.
3. *Caching at the edge needs GET.* POST bodies are invisible to caches (RFC 9111 "Storing Responses in Caches"); Ch15's hashed GET URLs are short and stable (Figure 16.2).
4. *Deciding `Cache-Control` per response.* Only GETs, only error-free, only operations whose root fields are reference data (`location`, `voyage`) get `public, max-age=300`; everything else gets `no-store` (Figure 16.4). Field-level hints (Apollo's `@cacheControl`) are mentioned and not adopted, because the canonical SDL has no directive (Ch5).
5. *The edge itself.* nginx `proxy_cache`: key, methods, `X-Cache-Status`, and `proxy_no_cache`/`proxy_cache_bypass $http_authorization`, because a key without the caller's identity leaks (Ch13:190, Ch18 forward).
6. *Caching inside the server.* Per-key caches behind the bulk sources: reference data (`voyage`, `location`) with TTL 300 s, handling events with TTL 5 s in the lab and invalidated on write. The loader still batches the misses. On SmallRye, `@CacheResult` on single-key operations and `CaffeineCache.getIfPresent`/`put` in the bulk ones; on Strawberry, `cachetools.TTLCache`.
7. *Invalidating on write.* `registerHandlingEvent` evicts the cargo's handling entry **before** the payload re-reads (Ch8's payload stays fresh) (Figure 16.3).
8. *Expiry as the backstop.* TTL bounds staleness from writers that bypass this service. DDIA "Trade-offs in Data Systems Architecture" (systems of record and derived data).
9. *What would change with replicas.* In-process caches diverge, and invalidation must be broadcast. A shared cache (Valkey, BSD-licensed, preferred over Redis since its licence change) or a pub/sub eviction. The chapter does not run Valkey; Chapters 25–27 run replicas (§8 decision 4).
10. *Why no whole-response cache in the server.* The keys need document, variables and identity; invalidation cannot see inside a cached response; the edge already does it for public reads.
11. On the wire / Decision / next.

**Example design**
- **Cache policy hook**
  - **Quarkus** `CachePolicy.java`: `void decide(@Observes @AfterExecute Context context)`. It inspects:
    - the request method (`CurrentVertxRequest#getCurrent().request().method()`);
    - errors (`context.unwrap(ExecutionResult.class).getErrors()`, or `getExecutionResult()`; spike);
    - the root field names of the selected operation (from `context.getQuery()` parsed once with graphql-java's `Parser`, or the document via `context.unwrap`; spike C3-a picks the public API);
    - the `Authorization` header.

    It then calls `response.putHeader("Cache-Control", …)`. **Spike C3-a:** AfterExecute fires before the response is written and on a thread where `CurrentVertxRequest` is active. Fallback: a Vert.x `rc.addHeadersEndHandler` registered by Ch15's route, reading a decision the observer stores in `rc.put("cache-control", …)`.
  - **Python:** `CachePolicy(SchemaExtension)`. `on_execute` after `yield` reads `execution_context.result.errors`, the document's root fields, `context.request.method` and the `authorization` header, and sets `context.response.headers["Cache-Control"]` (Strawberry FastAPI's documented response-header path).
  - Policy (identical): `public, max-age=300` iff the method is GET, there are no errors, every root field is in {`location`, `voyage`, `__typename`}, and there is no `Authorization` header. Otherwise `no-store`.
- **Field-level source caches**
  - **Quarkus** (`pom.xml` adds nothing new; `quarkus-cache` came with Ch15):
    - `@CacheResult(cacheName = "voyages")` on `VoyageSource.getVoyage(String request, @CacheKey String number)`, and the same for `locations` on `LocationSource.getLocation`. **Spike C3-b:** `@CacheResult` caches the `Uni` item and `@CacheKey` excludes the request id.
    - Bulk `getVoyages`/`getLocations`/`listEventsFor`:
      - partition the keys with `cache.as(CaffeineCache.class).getIfPresent(key)`;
      - make one bulk owner call for the misses, logged with only the misses' keys;
      - `put` each fetched value;
      - keep key order.
    - `handling-events` cache: `HandlingRegistration` calls `handlingEvents.invalidate(trackingId)` (a Uni, chained) after a successful append and before the payload's `cargo` is resolved.
    - Config:
      ```
      quarkus.cache.caffeine."voyages".expire-after-write=300S
      quarkus.cache.caffeine."locations".expire-after-write=300S
      quarkus.cache.caffeine."handling-events".expire-after-write=${TRACKING_HANDLING_CACHE_TTL:60S}
      ```
      compose sets `TRACKING_HANDLING_CACHE_TTL=5S`.
  - **Python** (`app/caches.py`): `SourceCaches` (app-scoped) holds three `cachetools.TTLCache(maxsize=1024, ttl=…)` (300, 300, `settings.handling_cache_ttl_seconds`, compose 5). The bulk sources partition hits and misses the same way. `registration.py` calls `caches.handling.pop(tracking_id, None)` after the append, before the payload re-read. The loaders are unchanged (still per request), so batching happens on misses only.
  - Hits are **not** logged as source calls (the log records calls to owners). The README states this.
- **Edge**
  - `examples/16-caching/edge/nginx.conf` is mounted at `/etc/nginx/nginx.conf:ro,z` and run with `command: ["nginx", "-g", "daemon off;"]`:
    - `pid /tmp/nginx.pid;`, temp paths under `/tmp`;
    - `proxy_cache_path /tmp/nginx-cache keys_zone=graphql:10m max_size=50m inactive=10m;`;
    - two `server` blocks, `listen 8080` → `http://quarkus:8080` and `listen 8081` → `http://python:8080`;
    - `proxy_cache graphql; proxy_cache_methods GET HEAD; proxy_cache_key "$scheme$request_method$host$request_uri";`;
    - `proxy_no_cache $http_authorization; proxy_cache_bypass $http_authorization;`;
    - `add_header X-Cache-Status $upstream_cache_status always;`.
  - It `depends_on` both apps healthy, with a healthcheck `curl -fsS http://localhost:8080/graphql?query=%7B__typename%7D`.
  - **Spike C3-c:** the UBI image runs this config as uid 1001; nginx honours upstream `max-age` and `no-store`; it emits no `Age` header (assert `X-Cache-Status` instead; the prose says Varnish would add `Age`).

**verify.sh assertions.** Direct ports 8260/8261 for server-cache cases; edge ports 8262/8263 for HTTP cases; the source-call log is read on the direct port. Each case is preceded by `source_calls_reset`.
1. Policy headers (direct):
   - GET `PortName` by hash (registered first by POST) gives `Cache-Control: public, max-age=300`;
   - POST of the same gives `no-store`;
   - GET `TrackCargo` gives `no-store`;
   - GET with an error (`{ location(unLocode:"NLRTM"){ weight } }` as text) gives `no-store`;
   - GET `PortName` with `Authorization: Bearer x` gives `no-store`.
2. Edge hit/miss (via 8262/8263): GET `PortName` (NLRTM) twice.
   - First: `X-Cache-Status: MISS`, and `location.getLocation:NLRTM` or `getLocations` 1 call *or* 0 if the server cache already holds it. To avoid this ambiguity, case 2 uses `USNYC`, which nothing earlier reads.
   - Second: `HIT`, total source calls 0, same body.
3. Edge never caches private or failed responses:
   - GET `TrackCargo` twice gives `MISS` both times (or no status recorded; assert `!= HIT`), and the server is reached both times (the `booking.getCargo` count is 2 over the two requests);
   - an error GET gives `!= HIT` on the repeat.
4. Edge bypass: GET `PortName` with `Authorization: Bearer x` gives `X-Cache-Status: BYPASS` (the server is reached).
5. Server reference caches: `Q_FAN` twice, back to back (direct).
   - Run 1: Python 6 / Quarkus 8 calls (Ch13).
   - Run 2: Python **3** (`booking.listCargos`, `booking.getCargos`, `routing.getItineraries`) / Quarkus **4** (the same plus a second `getItineraries`); `voyage *` 0, `location *` 0, `handling *` 0 (the handling entries cached by run 1, TTL 5 s; run 2 starts within 5 s).
   - Spike: confirm that run 2 completes within the TTL. Otherwise run 2 asserts only voyage/location 0 and case 7 covers handling.
6. Invalidation on write (direct; ABC123):
   - read `cargo(ABC123){delivery{transportStatus}}` twice: the second has `handling listEventsFor` 0;
   - register UNLOAD DEHAM V100S `2026-10-09T15:00:00Z` → `evt_10`; the payload's `cargo.delivery.transportStatus` is `IN_PORT`, and the mutation's call log includes one `handling.listEventsFor:ABC123` (an evicted miss);
   - the next read is `IN_PORT`, with handling 0 calls (refilled by the payload read).
7. Expiry: read `cargo(XYZ789){delivery{transportStatus}}` (fills), `sleep 6`, read again: `handling listEventsFor` keys `XYZ789` (1 call). Whole seconds only.
8. Single-key annotation path: `voyage(voyageNumber:"V200E"){number}` twice: the second has 0 `voyage.*` calls (Quarkus `@CacheResult`, Python TTLCache).
9. Ch15 still works: hash-only `PersistedQueryNotFound` for an unregistered hash (one case).
10. Deprecation check, scalar checks, `assert_sdl_conforms` (direct ports).

**Figures (4)**
- `16-cache-layers` (data movement): client normalized cache (keyed by `__typename`+`id`) → nginx (keyed by method+URL, honours `Cache-Control`, bypasses on `Authorization`) → server field caches (keyed by voyage number / UN/LOCODE / tracking id, TTL, evicted on write) → owners. Each layer is labelled with its invalidation mechanism.
- `16-edge-cache-hit` (data movement): two GETs of `PortName`. The first passes through to the server and the location owner (`MISS`, 1 call); the second stops at nginx (`HIT`, 0 calls), with headers drawn from the case-2 run.
- `16-invalidation-on-write` (data movement): read (fill `handling-events:ABC123`) → `registerHandlingEvent` → append → evict → payload re-read (miss, 1 call) → next read (hit), with the transportStatus values `ONBOARD_CARRIER` → `IN_PORT`.
- `16-cache-policy-decision`: the decision tree (GET? errors? root fields all reference data? `Authorization`?) ending in `public, max-age=300` or `no-store`.

**Citations.**
- RFC 9111 "HTTP Caching" (sections "Storing Responses in Caches", "Cache-Control") and RFC 9110 (GET safety).
- DDIA 2nd ed. "Trade-offs in Data Systems Architecture" (systems of record and derived data). **Spike:** confirm the section name inside the chapter before quoting it; cite the chapter title only if it cannot be confirmed.
- Quarkus "Application data caching" guide; nginx `ngx_http_proxy_module` (`proxy_cache*`); cachetools docs; Apollo "Caching" (`@cacheControl`, for contrast).
- *GraphQL in Action* "Optimizing data fetching" (verified title; caching context).
- Valkey project (licence) in prose only.

### Ch17: Transport security and introspection control

**Files:** `_docs/17-transport-security-and-introspection.md`, `examples/17-transport-security/` (from Ch13).

**Learning goals.** By the end of the chapter the reader can:
- serve GraphQL over TLS on both stacks from framework configuration, with certificates that never enter the repository;
- state each stack's TLS protocol floor;
- decide where introspection belongs (internal, CI or build export) and turn it off on public endpoints;
- turn off field suggestions and IDEs;
- close the browser CSRF paths for GraphQL (simple-request content types, GET mutations) and configure CORS for a known origin;
- bound request size;
- check the contract against a non-public instance.

**H2 outline**
1. *What the transport must guarantee.* Confidentiality and integrity for tokens (Ch18) and data; TLS 1.3 (RFC 8446).
2. *TLS in the framework.* Quarkus TLS registry PEM (`quarkus.tls.key-store.pem…`, `insecure-requests=disabled`) and uvicorn `--ssl-certfile/--ssl-keyfile`. Floors: Quarkus 3.40 defaults to TLS 1.3 only, Python's `ssl` default minimum is TLS 1.2. HSTS. Terminating at a proxy is the alternative (Figure 17.1 note; Chapters 25–27 forward).
3. *Certificates for a lab.* Generated at run time (a CA plus a server certificate with SANs `localhost`, `quarkus`, `python`, `127.0.0.1`), mounted read-only, git-ignored; why no private key is ever committed.
4. *Introspection is a map.* Ch6:188. Public vs internal endpoints (Figure 17.2). SmallRye `field-visibility=no-introspection`; Strawberry `DisableIntrospection`. `__typename` still works; `schema-available=false` removes `/graphql/schema.graphql` (build-time); IDEs off.
5. *Suggestions leak names.* graphql-core's "Did you mean" against Strawberry's `disable_field_suggestions`; graphql-java's validation message (spike C4-c). Disabling introspection without disabling suggestions still leaks the schema.
6. *CSRF for an API that takes JSON.* Simple requests (`text/plain`, form encodings) skip preflight. Both stacks must refuse non-JSON content types; GET mutations are refused (Ch8); GET is off on the public endpoint.
7. *CORS for the one origin that needs it.* `quarkus.http.cors.*` and FastAPI `CORSMiddleware`; a preflight for an allowed origin against an unknown one.
8. *Size limits.* Quarkus `limits.max-body-size` gives 413. Uvicorn has no body limit, so Python relies on `MaxTokensLimiter`, and a fronting proxy (`client_max_body_size`) is the production answer.
9. *Checking the contract without public introspection.* The internal instance (CI), or SDL export at build (Ch5).
10. On the wire / Decision / next.

**Example design**
- **Certificates:** `examples/17-transport-security/gen-certs.sh <dir>`, executable, bash, using `openssl` only. It writes `ca.crt`, `tls.crt` and `tls.key` (RSA 2048 or P-256, valid 2 days, `chmod 0644` on the key because it is a test fixture read by uid 185/1001). `verify.sh` runs it into `$SCRATCH/certs`, exports `CERT_DIR`, and sets `LGTM_CACERT="$CERT_DIR/ca.crt"`. compose mounts `${CERT_DIR:-./certs}:/certs:ro,z`. The README's Run it section runs `./gen-certs.sh certs` first. `.gitignore` has `certs/`.
- **Four services:**
  - `quarkus` (public): `TRACKING_PUBLIC=true`, `QUARKUS_SMALLRYE_GRAPHQL_FIELD_VISIBILITY=no-introspection`;
  - `quarkus-internal`: introspection on;
  - `python` (public): `TRACKING_PUBLIC=true`;
  - `python-internal`: `TRACKING_PUBLIC=false`.

  Healthchecks use `curl -fsS --cacert /certs/ca.crt https://localhost:8443/…`.
- **Quarkus** properties:
  ```
  quarkus.tls.key-store.pem.tls.cert=/certs/tls.crt
  quarkus.tls.key-store.pem.tls.key=/certs/tls.key
  quarkus.http.ssl-port=8443
  quarkus.http.insecure-requests=disabled
  quarkus.http.header."Strict-Transport-Security".value=max-age=31536000
  quarkus.http.cors.enabled=true
  quarkus.http.cors.origins=https://tracking.example.com
  quarkus.http.cors.methods=POST
  quarkus.http.cors.headers=content-type,authorization
  quarkus.http.limits.max-body-size=64K
  quarkus.smallrye-graphql.schema-available=false
  quarkus.smallrye-graphql.parser-max-tokens=5000
  ```
  `http.get.enabled` stays false.
  - **Spikes:**
    - **C4-a:** a `text/plain` and an `application/x-www-form-urlencoded` POST with a JSON body. Add `ContentTypeGuard` (a Vert.x filter registered through `@Observes Filters`, ahead of the GraphQL handler, 415 for anything except `application/json` and `application/graphql-response+json` on POST `/graphql`), following the GraphQL-over-HTTP draft and the OWASP CSRF cheat sheet. Teach it as a standard hardening step, record the guarded statuses, and record it in §9.
    - **C4-b:** `no-introspection` refuses `__schema` and `__type` (record the message) and keeps `__typename`.
    - **C4-c:** graphql-java's unknown-field message (does it suggest?).
- **Python**
  - `main.py`: uvicorn CMD `--ssl-certfile /certs/tls.crt --ssl-keyfile /certs/tls.key --port 8443`.
  - `GraphQLRouter(schema_for(settings), context_getter=get_context, graphql_ide=None if public else "graphiql", allow_queries_via_get=not public)`.
  - `app.add_middleware(CORSMiddleware, allow_origins=["https://tracking.example.com"], allow_methods=["POST"], allow_headers=["content-type","authorization"])`.
  - HSTS via `@app.middleware("http")`.
  - Schema built by `schema_for(public)`: `StrawberryConfig(scalar_map=…, disable_field_suggestions=public)`; extensions `[partial(MaskErrors,…), partial(MaxTokensLimiter, max_token_count=5000)] + ([DisableIntrospection] if public else [])`.
  - **Spike C4-d:** Strawberry's response to `text/plain` (expected `400 Unsupported content type`), and to `Accept: text/html` GET on a public endpoint with the IDE off.

**verify.sh assertions** (`LGTM_CACERT` set for all calls; "pub" = 8270/8271, "int" = 8272/8273)
1. TLS works and is verified:
   - `{ __typename }` over https on all four gives `Query`;
   - without `--cacert` the transport fails (`assert_transport_fails`);
   - `http://localhost:8270` fails or gives a non-200.
2. Protocol floor:
   - `--tlsv1.3` succeeds on pub (both);
   - `--tlsv1.2 --tls-max 1.2`: Quarkus transport fails, Python succeeds (assert per stack; prose explains both defaults).
3. HSTS: header `Strict-Transport-Security: max-age=31536000` on pub, both stacks.
4. Introspection:
   - pub `{ __schema { queryType { name } } }` gives `assert_has_errors`, `assert_no_data` (or data null per stack), with a per-stack message needle (C4-b, Strawberry's contains `introspection has been disabled`);
   - pub `__type(name:"Cargo")` is refused too;
   - pub `{ __typename }` works;
   - int introspection works.
5. Suggestions:
   - int Python `{ cargo(trackingId:"ABC123"){ trackingI } }` contains `Did you mean 'trackingId'?`;
   - pub Python does **not** contain `Did you mean`;
   - Quarkus pub and int: the observed message (C4-c), and `assert_body_not_contains … 'Did you mean'` if confirmed.
6. Schema endpoint and IDE: Quarkus `GET /graphql/schema.graphql` gives 404 (both instances; build-time); pub Python `GET /graphql` with `Accept: text/html` gives a non-HTML response (C4-d).
7. CSRF: POST `text/plain` with a mutation body, and POST form-encoded, to pub gives 4xx on both (C4-a; 415 from the guard), with 0 `handling.appendEvent`. GET `?query=mutation…` gives 4xx on both (Quarkus 405 because GET is off; Python 405 or 400 with GET off; record).
8. CORS:
   - preflight `OPTIONS` with `Origin: https://tracking.example.com` and `Access-Control-Request-Method: POST` gives `Access-Control-Allow-Origin: https://tracking.example.com`;
   - with `Origin: https://evil.example` there is no `Access-Control-Allow-Origin` (or not that origin);
   - both stacks.
9. Size:
   - Quarkus pub POST of a 100 KB body (a query padded with a 100 KB comment) gives 413;
   - Python pub the same body gives a GraphQL error from the token limit **or** passes (comments are not tokens). Spike C4-e: use a 6,000-field body instead for Python, giving the token-limit error. Assert per stack and explain the difference in prose.
10. Errors are still masked (Ch9 holds over TLS): the GHI345 edge case gives code `SERVICE_UNAVAILABLE` on pub.
11. Deprecation check, scalar checks and `assert_sdl_conforms` on the **internal** instances (inspector via `NODE_EXTRA_CA_CERTS`, C0).

**Figures (2)**
- `17-hardened-request-path` (data movement): browser/client → TLS (1.3; 1.2 on Python) → CORS preflight/origin → content-type guard → body size (Quarkus) → parse (token limit) → validate (introspection rule; suggestions off) → execute → masked errors. The refusal exit and status are shown at each gate.
- `17-public-vs-internal-endpoints`: the same image deployed twice. The public one has introspection, suggestions, IDE and GET off; the internal one has introspection on. CI's contract check points at the internal one, and the SDL export is the alternative.

**Citations.**
- RFC 8446 (TLS 1.3), RFC 6797 (HSTS).
- GraphQL spec "Introspection".
- GraphQL-over-HTTP "Request" (media types, GET).
- Fetch standard "CORS protocol" (simple requests and preflight).
- OWASP GraphQL Cheat Sheet (introspection, CSRF).
- Quarkus "TLS registry reference", "HTTP reference" (CORS, limits, headers) and the SmallRye GraphQL config (`field-visibility`, `schema-available`).
- Strawberry "DisableIntrospection", `StrawberryConfig`; uvicorn "Settings" (SSL); FastAPI "CORS".
- *GraphQL Best Practices* (security chapter, title **spike** as in Ch14).

### Ch18: AuthN and AuthZ

**Files:** `_docs/18-authn-and-authz.md`, `examples/18-authn-authz/` (from Ch13).

**Learning goals.** By the end of the chapter the reader can:
- separate authentication (who: a JWT from an OSS identity provider) from authorization (what: operation, object and field rules);
- validate tokens correctly (signature via JWKS, issuer, audience, expiry);
- put only the identity in the context (Ch7:213);
- protect operations with framework annotations and permission classes;
- enforce object-level ownership at one choke point so that every path (root, `node`, `nodes`, edges, `HandlingEvent.cargo`) obeys it;
- choose between an error and a silent null for a refused field or object, and predict the null propagation (Ch4);
- keep codes stable (`UNAUTHENTICATED`, `FORBIDDEN`) and keep bad tokens at HTTP 401.

**H2 outline**
1. *Who is asking, and what may they see.* One query touches public reference data and owned cargo (Ch2:81).
2. *Tokens from an identity provider.* Keycloak realm, clients, roles, the `shipper` claim and the audience mapper (Figure 18.1). The lab uses the password grant; RFC 9700 (OAuth 2.0 Security BCP) says production clients use the authorization code flow with PKCE.
3. *Validating a JWT.* Signature via JWKS (cached), `iss`, `aud`, `exp` (RFC 8725). A bad token gives HTTP 401 with `WWW-Authenticate: Bearer`, before GraphQL runs. No token means anonymous, not 401: public fields still work.
4. *Identity in the context, nothing else.* Quarkus `SecurityIdentity`/`JsonWebToken`; Python `TrackingContext.identity` (subject, roles, shipper). The raw token is never in the context.
5. *Operation-level rules.* `@Authenticated` / `@RolesAllowed("operator")` on SmallRye operations; `IsAuthenticated` / `IsOperator` permission classes on Strawberry fields; `UNAUTHENTICATED` vs `FORBIDDEN` (Figure 18.2).
6. *Object-level rules: a shipper sees only its cargos.* The rule lives in the booking source (one place). `cargos` is filtered at the index, so `totalCount` counts only the caller's cargos. A non-owned `cargo(...)` is null without an error, indistinguishable from an unknown id (no enumeration). `node(id:"evt_1")` resolves the event's owner.
7. *Field-level rules: errors or nulls.* `registrationTime` for operators only. An error with a code at the field's path, and the null propagates from `DateTime!` to the nullable edge node (Ch4's fuse), so the edges survive (Figure 18.3). When a silent null is right (objects) and when it misleads (fields: "not allowed" read as "absent").
8. *Writes need a role.* `registerHandlingEvent` is operator-only. `FORBIDDEN` on a non-null payload nulls `data` (Ch8).
9. *Codes the client can act on.* Ch9's vocabulary plus `UNAUTHENTICATED`/`FORBIDDEN`, exposed through the allowlist; masking still hides the rest.
10. *Caching and identity.* Ch16's bypass rule, and per-identity keys if responses were cached.
11. On the wire / Decision / next.

**Example design**
- **Keycloak service**:
  - `image: quay.io/keycloak/keycloak:26.8.1`, `command: ["start-dev", "--import-realm"]`;
  - env `KC_BOOTSTRAP_ADMIN_USERNAME=admin`, `KC_BOOTSTRAP_ADMIN_PASSWORD=admin-fixture-pw` (fixture), `KC_HEALTH_ENABLED=true`;
  - volume `./keycloak/shipping-realm.json:/opt/keycloak/data/import/shipping-realm.json:ro,z`;
  - port `8282:8080`;
  - healthcheck via bash `/dev/tcp` on management port 9000 `/health/ready`. **Spike C5-b:** the image has bash and the realm imports.
  - Tokens are always obtained from the host at `http://localhost:8282`, so `iss` is `http://localhost:8282/realms/shipping` (dev mode derives the hostname from the request). The apps fetch JWKS on the compose network.
- **Quarkus**
  - `pom.xml` adds `quarkus-oidc`.
  - Properties:
    ```
    quarkus.oidc.auth-server-url=http://keycloak:8080/realms/shipping
    quarkus.oidc.discovery-enabled=false
    quarkus.oidc.jwks-path=protocol/openid-connect/certs
    quarkus.oidc.token.issuer=http://localhost:8282/realms/shipping
    quarkus.oidc.token.audience=tracking-api
    quarkus.oidc.roles.role-claim-path=realm_access/roles
    quarkus.oidc.application-type=service
    quarkus.oidc.devservices.enabled=false
    ```
    Anonymous access is allowed at the HTTP layer: no `auth.permission` on `/graphql`; proactive auth stays on, so a *bad* token gives 401.
  - `@Authenticated` on `Query.cargo`, `Query.cargos`, `Query.nodes`? No: **`nodes`/`node` stay open**. They return null for invisible objects, and so do anonymous callers asking for cargos or events.
  - `@RolesAllowed("operator")` on `HandlingApi.registerHandlingEvent`.
  - The `registrationTime` component becomes `@Ignore`d on the `HandlingEvent` record, replaced by `@RolesAllowed("operator") @NonNull @Description(<canonical>) public Instant registrationTime(@Source HandlingEvent event)` in a `@GraphQLApi` class.
  - `Viewer` record (`shipper` or all), built from the injected `SecurityIdentity`/`JsonWebToken` at resolver entry, like the request id. `BookingSource.getCargo(s)`/`listCargos` take it and filter on `owner`.
  - The `node` resolver for `evt_` checks the event's cargo through `booking.getCargo(request, id, viewer)`.
  - `DeclaredErrorCodeProvider` extended with a fixed mapping `io.quarkus.security.UnauthorizedException → UNAUTHENTICATED` and `io.quarkus.security.ForbiddenException → FORBIDDEN`. Both are appended to `show-runtime-exception-message`.
  - **Spikes:**
    - **C5-a:** the code and message SmallRye emits for each exception, including whether `unwrap-exceptions` is needed;
    - **C5-c:** `@RolesAllowed` on a `@Source` method yields a per-path error with the event node nulled;
    - **C5-d:** `SecurityIdentity` is available in `Uni`/batch resolvers;
    - **C5-e:** the 401 response carries `WWW-Authenticate: Bearer`.
- **Python**
  - `pyproject` adds `pyjwt[crypto]==2.15.1`.
  - `app/auth.py`:
    - frozen `Identity(subject, roles: frozenset[str], shipper: str | None)`;
    - an app-scoped `PyJWKClient("http://keycloak:8080/realms/shipping/protocol/openid-connect/certs", cache_keys=True)`;
    - `async def identity_from(request) -> Identity | None`: no header gives `None`; otherwise `await run_in_threadpool(jwk_client.get_signing_key_from_jwt, token)`, then `jwt.decode(token, key, algorithms=["RS256"], audience="tracking-api", issuer=settings.oidc_issuer, options={"require": ["exp","iss","aud","sub"]})`. A `jwt.PyJWTError` raises `HTTPException(401, headers={"WWW-Authenticate": 'Bearer error="invalid_token"'})`.
  - `deps.get_context` adds `identity`. `TrackingContext.identity` is the only auth state; the token is not stored.
  - `app/permissions.py`: `IsAuthenticated`, `IsOperator(BasePermission)` with `on_unauthorized` raising `Unauthenticated(ExposedError)` (code `UNAUTHENTICATED`, `authentication required`) / `Forbidden(ExposedError)` (`FORBIDDEN`, `operator role required`). They are used as `permission_classes=[IsAuthenticated]` on `cargo`/`cargos`, `[IsOperator]` on `registerHandlingEvent` and on `HandlingEvent.registration_time`.
  - `app/access.py`: `visible(identity, owner) -> bool`, applied in the booking source's bulk and single operations and in `listCargos`.
  - **Spike C5-f:** the permission error on `registration_time` (`datetime`, non-null) nulls only the edge node; `should_mask` exposes it.
- The README states the fixture credentials, the password-grant caveat and the `iss` rule (tokens must be fetched at `localhost:8282`).

**verify.sh assertions.** Tokens come from `oidc_token http://localhost:8282/realms/shipping/protocol/openid-connect/token tracking-cli <user> <pw>`; `LGTM_BEARER` is set per case.
1. Public data, anonymous: `location(unLocode:"NLRTM"){name}` gives `Rotterdam`, no errors.
2. Anonymous protected operation:
   - `cargo(trackingId:"ABC123"){trackingId}` gives `assert_null_at '.data.cargo'`, path `["cargo"]`, code `UNAUTHENTICATED`, 0 source calls;
   - `cargos(first:2){totalCount}` gives `assert_null_at '.data'` (non-null connection), code `UNAUTHENTICATED`.
3. Anonymous `node`/`nodes`: `nodes(ids:["loc_NLRTM","cargo_ABC123"]){__typename}` gives `[{"__typename":"Location"},null]`, no errors.
4. Ownership (ana / ACME):
   - `cargos(first:10){edges{node{trackingId}} totalCount}` gives `[VWX901, DEF456, ABC123]`, totalCount 3;
   - `cargo(trackingId:"XYZ789")` gives null with `assert_no_errors`.
5. Ownership (bo / GLOBEX):
   - `cargos(first:10)` gives trackingIds `[XYZ789, STU678]` plus a null node at index 2 with `SERVICE_UNAVAILABLE` (GHI345's fault still applies), totalCount 3;
   - `cargo(trackingId:"ABC123")` gives null, no errors;
   - `node(id:"cargo_ABC123")` null; `node(id:"evt_1")` null;
   - `nodes(ids:["cargo_ABC123","cargo_XYZ789"]){… on Cargo{trackingId}}` gives `[null, {"trackingId":"XYZ789"}]`.
6. Operator (ops): `cargos(first:10){totalCount}` gives 6.
7. Field-level, error vs null:
   - ana `cargo(ABC123){handlingHistory(first:2){edges{cursor node{id registrationTime}}}}` gives error count 2, paths `["cargo","handlingHistory","edges",0,"node","registrationTime"]` and `…,1,…`, code `FORBIDDEN`; `assert_null_at` on both nodes; both cursors non-empty;
   - the same query as ops gives `registrationTime` values `2026-10-01T09:05:00Z`-style seed values (assert the seed literals from `data`), no errors;
   - ana without `registrationTime` gives no errors (the rule is per field).
8. Writes:
   - ana registers UNLOAD DEHAM V100S for ABC123: `assert_null_at '.data'`, code `FORBIDDEN`, 0 `handling.appendEvent`;
   - ops: `evt_10`, `IN_PORT`.
9. Bad tokens, at the HTTP level:
   - a tampered signature (last character flipped) gives `401` and the `WWW-Authenticate` header contains `Bearer`, on both stacks;
   - a token from `other-cli` (no `tracking-api` audience) gives 401.
   - The response is not a GraphQL body (assert the status and header only).
10. Context holds identity only: Python (lab): the README describes the context, and a code check `grep -c 'token' app/context.py` = 0 is **not** used (no grep-on-source assertions). This is checked in CV5 by reading the code.
11. Masking still holds: bo's GHI345 edge error is `SERVICE_UNAVAILABLE` (case 5).
12. Deprecation check, scalar checks, `assert_sdl_conforms` (anonymous introspection).

**Figures (3)**
- `18-token-flow` (data movement): client → Keycloak token endpoint (password grant, lab) → JWT (claims `sub`, `realm_access.roles`, `shipper`, `aud`, `iss`) → GraphQL server → JWKS fetch (cached) → validated identity in the context → resolvers. A 401 exit is drawn for a bad token.
- `18-authorization-layers`: operation level (annotation / permission class), object level (booking source filter, one choke point fed by every path), field level (`registrationTime`). Each is labelled with what a refusal looks like.
- `18-errors-vs-nulls` (data movement): ana's case-7 response beside bo's case-5 response. Errors with paths are shown for the refused field, propagating to the edge node; a silent null is shown for the non-owned cargo. Annotated "fields: error; objects: null".

**Citations.**
- RFC 6750 (Bearer), RFC 7519 (JWT), RFC 8725 (JWT BCP), RFC 9700 (OAuth 2.0 Security BCP).
- OpenID Connect Core (ID vs access tokens).
- Keycloak "Server guide" (import, hostname, health).
- Quarkus "OIDC Bearer token authentication" and the SmallRye GraphQL guide ("Security").
- Strawberry "Permissions".
- PyJWT docs (`PyJWKClient`).
- *Full Stack GraphQL Applications* (its authorization chapter; **spike:** verify the title against the ToC).
- OWASP GraphQL Cheat Sheet (authorization).

---

## 3. Harness additions (`examples/_lib/lib.sh`, C0)

Every change is backward compatible, `bash -n` and shellcheck clean, and uses stdlib `python3 -I`. Each one is documented in `examples/_lib/README.md`'s table. Existing callers behave identically when the new environment variables are unset.

| Function / variable | Contract |
|---|---|
| `LGTM_CACERT` (env) | When set, every curl in `wait_for_graphql`, `gql`, `gql_any`, `gql_meta`, `gql_get`, the `__type` helpers, `source_calls*`, and the new functions adds `--cacert "$LGTM_CACERT"`. `_sdl_diff` exports `NODE_EXTRA_CA_CERTS="$LGTM_CACERT"` for graphql-inspector. **Spike C0-a:** inspector introspection over https with it. |
| `LGTM_BEARER` (env) | When set, the same callers add `-H "Authorization: Bearer $LGTM_BEARER"`. `_sdl_diff` passes `--header "Authorization: Bearer …"` to inspector only when set (Ch18 conformance runs anonymous, so it is unset). |
| `_lib_curl_opts` (internal) | Builds the array of extra curl arguments from the two variables; used by every caller above. Prevents drift. |
| `gql_raw <url> <json-body> [accept] [content-type]` | POSTs the body verbatim (APQ hash-only, arrays, `text/plain`). Output as `gql_any` (status line, then body). |
| `http_any <method> <url> [curl-args…]` | Any method; line 1 is the status, the rest is the body. Non-zero only on transport failure. |
| `http_headers <method> <url> [curl-args…]` | Prints the response headers as lowercase `name: value` lines (final response only); the body is discarded. |
| `header_value <headers> <name>` | Prints the value of the (case-insensitive) header, or nothing. |
| `assert_header <headers> <name> <expected> [ctx]` / `assert_header_absent <headers> <name> [ctx]` | Exact value / absence. |
| `assert_transport_fails <ctx> <curl-args…>` | Passes only if curl exits non-zero (TLS verification, protocol floor, closed port). |
| `sha256_hex <text>` | Lowercase hex SHA-256 of the UTF-8 text (`hashlib`). |
| `apq_body <query-or-empty> <hash> [variables-json] [operationName]` | The APQ JSON body: `extensions.persistedQuery {version:1, sha256Hash}`, with `query` only when non-empty. |
| `apq_get_url <url> <hash> [variables-json]` | URL-encoded GET URL with `extensions` (and `variables`), printed for `http_any GET`. |
| `wait_for_http <url> [timeout] [expected-status]` | Polls until the status matches (default 200), honouring the curl options; FAIL after timeout (default 90). |
| `oidc_token <token-url> <client-id> <username> <password>` | Password-grant POST (form-encoded); prints `access_token`. FAIL with the IdP's error text otherwise. The comment says: lab only, RFC 9700. |

**C0 also:**
- adds `timeout-minutes: 45` to the `examples` job in `.github/workflows/contracts.yml` (nothing else in that file);
- updates the source-call log comment: cache hits are not source calls (Ch16).

**C0 self-test:**
- `bash -n`; shellcheck;
- the Ch0, Ch9 and Ch13 `verify.sh` green (backward compatibility);
- a scratch https smoke test: `python3 -m http.server` is not TLS, so use `openssl s_server -www` on a random port with a generated cert: `wait_for_http` with `LGTM_CACERT` passes, and without it fails;
- `sha256_hex 'abc'` = `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.

---

## 4. Acceptance criteria

**Per chapter (Ch14–Ch18)**
- `_docs/NN-*.md` exists with valid front matter (`part:` resolves, `order` = N), and `bash scripts/wordcount.sh` reports 2,800–3,400.
- The budgeted figures exist (14:4, 15:3, 16:4, 17:2, 18:3 = 16):
  - each paired at `assets/diagrams/NN-slug.{svg,excalidraw}` with a spec at `diagrams/NN-slug.py` that regenerates byte-identically;
  - each embedded with full-sentence alt text and a `Figure N.M — …` caption numbered by appearance;
  - each rendered to PNG and viewed by the executor and by CVn.
- `## On the wire` matches `verify.sh`, then the Decision callout naming Ch2's axes, then `## Where this goes next`. At least one Quarkus|Python codetabs pair.
- `examples/NN-slug/` has README (Ch13's sections plus spike results), `compose.yaml` (fixed `name:`, pinned images only), an executable `verify.sh`, `.gitignore`, `architecture.svg` + `.excalidraw`, `quarkus/` and `python/` with a re-generated `uv.lock`. Ch17 adds `gen-certs.sh`; Ch16 adds `edge/nginx.conf`; Ch18 adds `keycloak/shipping-realm.json`; Ch15 adds `persisted-documents.json`.
- `verify.sh` prints `PASS`. Every §2 assertion is present for both stacks (or per stack where §2 says so). It uses only the harness and stdlib (plus `openssl` in Ch17). `assert_sdl_conforms` passes on both stacks.
- No private key, real secret or token is committed. `git ls-files examples/17-transport-security | grep -E '\.(key|pem|crt)$'` is empty; the realm passwords end in `-fixture-pw`.
- No planning language. `grep -rniE 'wave [a-z0-9]|\bS[0-9]{1,2}\b|\b[BC][0-9]\b|\br0[0-9]\b|iteration|capstone|coverage matrix|phase [0-9]|TODO|TBD|spike' _docs/1[4-8]* examples/1[4-8]*/README.md` returns nothing. READMEs say "Code-first notes", never "spike".
- `lgtm-professional-voice`: 0 ban-tier findings. `lgtm-idiomatic-review`: 0 unresolved substantive findings. In particular:
  - no hand-rolled JWT parsing, TLS, CORS, depth/alias/token limiter or cache where the framework or a pinned library provides one;
  - the only deliberate hand-written pieces are the two named in §8 (the Python cost extension and the persisted-document resolvers, plus Ch17's content-type guard). Each carries a comment saying why.

**Chapter-specific**
- Ch14: identical cost numbers on both stacks for Q_CH1 (385151), Q_WIDE_COST (7651), Q_EDGE(6) (1051), A_BOMB (Quarkus, 1050), F_FAN (1025), N_IDS (1001); Q_EDGE(5) runs; every attack case has 0 source calls.
- Ch15: the three-step handshake on both stacks; GET by hash works; GET mutation refused; trusted mode refuses unknown text and runs manifest hashes without registration.
- Ch16: edge `MISS` → `HIT` with 0 calls on the second GET, `BYPASS` with `Authorization`; the second Q_FAN run gives Python 3 / Quarkus 4; invalidation and expiry cases pass.
- Ch17: https verified with a generated CA; the protocol floor differs as asserted; introspection refused on public instances and conformance passes on internal ones; CSRF content types refused with 0 writes.
- Ch18: ownership filtering including `totalCount`, `node(evt_1)` and `nodes`; field-level `FORBIDDEN` with edge-node nulls; 401 for tampered and wrong-audience tokens.

**For the wave**
- `python3 -I scripts/validate.py` exits 0 (checked via `$?`); `GATE=1 bash scripts/wordcount.sh` passes; the Jekyll build in the `ruby:3.3` container is clean.
- `npm --prefix contracts run lint` and `run breaking` pass; **the `contracts/` diff is empty**.
- All Ch0, Ch3–Ch18 `verify.sh` scripts run concurrently on one host and all pass. This exercises the port rule and Keycloak/nginx beside 32 app containers.
- On PR #1: `verify: 14-query-cost` … `verify: 18-authn-authz` green, and `ci-ok` green.
- Site figure total = 59.
- **Forward references delivered** (CV checks each against the shipped text):
  - Ch1:157 and Ch8:210 (GET in Ch15/16); Ch1:185 (persisted GETs and server caching); Ch1:187 (the nested query is Q_CH1; defenses in 14, transport in 17, auth in 18);
  - Ch2:65 (GET, server caching, caching under the loaders); Ch2:81 (depth/cost 14, introspection and error leaks 17, per-field authorization with unowned reference data 18); Ch2:154;
  - Ch5:145 (cost, caching hints and authorization gated outside the SDL in 14/16/18);
  - Ch6:43 (validation cost: persisted documents with parser/validation caches in 15, fragment and alias bounds in 14); Ch6:188 (introspection control in 17);
  - Ch7:213 (identity in the context in 18); Ch7:292 (controls in 13/14);
  - Ch10:182 (`nodes` bounded by cost in 14); Ch12:15 and :297, Ch13:311 (page size and depth as cost inputs in 14);
  - Ch13:162 and :190 (request and response level, expiry, invalidation, identity in keys, in 16).
- **Deliberate fixes, if needed (CW, never as side effects).** Ch1:185 says "response-level and field-level caching inside the server". Ch16 caches responses at the edge and fields inside the server. If CV3 confirms that the sentence overstates, CW applies a one-clause fix ("plus response caching in front of the server and field-level caching inside it (Chapter 16)") in its own `fix(§1)` commit. Ch1 is `draft`. Any other forward-statement mismatch found by a CV is drafted by the validator and applied the same way.

---

## 5. Risks and detection

| Risk | Detection / mitigation |
|---|---|
| The `GraphQL.Builder` observer cannot see SmallRye's chain, or double-wraps it, so the cost limit is missing or depth stops firing | Ch14 cases 2–4 (exact messages); spike C1-a. If it fails, stop and report; never rebuild SmallRye's chain from guessed contents. |
| graphql-java counts introspection depth, so depth 12 breaks `assert_sdl_conforms` on Quarkus | Spike C1-d: raise both stacks to the smallest passing limit ≤ 15, rebuild D_DEEP, explain in prose. |
| Python and Quarkus cost numbers differ (fragments, `__typename`, defaults, variables) | Identical-message assertions for six queries; spikes C1-c/f. Fix the Python walker to match graphql-java's semantics, then document any irreducible difference. |
| Python cost error masked by `MaskErrors` | Ch14 case 2 asserts the message on Python; fallback is an allowlisted `RequestLimitError` (spike C1-c). |
| Vert.x `reroute` loses parameters or body, or our route does not precede SmallRye's | Ch15 cases 2/4/6; spikes C2-a/b. Stop and report on failure; never touch `RoutingContextInternal`. |
| APQ registration lets anyone store documents (a memory DoS) | Bounded stores (1000 entries) and an eviction note in prose; trusted mode as the production answer (Ch15 §5). |
| `@AfterExecute` header not applied (async thread, response already written) | Ch16 case 1 asserts headers on direct ports; spike C3-a fallback (`addHeadersEndHandler`). |
| nginx UBI image cannot write its cache or pid as uid 1001, or ignores `Cache-Control` | Ch16 cases 2–4; spike C3-c; `/tmp` paths. If nginx proves unusable, report and apply §8 decision 3's alternative (Varnish 9.1.0) only after user sign-off. |
| TTL-dependent cases flaky on slow CI | Whole-second TTLs (5 s) and `sleep 6`; the case-5 handling-count clause degrades per the plan, never silently; CI retries 3×. |
| Cache hides Ch8's fresh payload (stale `delivery` after write) | Ch16 case 6 asserts `IN_PORT` in the payload and the evicted miss. |
| A browser sends simple-content-type POSTs cross-origin without a preflight (CSRF) | Ch17 case 7; spike C4-a adds the content-type guard (generic hardening) and records it in §9. |
| Self-signed CA not trusted by graphql-inspector (Node) | `NODE_EXTRA_CA_CERTS` in C0; spike C0-a; conformance runs on internal instances. |
| SELinux relabel conflicts on shared mounts | `:ro,z` (lowercase) for every mount shared by several containers (Pitfall C-6). |
| Keycloak slow or unhealthy in CI | Healthcheck with `start_period`, `wait_for_http … 180`, job `timeout-minutes: 45`, retries 3×. |
| Issuer mismatch (`iss` from host URL vs compose URL) | Tokens are always fetched at `localhost:8282`, and apps pin `token.issuer`/`issuer` to that value with JWKS by backchannel and discovery off; Ch18 case 4 fails loudly otherwise. |
| SmallRye leaks Quarkus exception class names as codes or messages for auth failures | Spike C5-a; the `DeclaredErrorCodeProvider` mapping; `assert_body_not_contains … 'io.quarkus'`. |
| `SecurityIdentity` missing in async/batch resolvers | Spike C5-d; Ch18 cases 4–7. |
| Object rule bypassed through `node`, `nodes`, `HandlingEvent.cargo` or edges | Ch18 cases 3, 5 (all paths asserted); a single choke point in the booking source. |
| Port collision with a reader's services | Port rule (§1); README notes; ports overridable as in earlier chapters. |
| Citation drift (DDIA 2nd ed. chapter structure; book titles unverified) | Cite only verified titles; CVs check every title with the O'Reilly tool. |
| Untested prose (Apollo `@cacheControl`, Valkey, proxy TLS) | Prose only, no code; CV flags any snippet the example does not run. |
| Strawberry extension-instance deprecation inherited from Ch13 | Factories in every Wave C chapter (Pitfall C-1); grep for `DeprecationWarning` in the Python container log is an informational check in CV. |

---

## 6. Coverage-matrix and plan updates (orchestrator only)

1. **At each chapter checkpoint** (same commit as the chapter): set the chapter to `draft` in both the Topics table (T15 Ch14, T16 Ch15, T17 Ch16, T18 Ch17, T19 Ch18) and the Full chapter inventory. Run `python3 -I scripts/validate.py; echo $?` and `GATE=1 bash scripts/wordcount.sh` before committing. Push.
2. **Verified:** after CVn passes **and** CI `verify: NN-*` is green, flip that chapter's two cells to `verified`. Never flip ahead of the CI evidence.
3. Leave the Diagram budget table unchanged (14:4, 15:3, 16:4, 17:2, 18:3). Record the actual Wave C count (16; site total 59) in the RESUME POINTER.
4. `_example_pages/index.md`, rows 14–18:
   - **14**: Depth, token and alias limits, a list-aware cost budget computed identically on both stacks, and six amplification attacks rejected before any source call.
   - **15**: Apollo APQ handshake and trusted-document allowlisting on both stacks, persisted queries over GET.
   - **16**: Per-response `Cache-Control`, an nginx HTTP cache in front of each stack, field-level server caches with expiry and invalidation on writes.
   - **17**: TLS from framework config with certificates generated at run time, public vs internal endpoints, introspection and suggestions off, CORS, CSRF content types, size limits.
   - **18**: Keycloak-issued JWTs, operation, object and field authorization with `UNAUTHENTICATED`/`FORBIDDEN`, and 401s for bad tokens.
5. `_plans/domain-glossary.md`: add **Trusted document** (a persisted document from a build-time manifest; unknown text is refused), **Query cost** (the Ch14 formula), and **Identity** (what the context carries in Ch18). Extend the Persisted query row: "APQ registers at run time; trusted documents are an allowlist".
6. `_plans/r01-execution-plan.md` RESUME POINTER:
   - S8 set to done with the date and the spike findings (cost-observer approach, introspection depth, APQ front/reroute, AfterExecute headers, nginx UBI behaviour, TLS floors, content-type guard statuses, SmallRye auth codes);
   - the Strawberry extension-instance deprecation recorded for the all-examples chore (Ch9–13);
   - the Quarkus APQ upstream issue draft at `_plans/upstream/smallrye-persisted-queries.md` (persisted-query support; forwarding client `extensions` into `ExecutionInput`), not filed, awaiting the user;
   - a note for S11: Keycloak realm JSON, nginx edge config and the TLS cert script exist per chapter and may be copied; Valkey is deferred to the replica tier;
   - `_plans/iteration-plan.md`: S8 → done.
7. Commits, one checkpoint per step on `r01`:
   - `chore(r01.x): Wave C harness additions (TLS, bearer, APQ, header helpers)` for C0;
   - `docs(§N): …` per chapter (prose, figures, example, matrix `draft`);
   - `fix(§N): …` for repair rounds;
   - `docs(r01): Wave C verified` for the flips and plan updates.

   Push after each and watch CI (lgtm-github conventions).
8. Append a **§9 "Wave C findings"** section to this plan at CW, binding on later waves, in the same form as Wave B's §9.

---

## 7. Binding pitfalls carried forward (every Wave C executor)

**From Wave A §7–§10 (still binding):**
1. Keep `ContractSchemaDetails.withCurrentTypes`. Assert fields through `... on X` via `node`/`nodes`, not only `__typename`.
2. Python scalars use `NewType` + `StrawberryConfig(scalar_map=…)`. No `scalar_overrides`. In Ch17, `disable_field_suggestions` joins the same `StrawberryConfig`.
3. Nulls via `assert_null_at`, absent keys via `assert_absent`, objects and booleans via `assert_json_eq`.
4. Helpers inside `$(...)` end each assertion with `|| return 1`.
5. Gate and drift needles must appear in the tool's change line.
6. SmallRye enum order is alphabetical: compare as sets.
7. Keep `getId()` on `Node`.
8. Constructor injection in `@GraphQLApi` and source beans, including the new `QueryCost`, `PersistedDocumentRoute` and `CachePolicy`.
9. Enum literals are bare in documents.
10. Request errors: Quarkus omits `data`, Strawberry sends `"data": null`. Use `assert_no_data`. The Ch14/15 rejections are request-level.
11. `lib.sh` is bash-only. Use `on_exit` for cleanup (Ch17 certificates, Ch14 generated queries).
12. SDL export needs `schema-include-scalars=true` where used.
13. Keep every source-backed resolver async; Python overlaps only `async def`.
14. Strawberry runs the first of several operations without `operationName`; assert per stack if it comes up.
15. Status codes: both stacks answer 200 for request errors. Quarkus GET is 405 unless `http.get.enabled=true` (Ch15/16 turn it on, Ch17 keeps it off).
16. Request id: Quarkus reads `Context#getExecutionId()` at entry; Python uses `info.context.request_id`. The Ch18 `Viewer` is built the same way, at entry.
17. Python layering: `context.py` has no runtime imports of sources; `deps.py` builds the context (now with `identity`) and the loaders.
18. Source shape `getX(request, key)` over `SourceCalls.call(...)`. Cached bulk operations log only the misses.
19. `TRACKING_SOURCE_LATENCY_MS` (default 0) and `TRACKING_DEBUG_ENDPOINTS` (default false); compose sets 250 / true. New settings follow the same `TRACKING_*` pattern.
20. Never `pkill -f`.
21. `Cargo.delivery` needs the itinerary.
22. Re-run `uv lock` after renaming.
23. `HandlingRecord` vs `HandlingEvent`; a thread-safe store.
24. Loaders are per request. Ch16's caches are app-scoped and live **under** the loaders, at the bulk sources, never inside a loader.
25. Optional Strawberry arguments print no `= null` (`strawberry.Maybe[T | None] = None`).
26. Explicit SmallRye `@Input("…")` names; root descriptions via `ContractSchemaDetails`.
27. Untested prose is a validation finding.

**From Wave B §7 and §9 (binding):**
- **B-1.** Exposed errors are an allowlist on both stacks. Every new exposed error (APQ codes, `UNAUTHENTICATED`, `FORBIDDEN`) must be added to `show-runtime-exception-message` / be an `ExposedError` subclass. Everything else stays masked.
- **B-2.** Batch source keys are sorted distinct keys joined with `+`. With the Ch16 caches, the key is the **misses** only.
- **B-3.** `assert_sdl_conforms` ignores deprecation; call `assert_deprecated` for `finalArrivalDate` in every chapter.
- **B-4.** Never edit a verified Ch0–Ch13 file.
- **Masking:** keep `DeclaredErrorCodeProvider`, the ServiceLoader file, and `quarkus.class-loading.removed-resources."io.smallrye\:smallrye-graphql"=META-INF/services/io.smallrye.graphql.api.ErrorExtensionProvider`. Masked errors carry `"code":null` on Quarkus and no `extensions` on Python. Ch18 extends the provider's mapping; it does not replace it.
- **Logs** carry no GraphQL path and no request id. Never claim otherwise.
- **Mutiny zero delay:** keep the `SourceCalls.afterLatency` guard.
- **SmallRye per-field batching and blast radius:** the `Q_FAN` 8-vs-6 difference and the whole-batch failure (GHI345) still hold. Ch16's run-2 counts (4 vs 3) and Ch18's bo page follow from them.
- **SmallRye `@Id List<String>`:** keep `List<@NonNull String>` plus the `ID_LIST` rewrite. **Deprecation:** keep the `ContractSchemaDetails` `field.deprecate(reason)` workaround.
- **`strawberry.Maybe`** for optional resolver arguments.
- **BadFaithIntrospection:** one `__Type.fields` selection per request.
- **Whole-second times** wherever a cursor or a TTL assertion depends on time.
- **CI:** `ensure_contracts_tools` before any direct npm/npx; `compose_up` runs `down -v` first; `validate.py` exit code checked directly (no `tail`).
- **Authoring:** figures numbered by appearance; full-sentence alt text; render and view every figure; cite books by verified chapter title. Verified so far:
  - DDIA 2nd ed.: Ch1 "Trade-offs in Data Systems Architecture", Ch2 "Defining Nonfunctional Requirements", Ch4 "Storage and Retrieval", Ch5 "Encoding and Evolution";
  - *GraphQL Best Practices*: Ch3 "Crafting Effective GraphQL Schemas";
  - *GraphQL in Action*: Ch4 "Designing a GraphQL schema", Ch7 "Optimizing data fetching", Ch8 "Implementing mutations";
  - *Full Stack GraphQL Applications*: Ch9 "Advanced GraphQL considerations".
- **GraphQL-over-HTTP** wording as settled in Wave B: 400/422 without data, 2xx with data, 294 only with `graphql-response+json`, both stacks 200.

**New in Wave C (binding):**
- **C-1.** Strawberry extensions are passed as classes or factories (`functools.partial`), never as instances (0.335.0 DeprecationWarning, per-request isolation). Do not fix Ch9–13.
- **C-2.** Every rejection Ch14 teaches is asserted with `source_calls_reset` before it and `assert_source_call_count calls '*' '*' 0` after it.
- **C-3.** Cost numbers are asserted as exact messages on both stacks. The Python message must equal graphql-java's format byte for byte.
- **C-4.** Contract checks run against an instance that allows introspection: Ch15 APQ, Ch17 internal, Ch18 anonymous. Say which in the README.
- **C-5.** No private keys, tokens or real secrets in git. Certificates are generated at run time into scratch dirs; fixture passwords end in `-fixture-pw`.
- **C-6.** Shared bind mounts use `:ro,z` (lowercase).
- **C-7.** Second instances reuse the stack's image (`image:` name) with different environment, and never a second build context.
- **C-8.** Cache hits are not source calls; only calls to owners are logged.
- **C-9.** Authorization rules live in one place per kind: annotations or permission classes for operations and fields, the booking source for ownership. Never scatter owner checks across resolvers.
- **C-10.** Tokens for Ch18 are always obtained from `http://localhost:8282` (the `iss` rule).

---

## 8. Open decisions needing user input (each with a recommendation)

1. **The cost model per stack.** Neither framework ships a list-aware cost model; SmallRye's `instrumentation-query-complexity` counts fields, and Strawberry has none.
   **Recommend:**
   - Quarkus: graphql-java's own `MaxQueryComplexityInstrumentation` with a `FieldComplexityCalculator`, appended to SmallRye's chain through the documented `@Observes GraphQL.Builder` event (reading the chain via `builder.build().getInstrumentation()`, because the builder has no getter).
   - Python: a ~60-line `SchemaExtension.on_execute` using graphql-core's `get_argument_values`, implementing the identical formula and message.
   - Both keep the built-in depth/token (and Python alias) limiters.

   The alternatives are config-only field counting, which ignores `first` and breaks introspection, and a validation rule, which cannot see variables.
2. **APQ / persisted documents on Quarkus, where SmallRye has no support.**
   **Recommend** a small Vert.x route in front of SmallRye (`@Observes Router`, order −10) that implements the Apollo protocol and the trusted-document mode, stores documents in `quarkus-cache`, and re-enters SmallRye with `rc.reroute(...)` and SmallRye's own `http.post.queryparameters.enabled`/`http.get.enabled` merge. Python uses a `SchemaExtension.on_operation` at the seam Strawberry's HTTP layer leaves open. Both are hand-written protocol code, because no idiom exists on either stack; the chapter says so. Also draft an upstream SmallRye issue (forward client `extensions` to `ExecutionInput`; accept `PersistedQueryMarker`), not filed without your say-so.
   Rejected: a GraphQL gateway (Hive Gateway, a Node image and Ch20's subject; Apollo Router is not OSS).
3. **The HTTP cache for Ch16.**
   **Recommend nginx from UBI**, `registry.access.redhat.com/ubi10/nginx-126:10.1-1779165744`. It follows the house UBI rule, `proxy_cache` honours `Cache-Control`, and `X-Cache-Status` gives HIT/MISS/BYPASS. The costs: nginx 1.26 rather than upstream 1.30.6 (Red Hat backports fixes), no `Age` header, no OSS purge. Ch16 does not need purge, because edge-cached data is reference data with TTL.
   The alternative is `varnish:9.1.0` (Debian-based; adds `Age`, supports BAN invalidation).
4. **A shared cache server.**
   **Recommend none in Wave C.** In-process Caffeine (`quarkus-cache`) and `cachetools` cover cross-request caching, expiry and invalidation for one replica per stack. Ch16 explains replicas and names Valkey (`valkey/valkey:9.0.6`, BSD) as the shared option. Valkey is deferred to the S11 tier (Ch25–27), where replicas exist; `quarkus-redis-cache` and `valkey-py` 6.2.0 are recorded for then.
5. **TLS approach.**
   **Recommend in-process TLS on both stacks** (Quarkus TLS registry PEM; uvicorn `--ssl-*`) with a CA and server certificate generated by `gen-certs.sh` at verify time, and proxy termination taught in prose. This shows each framework's TLS configuration and the real protocol-floor difference (TLS 1.3 only vs 1.2+).
6. **Identity provider and auth libraries.**
   **Recommend** Keycloak `quay.io/keycloak/keycloak:26.8.1` (UBI-based, Apache-2.0) in `start-dev --import-realm` with a committed realm JSON; `quarkus-oidc` (bearer, service) on Quarkus; `pyjwt[crypto]==2.15.1` with `PyJWKClient` on Python (rather than authlib 1.9.1: a smaller surface for validation only); the password grant for the lab only, with RFC 9700's caveat in prose and README.
7. **Canonical SDL additions.**
   **Recommend none.** Ownership is private data (like `bookedAt`), the field-level rule uses the existing `HandlingEvent.registrationTime`, and no `viewer` field is needed. The `contracts/` diff stays empty, so no gate re-run is needed.
8. **Does Wave C pre-empt S11?**
   **Recommend no.** Each Wave C service (nginx, Keycloak) lives in its chapter's compose with pinned tags and is not shared. S11 may copy the realm JSON, the nginx config and `gen-certs.sh`, and decides there on proxy TLS termination and Valkey for replicas.

### Critical Files for Implementation
- examples/_lib/lib.sh (C0: `LGTM_CACERT`/`LGTM_BEARER`, `gql_raw`, `http_headers`, `apq_body`, `oidc_token`, `wait_for_http`)
- examples/13-dataloaders/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/TrackingApi.java (with `BookingSource.java`, `HandlingRegistration.java`, `DeclaredErrorCodeProvider.java`, `application.properties`; the base for every Wave C copy)
- examples/13-dataloaders/python/app/schema.py (with `deps.py`, `context.py`, `sources.py`, `errors.py`, `registration.py`)
- examples/13-dataloaders/verify.sh and compose.yaml (the skeleton each chapter extends)
- _plans/coverage-matrix.md and .github/workflows/contracts.yml

---

**Notes for the caller (not part of the plan file):**
- **What I verified locally:**
  - Quarkus, SmallRye and graphql-java: config models and javadoc read from the jars under `~/.m2`, plus `javap` of `ExecutionService`, `SmallRyeGraphQLExecutionHandler` and the persisted-query classes;
  - Strawberry 0.335.0: source read from the uv archive `~/.cache/uv/archive-v0/MAJ_QYt-It_BsxNl/strawberry`;
  - image and PyPI versions: queried live from quay.io, Docker Hub, registry.access.redhat.com and PyPI.
- **Findings with impact beyond Wave C:**
  1. Strawberry 0.335.0 deprecates extension instances, and Ch9–13 pass `MaskErrors(...)` as an instance.
  2. Quarkus 3.40's TLS registry defaults to TLS 1.3 only.
  3. SmallRye cannot reach graphql-java's APQ support: it rejects a request with no `query` and does not forward `extensions`.
  4. `quarkus.smallrye-graphql.instrumentation-query-depth` reports a default of 20. Whether that limit is active is unverified (spike C1-d).
- **Sources used:**
  - [quay.io Keycloak tags](https://quay.io/repository/keycloak/keycloak)
  - [O'Reilly: DDIA 2nd ed.](https://www.oreilly.com/library/view/-/9781098119058)
  - [O'Reilly: DDIA ch01 preview](https://www.oreilly.com/library/view/designing-data-intensive-applications/9781098119058/ch01.html)
  - [graphql-kotlin APQ](https://opensource.expediagroup.com/graphql-kotlin/docs/server/automatic-persisted-queries/)
  - [Escape APQ explainer](https://docs.escape.tech/dast/vulnerabilities/configuration/graphql_apq)

---

## 9. Wave C findings (binding on later waves)

These were recorded from execution and Opus validation on 2026-10-16. They are engineering notes only.

**Reader-facing text: a tutorial, not an issue log**
- State each technique as the design.
- No framework-defect narratives, no upstream issue numbers, no "workaround" or spike write-ups, and no bypass stories. Report every hit under `lgtm-professional-voice` rule 13; rule 14 covers the site chrome.
- Describe stack differences neutrally.
- Spec conformance is phrased as "the draft recommends X; the stack answers Y; clients read the body".
- `_plans/` is not rendered (`plans: output: false`).
- Upstream drafts live outside this repo.

**Test code shows behaviour, not attack recipes**
- Inputs for refusal cases come from small, neutrally named generators.
- Assert the refusal (status, `extensions.code`, 0 source calls). Never assert counts or timings that describe a document's shape.
- verify messages name the case and the outcome only.

**Limits (Ch14)**
- The cost, alias and depth limits are all asserted with 0 source calls.
- The cost budget clamps each field at `Integer.MAX_VALUE / maxTokens`, so sibling sums stay inside 32-bit range.
- The alias and depth limits count each fragment definition once on both stacks. On Python they are `AddValidationRules` rules with Strawberry's counts and messages.
- `@skip` and `@include` are honoured by the Python cost walker.

**Persisted documents and GET (Ch15/Ch16)**
- The route hands on exactly the text it checked, on GET and POST.
- It refuses any request with an `Upgrade` header (HTTP only until Ch21).
- It rejects an `operationName` that names no operation in the document, and fails closed on parse errors.
- It adds a POST-only `BodyHandler` (no uploads).
- Strawberry renders its IDE when `Accept` includes `text/html` or `*/*`, so hash-only GETs send `Accept: application/json`.

**Caching (Ch16)**
- `public` responses carry `Vary: Accept`.
- The nginx key is `$scheme$request_method$proxy_host$request_uri`.
- The lab TTL is 20 s.
- Quarkus `@CacheResult` stores unknown-key results (negative caching); Python does not.

**Harness**
- `status_of` reads the status line without a pipe.
- Avoid `producer | head` under `pipefail` in every verify.sh.

**Cross-chapter chore (all examples)**
- Every Quarkus stack sets an OTLP endpoint to `lgtm` even when the observability profile is off. The exporter then blocks on DNS for 3–4 s at a time, which is the likely source of TTL timing pressure.
- Strawberry extension instances in Ch9–Ch13 emit a 0.335.0 DeprecationWarning; they should be passed as factories.

**Books (verified titles)**
- *GraphQL Best Practices*: Ch10 "Keeping Data Secure".
- *Full Stack GraphQL Applications*: Ch7 "Adding authorization and authentication".
- DDIA 2nd edition: Ch1 "Trade-offs in Data Systems Architecture".
