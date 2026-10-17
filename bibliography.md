---
title: "Bibliography"
layout: plan
permalink: /bibliography/
description: "The reference works this site's coverage and rigor draw on — nothing here is ported from them."
---

This site's chapter arc, pattern coverage, and level of rigor draw on a small set
of books and primary specifications on GraphQL and data-intensive systems. They're
reference works, not sources — no text or code from any of them is reproduced
here. If a topic in this site is useful to you, these are where to go deeper.

## Books

| Title | Author(s) | Publisher | Edition | Year | Focus |
|---|---|---|---|---|---|
| [*GraphQL in Action*](https://www.manning.com/books/graphql-in-action) | Samer Buna | Manning | 1st | 2021 | The language, schema design, resolvers, data fetching, mutations, client use |
| [*GraphQL Best Practices*](https://www.packtpub.com/en-us/product/graphql-best-practices-9781835467145) | Artur Czemiel | Packt | 1st | 2024 | Schema design, error descriptions, query limits and security |
| [*Full Stack GraphQL Applications*](https://www.manning.com/books/fullstack-graphql-applications) | William Lyon | Manning | 1st | 2022 | End-to-end applications, authorization, pagination, React and Apollo clients |
| [*Designing Data-Intensive Applications*, 2nd ed.](https://www.oreilly.com/library/view/designing-data-intensive-applications/9781098119058/) | Martin Kleppmann, Chris Riccomini | O'Reilly | 2nd | 2026 | Data-layer rigor behind pagination, batching, query cost, caching |

## Where each book is cited

Each chapter's closing section names the parts of these books that cover the same ground.

### *GraphQL in Action*

| Chapter here | Chapter of the book |
|---|---|
| [Ch1 · From REST/RPC to GraphQL]({{ '/docs/01-from-rest-and-rpc-to-graphql/' | relative_url }}) | the book as a whole, for language and execution model |
| [Ch2 · The GraphQL decision framework]({{ '/docs/02-graphql-decision-framework/' | relative_url }}) | the book as a whole, for schema and resolver design |
| [Ch3 · SDL and the type system in depth]({{ '/docs/03-sdl-and-the-type-system/' | relative_url }}) | Chapter 1, "Introduction to GraphQL", and chapter 4, "Designing a GraphQL schema" |
| [Ch4 · Nullability and null propagation]({{ '/docs/04-nullability-and-null-propagation/' | relative_url }}) | Chapter 4, "Designing a GraphQL schema" |
| [Ch5 · Schema-first / contract-first]({{ '/docs/05-contract-first-schemas/' | relative_url }}) | Chapter 4, "Designing a GraphQL schema" |
| [Ch6 · The execution model]({{ '/docs/06-the-execution-model/' | relative_url }}) | Chapter 1, "Introduction to GraphQL", and chapter 5, "Implementing schema resolvers" |
| [Ch7 · Queries and resolvers]({{ '/docs/07-queries-and-resolvers/' | relative_url }}) | Chapter 3, "Customizing and organizing GraphQL operations", chapter 5, "Implementing schema resolvers", and chapter 6, "Working with database models and relations" |
| [Ch8 · Mutations and input types]({{ '/docs/08-mutations-and-input-types/' | relative_url }}) | Chapter 8, "Implementing mutations" |
| [Ch9 · Error handling]({{ '/docs/09-error-handling/' | relative_url }}) | Chapter 8, "Implementing mutations" |
| [Ch10 · Schema design patterns]({{ '/docs/10-schema-design-patterns/' | relative_url }}) | Chapter 4, "Designing a GraphQL schema" |
| [Ch13 · The N+1 problem and DataLoaders]({{ '/docs/13-n-plus-one-and-dataloaders/' | relative_url }}) | Chapter 7, "Optimizing data fetching" |
| [Ch16 · Caching]({{ '/docs/16-caching/' | relative_url }}) | Chapter 7, "Optimizing data fetching" |
| [Ch22 · Client integration]({{ '/docs/22-client-integration/' | relative_url }}) | the book as a whole, for consuming a GraphQL API from a client |

### *GraphQL Best Practices*

| Chapter here | Chapter of the book |
|---|---|
| [Ch9 · Error handling]({{ '/docs/09-error-handling/' | relative_url }}) | the book as a whole, for error descriptions |
| [Ch10 · Schema design patterns]({{ '/docs/10-schema-design-patterns/' | relative_url }}) | the book as a whole, for naming, enums, interfaces and pagination |
| [Ch11 · Evolution and versioning]({{ '/docs/11-evolution-and-versioning/' | relative_url }}) | the book as a whole, for schema design |
| [Ch14 · Depth limits and query cost analysis]({{ '/docs/14-depth-limits-and-query-cost/' | relative_url }}) | the book as a whole, for query limits |
| [Ch17 · Transport security and introspection control]({{ '/docs/17-transport-security-and-introspection/' | relative_url }}) | the book as a whole, for attacks on GraphQL servers and schema design for security |

### *Full Stack GraphQL Applications*

| Chapter here | Chapter of the book |
|---|---|
| [Ch1 · From REST/RPC to GraphQL]({{ '/docs/01-from-rest-and-rpc-to-graphql/' | relative_url }}) | the book as a whole, for the end-to-end application view |
| [Ch2 · The GraphQL decision framework]({{ '/docs/02-graphql-decision-framework/' | relative_url }}) | the book as a whole, for clients and authorization |
| [Ch12 · Connections and pagination]({{ '/docs/12-connections-and-pagination/' | relative_url }}) | Chapter 9, "Advanced GraphQL considerations" |
| [Ch18 · AuthN and AuthZ]({{ '/docs/18-authn-and-authz/' | relative_url }}) | Chapter 7, "Adding authorization and authentication" |
| [Ch22 · Client integration]({{ '/docs/22-client-integration/' | relative_url }}) | the book as a whole, for a React client on Apollo Client |
| [Ch27 · The final project]({{ '/docs/27-the-final-project/' | relative_url }}) | Chapter 7, "Adding authorization and authentication", and chapter 9, "Advanced GraphQL considerations" |

### *Designing Data-Intensive Applications*, 2nd edition

| Chapter here | Chapter of the book |
|---|---|
| [Ch11 · Evolution and versioning]({{ '/docs/11-evolution-and-versioning/' | relative_url }}) | the book as a whole, for backward and forward compatibility |
| [Ch12 · Connections and pagination]({{ '/docs/12-connections-and-pagination/' | relative_url }}) | the book as a whole, for ordered indexes and range scans |
| [Ch13 · The N+1 problem and DataLoaders]({{ '/docs/13-n-plus-one-and-dataloaders/' | relative_url }}) | the book as a whole, for tail latency from fanning one request out to backend calls |
| [Ch14 · Depth limits and query cost analysis]({{ '/docs/14-depth-limits-and-query-cost/' | relative_url }}) | the book as a whole, for load, response-time percentiles and tail latency |
| [Ch16 · Caching]({{ '/docs/16-caching/' | relative_url }}) | the book as a whole, for systems of record and derived data |

## Specifications and primary docs

| Title | Author(s) | Focus |
|---|---|---|
| [GraphQL specification](https://spec.graphql.org/) | GraphQL Foundation | Type system, validation, execution, response format |
| [GraphQL over HTTP](https://http-spec.graphql.org/draft/) | GraphQL Foundation (working draft) | Request encoding, GET vs POST, media types, status codes |
| [GraphQL Cursor Connections](https://relay.dev/graphql/connections.htm) | Relay | Connection, edge, and `PageInfo` shapes for pagination |
| [Quarkus SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) | Quarkus | `quarkus-smallrye-graphql` specifics for the Quarkus stack |
| [Strawberry documentation](https://strawberry.rocks/docs) | Strawberry | Code-first schemas and the FastAPI integration for the Python stack |
| [GraphQL Inspector](https://the-guild.dev/graphql/inspector/docs) | The Guild | Schema diffing and the breaking-change gate |
| [GraphQL ESLint](https://the-guild.dev/graphql/eslint/docs) | The Guild | Schema linting rules for the canonical SDL |

These titles inform this site's coverage and rigor only — nothing in these chapters
or the runnable examples copies text or code from them.
