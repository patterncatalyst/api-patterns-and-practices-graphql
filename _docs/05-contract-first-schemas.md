---
title: "Schema-first / contract-first"
order: 5
part: "The Schema: SDL & the Type System"
description: "How the tracking view keeps two code-first schemas aligned with one canonical SDL: export each stack's schema, diff it in two directions with GraphQL Inspector, lint the contract, and watch seeded drift fail the gate."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Contrast SDL-first and code-first schema ownership and name the typical failure mode of each.
- Export the schema each stack actually builds (`GET /graphql/schema.graphql` on Quarkus, `strawberry export-schema` on Python).
- Run a two-direction `graphql-inspector diff` (live-to-canonical and canonical-to-live) and explain why checking only one direction misses a tightened field.
- Filter framework-injected noise (directives, scalars) out of a conformance diff without masking real drift.
- Lint the canonical SDL with GraphQL ESLint and gate it against `main` with a breaking-change check.

## Why this matters

Chapter 3 gave the tracking view a vocabulary and Chapter 4 explained what its nullability promises. Both chapters leaned on one mechanism without opening it: after every run, `verify.sh` compared the schema each stack built with the canonical SDL in `contracts/schema/`. This chapter opens it. It covers who owns the schema, how each stack exports the schema it builds, what the diff can and cannot see, and how to prove the gate works by breaking the schema and watching it fail.

The code is in `examples/05-contract-first/`. It starts from the Chapter 3 example, serves the same slice from the same seed, and adds the export, the checks around it and five seeded drifts. Its `verify.sh` asserts every value in the "On the wire" section.

## Two ways to own a schema

A GraphQL service needs a schema, and the schema has to come from somewhere. There are two sources.

In the **SDL-first** approach, a `.graphql` file is the source. The server loads it at startup and binds a resolver to each field by name, or a generator reads it and emits types for the server to implement. The file is what reviewers read, and the code has to match it.

In the **code-first** approach, the source is the application code. Annotations or decorators on classes and methods build the schema at startup, and the SDL is something you print from the running service. The code is what developers edit, and the printed schema has to be checked against something else if anyone else depends on it.

Each approach has a typical failure. An SDL-first schema can describe a field the resolvers never fill, and the mismatch shows up at runtime or not at all. A code-first schema can change as a side effect of a refactor: a renamed Java getter, a field that went from `Itinerary` to `Itinerary | None`, a framework upgrade that rewrites a description. Nobody wrote the change down, so nobody reviewed it.

