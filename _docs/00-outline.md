---
title: "Outline"
order: 0
overview: true
part: "Prerequisites & the Lab"
description: "The 28 chapters across 13 parts plus Appendix A, with both stacks built against one SDL contract."
---

GraphQL here is the aggregation layer over a shipping and cargo domain. The **tracking view** stitches
cargo, route legs and handling events into one graph, so a client asks for exactly the shape it needs in one
round trip. Every hands-on chapter ships the same example in **both Quarkus (SmallRye GraphQL) and Python
(Strawberry)**. Both stacks are code-first and export their SDL. CI diff-checks that export against the
canonical SDL in `contracts/schema/`, and a graphql-inspector gate fails any change to the canonical SDL that
would break an existing client. Real-time gets one chapter that compares subscriptions, SSE and WebSockets.

## Part 0: Prerequisites & the Lab
- [0. Prerequisites and the lab](../00-prerequisites-and-the-lab/)

## Part 1: Why GraphQL & the Decision Lens
- [1. From REST/RPC to GraphQL](../01-from-rest-and-rpc-to-graphql/)
- [2. The GraphQL decision framework](../02-graphql-decision-framework/)

## Part 2: SDL & the Type System
- [3. SDL and the type system in depth](../03-sdl-and-the-type-system/)
- [4. Nullability and null propagation](../04-nullability-and-null-propagation/)
- [5. Schema-first / contract-first](../05-contract-first-schemas/)

## Part 3: Execution, Resolvers, Queries & Mutations
- [6. The execution model](../06-the-execution-model/)
- [7. Queries and resolvers](../07-queries-and-resolvers/)
- [8. Mutations and input types](../08-mutations-and-input-types/)

## Part 4: Reliability: Errors & Partial Results
- [9. Error handling](../09-error-handling/)

## Part 5: Schema Evolution & the Living Contract
- [10. Schema design patterns](../10-schema-design-patterns/)
- [11. Evolution and versioning](../11-evolution-and-versioning/)

## Part 6: Data Fetching at Scale
- [12. Connections & pagination](../12-connections-and-pagination/)
- [13. The N+1 problem and dataloaders](../13-n-plus-one-and-dataloaders/)

## Part 7: Performance & Safety
- [14. Depth limits & query cost analysis](../14-depth-limits-and-query-cost/)
- [15. Persisted queries & APQ](../15-persisted-queries-and-apq/)
- [16. Caching](../16-caching/)

## Part 8: Security
- [17. Transport security & introspection control](../17-transport-security-and-introspection/)
- [18. AuthN & AuthZ](../18-authn-and-authz/)

## Part 9: Observability & the Gateway
- [19. Observability](../19-observability/)
- [20. Federation & schema composition](../20-federation-and-schema-composition/)

## Part 10: Real-time & Client Integration
- [21. Real-time: subscriptions vs SSE vs WebSockets](../21-real-time-subscriptions-sse-websockets/)
- [22. Client integration](../22-client-integration/)

## Part 11: Testing & Debugging
- [23. Testing GraphQL APIs](../23-testing-graphql-apis/)
- [24. Debugging GraphQL](../24-debugging-graphql/)

## Part 12: Running It & the Final Project
- [25. Local with Docker Compose](../25-local-with-docker-compose/)
- [26. Kubernetes on minikube](../26-kubernetes-on-minikube/)
- [27. The final project](../27-the-final-project/)
- [Appendix A: OpenShift Local (CRC)](../99-appendix-a-openshift-crc/)
