---
title: "Examples"
layout: plan
permalink: /examples/
description: "Every runnable example in this repo, mapped to the chapter it supports."
---

Every hands-on chapter in this site has a matching runnable example under
[`examples/`](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples)
in the repo. Each hands-on example ships **both** a Quarkus (SmallRye GraphQL) and a
Python (Strawberry) implementation, built code-first against the same canonical SDL,
and a `verify.sh` that calls the running services, asserts response semantics as well as status codes,
and checks each stack's live schema against the contract.

| Example | What it shows | Stacks | Chapter |
|---|---|---|---|
| [00-prerequisites](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/00-prerequisites) | Lab skeleton — both stacks serve a canned `cargo(trackingId:)` slice, reject bad scalars, and conform to the canonical SDL | Both | [Ch0]({{ '/docs/00-prerequisites-and-the-lab/' | relative_url }}) |
| [03-sdl-type-system](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/03-sdl-type-system) | Type system — enums, `Node` dispatch by id, `DateTime` and custom scalars, identical values on both stacks | Both | [Ch3]({{ '/docs/03-sdl-and-the-type-system/' | relative_url }}) |
| [04-nullability](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/04-nullability) | Null propagation — a failed voyage nulls at the leg, a null `loadLocation` bubbles to `itinerary`, a failed delivery nulls `cargo`; error paths asserted exactly | Both | [Ch4]({{ '/docs/04-nullability-and-null-propagation/' | relative_url }}) |
| [05-contract-first](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/05-contract-first) | Contract-first — SDL exported from both stacks, a two-direction drift gate, five seeded drifts that fail it | Both | [Ch5]({{ '/docs/05-contract-first-schemas/' | relative_url }}) |
| [06-execution-model](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/06-execution-model) | Execution phases — zero source calls on request errors, sibling resolvers overlapping in time, `operationName` selection | Both | [Ch6]({{ '/docs/06-the-execution-model/' | relative_url }}) |
| [07-queries-resolvers](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/07-queries-resolvers) | Resolver chain — parent values keying child calls, a derived `Delivery`, `@include`/`@skip` pruning source calls | Both | [Ch7]({{ '/docs/07-queries-and-resolvers/' | relative_url }}) |
| [08-mutations](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/08-mutations) | `registerHandlingEvent` — coercion errors vs `userErrors`, payload re-read, serial aliased mutations, idempotent replay under parallel retries | Both | [Ch8]({{ '/docs/08-mutations-and-input-types/' | relative_url }}) |
| [09-error-handling](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/09-error-handling) | Exposed vs masked execution errors — partial data with error paths, a stable `extensions.code` vocabulary, internal detail kept in the server log, status codes by media type | Both | [Ch9]({{ '/docs/09-error-handling/' | relative_url }}) |
| [10-schema-design](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/10-schema-design) | `Node` refetch rule, `nodes(ids:)` order and null semantics, naming and payload conventions checked against both live schemas | Both | [Ch10]({{ '/docs/10-schema-design-patterns/' | relative_url }}) |
| [11-evolution](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/11-evolution) | `finalArrivalDate` deprecated for `finalArrivalTime` on both stacks, and the breaking-change gate run on safe, dangerous, breaking and strict-mode fixtures | Both | [Ch11]({{ '/docs/11-evolution-and-versioning/' | relative_url }}) |
| [12-pagination](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/12-pagination) | Relay connections with opaque keyset cursors — forward and backward paging, stability under inserts, the edge-node fuse, and the 29-call N+1 baseline | Both | [Ch12]({{ '/docs/12-connections-and-pagination/' | relative_url }}) |
| [13-dataloaders](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/13-dataloaders) | N+1 measured and batched — SmallRye `@Source List` batch resolvers and Strawberry DataLoaders, 29 source calls down to 8 (Quarkus) and 6 (Python) | Both | [Ch13]({{ '/docs/13-n-plus-one-and-dataloaders/' | relative_url }}) |
| [14-query-cost](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/14-query-cost) | Depth, token, alias and list-aware cost limits on both stacks; deep, wide and batched requests are refused before any source call | Both | [Ch14]({{ '/docs/14-depth-limits-and-query-cost/' | relative_url }}) |
| [15-persisted-queries](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/15-persisted-queries) | Apollo automatic persisted queries and a trusted-document allowlist, GET by hash, mutations kept on POST | Both | [Ch15]({{ '/docs/15-persisted-queries-and-apq/' | relative_url }}) |
| [16-caching](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/16-caching) | `Cache-Control` per response, an nginx edge cache (MISS, HIT, BYPASS), field caches with expiry and invalidation on write | Both | [Ch16]({{ '/docs/16-caching/' | relative_url }}) |
| [17-transport-security](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/17-transport-security) | TLS with certificates generated at run time, public and internal instances, introspection off in public, CORS and JSON-only request bodies | Both | [Ch17]({{ '/docs/17-transport-security-and-introspection/' | relative_url }}) |
| [18-authn-authz](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/18-authn-authz) | Keycloak-issued JWTs, operation- and field-level authorization, a shipper sees only its own cargos on every path | Both | [Ch18]({{ '/docs/18-authn-and-authz/' | relative_url }}) |
| [19-observability](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/19-observability) | A trace per request joined to the caller's trace id, a span per resolver, span metrics, errors by code, deprecated-field usage by client, and the error log line found by trace id | Both | [Ch19]({{ '/docs/19-observability/' | relative_url }}) |
| [20-federation](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/20-federation) | Four subgraphs (cargo and handling on both stacks), explicit composition with The Guild's composer, two cross-wired Hive Gateways, the query plan counted per subgraph | Both | [Ch20]({{ '/docs/20-federation-and-schema-composition/' | relative_url }}) |
| [21-real-time](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/21-real-time) | `Subscription.cargoHandled` over graphql-transport-ws on both stacks, GraphQL over SSE on Python, a plain SSE feed that resumes from `Last-Event-ID`, every subscriber cleaned up | Both | [Ch21]({{ '/docs/21-real-time-subscriptions-sse-websockets/' | relative_url }}) |
| [22-client-integration](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/22-client-integration) | Apollo Client's normalized cache with typed documents from codegen, Python `gql` validating against the schema, the SmallRye typesafe client reading a partial page | Both | [Ch22]({{ '/docs/22-client-integration/' | relative_url }}) |
| [23-testing](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/23-testing) | Six test layers on both stacks in UBI test images (schema, resolver unit, operation, contract, client documents, load); k6 load runs assert per-request call shapes, refusals with no call, and one write under concurrent retries | Both | [Ch23]({{ '/docs/23-testing-graphql-apis/' | relative_url }}) |
| [24-debugging](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/24-debugging) | A seeded fault diagnosed from the error path and from `extensions.traceId` through Tempo and Loki; a debug log category switched at run time; GraphiQL and the Dev UI on dev instances only | Both | [Ch24]({{ '/docs/24-debugging-graphql/' | relative_url }}) |
| [25-docker-compose](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/25-docker-compose) | Both stacks behind an nginx edge (TLS 1.3, a 64k body limit, only `/graphql` routed) on an internal network, with configs, secrets, health, limits, restart and graceful stop | Both | [Ch25]({{ '/docs/25-local-with-docker-compose/' | relative_url }}) |
| [26-minikube](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/26-minikube) | One Helm chart for both stacks on minikube: probes, ConfigMaps, generated TLS, NetworkPolicy and `helm test`, behind a NodePort edge (cluster tier, no `verify.sh`) | Both | [Ch26]({{ '/docs/26-kubernetes-on-minikube/' | relative_url }}) |
| [27-final-project](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/27-final-project) | Every defence together: the complete schema with subscriptions, cost limits, Keycloak authorization on every path, internal-only introspection and k6 through the edge, on Compose and on minikube | Both | [Ch27]({{ '/docs/27-the-final-project/' | relative_url }}) |
| [99-appendix-a-openshift-crc](https://github.com/{{ site.github_username }}/{{ site.github_repo }}/tree/main/examples/99-appendix-a-openshift-crc) | The final project's chart on OpenShift Local through a wrapper chart: Routes, in-cluster builds and ImageStreams (cluster tier, validated statically) | Both | [Appendix A]({{ '/docs/99-appendix-a-openshift-crc/' | relative_url }}) |

## Running an example

Each directory is self-contained — a `README.md`, a `compose.yaml`, and a
`verify.sh` that calls the running services, asserts response semantics as well
as status codes, and checks each stack's live schema against the canonical SDL
under `contracts/schema/`. The cluster-tier examples ship a `helm/` chart
instead and run on minikube or CRC.

```bash
cd examples/05-contract-first
./verify.sh
```

See [Prerequisites & the Lab]({{ '/docs/00-prerequisites-and-the-lab/' | relative_url }}) for the full toolchain setup.
