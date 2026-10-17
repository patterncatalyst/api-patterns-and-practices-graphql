# API Patterns and Practices: GraphQL

Designing GraphQL APIs well, with runnable examples in **Quarkus** (SmallRye GraphQL) and
**Python** (Strawberry) against one canonical SDL contract. A chapter-based Jekyll site with
a runnable example for each hands-on chapter.

Third of four per-style sites in the *API Patterns & Practices* series:
[REST](https://github.com/patterncatalyst/api-patterns-and-practices-rest) →
[gRPC](https://github.com/patterncatalyst/api-patterns-and-practices-grpc) →
GraphQL → WebSockets. The shipping and cargo domain runs through the whole series. Here,
GraphQL is the read-oriented tracking view.

Read it at <https://patterncatalyst.github.io/api-patterns-and-practices-graphql/>.

## What's here

- **28 chapters (Ch0–Ch27) and Appendix A**, from the decision lens and the SDL type system
  through resolvers, errors, schema evolution, pagination and dataloaders, query cost,
  persisted queries and caching, security, observability, federation, subscriptions, client
  integration, testing and debugging, to a final project that ties the system together.
- **Both stacks, first-class.** Every hands-on chapter ships a Quarkus example and a Python
  example, both code-first, against the same schema.
- **Contract-first.** One canonical SDL under [`contracts/`](contracts/) is the source of truth.
  [graphql-inspector](https://the-guild.dev/graphql/inspector) diffs each stack's exported
  schema against it and gates breaking changes.
- **Behavioural verification.** Every example ships a `verify.sh` that calls the running
  services and asserts response semantics, not only a status code.
- **Three tiers.** Docker Compose, minikube (Kubernetes) and OpenShift Local (Appendix A).
- **Three decks:** a 100-level GraphQL concepts deck plus Quarkus and Python implementation decks (`presentation/`).

## Domain

The canonical shipping and cargo domain used across the series: `Cargo`, `Voyage`, route
legs, `Location` (UN/LOCODE) and handling events. GraphQL serves the tracking view, one
query-shaped graph that joins cargo, route legs and handling events, so a client asks for
exactly the fields it needs in a single round trip.

## Build locally

Jekyll builds in the `ruby:3.3` container, which matches CI. `<bundle-dir>` is any
writable directory that caches the gems.

```bash
docker run --rm -u $(id -u):$(id -g) -e HOME=/tmp -e BUNDLE_PATH=/bundle \
  -v "$PWD":/site:Z -v <bundle-dir>:/bundle:Z -w /site ruby:3.3 \
  sh -c 'bundle install && bundle exec jekyll build --trace'
```

## Run an example

Each example runs both stacks on Docker Compose and checks them against the contract:

```bash
bash examples/05-contract-first/verify.sh
```

## Layout

| Path | What |
|---|---|
| `_docs/` | The chapters and Appendix A (Markdown). |
| `contracts/` | The canonical SDL and the breaking-change gate. |
| `examples/` | One runnable example per hands-on chapter, Quarkus and Python, each with `verify.sh`. |
| `diagrams/` | One spec per figure; each renders to an SVG and an Excalidraw file. |
| `scripts/` | Static validation, diagram generation and the word-count gate. |
| `presentation/` | The three `.pptx` decks and their builders (concepts, Quarkus, Python). |

## Licence

MIT, for prose and code.
