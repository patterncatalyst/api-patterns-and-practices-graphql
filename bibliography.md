---
title: "Bibliography"
layout: plan
permalink: /bibliography/
description: "The reference works this site's coverage and rigor draw on. Nothing here is ported from them."
---

This site's chapter arc, pattern coverage, and level of rigor draw on a small set
of books and primary specifications on GraphQL and data-intensive systems. They're
reference works, not sources, and no text or code from any of them is reproduced
here. If a topic in this site is useful to you, these are where to go deeper.

## Books

<table class="bib bib--books">
  <colgroup><col style="width:62%"><col style="width:24%"><col style="width:14%"></colgroup>
  <thead><tr><th>Title</th><th>Author(s)</th><th>Year</th></tr></thead>
  <tbody>
    <tr><td><a href="https://www.manning.com/books/graphql-in-action" rel="noopener"><em>GraphQL in Action</em></a><br><small>Manning. Edition: 1st. The language, schema design, resolvers, data fetching, mutations, client use</small></td><td>Samer Buna</td><td>2021</td></tr>
    <tr><td><a href="https://www.packtpub.com/en-us/product/graphql-best-practices-9781835467145" rel="noopener"><em>GraphQL Best Practices</em></a><br><small>Packt. Edition: 1st. Schema design, error descriptions, query limits and security</small></td><td>Artur Czemiel</td><td>2024</td></tr>
    <tr><td><a href="https://www.manning.com/books/fullstack-graphql-applications" rel="noopener"><em>Full Stack GraphQL Applications</em></a><br><small>Manning. Edition: 1st. End-to-end applications, authorization, pagination, React and Apollo clients</small></td><td>William Lyon</td><td>2022</td></tr>
    <tr><td><a href="https://www.oreilly.com/library/view/designing-data-intensive-applications/9781098119058/" rel="noopener"><em>Designing Data-Intensive Applications</em>, 2nd ed.</a><br><small>O'Reilly. Edition: 2nd. Data-layer rigor behind pagination, batching, query cost, caching</small></td><td>Martin Kleppmann, Chris Riccomini</td><td>2026</td></tr>
  </tbody>
</table>

## Where each book is cited

Each chapter's closing section names the parts of these books that cover the same ground.

### *GraphQL in Action*

<table class="bib">
  <colgroup><col style="width:44%"><col style="width:56%"></colgroup>
  <thead><tr><th>Chapter here</th><th>Chapter of the book</th></tr></thead>
  <tbody>
    <tr><td><a href="{{ '/docs/01-from-rest-and-rpc-to-graphql/' | relative_url }}" rel="noopener">Chapter 1 · From REST/RPC to GraphQL</a></td><td>the book as a whole, for language and execution model</td></tr>
    <tr><td><a href="{{ '/docs/02-graphql-decision-framework/' | relative_url }}" rel="noopener">Chapter 2 · The GraphQL decision framework</a></td><td>the book as a whole, for schema and resolver design</td></tr>
    <tr><td><a href="{{ '/docs/03-sdl-and-the-type-system/' | relative_url }}" rel="noopener">Chapter 3 · SDL and the type system in depth</a></td><td>Chapter 1, "Introduction to GraphQL", and chapter 4, "Designing a GraphQL schema"</td></tr>
    <tr><td><a href="{{ '/docs/04-nullability-and-null-propagation/' | relative_url }}" rel="noopener">Chapter 4 · Nullability and null propagation</a></td><td>Chapter 4, "Designing a GraphQL schema"</td></tr>
    <tr><td><a href="{{ '/docs/05-contract-first-schemas/' | relative_url }}" rel="noopener">Chapter 5 · Schema-first / contract-first</a></td><td>Chapter 4, "Designing a GraphQL schema"</td></tr>
    <tr><td><a href="{{ '/docs/06-the-execution-model/' | relative_url }}" rel="noopener">Chapter 6 · The execution model</a></td><td>Chapter 1, "Introduction to GraphQL", and chapter 5, "Implementing schema resolvers"</td></tr>
    <tr><td><a href="{{ '/docs/07-queries-and-resolvers/' | relative_url }}" rel="noopener">Chapter 7 · Queries and resolvers</a></td><td>Chapter 3, "Customizing and organizing GraphQL operations", chapter 5, "Implementing schema resolvers", and chapter 6, "Working with database models and relations"</td></tr>
    <tr><td><a href="{{ '/docs/08-mutations-and-input-types/' | relative_url }}" rel="noopener">Chapter 8 · Mutations and input types</a></td><td>Chapter 8, "Implementing mutations"</td></tr>
    <tr><td><a href="{{ '/docs/09-error-handling/' | relative_url }}" rel="noopener">Chapter 9 · Error handling</a></td><td>Chapter 8, "Implementing mutations"</td></tr>
    <tr><td><a href="{{ '/docs/10-schema-design-patterns/' | relative_url }}" rel="noopener">Chapter 10 · Schema design patterns</a></td><td>Chapter 4, "Designing a GraphQL schema"</td></tr>
    <tr><td><a href="{{ '/docs/13-n-plus-one-and-dataloaders/' | relative_url }}" rel="noopener">Chapter 13 · The N+1 problem and DataLoaders</a></td><td>Chapter 7, "Optimizing data fetching"</td></tr>
    <tr><td><a href="{{ '/docs/16-caching/' | relative_url }}" rel="noopener">Chapter 16 · Caching</a></td><td>Chapter 7, "Optimizing data fetching"</td></tr>
    <tr><td><a href="{{ '/docs/22-client-integration/' | relative_url }}" rel="noopener">Chapter 22 · Client integration</a></td><td>the book as a whole, for consuming a GraphQL API from a client</td></tr>
  </tbody>
