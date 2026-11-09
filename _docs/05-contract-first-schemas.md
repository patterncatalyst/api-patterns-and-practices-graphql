---
title: "Schema-first / contract-first"
order: 5
part: "The Schema: SDL & the Type System"
description: "Keep two code-first schemas aligned with one canonical SDL: export each stack's schema, diff it in both directions with GraphQL Inspector, lint the contract, and watch seeded drift fail the check."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Contrast SDL-first and code-first schema ownership and name the typical failure mode of each.
- Export the schema each stack builds (`GET /graphql/schema.graphql` on Quarkus, `strawberry export-schema` on Python).
- Run a two-direction `graphql-inspector diff` (live-to-canonical and canonical-to-live) and explain why one direction misses a tightened field.
- Filter framework-injected noise (directives, scalars) out of a conformance diff without masking real drift.
- Lint the canonical SDL with GraphQL ESLint and gate it against `main` with a breaking-change check.

## Why this matters

A schema that many unknown clients read is only an asset while it stays one schema. Two services that each build their own can disagree about a nullable field or a scalar and nobody notices until a client breaks. The fix is a canonical SDL in `contracts/schema/`, plus a gate that compares what each stack serves with it on every run.

## Two ways to own a schema

In the **SDL-first** approach a `.graphql` file is the source. The server loads it and binds a resolver to each field by name, or a generator emits types for the server to implement. Reviewers read the file and the code has to match it. The typical failure: the schema describes a field the resolvers never fill, and the mismatch shows up at runtime or not at all.

In the **code-first** approach the application code is the source. Annotations or decorators build the schema at startup, and the SDL is something you print from the running service. The typical failure: the schema changes as a side effect of a refactor, such as a renamed getter, a field that went from `Itinerary` to `Itinerary | None`, or a framework upgrade that rewrites a description. Nobody wrote the change down, so nobody reviewed it.

