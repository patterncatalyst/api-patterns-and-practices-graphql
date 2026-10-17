---
layout: plan
render_with_liquid: false
title: "r01 Wave D Plan — Ch19–Ch22 (Observability & the Gateway, Real-time & Client Integration)"
---

# Wave D (S9): Ch19–Ch22, Observability & the Gateway and Real-time & Client Integration

**Status: DONE 2026-10-17 (D0–D4, DV1–DV4, DW); Ch19–22 verified, CI green at e5710fb. DX done 2026-10-17 (Ch0, Ch3–18 and Ch21; the Quarkus switch is the `QUARKUS_OTEL_SDK_DISABLED` env mapping of the runtime property `quarkus.otel.sdk.disabled`, so no properties change). APPROVED by user 2026-10-16 — §8 decisions 1–12 as recommended (Hive Gateway + `@theguild/federation-composition`; Apollo Client 4.3.4).**

This plan is written for Sonnet executors. Where it gives a value (a port, an id, a span name, a config key, a metric name, an error code, a path or an image tag), use exactly that value. Where it says **spike**, check the behaviour on the pinned versions before writing any prose that depends on it, and record what you observe in the example README under "Code-first notes". If a spike contradicts an expected value in this plan, assert what you observed, rewrite the prose to match, and report it to the orchestrator. Never weaken an assertion without saying so.

**Precondition.** S8 (Wave C) is done: Ch0 and Ch3–Ch18 are `verified`, CI is green at `ef6f8ce`. Every Wave D example starts from `examples/13-dataloaders/` (the newest example that carries Ch9's error machinery and Ch13's batching without the Wave C concerns), exactly as Ch14, Ch17 and Ch18 did.

**The content rule (binding on every executor and validator).** The site is a GraphQL tutorial, not an issue tracker. Reader-facing text (chapters, READMEs, code comments, verify messages, figure labels and alt text) states every technique positively, as the design. It never describes framework bugs, limitations, upstream issues, workarounds, or security weaknesses of any framework, and it carries no issue numbers. Stack differences are described neutrally ("Strawberry also serves the subscription over SSE; the Quarkus stack serves it over WebSocket"). Where a framework needs a small extension point to meet the contract, describe it as a normal design choice. This is `lgtm-professional-voice` rules 13–14. If an executor observes behaviour that looks like a framework defect, it reports it to the orchestrator in one neutral line and writes nothing about it in the repository, including `_plans/`.

---

## 0. Facts checked (2026-10-16)

These are inputs to the plan, read from the local jars and wheels and from the registries on 2026-10-16. Anything still marked *spike* has not been run.

**Quarkus 3.40.1** (newest stable stream on registry.quarkus.io; 4.0.0.Beta1 is a prerelease and is not used).
- `quarkus-smallrye-graphql` config (from `META-INF/quarkus-config-doc`):
  - `tracing.enabled` (build time; "enabled if the tracing extension is added"). SmallRye's `TracingService` opens **one span per operation** (`beforeExecute`/`afterExecute`) with the attributes `graphql.executionId`, `graphql.operationType`, `graphql.operationName`. It opens no span per field.
  - `metrics.enabled` (build time, default false; needs a metrics extension). SmallRye's Micrometer service records a timer `mp_graphql` tagged `name`, `type`, `source`, and a gauge `mp_graphql_subscription`.
  - `federation.enabled` (build time; on automatically when federation annotations are present) and `federation.batch-resolving-enabled` (build time, default false).
  - `websocket-subprotocols` (build time; default both `graphql-ws` and `graphql-transport-ws`) and `authorization-client-init-payload-name`.
- SmallRye federation annotations (`io.smallrye.graphql.api.federation`): `@Key(fields = @FieldSet("…"), resolvable)`, `@Shareable`, `@External`, `@Requires`, `@Provides`, `@Override`, `@Inaccessible`, `@InterfaceObject`, `@Resolver`, `@link.Link`. `Link.FEDERATION_SPEC_LATEST_VER = "2.7"`. Federation support is `com.apollographql.federation:federation-graphql-java-support:6.2.1` (MIT, apollographql/federation-jvm).
- `quarkus-opentelemetry` config: `quarkus.otel.sdk.disabled` (**runtime**, default false); `traces.enabled` (build, default true); `metrics.enabled` and `logs.enabled` (build, default **false**); `metric.export.interval` (runtime, default 60S); `bsp.schedule.delay` (runtime, default 5S); `exporter.otlp.endpoint` (runtime, default `http://localhost:4317/`).
- The Quarkus platform BOM 3.40.1 manages `io.opentelemetry.instrumentation:opentelemetry-graphql-java-20.0:2.28.1-alpha` (the OpenTelemetry project's own graphql-java instrumentation; `-alpha` is that project's API-stability label on instrumentation modules, not a prerelease), `opentelemetry-api`/`-sdk` 1.62.0, graphql-java 25.0, `quarkus-micrometer-opentelemetry`, `quarkus-smallrye-graphql-client` 3.40.1 and `smallrye-graphql-client*` 2.18.5.
- Quarkus REST serves server-sent events from a `Multi<T>` with `@Produces(MediaType.SERVER_SENT_EVENTS)` (`quarkus-rest-jackson` is already in every example). The Quarkus SmallRye GraphQL guide's subscription example publishes through a Mutiny `BroadcastProcessor`.

**Strawberry 0.335.0** (newest on PyPI, 2026-10-14), read from the uv archive `~/.cache/uv/archive-v0/MAJ_QYt-It_BsxNl/strawberry`.
- `strawberry.extensions.tracing.OpenTelemetryExtension(arg_filter=…, tracer_provider=…)`: an operation span `GraphQL Query: <operationName>` (`SpanKind.SERVER`, attributes `component`, `query` = the document as sent), child spans `GraphQL Parsing` and `GraphQL Validation`, and one span `GraphQL Resolving: <field>` per resolver with `graphql.parentType`, `graphql.path` and `graphql.param.<arg>` (passed through `arg_filter`). It skips default resolvers and introspection fields. It keeps per-request state, so it is passed as a class (Pitfall C-1).
- Subscriptions: `GraphQLRouter(subscription_protocols=…)` defaults to `(GRAPHQL_TRANSPORT_WS_PROTOCOL, GRAPHQL_WS_PROTOCOL)`. Adding `GRAPHQL_SSE_PROTOCOL` (`"graphql-sse"`) enables GraphQL over SSE on the same path (`SSETransport`: `Content-Type: text/event-stream`, `Cache-Control: no-cache, no-transform`, `event: next` / `event: complete`, a `: ping` comment every 15 s). Multipart subscriptions (`multipart/mixed;subscriptionSpec=1.0`) are also built in.
- `strawberry.federation.Schema(…, federation_version="2.11")` is the default; versions 2.0–2.11 are accepted.
- FastAPI 0.143.2 (the pin) ships `fastapi.sse.EventSourceResponse` and `ServerSentEvent(id, event, data, retry)` for `yield`-based SSE path operations.

**Registries (latest stable, checked 2026-10-16)**

| Component | Version | Licence | Released | Used in |
|---|---|---|---|---|
| Quarkus platform | 3.40.1 | Apache-2.0 | (current) | all |
| SmallRye GraphQL (+ client) | 2.18.5 (BOM) | Apache-2.0 | — | all, Ch22 client |
| opentelemetry-graphql-java-20.0 | 2.28.1-alpha (BOM) | Apache-2.0 | — | Ch19 |
| federation-graphql-java-support | 6.2.1 (via SmallRye; 7.0.0 is upstream latest, not used directly) | MIT | — | Ch20 |
| strawberry-graphql | 0.335.0 | MIT | 2026-10-14 | all |
| fastapi | 0.143.2 pinned (0.143.3 released 2026-10-16; not bumped in-wave) | MIT | — | all |
| uvicorn | 0.54.0 | BSD-3 | 2026-09-25 | all |
| opentelemetry-distro / -instrumentation-fastapi | 0.66b1 | Apache-2.0 | 2026-10-06 | Ch19 |
| opentelemetry-sdk / -exporter-otlp-proto-grpc | 1.45.1 | Apache-2.0 | 2026-10-06 | Ch19 |
| gql | 4.4.0 | MIT | 2026-09-27 | Ch21 client, Ch22 |
| websockets | 17.2 | BSD-3 | 2026-10-03 | Ch21 client (via `gql[websockets]`) |
| httpx | 0.28.1 | BSD-3 | 2024-12-06 | Ch22 (via `gql[httpx]`) |
| graphql-core | 3.3.0 (transitive; let uv resolve) | MIT | 2026-09-27 | — |
| @graphql-hive/gateway | 2.15.2 | MIT | 2026-10-08 | Ch20 |
| @theguild/federation-composition | 0.27.0 | MIT | 2026-09-23 | Ch20 |
| graphql (npm) | 16.14.2 (same as `contracts/`; 17.0.2 exists, Hive Gateway's peer range is ^16) | MIT | — | Ch20, Ch22 |
| @apollo/client | 4.3.4 | MIT | 2026-10-16 | Ch22 |
| rxjs | 7.8.2 | Apache-2.0 | 2025-02-22 | Ch22 (Apollo peer) |
| @graphql-codegen/cli | 7.4.6 | MIT | 2026-10-09 | Ch22 |
| @graphql-codegen/client-preset | 6.2.3 | MIT | 2026-10-09 | Ch22 |
| typescript | 7.0.2 (**spike**: client-preset output type-checks; fall back to the newest 6.x only with orchestrator sign-off) | Apache-2.0 | — | Ch22 |
| graphql-ws (npm) | 6.4.1 | MIT | 2026-10-15 | prose only (Ch21/22) |
| grafana/otel-lgtm | 0.36.0 pinned (0.37.0 released 2026-10-16; bumped in the DX chore, not in-wave) | Apache-2.0 | 2026-10-09 | Ch19 |
| `registry.access.redhat.com/ubi10/nodejs-24` | `10.2-1791943587` | — | — | Ch20, Ch22 build stages |
| `registry.access.redhat.com/ubi10/nodejs-24-minimal` | `10.2-1791916595` | — | 2026-10-13 | Ch20, Ch22 runtime |
| `ubi10/openjdk-25` / `-runtime` | `1.24-16` (unchanged pin) | — | — | all |
| `ubi10/python-314-minimal` | `10.2-1791928506` (unchanged pin) | — | — | all |
| Rejected: Apollo Router, Apollo Federation composition, rover | — | Elastic License 2.0 | — | not used |
| Alternative: Cosmo Router / wgc / @wundergraph/composition | 0.359.0 / 0.133.0 / 0.65.2 | Apache-2.0 | 2026-10 | §8 alternative |

**otel-lgtm 0.36.0 internals** (read from the image): Tempo listens on 3200, and its `metrics_generator` runs the `span-metrics` processor (dimensions `service_name`, `operation`, `status_code`) and `service-graphs`, remote-writing to Prometheus on 9090. RED metrics per span name therefore exist with no application code. Loki is on 3100. The collector receives OTLP on 4317/4318.

**Books.** Execution plan: Lyon's *Full Stack GraphQL Applications* is the reference for Ch19–22. Verified titles so far: Ch7 "Adding authorization and authentication", Ch9 "Advanced GraphQL considerations". Every other title is a **spike** (check the ToC with the O'Reilly tool; cite by verified chapter title only, and only where the chapter actually covers the topic). DDIA is not required in Wave D.

**Figures.** The site has 59. Wave D adds 16 (Ch19 4, Ch20 5, Ch21 4, Ch22 3), for a total of 75.

---

## 1. Approach

### Sequencing (DAG)