</table>

### *GraphQL Best Practices*

<table class="bib">
  <colgroup><col style="width:47%"><col style="width:53%"></colgroup>
  <thead><tr><th>Chapter here</th><th>Chapter of the book</th></tr></thead>
  <tbody>
    <tr><td><a href="{{ '/docs/09-error-handling/' | relative_url }}" rel="noopener">Chapter 9 · Error handling</a></td><td>the book as a whole, for error descriptions</td></tr>
    <tr><td><a href="{{ '/docs/10-schema-design-patterns/' | relative_url }}" rel="noopener">Chapter 10 · Schema design patterns</a></td><td>the book as a whole, for naming, enums, interfaces and pagination</td></tr>
    <tr><td><a href="{{ '/docs/11-evolution-and-versioning/' | relative_url }}" rel="noopener">Chapter 11 · Evolution and versioning</a></td><td>the book as a whole, for schema design</td></tr>
    <tr><td><a href="{{ '/docs/14-depth-limits-and-query-cost/' | relative_url }}" rel="noopener">Chapter 14 · Depth limits and query cost analysis</a></td><td>the book as a whole, for query limits</td></tr>
    <tr><td><a href="{{ '/docs/17-transport-security-and-introspection/' | relative_url }}" rel="noopener">Chapter 17 · Transport security and introspection control</a></td><td>the book as a whole, for attacks on GraphQL servers and schema design for security</td></tr>
  </tbody>
</table>

### *Full Stack GraphQL Applications*

<table class="bib">
  <colgroup><col style="width:43%"><col style="width:57%"></colgroup>
  <thead><tr><th>Chapter here</th><th>Chapter of the book</th></tr></thead>
  <tbody>
    <tr><td><a href="{{ '/docs/01-from-rest-and-rpc-to-graphql/' | relative_url }}" rel="noopener">Chapter 1 · From REST/RPC to GraphQL</a></td><td>the book as a whole, for the end-to-end application view</td></tr>
    <tr><td><a href="{{ '/docs/02-graphql-decision-framework/' | relative_url }}" rel="noopener">Chapter 2 · The GraphQL decision framework</a></td><td>the book as a whole, for clients and authorization</td></tr>
    <tr><td><a href="{{ '/docs/12-connections-and-pagination/' | relative_url }}" rel="noopener">Chapter 12 · Connections and pagination</a></td><td>Chapter 9, "Advanced GraphQL considerations"</td></tr>
    <tr><td><a href="{{ '/docs/18-authn-and-authz/' | relative_url }}" rel="noopener">Chapter 18 · AuthN and AuthZ</a></td><td>Chapter 7, "Adding authorization and authentication"</td></tr>
    <tr><td><a href="{{ '/docs/22-client-integration/' | relative_url }}" rel="noopener">Chapter 22 · Client integration</a></td><td>the book as a whole, for a React client on Apollo Client</td></tr>
    <tr><td><a href="{{ '/docs/27-the-final-project/' | relative_url }}" rel="noopener">Chapter 27 · The final project</a></td><td>Chapter 7, "Adding authorization and authentication", and chapter 9, "Advanced GraphQL considerations"</td></tr>
  </tbody>
