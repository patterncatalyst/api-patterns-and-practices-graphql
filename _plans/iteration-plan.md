---
title: "Build & Iteration Plan"
layout: plan
render_with_liquid: false
---

# Build & Iteration Plan — API Patterns and Practices: GraphQL

Third of the per-style sites, after REST and gRPC. The structure mirrors the gRPC
sibling; the contract spine is a canonical **SDL** in `contracts/schema/` instead of
proto, and a **graphql-inspector** breaking-change gate replaces `buf breaking`. The
full decisions, outline and naming tables live in `_plans/r01-execution-plan.md`; this
file tracks the build order.

## Approach

- **Contract spine = canonical SDL.** Both stacks (Quarkus SmallRye GraphQL, Python
  Strawberry) are code-first, export their SDL, and CI diff-checks the export against
  the canonical schema. graphql-inspector gates breaking changes.
- **Behavioral verification.** Each hands-on example ships a `verify.sh` that runs the
  service and asserts response semantics, not just a status code. A chapter is marked
  verified only when both stacks pass.
- **Dependency waves.** Chapters are authored in waves so each wave builds on proven
  earlier ones. Every chapter and example is an independently committable, CI-gated unit.
- **One domain.** The shipping/cargo tracking view, per `_plans/domain-glossary.md`.
- **Audited coverage.** `_plans/coverage-matrix.md` maps every topic to one chapter; CI
  fails when a mapped, non-`planned` chapter file is missing.

## Steps

| Step | Work | Depends on | Gate |
|---|---|---|---|
| S1 | Repo scaffold and site shell: config, layouts, includes, home page, styles, repo and branch setup | none | `jekyll build` clean |
| S2 | Parts, outline and plans spine: `_parts/00..12`, outline page, coverage matrix (all `planned`), glossary, this plan | S1 | `jekyll build` clean; every `part:` resolves; matrix parses |
| S3 | Canonical SDL contract and CI: `contracts/schema/`, inspector and linter config, workflows, `validate.py`, `wordcount.sh` | S1 | SDL lints clean; workflows parse |
| S4 | Shared example library and lab (Ch0) | S2, S3 | Ch0 `verify.sh` green on both stacks |
| S5 | Concept chapters Ch1–2 (no examples) | S2 | word floor; diagrams paired |
| S6 | Wave A, Schema and execution: Ch3–8 | S3, S4 | both stacks green; SDL export matches canonical |
| S7 | Wave B, Reliability, evolution, data at scale: Ch9–13 | S6 | Ch11 exercises the breaking gate; Ch13 asserts resolver call counts |
| S8 | Wave C, Performance and security: Ch14–18 | S7 | both stacks green |
| S9 | Wave D, Observability, gateway, real-time, client: Ch19–22 | S8 | both stacks green; real-time confined to Ch21 |
| S10 | Wave E, Testing and debugging: Ch23–24, load-testing harness | S9 | both stacks green |
| S11 | Infra tiers and final project: Ch25–27 and Appendix A | S6–S10 | Compose verify green; minikube and CRC manifests pass kubeconform and helm |
| S12 | Bibliography and voice pass | all chapters | voice scan clean |
| S13 | Three decks: concepts, Quarkus, Python | S12 | decks build; notes on every slide |
| S14 | Release gate and publish | all | full sweep green; tagged release |

## Waves

- **Foundation:** S1 → S2 and S3 in parallel → S4.
- **Concepts:** S5 can run as soon as S2 lands.
- **Content waves:** S6 → S7 → S8 → S9 → S10, each building on the last.
- **Infrastructure and wrap-up:** S11, then S12 → S13 → S14.

## Status

| Step | Status |
|---|---|
| S1 | done |
| S2 | done |
| S3 | done |
| S4 | done |
| S5 | done |
| S6 | done (Wave A, Ch3–8; see `r01-wave-a-plan.md`) |
| S7 | done (Wave B, Ch9–13; see `r01-wave-b-plan.md`) |
| S8 | done (Wave C, Ch14–18; see `r01-wave-c-plan.md`) |
| S9 | done (Wave D, Ch19–22; see `r01-wave-d-plan.md`); step DX (OTLP default) done |
| S10 | done (Wave E, Ch23–24; see `r01-wave-e-plan.md`) |
| S11 | done (Ch25–27 + Appendix A; see `r01-wave-f-plan.md`) |
| S12 | done (bibliography, voice pass and site chrome; see `r01-wave-g-plan.md`) |
| S13 | done (three decks; see `r01-wave-h-plan.md`) |
| S14 | next |

The authoritative, detailed status is the RESUME POINTER in `r01-execution-plan.md`.

## Per-chapter gates

- Prose at or above the 2,000-word floor (`scripts/wordcount.sh`).
- At least one paired SVG + `.excalidraw` diagram embedded; 89 across the site (band 80–95); specs in `diagrams/`.
- Both stacks pass the same `verify.sh`; exported SDL reconciles with the canonical SDL.
- Cluster-tier directories (Ch26, Appendix A) carry no `verify.sh` and are validated with kubeconform and helm.
- `python -I scripts/validate.py` exits 0 and `jekyll build --trace` is clean.
