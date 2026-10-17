---
layout: plan
render_with_liquid: false
title: "r01 Wave E Plan — Ch23–Ch24 (Testing & Debugging)"
---

# Wave E (S10): Ch23–Ch24, Testing & Debugging

**Status: DONE 2026-10-17 (E0–E2, EV1–EV2, EW); Ch23–24 verified, CI green at 9002628. APPROVED by user 2026-10-17 — §8 decisions 1–14 as recommended (k6 v2.3.0 on UBI; quarkus-logging-manager 3.4.2, which works on 3.40.1, so the configuration fallback was not used).**

This plan is written for Sonnet executors. Where it gives a value (a port, a path, a test name, a config key, an error code, a count, an image tag), use exactly that value. Where it says **spike**, check the behaviour on the pinned versions before writing prose that depends on it, and record what you observe in the example README under "Code-first notes". If a spike contradicts an expected value here, assert what you observed, rewrite the prose to match, and report it to the orchestrator. Never weaken an assertion without saying so.

**Precondition.** S9 (Wave D) and DX are done: Ch0 and Ch3–Ch22 are `verified`, CI is green at `e5710fb`. Ch23 starts from `examples/14-query-cost/` (batching and the cost limits, the two behaviours a load run must hold). Ch24 starts from `examples/19-observability/` (traces, metrics and logs by trace id, the material a diagnosis reads).

**The content rule (binding on every executor and validator).** The site is a GraphQL tutorial, not an issue tracker. Reader-facing text (chapters, READMEs, code comments, test names and messages, verify messages, figure labels and alt text) states every technique positively, as the design. It never describes framework bugs, limitations, upstream issues, workarounds or security weaknesses of any framework, and it carries no issue numbers. Ch24 debugs **the application**: its data, its resolvers, its own code paths. It never presents a framework as the thing at fault. Stack differences are described neutrally ("Quarkus serves the GraphQL UI in dev mode; Strawberry serves GraphiQL on the GraphQL path when the IDE is enabled"). This is `lgtm-professional-voice` rules 13–14. If an executor observes behaviour that looks like a framework defect, it reports it to the orchestrator in one neutral line and writes nothing about it in the repository, including `_plans/`.

---

## 0. Facts checked (2026-10-16)

Read from the local Maven repository (`~/.m2`, Quarkus BOM 3.40.1), the uv archive of Strawberry 0.335.0, PyPI, Maven Central, GitHub releases, Docker Hub and `registry.access.redhat.com` on 2026-10-16. Anything marked *spike* has not been run.

**Quarkus 3.40.1 test stack (from `quarkus-bom-3.40.1.pom`)**
- `io.quarkus:quarkus-junit` is the test extension (JUnit Jupiter **6.1.3**). `quarkus-junit5` is a relocation to it; use `quarkus-junit`.
- `io.quarkus:quarkus-junit-mockito` (`@InjectMock`) and `io.quarkus:quarkus-junit-component` (`@QuarkusComponentTest`) are managed.
- `io.rest-assured:rest-assured` **6.0.1** is managed. `org.awaitility:awaitility` 4.3.0 is managed.
- `io.quarkus:quarkus-smallrye-graphql-client` is managed (SmallRye GraphQL client 2.18.5): `TypesafeGraphQLClientBuilder`, `DynamicGraphQLClientBuilder`, `ErrorOr<T>`; Ch22 already uses it.
- The BOM does not manage `maven-surefire-plugin`; the newest stable is **3.6.0** (Maven Central). Quarkus projects set `<surefire-plugin.version>` and the `java.util.logging.manager` system property for the plugin.
- `quarkus.http.test-port` (`0` picks a free port).
- `quarkus-smallrye-graphql` config (from `META-INF/quarkus-config-doc/quarkus-config-model.json`):
  - `quarkus.smallrye-graphql.ui.always-include` (build time, default `false`): the GraphQL UI (GraphiQL) is included in dev and test mode and not in a production build unless this is set.
  - `quarkus.smallrye-graphql.ui.root-path` (build time, default `graphql-ui`, so `/q/graphql-ui`), `quarkus.smallrye-graphql.ui.enabled` (run time, default `true`).
  - `quarkus.smallrye-graphql.log-payload` (run time, default `off`; values `off`, `query-only`, `query-and-variables`, **spike** E2-d for the exact names).
- Dev UI is served under `/q/dev-ui` in dev mode only. Access from a host other than localhost is governed by Dev UI's allowed-hosts setting (**spike** E2-a: property name, expected `quarkus.dev-ui.hosts`, and whether a request through a published container port counts as remote).
- `quarkus:go-offline` (quarkus-maven-plugin goal) resolves the dev- and test-mode dependencies that `dependency:go-offline` misses (**spike** E1-a / E2-b).

**Strawberry 0.335.0 (uv archive)**
- `strawberry.asgi.test.GraphQLTestClient` (subclass of `strawberry.test.client.BaseGraphQLTestClient`) wraps a Starlette `TestClient`: `client.query(query, variables=…, asserts_errors=False)` returns `Response(errors, data, extensions)`.
- `await schema.execute(query, variable_values=…, context_value=…, operation_name=…)` runs in process; `schema.execute_sync` exists for synchronous resolvers only (every resolver here is `async`, so tests use `execute`).
- `GraphQLRouter(..., graphql_ide="graphiql" | "apollo-sandbox" | "pathfinder" | None)`; default `"graphiql"`. Ch17 builds it with `graphql_ide=None if settings.public else "graphiql"`. The router has no payload-logging switch; Ch24's Python debug output is the application's own logger.

**FastAPI testing idiom.** FastAPI's "Async Tests" page uses `httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")` with `@pytest.mark.anyio`; `ASGITransport` does not run the lifespan, and the page points to `asgi_lifespan.LifespanManager` for that. Every example creates `app.state.calls` and `app.state.store` in the lifespan, so the integration fixture wraps the app in `LifespanManager`.

**Registries (latest stable, checked 2026-10-16)**

| Component | Version | Licence | Released | Used in |
|---|---|---|---|---|
| Quarkus platform | 3.40.1 (unchanged) | Apache-2.0 | — | both |
| `quarkus-junit` (JUnit Jupiter) | BOM (JUnit 6.1.3) | Apache-2.0 / EPL-2.0 | — | Ch23 |
| `quarkus-junit-mockito` | BOM | Apache-2.0 | — | Ch23 |
| `rest-assured` | 6.0.1 (BOM) | Apache-2.0 | — | Ch23 |
| `quarkus-smallrye-graphql-client` (test scope) | BOM (SmallRye 2.18.5) | Apache-2.0 | — | Ch23 |
| `maven-surefire-plugin` | 3.6.0 | Apache-2.0 | 2026 | Ch23 (and Ch24 `pom.xml` for parity) |
| `io.quarkiverse.loggingmanager:quarkus-logging-manager` | 3.4.2 (built against Quarkus 3.20.2; **spike** E2-c on 3.40.1) | Apache-2.0 | 2026-05-02 | Ch24, §8 decision 6 |
| strawberry-graphql | 0.335.0 (unchanged) | MIT | 2026-10-14 | both |
| fastapi | 0.143.2 pinned (0.143.3 released 2026-10-16; not bumped in-wave) | MIT | — | both |
| pytest | 9.1.1 | MIT | 2026-06-19 | Ch23 |
| anyio (pytest plugin) | 4.15.1 | MIT | 2026-09-05 | Ch23 |
| pytest-asyncio | 1.4.0 (alternative, §8 decision 12) | Apache-2.0 | 2026-05-26 | — |
| httpx | 0.28.1 | BSD-3-Clause | 2024-12-06 | Ch23 |
| asgi-lifespan | 2.1.0 | MIT | 2023-03-28 | Ch23 |
| Grafana k6 | v2.3.0 (`k6-v2.3.0-linux-amd64.tar.gz` + `k6-v2.3.0-checksums.txt`; image `grafana/k6:2.3.0` digest `sha256:9c2dee7f8ed7…` is the non-UBI alternative) | AGPL-3.0 (OSI-approved, no fees, no key) | 2026-09-21 | Ch23 load, §8 decision 1 |
| Locust | 2.46.7 (gevent 26.9.0 has cp314 wheels) | MIT | 2026-10-04 | §8 alternative |
| vegeta | v12.13.0 | MIT | 2025-10-31 | §8 alternative |
| `registry.access.redhat.com/ubi10/ubi-minimal` | `10.2-1791891203` | — | 2026-10-13 | Ch23 load image |
| `ubi10/openjdk-25` / `-runtime` | `1.24-16` (newest; unchanged) | — | — | both |
| `ubi10/python-314-minimal` | `10.2-1791928506` (newest; unchanged) | — | — | both |
| uv | 0.13.1 (unchanged) | MIT / Apache-2.0 | — | both |
| `grafana/otel-lgtm` | 0.37.0 (newest; unchanged since DX) | Apache-2.0 | 2026-10-16 | Ch24 |
| `@graphql-inspector/cli` | 7.0.1 (already in `contracts/`; `validate`, `coverage`, `diff` commands installed) | MIT | — | Ch23 |

**The documents Ch22 ships** (`examples/22-client-integration/clients/js/src/operations.graphql`): `TrackCargo`, `TrackCargoBrief`, `RegisterHandling`, `ListCargos`; fixture `clients/js/fixtures/cargo-weight.graphql`.

