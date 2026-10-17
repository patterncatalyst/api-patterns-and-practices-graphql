---
layout: plan
render_with_liquid: false
title: "r01 Execution Plan — api-patterns-and-practices-graphql"
---

# PLAN — api-patterns-and-practices-graphql (series site #3)

**Status: APPROVED by user 2026-10-15. SHIPPED 2026-10-17 as r1.0 (main 9143d56); see RESUME POINTER at the end.**

Third site in the "API Patterns and Practices" series, after REST and gRPC.
Mirrors `~/Dev/api-patterns-and-practices-grpc` (primary template) structurally,
byte-for-byte where possible; REST (`~/Dev/api-patterns-and-practices-rest`) is
the first-in-series reference. Produced via lgtm-relay (Opus plan → Sonnet
execute → Opus validate).

## Locked decisions
- Repo: `patterncatalyst/api-patterns-and-practices-graphql` (public). Jekyll,
  `baseurl: /api-patterns-and-practices-graphql`, pretty permalinks, collections
  `_docs` (`/docs/:name/`), `_parts`, `_plans`, `_example_pages` (`/examples/:name/`).
  Nav: Chapters · Examples · Bibliography · GitHub. Amber house style.
- Length: 13 parts / 28 chapters (Ch0–27) + Appendix A + outline = 30 docs.
- Languages: **Quarkus SmallRye GraphQL + Python Strawberry only** (no .NET).
  uv (matches the REST/gRPC siblings and lgtm-python; user, 2026-10-16 — replaces Poetry), latest-stable LTS, UBI 10.
- Domain: GraphQL as the **tracking view** — a read-oriented aggregation layer
  stitching cargo, route legs, and handling events into one query-shaped graph.
- Diagrams: paired `assets/diagrams/NN-slug.svg` + `.excalidraw` via
  lgtm-diagram-generator (amber), embedded with `{% include excalidraw.html %}`
  (renders `<img>`). Target **89** (band 80–95) — heavier than gRPC (user, 2026-10-16):
  extra figures explain data movement. Specs kept in-repo under `diagrams/`, one per figure
  (user, 2026-10-16); never hand-edit generated SVG. Per-chapter budget: coverage-matrix.md.
- Decks: three via lgtm-presentation — `api-patterns-graphql-100` (concepts) +
  `-quarkus` + `-python`, plus `_shared`.
- Infra: lgtm-docker-stack → lgtm-minikube-stack → lgtm-crc. Load-testing harness.
  Dedicated Testing section AND Debugging section.
- Real-time: exactly ONE chapter (Ch21) — subscriptions vs SSE vs WebSockets,
  with a forward pointer to the planned WebSockets book. NOT a full part.
- Contract: canonical **SDL** in `contracts/schema/` replaces proto; a
  `graphql-inspector` schema-diff/breaking gate replaces `buf breaking`. Both
  stacks are code-first and export SDL diff-checked against the canonical schema.

## Reference books (bibliography — reference works, not sources)
1. *GraphQL in Action* — Samer Buna (Manning) — schema/execution/client; Ch1–9, 22.
2. *GraphQL Best Practices* — Artur Czemiel (Packt) — schema design, security, perf; Ch10, 14–18.
3. *Full Stack GraphQL Applications* — William Lyon (Manning) — end-to-end, client, federation; Ch19–22, 27.
4. *Designing Data-Intensive Applications, 2nd ed.* — Martin Kleppmann & Chris Riccomini —
   data-layer rigor; cite specifically in Ch12 (connections/pagination), Ch13
   (N+1/dataloaders/batching), Ch14 (query cost/perf), Ch16 (caching).
Plus primary docs: graphql.org spec, GraphQL-over-HTTP spec, Relay cursor-connections
spec, SmallRye/Quarkus GraphQL guides, Strawberry docs.

## Canonical outline (13 parts / 28 chapters + Appendix A; 89 diagrams; 27 example dirs)
Ex = carries runnable example. Dg = original diagram estimate (superseded: see coverage-matrix.md Diagram budget, total 89).