| Step | Executor | Owns (exclusive write set) | Depends on |
|---|---|---|---|
| **D0** Harness + CI | Executor 1 | `examples/_lib/lib.sh`, `examples/_lib/README.md`, `.github/workflows/contracts.yml` (the `examples` job's `timeout-minutes` only) | S8 |
| **D1** Ch19 Observability | Executor 2 | `_docs/19-*`, `examples/19-observability/**`, `diagrams/19-*.py`, `diagrams/examples/19-*`, `assets/diagrams/19-*` | D0 (copies Ch13) |
| **D2** Ch20 Federation and schema composition | Executor 3 | same pattern for `20-*` | D0 (copies Ch13) |
| **D3** Ch21 Real-time | Executor 4 | same pattern for `21-*` | D0 (copies Ch13) |
| **D4** Ch22 Client integration | Executor 5 | same pattern for `22-*` | D0 (copies Ch13) |
| **DV1…DV4** Validation (Opus), one per chapter | Opus | read-only findings; fixes routed to the owning executor | the chapter's step |
| **DW** Wrap (orchestrator) | orchestrator | `_plans/*`, `_example_pages/index.md`, commits, coverage-matrix flips, deliberate one-clause fixes (§4) | DV1–DV4 + CI green |
| **DX** OTLP default chore, Ch0–Ch18 (§8 decision 9) | Executor 1 (after DW) | `examples/0*/`, `examples/1[0-8]*/` compose files, READMEs and `application.properties`/Containerfile OTel lines only; `_docs/00-*` one paragraph (deliberate fix) | DW |

How to run it:
- D0 is small (helpers only). After it lands, run **D1–D4 in parallel** (four executors). None depends on another: each copies Ch13 and writes only its own `NN-*` paths. Ch22 deliberately copies Ch13, not Ch21 (§8 decision 11), so the client chapter does not wait for subscriptions.
- The critical path is D0 → D2 (Ch20 is the largest: four subgraph services, a composer and two gateways).
- **Shared files are single-owner.** Only D0 edits `lib.sh`, its README and the CI workflow. Only the orchestrator edits `_plans/`, `coverage-matrix.md` and `_example_pages/`. **Nobody edits `contracts/`** (§8 decision 10). If a chapter executor needs a helper D0 did not provide, it writes the helper as a local function at the top of its own `verify.sh`, says so in its hand-back, and the orchestrator decides at DW whether to promote it into `lib.sh` (one owner, after the wave).
- Each DVn starts as soon as its chapter's checkpoint commit lands. At most two repair rounds per chapter; a third failure goes back to the user.
- DX runs after DW, as its own commit, and re-runs every `verify.sh` (Ch0, Ch3–Ch22) concurrently before it lands.

**Executor rules (unchanged from Waves A–C, binding)**
- Write files only. No git.
- Do not touch `_plans/*`, `coverage-matrix.md`, `_example_pages/`, `scripts/`, `contracts/`, `examples/_lib/` (only D0 and DX as listed), or any other chapter's files, including every verified Ch0–Ch18 file.
- Never delete or reinstall `contracts/node_modules`.
- Never `pkill -f`. Several stacks run concurrently; stop only your own with `docker compose -p <your project> down -v`.
- Before handing back, every executor runs its own `verify.sh` green; `python3 -I scripts/validate.py; echo rc=$?` (never piped through `tail`); `bash scripts/wordcount.sh _docs/NN-*.md`; `npm --prefix contracts run lint`; and renders every new figure to PNG and **views** it.

**Orchestrator rule.** At each chapter's checkpoint commit, flip that chapter to `draft` in **both** the Topics table (T20–T23) and the Full chapter inventory, in the same commit as the chapter, then push so CI runs `verify: NN-*`, the wordcount GATE and `validate.py`. A chapter is `verified` only after DVn passes **and** the CI `verify: NN-*` job is green.

**Rejected alternatives (one line each)**
- *Serial Ch19 → Ch22*: no real dependency; Ch21's subscription client and Ch22's clients are independent.
- *Ch22 built on Ch21*: it couples the client chapter to the subscription surface and serializes the wave; Ch22 points to Ch21 for subscription clients in prose.
- *Ch20 built on Ch19 (traces across the gateway)*: it adds the LGTM image to the heaviest example; a distributed trace across the gateway is described in Ch20 prose and pointed back to Ch19.
- *Apollo Router or Apollo composition/rover*: Elastic License 2.0, not OSS by the site's rule.
- *Hive's hosted schema registry or Hive Gateway's dev composition mode*: a hosted service, or a mode documented for local development only; composition is an explicit, inspectable step here.
- *A hand-written graphql-sse or WebSocket protocol on either stack*: each stack's own transports are used; no protocol code is written on the server.
- *A browser test (Playwright) for Ch22*: a browser image and a page add nothing the normalized cache does not already show headlessly in Node (§8 decision 6).

### Example structure

Same as Waves A–C: a self-contained copy per chapter, package `com.patterncatalyst.shipping.tracking`, Python package `app`. For each chapter change the artifactId, the Python project name (then **re-run `uv lock`**), `quarkus.otel.service.name` / `OTEL_SERVICE_NAME`, the container names and the compose `name:`. Add `python/.ruff_cache/` to each `.gitignore`; Node directories also ignore `node_modules/` and generated code (`src/gql/`).

**Pins** are identical to Wave C (Quarkus 3.40.1; Strawberry 0.335.0; FastAPI 0.143.2; uvicorn 0.54.0; uv 0.13.1; pydantic-settings 2.16.0; OTel as in Ch13; `ubi10/openjdk-25:1.24-16`; `ubi10/python-314-minimal:10.2-1791928506`; `grafana/otel-lgtm:0.36.0`). If a newer stable release exists at execution time, **do not** bump it inside Wave D; record it for DX.

**New pins in Wave D**

| Chapter | Addition | Pin |
|---|---|---|
| 19 | `io.opentelemetry.instrumentation:opentelemetry-graphql-java-20.0` | platform BOM (2.28.1-alpha) |
| 19 | LGTM as a default service (not a profile) | `docker.io/grafana/otel-lgtm:0.36.0` |
| 20 | Gateway and composer image (one image, two roles; C-7) | `ubi10/nodejs-24:10.2-1791943587` build, `ubi10/nodejs-24-minimal:10.2-1791916595` runtime; npm `@graphql-hive/gateway@2.15.2`, `@theguild/federation-composition@0.27.0`, `graphql@16.14.2` with a committed `package-lock.json` |
| 21 | Subscription test client image | `ubi10/python-314-minimal:10.2-1791928506`, uv 0.13.1, `gql[websockets]==4.4.0` (uv.lock pins `websockets` 17.2) |
| 22 | JS client | Node image as Ch20; `@apollo/client@4.3.4`, `rxjs@7.8.2`, `graphql@16.14.2`, `@graphql-codegen/cli@7.4.6`, `@graphql-codegen/client-preset@6.2.3`, `typescript@7.0.2` |
| 22 | Python client | `gql[httpx]==4.4.0` |
| 22 | Java client | `io.quarkus:quarkus-smallrye-graphql-client` (BOM), Quarkus command mode |

Strawberry extensions are **classes or factories** in every Wave D chapter (Pitfall C-1).

### How the schema slice grows

| Ch | Base | Served slice | Behaviour added |
|---|---|---|---|
| 19 | Ch13 | Ch13's (all but `Subscription`) | OTel traces with a span per resolver and per source call, OTLP metrics (errors by code, deprecated-field usage), span metrics from Tempo, logs correlated by trace id |
| 20 | Ch13 | through each gateway: all but `Query.node`, `Query.nodes` and `Subscription` | two subgraphs per stack (cargo, handling), entities and references, explicit composition with failure fixtures, two cross-wired gateways |
| 21 | Ch13 | **the whole canonical SDL** (adds `Subscription.cargoHandled`) | subscriptions over `graphql-transport-ws` (and `graphql-ws`) on both stacks, GraphQL over SSE on Python, a plain SSE feed with `Last-Event-ID` resume on both |
| 22 | Ch13 | Ch13's | three typed clients (Apollo Client with a normalized cache, `gql`, SmallRye typesafe and dynamic), codegen against the canonical SDL, run against both servers |

### Canonical SDL changes

**None** (§8 decision 10). `Subscription.cargoHandled(trackingId: TrackingId!): HandlingEvent!` is already canonical (S3). Federation directives belong to the subgraph schemas, which live in the Ch20 example; the canonical SDL stays the API schema the gateway must serve. The `contracts/` diff for Wave D must be empty, so the breaking gate has nothing to classify.

### Seed data

The Ch13 seed unchanged (VWX901, XYZ789, STU678, DEF456, ABC123, GHI345 with the `booking service unavailable` fault; DEF456 `evt_3`–`evt_9`; ABC123 `evt_1`/`evt_2`). The first new registration is `evt_10`. Registrations used in Wave D:

| Name | Input | Expected |
|---|---|---|
| `REG_A1` | ABC123 `UNLOAD` DEHAM `V100S` `2026-10-09T15:00:00Z` | `evt_10`, `transportStatus` `IN_PORT` (Wave C value) |
| `REG_D1` | DEF456 `CUSTOMS` at DEF456's last known location, no voyage, `2026-10-09T16:00:00Z` | next id, `userErrors` empty (**spike**: confirm against Ch13 validation, adjust the location/time and record) |
| `REG_A2` | ABC123 `LOAD` DEHAM `V100S` `2026-10-09T18:00:00Z` | next id, `ONBOARD_CARRIER` (**spike** as above) |

### Ports, project names, extra services

**Rule (unchanged):** chapter N owns host ports 8100+10·N … +9; Quarkus +0, Python +1, extras +2…+9. Internal-only services publish nothing.

| Ch | dir | Quarkus | Python | extras (host → container) | compose `name:` / `PROJECT` | container prefix | artifactId / Python project |
|---|---|---|---|---|---|---|---|
| 19 | `19-observability` | 8290 | 8291 | 8292 → lgtm:3000 (Grafana), 8293 → lgtm:3200 (Tempo), 8294 → lgtm:9090 (Prometheus), 8295 → lgtm:3100 (Loki); OTLP 4317/4318 internal only | `gql-ch19-observability` | `ch19-observability-` | `ch19-quarkus-observability` / `shipping-python-ch19-observability` |
| 20 | `20-federation` | 8302 cargo, 8304 handling | 8303 cargo, 8305 handling | 8300 → gateway-a:4000 (cargo-quarkus + handling-python), 8301 → gateway-b:4000 (cargo-python + handling-quarkus); composer internal | `gql-ch20-federation` | `ch20-federation-` | `ch20-quarkus-cargo-subgraph`, `ch20-quarkus-handling-subgraph` / `shipping-python-ch20-cargo-subgraph`, `shipping-python-ch20-handling-subgraph` |
| 21 | `21-real-time` | 8310 | 8311 | — (HTTP, WebSocket and SSE share the app port); `client` service has no port | `gql-ch21-real-time` | `ch21-real-time-` | `ch21-quarkus-real-time` / `shipping-python-ch21-real-time` |
| 22 | `22-client-integration` | 8320 | 8321 | — (`js-client`, `python-client`, `java-client` have no ports) | `gql-ch22-clients` | `ch22-clients-` | `ch22-quarkus-clients` (server), `ch22-quarkus-typed-client` (client) / `shipping-python-ch22-clients`, `shipping-python-ch22-client` |

- Ch19 publishes LGTM on its own block, so it never collides with a reader's own observability profile on 3000/4317/…; the README says so.
- Ch20 departs from "Quarkus +0, Python +1" for the gateways; the README's Ports table states the mapping.
- Client and composer services are run with `docker compose run` (D0 `compose_run`), never published.
- **CI.** One example per `ubuntu-latest` job (4 vCPU, 16 GB). Estimated attempt times: Ch19 ~8 min (the LGTM image is the largest in CI; span metrics need up to two generator flushes), Ch20 ~12 min (two Maven and two uv builds in parallel, one Node build), Ch21 ~7 min, Ch22 ~12 min (two Maven builds, one Node build with codegen). D0 raises the `examples` job to `timeout-minutes: 60` to cover three attempts. New pulls: `grafana/otel-lgtm:0.36.0` (Ch19), `ubi10/nodejs-24` and `-minimal` (Ch20, Ch22). No new job, no new runner tooling: Node and Python run in containers; the host keeps only bash, curl, `python3 -I` stdlib and the Node 24 the workflow already sets up.

---

## 2. Per chapter

**Common to every chapter** (as in Waves A–C):
- **Front matter:** `title` (Ch19 "Observability", Ch20 "Federation & schema composition", Ch21 "Real-time: subscriptions vs SSE vs WebSockets", Ch22 "Client integration"), `order: N`, `part:` exactly "Observability & the Gateway" (Ch19–20) or "Real-time & Client Integration" (Ch21–22), `description`, `duration` (words/200).
- **Length and figures:** 2,800–3,400 prose words (`wordcount.sh`); figures via `{% include excalidraw.html file="NN-slug" alt="…full sentences…" caption="Figure N.M — …" %}`, numbered by order of appearance; at least one `{% include codetabs.html langs="Quarkus|Python" %}` (Ch22 may use `langs="Java|Python|TypeScript"`; validate.py checks the fence count).
- **Last three blocks:** `## On the wire` (commands and the exact values `verify.sh` asserts), the Decision callout naming Ch2's axes, `## Where this goes next`.
- **Prose rules:** no `{{`/`{%` outside includes and fences; books by verified chapter title only; spec sections by name; "execution error"; never claim a server log carries the GraphQL path or a request id (Ch19 may say a log record carries the **trace id**, because it is asserted); every Java/Python/TypeScript snippet in prose exists in the example (Pitfall 27); the content rule above.
- **Diagram specs:** `diagrams/NN-slug.py`; architecture figures `diagrams/examples/NN-slug-architecture.py` (not counted). Data-movement figures drawn from a run name that run in the spec docstring. Regenerate; never hand-edit SVG.
- **verify.sh skeleton:** Ch13's: `run_stack_check <stack> <url> …` per stack, then `PASS`; `source_calls_reset` before each counted case; one `__type` per request; the scalar `kind`/`specifiedByURL` loop; `assert_deprecated` for `finalArrivalDate`; `assert_sdl_conforms` (or `assert_sdl_equals`, Ch21) last; scratch dir via `on_exit`; `ensure_contracts_tools` before direct npm/npx.
- **README sections** (Ch13 order): The served slice, Run it, The source-call log (lab only), Ports, On the wire, Code-first notes (spike results), Diagram.

### Ch19: Observability

**Files:** `_docs/19-observability.md`, `examples/19-observability/` (from Ch13).

**Learning goals.** By the end of the chapter the reader can:
- explain why URL- and status-keyed telemetry sees one route at `200` for every GraphQL request (Ch1:195, Ch2:81, Ch9:173);
- name the three signals and what each answers for a GraphQL service: traces (where the time went, per resolver and per source), metrics (how often, how slow, which errors by code), logs (the detail of one failure, linked to its trace);
- wire OpenTelemetry idiomatically on both stacks and export OTLP to a collector;
- read one trace with a span per resolver and see Ch13's batching in it (many resolver spans, one source span);
- count errors by `extensions.code` and deprecated-field usage by operation and client (Ch9:272, Ch11:93/278);
- derive RED metrics per operation from spans, and decide what to record (operation name, field coordinates) and what not to (variable values, tokens; Ch18:325).

**H2 outline**
1. *One endpoint, every operation.* An access log and a latency histogram for `POST /graphql`; why every operation looks the same (Figure 19.1). Operation names as the unit (Ch15:242).
2. *Three signals, one collector.* OTLP from both stacks to `grafana/otel-lgtm` (collector, Tempo, Prometheus/Mimir, Loki, Grafana) (Figure 19.3). W3C Trace Context (`traceparent`) joins a caller's trace.
3. *A trace per request, a span per resolver.* The HTTP server span → the operation span → resolver spans → `source.call` spans. Quarkus: `quarkus-opentelemetry` plus the OpenTelemetry project's graphql-java instrumentation, installed through the same `GraphQL.Builder` event Ch14 used. Python: `opentelemetry-instrument` for FastAPI plus Strawberry's `OpenTelemetryExtension`. The naming difference per stack is stated neutrally.
4. *Reading the trace.* The `Q_FAN` trace from the run (Figure 19.2): resolver spans overlap; one `location.getLocations` source span serves many location resolvers (Ch13's loader, visible). Trivial fields carry no span on either stack.
5. *Errors in a trace.* GHI345: the resolver span records the exception and an error status; the client still reads `SERVICE_UNAVAILABLE` and the masked message (Ch9's allowlist); the detail lives in the trace and the log, not the response.
6. *Metrics from spans.* Tempo's span-metrics generator turns every span into call counts and latency per `service_name` and span name, with no application code. Operation RED in Prometheus.
7. *Metrics the spans cannot give.* `graphql.errors` by `error.code` and operation (the Ch9 promise); `graphql.field.deprecated.usage` by field coordinate, operation and client (the Ch11 promise: when its count stays at zero, the field can go). Both are OpenTelemetry counters recorded at the framework's operation-level hook (graphql-java `Instrumentation`; Strawberry `SchemaExtension`).
8. *Logs that point at traces.* The masked error's server-side log record carries the trace id; Loki finds it from the trace.
9. *What to record.* Operation name, type, field coordinates, codes: yes. Variable values, tokens, owner lists: no. Strawberry's `arg_filter` drops resolver arguments; the Quarkus instrumentation records a document with literals replaced; documents sent with variables keep values out of both (Figure 19.4). Sampling (`parentbased_always_on` in the lab).
10. *Cardinality.* Why operation name is a good label and the document or a tracking id is not.
11. On the wire / Decision / next (federation, Ch20: a trace that crosses the gateway).

**Example design**
- **compose**: `lgtm` is a **default** service (no profile) with Ch0's healthcheck; `quarkus` and `python` `depends_on: lgtm: condition: service_healthy`; `OTEL_EXPORTER_OTLP_ENDPOINT=http://lgtm:4317` on both; ports per §1.
- **Quarkus**
  - `pom.xml` adds `io.opentelemetry.instrumentation:opentelemetry-graphql-java-20.0` (no version; BOM).
  - Properties:
    ```
    quarkus.otel.service.name=ch19-observability-quarkus
    quarkus.otel.exporter.otlp.endpoint=${OTEL_EXPORTER_OTLP_ENDPOINT:http://localhost:4317}
    quarkus.otel.metrics.enabled=true
    quarkus.otel.logs.enabled=true
    quarkus.otel.metric.export.interval=5S
    quarkus.otel.bsp.schedule.delay=1S
    quarkus.smallrye-graphql.tracing.enabled=false
    ```
    The comment says the operation span comes from the graphql-java instrumentation, so SmallRye's own operation span is off and there is one operation span per request.
  - `Telemetry.java` (`@ApplicationScoped`, constructor-injected `OpenTelemetry`, `Meter`): `void instrument(@Observes GraphQL.Builder builder)` appends, exactly in Ch14's pattern (read the chain from `builder.build().getInstrumentation()`, wrap in a `ChainedInstrumentation`):
    1. `GraphQLTelemetry.builder(openTelemetry).setDataFetcherInstrumentationEnabled(true).build().newInstrumentation()`;
    2. `TrackingInstrumentation extends SimplePerformantInstrumentation`: `beginExecuteOperation` walks the operation with graphql-java's `QueryTraverser` (schema, document, operation name, coerced variables) and increments `graphql.field.deprecated.usage` once per deprecated field coordinate per request; `instrumentExecutionResult` increments `graphql.errors` once per error, attribute `error.code` = `extensions.code` or `unclassified`.
    - Attributes: `graphql.operation.name` (or `anonymous`), `graphql.field.coordinate` (`Itinerary.finalArrivalDate`), `client.name` from the `X-Client-Name` request header (`unknown` when absent; read through `CurrentVertxRequest` at execution start, **spike** that it is active there; fallback: SmallRye `Context` request headers).
  - Source spans: `SourceCalls.call`/`callBatch` get `@WithSpan("source.call")` with `@SpanAttribute("source.name")`, `@SpanAttribute("source.operation")`, `@SpanAttribute("source.key")` (**spike** D1-a: the CDI interceptor applies and the span ends when the `Uni` completes; fallback: an injected `Tracer` and a span ended in `onTermination`).
  - **Spikes:** **D1-b** the data-fetcher spans' names and attributes (`graphql.field.name`, `graphql.field.path`) and that `Uni`/batched `@Source` fetchers end their spans when the value arrives; **D1-c** the operation span name format (OTel semconv `query TrackCargo`); **D1-d** whether the failing GHI345 fetcher span carries status ERROR and an exception event; **D1-e** Prometheus names after OTLP translation (`graphql_errors_total`, label `error_code`, service label `job` or `service_name`).
- **Python**
  - Containerfile env adds `OTEL_METRICS_EXPORTER=otlp`, `OTEL_LOGS_EXPORTER=otlp`, `OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true`, `OTEL_METRIC_EXPORT_INTERVAL=5000`, `OTEL_BSP_SCHEDULE_DELAY=1000`; `OTEL_SERVICE_NAME=ch19-observability-python`.
  - Schema extensions: `[partial(MaskErrors, …), partial(OpenTelemetryExtension, arg_filter=drop_arguments), OperationMetrics]`. `drop_arguments` returns `{}` (the README explains: arguments are values; field coordinates are enough).
  - `app/telemetry.py`: `OperationMetrics(SchemaExtension)`: `on_execute` before `yield` visits the document with graphql-core `TypeInfo` + `TypeInfoVisitor` and counts each deprecated field (`get_field_def().deprecation_reason`) once per request; after `yield` counts `execution_context.result.errors` by `extensions.code`. Same meter names and attributes as Quarkus; `client.name` from `context.request.headers`.
  - `SourceCalls.call`/`call_batch` wrap the lookup in `tracer.start_as_current_span("source.call", attributes={…})` (the OpenTelemetry API's manual-instrumentation idiom).
  - **Spike D1-f:** the Strawberry operation span is a child of the FastAPI server span; resolver spans for `async` loader-backed fields end after the batch.
- Sources, batching, seed and debug endpoints unchanged from Ch13.

**Queries** (top of `verify.sh`): `Q_FAN` (Ch13's, named `FanOut`), `TRACK` = `query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }`, `LEGACY` = `query LegacyArrival($id: TrackingId!) { cargo(trackingId: $id) { itinerary { finalArrivalDate } } }`, `FAULT` = Ch13's GHI345 edge query named `CargoPage`.

**verify.sh assertions (both stacks; per-stack span names from spikes D1-b/c).** Each traced case generates a trace id with `new_trace_id`, sets `LGTM_TRACEPARENT`, and reads the trace with `tempo_trace http://localhost:8293 <id> 60 <min-spans>`.
1. Responses are unchanged: `Q_FAN` data and source calls as in Ch13 (Python 6 / Quarkus 8); `TRACK` gives `ONBOARD_CARRIER`.
2. The trace joins the caller: every span in the trace has the sent trace id; exactly one HTTP server span (`POST /graphql` or the stack's observed name); exactly one operation span, named for `FanOut`, a descendant of the HTTP span.
3. A span per resolver: for `Q_FAN`, resolver spans exist for `cargos`, `itinerary`, `delivery`, `handlingHistory`, `loadLocation` (per-stack names) and each descends from the operation span; `assert_span … min max` counts match the data shape (record the counts in the README).
4. Batching is visible: `source.call` spans with `source.operation=getLocations` count exactly 1 (Python) / as Ch13's call log says (Quarkus), while location resolver spans count ≥ 2. The `source.call` span count equals the source-call log length for the same request.
5. Errors: `FAULT` response has `SERVICE_UNAVAILABLE` and the masked message as in Ch13; in its trace the span for the failing field has status ERROR (**spike** D1-d) and the operation span is still present.
6. What is recorded: the operation span's document attribute (Quarkus `graphql.document`, Python `query`) does not contain `ABC123` for `TRACK` (sent as a variable); no Python span carries a `graphql.param.*` attribute.
7. Span metrics: `wait_for_metric http://localhost:8294 'sum(traces_spanmetrics_calls_total{service_name="ch19-observability-<stack>", span_name=~"<op span for TrackCargo>"})' 3 120` after three `TRACK` requests (exact metric and label names **spike** D1-e).
8. Error metric: after one `FAULT` request, `graphql_errors_total{error_code="SERVICE_UNAVAILABLE", graphql_operation_name="CargoPage"}` ≥ 1 (names per D1-e).
9. Deprecated-field usage: `LEGACY` twice with `LGTM_HEADERS='X-Client-Name: legacy-app'` and once without; `graphql_field_deprecated_usage_total{graphql_field_coordinate="Itinerary.finalArrivalDate", client_name="legacy-app"}` = 2 and `client_name="unknown"` = 1; `TRACK` adds nothing to it.
10. Logs: `loki_wait http://localhost:8295 '{service_name="ch19-observability-<stack>"} | trace_id="<FAULT trace id>"' 60 1` returns at least one record, and that record does not appear in the client response (**spike** D1-g: the LogQL form for OTLP structured metadata).
11. Deprecation check, scalar checks, `assert_sdl_conforms` (unchanged slice).

**Figures (4)**
- `19-one-endpoint-blind-spot`: left, a URL dashboard (one route, all `200`, one latency curve); right, the same traffic split by operation name and by `extensions.code`.
- `19-span-per-resolver` (data movement): the `FanOut` trace as a waterfall from the run: HTTP span, operation span, resolver spans overlapping, a single batched `source.call` under many location resolvers. Docstring names the run.
- `19-telemetry-pipeline` (data movement): both stacks → OTLP → collector → Tempo (traces; span-metrics generator → Prometheus), Prometheus (OTLP metrics), Loki (logs, with trace id) → Grafana; `traceparent` arriving from the client.
- `19-what-to-record`: two columns, record (operation name and type, field coordinate, error code, client name, source name/operation) vs leave out (variable values, tokens, owner lists, raw documents with literals), with the label-cardinality note.

**Citations.** OpenTelemetry specification ("Trace Context", semantic conventions for GraphQL spans: `graphql.operation.name`, `graphql.operation.type`, `graphql.document`); W3C Trace Context; Quarkus "Using OpenTelemetry" guides (tracing, metrics, logging); the OpenTelemetry Java instrumentation graphql-java library docs; Strawberry "OpenTelemetry" extension docs; OpenTelemetry Python "zero-code instrumentation"; Grafana Tempo "metrics-generator" (span metrics) docs; Lyon only if a verified chapter covers monitoring (**spike**).

### Ch20: Federation & schema composition

**Files:** `_docs/20-federation-and-schema-composition.md`, `examples/20-federation/` (from Ch13).

**Learning goals.** By the end of the chapter the reader can:
- say when federation pays (Ch2:87/146/154: several teams, schema review as the queue) and when one schema owner is cheaper;
- split the tracking view into subgraphs by ownership, and mark entities with `@key`, shared value types with `@shareable`, and references with `resolvable: false`;
- implement entity resolution on both stacks (`_entities`) and batch it;
- compose subgraphs into a supergraph as an explicit, failing step, and read composition errors;
- follow a query plan across subgraphs and count the subgraph requests it makes;
- check that the composed API schema is still the canonical contract;
- reason about partial failure across subgraphs with Ch4's nullability.

**H2 outline**
1. *When one schema owner becomes the queue.* Ch2's seventh axis; Ch1:177.
2. *Subgraphs by ownership.* The cargo subgraph (booking and routing team) and the handling subgraph (handling team) (Figure 20.1). Both read the booking and routing backends; only the cargo subgraph exposes them in the graph. What stays out of this example: `node`/`nodes` across subgraphs (needs entity interfaces, `@interfaceObject`) and `Subscription` (Ch21).
3. *Entities, keys and references.* `Cargo @key(fields: "trackingId")` in both; `Location @key(fields: "unLocode")` and `Voyage @key(fields: "number")` resolvable in cargo, references (`resolvable: false`) in handling; `PageInfo` `@shareable`. The representation `{__typename, trackingId}` (Figure 20.4).
4. *Federation on SmallRye.* `@Key`, `@Shareable`, `@Resolver` entity resolvers with `federation.batch-resolving-enabled`, `@Link` to Federation 2.7.
5. *Federation on Strawberry.* `strawberry.federation.Schema(federation_version="2.7")`, `@strawberry.federation.type(keys=[…])`, `resolve_reference` through Ch13's DataLoaders.
6. *Composition as a gate.* Live `_service { sdl }` from each subgraph → `@theguild/federation-composition` → a supergraph file → Hive Gateway (Figure 20.2). A failed composition stops the deploy, the way Ch11's breaking gate stops a pull request. Two fixtures, two errors.
7. *A query plan.* `TrackCargo` through gateway-a: cargo subgraph (root), handling subgraph (`_entities` for `Cargo`), cargo subgraph again (`_entities` for `Location`, batched) (Figure 20.3). Counts from the source-call logs.
8. *Mutations across subgraphs.* `registerHandlingEvent` on the handling subgraph; the payload's `cargo { description }` comes from the cargo subgraph by entity fetch; `delivery` is fresh because its owner wrote the event.
9. *The contract still holds.* The gateway's API schema conforms to `contracts/schema/` (slice: no `node`, `nodes`, `Subscription`). Federation directives never reach clients.
10. *Two stacks, one supergraph.* Gateway-a composes cargo-on-Quarkus with handling-on-Python; gateway-b the reverse (Figure 20.5). The subgraph contract is stack-neutral.
11. *When a subgraph is down.* `Cargo.delivery: Delivery!` and `handlingHistory: …!` are owned by handling; with that subgraph stopped, the non-null fields null the cargo (Ch4). Choosing nullability at subgraph seams.
12. *Operating a supergraph.* Composition in CI before deploy, subgraph schema checks against the composed result, traces across the gateway (the gateway propagates `traceparent`; Ch19), `@requires` for data that only another subgraph has (prose only).
13. On the wire / Decision / next.

**Subgraph split (exact)**

| Subgraph | Owns | Entities and references |
|---|---|---|
| cargo | `Query.cargo`, `Query.cargos`, `Query.location`, `Query.voyage`; `Cargo.{id, trackingId, description, origin, destination, routeSpecification, itinerary}`; `Location`, `Voyage`, `CarrierMovement`, `RouteSpecification`, `Itinerary`, `Leg`, `CargoConnection`, `CargoEdge`, `RoutingStatus` | `Cargo @key("trackingId")`, `Location @key("unLocode")`, `Voyage @key("number")`, all resolvable |
| handling | `Mutation.registerHandlingEvent`; `Cargo.{trackingId, handlingHistory, delivery}`; `HandlingEvent` (all fields), `HandlingEventConnection`, `HandlingEventEdge`, `Delivery`, `HandlingActivity`, `TransportStatus`, `RoutingStatus` (identical definition), `HandlingEventType`, input, payload, `UserError`, `UserErrorCode` | `Cargo @key("trackingId")` resolvable; `HandlingEvent @key("id")`; `Location @key("unLocode", resolvable: false)`, `Voyage @key("number", resolvable: false)` |
| both | `Node` interface, scalars, `PageInfo @shareable`; every description copied from the canonical SDL verbatim | — |

**Spike D2-a (stop and report if it fails):** composition accepts `Node` defined in both subgraphs with implementers split between them, and the supergraph API schema shows all four implementers. **D2-b:** SmallRye `@Key(resolvable = false)` prints `resolvable: false`; batch `@Resolver` methods take a `List` and are called once per `_entities` request. **D2-c:** SmallRye's `@Link` and Strawberry's `federation_version="2.7"` compose together.

**Example design**
- Layout: `quarkus/cargo/`, `quarkus/handling/`, `python/cargo/`, `python/handling/` (four independent projects copied from Ch13 and cut down to their subgraph), `gateway/` (one Node project: `package.json`, `package-lock.json`, `compose-supergraph.mjs`, `Containerfile`), `fixtures/` (failure fixtures). Each subgraph keeps Ch13's sources, latency, source-call log and debug endpoints; the handling subgraphs hold the mutable handling store.
- **Quarkus subgraphs:** `quarkus.smallrye-graphql.federation.enabled=true`, `quarkus.smallrye-graphql.federation.batch-resolving-enabled=true`; `@Link(url = "https://specs.apollo.dev/federation/v2.7", _import = {…})` on a package-level or schema class; `@Key(fields = @FieldSet("trackingId"))` on `Cargo`; `@Resolver` methods `List<Cargo> cargosByTrackingId(List<…> trackingIds)` (and Location/Voyage in cargo) calling the Ch13 bulk sources.
- **Python subgraphs:** `strawberry.federation.Schema(query=…, mutation=…, federation_version="2.7", config=…, extensions=[partial(MaskErrors, …)])`; `@strawberry.federation.type(keys=["trackingId"])` with `resolve_reference` loading through the request's DataLoader; reference types `@strawberry.federation.type(keys=["unLocode"], resolvable=False)`.
- **Composer** (`gateway/compose-supergraph.mjs`, ~40 lines, uses only `graphql` and `@theguild/federation-composition`): `node compose-supergraph.mjs --out /supergraph/<name>.graphql --subgraph cargo=<url> --subgraph handling=<url>` fetches `{ _service { sdl } }` from each URL, calls `composeServices([{ name, typeDefs: parse(sdl), url }])`, writes `supergraphSdl`, and on `compositionHasErrors` prints one line per error, `<extensions.code>: <message>`, and exits 1. `--file name=path` reads SDL from a file (fixtures). The script comment states that composition is a build step the gateway consumes.
- **compose services:** four subgraphs (healthchecks as Ch13); `composer` (`image: gql-ch20-federation-gateway:local`, built here) runs once after the subgraphs are healthy and writes `supergraph-a.graphql` (cargo-quarkus + handling-python) and `supergraph-b.graphql` (cargo-python + handling-quarkus) to the named volume `supergraph`; `gateway-a`/`gateway-b` (same image, C-7) run `npx hive-gateway supergraph /supergraph/supergraph-<x>.graphql --port 4000` with `depends_on: composer: condition: service_completed_successfully`; healthcheck on `/readiness` with `node -e` fetch (**spike** D2-d: endpoint name and that the minimal image has what the healthcheck needs).
- **Fixtures:** `fixtures/handling-key-type-conflict.graphql` (the handling subgraph with `Location.unLocode: String!` instead of `UnLocode!`) and `fixtures/handling-unshared-pageinfo.graphql` (`PageInfo` without `@shareable`), each composed against a committed copy of the cargo subgraph SDL, `fixtures/cargo.graphql`, exported from the live service at authoring time. Expected codes **spike** D2-e (`FIELD_TYPE_MISMATCH`, `INVALID_FIELD_SHARING` are the expected names).

**Queries:** `TRACK_FED` = `query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId description itinerary { legs { loadLocation { name } } } delivery { transportStatus lastKnownLocation { name } } handlingHistory(first: 2) { edges { node { type location { name } } } } } }`; `REGISTER` as Ch13 with payload `cargo { trackingId description delivery { transportStatus } }`.

**verify.sh assertions.** Gateways at 8300/8301; subgraphs at 8302–8305 for direct cases and source-call logs.
1. Subgraph SDL: each subgraph's `_service { sdl }` contains `@key(fields: "trackingId")` on `Cargo`; handling ones contain `resolvable: false` on `Location`; cargo ones do not define `handlingHistory`.
2. Entity resolution, direct: `_entities(representations: [{__typename: "Cargo", trackingId: "ABC123"}, {__typename: "Cargo", trackingId: "ZZZ999"}])` → cargo subgraphs `[{description: <seed>}, null]` via `... on Cargo { description }`; handling subgraphs `{delivery {transportStatus}}` `ONBOARD_CARRIER` for ABC123. Five `Location` representations in one request → one bulk location source call on cargo subgraphs.
3. Composition gate: `compose_run composer … --file cargo=fixtures/cargo.graphql --file handling=fixtures/handling-key-type-conflict.graphql` exits 1 and prints the expected code; the shared-field fixture likewise; the real composition (already done by the `composer` service) exited 0 (`docker compose ps -a` state, or re-run and check the file).
4. Query plan through each gateway: `TRACK_FED` for ABC123 gives the Ch13 values (itinerary locations, `ONBOARD_CARRIER`, two events); then, from the subgraph source-call logs: the cargo subgraph saw **2** distinct requests and the handling subgraph **1** (`assert_request_count`); the cargo subgraph's second request made exactly one `location.getLocations` call whose key is the event and last-known locations (exact key from the run).
5. Mutation across subgraphs (gateway-a then gateway-b, each against its own handling subgraph): `REG_A1` → `evt_10`, `IN_PORT`, `description` from the cargo subgraph; the handling subgraph logged one `handling.appendEvent`; a repeat with the same `idempotencyKey` returns `evt_10`.
6. Errors cross the gateway: the GHI345 page (`cargos(first: 10)`) through each gateway gives a `SERVICE_UNAVAILABLE` error at the GHI345 edge path with the other nodes present (per-stack batch blast radius as in Ch13, since the cargo subgraph's stack decides it).
7. Contract: `assert_sdl_conforms http://localhost:8300/graphql` and `…8301…` (slice removals `node`, `nodes`, `Subscription` allowed by the existing filter; if the gateway adds directives, list them in a local `LGTM_SDL_FRAMEWORK_DIRECTIVES` override in verify.sh and record them in the README); `assert_deprecated` for `finalArrivalDate` through each gateway; scalar `specifiedByURL` through each gateway.
8. Subgraph down (last): `docker compose -p "$PROJECT" stop handling-python`; `TRACK_FED` through gateway-a gives `data.cargo` null with an error whose path starts `["cargo"]`; `location(unLocode:"NLRTM"){name}` through gateway-a still answers `Rotterdam`. Same for gateway-b with `handling-quarkus`.

**Figures (5)**
- `20-subgraph-ownership`: the canonical types laid out in two columns (cargo, handling), entities marked with their keys, references dashed, shared types in the middle.
- `20-composition-pipeline` (data movement): four subgraphs → `_service.sdl` → composer → `supergraph-a/b.graphql` → two gateways; a red exit with the fixture's error code.
- `20-query-plan` (data movement): `TRACK_FED` split into three fetches with the subgraph request counts and the batched location call from the run.
- `20-entity-reference-fetch` (data movement): a handling event's `location { unLocode }` reference → representation `{__typename: "Location", unLocode: "DEHAM"}` → `_entities` on cargo → `@Resolver` / `resolve_reference` → one bulk source call.
- `20-cross-stack-topology`: gateway-a and gateway-b cross-wired over the four subgraphs, with ports.

**Citations.** Apollo Federation 2 subgraph specification (`_service`, `_entities`, `@key`, `@shareable`, `@external`, `@requires`; the spec text is MIT-licensed documentation; cite by section name); The Guild's federation-composition and Hive Gateway docs ("Supergraph", "OpenTelemetry" for trace propagation); Quarkus SmallRye GraphQL "Federation" guide; Strawberry "Federation" guide; Lyon only by a verified title (**spike**).

### Ch21: Real-time: subscriptions vs SSE vs WebSockets

**Files:** `_docs/21-real-time-subscriptions-sse-websockets.md`, `examples/21-real-time/` (from Ch13).

**Learning goals.** By the end of the chapter the reader can:
- explain a subscription: one document, a stream of results, each event executing the selection set (Ch1:161, Ch2:57);
- trace the event path from the handling store's append to a subscriber's frame;
- serve `cargoHandled` over WebSocket with `graphql-transport-ws` on both stacks, and over GraphQL-over-SSE on Strawberry;
- serve a plain SSE event feed (not GraphQL) with `Last-Event-ID` resume, and say what it gives up (selection) and gains (HTTP semantics, resume, proxies);
- choose between a GraphQL subscription, SSE and a raw WebSocket protocol;
- account for per-subscription cost, cleanup and backpressure;
- know where the series goes deeper (the forthcoming WebSockets book).

**H2 outline**
1. *Asking once, hearing many times.* The `cargoHandled` contract; the payload is a selection like any other, and each event runs it (resolver and source calls per event).
2. *The event path.* `registerHandlingEvent` → store append (after idempotency) → broadcast → per-subscription filter by `trackingId` → execute selection → encode for the transport (Figure 21.2). In process here; a broker (Kafka, S11) in production.
3. *Subscriptions over WebSocket.* `graphql-transport-ws`: `connection_init`/`connection_ack`, `subscribe`, `next`, `complete`, `ping`/`pong` (Figure 21.3, frames from the run). SmallRye: `@Subscription` returning `Multi`, published through a Mutiny `BroadcastProcessor`; Strawberry: an `async` generator fed by an `asyncio.Queue` per subscriber. The legacy `graphql-ws` subprotocol both stacks also accept.
4. *GraphQL over SSE.* The `graphql-sse` distinct-connections mode: a POST with `Accept: text/event-stream`, `event: next` / `event: complete`. Strawberry serves it from `subscription_protocols`; the Quarkus stack serves subscriptions over WebSocket.
5. *Plain SSE: an event feed, not a query.* `GET /events/cargos/{trackingId}` on both stacks (Quarkus REST `Multi` + `SERVER_SENT_EVENTS`; FastAPI `EventSourceResponse`): fixed payload, `id:` per event, `Last-Event-ID` replay after reconnect (Figure 21.4). What a GraphQL subscription does not give: resume.
6. *Raw WebSockets.* A bidirectional channel with your own message protocol: when it wins (chat, collaborative editing, high-frequency bidirectional), and what you must then design (framing, acks, auth, resume). Prose only; the forthcoming WebSockets book in this series covers it in depth.
7. *Comparing the three* (Figure 21.1): direction, framing, selection, HTTP caching/proxies, resume, browser support, auth (headers vs `connection_init` payload; Ch18), load balancers and timeouts.
8. *The cost of a subscription.* One execution per event per subscriber; Ch13's loaders per event; bounded queues and what happens when a subscriber is slow; cleanup on `complete` and on disconnect (asserted).
9. *Ordering and delivery.* In-order per cargo here, at-most-once to a connected subscriber, nothing for a disconnected one (the SSE feed's replay is the exception).
10. On the wire / Decision / next (Ch22's clients; the WebSockets book).

**Example design**
- **Store and broadcast**
  - Quarkus `HandlingStore` gains `Multi<HandlingRecord> appended()` backed by a `BroadcastProcessor<HandlingRecord>`; `append` emits after the record is stored (never for an idempotent replay). `HandlingApi` adds `@Subscription @Description(<canonical>) public Multi<HandlingEvent> cargoHandled(@NonNull TrackingId trackingId)` filtering by tracking id and mapping to the GraphQL type; `HandlingEvent` field resolvers (`cargo`, `location`, `voyage`) are the existing ones.
  - Python `HandlingStore` gains `subscribe(tracking_id) -> AsyncIterator[HandlingRecord]`: an `asyncio.Queue(maxsize=100)` registered per subscriber, removed in `finally`; `append` puts after storing. Schema adds `@strawberry.type class Subscription` with `@strawberry.subscription async def cargo_handled(self, info, tracking_id: TrackingId) -> AsyncGenerator[HandlingEvent, None]`.
  - `GraphQLRouter(…, subscription_protocols=(GRAPHQL_TRANSPORT_WS_PROTOCOL, GRAPHQL_WS_PROTOCOL, GRAPHQL_SSE_PROTOCOL))`.
  - **Spikes:** **D3-a** per-event execution on SmallRye resolves `@Source` fields (Ch13's batching applies per event); **D3-b** each event gets its own request id in the source-call log on both stacks (per-event context); **D3-c** a full queue on Python: the plan is to drop the subscriber with an error frame, **spike** what Strawberry sends and assert it; on Quarkus, `BroadcastProcessor` backpressure behaviour, recorded in the README.
- **Plain SSE feed** (`/events/cargos/{trackingId}`, both stacks): each event `id: <evt id>`, `event: handled`, `data: {"id","trackingId","type","location","completionTime"}`. With `Last-Event-ID: <id>`, first replay the stored events for that cargo after that id (in store order), then live, without duplicates (subscribe to live before reading the replay; drop ids already sent). Quarkus: `@GET @Produces(MediaType.SERVER_SENT_EVENTS) @RestStreamElementType(MediaType.APPLICATION_JSON) Multi<OutboundSseEvent>` built with `Sse` (**spike** D3-d: the idiomatic way to set `id`/`event` per element in Quarkus REST). Python: `response_class=EventSourceResponse`, yielding `ServerSentEvent(id=…, event="handled", data=…)`.
- **Debug (lab only, `TRACKING_DEBUG_ENDPOINTS`)**: `GET /debug/subscribers` → `{"graphql": {"ABC123": 1}, "sse": {"ABC123": 0}}` (counts of live subscriptions per tracking id). Quarkus counts via `onSubscription`/`onTermination` on the filtered `Multi`; Python via the store's registry.
- **Test client** `examples/21-real-time/client/`: `pyproject.toml` (`gql[websockets]==4.4.0`), `uv.lock`, `Containerfile` (UBI python-314-minimal, uv), `subscribe.py`. Usage: `subscribe.py --url ws://quarkus:8080/graphql --subprotocol graphql-transport-ws|graphql-ws --tracking-id ABC123 --count 2 --timeout 30 [--query FILE]`. It prints one JSON line per `next` payload, `{"error": …}` for an error, and `{"complete": true}`; exit 0 on `count` events, 2 on timeout. It uses gql's `WebsocketsTransport` with the requested subprotocol; it holds no protocol code of its own. compose service `client` has `profiles: ["client"]` and is run with `compose_run`.

**Queries:** `SUB` = `subscription Watch($id: TrackingId!) { cargoHandled(trackingId: $id) { id type location { name } cargo { trackingId delivery { transportStatus } } } }`.

**verify.sh assertions (both stacks unless marked).** The client runs in the background (`compose_run client … > "$SCRATCH/<stack>.out" &`); `wait_for_json <base>/debug/subscribers '.graphql.ABC123' 1 30` gates every mutation.
1. Schema: `assert_sdl_equals` on both stacks (the whole canonical SDL, `Subscription` included; if framework noise remains, fall back to `assert_sdl_conforms` plus a `__schema { subscriptionType { name } }` check and record why).
2. WebSocket subscription (`graphql-transport-ws`): subscribe ABC123 with `--count 2`; register `REG_A1`, then `REG_D1` (DEF456), then `REG_A2`. The client prints exactly two events, `evt_10` then the `REG_A2` id, in that order, with `location.name` `Hamburg` and `transportStatus` `IN_PORT` then `ONBOARD_CARRIER`; DEF456's event never appears.
3. Per-event execution: the source-call log after case 2 holds the subscription's per-event calls (`location.*` and `booking.*`) under one request id per event (D3-b).
4. Cleanup: after the client exits, `/debug/subscribers` `.graphql.ABC123` returns to 0 within 5 s. A client killed mid-stream (`--count 5`, killed after the first event) also returns the count to 0 within 5 s.
5. Legacy subprotocol: the same subscription with `--subprotocol graphql-ws` receives one event.
6. Validation error: a subscription selecting `cargoHandled { weight }` gives an `error` frame (client prints `{"error": …}` containing `weight`) and no subscriber is registered.
7. GraphQL over SSE (**Python only**): `sse_collect http://localhost:8311/graphql 20 1 -X POST -H 'Content-Type: application/json' -H 'Accept: text/event-stream' --data <SUB body>` in the background, gated on `/debug/subscribers`, then one ABC123 registration → exactly one `event: next` whose `data.data.cargoHandled.id` is the new event id. The response headers carry `Content-Type: text/event-stream`. On Quarkus the README records, neutrally, that subscriptions are served over WebSocket; no SSE case runs against `/graphql` there.
8. Plain SSE feed (both): `sse_collect …/events/cargos/ABC123 20 1` receives one `handled` event with `id:` equal to the new event id; then with `-H 'Last-Event-ID: evt_10'` (after `REG_A2` and one more ABC123 registration) the feed replays the events after `evt_10` in order before any live event, with no duplicate ids.
9. Mutations still answer over HTTP as in Ch13 (payload `evt_*`, `userErrors` empty).
10. Deprecation check, scalar checks (`assert_sdl_equals` already ran).

**Figures (4)**
- `21-three-ways-to-push`: a comparison grid (GraphQL subscription over WebSocket, GraphQL over SSE, plain SSE feed, raw WebSocket) by direction, framing, selection, resume, HTTP intermediaries, auth.
- `21-event-path` (data movement): mutation → store append → broadcast → filter by tracking id → per-event execution (resolver and source calls) → `next` frame / SSE event, two subscribers, one filtered out. Docstring names the run.
- `21-transport-ws-sequence` (data movement): client/server sequence with the frames captured in case 2 (`connection_init`, `connection_ack`, `subscribe`, `next` ×2, `complete`).
- `21-sse-resume` (data movement): a feed delivering `evt_10`, a drop, a reconnect with `Last-Event-ID: evt_10`, replay of the later events, then live.

**Citations.** The GraphQL specification "Subscription" (CreateSourceEventStream, MapSourceToResponseEvent); the `graphql-transport-ws` protocol document (graphql-ws repository, `PROTOCOL.md`); the `graphql-sse` protocol document; WHATWG HTML "Server-sent events" (`Last-Event-ID`, reconnection); RFC 6455 (WebSocket) and RFC 8441 if HTTP/2 is mentioned; Quarkus SmallRye GraphQL guide (subscriptions) and Quarkus REST (SSE); Strawberry "Subscriptions" and "Server-Sent Events" docs; FastAPI SSE docs; Lyon only by verified title (**spike**).

### Ch22: Client integration

**Files:** `_docs/22-client-integration.md`, `examples/22-client-integration/` (from Ch13).

**Learning goals.** By the end of the chapter the reader can:
- state what a GraphQL client adds over `curl`: documents, typed results, errors, a cache, transport;
- run a normalized cache (Ch16:19/30): entities by `__typename` + `id`, a query answered from the cache, a mutation payload refreshing what another query shows;
- generate types from the canonical SDL and fail the build on a document that no longer matches it;
- use the idiomatic typed client on each stack: SmallRye typesafe and dynamic clients on Java, `gql` on Python, Apollo Client with GraphQL Code Generator in TypeScript;
- handle partial results in a typed client (`ErrorOr` on SmallRye, `errors` beside `data` elsewhere);
- connect the client to the earlier chapters: persisted documents from codegen (Ch15), `X-Client-Name` for Ch19's telemetry, subscriptions (Ch21).

**H2 outline**
1. *What a client is for.* The three clients and what each brings (Figure 22.3).
2. *The normalized cache.* `Cargo:cargo_ABC123`; a second query answered with zero requests; the mutation payload updating the cached cargo; why the server returns the changed object (Ch8, Ch16) (Figure 22.1).
3. *Types from the contract.* GraphQL Code Generator's client preset reads `contracts/schema/` and the documents, emits `TypedDocumentNode`s; `tsc` checks the use; a document selecting a field the contract lacks fails codegen (Figure 22.2). The persisted-document manifest the preset can emit (Ch15).
4. *Python: `gql`.* A `Client` built with the canonical SDL validates documents before they are sent; `gql.dsl` builds documents from the schema; httpx transport.
5. *Java: SmallRye typesafe and dynamic clients.* An interface annotated `@GraphQLClientApi` whose return types define the selection; `ErrorOr<T>` for a field that may fail; the dynamic client's document builder for shapes decided at run time.
6. *Errors in a client.* Ch9's codes as data the client branches on; partial data kept.
7. *Identifying the client.* `X-Client-Name` on every request (Ch19), the version, and why the operation name matters.
8. *Subscriptions from a client.* Apollo's `graphql-ws` link and gql's WebSocket transport (Ch21); prose only here.
9. On the wire / Decision / next (testing, Ch23).

**Example design**
- **Server:** Ch13's two stacks unchanged apart from names and ports (no new server code).
- **JS client** `clients/js/`: `package.json` (pins above; scripts `codegen`, `typecheck`, `start`), `package-lock.json`, `codegen.ts` (`schema: "/schema/**/*.graphql"`, `documents: "src/**/*.graphql"`, preset `client`), `src/operations.graphql` (`TrackCargo`, `TrackCargoBrief` = a subset of `TrackCargo`'s selection on the same root field and arguments, `RegisterHandling`), `src/main.ts`. `Containerfile`: build stage `ubi10/nodejs-24` with `npm ci`, `COPY --from=schema` (compose `build.additional_contexts: schema: ../../contracts/schema`), `npm run codegen`, `npm run typecheck`; runtime `ubi10/nodejs-24-minimal` running `node src/main.ts` (Node 24 type stripping; **spike** D4-a, fallback: compile with `tsc` to `dist/` in the build stage). `main.ts <url>` creates `new ApolloClient({ link: new HttpLink({ uri, fetch: countingFetch, headers: { "X-Client-Name": "ch22-js" } }), cache: new InMemoryCache() })`, then:
  1. `query(TrackCargo, {id: "ABC123"})` → prints `{"step": "track", "status": …, "fetches": 1}`;
  2. `query(TrackCargoBrief, {id: "ABC123"})` with the default `cache-first` → `{"step": "brief", "fetches": 1}` (no new request);
  3. `cache.extract()` holds exactly one `Cargo:` entry for ABC123 and `Location:` entries keyed by `id` → `{"step": "normalized", "cargoKeys": ["Cargo:cargo_ABC123"], …}`;
  4. `mutate(RegisterHandling, REG_A1)` whose payload selects `cargo { id delivery { transportStatus } }` → then `readQuery(TrackCargo)` (cache only) shows `IN_PORT` → `{"step": "after-mutation", "status": "IN_PORT", "fetches": 2}`.
  `countingFetch` wraps the global `fetch`; HttpLink's `fetch` option is the documented seam.
- **Python client** `clients/python/`: `pyproject.toml` (`gql[httpx]==4.4.0`), `uv.lock`, `Containerfile` (UBI python-314-minimal, uv; the schema via `additional_contexts`), `track.py <url>`: `Client(transport=HTTPXAsyncTransport(url=…, headers={"X-Client-Name": "ch22-python"}), schema=<canonical SDL text>)`; prints `TrackCargo` data, a `gql.dsl`-built `location(unLocode: "NLRTM") { name }`, and for a document selecting `Cargo.weight` prints `{"step": "local-validation", "error": …}` without sending anything.
- **Java client** `clients/java/`: a Quarkus command-mode app (`quarkus-smallrye-graphql-client`), `@GraphQLClientApi(configKey = "tracking") interface TrackingClient` with `@Query Cargo cargo(@NonNull @Name("trackingId") String trackingId)`, a `CargoPage` record whose edge node is `ErrorOr<CargoSummary>` (for GHI345), and `@Mutation RegisterHandlingEventPayload registerHandlingEvent(@Name("input") RegisterInput input)`; a `DynamicGraphQLClient` call building `location(unLocode: "NLRTM") { name }` with the `Document`/`Operation`/`Field` DSL. `quarkus.smallrye-graphql-client.tracking.url=${TRACKING_URL}` and header `X-Client-Name: ch22-java` via `quarkus.smallrye-graphql-client.tracking.header."X-Client-Name"`. Prints JSON lines. **Spikes:** **D4-b** the typesafe client's generated document for `CargoPage` and how `ErrorOr` reports the GHI345 edge error; **D4-c** the dynamic client DSL imports at 2.18.5.
- compose: `quarkus`, `python` servers; `js-client`, `python-client`, `java-client` with `profiles: ["client"]`, each run per server URL with `compose_run`.

**verify.sh assertions.** Each client runs against `http://quarkus:8080/graphql` and then `http://python:8080/graphql` (service names on the compose network). `compose_up` restarts nothing between clients, so the order is: JS (mutates ABC123) against Quarkus, JS against Python, then Python and Java clients (read-only plus their own registration on a different cargo where stated).
1. Codegen gate (once): `compose_run js-client npm run codegen -- --config codegen.fail.ts` with a fixture document selecting `Cargo.weight` exits non-zero and prints `Cannot query field "weight" on type "Cargo"` (exact text **spike**); the image build already proved the real documents generate and type-check.
2. JS normalized cache, per server: steps 1–4 above with exact values (`fetches` 1, 1, 2; `IN_PORT`); the server's source-call log between step 1 and step 4 shows **no** calls from step 2 (reset after step 1; `assert_source_call_count calls '*' '*' 0` before the mutation); after step 4 exactly one `handling.appendEvent`.
3. Python `gql`, per server: `TrackCargo` gives the Ch13 values; the DSL query gives `Rotterdam`; the `weight` document is refused locally and the server's source-call log stays empty for it.
4. Java typesafe, per server: `cargo(ABC123)` prints the seed `trackingId`/`description`; `CargoPage` for `cargos(first: 10)` prints 6 edges with one error entry at the GHI345 edge (Python: 1 error; Quarkus: per Ch13's batch behaviour, assert the observed count) and the other nodes present; dynamic `location` gives `Rotterdam`.
5. Client identification is configured in each client (`X-Client-Name`) and taught in prose with a pointer to Ch19, where it is asserted; the Ch22 servers stay unchanged, so nothing is asserted server-side here.
6. Deprecation check, scalar checks, `assert_sdl_conforms` on both servers.

**Figures (3)**
- `22-normalized-cache-update` (data movement): the `TrackCargo` response flattened into `ROOT_QUERY`, `Cargo:cargo_ABC123` and `Location:loc_*`; `TrackCargoBrief` answered from the cache (0 requests); the mutation payload merging `delivery.transportStatus: IN_PORT` into the same entry. Values from case 2.
- `22-codegen-loop` (data movement): `contracts/schema/` + `operations.graphql` → codegen → `TypedDocumentNode`s → `tsc` → the client; a red exit for the `weight` fixture.
- `22-client-landscape`: three columns (SmallRye typesafe/dynamic, `gql`, Apollo Client): how the document is written, typing, schema validation, cache, subscriptions, partial results.

**Citations.** Apollo Client docs ("Caching in Apollo Client", "Configuring the cache", `HttpLink`); GraphQL Code Generator "client preset" docs; gql docs ("Schema validation", "DSL module", transports); Quarkus "SmallRye GraphQL Client" guide (typesafe, dynamic, `ErrorOr`); the GraphQL-over-HTTP draft for client requests; *GraphQL in Action* if its client chapter title is verified (**spike**); Lyon's client chapter by verified title (**spike**; "Client-side GraphQL with React and Apollo Client" is the expected title).

---

## 3. Harness additions (`examples/_lib/lib.sh`, D0)

Every change is backward compatible, `bash -n` and shellcheck clean, stdlib `python3 -I` only, and documented in `examples/_lib/README.md`'s table. Existing callers behave identically when the new variables are unset.

| Function / variable | Contract |
|---|---|
| `LGTM_TRACEPARENT` (env) | When set, `_lib_curl_opts` adds `-H "traceparent: $LGTM_TRACEPARENT"`, so every GraphQL and HTTP helper sends it (Ch19). |
| `LGTM_HEADERS` (env) | Newline-separated `Name: value` lines; each becomes `-H`. Used for `X-Client-Name` (Ch19). |
| `new_trace_id` | 32 lowercase hex characters (`secrets.token_hex(16)`). |
| `traceparent_for <trace-id>` | `00-<trace-id>-<16 hex>-01`. |
| `tempo_trace <tempo-base> <trace-id> [timeout] [min-spans]` | Polls `GET <base>/api/traces/<id>` (and `/api/v2/traces/<id>` when the first answers 404; **spike** D0-a for the shape on Tempo in otel-lgtm 0.36.0) until at least `min-spans` spans exist; prints a normalized document `{"spans":[{"name","spanId","parentSpanId","service","kind","status","attributes":{…}}]}` with ids in hex. FAIL after timeout (default 60). |
| `assert_span <trace> <name-regex> [min] [max] [ctx]` | Count of spans whose name matches is within [min, max] (defaults 1, unbounded). |
| `assert_span_attr <trace> <name-regex> <attr> <expected> [ctx]` / `assert_span_attr_absent <trace> <attr-regex> [ctx]` | Some matching span has the attribute value / no span has an attribute whose key matches. |
| `assert_span_descends <trace> <child-regex> <ancestor-regex> [ctx]` | Every span matching the child regex has an ancestor matching the other. |
| `assert_span_status <trace> <name-regex> <OK|ERROR|UNSET> [ctx]` | Some matching span has that status. |
| `assert_attr_not_contains <trace> <name-regex> <attr> <needle> [ctx]` | The attribute of every matching span does not contain the needle. |
| `prom_query <prom-base> <promql>` | Prints the `data.result` JSON of `GET /api/v1/query`. |
| `wait_for_metric <prom-base> <promql> <min> [timeout]` | Polls until the first sample's value ≥ min (default timeout 120). |
| `assert_metric_eq <prom-base> <promql> <value> [ctx]` | The first sample's value equals the number. |
| `loki_wait <loki-base> <logql> [timeout] [min-lines]` | Polls `GET /loki/api/v1/query_range` until enough lines; prints them. |
| `compose_run <service> [args...]` | `docker compose -p <project> -f <file> run --rm -T --build <service> args…` for the stack `compose_up` started; FAIL when none is up. Profiled services are run explicitly, so `compose_up` stays unchanged. |
| `wait_for_json <url> <dot.path> <expected> [timeout]` | Polls a GET until the JSON value at the path equals the expectation (Ch21 subscriber counts). |
| `sse_collect <url> <max-secs> <max-events> [curl-args...]` | `curl -sN --max-time` the stream; prints one JSON line per event `{"event","id","data"}` (comments skipped); stops after `max-events`. Non-zero only on transport failure. |
| `assert_request_count <calls-json> <n> [ctx]` | The number of distinct non-empty request ids in a source-call log equals n (Ch20). |

**D0 also:** sets `timeout-minutes: 60` on the `examples` job in `.github/workflows/contracts.yml` (nothing else in that file).

**D0 self-test:** `bash -n`; shellcheck; Ch0, Ch13 and Ch18 `verify.sh` green; `traceparent_for "$(new_trace_id)"` matches `^00-[0-9a-f]{32}-[0-9a-f]{16}-01$`; the trace normalizer and span assertions run against two saved Tempo responses (v1 and v2 shape, obtained from a scratch run of `grafana/otel-lgtm:0.36.0` with one OTLP span sent by a stdlib-free means: the Ch0 example's observability profile plus one `curl`), kept in the scratch dir, not committed; `sse_collect` parsing tested on a saved `text/event-stream` body through a `file://` URL (curl reads it like a stream); its live behaviour is proven by D3's run.

---

## 4. Acceptance criteria

**Per chapter (Ch19–Ch22)**
- `_docs/NN-*.md` with valid front matter (`part:` resolves, `order` = N); `bash scripts/wordcount.sh` reports 2,800–3,400.
- Budgeted figures (19:4, 20:5, 21:4, 22:3 = 16): each at `assets/diagrams/NN-slug.{svg,excalidraw}` with a spec `diagrams/NN-slug.py` that regenerates byte-identically, embedded with full-sentence alt text and a `Figure N.M — …` caption numbered by appearance, rendered to PNG and viewed by the executor and by DVn.
- `## On the wire` matches `verify.sh`, then the Decision callout naming Ch2's axes, then `## Where this goes next`; at least one codetabs pair.
- `examples/NN-slug/` has README (Ch13's sections plus Code-first notes), `compose.yaml` (fixed `name:`, pinned images only), executable `verify.sh`, `.gitignore`, `architecture.svg` + `.excalidraw`, `quarkus/` and `python/` (Ch20: their four sub-projects) with re-generated `uv.lock`; Node projects have a committed `package-lock.json` and use `npm ci`.
- `verify.sh` prints `PASS`; every §2 assertion present for both stacks (or per stack where §2 says so); only the harness, stdlib and the example's own containers.
- No planning language: `grep -rniE 'wave [a-z0-9]|\bS[0-9]{1,2}\b|\b[D][0-9]\b|\br0[0-9]\b|iteration|capstone|coverage matrix|phase [0-9]|TODO|TBD|spike' _docs/19-* _docs/2[0-2]-* examples/19-*/README.md examples/2[0-2]-*/README.md` returns nothing.
- Content rule: DVn reads every reader-facing line for rule-13/14 hits (framework defects, issue numbers, workaround narratives, weakness descriptions); 0 allowed. `lgtm-professional-voice`: 0 ban-tier findings. `lgtm-idiomatic-review`: 0 unresolved substantive findings; the only hand-written framework-adjacent pieces are the two telemetry hooks (Ch19), the composer script (Ch20) and the store broadcast/queue (Ch21), each with a comment saying what framework seam it uses.

**Chapter-specific**
- Ch19: a trace per request joined to the caller's trace id on both stacks; resolver spans descend from the operation span; one batched `source.call` under many location resolvers; span metrics, `graphql.errors` and deprecated-usage metrics present in Prometheus with the asserted values; the FAULT log record found in Loki by trace id.
- Ch20: composition succeeds for both cross-wired pairs and fails with the expected codes for both fixtures; direct `_entities` on all four subgraphs; the query-plan request counts (cargo 2, handling 1) through both gateways; both gateways' API schemas conform to the canonical slice.
- Ch21: `assert_sdl_equals` (or the recorded fallback) on both stacks; two in-order events and no foreign event over `graphql-transport-ws` on both; cleanup to 0 after complete and after kill; graphql-sse on Python; plain SSE resume with no duplicates on both.
- Ch22: codegen fixture fails; JS fetch counts 1, 1, 2 and `IN_PORT` from the cache on both servers with 0 source calls for the cached query; `gql` local validation sends nothing; SmallRye typesafe `ErrorOr` reports the GHI345 edge.

**For the wave**
- `python3 -I scripts/validate.py` exits 0 (checked via `$?`); `GATE=1 bash scripts/wordcount.sh` passes; Jekyll build in the `ruby:3.3` container is clean.
- `npm --prefix contracts run lint` and `run breaking` pass; **the `contracts/` diff is empty**.
- All Ch0, Ch3–Ch22 `verify.sh` run concurrently on one host and pass (port rule; LGTM on Ch19's block).
- On PR #1: `verify: 19-observability` … `verify: 22-client-integration` green, `ci-ok` green.
- Site figure total = 75.
- **Forward references delivered** (DVn checks each against the shipped text): Ch0:295 (Ch19 uses the LGTM stack; DX revisits the profile wording); Ch1:161, :177, :195; Ch2:57, :81, :87, :146, :154; Ch9:173 and :272 (errors by code as a metric); Ch11:93 and :278 (deprecated-field usage by client); Ch12:11 (`Subscription` in Ch21); Ch15:101 (WebSockets in Ch21) and :242 (operation names in Ch19); Ch16:19 and :30 (client normalized cache in Ch22); Ch18:325 (what to record).
- **Deliberate fixes (DW, never as side effects).** If a DV finds a forward statement the shipped chapter does not meet, the validator drafts a one-clause fix and the orchestrator applies it in its own `fix(§N)` commit, re-verified.

---

## 5. Risks and detection

| Risk | Detection / mitigation |
|---|---|
| The OTel graphql-java instrumentation cannot be appended through the `GraphQL.Builder` event, or double-counts operation spans | Ch19 cases 2–3 (exactly one operation span); spike D1-b/c. Fallback, with orchestrator sign-off only: `@WithSpan` on the `@GraphQLApi` resolver methods plus SmallRye's operation span. |
| Async/batched resolver spans end before the value (wrong durations) or never | Case 3–4 spans descend and the batched `source.call` lies inside its resolver spans; spike D1-b/f. |
| Span metrics or OTLP metrics arrive too late in CI | `wait_for_metric` up to 120 s, 5 s export interval, 1 s span batch delay; CI retries 3×. |
| Prometheus metric and label names differ from the plan after OTLP translation | Spike D1-e; assert the observed names and record them in the README. |
| Loki structured-metadata query form differs | Spike D1-g; if trace-id lookup is not queryable, report before changing the assertion. |
| Composition rejects `Node` split across subgraphs | Spike D2-a; stop and report (alternatives need a plan change: Node only in cargo with `HandlingEvent` not implementing it is not acceptable because it changes the API schema). |
| SmallRye and Strawberry subgraphs compose at different federation versions | Both pinned to 2.7 (D2-c). |
| Gateway API schema carries extra directives or types | Case 7 records them in a local `LGTM_SDL_FRAMEWORK_DIRECTIVES` override, named one by one; never a broad filter. |
| Query-plan counts depend on the gateway's planner version | Pinned gateway; counts asserted from the run and drawn in Figure 20.3 from the same run. |
| Race between subscribing and the first mutation | `/debug/subscribers` gate before every mutation (Ch21). |
| Leaked subscriptions after disconnect | Ch21 case 4 (complete and kill). |
| Slow subscriber fills memory | Bounded queue (Python), backpressure recorded (Quarkus), prose on drop policy (D3-c). |
| SSE resume duplicates or loses events at the replay/live seam | Ch21 case 8 asserts order and no duplicates; subscribe-before-replay design. |
| Node 24 type stripping cannot run the generated client | Spike D4-a; compile in the build stage instead. |
| TypeScript 7.0.2 and the client preset disagree | Spike in D4's build; newest 6.x only with orchestrator sign-off; record. |
| Client order in Ch22 makes later cases depend on earlier mutations | Fixed order in §2; the JS mutation is the only write to ABC123; Python and Java read the post-write state and assert it. |
| A reader-facing line describes a framework defect | Content rule; DVn's line-by-line read; S12b sweep re-runs rule 13. |
| CI time grows past the job limit | `timeout-minutes: 60` (D0); per-example estimates in §1; Maven layer caching as in Ch13 Containerfiles. |
| Port collisions with a reader's LGTM | Ch19 publishes LGTM on 8292–8295 only. |
| Untested prose (raw WebSocket protocol, `@requires`, `@interfaceObject`, persisted-document manifest from codegen, Apollo subscriptions) | Prose only, no code; DV flags any snippet the example does not run. |

---

## 6. Coverage-matrix and plan updates (orchestrator only)

1. **At each chapter checkpoint** (same commit): T20 Ch19, T21 Ch20, T22 Ch21, T23 Ch22 to `draft` in the Topics table and the Full chapter inventory. Run `python3 -I scripts/validate.py; echo $?` and `GATE=1 bash scripts/wordcount.sh`. Push.
2. **Verified:** after DVn passes **and** CI `verify: NN-*` is green.
3. Diagram budget table unchanged (19:4, 20:5, 21:4, 22:3). Record the Wave D count (16; site total 75) in the RESUME POINTER.
4. `_example_pages/index.md`, rows 19–22:
   - **19**: OpenTelemetry on both stacks: a trace per request with a span per resolver and per source call, errors by code and deprecated-field usage as metrics, span metrics, logs found by trace id.
   - **20**: Two subgraphs per stack composed into one supergraph with an explicit composition gate, entity resolution, a query plan counted across subgraphs, Hive Gateway cross-wired over both stacks.
   - **21**: `cargoHandled` over `graphql-transport-ws` on both stacks, GraphQL over SSE on Python, a plain SSE feed with `Last-Event-ID` resume, subscription cleanup asserted.
   - **22**: Apollo Client's normalized cache, GraphQL Code Generator against the canonical SDL, `gql` with local validation, SmallRye typesafe and dynamic clients, all run against both servers.
5. `_plans/domain-glossary.md`: add **Subgraph**, **Supergraph**, **Entity** (federation), **Composition**, **Span** (per resolver), **Normalized cache**; extend **Subscription** ("served over `graphql-transport-ws`; Ch21 compares SSE").
6. RESUME POINTER: S9 done with date and spike findings (instrumentation approach, span names per stack, metric names, Loki query form, composition codes, query-plan counts, subscription per-event context, SSE seam, Node type stripping); DX status; any versions to bump in DX (otel-lgtm 0.37.0, fastapi 0.143.3, newer UBI tags); `iteration-plan.md` S9 → done.
7. Commits on `r01`, one checkpoint per step: `chore(r01.x): Wave D harness additions (tracing, metrics, SSE, compose run helpers)` for D0; `docs(§N): …` per chapter; `fix(§N): …` for repair rounds; `docs(r01): Wave D verified`; `chore(examples): OTLP off unless the observability stack runs` for DX. Push after each and watch CI.
8. Append **§9 "Wave D findings"** at DW, engineering notes only, in the neutral form of Wave C's §9 (no defect narratives; anything that reads as a defect goes to the user outside the repository).

---

## 7. Binding pitfalls carried forward (every Wave D executor)

**From Waves A–C (still binding):** Wave A §7 items 1–10 and the Ch6/Ch7 handoffs; Wave B §9 (masking allowlist and `DeclaredErrorCodeProvider`; per-field SmallRye batching and blast radius; one `__Type.fields` per request; whole-second times; `ensure_contracts_tools`; `compose_up` runs `down -v`; `validate.py` exit code checked directly); Wave C §7 C-1…C-10 and §9 (reader-facing text is a tutorial; test code shows behaviour, not recipes; `status_of` without a pipe; no `producer | head` under `pipefail`).

**New in Wave D (binding):**
- **D-1.** Every telemetry assertion reads the trace by the trace id the script sent (`LGTM_TRACEPARENT`), never "the latest trace".
- **D-2.** Span and metric names differ per stack where the instrumentation names them; assert per stack from the spike tables and describe the difference neutrally.
- **D-3.** No variable value, token or owner list in a span attribute or metric label; operation name and field coordinate are the labels.
- **D-4.** Federation directives live only in subgraph schemas and the Ch20 fixtures, never in `contracts/`.
- **D-5.** Subgraph descriptions are copied verbatim from the canonical SDL, so the composed API schema conforms.
- **D-6.** Every Ch21 mutation is gated on `/debug/subscribers`; every subscription test ends with the count back at 0.
- **D-7.** Client images get the canonical schema through `build.additional_contexts`, never by copying `contracts/` into the example.
- **D-8.** Profiled helper services (`client`, `composer` re-runs, `*-client`) run through `compose_run`; `compose_up` is not changed.
- **D-9.** Node projects install with `npm ci` from a committed lockfile; no `npx` of unpinned packages.

---

## 8. Open decisions needing user input (each with a recommendation)

1. **Federation gateway and composer (Ch20).**
   - (a) **Hive Gateway 2.15.2 + `@theguild/federation-composition` 0.27.0** (both MIT, The Guild, the same maintainers as the graphql-inspector the site already uses), built on UBI Node 24, composition as an explicit one-shot step writing a supergraph file.
   - (b) Cosmo Router 0.359.0 + `wgc router compose` 0.133.0 (Apache-2.0; Go router, needs its own execution-config step).
   - (c) Hive Gateway's dev composition mode (documented for local development).
   Apollo Router and Apollo's composition are excluded (Elastic License 2.0). **Recommend (a).**
2. **Federation topology (Ch20).** (a) **two cross-wired gateways** (cargo-Quarkus + handling-Python; cargo-Python + handling-Quarkus), proving the subgraph contract is stack-neutral; (b) one all-Quarkus and one all-Python supergraph. Both need four subgraph services. **Recommend (a).**
3. **Subscription transports (Ch21).** **Recommend:** `graphql-transport-ws` on both stacks (asserted; legacy `graphql-ws` asserted once); GraphQL over SSE (`graphql-sse`) on Strawberry, where it is built in; a plain SSE feed with `Last-Event-ID` resume on both stacks; raw WebSockets in prose with the pointer to the forthcoming WebSockets book. Alternative: drop the plain SSE feed and compare only GraphQL transports (shorter, but loses the resume lesson the chapter title promises).
4. **Subscription test client (Ch21).** (a) **a small Python script on `gql[websockets]` 4.4.0** in a pinned UBI container on the compose network; (b) a pinned `websocat` binary with the protocol frames scripted in bash. **Recommend (a)**: the client library speaks both subprotocols; no protocol code in the repository.
5. **JS client (Ch22).** (a) **Apollo Client 4.3.4** (MIT; normalized `InMemoryCache` built in; widest use; released 2026-10-16, so the executor confirms no 4.3.5 fix release before pinning); (b) urql 5.0.4 + `@urql/exchange-graphcache` 9.0.2 (MIT; the normalized cache is an add-on exchange). **Recommend (a)**, with GraphQL Code Generator's client preset for types.
6. **Browser or headless (Ch22).** (a) **headless Node 24 in UBI** (the cache is a library; fetch counts and `cache.extract()` are machine-checkable); (b) a browser via Playwright (a large non-UBI image, flakier). **Recommend (a).**
7. **Python client (Ch22).** (a) **`gql` 4.4.0** (schema validation against the canonical SDL, DSL builder, async transports, also used in Ch21); (b) `ariadne-codegen` 0.19.0 (BSD-3; generates a typed pydantic client). **Recommend (a)**; name (b) in prose as the codegen route.
8. **Per-resolver spans on Quarkus (Ch19).** (a) **the OpenTelemetry project's `opentelemetry-graphql-java-20.0`**, managed by the Quarkus BOM, installed through the `GraphQL.Builder` event (Ch14's pattern), with SmallRye's own operation span turned off; (b) `@WithSpan` on every `@GraphQLApi` resolver method plus SmallRye's operation span. **Recommend (a)**: automatic per data fetcher, semantic-convention names, no annotation per method.
9. **OTLP when the observability stack is off (Ch0–Ch18, the Wave C chore).** Ch19 runs LGTM as a default service, so it needs no switch. For the other examples:
   - (a) **a compose override file** per example: `compose.yaml` sets `OTEL_SDK_DISABLED=true` and no endpoint; `compose.observability.yaml` adds `lgtm` and sets `OTEL_SDK_DISABLED=false` plus the endpoint (`docker compose -f compose.yaml -f compose.observability.yaml up --build`). Quarkus reads `quarkus.otel.sdk.disabled=${OTEL_SDK_DISABLED:false}` (runtime property); the Python SDK honours `OTEL_SDK_DISABLED` natively. Ch0's observability paragraph is updated as a deliberate fix.
   - (b) keep the profile and add `OTEL_SDK_DISABLED=${OTEL_SDK_DISABLED:-true}` (readers must set two things).
   - (c) leave Ch0–Ch18 as they are.
   **Recommend (a), as step DX after DW** in one `chore(examples)` commit with every `verify.sh` re-run, bumping `grafana/otel-lgtm` to the newest stable in the same commit. Ch19's prose teaches the pattern once.
10. **Canonical SDL additions.** **Recommend none.** `Subscription.cargoHandled` is already canonical; federation directives belong to subgraph schemas inside the Ch20 example; the `contracts/` diff stays empty, so the breaking gate is untouched (an addition would have been safe; none is needed).
11. **Ch22's base.** (a) **Ch13** (parallel with Ch21; subscription clients in prose with a pointer to Ch21); (b) Ch21 (adds an Apollo `graphql-ws` subscription test; serializes the wave). **Recommend (a).**
12. **LGTM ports in Ch19.** (a) **publish on the chapter block** (8292 Grafana, 8293 Tempo, 8294 Prometheus, 8295 Loki); (b) the Ch0 ports (3000, 3200, 9090, 3100). **Recommend (a)**, so Ch19's verify never collides with a reader's own observability profile and can run beside the other examples.

### Critical files for implementation
- `examples/_lib/lib.sh` (D0: trace, metric, log, SSE and `compose_run` helpers)
- `examples/13-dataloaders/` (the base of every Wave D copy: `TrackingApi.java`, `HandlingStore.java`, `SourceCalls.java`, `application.properties`; `python/app/schema.py`, `handling.py`, `sources.py`, `deps.py`, `main.py`; `verify.sh`, `compose.yaml`)
- `examples/14-query-cost/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/QueryCost.java` (the `GraphQL.Builder` observer pattern Ch19 reuses)
- `contracts/schema/shipping/*.graphql` (read-only: the contract the gateway and the clients are checked against)
- `_plans/coverage-matrix.md` and `.github/workflows/contracts.yml`

---

## 9. Wave D findings

Binding on later waves unless noted. Engineering notes only.

- **Telemetry assertions read by the caller's trace id** and exact span counts; a check that a value is absent must look at every span attribute (`assert_no_attr_value` in Ch19), not one attribute.
- **Counters must scope the same on both stacks**: Ch19 counts errors of executed operations only (parse and validation errors excluded on Quarkus too).
- **No fixed sleeps before a "nothing changed" metric check**: use a later metric from the same export as the barrier (Ch19 case 9).
- **An order assertion needs concurrent input**: send the events at once, or the subscriber reads each before the next arrives and nothing queues (Ch21 5b).
- **A hot-source subscription feeding a Mutiny `UnicastProcessor` is cancelled by the caller** (the processor's cancel callback); the subscriber count measures membership in the broadcast so the cleanup case sees it (Ch21).
- **Each subscription event is resolved with fresh DataLoaders** (Quarkus: an instrumentation at `beginSubscribedFieldEvent`; Python: `context.begin_event()`).
- **Frame-list assertions exclude keep-alive `ping`/`pong`.**
- **Federation:** the gateway sends each distinct representation once; a batching assertion needs distinct keys (Ch20 DEF456). Every SDL patch in an observer throws when its target is missing, and verify asserts the served SDL directly — a partner subgraph can mask a missing directive at composition.
- **Docs cited by page title (H1), not sidebar label.**
- **`compose_run` output:** BuildKit progress reaches stdout when it is not a TTY; Ch21 sets `COMPOSE_PROGRESS=quiet` in a local wrapper and Ch22 filters JSON lines. Promote `COMPOSE_PROGRESS=quiet` into `lib.sh` `compose_run` in DX.
- **DX inputs:** `grafana/otel-lgtm:0.36.0` has `curl` but no `wget` (the Ch0/Ch13-era `lgtm` healthchecks use `wget`); OTel duration values are lowercase (`5s`); the Ch0:295 profile sentence is revised with DX.
- **S12b sweep inputs:** the inherited `Node.java` Javadoc wording in Ch13–19, 21, 22 (reworded in Ch20) is restated positively; re-run the rule-13 sweep over Wave D files.
- **CI:** a Maven Central fetch error failed one Quarkus build once (e5710fb); a re-run of the failed jobs passed. Wave D verify jobs: Ch19 ~1.5 min, Ch20 ~1 min, Ch21 ~2.5–3 min, Ch22 ~0.5 min warm.
