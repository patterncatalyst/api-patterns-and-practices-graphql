---
title: "Coverage Matrix"
layout: plan
render_with_liquid: false
---

# Coverage Matrix

Every topic maps to exactly one chapter. `scripts/validate.py` reads this
file and fails CI when a chapter whose **Status is not `planned`** is missing its
`_docs/*.md` file — so coverage is authored incrementally (all rows start `planned`)
while still guaranteeing no mapped-and-claimed chapter silently disappears.

**Status legend:** `planned` (file not yet written) · `draft` (prose in, unverified) ·
`verified` (both stacks run green, footer flipped).

## Topics → chapters

| # | Topic | Chapter | File | Status |
|---|---|---|---|---|
| T1 | Prerequisites, lab toolchain and the tracking domain | Ch0 | `_docs/00-prerequisites-and-the-lab.md` | verified |
| T2 | Why GraphQL: from REST/RPC to a query-shaped graph | Ch1 | `_docs/01-from-rest-and-rpc-to-graphql.md` | verified |
| T3 | GraphQL decision framework | Ch2 | `_docs/02-graphql-decision-framework.md` | verified |
| T4 | SDL and the type system in depth | Ch3 | `_docs/03-sdl-and-the-type-system.md` | verified |
| T5 | Nullability and null propagation | Ch4 | `_docs/04-nullability-and-null-propagation.md` | verified |
| T6 | Schema-first / contract-first (canonical SDL, code-first export, drift gate) | Ch5 | `_docs/05-contract-first-schemas.md` | verified |
| T7 | The execution model (parse, validate, execute) | Ch6 | `_docs/06-the-execution-model.md` | verified |
| T8 | Queries and resolvers | Ch7 | `_docs/07-queries-and-resolvers.md` | verified |
| T9 | Mutations and input types | Ch8 | `_docs/08-mutations-and-input-types.md` | verified |
| T10 | Error handling and partial results | Ch9 | `_docs/09-error-handling.md` | verified |
| T11 | Schema design patterns | Ch10 | `_docs/10-schema-design-patterns.md` | verified |
| T12 | Evolution, deprecation and the breaking-change gate | Ch11 | `_docs/11-evolution-and-versioning.md` | verified |
| T13 | Connections and cursor pagination | Ch12 | `_docs/12-connections-and-pagination.md` | verified |
| T14 | The N+1 problem, batching and dataloaders | Ch13 | `_docs/13-n-plus-one-and-dataloaders.md` | verified |
| T15 | Depth limits and query cost analysis | Ch14 | `_docs/14-depth-limits-and-query-cost.md` | verified |
| T16 | Persisted queries and APQ | Ch15 | `_docs/15-persisted-queries-and-apq.md` | verified |
| T17 | Caching (HTTP, response, field and dataloader) | Ch16 | `_docs/16-caching.md` | verified |
| T18 | Transport security and introspection control | Ch17 | `_docs/17-transport-security-and-introspection.md` | verified |
| T19 | AuthN and AuthZ (field-level authorization) | Ch18 | `_docs/18-authn-and-authz.md` | verified |
| T20 | Observability (resolver tracing, metrics, logs) | Ch19 | `_docs/19-observability.md` | verified |
| T21 | Federation and schema composition | Ch20 | `_docs/20-federation-and-schema-composition.md` | verified |
| T22 | Real-time: subscriptions vs SSE vs WebSockets | Ch21 | `_docs/21-real-time-subscriptions-sse-websockets.md` | verified |
| T23 | Client integration | Ch22 | `_docs/22-client-integration.md` | verified |
| T24 | Testing GraphQL APIs and the load-testing harness | Ch23 | `_docs/23-testing-graphql-apis.md` | verified |
| T25 | Debugging GraphQL | Ch24 | `_docs/24-debugging-graphql.md` | verified |
| T26 | Local with Docker Compose | Ch25 | `_docs/25-local-with-docker-compose.md` | verified |
| T27 | Kubernetes on minikube | Ch26 | `_docs/26-kubernetes-on-minikube.md` | verified |
| T28 | The final project | Ch27 | `_docs/27-the-final-project.md` | verified |

## Runtime-tier topics → chapters

| # | Topic | Chapter | File | Status |
|---|---|---|---|---|
| R1 | Docker Compose tier | Ch0 / Ch25 | `_docs/25-local-with-docker-compose.md` | planned |
| R2 | minikube tier | Ch26 / Ch27 | `_docs/26-kubernetes-on-minikube.md` | planned |
| R3 | CRC / OpenShift Local tier | Appendix A | `_docs/99-appendix-a-openshift-crc.md` | verified |