**Ch14 values Ch23 relies on.** Budget 1000; message `maximum query complexity exceeded <cost> > 1000` on both stacks, no `data`, 0 source calls; `Q_WIDE_COST` costs 7651; `Q_FAN` (four-cargo page) costs 53 and makes 8 source calls on Quarkus, 6 on Python; GHI345 fails at the booking source (`SERVICE_UNAVAILABLE`; Quarkus nulls the whole batch, Python one edge).

**Ch19 values Ch24 relies on.** One operation span per request named `query <OperationName>`; resolver spans descend from it; `source.call` spans with `source.name`/`source.operation`; the exception log record carries `trace_id` (structured metadata in Loki) with `exception_type` and `exception_message`; masked errors are `Internal server error.` with `"code":null` on Quarkus and no `extensions` on Python.

**Books.** Verified titles so far are listed in Wave C §7. For Ch23/Ch24 every new title is a **spike** (O'Reilly ToC); cite by verified chapter title only and only where the chapter covers testing or debugging (*GraphQL Best Practices* and *Full Stack GraphQL Applications* are the likely sources). DDIA is not required in Wave E.

**Figures.** The site has 75. Wave E adds 4 (Ch23 2, Ch24 2): total 79. S11 adds 10 (Ch25 2, Ch26 2, Ch27 3, Appendix A 3) for 89.

**Forward references this wave must deliver** (grep of `_docs/` and example READMEs for "Chapter 23", "Chapter 24", "Ch23", "Ch24", testing and debugging mentions):
- **Ch5:182**: "The export also belongs inside each service's own test suite … Chapter 23 builds the real test suites." Ch23's schema tests are the real versions of Ch5's two sketches (`@QuarkusTest` fetching `/graphql/schema.graphql`; `schema.as_str()` in pytest), and the exported SDL is then diffed against the canonical SDL.
- **Ch22:319**: "Chapter 23 tests the whole of it: what a GraphQL API suite asserts at each layer, and the load-testing harness that runs the same documents at volume." Ch23 teaches every layer and its load run executes Ch22's documents.
- **Execution plan, risks**: "N+1 silently present in example code → resolver-call-count assertion in Ch13/Ch24 verify.sh." Ch24's verify asserts the batched source-call count read from a trace, and Ch23 asserts it per request under load.
- **Part 11 blurb**: "Prove conformance, load-test the graph, and diagnose a misbehaving GraphQL service end to end."
- **Ch17:109** (GraphiQL off on the public instance) is echoed, not contradicted, by Ch24's dev-versus-production surfaces.
- **Ch19, Ch9, Ch20**: Ch24 reads Ch19's traces and logs, Ch9's codes and masking, and points to Ch20's per-subgraph request counts as the way to read a query plan (prose only).

---

## 1. Approach

### Sequencing (DAG)

| Step | Executor | Owns (exclusive write set) | Depends on |
|---|---|---|---|
| **E0** Harness | Executor 1 | `examples/_lib/lib.sh`, `examples/_lib/README.md` | S9 + DX |
| **E1** Ch23 Testing GraphQL APIs | Executor 2 | `_docs/23-*`, `examples/23-testing/**`, `diagrams/23-*.py`, `diagrams/examples/23-*`, `assets/diagrams/23-*` | E0 (copies Ch14) |
| **E2** Ch24 Debugging GraphQL | Executor 3 | same pattern for `24-*` | E0 (copies Ch19) |
| **EV1, EV2** Validation (Opus), one per chapter | Opus | read-only findings; fixes routed to the owning executor | the chapter's step |
| **EW** Wrap (orchestrator) | orchestrator | `_plans/*`, `_example_pages/index.md`, coverage-matrix flips, commits, deliberate one-clause fixes (§4) | EV1, EV2 + CI green |

How to run it:
- E0 is small (four helpers, §3). After it lands, run **E1 and E2 in parallel**. Neither depends on the other: each copies its own base and writes only its own `NN-*` paths.
- The critical path is E0 → E1 (two test images, a load image, four load runs per stack).
- **Shared files are single-owner.** Only E0 edits `lib.sh` and its README. Only the orchestrator edits `_plans/`, `coverage-matrix.md` and `_example_pages/`. **Nobody edits `contracts/` or `.github/workflows/`** (§8 decisions 10 and 11). A helper E0 did not provide is written as a local function at the top of the chapter's `verify.sh`, reported in the hand-back, and promoted by the orchestrator at EW if it is reusable.
- Each EVn starts as soon as its chapter's checkpoint commit lands. At most two repair rounds per chapter; a third failure goes back to the user.

**Executor rules (unchanged from Waves A–D, binding)**
- Write files only. No git.
- Do not touch `_plans/*`, `coverage-matrix.md`, `_example_pages/`, `scripts/`, `contracts/`, `.github/`, `examples/_lib/` (only E0), or any other chapter's files, including every verified Ch0–Ch22 file. Ch23 **reads** Ch22's documents (§2 Ch23 case 6); it never writes them.
- Never delete or reinstall `contracts/node_modules`.
- Never `pkill -f`. Several stacks run concurrently; stop only your own with `docker compose -p <your project> down -v`.
- Before handing back, every executor runs its own `verify.sh` green; `python3 -I scripts/validate.py; echo rc=$?` (never piped through `tail`); `bash scripts/wordcount.sh _docs/NN-*.md`; `npm --prefix contracts run lint`; and renders every new figure to PNG and **views** it.
- Tests and builds run only inside the pinned UBI images (`mvn` in `ubi10/openjdk-25`, `uv run pytest` in `ubi10/python-314-minimal`), never with the host's JDK, Maven, Python or uv.

**Orchestrator rule.** At each chapter's checkpoint commit, flip that chapter to `draft` in **both** the Topics table (T24, T25) and the Full chapter inventory, in the same commit, then push so CI runs `verify: 23-testing` / `verify: 24-debugging`, the wordcount GATE and `validate.py`. A chapter is `verified` only after EVn passes **and** the CI job is green.

**Rejected alternatives (one line each)**
- *Serial Ch23 → Ch24*: no real dependency; Ch24 needs Ch19's telemetry, Ch23 needs Ch14's limits.
- *One example for both chapters*: couples a load run to an LGTM stack and a dev-mode container; each chapter would fail for the other's reasons.
- *Tests on the host toolchain*: breaks the "pinned UBI images only" rule and diverges from CI.
- *Testcontainers inside the test suites*: the tests start the application in process (`@QuarkusTest`, ASGI transport); there is no backing service to start, so a container runtime inside a test container adds nothing.
- *A browser test of GraphiQL (Playwright)*: the dev/production difference is an HTTP fact (200 HTML versus 404); a browser image adds nothing a headless check does not show.
- *Absolute latency thresholds in the load run*: not robust on a shared GitHub runner; the load run asserts correctness invariants only (§2 Ch23).

### Example structure

Same as Waves A–D: a self-contained copy per chapter, package `com.patterncatalyst.shipping.tracking`, Python package `app`. For each chapter change the artifactId, the Python project name (then **re-run `uv lock`**), `quarkus.otel.service.name` / `OTEL_SERVICE_NAME`, the container names and the compose `name:`. `.gitignore` adds `python/.ruff_cache/`, `quarkus/target/`, `python/.venv/`, `python/.pytest_cache/`.

**Pins** are identical to Wave D after DX (Quarkus 3.40.1; Strawberry 0.335.0; FastAPI 0.143.2; uvicorn 0.54.0; uv 0.13.1; pydantic-settings 2.16.0; OTel as in Ch19; `ubi10/openjdk-25:1.24-16`; `ubi10/python-314-minimal:10.2-1791928506`; `grafana/otel-lgtm:0.37.0`). If a newer stable release exists at execution time, **do not** bump it inside Wave E; record it for the orchestrator.

**New pins in Wave E**

| Chapter | Addition | Pin |
|---|---|---|
| 23 | Quarkus test deps (`<scope>test</scope>`) | `io.quarkus:quarkus-junit`, `io.quarkus:quarkus-junit-mockito`, `io.rest-assured:rest-assured`, `io.quarkus:quarkus-smallrye-graphql-client` (all BOM) |
| 23 | Surefire | `maven-surefire-plugin` 3.6.0 with `java.util.logging.manager=org.jboss.logmanager.LogManager` and `maven.home` system properties (the Quarkus project template's configuration) |
| 23 | Python dev group (`[dependency-groups] dev`) | `pytest==9.1.1`, `httpx==0.28.1`, `asgi-lifespan==2.1.0`, `anyio==4.15.1` (pinned explicitly; already transitive) |
| 23 | Load image | `ubi10/ubi-minimal:10.2-1791891203` + k6 v2.3.0 static binary from the GitHub release tarball, verified against `k6-v2.3.0-checksums.txt` (sha256 recorded in the Containerfile, as the CI workflow does for kubeconform) |
| 24 | Quarkus runtime log levels | `io.quarkiverse.loggingmanager:quarkus-logging-manager:3.4.2` (only if spike E2-c passes; §8 decision 6) |

### How the schema slice grows

| Ch | Base | Served slice | Behaviour added |
|---|---|---|---|
| 23 | Ch14 | Ch14's (all but `Subscription`) | test suites on both stacks (schema, resolver unit, operation integration, client documents), exported SDL diffed against the contract, client-document validation and coverage, a k6 load run asserting batching, cost refusals and idempotency under concurrency |
| 24 | Ch19 | Ch19's (all but `Subscription`) | one seeded data fault (`JKL012`), `extensions.traceId` on errors, a dev instance per stack beside the production instance, an application debug category switched at run time |

### Canonical SDL changes

**None.** The `contracts/` diff for Wave E must be empty. `extensions.traceId` (Ch24) is a response extension, not schema.

### Seed data

**Ch23:** Ch14's seed unchanged (it is Ch13's). Registrations used:

| Name | Input | Expected |
|---|---|---|
| `REG_A1` | ABC123 `UNLOAD` DEHAM `V100S` `2026-10-09T15:00:00Z`, `idempotencyKey` `ch23-load-a1` | `evt_10`, `IN_PORT` |
| `REG_T1` (test suites only) | DEF456 `CUSTOMS` as Wave D's `REG_D1` (**spike**: reuse the input Ch21 recorded), `idempotencyKey` `ch23-test-d1` | next id, `userErrors` empty |

**Ch24:** Ch19's seed plus **one seeded fault**, cargo `JKL012`:
- booking: `JKL012`, "Machine parts", origin `NLRTM`, destination `USNYC`, booked **earlier than every Ch13 seed** so `cargos(first: 4)` and the Ch19 `Q_FAN` data are unchanged (**spike**: confirm the Ch19 `Q_FAN` result and counts are byte-identical; `cargos(first: 10)` now has seven edges);
- routing: two legs, `NLRTM → DEHAM` on `V100S`, then `DEHAM → XXBAD` on `V200E`; `XXBAD` is a well-formed UN/LOCODE the location source does not hold (**spike**: the `UnLocode` scalar serializes it on both stacks);
- handling: one event `evt_jkl_1`, `UNLOAD` at `XXBAD`.

The two faults it produces, both caused by data and both reached through ordinary queries:
- **F1 (non-null violation):** `cargo(trackingId: "JKL012") { itinerary { legs { unloadLocation { name } } } }`: the location loader returns null for `XXBAD`; `Leg.unloadLocation: Location!` cannot be null, so the error path is `["cargo","itinerary","legs",1,"unloadLocation"]` and `itinerary` (nullable) becomes null (Ch4). Message per stack **spike** E2-e.
- **F2 (masked unexpected error):** `cargo(trackingId: "JKL012") { delivery { transportStatus } }`: `DeliveryDerivation` looks up the last event's location (`self._locations[last.un_locode]` on Python; the Java equivalent on Quarkus) and raises (`KeyError` / the Java exception, **spike** E2-e). The client gets `Internal server error.`; the log record holds the exception; `Cargo.delivery: Delivery!` nulls `cargo`.

Ch24 does **not** change `DeliveryDerivation` to tolerate the fault: the chapter diagnoses it and states the fix in prose (the location owner adds `XXBAD`, or the derivation treats an unknown location as `lastKnownLocation: null`), because the example's job is to stay reproducible.

### Ports, project names, extra services

**Rule (unchanged):** chapter N owns host ports 8100+10·N … +9; Quarkus +0, Python +1, extras +2…+9. Internal-only services publish nothing.

| Ch | dir | Quarkus | Python | extras (host → container) | compose `name:` / `PROJECT` | container prefix | artifactId / Python project |
|---|---|---|---|---|---|---|---|
| 23 | `23-testing` | 8330 | 8331 | — ; `quarkus-test`, `python-test`, `load` have no ports (profiles, `compose_run`) | `gql-ch23-testing` | `ch23-testing-` | `ch23-quarkus-testing` / `shipping-python-ch23-testing` |
| 24 | `24-debugging` | 8340 (production jar) | 8341 (production) | 8342 → `quarkus-dev`:8080 (dev mode), 8343 → `python-dev`:8080, 8344 → lgtm:3000 (Grafana), 8345 → lgtm:3200 (Tempo), 8346 → lgtm:9090 (Prometheus), 8347 → lgtm:3100 (Loki); OTLP internal only | `gql-ch24-debugging` | `ch24-debugging-` | `ch24-quarkus-debugging` / `shipping-python-ch24-debugging` |

- Ch24 departs from "Quarkus +0, Python +1" only for the dev instances and LGTM; the README's Ports table states the mapping.
- `python-dev` reuses the `python` image (`image:` name, C-7) with different environment. `quarkus-dev` is the `dev` target of the same Containerfile (§2 Ch24): dev mode runs from sources, so it cannot be the production image.
- **CI.** One example per `ubuntu-latest` job (4 vCPU, 16 GB); `timeout-minutes: 60` and three attempts already in place; the matrix discovers both new `verify.sh` files with no workflow change. Estimates per attempt, cold: Ch23 ~10 min (two Maven builds plus a Maven test run, two uv syncs plus a pytest run, the k6 image, four load runs per stack at ~20–40 s each); Ch24 ~11 min (LGTM pull, a production and a dev-mode Quarkus, dev-mode start ~60–90 s, two Python instances from one image). New pulls: `ubi10/ubi-minimal:10.2-1791891203` and the k6 tarball from GitHub releases (Ch23). No new host tooling: the host keeps bash, curl, `python3 -I` stdlib, docker and the Node 24 the workflow already sets up.

---

## 2. Per chapter

**Common to both chapters** (as in Waves A–D):
- **Front matter:** `title` (Ch23 "Testing GraphQL APIs", Ch24 "Debugging GraphQL"), `order: N`, `part:` exactly "Testing & Debugging", `description`, `duration` (words/200).
- **Length and figures:** 2,800–3,400 prose words (`wordcount.sh`); figures via `{% include excalidraw.html file="NN-slug" alt="…full sentences…" caption="Figure N.M — …" %}`, numbered by order of appearance; at least one `{% include codetabs.html langs="Quarkus|Python" %}` (validate.py checks the fence count).
- **Last three blocks:** `## On the wire` (commands and the exact values `verify.sh` asserts), the Decision callout naming Ch2's axes, `## Where this goes next`.
- **Prose rules:** no `{{`/`{%` outside includes and fences; books by verified chapter title only; spec sections by name; "execution error"; never claim a framework's log carries the GraphQL path or a request id (the **application's** debug line in Ch24 carries a field coordinate, because it writes one; the Loki record carries the trace id, because it is asserted); every Java/Python/JavaScript snippet in prose exists in the example (Pitfall 27); the content rule.
- **Diagram specs:** `diagrams/NN-slug.py`; architecture figures `diagrams/examples/NN-slug-architecture.py` (not counted). Data-movement figures drawn from a run name that run in the spec docstring. Regenerate; never hand-edit SVG.
- **verify.sh skeleton:** the base chapter's; `source_calls_reset` before each counted case; one `__type` per request; the scalar `kind`/`specifiedByURL` loop; `assert_deprecated` for `finalArrivalDate`; `assert_sdl_conforms` last; scratch dir via `on_exit`; `ensure_contracts_tools` before direct npm/npx.
- **README sections** (Ch13 order): The served slice, Run it, The source-call log (lab only), Ports, On the wire, Code-first notes (spike results), Diagram. Ch23 adds "Running the tests" after Run it; Ch24 adds "Dev and production instances" after Ports.