gRPC solves this with a generator: in [Contract-first with Buf](https://patterncatalyst.github.io/api-patterns-and-practices-grpc/docs/05-contract-first-with-buf/) the `.proto` file is the single source and `buf generate` emits the types for both stacks. GraphQL has no such step. Each stack decides for itself whether a bare field is nullable, which scalar a `datetime` becomes, in which order fields print and whether a description gets a suffix. Those are details a client-visible contract has to pin down.

## Code-first with a canonical yardstick

| Decision | Choice |
|---|---|
| Contract | The canonical SDL in `contracts/schema/shipping/*.graphql`. Reviewers read it, and a breaking-change gate checks every change to it. |
| Implementation | Both stacks stay code-first: SmallRye GraphQL builds its schema from annotated records, Strawberry from decorated classes. |
| Gate | Each stack's schema is diffed against the canonical SDL on every verification run, locally and in CI. |

Generating server types from the SDL was rejected. It adds a generator to each build, and the generated types still pass through each framework's own mapping of scalars, wrappers and descriptions, so the places where the stacks can differ only move. A gate that compares the schema each stack serves catches the difference wherever it comes from.

{% include excalidraw.html file="05-contract-loop" alt="Data flow of the contract loop. On the left, two blue boxes, Quarkus code with its annotations and Strawberry code with its decorators, each lead right into an export step: a GET of /graphql/schema.graphql on Quarkus and the strawberry command-line export-schema on app.schema:schema for Python. Each export step leads with an amber arrow to an SDL file box, quarkus.graphql and python.graphql, and a dashed double-headed arrow between those two boxes is labelled same schema. Amber arrows run from both files into a light amber box on the right, graphql-inspector diff, which describes two directions, live to canonical for extra or tighter surface and canonical to live for changed rather than absent surface. A box above it holds contracts/schema, the canonical SDL, and feeds the diff with an amber arrow labelled both directions. An amber arrow leads from the diff down to a box, gate result, which reads pass or fail naming the field. In a band along the bottom, titled gates on the canonical SDL itself, a central box for contracts/schema has an arrow left to npm run lint, which checks descriptions and naming, and an arrow right to npm run breaking, which compares the canonical SDL with origin/main for breaking changes." caption="Figure 5.1: The contract loop. Code builds the schema, the export makes it a file, and the diff compares it with the canonical SDL in both directions." %}

In CI a `contracts` job runs `npm run lint` and, after fetching `origin/main`, `npm run breaking`. An `examples` job runs each `verify.sh`, which calls the same pinned `graphql-inspector`. A pull request fails when either job fails.

## Exporting the schema each stack builds

The conformance check needs the schema as a file, because a file can be diffed, copied and committed.

**Quarkus.** SmallRye GraphQL serves its schema at `GET /graphql/schema.graphql`, on the endpoint's port. One option makes the export declare every scalar, so the references from `Cargo` to `TrackingId` and `DateTime` resolve when `graphql-inspector` loads the file:

```properties
quarkus.smallrye-graphql.schema-include-scalars=true
```

The file then declares `DateTime`, `TrackingId` and `UnLocode`, plus SmallRye's `BigDecimal` and `BigInteger`, which no field uses. The options `schema-include-directives`, `schema-include-introspection-types` and `schema-include-schema-definition` stay at their defaults, and none of them changes what the checks compare.

**Python.** Strawberry's exporter ships behind the `cli` extra (`strawberry-graphql[cli]`). The export is one command, run in the container that holds the application's code and dependencies:

```bash
strawberry export-schema app.schema:schema
```

The argument is a module path and the schema object's name. Inside a process that already holds the schema, `schema.as_str()` returns the same text.

The two files look different. SmallRye prints fields alphabetically with one-line descriptions in plain quotes. Strawberry prints them in declaration order with `"""` blocks. A text diff is all noise, so the checks hand both files to a tool that compares schemas, never lines.

One difference is semantic. Introspection and the export are two views of one schema, and they disagree on `@specifiedBy`. Strawberry prints the directive on the scalar. SmallRye's export prints the scalar without it, with or without `schema-include-directives`:

```graphql
scalar UnLocode @specifiedBy(url: "https://unece.org/trade/uncefact/unlocode")
```

Both stacks report the URL through introspection as `specifiedByURL`, which the Introspection section of the [GraphQL specification](https://spec.graphql.org/) defines on `__Type`. The diff reads types, fields, arguments, enum values and descriptions, so it sees the directive only in the Strawberry file. Query `specifiedByURL` directly to check a scalar's metadata.

## Diffing in two directions

`graphql-inspector diff <old> <new>` lists every change between two schemas and classifies each as breaking, dangerous or safe from the point of view of a client of the old schema. It exits non-zero on a breaking change. A pointer can be a URL (read by introspection), a file or a glob of SDL.

The classification depends on which schema is old, so a conformance check runs the tool twice.

| Direction | Old / new | A breaking change means | Example change line |
|---|---|---|---|
| Live to canonical | stack / contract | The stack exposes more or tighter surface than the contract. | `Field weightKg was removed from object type Cargo`; `Field Cargo.itinerary changed type from Itinerary! to Itinerary` |
| Canonical to live | contract / stack | What the stack serves differs from the contract. | `Field Cargo.trackingId changed type from TrackingId! to TrackingId` |

Canonical to live fails on any removal except one: this slice serves only part of the schema, so a whole type, a whole output field or a whole mutation or subscription root may be absent. A removed enum value, argument, input field or union member fails. A changed description on a field, argument or type that both sides have fails too, although the tool marks it safe.

{% include excalidraw.html file="05-two-direction-diff" alt="Two side-by-side panels. The left panel, titled live to canonical, asks whether the stack exposes more or tighter surface than the contract. It has three rows, each with a white case box on the left and a result box on the right: an extra field, weightKg Float on Cargo, leads with an amber arrow to a light amber box that reads fail, breaking, field weightKg was removed from object type Cargo; a tightened output, itinerary as Itinerary non-null, leads to a light amber box that reads fail, breaking, field Cargo.itinerary changed type from Itinerary non-null to Itinerary; and a slice case, HandlingEvent not served, leads with a dashed arrow to a plain box reading safe, ignored, type HandlingEvent was added. A note below states that the opposite diff lists a tighter output as safe, so one direction would pass a tightened field. The right panel, titled canonical to live, asks whether what the stack serves differs from the contract. It has four rows: the slice case leads by a dashed arrow to a dashed box reading allowed, slice removal, type HandlingEvent was removed; a loosened output, trackingId as TrackingId, leads to a light amber box reading fail, drift, field Cargo.trackingId changed type from TrackingId non-null to TrackingId; a removed enum value, UNKNOWN, leads to a light amber box reading fail, drift, enum value UNKNOWN was removed from enum TransportStatus; and a changed description leads to a light amber box reading fail, drift, though marked safe. A note below states that only whole types, output fields and roots may be absent." caption="Figure 5.2: The two directions of the diff. Each seeded drift is reported by one of them, and only the canonical-to-live direction may ignore a slice." %}

One direction alone is not enough, and a tightened field shows why. Someone changes `Cargo.itinerary` from `Itinerary` to `Itinerary!` because every seeded cargo has a route. The canonical-to-live diff reports `✔ Field Cargo.itinerary changed type from Itinerary to Itinerary!` with no breaking marker, because a field that never returns null is easier for a client. Only live-to-canonical reports it as breaking. It matters because the nullability fuse is gone. When the routing service fails for one cargo, a nullable `itinerary` costs one field. A non-null one passes the `null` up to `Query.cargo`, and the client loses the whole cargo.

## Framework noise

A framework-built schema contains things the author never wrote. Live Quarkus introspection compared with the canonical SDL starts with these lines, before it reaches anything in the slice:

```text
[log] ✖  Directive constraint was removed
[log] ✖  Directive defer was removed
[log] ✖  Directive experimental_disableErrorPropagation was removed
[log] ✖  Directive rolesAllowed was removed
[log] ✖  Type BigDecimal was removed
[log] ✖  Type BigInteger was removed
```

SmallRye registers four directives and two scalars that no field uses. They aren't drift and aren't part of the contract. The check filters them by exact name:

```bash
LGTM_SDL_FRAMEWORK_DIRECTIVES="${LGTM_SDL_FRAMEWORK_DIRECTIVES:-constraint|defer|experimental_disableErrorPropagation|rolesAllowed}"
LGTM_SDL_FRAMEWORK_TYPES="${LGTM_SDL_FRAMEWORK_TYPES:-BigDecimal|BigInteger}"
```

Never filter by pattern. A rule such as "ignore every added directive" hides the day a developer adds an `@internal` directive the canonical SDL doesn't declare, which is the change the check exists to see. When a framework upgrade registers a new directive, the check fails, someone reads the change line, and the name goes on the list or the setting that registered it is turned off.

The same filter applies when the two exports are compared with each other. That comparison, Quarkus against Python and Python against Quarkus, makes "two stacks, one schema" a property the check checks.

## Linting the contract

Diffing compares two schemas and says nothing about whether either is any good. GraphQL ESLint checks the canonical SDL on its own:

```bash
npm --prefix contracts run lint
```

The configuration starts from the plugin's `schema-recommended` rules and adjusts two. The contract requires descriptions on every type, field, argument and enum value, not only types and root fields, which gives the diff's description check something to compare. And `strict-id-in-types` requires an `id` field on entity types, with exceptions written down in `eslint.config.mjs` for value objects such as `Leg` and `Delivery` and for names ending in `Connection`, `Edge`, `Info`, `Payload` and `Error`. A new type that should have an identity but doesn't is a lint failure.

The lint runs on the canonical SDL, not the exports. The contract is what people review, and the diff holds the exports to it: a description missing in code fails as a description change once the stack serves the field.

## What the diff cannot see

| Gap | Why | Covered by |
|---|---|---|
| Behavior | The diff compares types and arguments and never runs a query. A stack that serves `Cargo.delivery` with the right type and the wrong status passes. | Assertions on real responses, such as exact timestamps and null-propagation paths. |
| `specifiedByURL` | Absent from the SmallRye file. | An introspection query on both stacks. |
| Default values | Classified dangerous, not breaking, and conformance fails only on breaking lines and descriptions. | An explicit assertion once an input type is served. |
| Authorization, cost limits, caching hints, resolver contents | Outside the SDL. | Each gated on its own. |

A copy of the canonical SDL with `first: Int = 10` added to `Query.cargos` produces this and exits zero:

```text
[log] ⚠  Default value 10 was added to argument first on field Query.cargos
[success] No breaking changes detected
```

That is the right classification for evolution, since existing queries keep working, and the wrong one for conformance, since the stack now differs from the contract. Keep explicit assertions beside the conformance check: the diff covers the structural surface cheaply, and the assertions cover what it cannot see.

## Seeing the check fire

A check that has never failed proves nothing. Five drifts are seeded into copies of each stack's export, and the conformance check must fail on each, on both stacks. Each is a `sed` edit scoped to the `Cargo` type, so it cannot touch the `Query.cargo` argument that is also spelled `trackingId: TrackingId!`.

| Case | Edit to the export | Reported by | Needle |
|---|---|---|---|
| tighten | `itinerary: Itinerary` becomes `Itinerary!` | live to canonical | `Cargo.itinerary` |
| loosen | `trackingId: TrackingId!` becomes `TrackingId` | canonical to live | `Cargo.trackingId` |
| extra field | `weightKg: Float` added to `Cargo` | live to canonical | `weightKg` |
| enum value | `UNKNOWN` removed from `TransportStatus` | canonical to live | `UNKNOWN` |
| description | `The public tracking identifier.` becomes `Tracking id.` | canonical to live | `Cargo.trackingId` |

Three rules keep the fixtures meaningful.

- **The fixture must apply.** After each edit, `cmp -s` compares the export with the edited copy. If they are identical the pattern matched nothing, perhaps because an upgrade changed how a field prints, and a copy identical to the export conforms. An unchanged copy fails the fixture instead of passing vacuously.
- **The needle must be in the change line.** A drift check passes only when conformance fails and a line of `graphql-inspector`'s report contains the needle. A file that didn't parse, or an unrelated change, proves nothing.
- **A tool error is not drift.** Deleting only the line `UNKNOWN` leaves the value's description with nothing to describe, the file stops being valid SDL, and the tool reports a syntax error (`Expected Name, found "}"`). The fixture removes the value together with its description. A comparison that didn't run is a failure, never a pass.

A run of the tighten case against the Python export prints:

```text
[log] ✖  Field Cargo.itinerary changed type from Itinerary! to Itinerary
[error] Detected 1 breaking change
```

## Where the breaking gate fits

Two gates look alike and answer different questions. Conformance asks whether the stacks match the contract. The breaking-change gate, `npm run breaking`, asks whether the contract itself changed in a way that breaks an existing client.

It extracts `contracts/schema/` from a base ref, `origin/main` by default, and diffs that copy against the working tree. A removed field, a changed type or a removed enum value fails, and additive changes pass. When the base ref contains no schema yet, as on the first introduction of the contract, the command prints a message and skips. A base ref that doesn't resolve is an error, so it can't pass by accident. Setting `BASE_DIR` compares against a directory instead of a git ref.

A change to the canonical SDL goes through `npm run breaking`. A change to either stack goes through conformance against the canonical SDL.

> **🤖 Explore with your agent**
>
> "In `examples/05-contract-first`, add a `weightKg: Float` field to `Cargo` on both stacks without touching `contracts/schema/shipping/`. Run `graphql-inspector diff` between each stack's export and the canonical SDL in both directions, and tell me which direction reports it and what the change line says. Then add the field to the canonical SDL with a description so the check passes."
>
> Check: the live-to-canonical diff prints `Field weightKg was removed from object type Cargo`; after the SDL edit `bash examples/05-contract-first/verify.sh` ends in `PASS`.

## Build, run, observe

Quarkus is on `8150` and Python on `8151`; both answer the tracking query with the same bytes.

```bash
docker compose -f examples/05-contract-first/compose.yaml up -d --build
curl -s localhost:8150/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId delivery { transportStatus } } }"}'
```

```json
{"data":{"cargo":{"trackingId":"ABC123","delivery":{"transportStatus":"ONBOARD_CARRIER"}}}}
```

Export the schema each stack builds and compare the scalars, where the two files disagree:

```bash
curl -fsS localhost:8150/graphql/schema.graphql | grep -n '^scalar'
```

```text
187:scalar BigDecimal
190:scalar BigInteger
193:scalar DateTime
199:scalar TrackingId
205:scalar UnLocode
```

```bash
docker compose -p gql-ch05-contract exec -T python strawberry export-schema app.schema:schema | grep -n '^scalar'
```

```text
48:scalar DateTime @specifiedBy(url: "https://www.rfc-editor.org/rfc/rfc3339")
220:scalar TrackingId
244:scalar UnLocode @specifiedBy(url: "https://unece.org/trade/uncefact/unlocode")
```

Introspection reports the URL on both stacks, even where the file doesn't print it:

```bash
curl -s localhost:8150/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ __type(name: \"UnLocode\") { kind specifiedByURL } }"}'
```

```json
{"data":{"__type":{"kind":"SCALAR","specifiedByURL":"https://unece.org/trade/uncefact/unlocode"}}}
```

Diff the live Python endpoint against the canonical SDL, then break a copy of its export and diff that:

```bash
cd contracts
npx --no-install graphql-inspector diff http://localhost:8151/graphql 'schema/**/*.graphql' | tail -3
```

```text
[log] ✔  Type UserError was added
[log] ✔  Type UserErrorCode was added
[success] No breaking changes detected
```

```bash
docker compose -p gql-ch05-contract exec -T python strawberry export-schema app.schema:schema > /tmp/python.graphql
sed -e '/^type Cargo implements Node {/,/^}/ s/^\(  itinerary: Itinerary\)$/\1!/' /tmp/python.graphql > /tmp/drift.graphql
npx --no-install graphql-inspector diff /tmp/drift.graphql 'schema/**/*.graphql' | grep -E '✖|error'
```

```text
[log] ✖  Field Cargo.itinerary changed type from Itinerary! to Itinerary
[error] Detected 1 breaking change
```

`bash examples/05-contract-first/verify.sh` runs the whole check on both stacks. It checks the values above, compares each export and the live introspection with the canonical SDL, compares the two exports, lints the contract, and runs the five seeded drifts. It prints `PASS` only when both stacks hold and every drift fails the check. It needs Docker Engine with the `docker compose` plugin and Node.

Experiments:

- **Tighten a field.** Make `itinerary` non-null on `Cargo` in a copy of an export. Only the live-to-canonical diff reports it as breaking.
- **Edit a description.** Change `The public tracking identifier.` to `Tracking id.` The canonical-to-live check fails although the tool marks the change safe.
- **Remove only the enum line.** Delete `UNKNOWN` without its description. The tool reports a syntax error and the run fails instead of passing.

> **Decision**
>
> Keep both stacks code-first and make the canonical SDL the contract: diff each stack's export and live schema against it in both directions on every run, filter framework names by exact name only, lint the SDL itself, and keep explicit assertions for what a structural diff cannot see (behavior, `specifiedByURL`, default values). A change to the SDL goes through the breaking-change gate; a change to a stack goes through conformance.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): "Designing a GraphQL schema" covers the schema-ownership trade-offs. Listed on the [Bibliography](../../bibliography/) page.
- *Cloud Native Design Patterns*, [API Registry](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/09-api-registry/): the broader pattern of a canonical contract checked against what services serve.
- [GraphQL Inspector](https://the-guild.dev/graphql/inspector/docs): the two-direction diff and breaking-change tooling.
- [GraphQL ESLint](https://the-guild.dev/graphql/eslint): the linter that enforces description and naming rules on the canonical SDL.
- The Type System and Introspection sections of the [GraphQL specification](https://spec.graphql.org/) define the schema and `specifiedByURL`.