## Full chapter inventory (28 + appendix)

| Ch | File | Part | Status |
|---|---|---|---|
| 0 | `_docs/00-prerequisites-and-the-lab.md` | Part 0 | verified |
| 1 | `_docs/01-from-rest-and-rpc-to-graphql.md` | Part 1 | verified |
| 2 | `_docs/02-graphql-decision-framework.md` | Part 1 | verified |
| 3 | `_docs/03-sdl-and-the-type-system.md` | Part 2 | verified |
| 4 | `_docs/04-nullability-and-null-propagation.md` | Part 2 | verified |
| 5 | `_docs/05-contract-first-schemas.md` | Part 2 | verified |
| 6 | `_docs/06-the-execution-model.md` | Part 3 | verified |
| 7 | `_docs/07-queries-and-resolvers.md` | Part 3 | verified |
| 8 | `_docs/08-mutations-and-input-types.md` | Part 3 | verified |
| 9 | `_docs/09-error-handling.md` | Part 4 | verified |
| 10 | `_docs/10-schema-design-patterns.md` | Part 5 | verified |
| 11 | `_docs/11-evolution-and-versioning.md` | Part 5 | verified |
| 12 | `_docs/12-connections-and-pagination.md` | Part 6 | verified |
| 13 | `_docs/13-n-plus-one-and-dataloaders.md` | Part 6 | verified |
| 14 | `_docs/14-depth-limits-and-query-cost.md` | Part 7 | verified |
| 15 | `_docs/15-persisted-queries-and-apq.md` | Part 7 | verified |
| 16 | `_docs/16-caching.md` | Part 7 | verified |
| 17 | `_docs/17-transport-security-and-introspection.md` | Part 8 | verified |
| 18 | `_docs/18-authn-and-authz.md` | Part 8 | verified |
| 19 | `_docs/19-observability.md` | Part 9 | verified |
| 20 | `_docs/20-federation-and-schema-composition.md` | Part 9 | verified |
| 21 | `_docs/21-real-time-subscriptions-sse-websockets.md` | Part 10 | verified |
| 22 | `_docs/22-client-integration.md` | Part 10 | verified |
| 23 | `_docs/23-testing-graphql-apis.md` | Part 11 | verified |
| 24 | `_docs/24-debugging-graphql.md` | Part 11 | verified |
| 25 | `_docs/25-local-with-docker-compose.md` | Part 12 | verified |
| 26 | `_docs/26-kubernetes-on-minikube.md` | Part 12 | verified |
| 27 | `_docs/27-the-final-project.md` | Part 12 | verified |
| A | `_docs/99-appendix-a-openshift-crc.md` | Part 12 | verified |

## Diagram budget

Target total: **89** paired SVG + `.excalidraw` figures (band 80–95). Each chapter embeds at least one.
GraphQL runs heavier on figures than the sibling books: the extra ones show data movement
(execution order, resolver fan-out, null propagation, batching, cursors, cache layers, query plans).
Specs live in `diagrams/` (one per figure).

| Ch | Diagrams | Data-movement focus |
|---|---|---|
| 0 | 2 | |
| 1 | 2 | |
| 2 | 2 | |
| 3 | 4 | + how a selection maps onto types |
| 4 | 3 | + step-by-step null bubbling through a response |
| 5 | 2 | |
| 6 | 5 | + field-by-field execution walk; parallel query vs serial mutation fields |
| 7 | 3 | + resolver chain: parent value → child args → source calls |
| 8 | 3 | + mutation flow: input coercion → write → payload re-read |
| 9 | 4 | + partial data: errors[] paths beside data |
| 10 | 2 | |
| 11 | 2 | |
| 12 | 4 | + cursor movement across pages |
| 13 | 5 | + N+1 fan-out vs batched load; DataLoader tick timeline |
| 14 | 4 | + cost accumulation across a nested selection |
| 15 | 3 | + APQ hash handshake round trips |
| 16 | 4 | + cache layers: client, CDN/GET, resolver, source |
| 17 | 2 | |
| 18 | 3 | |
| 19 | 4 | + one trace with a span per resolver |
| 20 | 5 | + query plan split across subgraphs; entity-reference fetch |
| 21 | 4 | + event path from handling store to subscriber |
| 22 | 3 | + client normalized cache update |
| 23 | 2 | |
| 24 | 2 | |
| 25 | 2 | |
| 26 | 2 | |
| 27 | 3 | |
| A | 3 | |
| **Total** | **89** | |