### Ch23: Testing GraphQL APIs

**Files:** `_docs/23-testing-graphql-apis.md`, `examples/23-testing/` (from Ch14).

**Learning goals.** By the end of the chapter the reader can:
- name the test layers for a GraphQL API and what each one proves: schema, resolver unit, operation integration, contract, client document, load (Figure 23.1);
- write each in-process layer idiomatically: `@QuarkusTest` with RestAssured and the SmallRye typesafe client; pytest with `schema.execute`, Strawberry's `GraphQLTestClient` and httpx `AsyncClient` over the ASGI app;
- assert GraphQL semantics instead of HTTP status: `data` beside `errors`, error paths and `extensions.code`, partial results (Ch9), the same as `verify.sh` does;
- turn Ch13's batching into a regression test by counting source calls inside the test;
- export the schema from the test suite and diff it against the canonical SDL (Ch5's promise);
- validate a client's documents against the contract and measure what they cover (Ch22's documents);
- load-test with assertions that hold on any machine: zero transport failures, every check true, the per-request source-call count unchanged under concurrency, every over-budget document refused, one write for many concurrent retries (Figure 23.2).

**H2 outline**
1. *What a GraphQL test asserts.* A 200 proves nothing (Ch6, Ch9); a test reads `data`, `errors`, paths and codes. The six layers and where each runs (Figure 23.1).
2. *Schema tests.* Ch5's sketches made real: `SchemaExportTest` (Quarkus, `GET /graphql/schema.graphql`) and `test_schema.py` (`schema.as_str()`), each writing the exported SDL to a report directory. What a schema test catches in seconds and what only the diff catches.
3. *Resolver unit tests.* Pure units first: `DeliveryDerivation` and the cost calculator with no server. Then a resolver with a stubbed source: Quarkus `@InjectMock BookingSource` making `getCargo` fail and asserting `SERVICE_UNAVAILABLE` at the field path; Python `schema.execute` with a context whose booking source raises the same exception.
4. *Operation integration tests.* The app in process, a request over its HTTP layer: RestAssured POSTs; the SmallRye typesafe client (`TypesafeGraphQLClientBuilder` against `@TestHTTPResource`) with `ErrorOr` for the GHI345 edge; Strawberry's `GraphQLTestClient`; httpx `AsyncClient` with `ASGITransport` inside `LifespanManager`.
5. *Testing behaviour the schema cannot show.* The batching regression test: inject the source-call log (`SourceCalls` bean; `app.state.calls`), run `FanOut`, assert 8 / 6 calls and the bulk keys. The cost limit: over-budget refused with the exact message and 0 calls. Idempotent replay of `REG_T1`.
6. *Contract tests.* The schema exported by the test run, and the live endpoint, diffed against `contracts/schema/` with graphql-inspector (`assert_sdl_conforms`); the breaking gate (Ch11) stays on the contract itself.
7. *Client documents as tests.* Ch22's documents copied into `documents/`: `graphql-inspector validate` against the canonical SDL (a document selecting `Cargo.weight` fails), `graphql-inspector coverage` showing which fields clients use, and the same documents executed by both test suites.
8. *Load tests that assert correctness.* k6 runs the documents at volume (Figure 23.2): `shared-iterations` executors for exact counts, `checks` on the GraphQL body, thresholds `http_req_failed rate==0` and `checks rate==1`; afterwards, the server's source-call log grouped by request id. Why latency is reported and not asserted on a shared runner.
9. *Where tests run.* A `test` target in each Containerfile: `mvn verify` and `uv run pytest` inside the pinned UBI images; reports and exported SDL written to a mounted directory; production images build with tests skipped because the test image ran them. Dev Services start backing services for `@QuarkusTest` when an extension needs one; this example has none.
10. On the wire / Decision / next (Ch24: when a test fails in production instead).

