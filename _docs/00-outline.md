---
title: "Outline"
order: 0
overview: true
part: "Prerequisites & the Lab"
description: "What this site covers and how it's organized — 28 chapters across 13 parts plus Appendix A, both stacks against one SDL contract."
---

This site teaches GraphQL API design through one read-oriented view of a shipping and
cargo domain: the **tracking view**. GraphQL here is the aggregation layer that stitches
cargo, route legs and handling events into a single query-shaped graph, so a client asks
for exactly the shape it needs in one round trip. Every hands-on chapter ships the same
example in **both Quarkus (SmallRye GraphQL) and Python (Strawberry)**. Both stacks are
code-first and export their SDL; CI diff-checks that export against the canonical SDL in
`contracts/schema/`, so the two stacks never drift, and a graphql-inspector gate fails any
change to the canonical SDL that would break an existing client. Real-time is a single chapter (Ch21) that compares
subscriptions, SSE and WebSockets and points to a planned WebSockets book. The full arc is below.

## Part 0 — Prerequisites & the Lab
- [Ch0 · Prerequisites and the lab](../00-prerequisites-and-the-lab/)

## Part 1 — Why GraphQL & the Decision Lens
- [Ch1 · From REST/RPC to GraphQL](../01-from-rest-and-rpc-to-graphql/)
- [Ch2 · The GraphQL decision framework](../02-graphql-decision-framework/)

## Part 2 — The Schema: SDL & the Type System
- [Ch3 · SDL and the type system in depth](../03-sdl-and-the-type-system/)
- [Ch4 · Nullability and null propagation](../04-nullability-and-null-propagation/)
- [Ch5 · Schema-first / contract-first](../05-contract-first-schemas/)

## Part 3 — Execution: Resolvers, Queries & Mutations
- [Ch6 · The execution model](../06-the-execution-model/)
- [Ch7 · Queries and resolvers](../07-queries-and-resolvers/)
- [Ch8 · Mutations and input types](../08-mutations-and-input-types/)

## Part 4 — Reliability: Errors & Partial Results
- [Ch9 · Error handling](../09-error-handling/)

## Part 5 — Schema Evolution & the Living Contract
- [Ch10 · Schema design patterns](../10-schema-design-patterns/)
- [Ch11 · Evolution and versioning](../11-evolution-and-versioning/)

## Part 6 — Data Fetching at Scale
- [Ch12 · Connections & pagination](../12-connections-and-pagination/)
- [Ch13 · The N+1 problem and dataloaders](../13-n-plus-one-and-dataloaders/)

## Part 7 — Performance & Safety
- [Ch14 · Depth limits & query cost analysis](../14-depth-limits-and-query-cost/)
- [Ch15 · Persisted queries & APQ](../15-persisted-queries-and-apq/)
- [Ch16 · Caching](../16-caching/)

## Part 8 — Security
- [Ch17 · Transport security & introspection control](../17-transport-security-and-introspection/)
- [Ch18 · AuthN & AuthZ](../18-authn-and-authz/)

## Part 9 — Observability & the Gateway
- [Ch19 · Observability](../19-observability/)
- [Ch20 · Federation & schema composition](../20-federation-and-schema-composition/)

## Part 10 — Real-time & Client Integration
- [Ch21 · Real-time: subscriptions vs SSE vs WebSockets](../21-real-time-subscriptions-sse-websockets/)
- [Ch22 · Client integration](../22-client-integration/)

## Part 11 — Testing & Debugging
- [Ch23 · Testing GraphQL APIs](../23-testing-graphql-apis/)
- [Ch24 · Debugging GraphQL](../24-debugging-graphql/)

## Part 12 — Running It & the Final Project
- [Ch25 · Local with Docker Compose](../25-local-with-docker-compose/)
- [Ch26 · Kubernetes on minikube](../26-kubernetes-on-minikube/)
- [Ch27 · The final project](../27-the-final-project/)
- [Appendix A · OpenShift Local (CRC)](../99-appendix-a-openshift-crc/)