The gRPC sibling of this book faces the same question and answers it with a generator. In [Contract-first with Buf](https://patterncatalyst.github.io/api-patterns-and-practices-grpc/docs/05-contract-first-with-buf/), the `.proto` file is the single source and `buf generate` emits the message and service types for both stacks, so the contract and the code cannot disagree about a field number or a type. GraphQL has no equivalent step that comes with the language. What travels on the wire is JSON shaped by the query, and what each stack decides for itself is how the schema is built: whether a bare field is nullable, which scalar a `datetime` becomes, in which order fields print, whether a description gets an extra suffix. Those are exactly the details a client-visible contract has to pin down.

## Code-first with a canonical yardstick

This book makes three decisions.

1. The canonical SDL lives in `contracts/schema/shipping/*.graphql` and is the contract. Reviewers read it, and Chapter 11 gates changes to it.
2. Both stacks stay code-first. SmallRye GraphQL builds its schema from annotated records and Strawberry builds its from decorated classes, which is the idiom each community uses and the code its developers expect to edit.
3. A drift gate ties the two together. Each stack's schema is diffed against the canonical SDL on every verification run, in CI as well as locally.

The alternative, generating server types from the SDL into either stack, was rejected. It adds a generator to each build, and the generated types still pass through each framework's own mapping rules for scalars, wrappers and descriptions, so the generator does not remove the places where the two stacks can differ. It only moves them. A gate that compares behavior-visible output catches the difference wherever it comes from.

Figure 5.1 shows the loop the example runs. Each stack builds its schema from code and exports it as an SDL file. `graphql-inspector` diffs the file against the canonical SDL in both directions, and the result is pass, or a failure whose change line names the field. The lower lane shows the two gates that apply to the canonical SDL itself: a linter that checks its quality and a breaking-change gate that checks it against `main`.

{% include excalidraw.html file="05-contract-loop" alt="Data flow of the contract loop. On the left, two blue boxes, Quarkus code with its annotations and Strawberry code with its decorators, each lead right into an export step: a GET of /graphql/schema.graphql on Quarkus and the strawberry command-line export-schema on app.schema:schema for Python. Each export step leads with an amber arrow to an SDL file box, quarkus.graphql and python.graphql, and a dashed double-headed arrow between those two boxes is labelled same schema. Amber arrows run from both files into a light amber box on the right, graphql-inspector diff, which describes two directions, live to canonical for extra or tighter surface and canonical to live for changed rather than absent surface. A box above it holds contracts/schema, the canonical SDL, and feeds the diff with an amber arrow labelled both directions. An amber arrow leads from the diff down to a box, gate result, which reads pass or fail naming the field. In a band along the bottom, titled gates on the canonical SDL itself, a central box for contracts/schema has an arrow left to npm run lint, which checks descriptions and naming, and an arrow right to npm run breaking, which compares the canonical SDL with origin/main and refers to Chapter 11." caption="Figure 5.1 — The contract loop. Code builds the schema, the export makes it a file, and the diff compares it with the canonical SDL in both directions." %}

The same arrangement runs in CI. The `contracts` job installs the pinned tooling with `npm ci` on Node 24.22.0, runs `npm run lint`, fetches `origin/main` and runs `npm run breaking`. The `examples` matrix job installs the same Node version and runs each `verify.sh`, which calls the same pinned `graphql-inspector`, with up to three attempts per example to absorb image pulls and JVM cold starts. A pull request fails when either job fails, so the contract and both implementations cannot move apart unseen.

## Exporting the schema each stack builds

The gate needs the schema as a file, because a file can be diffed, copied, edited and committed. Each stack can produce one.

**Quarkus.** SmallRye GraphQL serves the schema it built at `GET /graphql/schema.graphql`, on the same port as the endpoint. The example enables it explicitly with one option:

```properties
quarkus.smallrye-graphql.schema-include-scalars=true
```

The option makes the export declare every scalar, so that the references from `Cargo` to `TrackingId` and `DateTime` resolve when `graphql-inspector` loads the file. The file declares `DateTime`, `TrackingId` and `UnLocode`, and also SmallRye's `BigDecimal` and `BigInteger`, which no field in this slice uses. The related options `schema-include-directives`, `schema-include-introspection-types` and `schema-include-schema-definition` are left at their defaults. The first one adds the directive definitions SmallRye registers, such as `@constraint` and `@rolesAllowed`, and none of the three changes what the checks in this chapter compare.

**Python.** Strawberry ships a command-line exporter behind an extra, so the dependency in `pyproject.toml` becomes `strawberry-graphql[cli]==0.335.0`. Resolving it adds `typer`, `rich` and a handful of their dependencies to `uv.lock`. With the extra installed, the export is one command:

```bash
strawberry export-schema app.schema:schema
```

The argument is a module path and the name of the schema object, `schema` in `app/schema.py`. The command runs inside the container, because that is where the application's code and dependencies are installed, and `verify.sh` reaches it with `docker compose exec`. No helper script is needed. Inside a process that already holds the schema object, `schema.as_str()` returns the same text.

Both exports are SDL, and the two files still look different. SmallRye prints fields in alphabetical order and puts a one-line description in plain quotes, `"…"`. Strawberry prints them in declaration order and writes every description as a `"""` block. A text diff of the two files is full of noise that means nothing, which is why the checks never text-diff the exports and always hand them to a tool that compares schemas rather than lines.

A second difference is semantic. Introspection and the export are two views of the same schema, and they do not agree on `@specifiedBy`. Strawberry prints the directive on the scalar, and SmallRye's export prints the scalar without it, with or without `schema-include-directives`:

```graphql
scalar UnLocode @specifiedBy(url: "https://unece.org/trade/uncefact/unlocode")
```

Both stacks report the URL through introspection as `specifiedByURL`: SmallRye because `ContractSchemaDetails` sets it on the scalar object, Strawberry because the scalar declares `specified_by_url`. The URL is present in the introspection result and absent from the SmallRye file. The diff reads types, fields, arguments, enum values and descriptions, so it sees the directive only in an SDL file, and only the Strawberry one. The Introspection section of the [GraphQL specification](https://spec.graphql.org/) defines `specifiedByURL` as a field of `__Type`. Each view carries part of a scalar's metadata, so `verify.sh` asks for `specifiedByURL` directly.

## Diffing in two directions

`graphql-inspector diff <old> <new>` reports every change between two schemas and classifies each as breaking, dangerous or safe from the point of view of a client of the old schema. It exits non-zero when it finds a breaking change. Each pointer can be a URL, which it reads by introspection, or a file or glob of SDL.

The classification depends on which schema is old, so a conformance check that wants to catch drift both ways has to run the tool twice. `assert_sdl_conforms` in `lib.sh` does:

- **Live to canonical** treats the stack as old and the contract as new. A breaking change here means the stack exposes something the contract does not. An extra field on `Cargo` appears as `Field weightKg was removed from object type Cargo`, because moving to the contract removes it. A field the stack made non-null appears as `Field Cargo.itinerary changed type from Itinerary! to Itinerary`, because moving to the contract makes it nullable again.
- **Canonical to live** treats the contract as old and the stack as new. A breaking change here means something the stack serves differs from the contract, and the check fails it with one exception. The slice allows a whole type, a whole output field or a whole mutation or subscription root to be absent, because Chapter 3 serves only part of the schema. Any other removal fails: an enum value, an argument, an input field, a union member. A type that became looser, such as a field the contract makes non-null, appears here as `Field Cargo.trackingId changed type from TrackingId! to TrackingId`. A changed description on a field, argument or type that both sides have fails here too, although the tool marks it safe.

Figure 5.2 sorts the five seeded cases by the direction that reports them.

{% include excalidraw.html file="05-two-direction-diff" alt="Two side-by-side panels. The left panel, titled live to canonical, asks whether the stack exposes more or tighter surface than the contract. It has three rows, each with a white case box on the left and a result box on the right: an extra field, weightKg Float on Cargo, leads with an amber arrow to a light amber box that reads fail, breaking, field weightKg was removed from object type Cargo; a tightened output, itinerary as Itinerary non-null, leads to a light amber box that reads fail, breaking, field Cargo.itinerary changed type from Itinerary non-null to Itinerary; and a slice case, HandlingEvent not served, leads with a dashed arrow to a plain box reading safe, ignored, type HandlingEvent was added. A note below states that the opposite diff lists a tighter output as safe, so one direction would pass a tightened field. The right panel, titled canonical to live, asks whether what the stack serves differs from the contract. It has four rows: the slice case leads by a dashed arrow to a dashed box reading allowed, slice removal, type HandlingEvent was removed; a loosened output, trackingId as TrackingId, leads to a light amber box reading fail, drift, field Cargo.trackingId changed type from TrackingId non-null to TrackingId; a removed enum value, UNKNOWN, leads to a light amber box reading fail, drift, enum value UNKNOWN was removed from enum TransportStatus; and a changed description leads to a light amber box reading fail, drift, though marked safe. A note below states that only whole types, output fields and roots may be absent." caption="Figure 5.2 — The two directions of the diff. Each seeded drift is reported by one of them, and only the canonical-to-live direction may ignore a slice." %}

One direction alone is not enough, and the tightened field is the example that proves it. Suppose someone changes `Cargo.itinerary` from `Itinerary` to `Itinerary!` because every seeded cargo happens to have a route. For a client, a field that can never be null is easier to use, so the canonical-to-live diff reports the change with a check mark and no breaking marker: `✔ Field Cargo.itinerary changed type from Itinerary to Itinerary!`. Only the live-to-canonical diff reports it as breaking. And it matters, because Chapter 4's fuse is gone. When the routing service fails for one cargo, a nullable `itinerary` costs one field. A non-null one passes the `null` up to `Query.cargo`, so the client loses the whole cargo, and a diff that checked only one direction would have let that change through.

## Framework noise

A schema built by a framework contains things the author never wrote. Live Quarkus introspection compared with the canonical SDL starts with these lines, before it reaches anything in the slice:

```text
[log] ✖  Directive constraint was removed
[log] ✖  Directive defer was removed
[log] ✖  Directive experimental_disableErrorPropagation was removed
[log] ✖  Directive rolesAllowed was removed
[log] ✖  Type BigDecimal was removed
[log] ✖  Type BigInteger was removed
```

SmallRye registers four directives and two scalars that no field in this schema uses. They are not drift, and they are not part of the contract. The check filters them with an extended regular expression, `LGTM_SDL_IGNORE`, that lists each name:

```bash
LGTM_SDL_FRAMEWORK_DIRECTIVES="constraint|defer|experimental_disableErrorPropagation|rolesAllowed"
LGTM_SDL_FRAMEWORK_TYPES="BigDecimal|BigInteger"
```

Exact names, never a pattern. A rule such as "ignore every added directive" would hide the day a developer adds an `@internal` directive that the canonical SDL does not declare, which is the change the gate exists to see. Listing each framework name keeps the filter a statement about the framework and not a hole in the contract. When a framework upgrade registers a new directive, the gate fails, someone reads the change line, and the name goes on the list or the setting that registered it is turned off.

The same filter applies when the two exports are compared with each other. `assert_sdl_same` diffs Quarkus against Python and Python against Quarkus and fails if any change line remains after the framework names and the `@specifiedBy` lines are filtered. That is the check that makes "two stacks, one schema" a property the script asserts and not a claim.

## Linting the contract itself

Diffing compares two schemas, and says nothing about whether one of them is any good. A linter checks a schema on its own. The contracts tooling runs GraphQL ESLint over `contracts/schema/` with `npm run lint`:

```bash
npm --prefix contracts run lint
```

The configuration starts from the plugin's `schema-recommended` rule set and adjusts two rules. The recommended preset requires descriptions on types and root fields; the contract also requires them on every field, argument and enum value, which is why the diff's description check has something to compare. The second, `strict-id-in-types`, requires an `id` field on entity types, with explicit exceptions for value objects such as `Leg` and `Delivery` and for types named with the suffixes `Connection`, `Edge`, `Info`, `Payload` and `Error`. The exceptions are written down in `eslint.config.mjs`, so adding a type that should have an identity but does not is a lint failure.

The lint runs on the canonical SDL, not on the stacks' exports. The contract is what people review, so its quality is checked at the source, and the exports are held to the contract by the diff. A description missing in code fails as a description change once the stack serves the field.

## What the assertions add to the gate

The diff covers structure. Four things sit outside it.

**Behavior.** The diff compares types and arguments. It never runs a query, so a stack that serves `Cargo.delivery` with the right type and the wrong status passes. The values come from the assertions in `verify.sh` that read real responses: the exact timestamps in Chapter 3, the null propagation paths in Chapter 4. Null propagation shows the limit clearly. An execution error (older editions of the specification call it a field error) is a runtime event, and no schema file describes it.

**`specifiedByURL`.** Covered above. The diff covers types, fields, arguments, enum values and descriptions, so `verify.sh` reads the URL through introspection on both stacks.

**Default values.** A default added to an argument is classified as dangerous, not breaking, and `assert_sdl_conforms` looks only at breaking lines and descriptions. A copy of the canonical SDL with `first: Int = 10` added to `Query.cargos` produces this and exits zero:

```text
[log] ⚠  Default value 10 was added to argument first on field Query.cargos
[success] No breaking changes detected
```

That is the right classification for evolution, since existing queries keep working, and the wrong one for conformance, since the stack now differs from the contract. A default the stack prints and the contract lacks is caught only when a chapter asserts it. Chapter 8 does so for the input type, where the assertion confirms that no field carries a default.

**Everything the schema does not express.** Authorization, cost limits, caching hints and the contents of resolvers are outside the SDL. Chapters 14, 16 and 18 gate them in their own ways.

These four argue for keeping explicit assertions beside the gate. The diff covers the structural surface cheaply and completely, and the assertions cover the facts it cannot see.

## Seeing the gate fire

A check that has never failed proves nothing. The example seeds drift into copies of each stack's export and requires the gate to fail on each, on both stacks. Every case is a `sed` edit scoped to the `Cargo` type, so the edit cannot touch the `Query.cargo` argument, which is also spelled `trackingId: TrackingId!`.

| Case | Edit to the export | Reported by | Needle |
|---|---|---|---|
| tighten | `itinerary: Itinerary` becomes `Itinerary!` | live to canonical | `Cargo.itinerary` |
| loosen | `trackingId: TrackingId!` becomes `TrackingId` | canonical to live | `Cargo.trackingId` |
| extra field | `weightKg: Float` added to `Cargo` | live to canonical | `weightKg` |
| enum value | `UNKNOWN` removed from `TransportStatus` | canonical to live | `UNKNOWN` |
| description | `The public tracking identifier.` becomes `Tracking id.` | canonical to live | `Cargo.trackingId` |

Three rules keep the fixtures meaningful.

**The fixture must apply.** After each edit the script runs `cmp -s` between the export and the edited copy. If they are identical, the pattern matched nothing, for example because a framework upgrade changed how a field prints. A copy identical to the export conforms, so the "drift" check would then fail for the wrong reason, or worse, a loosened check would pass vacuously. The script treats an unchanged copy as a failed fixture and stops.

**The needle must be in the change line.** `assert_sdl_drift <file> <needle>` passes only when the conformance check fails and a line of graphql-inspector's report contains the needle. The context string passed by the caller is never searched, and neither is the script's own `lib.sh:` prefix. A drift check that passed because the file did not parse, or because an unrelated change appeared, would prove nothing.

**A tool error is not drift.** An edit that deletes only the line `UNKNOWN` looks like the obvious enum fixture. In both exports the line above it is the value's description, so the edit leaves a description with nothing to describe and the file stops being valid SDL. `graphql-inspector` then reports a syntax error (`Expected Name, found "}"`), and `assert_sdl_drift` sees its "could not compare" message and fails the case. The fixture therefore removes the value together with its description. A comparison that did not run is a failure, never a pass.

A run of the tighten case against the Python export prints, once the unrelated slice additions are filtered with `grep`:

```text
[log] ✖  Field Cargo.itinerary changed type from Itinerary! to Itinerary
[error] Detected 1 breaking change
```

The change line that `verify.sh` matches is that first line, and the needle `Cargo.itinerary` is in it. The Quarkus export produces the same change lines for all five cases, as expected of two exports of one schema.

## Where the breaking gate fits

Two gates look alike and answer different questions. Conformance asks whether the stacks match the contract, and it is what this chapter built. The breaking-change gate asks whether the contract itself changed in a way that breaks an existing client, and it is `npm run breaking`.

The gate extracts `contracts/schema/` from a base ref, `origin/main` by default, and runs `graphql-inspector diff` between that copy and the working tree. A removed field, a changed type or a removed enum value fails, and additive changes pass. Two edge cases have explicit handling. When the base ref contains no schema yet, as on the first introduction of the contract, the gate prints a message and skips. A base ref that does not resolve, because it was not fetched, is an error, so the gate cannot pass by accident. Setting `BASE_DIR` compares against a directory instead of a git ref, which is how the gate is tested.

The two gates compose. A change to the canonical SDL goes through `npm run breaking` against `main`, and a change to either stack goes through `assert_sdl_conforms` against the canonical SDL. Chapter 11 builds on the first and covers how to evolve a contract that clients already use.

## Code-first on two stacks

The export also belongs inside each service's own test suite, where it runs on every build without compose or Node. The example keeps the checks in `verify.sh`, and this sketch shows the shape a unit test takes on each stack. It is an illustration, not part of the example. Chapter 23 builds the real test suites.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@QuarkusTest
class SchemaExportTest {

    @Test
    void exportDeclaresCargoAndItsScalars() {
        given().when().get("/graphql/schema.graphql")
                .then()
                .statusCode(200)
                .body(containsString("type Cargo implements Node"))
                .body(containsString("scalar TrackingId"));
    }
}
```

```python
from app.schema import schema


def test_export_declares_cargo_and_its_scalars():
    sdl = schema.as_str()
    assert "type Cargo implements Node" in sdl
    assert "scalar TrackingId" in sdl
```

The Quarkus test starts the application and fetches the schema over HTTP, the way a client would. The Python test needs no server, because the schema is a plain object and `as_str()` prints it. Both catch a field or type that disappears, in seconds. Neither replaces the gate: seeing the canonical SDL means handing both schemas to a diff tool, which is what `verify.sh` already does.

## On the wire

Start the stack. Quarkus is on `8150` and Python on `8151`; both answer the Chapter 3 query with the same bytes.

```bash
docker compose -f examples/05-contract-first/compose.yaml up -d --build
curl -s localhost:8150/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId delivery { transportStatus } } }"}'
```

```json
{"data":{"cargo":{"trackingId":"ABC123","delivery":{"transportStatus":"ONBOARD_CARRIER"}}}}
```

Export the schema each stack builds and look at the scalars, where the two files disagree:

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

Introspection reports the URL on both stacks, even where the file does not print it:

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

`bash examples/05-contract-first/verify.sh` asserts the following on each stack, then compares the two exports and lints the canonical SDL:

| Check | Expected |
|---|---|
| `cargo(trackingId: "ABC123")` | `ABC123`, `ONBOARD_CARRIER`, no `errors` |
| `TrackingId`, `UnLocode`, `DateTime` | kind `SCALAR`; `specifiedByURL` `null`, `https://unece.org/trade/uncefact/unlocode`, `https://www.rfc-editor.org/rfc/rfc3339` |
| the exported SDL | non-empty, contains `type Cargo implements Node`, declares `scalar DateTime` and `scalar UnLocode` |
| the Quarkus export | contains no `@specifiedBy` |
| the Python export | contains `scalar UnLocode @specifiedBy(url: "https://unece.org/trade/uncefact/unlocode")` |
| export and introspection vs `contracts/schema/` | no breaking change beyond the slice, no changed description |
| the Quarkus export vs the Python export | identical after the framework filter |
| `npm --prefix contracts run lint` | exit 0 |
| tighten | change line contains `Cargo.itinerary` |
| loosen | change line contains `Cargo.trackingId` |
| extra field | change line contains `weightKg` |
| enum value | change line contains `UNKNOWN` |
| description | change line contains `Cargo.trackingId` |

