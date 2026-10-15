---
layout: plan
render_with_liquid: false
title: "r01 Execution Plan — api-patterns-and-practices-graphql"
---

# PLAN — api-patterns-and-practices-graphql (series site #3)

**Status: APPROVED by user 2026-10-15. Execution started (branch `r01`). Paused after plan commit; scaffold not yet begun.**

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
  Poetry, latest-stable LTS, UBI 10.
- Domain: GraphQL as the **tracking view** — a read-oriented aggregation layer
  stitching cargo, route legs, and handling events into one query-shaped graph.
- Diagrams: paired `assets/diagrams/NN-slug.svg` + `.excalidraw` via
  lgtm-diagram-generator (amber), embedded with `{% include excalidraw.html %}`
  (renders `<img>`). Target **71** (band 60–72), gRPC-level density.
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

## Canonical outline (13 parts / 28 chapters + Appendix A; 71 diagrams; 27 example dirs)
Ex = carries runnable example. Dg = diagram estimate.

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
- **S13 — Three decks** (dep S12): port `_shared`, build 100/quarkus/python decks.
- **S14 — Release gate + publish** (dep all): full green sweep (validate.py,
  wordcount GATE, SDL lint/inspector, jekyll, example matrix, k8s/helm,
  idiomatic review, voice gate); tag + GitHub release via lgtm-github.
  Out-of-repo follow-up (NOT on this branch, user does it): add site to hub
  `_data/sites.yml` + the 4 books to `_data/books.yml` next to gRPC (never run gen-books.py).

## Acceptance criteria
- 13 parts, 28 chapters + `99-appendix-a` + outline; every `part:` resolves.
- `python -I scripts/validate.py` exits 0; `GATE=1 bash scripts/wordcount.sh` passes.
- 60–72 paired SVG+excalidraw (target 71); each chapter embeds ≥1.
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
- Diagram count out of 60–72 → validate.py pair count + per-chapter budget in matrix.
- Chapter under 2,000 words → wordcount GATE per chapter.
- Cluster-tier example auto-discovered → keep Ch26/Appendix A free of verify.sh.
- Breaking gate false-positive on first introduction → mirror buf "no baseline → skip".
- Planning/capstone language in decks → grep gate + voice pass; mine chapters not plans.
- pptxgenjs missing in fresh sandbox → install/copy _shared/node_modules, trial-require.
- Latest-stable pin drift → pin in pom.xml/pyproject.toml/Containerfiles; idiomatic-review at release.

## RESUME POINTER (where a fresh session picks up)
Done: project dir created at `~/Dev/api-patterns-and-practices-graphql`, `git init`,
branch `r01`, this plan committed. GitHub repo NOT yet created. Scaffold NOT started.
Next action: **S1** — create public GitHub repo via lgtm-github + branch protection,
then scaffold the site shell by copying/re-skinning from `~/Dev/api-patterns-and-practices-grpc`.
Relay orchestration: delegate each step to a Sonnet executor, Opus-validate, checkpoint-commit.