</table>

### *Designing Data-Intensive Applications*, 2nd edition

<table class="bib">
  <colgroup><col style="width:43%"><col style="width:57%"></colgroup>
  <thead><tr><th>Chapter here</th><th>Chapter of the book</th></tr></thead>
  <tbody>
    <tr><td><a href="{{ '/docs/11-evolution-and-versioning/' | relative_url }}" rel="noopener">Chapter 11 · Evolution and versioning</a></td><td>the book as a whole, for backward and forward compatibility</td></tr>
    <tr><td><a href="{{ '/docs/12-connections-and-pagination/' | relative_url }}" rel="noopener">Chapter 12 · Connections and pagination</a></td><td>the book as a whole, for ordered indexes and range scans</td></tr>
    <tr><td><a href="{{ '/docs/13-n-plus-one-and-dataloaders/' | relative_url }}" rel="noopener">Chapter 13 · The N+1 problem and DataLoaders</a></td><td>the book as a whole, for tail latency from fanning one request out to backend calls</td></tr>
    <tr><td><a href="{{ '/docs/14-depth-limits-and-query-cost/' | relative_url }}" rel="noopener">Chapter 14 · Depth limits and query cost analysis</a></td><td>the book as a whole, for load, response-time percentiles and tail latency</td></tr>
    <tr><td><a href="{{ '/docs/16-caching/' | relative_url }}" rel="noopener">Chapter 16 · Caching</a></td><td>the book as a whole, for systems of record and derived data</td></tr>
  </tbody>
</table>

## Specifications and primary docs

<table class="bib">
  <colgroup><col style="width:30%"><col style="width:23%"><col style="width:47%"></colgroup>
  <thead><tr><th>Title</th><th>Author(s)</th><th>Focus</th></tr></thead>
  <tbody>
    <tr><td><a href="https://spec.graphql.org/" rel="noopener">GraphQL specification</a></td><td>GraphQL Foundation</td><td>Type system, validation, execution, response format</td></tr>
    <tr><td><a href="https://http-spec.graphql.org/draft/" rel="noopener">GraphQL over HTTP</a></td><td>GraphQL Foundation (working draft)</td><td>Request encoding, GET vs POST, media types, status codes</td></tr>
    <tr><td><a href="https://relay.dev/graphql/connections.htm" rel="noopener">GraphQL Cursor Connections</a></td><td>Relay</td><td>Connection, edge, and <code>PageInfo</code> shapes for pagination</td></tr>
    <tr><td><a href="https://quarkus.io/guides/smallrye-graphql" rel="noopener">Quarkus SmallRye GraphQL guide</a></td><td>Quarkus</td><td><code>quarkus-smallrye-graphql</code> specifics for the Quarkus stack</td></tr>
    <tr><td><a href="https://strawberry.rocks/docs" rel="noopener">Strawberry documentation</a></td><td>Strawberry</td><td>Code-first schemas and the FastAPI integration for the Python stack</td></tr>
    <tr><td><a href="https://the-guild.dev/graphql/inspector/docs" rel="noopener">GraphQL Inspector</a></td><td>The Guild</td><td>Schema diffing and the breaking-change gate</td></tr>
    <tr><td><a href="https://the-guild.dev/graphql/eslint/docs" rel="noopener">GraphQL ESLint</a></td><td>The Guild</td><td>Schema linting rules for the canonical SDL</td></tr>
  </tbody>
</table>

These titles inform this site's coverage and rigor only; nothing in these chapters
or the runnable examples copies text or code from them.