| Part | Ch | Title | Ex | Dg |
|---|---|---|---|---|
| 0 Prerequisites & the Lab | 0 | Prerequisites and the lab | ✓ | 2 |
| 1 Why GraphQL & the Decision Lens | 1 | From REST/RPC to GraphQL | | 2 |
| | 2 | The GraphQL decision framework | | 2 |
| 2 The Schema: SDL & Type System | 3 | SDL and the type system in depth | ✓ | 3 |
| | 4 | Nullability and null propagation | ✓ | 2 |
| | 5 | Schema-first / contract-first | ✓ | 2 |
| 3 Execution: Resolvers, Queries & Mutations | 6 | The execution model | ✓ | 3 |
| | 7 | Queries and resolvers | ✓ | 2 |
| | 8 | Mutations and input types | ✓ | 2 |
| 4 Reliability: Errors & Partial Results | 9 | Error handling | ✓ | 3 |
| 5 Schema Evolution & the Living Contract | 10 | Schema design patterns | ✓ | 2 |
| | 11 | Evolution and versioning | ✓ | 2 |
| 6 Data Fetching at Scale | 12 | Connections & pagination | ✓ | 3 |
| | 13 | The N+1 problem and dataloaders | ✓ | 3 |
| 7 Performance & Safety | 14 | Depth limits & query cost analysis | ✓ | 3 |
| | 15 | Persisted queries & APQ | ✓ | 2 |
| | 16 | Caching | ✓ | 3 |
| 8 Security | 17 | Transport security & introspection control | ✓ | 2 |
| | 18 | AuthN & AuthZ | ✓ | 3 |
| 9 Observability & the Gateway | 19 | Observability | ✓ | 3 |
| | 20 | Federation & schema composition | ✓ | 3 |
| 10 Real-time & Client Integration | 21 | Real-time: subscriptions vs SSE vs WebSockets (single ch; → WebSockets book) | ✓ | 3 |
| | 22 | Client integration | ✓ | 2 |
| 11 Testing & Debugging | 23 | Testing GraphQL APIs (+ load-testing harness) | ✓ | 2 |
| | 24 | Debugging GraphQL | ✓ | 2 |
| 12 Running It & the Final Project | 25 | Local with Docker Compose | ✓ | 2 |
| | 26 | Kubernetes on minikube (cluster-tier, no verify.sh) | ✓ | 2 |
| | 27 | The final project | ✓ | 3 |
| (Appendix) | A | OpenShift Local (CRC) (cluster-tier, helm-validated) | ✓ | 3 |

Ch1/Ch2 conceptual (no example). Appendix file: `99-appendix-a-openshift-crc.md`.

## Canonical names (fixed 2026-10-15; S2 and S3 both depend on these)