**Example design**
- **Server code:** Ch14's two stacks unchanged apart from names and ports, and `TRACKING_SOURCE_LATENCY_MS=50` in compose (§8 decision 9; **spike** E1-b: the Ch14 `Q_FAN` counts and keys are identical at 50 ms).
- **`documents/`** (shared by both test suites, `graphql-inspector` and k6):
  - `track-cargo.graphql`, `track-cargo-brief.graphql`, `register-handling.graphql`, `list-cargos.graphql`: byte copies of Ch22's four operations, one per file (verify case 6 checks they are the same text as Ch22's `operations.graphql`, operation by operation);
  - `fan-out.graphql`: `query FanOut` = Ch14's `Q_FAN` with that name;
  - `fixtures/cargo-weight.graphql`: byte copy of Ch22's fixture;
  - `load/over-budget.graphql`: `query OverBudget` = Ch14's `Q_WIDE_COST` (cost 7651).
  Images receive it through `build.additional_contexts: documents: ./documents` (D-7), copied to `src/test/resources/documents/` and `tests/documents/`.
- **Quarkus tests** (`quarkus/src/test/java/com/patterncatalyst/shipping/tracking/`), all `@QuarkusTest` unless stated, `quarkus.http.test-port=0` in `src/test/resources/application.properties`, latency 0, debug endpoints off:
  - `SchemaExportTest`: GET `/graphql/schema.graphql` → 200, contains `type Cargo implements Node`, `scalar TrackingId`; writes the body to `${tracking.test.export-dir:target}/schema.graphql`.
  - `DeliveryDerivationTest` (plain JUnit, no Quarkus): last event `UNLOAD` at DEHAM → `IN_PORT`; no events → `NOT_RECEIVED`.
  - `CostCalculatorTest` (plain JUnit or `@QuarkusTest` per what the calculator needs, **spike**): `Q_FAN` costs 53, `Q_WIDE_COST` 7651.
  - `BookingFailureTest`: `@InjectMock BookingSource`; `getCargo` fails with `SourceUnavailableException("booking service unavailable")`; `cargo(trackingId: "ABC123") { trackingId }` → `data.cargo` null, one error at `["cargo"]`, `extensions.code` `SERVICE_UNAVAILABLE` (**spike** E1-c: `@InjectMock` on the source bean's scope; normal-scoped beans only).
  - `TrackCargoTest` (RestAssured): each of the four documents from `documents/` with Ch22's variables; `TrackCargo` ABC123 → `ONBOARD_CARRIER`; `ListCargos` → 6 edges with the per-stack GHI345 errors (Ch13 values).
  - `TypedClientTest`: a `@GraphQLClientApi` interface in test sources (Ch22's `TrackingClient` shape), built with `TypesafeGraphQLClientBuilder.newBuilder().endpoint(url).build(…)` against `@TestHTTPResource("/graphql") URI url`; `cargo("ABC123")` description; `CargoPage` with `ErrorOr` reporting GHI345.
  - `BatchingTest`: injects `SourceCalls`; reset; `FanOut` → 8 calls, keys exactly Ch14's eight; one request id.
  - `CostLimitTest`: `OverBudget` → `maximum query complexity exceeded 7651 > 1000`, no `data`, 0 calls.
  - `IdempotencyTest`: `REG_T1` twice with the same key → same event id, one `handling.appendEvent`.
  - Test names state behaviour (`fanOutMakesEightSourceCalls`, `overBudgetDocumentIsRefusedBeforeAnySourceCall`).
- **Python tests** (`python/tests/`), `conftest.py` sets `TRACKING_SOURCE_LATENCY_MS=0` before importing the app, and provides fixtures `app_client` (`LifespanManager(app)` + `httpx.AsyncClient(transport=ASGITransport(app=manager.app), base_url="http://test")`), `calls` (`app.state.calls` after lifespan start), `documents` (reads `tests/documents/`). `@pytest.mark.anyio` with `anyio_backend` fixture returning `"asyncio"`.
  - `test_schema.py`: `schema.as_str()` contains the two lines; writes it to `$TRACKING_TEST_EXPORT_DIR/schema.graphql` (default `build/`).
  - `test_derivation.py`, `test_cost.py`: pure units, same values as Quarkus.
  - `test_resolvers.py`: `await schema.execute(doc, variable_values=…, context_value=<TrackingContext with a booking source that raises SourceUnavailable>)` → the same error and code as `BookingFailureTest` (**spike** E1-d: building a `TrackingContext` in a test without FastAPI, through `deps`' factories; no change to `app/` beyond what the test needs is allowed only if it is a plain factory function).
  - `test_operations.py`: the four documents through `app_client`, values as Quarkus; one case through `strawberry.asgi.test.GraphQLTestClient(TestClient(app))` (Starlette's `TestClient` runs the lifespan in its context manager).
  - `test_batching.py`, `test_cost_limit.py`, `test_idempotency.py`: as Quarkus, Python counts (6 calls).
- **Test images:** `quarkus/Containerfile` gains `FROM build AS test` (`COPY src/test ./src/test`, `COPY --from=documents . src/test/resources/documents/`, `CMD ["mvn","-B","…retry opts…","verify","-Dtracking.test.export-dir=/out"]` with surefire reports under `/out/surefire-reports`); `python/Containerfile` gains `FROM build AS test` (`uv sync --locked` including the dev group, `COPY tests ./tests`, documents copied to `tests/documents/`, `CMD ["uv","run","--locked","pytest","-q","--junitxml=/out/junit.xml"]`, env `TRACKING_TEST_EXPORT_DIR=/out`). The production stage still builds with `-DskipTests` / `--no-dev`. **Spike** E1-a: whether `mvn -o` works after `dependency:go-offline` (surefire's JUnit Platform provider resolves at test time); if not, run online with the retry options and record it.
- **Load image** `load/`: `Containerfile` (`ubi10/ubi-minimal:10.2-1791891203`; `microdnf install -y tar gzip` if absent; download the k6 tarball and the checksums file in a build stage, `sha256sum -c` on the tarball's line, copy `k6` to `/usr/local/bin`; run as a non-root UID), `tracking.js`, and the documents through `additional_contexts` at `/documents`. `tracking.js` reads documents with `open()`, takes `__ENV.TARGET` (`http://quarkus:8080/graphql` or `http://python:8080/graphql`), `__ENV.RUN` (`fanout`, `cost`, `retry`, `mix`) and `__ENV.STACK`, sets `X-Client-Name: ch23-load`, defines one scenario per run, and writes the end-of-test summary as JSON to stdout through `handleSummary` (no remote jslib imports). Thresholds per run below; k6 exits non-zero when one fails.
- **compose services:** `quarkus`, `python` (servers; `TRACKING_DEBUG_ENDPOINTS=true`); `quarkus-test`, `python-test` (`build.target: test`, `profiles: ["test"]`); `load` (`profiles: ["load"]`). Profiled services run through `compose_run` with `-v "$SCRATCH/<name>:/out:z"` (scratch directories created with mode 0777, because the images run as UID 185 / 1001).

**Load runs** (each per stack, in this order, `source_calls_reset` before each):

| Run | Executor | Work | k6 thresholds | Then verify.sh asserts from the source-call log |
|---|---|---|---|---|
| `fanout` | `shared-iterations`, 8 VUs, 160 iterations | `FanOut`; check: no `errors`, 4 edges, `delivery.transportStatus` present | `http_req_failed: rate==0`, `checks: rate==1`, `iterations: count==160` | exactly 160 distinct request ids; every request id has exactly 8 (Quarkus) / 6 (Python) calls; every request's multiset of `source.op:key` equals Ch14's single-request set (no keys from another request in any batch) |
| `cost` | two `shared-iterations` scenarios started together, 4 VUs each: 80 × `FanOut`, 80 × `OverBudget` | `OverBudget` check: no `data`, one error, message exactly `maximum query complexity exceeded 7651 > 1000`; `FanOut` check as above | as above, `iterations: count==160` | exactly 80 distinct request ids, each with the per-stack count (refused requests made no call) |
| `retry` | `shared-iterations`, 8 VUs, 40 iterations, all `REG_A1` with key `ch23-load-a1` | check: `handlingEvent.id` equals the same id in every response, `userErrors` empty | `http_req_failed: rate==0`, `checks: rate==1` | exactly one `handling.appendEvent`; then a `TrackCargo` for ABC123 says `IN_PORT` |
| `mix` | `constant-arrival-rate` is **not** used; `shared-iterations`, 8 VUs, 120 iterations cycling `TrackCargo`, `TrackCargoBrief`, `ListCargos` | `TrackCargo`/`Brief`: no `errors`; `ListCargos`: 6 edges with the per-stack GHI345 error count and code `SERVICE_UNAVAILABLE` (partial data is the expected answer) | `http_req_failed: rate==0`, `checks: rate==1` | 120 distinct request ids; no request id has a single-key call (`getCargo`, `getLocation`, `getVoyage`, `getItinerary`, `listEvents`) where Ch14 shows the bulk one |

The `retry` run runs once per stack and is the only write; the `mix` run reads the post-write state (ABC123 `IN_PORT`), so it runs after `retry`. Latency percentiles appear in the summary and the README; none is asserted.

**verify.sh assertions**
1. Servers up; Ch14 response checks reduced to the anchors: `FanOut` data and per-stack counts, `OverBudget` message, `first: 51` `BAD_USER_INPUT`.
2. **Quarkus test suite:** `compose_run -v "$SCRATCH/qt:/out:z" quarkus-test` exits 0; `assert_junit "$SCRATCH/qt/surefire-reports" <N>`: the exact test count the executor records (no failures, errors or skips), so a test cannot silently disappear.
3. **Python test suite:** `compose_run -v "$SCRATCH/pt:/out:z" python-test` exits 0; `assert_junit "$SCRATCH/pt/junit.xml" <N>`.
4. **Contract, exported:** `assert_sdl_conforms "$SCRATCH/qt/schema.graphql"` and `"$SCRATCH/pt/schema.graphql"` (the schema each test suite exported). The two exports are not compared with each other: each is checked against the contract, which is the claim the chapter makes.
5. **Contract, live:** `assert_sdl_conforms` on both URLs, `assert_deprecated` for `finalArrivalDate`, scalar checks (unchanged slice).
6. **Client documents:** each `documents/*.graphql` operation equals the same-named operation in `examples/22-client-integration/clients/js/src/operations.graphql` after whitespace normalization (`python3 -I`, read-only); `documents_validate 'documents/*.graphql'` passes; `documents_validate 'documents/fixtures/cargo-weight.graphql'` fails and its output contains `Cannot query field "weight" on type "Cargo"` (**spike**: inspector's exact text; Ch22 recorded codegen's); `graphql-inspector coverage` over the four Ch22 documents reports `Query.cargo` as used and `Query.voyage` as unused (**spike** E1-e: the output format; assert two field lines).
7. **Load runs:** the four runs above on each stack, each `compose_run load run …` exits 0, its JSON summary has `metrics.iterations.values.count` equal to the run's iterations and `metrics.checks.values.rate == 1`; then the source-call assertions in the table (with `assert_calls_per_request`, §3).

**Queries:** at the top of `verify.sh`, the anchors only; everything else is read from `documents/`.

**Figures (2)**
- `23-test-layers`: six layers in a column, each with what it runs against (a function, the in-process app, the HTTP layer, the canonical SDL, client documents, the running stack under load), what it asserts, where it runs (test image, verify.sh, k6 image) and an example from this chapter; the in-process layers marked as the ones that run on every build.
- `23-load-run` (data movement): k6 VUs sending `FanOut` and `OverBudget` to one server; accepted requests fanning into bulk source calls grouped per request id; refused requests stopping at validation with no source call; the counts from the run (160 / 80 request ids, 8 or 6 calls each). Docstring names the run.

**Citations.** Quarkus "Testing your application" guide (`@QuarkusTest`, `@TestHTTPResource`, `@InjectMock`, test profiles, Dev Services mention); Quarkus "SmallRye GraphQL Client" guide (typesafe client, `ErrorOr`); REST Assured documentation; Strawberry "Testing" docs (`schema.execute`, the test client); FastAPI "Testing" and "Async Tests"; pytest documentation (fixtures, `--junitxml`); AnyIO "Testing with AnyIO"; GraphQL Inspector docs ("Validate", "Coverage", "Diff"); k6 docs ("Thresholds", "Checks", "Scenarios", "Shared iterations", "End-of-test summary"); the GraphQL specification "Validation"; a book chapter only by verified title (**spike**).

### Ch24: Debugging GraphQL

**Files:** `_docs/24-debugging-graphql.md`, `examples/24-debugging/` (from Ch19).

**Learning goals.** By the end of the chapter the reader can:
- read a failing GraphQL response for what it already says: the error path, `extensions.code`, which nullable ancestor became null and why (Ch4, Ch9);
- follow the diagnosis path for a masked error: the response's trace id → the trace in Tempo → the ERROR span → the log record in Loki → the exception and the data that caused it (Figure 24.1);
- use the development surfaces each stack provides, and know which of them a production instance serves: Quarkus dev mode with Dev UI and the GraphQL UI, Strawberry's GraphiQL, payload logging in dev (Figure 24.2);
- switch an application debug category on at run time, read the resolver coordinate and key it logs, and switch it off again;
- read a trace for fan-out: count `source.call` spans per request to confirm batching (Ch13), and know that across a gateway the same count per subgraph reads the query plan (Ch20);
- reproduce a production fault in a dev instance with the same document and variables.

**H2 outline**
1. *Start from the response.* What a GraphQL response tells before any tool: `data` beside `errors`, the path, the code. F1 read from its path: `legs[1].unloadLocation` is null in a non-null position, so `itinerary` is null (Ch4's bubbling, applied to a real failure).
2. *When the response says only "Internal server error."* F2: masking is the design (Ch9); the trace id is how a client hands the problem to an operator. `extensions.traceId` on every error, equal to the `traceparent` the client sent, or a new one when it sent none.
3. *From trace id to cause.* Tempo by trace id: the operation span, the `delivery` resolver span with status ERROR and the exception event (Ch19); Loki by `trace_id`: the record with the exception type and message; the data behind it (`XXBAD` in the handling event) (Figure 24.1).
4. *The application's debug category.* `com.patterncatalyst.shipping.tracking.resolve` / `app.resolve` at DEBUG: one line per resolved reference with field coordinate, key and outcome (`Leg.unloadLocation key=XXBAD outcome=missing`). Off by default; switched on at run time on the running instance, read, switched off. Logging keys of reference data only, never tokens or owner lists (Ch19's rule).
5. *Development surfaces.* Quarkus dev mode: live reload, Dev UI at `/q/dev-ui`, the GraphQL UI at `/q/graphql-ui`, `log-payload=query-only` in the dev profile. Strawberry: GraphiQL on the GraphQL path when the IDE is enabled. A production build carries none of them (Ch17) (Figure 24.2).
6. *Reproducing in dev.* The F1 document and variables, pasted into GraphiQL on each dev instance, give the same error path; the dev log shows the payload (Quarkus) and the debug lines.
7. *Reading a trace for fan-out.* The `Q_FAN` trace: one location `source.call` serving many resolver spans (Ch13); what an N+1 looks like in the same view; the count asserted. Across a gateway, the per-subgraph request counts of Ch20 are the query plan.
8. *Debugging with a debugger.* Quarkus dev mode listens for a JDWP debugger on 5005 (local only); Python under `debugpy` or an IDE run configuration; prose only, no published debug ports.
9. *A checklist.* Response → path and code → trace id → trace → log → data or code → test (back to Ch23: the fix gets a test that reproduces F1/F2).
10. On the wire / Decision / next (Ch25: the whole stack locally).

**Example design**
- **Seed:** `JKL012` as §1 on both stacks (booking, routing, handling seed). The source-call log and debug endpoints unchanged.
- **`extensions.traceId`** (§8 decision 7):
  - Quarkus: a second entry in the `ErrorExtensionProvider` ServiceLoader file, `TraceIdExtensionProvider` (key `traceId`, value `Span.current().getSpanContext().getTraceId()` when valid), and `quarkus.smallrye-graphql.error-extension-fields=code,traceId` (**spike** E2-f: the provider sees the request's span context when SmallRye serializes the error, and the masked error keeps `"code":null` beside it).
  - Python: a `SchemaExtension` class (C-1) after `MaskErrors` in the extensions list that, after `yield` in `on_execute`, sets `extensions["traceId"]` on each error of `execution_context.result` from `trace.get_current_span()` (**spike** E2-g: ordering with `MaskErrors` so the masked error gets the id and keeps no other extension).
  - The code comments say what seam each uses; the README says the id is the trace id of the request, not a secret, and the only extension besides `code`.
- **Application debug category:** Quarkus logger `com.patterncatalyst.shipping.tracking.resolve` (`org.jboss.logging.Logger`), Python `logging.getLogger("app.resolve")`; at DEBUG each loader-backed reference resolver (`Leg.loadLocation`, `Leg.unloadLocation`, `Leg.voyage`, `HandlingEvent.location`) writes `resolve <coordinate> key=<key> outcome=<found|missing>` once per key per request (written after the batch returns, from the resolver that maps keys to results). `DeliveryDerivation` logs nothing new: F2's record is the exception log Ch19 already has. Default level INFO for both categories.
- **Run-time level switch** (§8 decision 6, recommended (a)):
  - Quarkus: `quarkus-logging-manager` 3.4.2: `POST /q/logging-manager` with form fields `loggerName`, `loggerLevel`; `GET /q/logging-manager?loggerName=…` reads it (**spike** E2-c: builds and runs on 3.40.1; endpoint path and form names; whether it is enabled in a production build and how it is switched off; if it is not compatible, stop and report, then take decision 6's fallback).
  - Python: a lab router `app/debug.py` adds `GET`/`POST /debug/loggers` with the same field names, over `logging.getLogger(name).setLevel()` (the standard library's run-time API), mounted only with `TRACKING_DEBUG_ENDPOINTS=true`.
  - The Quarkus endpoint is served only when `TRACKING_DEBUG_ENDPOINTS=true` too, by whatever switch spike E2-c finds (README states it).
- **Dev and production instances:**
  - `quarkus` (production fast-jar, Ch19's Containerfile stages) and `python` (`TRACKING_PROFILE=prod` → `graphql_ide=None`).
  - `quarkus-dev`: `quarkus/Containerfile` gains `FROM build AS dev` (`COPY src ./src` already in build; `RUN mvn -B … quarkus:go-offline`; `CMD ["mvn","-B","quarkus:dev","-Dquarkus.http.host=0.0.0.0","-Ddebug=false","-Dquarkus.console.enabled=false","-Dquarkus.test.continuous-testing=disabled","-Dquarkus.analytics.disabled=true"]`), environment as `quarkus` plus the OTLP endpoint and service name `ch24-debugging-quarkus-dev`; `application.properties` adds `%dev.quarkus.smallrye-graphql.log-payload=query-only` and the Dev UI host setting from spike E2-a. Healthcheck `/q/health/ready` with `start_period: 120s`. **Spike** E2-b: dev mode in a non-TTY container, no Dev Services started (none configured), OTel export to `lgtm`.
  - `python-dev`: `image: gql-ch24-debugging-python:local` (C-7), `TRACKING_PROFILE=dev` → `graphql_ide="graphiql"`, service name `ch24-debugging-python-dev`.
  - `TRACKING_PROFILE` is a new `Settings` field (`Literal["dev","prod"]`, default `prod`), following the `TRACKING_*` pattern; masking is identical in both profiles (Ch9).
- **LGTM** as Ch19 (default service, healthcheck with `curl`), ports per §1.

**Queries** (top of `verify.sh`): `F1` = `query LegsOfJkl($id: TrackingId!) { cargo(trackingId: $id) { trackingId itinerary { legs { unloadLocation { name } } } } }`; `F2` = `query DeliveryOfJkl($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }`; `Q_FAN` = Ch19's `FanOut`; `HEALTHY` = Ch19's `TrackCargo` for ABC123.

**verify.sh assertions (both stacks unless marked).** Each traced case picks a trace id with `new_trace_id` and sets `LGTM_TRACEPARENT`.
1. **Unchanged behaviour:** `HEALTHY` → `ONBOARD_CARRIER`, no errors, no `extensions.traceId` anywhere (successful responses carry no extension); `Q_FAN` data and per-stack calls as Ch19.
2. **F1 read from the response** (production instances): `data.cargo.trackingId` `JKL012`, `data.cargo.itinerary` null; exactly one error, path `["cargo","itinerary","legs",1,"unloadLocation"]`; message per stack (E2-e); the source-call log for the request holds one `location.getLocations` whose key includes `XXBAD`.
3. **F2 through the diagnosis path** (production instances): response `data.cargo` null, one error at `["cargo","delivery"]` with message `Internal server error.`, `extensions.code` null (Quarkus) / absent (Python), and `extensions.traceId` equal to the trace id sent; `tempo_trace` by that id has the operation span `query DeliveryOfJkl` and a span with status ERROR descending from it (per-stack name from Ch19's tables); `loki_wait '{service_name="ch24-debugging-<stack>"} | trace_id="<id>"'` returns a record whose `exception_type` matches the stack's exception (E2-e) and whose text contains `XXBAD`; `assert_body_not_contains` the response for `XXBAD` and the exception type (the detail stayed server-side).
4. **Trace id without a caller trace:** F2 with `LGTM_TRACEPARENT` unset → `extensions.traceId` is 32 lowercase hex; `tempo_trace` by that id finds the trace.
5. **Debug category at run time** (production instances): with the category at INFO, F1 → no `resolve Leg.unloadLocation` line in `compose_logs <service>` after a marker request; switch to DEBUG (`http_any POST …/q/logging-manager -d loggerName=… -d loggerLevel=DEBUG` / `…/debug/loggers`); read the level back as `DEBUG`; F1 again → exactly one line `resolve Leg.unloadLocation key=XXBAD outcome=missing` for that request (located after a unique marker: the request's trace id, logged by the same line through the log record's MDC/trace context, **spike** E2-h for how to delimit it in `compose_logs`; fallback: Loki by trace id); switch back to INFO and read `INFO`.
6. **Dev versus production surfaces:**
   - Quarkus dev (8342): `GET /q/graphql-ui/` → 200, `text/html`, body contains `graphiql` (case-insensitive); `GET /q/dev-ui/` → 200 (E2-a). Quarkus production (8340): both → 404.
   - Python dev (8343): `GET /graphql` with `Accept: text/html` → 200 with `graphiql`; Python production (8341): 404 (Ch17's observed answer).
   - Quarkus dev: after F1 on 8342, `compose_logs quarkus-dev` contains the operation text `LegsOfJkl` (payload logging); production `compose_logs quarkus` does not.
7. **Reproduce in dev:** F1 on each dev instance gives the same error path and the same nulls as production.
8. **Fan-out from a trace:** `Q_FAN` on each production instance; in its trace the number of `source.call` spans with `source.operation=getLocations` equals the source-call log's `location.getLocations` count for the same request (Ch19 values), and location resolver spans number ≥ 2.
9. Deprecation check, scalar checks, `assert_sdl_conforms` on the production instances (slice unchanged; the seed adds data only).

**Figures (2)**
- `24-diagnosis-path` (data movement): a masked F2 response with `extensions.traceId` → Tempo trace (operation span, ERROR span on `delivery`) → Loki record (`exception_type`, `XXBAD`) → the handling event's location → the fix, then a regression test (Ch23). Values from the run; docstring names it.
- `24-dev-vs-prod-surfaces`: two columns, dev instance and production instance, rows: GraphQL IDE (`/q/graphql-ui`, GraphiQL on `/graphql`), Dev UI, payload logging, debug category switch (lab), masked errors (both), `extensions.traceId` (both), traces and logs (both). Ports from §1.

**Citations.** Quarkus "Dev UI" and "Dev mode" (Getting started / "Maven tooling": `quarkus:dev`, debug port), Quarkus "Configuring logging" (categories, levels, `min-level`), Quarkus SmallRye GraphQL guide (GraphQL UI, `log-payload`), the Quarkiverse Logging Manager docs (if decision 6 (a)), Strawberry "GraphQL IDE" / FastAPI integration docs (`graphql_ide`), Python `logging` docs ("Logger Objects", `setLevel`), Grafana Tempo "Query by trace id" and Loki "LogQL" structured metadata, OpenTelemetry "Trace Context", W3C Trace Context; Ch9's masking and Ch19's signals by chapter; a book chapter only by verified title (**spike**).

---

## 3. Harness additions (`examples/_lib/lib.sh`, E0)

Every change is backward compatible, `bash -n` and shellcheck clean, stdlib `python3 -I` only, and documented in `examples/_lib/README.md`'s table. Existing callers behave identically.

| Function | Contract |
|---|---|
| `assert_calls_per_request <calls-json> <n> [ctx]` | Every distinct non-empty request id in a source-call log has exactly `n` calls; FAIL prints the first offending id and its count. An empty log fails. |
| `assert_calls_same_per_request <calls-json> <k1,k2,...> [ctx]` | For every request id, the multiset of `source.op:key` equals the list (order ignored). The per-request form of `assert_source_calls_exactly`, for load runs. |
| `assert_junit <report-file-or-dir> <expected-tests> [ctx]` | Parses JUnit XML (one file, or every `TEST-*.xml` in a directory, with `xml.etree.ElementTree`); total `tests` equals the expectation and `failures`, `errors`, `skipped` are all 0; FAIL lists failing test names. |
| `documents_validate <glob> [extra-args...]` | `ensure_contracts_tools`, then `graphql-inspector validate '<glob>' 'contracts/schema/**/*.graphql'`; prints the combined output and returns the tool's exit code (callers assert success or failure and the needle, as `run_gate` does). |

**E0 self-test:** `bash -n`; shellcheck; Ch0, Ch13 and Ch19 `verify.sh` green; `assert_calls_per_request` and `assert_calls_same_per_request` against a saved two-request log (pass) and a log with one extra call (fail); `assert_junit` against a saved surefire directory and a pytest `junit.xml` (pass), one with a failure and one with a skip (fail); `documents_validate` on Ch22's `operations.graphql` (rc 0) and fixture (rc 1). Saved inputs live in the scratch dir, not the repository.

---

## 4. Acceptance criteria

**Per chapter (Ch23, Ch24)**
- `_docs/NN-*.md` with valid front matter (`part:` "Testing & Debugging", `order` = N); `bash scripts/wordcount.sh` reports 2,800–3,400.
- Two figures each at `assets/diagrams/NN-slug.{svg,excalidraw}` with a spec `diagrams/NN-slug.py` that regenerates byte-identically, embedded with full-sentence alt text and a `Figure N.M — …` caption, rendered to PNG and viewed by the executor and by EVn.
- `## On the wire` matches `verify.sh`, then the Decision callout naming Ch2's axes, then `## Where this goes next`; at least one codetabs pair.
- `examples/NN-slug/` has README (sections per §2), `compose.yaml` (fixed `name:`, pinned images only), executable `verify.sh`, `.gitignore`, `architecture.svg` + `.excalidraw`, `quarkus/` and `python/` with re-generated `uv.lock`; Ch23 also `documents/` and `load/`.
- `verify.sh` prints `PASS`; every §2 assertion present for both stacks; only the harness, stdlib and the example's own containers.
- No planning language: `grep -rniE 'wave [a-z0-9]|\bS[0-9]{1,2}\b|\bE[0-9]\b|\br0[0-9]\b|iteration|capstone|coverage matrix|phase [0-9]|TODO|TBD|spike' _docs/2[34]-* examples/2[34]-*/README.md` returns nothing (k6's "iterations" in Ch23 code and prose is a k6 term: the grep runs with `iteration[^s]` for Ch23 and the validator reads each hit).
- Content rule: EVn reads every reader-facing line, including test names and messages, for rule-13/14 hits; 0 allowed. `lgtm-professional-voice`: 0 ban-tier findings. `lgtm-idiomatic-review`: 0 unresolved substantive findings; the hand-written framework-adjacent pieces are Ch24's two `traceId` hooks, the Python logger router and the debug lines, each with a comment naming the seam it uses.

**Chapter-specific**
- Ch23: both test suites pass inside their UBI test images with the recorded exact test counts; the schemas they export conform to `contracts/schema/`; Ch22's documents are byte-equivalent copies, validate against the contract, the `weight` fixture fails validation, and coverage names `Query.cargo` used and `Query.voyage` unused; on both stacks the four load runs pass their thresholds, every request has the per-stack call count and Ch14's key set, every over-budget request is refused with 0 calls, and 40 concurrent retries write one event.
- Ch24: F1's path and nulls read from the response; F2's `extensions.traceId` equals the sent trace id, the trace holds an ERROR span, Loki returns the exception record with `XXBAD`, and the response does not contain it; a server-chosen trace id is findable; the debug category goes INFO → DEBUG → INFO at run time with exactly one debug line for the F1 request; the IDE and Dev UI answer 200 on the dev instances and 404 on the production instances; payload logging only on the Quarkus dev instance; the fan-out count read from the trace equals the source-call log.

**For the wave**
- `python3 -I scripts/validate.py` exits 0 (checked via `$?`); `GATE=1 bash scripts/wordcount.sh` passes; Jekyll build in the `ruby:3.3` container is clean.
- `npm --prefix contracts run lint` and `run breaking` pass; **the `contracts/` and `.github/` diffs are empty**.
- All Ch0, Ch3–Ch24 `verify.sh` run concurrently on one host and pass (port rule).
- On PR #1: `verify: 23-testing` and `verify: 24-debugging` green, `ci-ok` green.
- Site figure total = 79.
- **Forward references delivered** (EVn checks each against the shipped text): Ch5:182 (the real test suites, the two sketches' shapes, the export diffed); Ch22:319 (each layer; the load harness runs Ch22's documents); the execution plan's call-count risk (Ch23 per request under load, Ch24 from a trace); the Part 11 blurb.
- **Deliberate fixes (EW, never as side effects).** If an EV finds a forward statement the shipped chapter does not meet, the validator drafts a one-clause fix and the orchestrator applies it in its own `fix(§N)` commit, re-verified.

---

## 5. Risks and detection

| Risk | Detection / mitigation |
|---|---|
| Maven offline test run cannot resolve surefire's JUnit Platform provider | Spike E1-a; run online with retry options and record. |
| `@InjectMock` does not apply to the source bean's scope | Spike E1-c; make the source `@ApplicationScoped` (normal scope) in Ch23's copy, which is the documented requirement; record. |
| Python tests import settings before the environment is set | `conftest.py` sets env first; `test_batching` asserts 6 calls at latency 0. |
| Test order makes mutation tests depend on each other | Distinct idempotency keys and cargos per test; assertions relative to the test's own reset of the call log. |
| Load counts flaky on a shared runner | Only exact-count invariants (`shared-iterations`), never latency; CI retries 3×; `compose_up` resets state per attempt. |
| Batched keys differ under concurrency (a tick spans requests) | Loaders are per request (Pitfall 24); `assert_calls_same_per_request` proves it; a failure is a real finding, reported. |
| Lower latency (50 ms) changes SmallRye's per-field batch counts | Spike E1-b; keep 250 ms if counts differ, and size runs down to stay within ~1 min per stack. |
| k6 2.x script API differs from 1.x examples | Executor reads the v2.3.0 docs; `k6 inspect` on the script in the image build. |
| k6 checksum line format changes | `grep 'linux-amd64.tar.gz' checksums | sha256sum -c` in the build; the sha256 is also written in the Containerfile comment. |
| Dev mode in a container is slow or interactive | `-Dquarkus.console.enabled=false`, `start_period: 120s`, `quarkus:go-offline` in the image; spike E2-b. |
| Dev UI refuses requests through a published port | Spike E2-a; set the allowed-hosts property in `%dev` config; if no property admits it, assert the GraphQL UI only and record. |
| Logging manager incompatible with 3.40.1 | Spike E2-c; stop and report; fallback is §8 decision 6 (c), with orchestrator sign-off. |
| `traceId` extension missing on masked errors, or adds other keys | Spike E2-f/g; case 3 asserts the exact extension set. |
| Debug line for F1 cannot be delimited in `compose_logs` | Spike E2-h; fallback Loki by trace id (the line is exported over OTLP like the exception record). |
| The `JKL012` seed changes Ch19-derived values | Spike in §1; Ch24 asserts its own seven-edge `cargos(first: 10)` if used. |
| A reader-facing line presents a framework as at fault | Content rule; EVn line-by-line read; S12b sweep re-runs rule 13. |
| Untested prose (debugger attach, Dev Services, Ch20 query plans, `debugpy`) | Prose only, no code; EV flags any snippet the example does not run. |

---

## 6. Coverage-matrix and plan updates (orchestrator only)

1. **At each chapter checkpoint** (same commit): T24 Ch23, T25 Ch24 to `draft` in the Topics table and the Full chapter inventory. Run `python3 -I scripts/validate.py; echo $?` and `GATE=1 bash scripts/wordcount.sh`. Push.
2. **Verified:** after EVn passes **and** CI `verify: NN-*` is green.
3. Diagram budget table unchanged (23:2, 24:2). Record the Wave E count (4; site total 79) in the RESUME POINTER.
4. `_example_pages/index.md`, rows 23–24:
   - **23**: Test suites on both stacks (schema, resolver unit, operation integration, client documents) run in UBI test images, the exported schema diffed against the contract, Ch22's documents validated, and a k6 load run that asserts batching, cost refusals and idempotency under concurrency.
   - **24**: A seeded data fault diagnosed from the response, then through the trace id to the trace and the log; dev instances with GraphiQL and Dev UI beside production instances without them; an application debug category switched at run time.
5. `_plans/domain-glossary.md`: add **Test layer**, **Load run** (k6, shared iterations), **Trace id extension** (`extensions.traceId`), **Dev instance**.
6. RESUME POINTER: S10 done with date and spike findings (offline Maven tests, `@InjectMock` scope, latency used, inspector texts, k6 summary fields, dev-mode container flags, Dev UI host setting, logging-manager result, `traceId` seam per stack, F1/F2 messages, debug-line delimiting); versions to bump later (fastapi 0.143.3 and any newer UBI tags); `iteration-plan.md` S10 → done.
7. Commits on `r01`, one checkpoint per step: `chore(r01.x): Wave E harness additions (per-request calls, JUnit reports, document validation)` for E0; `docs(§23): …`, `docs(§24): …`; `fix(§N): …` for repair rounds; `docs(r01): Wave E verified`. Push after each and watch CI.
8. Append **§9 "Wave E findings"** at EW, engineering notes only, in the neutral form of Wave D's §9 (no defect narratives; anything that reads as a defect goes to the user outside the repository).

---

## 7. Binding pitfalls carried forward (every Wave E executor)

**From Waves A–D (still binding):** Wave A §7 items 1–10 and §9–§10 handoffs; Wave B §9 (masking allowlist and `DeclaredErrorCodeProvider`; per-field SmallRye batching and blast radius; one `__Type.fields` per request; whole-second times; `ensure_contracts_tools`; `compose_up` runs `down -v`; `validate.py` exit code checked directly); Wave C §7 items 1–27, B-1…B-4, C-1…C-10 and §9 (reader-facing text is a tutorial; test code shows behaviour, not recipes; `status_of` without a pipe; no `producer | head` under `pipefail`); Wave D §7 D-1…D-9 and §9 (telemetry by the caller's trace id; per-stack span names; no values in attributes or labels; no fixed sleeps before a "nothing changed" check; `compose_run` with `COMPOSE_PROGRESS=quiet`; docs cited by page title).

**New in Wave E (binding):**
- **E-1.** Tests and builds run only inside the pinned UBI images; nothing in verify.sh calls the host's `mvn`, `java`, `uv` or `pytest`.
- **E-2.** A test suite's pass is asserted with its exact test count from the JUnit XML, never only by exit code.
- **E-3.** Test names and assertion messages are reader-facing: they name a behaviour (`overBudgetDocumentIsRefusedBeforeAnySourceCall`), never a defect or a workaround.
- **E-4.** Load assertions are exact counts and invariants; latency is printed, never asserted.
- **E-5.** Every load run starts from `source_calls_reset` and reads the log once at the end; the write run (`retry`) precedes the reads that depend on it.
- **E-6.** The client documents are Ch22's, compared by text; Ch23 never edits Ch22's files.
- **E-7.** Volumes mounted into test and load containers are scratch directories with mode 0777 and `:z`; nothing is written into the example tree at run time.
- **E-8.** Ch24's seeded fault lives in the seed data only; no fault switch in application code, and the derivation is not altered to tolerate it.
- **E-9.** Dev surfaces (IDE, Dev UI, payload logging, level switch) are asserted present on the dev instance **and** absent on the production instance; the level switch, like every debug endpoint, needs `TRACKING_DEBUG_ENDPOINTS=true`.
- **E-10.** The debug category logs field coordinates and reference keys only; never a tracking id list, a token, a variable value or an owner.

---

## 8. Open decisions needing user input (each with a recommendation)

1. **Load tool (Ch23).**
   - (a) **Grafana k6 v2.3.0**, the static binary from the release tarball, sha256-verified, on `ubi10/ubi-minimal:10.2-1791891203`. JavaScript scenarios, `shared-iterations` for exact counts, first-class `checks` and `thresholds` with a non-zero exit, a JSON end-of-test summary. AGPL-3.0: OSI-approved open source, no fees, no key; used unmodified as a CLI.
   - (b) The same k6 from the upstream `grafana/k6:2.3.0` image (not UBI).
   - (c) **Locust 2.46.7** (MIT) in `ubi10/python-314-minimal` via uv: Python scenarios, matches the Python stack; counts are run-time based, so exact-count assertions need a custom stop condition and an exit-code hook.
   - (d) vegeta v12.13.0 (MIT): constant-rate HTTP attack, no per-response body checks; it cannot assert GraphQL semantics.
   **Recommend (a).**
2. **Test layers and where tests run (Ch23).**
   - (a) **Six layers** (schema, resolver unit, operation integration, contract, client document, load). The in-process layers run in a `test` target of each Containerfile via `compose_run`, with reports and exported SDL in a mounted scratch dir. Contract, document and load run from `verify.sh`.
   - (b) Tests run inside the production image build (`mvn package` without `-DskipTests`): a failure fails the build, but reports are harder to read and every image build pays for the tests.
   - (c) Host toolchain: excluded by the rules.
   **Recommend (a).**
3. **Ch23's base.** (a) **copy Ch14** (batching and cost limits, both asserted under load); (b) copy Ch13 and add the cost limits again; (c) one shared example that other chapters' tests reach into. **Recommend (a).**
4. **Ch24's base.** (a) **copy Ch19** (LGTM as a default service; traces, metrics and logs by trace id already wired); (b) Ch14 plus `compose.observability.yaml`. **Recommend (a).**
5. **Debug surface (Ch24).**
   - (a) **A dev instance beside the production instance on each stack.** Quarkus: a `dev` Containerfile target running `mvn quarkus:dev`. Python: the same image with `TRACKING_PROFILE=dev`. Assert the IDE and Dev UI present on dev and absent on production.
   - (b) A production jar built with `ui.always-include=true`: puts the IDE in production, the opposite of the lesson.
   - (c) Production instances only, with dev surfaces in prose: nothing machine-checkable about dev.
   **Recommend (a).**
6. **Changing a log level at run time (Ch24).**
   - (a) **Quarkus: `quarkus-logging-manager` 3.4.2** (Quarkiverse, Apache-2.0; spike E2-c on 3.40.1). Python: a lab router `/debug/loggers` with the same field names over `logging.getLogger().setLevel()`. Both need `TRACKING_DEBUG_ENDPOINTS=true`.
   - (b) A lab route on both stacks over each platform's logging API (`java.util.logging` on JBoss LogManager; Python `logging`). Symmetric, no new dependency, but hand-written on Quarkus, where an extension exists.
   - (c) The level set at start through configuration (`QUARKUS_LOG_CATEGORY__…__LEVEL=DEBUG`; `TRACKING_LOG_LEVELS`) on a second instance: no code at all, but not a run-time switch.
   **Recommend (a), with (c) as the fallback** if E2-c fails. The orchestrator signs off on the fallback.
7. **Getting the trace id to the client (Ch24).** (a) **`extensions.traceId` on every error** (both stacks; ties a masked error to its trace for support); (b) only the `traceparent` the client chose (no server change, but a client that sent none has nothing to report). **Recommend (a)**; (b) is the fallback if E2-f/g fail.
8. **The seeded fault (Ch24).** (a) **a seventh seed cargo `JKL012` with the unknown location `XXBAD`**, producing F1 (non-null violation) and F2 (masked exception) through ordinary queries; (b) an environment switch that injects failures into a source. **Recommend (a)**: it is data, as real faults usually are, and it needs no fault code.
9. **Source latency for Ch23.** (a) **`TRACKING_SOURCE_LATENCY_MS=50`** in Ch23's compose, so the load runs fit in about a minute per stack (spike E1-b: counts unchanged); (b) 250 ms as every other example, with smaller runs. **Recommend (a).**
10. **Harness additions.** (a) **E0** adds four helpers (§3) for reuse in Ch25–27; (b) local functions in each `verify.sh`. **Recommend (a).**
11. **CI runtime budget.** (a) **no workflow change.** The matrix discovers both examples; `timeout-minutes: 60` covers three cold attempts (~10–11 min each); there are no new jobs and no new host tools. (b) A separate `load` job or a nightly schedule for the load runs. **Recommend (a).** The load runs are small, deterministic, and part of the chapter's proof.
12. **Python async test runner.** (a) **the AnyIO pytest plugin** (`@pytest.mark.anyio`; the FastAPI documentation's idiom; AnyIO already installed); (b) `pytest-asyncio` 1.4.0. **Recommend (a).**
13. **Client documents in Ch23.** (a) **copy Ch22's documents into `examples/23-testing/documents/`** and assert in verify.sh that they still match Ch22's, read-only (self-contained, and drift between the chapters fails); (b) mount Ch22's directory into Ch23's images (couples two examples' build contexts). **Recommend (a).**
14. **Canonical SDL additions.** **Recommend none.** `extensions.traceId` is a response extension; the `contracts/` diff stays empty.

### Critical files for implementation
- `examples/_lib/lib.sh` and `examples/_lib/README.md` (E0)
- `examples/14-query-cost/` (base of Ch23: `QueryCost.java`, `TrackingCostCalculator.java`, `SourceCalls.java`, `python/app/limits.py`, `sources.py`, `deps.py`, `main.py`, `verify.sh`, Containerfiles)
- `examples/19-observability/` (base of Ch24: `Telemetry.java`, `DeclaredErrorCodeProvider.java`, `DeliveryDerivation.java`, `TrackingData.java`, the ServiceLoader file, `python/app/telemetry.py`, `derivation.py`, `data.py`, `debug.py`, `settings.py`, `compose.yaml`, `verify.sh`)
- `examples/22-client-integration/clients/js/src/operations.graphql` and `fixtures/cargo-weight.graphql` (read-only sources of Ch23's documents)
- `contracts/schema/shipping/*.graphql` and `contracts/node_modules/.bin/graphql-inspector` (read-only)
- `_plans/coverage-matrix.md` (orchestrator)

---

## 9. Wave E findings

Binding on later waves unless noted. Engineering notes only.

- **Decision 7 as built:** `extensions.traceId` is on every *execution* error (errors with a path), not on request errors, which never execute and have no trace; Ch24 asserts both. On Quarkus a graphql-java instrumentation adds it to errors the engine raises itself, beside the `ErrorExtensionProvider`.
- **Tests run offline:** the Quarkus test stage runs one unit test at build time so Surefire's provider is in the image, then `mvn -o verify`; `quarkus:go-offline` sits in its own layer before the tests.
- **Construct framework value types in unit tests** (graphql-java `FieldComplexityEnvironment`) rather than mocking them.
- **Starlette's `TestClient` uses `httpx2`** (pydantic/httpx2, BSD-3) — add it to the Python dev group.
- **Only a concurrent load run tests a lock:** sequential suite replays pass with the store's check removed; the k6 `retry` run fails. Keep a concurrent case for every atomicity claim.
- **Exact test counts from JUnit XML** guard against skipped or removed tests (`assert_junit` fails on skips).
- **Dev mode in a container:** `%dev.quarkus.devservices.enabled=false` when the compose stack supplies the backing services; `-Dquarkus.console.enabled=false -Ddebug=false`; give the dev instance a 240 s readiness wait.
- **Lab debug endpoints** (`/q/logging-manager`, `/debug/loggers`, `/debug/source-calls`) are behind `TRACKING_DEBUG_ENDPOINTS`; Ch24 asserts 404 with the switch off.
- **Promotion candidates for `lib.sh`** (Ch25–27): `log_count`, `run_load`, `request_shapes`, the coverage JSON reader.
- **S12b inputs:** Ch14's cost/alias comments and prose and every `Node.java` Javadoc were restated as design (fabe070); the rule-13 sweep still runs over every file at S12b.

(Appended at EW.)