The script prints `PASS` only when both stacks hold and every seeded drift fails the gate.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Contract-first work is where the <em>contract and evolution style</em> axis of Chapter 2 becomes a process. A single schema that many unknown clients read is only an asset if it stays one schema, so the canonical SDL owns the contract and each code-first stack is held to it by a diff, in both directions, on every run. The <em>team ownership and federation</em> axis explains the shape: one team can review one SDL file, and a gate replaces the coordination meeting. The <em>operational and security cost</em> axis registers a small charge, a pinned Node toolchain, two export paths and a framework-noise list to maintain, and it buys detection of silent drift for the price of a few seconds of CI. The <em>client diversity and shape variance</em> axis is the reason the price is worth paying, since a field that tightens or disappears in one stack breaks a client nobody on the team has met. The tracking view stays code-first on both stacks, treats the canonical SDL as the yardstick, and keeps explicit assertions for what a structural diff cannot see.</p></div>

## Where this goes next

This chapter covered the two ways to own a schema, how each stack exports the schema it builds, what the two-direction diff reports and what the assertions add, the framework noise filter, the lint on the contract, and five seeded drifts that prove the gate fails and where. It also recorded where the two exports differ: scalar definitions and `@specifiedBy`.

Chapter 6 leaves the schema and follows a request through the engine: parse, validate, coerce variables and execute. Chapter 8 serves the input type and asserts that no input field carries a default, which the diff would report only as dangerous. Chapter 11 takes the breaking-change gate and uses it to evolve a contract that clients already depend on, including the question of what to do with a tightened field. Chapter 23 turns the export checks into the unit tests sketched above.

For the formal definitions, read the Type System and Introspection sections of the [GraphQL specification](https://spec.graphql.org/). The tools are documented at [GraphQL Inspector](https://the-guild.dev/graphql/inspector/docs) and [GraphQL ESLint](https://the-guild.dev/graphql/eslint). Samer Buna's *GraphQL in Action* covers designing a schema in "Designing a GraphQL schema", which is listed on the [Bibliography](../../bibliography/) page, and the gRPC sibling of this site covers the same ground with `buf` in its Contract-first with Buf chapter.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021) — "Designing a GraphQL schema" covers the schema-ownership tradeoffs this chapter resolves with a gate.
- Cloud Native Design Patterns — [API Registry](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/09-api-registry/) chapter, for the broader pattern of a canonical contract checked against what services actually serve.
- [GraphQL Inspector](https://the-guild.dev/graphql/inspector/docs) — the two-direction diff and breaking-change tooling this chapter's gate is built on.
- [GraphQL ESLint](https://the-guild.dev/graphql/eslint) — the linter that enforces description and naming rules on the canonical SDL.