Parts (`_parts/<file>` → `part_name`, which every chapter's `part:` must equal):

| order | file | part_name |
|---|---|---|
| 0 | `00-prerequisites.md` | Prerequisites & the Lab |
| 1 | `01-why-graphql.md` | Why GraphQL & the Decision Lens |
| 2 | `02-schema-and-type-system.md` | The Schema: SDL & the Type System |
| 3 | `03-execution.md` | Execution: Resolvers, Queries & Mutations |
| 4 | `04-reliability.md` | Reliability: Errors & Partial Results |
| 5 | `05-schema-evolution.md` | Schema Evolution & the Living Contract |
| 6 | `06-data-fetching-at-scale.md` | Data Fetching at Scale |
| 7 | `07-performance-and-safety.md` | Performance & Safety |
| 8 | `08-security.md` | Security |
| 9 | `09-observability-and-gateway.md` | Observability & the Gateway |
| 10 | `10-real-time-and-client.md` | Real-time & Client Integration |
| 11 | `11-testing-and-debugging.md` | Testing & Debugging |
| 12 | `12-running-it-and-final-project.md` | Running It & the Final Project |

Chapters (`_docs/`) → example dir (`examples/`; — = no example):

| Ch | `_docs/` file | `examples/` dir |
|---|---|---|
| — | `00-outline.md` (overview) | — |
| 0 | `00-prerequisites-and-the-lab.md` | `00-prerequisites` |
| 1 | `01-from-rest-and-rpc-to-graphql.md` | — |
| 2 | `02-graphql-decision-framework.md` | — |
| 3 | `03-sdl-and-the-type-system.md` | `03-sdl-type-system` |
| 4 | `04-nullability-and-null-propagation.md` | `04-nullability` |
| 5 | `05-contract-first-schemas.md` | `05-contract-first` |
| 6 | `06-the-execution-model.md` | `06-execution-model` |
| 7 | `07-queries-and-resolvers.md` | `07-queries-resolvers` |
| 8 | `08-mutations-and-input-types.md` | `08-mutations` |
| 9 | `09-error-handling.md` | `09-error-handling` |
| 10 | `10-schema-design-patterns.md` | `10-schema-design` |
| 11 | `11-evolution-and-versioning.md` | `11-evolution` |
| 12 | `12-connections-and-pagination.md` | `12-pagination` |
| 13 | `13-n-plus-one-and-dataloaders.md` | `13-dataloaders` |
| 14 | `14-depth-limits-and-query-cost.md` | `14-query-cost` |
| 15 | `15-persisted-queries-and-apq.md` | `15-persisted-queries` |
| 16 | `16-caching.md` | `16-caching` |
| 17 | `17-transport-security-and-introspection.md` | `17-transport-security` |
| 18 | `18-authn-and-authz.md` | `18-authn-authz` |
| 19 | `19-observability.md` | `19-observability` |
| 20 | `20-federation-and-schema-composition.md` | `20-federation` |
| 21 | `21-real-time-subscriptions-sse-websockets.md` | `21-real-time` |
| 22 | `22-client-integration.md` | `22-client-integration` |
| 23 | `23-testing-graphql-apis.md` | `23-testing` |
| 24 | `24-debugging-graphql.md` | `24-debugging` |
| 25 | `25-local-with-docker-compose.md` | `25-docker-compose` |
| 26 | `26-kubernetes-on-minikube.md` | `26-minikube` (cluster-tier, no verify.sh) |
| 27 | `27-the-final-project.md` | `27-final-project` |
| A | `99-appendix-a-openshift-crc.md` | `99-appendix-a-openshift-crc` (cluster-tier, no verify.sh) |

27 example dirs. Chapter titles are the outline table titles above.

## Conventions to mirror from the gRPC project
- `_config.yml`: kramdown/GFM/rouge, `permalink: pretty`; collections + defaults
  (docs→`tutorial` sectionid docs, plans→`plan`, example_pages→`tutorial`
  sectionid examples, parts→`part_index`); `exclude:` examples/ contracts/
  scripts/ presentation/ Gemfile(.lock) vendor node_modules README LICENSE PRD.
- Front-matter: `_docs` = title, order, part (==a `_parts` part_name), description,
  duration; outline adds `overview: true`. `_parts` = title, order, part_name,
  blurb (body empty). `_plans` = `layout: plan, render_with_liquid: false`.
- Chapter length: `wordcount.sh` GATE floor 2,000 (soft ceiling 2,500); shipped
  gRPC chapters ~2,800–3,730 (avg ~3,100). Target 2,800–3,400/chapter.
- Example dir `examples/NN-slug/`: README.md, compose.yaml, verify.sh (exec,
  `set -euo pipefail`, sources `../_lib/lib.sh`), .gitignore, architecture.svg+
  .excalidraw, `quarkus/` + `python/` subdirs. `examples/_lib/lib.sh` shared.
  Cluster-tier dirs (Ch26, Appendix A) carry NO verify.sh (kustomize `k8s/` /
  `helm/`, static-validated via kubeconform/helm).
- `_includes/`: header (nav), footer, excalidraw.html (now `<img>`), codetabs.html.
- `_layouts/`: default, tutorial, part_index, plan.
- `scripts/`: validate.py (stdlib, `python -I`), wordcount.sh (GATE), generate_diagram.py.
- `_plans/`: coverage-matrix.md (topics→chapter→file→status planned/draft/verified),
  domain-glossary.md, iteration-plan.md, rNN-execution-plan.md.
- CI `.github/workflows/`: pages.yml (build any branch, deploy Pages from main);
  contracts.yml jobs = contracts (→ SDL lint + inspector breaking gate), site
  (validate.py + wordcount GATE + jekyll), k8s-manifests (kubeconform/helm),
  discover-examples (matrix from examples/*/verify.sh), examples (3× retry),
  examples-summary (gate).
- `presentation/`: _shared (deck-helpers.js, render_svgs.py cairosvg→png, dgen.py,
  assets, package.json, node_modules gitignored) + three deck dirs (deck.js
  pptxgenjs 16:9 Red Hat style, notes every slide, built -r1.0.pptx, qa/ gitignored).
  Zero planning/capstone language (grep gate `capstone|r[0-9][0-9]|phase [0-9]|iteration|coverage matrix|wave [0-9]`).

## Approach
Clone the gRPC project structure 1:1 and re-skin for GraphQL. Substantive swaps:
`contracts/` → canonical SDL + graphql-inspector breaking gate; both stacks
code-first (SmallRye, Strawberry) exporting SDL drift-checked vs canonical;
part arc remapped to GraphQL concerns. Author in dependency waves, each
chapter = prose + diagrams + runnable example, flipped planned→draft→verified so
CI gates stay green. Infra docker→minikube→CRC. Decks last. Each chapter/example
is an independently committable, CI-gated unit.

**Rejected:** .NET third stack (locked out); SDL-first codegen à la buf generate
(both frameworks are idiomatically code-first — use code-first + SDL export +
drift gate, canonical SDL still enforced); real-time as its own part (one chapter);
a separate transport perf chapter (GraphQL perf IS cost/depth/caching/N+1);
proprietary managed GraphQL registries (vendor-neutral + OSS inspector only).

## Steps (each a checkpoint-commit unit; branch per iteration, PR → squash-merge)
- **S1 — Repo scaffold & site shell** (no deps): copy+reskin `_config.yml`,
  Gemfile(+lock), `_layouts/*`, `_includes/*`, index.html, .gitignore, LICENSE,
  amber `assets/css/site.css`. Create public GitHub repo + branch protection.
  Gate: `jekyll build` clean.
- **S2 — Parts + outline + plans spine** (dep S1): `_parts/00..12`, `_docs/00-outline.md`,
  `_plans/coverage-matrix.md` (all `planned`), domain-glossary.md, iteration-plan.md.
- **S3 — Canonical SDL contract + CI** (dep S1): `contracts/schema/shipping/*.graphql`,
  inspector/linter config, README; port pages.yml; adapt contracts.yml (SDL job);
  port validate.py + wordcount.sh.
- **S4 — examples/_lib + lab (Ch0)** (dep S2,S3).
- **S5 — Concept chapters Ch1–2** (dep S2; no examples).
- **S6 — Wave A: Schema & Execution Ch3–8** (dep S3,S4).
- **S7 — Wave B: Reliability, Evolution, Data-at-scale Ch9–13** (dep S6; Ch11 exercises
  breaking gate; Ch12/13 cite DDIA).
- **S8 — Wave C: Performance & Security Ch14–18** (dep S7; Ch14/16 cite DDIA).
- **S9 — Wave D: Observability, Gateway, Real-time, Client Ch19–22** (dep S8).
- **S10 — Wave E: Testing & Debugging Ch23–24** (dep S9; load-testing harness).
- **S11 — Infra tiers & Final Project Ch25–27 + Appendix A** (dep S6–S10).
- **S12 — Bibliography (4 books) + voice pass** (dep all chapters).
- **S12b — Footer and site-chrome cleanup** (dep S12), as on the gRPC site (its PR #6, 4b33d5f):
  `lgtm-professional-voice` rules 13–14 and procedure step 4b. Sweep `_includes/footer.html`,
  `index.html`, `_layouts/part_index.html`, `_parts/*`, `_example_pages/index.md`, the outline and
  any planned-chapter stubs for planning links, iteration labels and sequence numbers; keep
  `plans` at `output: false`; build and confirm `grep -rl '/plans/' _site` is empty. Re-run the
  issue-framing sweep (rule 13) over every chapter, README, code comment, figure and verify message
  that landed after the 2026-10-16 scrub.
- **S13 — Three decks** (dep S12): port `_shared`, build 100/quarkus/python decks.
- **S14 — Release gate + publish** (dep all): full green sweep (validate.py,
  wordcount GATE, SDL lint/inspector, jekyll, example matrix, k8s/helm,
  idiomatic review, voice gate incl. rules 13–14); tag + GitHub release via lgtm-github.
  Hub (user request 2026-10-17): the entry is prepared on a LOCAL branch `add-graphql-site` in
  `~/Dev/patterncatalyst-workshops-tutorials-list` (35cf410). It adds the site after gRPC in `_data/sites.yml`, the
  three GraphQL books in `_data/books.yml`, and this site to DDIA's `referenced_by`; gen-books.py is not run. Push
  it and open the PR only once r01 is merged and Pages is live, so the link never 404s.
  Branch cleanup when done (user request 2026-10-17): after the squash-merge of PR #1, delete `r01` locally and on
  origin. Delete merged local branches in the hub and lgtm-skills, and remove any leftover worktrees. List the
  branches before deleting any of them.

## Acceptance criteria
- 13 parts, 28 chapters + `99-appendix-a` + outline; every `part:` resolves.
- `python -I scripts/validate.py` exits 0; `GATE=1 bash scripts/wordcount.sh` passes.
- 80–95 paired SVG+excalidraw (target 89), each with a spec in `diagrams/`; each chapter embeds ≥1.
- 27 example dirs; every non-cluster `verify.sh` green on BOTH stacks; cluster-tier
  (Ch26, Appendix A) no verify.sh, pass kubeconform/helm.
- `contracts/schema/` SDL lints clean; both stacks' exported SDL reconciles; inspector gate wired.
- `jekyll build --trace` clean; nav + baseurl + amber correct.
- `bibliography.md` lists all 4 books (DDIA cited in Ch12/13/14/16); disclaimer present.
- 3 decks build + QA clean, notes every slide, zero planning language; `presentation/` < 15 MB.
- Real-time confined to Ch21 with WebSockets forward pointer; no real-time part.
- No .NET; no proprietary cloud SDKs; minikube primary + CRC mirror.

## Risks (+ detection)
- SmallRye↔Strawberry SDL drift → export + inspector diff vs canonical in verify.sh/CI.
- N+1 silently present in example code → resolver-call-count assertion in Ch13/Ch24 verify.sh.
- Diagram count out of 80–95 → validate.py pair count + per-chapter budget in matrix.
- Chapter under 2,000 words → wordcount GATE per chapter.
- Cluster-tier example auto-discovered → keep Ch26/Appendix A free of verify.sh.
- Breaking gate false-positive on first introduction → mirror buf "no baseline → skip".
- Planning/capstone language in decks → grep gate + voice pass; mine chapters not plans.
- pptxgenjs missing in fresh sandbox → install/copy _shared/node_modules, trial-require.
- Latest-stable pin drift → pin in pom.xml/pyproject.toml/Containerfiles; idiomatic-review at release.

## RESUME POINTER (where a fresh session picks up)
Step status:

| Step | Status |
|---|---|
| S1 Repo scaffold & site shell | **done** (2026-10-15) — Opus-validated 11/11; jekyll build clean |
| S2 Parts + outline + plans spine | **done** (2026-10-15) — Opus-validated; glossary reconciled to SDL |
| S3 Canonical SDL contract + CI | **done** (2026-10-15) — Opus-validated; CI green on PR #1 incl. `ci-ok` |
| S4 examples/_lib + lab (Ch0) | **done** (2026-10-16) — harness + example + Ch0 prose Opus-validated; Ch0 `verified` |
| S5 Concept chapters Ch1–2 | **done** (2026-10-15) — Opus-validated; `draft` (no example). Diagrams hand-fixed after generation; specs not kept in repo |
| S6 Wave A Ch3–8 | **done** (2026-10-16) — all six chapters + examples Opus-validated; CI green on every `verify:` job (f567d51); Ch0–Ch8 `verified`, Ch1–2 `draft` (no example); 26 figures so far (20 in Wave A). Findings in `r01-wave-a-plan.md` §7–§10 |
| S7 Wave B Ch9–13 | **done** (2026-10-16) — B0 harness + canonical `Query.nodes` / `finalArrivalTime` (finalArrivalDate deprecated); Ch9–13 Opus-validated with repair rounds; CI green on every `verify:` job (f1aff13); Ch0, Ch3–Ch13 `verified`, Ch1–2 `draft`; 43 figures (17 in Wave B). Deliberate fixes to verified Ch1/2/4/6/10 found in validation. Findings binding on later waves in `r01-wave-b-plan.md` §9 |
| S8 Wave C Ch14–18 | **done** (2026-10-16) — C0 harness (TLS/bearer options, raw/header/APQ/OIDC helpers); Ch14–18 Opus-validated with repair rounds; site-wide reader-facing scrub (voice rules 13–14); CI green on every `verify:` job (ef6f8ce); Ch0, Ch3–Ch18 `verified`, Ch1–2 `draft`; 59 figures (16 in Wave C). Findings in `r01-wave-c-plan.md` §9 |
| S9 Wave D Ch19–22 | **done** (2026-10-17) — D0 harness (trace/metric/log/SSE/`compose_run` helpers); Ch19–22 Opus-validated with repair rounds; CI green on every `verify:` job (e5710fb, Ch14 re-run after a Maven Central fetch error); Ch0, Ch3–Ch22 `verified`, Ch1–2 `draft`; 75 figures (16 in Wave D). Findings in `r01-wave-d-plan.md` §9. Step DX done (2026-10-17): telemetry off by default in Ch0, Ch3–18 and Ch21 (`QUARKUS_OTEL_SDK_DISABLED` / `OTEL_SDK_DISABLED`), opt-in `compose.observability.yaml` with `otel-lgtm` 0.37.0 (Ch19 bumped too), Opus-validated |
| S10 Wave E Ch23–24 | **done** (2026-10-17) — E0 harness (per-request call checks, JUnit, document validation); Ch23–24 Opus-validated with one repair round each; CI green on every job (9002628); Ch0, Ch3–Ch24 `verified`, Ch1–2 `draft`; 79 figures. Findings in `r01-wave-e-plan.md` §9. Rule-13 sweep of the Ch14 cost comments and every `Node.java` done early (fabe070) |
| S11 Infra tiers & Final Project Ch25–27 + Appendix A | **done** (2026-10-17) — F0 harness + Helm-aware k8s CI job; Ch25–27 + Appendix A Opus-validated with one repair round each; Ch26/Ch27 charts proven live on minikube `gql-tracking` (Kubernetes v1.37.1), Appendix A static only; CI green on all 31 jobs (32f3390, Ch25 re-run after a Maven Central fetch error); all 27 example dirs; 89 figures; Ch0, Ch3–27 and Appendix A `verified`, Ch1–2 `draft`. Findings in `r01-wave-f-plan.md` §9 |
| S12 Bibliography + voice pass (+ S12b) | **done** (2026-10-17) — bibliography with editions, years and a per-chapter citation map (unconfirmable chapter titles cited book-level); site-wide voice pass in five batches, each Opus-validated with one repair round; site chrome and a root README; fresh Jekyll build clean (no Liquid warnings, no `/plans/` pages, 0 broken internal links); 89 figures; findings in `r01-wave-g-plan.md` §9 |
| S13 Three decks | **done** (2026-10-17) — `api-patterns-graphql-100` (78 slides, 4.7 MB), `-quarkus` (70, 2.0 MB), `-python` (68, 1.9 MB), 8.9 MB in all; built with pptxgenjs 4.0.1 in pinned UBI Node 24; code read from the repo at build time (`snippet()`); `qa.py` gates notes, fonts, logo, title, planning and content language and code fidelity; each deck Opus-validated, then a cross-deck pass. Appendix A also verified live on OpenShift Local 4.22.14 (cluster returned to its pre-run inventory) |
| S14 Release gate | **done** (2026-10-17) — CI green on all 31 jobs (f67a289); squash-merged to `main` as 9143d56 (PR #1); Pages live at https://patterncatalyst.github.io/api-patterns-and-practices-graphql/ (all 29 chapter pages 200); About link set; release `r1.0` with the three decks attached; hub entry merged (patterncatalyst-workshops-tutorials-list #13, 7a42c93); `r01` deleted locally and on origin, no stray branches in the hub or lgtm-skills |


Notes for a fresh session:
- Public GitHub repo (`main`; r01 merged and deleted; follow-ups on `r02`). Templates cloned at `~/Dev/api-patterns-and-practices-grpc`
  (primary) and `~/Dev/api-patterns-and-practices-rest` — read-only references.
- PR #1 (`r01` → `main`) carried r1.0 and is merged. `main` ruleset active: PR-only, squash-only,
  required check `ci-ok` (the always-reporting summary job in contracts.yml). Pages enabled
  (build_type workflow); About website = https://patterncatalyst.github.io/api-patterns-and-practices-graphql/.
- SDL design decisions (post-validation): edge `node` nullable (Ch4 teaches the strict variant as
  the counterexample); `HandlingEvent.cargo` nullable; `idempotencyKey` (not Relay
  `clientMutationId`); payload `userErrors` with `UserErrorCode` enum and `field` path.
  Breaking-gate policy (decided, Ch11): fail only on breaking; dangerous changes surface as PR `::warning`
  annotations; `BREAKING_RULES=dangerousBreaking` is opt-in strict mode; removing a deprecated field stays
  breaking unless `suppressRemovalOfDeprecatedField`. Wave B canonical additions: `Query.nodes(ids:)`,
  `Itinerary.finalArrivalTime` (`finalArrivalDate` deprecated).
- Upstream SmallRye GraphQL issues FILED 2026-10-16: smallrye/smallrye-graphql#2733 (`@Id List<String>` fails
  at run time), #2734 (`@Deprecated` never reaches introspection) and #2735 (client `extensions` never reach
  `ExecutionInput`; narrower than open #2321). When #2735 is fixed,
  Ch15's Vert.x persisted-document route can give way to graphql-java's `ApolloPersistedQuerySupport`.
- Further upstream drafts are kept outside this repo; do not file or re-add them. Reproducer repo:
  https://github.com/patterncatalyst/smallrye-graphql-reproducers (one module + failing `@QuarkusTest` each;
  reproduces on 2.18.5, 3.0.0.Beta7, `main`). When fixed upstream: drop the `ContractSchemaDetails` workarounds
  (ID_LIST rewrite in Ch10–13; deprecate bridge in Ch11–13) and the README notes. Bodies: `_plans/upstream/`.
- Known: `braces` advisory GHSA-vfj7-8cjw-p6xm (dev-only lint tooling, via graphql-eslint → fast-glob → micromatch;
  globs are the repo's own, no untrusted input). Re-checked 2026-10-17: no patched `braces` release (3.0.3 is
  newest); `npm audit --omit=dev` clean. Re-check when `braces` or `micromatch` publishes a fix. `graphql` stays
  on 16.14.2 (newest 16.x) because graphql-eslint 4.4.2 peers `graphql ^16`; eslint bumped to 10.13.0 on r02.
- Host Ruby lacks `ruby-devel`; build Jekyll in the `ruby:3.3` container (matches CI):
  `docker run --rm -u $(id -u):$(id -g) -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$PWD":/site:Z -v <bundle-dir>:/bundle:Z -w /site ruby:3.3 sh -c 'bundle install && bundle exec jekyll build --trace'`
- Favicon now uses `site.brand_emoji` (the gRPC template hardcodes 🔌 — upstream bug, not fixed there).

Relay orchestration: delegate each step to a Sonnet executor, Opus-validate, checkpoint-commit.
