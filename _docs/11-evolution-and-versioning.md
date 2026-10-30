---
title: "Evolution and versioning"
order: 11
part: "Schema Evolution & the Living Contract"
description: "How a GraphQL schema changes while clients depend on it: one schema without version numbers, safe, dangerous and breaking changes, nullability in both directions, the deprecation lifecycle on both stacks, and the breaking-change gate run on fixtures."
duration: "15 min read"
---

## Learning objectives

By the end of this chapter you can:

- Classify a schema change as safe, dangerous, or breaking using the GraphQL Inspector diff and know what each class costs clients.
- Apply the opposite nullability rule to outputs and inputs: tightening an output is safe, tightening an input is breaking.
- Run a field through the full deprecation lifecycle: add `finalArrivalTime`, deprecate `finalArrivalDate` with a reason, then remove it only with a sign-off.
- Read `isDeprecated` and `deprecationReason` through introspection, and use `includeDeprecated` to see hidden fields.
- Run `contracts/scripts/breaking.sh` against fixture schemas to see what a given edit costs before it ships.

## Why this matters

Ten chapters built a schema and served it. Every client that selects a field from it makes the same bet, that the field will still be there next year. The tracking view has clients nobody on the team has met: a dashboard, a mobile app, a partner's integration. Keeping that bet safe while the schema keeps changing is the subject here.

The code is in `examples/11-evolution/`. It starts from the schema-design example and applies the one change the earlier chapters kept promising. `Itinerary.finalArrivalTime` joins the schema, and `Itinerary.finalArrivalDate` is deprecated in favour of it. Both stacks serve both fields, and `verify.sh` checks the deprecation through introspection. It then runs the breaking-change gate introduced with the contract-first conformance check, `contracts/scripts/breaking.sh`, against fixture copies of the contract, one edit per case, to show what each kind of change costs.

## One schema, many clients, no version numbers

A REST API that must change in a way old clients cannot survive usually grows a second door, `/v2`, and keeps the first one open until the last client leaves. GraphQL has no equivalent need for most changes, because a client states exactly which fields it reads. A field the client never selected can appear, change or vanish without touching it. The server evolves one schema, continuously, and the contract is whatever the clients select.

That turns the question around. The server does not ask "which version is this client on?" It asks "does any client still select this?" Three habits follow:

- Add, do not change. A new field, a new optional argument or a new type costs existing clients nothing.
- Deprecate before removing. A field marked deprecated keeps working and tells every tool that reads the schema to stop using it.
- Remove only with evidence. A field leaves when nobody selects it, and the gate makes sure it is a recorded decision.

Martin Kleppmann and Chris Riccomini's *Designing Data-Intensive Applications*, 2nd edition, names the compatibility directions in its treatment of how formats change over time. Backward compatibility means newer code can read data written by older code. Forward compatibility means older code can read data written by newer code. An API contract has both. A new server must keep answering the queries old clients send, which is backward compatibility, and a client built against a newer schema may reach a server that has not been upgraded yet during a rollout, which is the forward direction. Additive evolution with deprecation keeps both true without a version number.

The slowest client sets the pace. A web client redeploys with the server, but a mobile app on a phone, or a partner's integration, may run a query written a year ago. Deprecation gives those clients a window, and the schema gives their authors a machine-readable reason to move: the generated types flag the field, and an editor strikes it through. The server keeps its side of the bargain by not deleting the field until the usage says the window can close.

A new endpoint is still justified in a few cases. The whole aggregation root changes, so that no old query can be answered by the new model. The authentication scheme changes for everyone. The transport changes. These are rewrites of the contract and not edits to it, and they should be rare enough to plan. Everything else in this chapter assumes one endpoint, one schema and a stream of small changes.

## Safe, dangerous, breaking

GraphQL Inspector sorts every change into one of three classes, from the point of view of a client of the old schema. Figure 11.1 lists one change in each class, with the line the tool prints for it and the result the gate gives.

{% include excalidraw.html file="11-change-classes" alt="Three columns list schema changes by class. The safe column, marked with a check, lists five changes: adding a field, adding an optional input field, tightening an output, deprecating a field and loosening an input. The dangerous column, marked with a warning sign, lists adding an enum value, adding an optional argument, adding a union member and making an existing type implement an interface. The breaking column, marked with a cross, lists removing a field, loosening an output, requiring an input, removing an enum value and removing a deprecated field. A box under each column gives the gate result: exit 0 for safe changes in both modes, exit 0 with a pull request warning for dangerous changes and exit 1 in strict mode, and exit 1 for breaking changes. A strip at the bottom shows that tightening an output and loosening an input are safe, while loosening an output and tightening an input are breaking." caption="Figure 11.1: Three classes of change. Each example is a fixture that verify.sh runs through the gate; the strip shows how nullability flips between outputs and inputs." %}

**Safe** changes cannot break any query that was valid before. A new field on `Location`, a new optional field on `RegisterHandlingEventInput`, and a newly deprecated field all print a check mark. The mutation chapter made `voyageNumber` and `idempotencyKey` optional from the start so that the input could grow this way.

**Dangerous** changes keep every old query valid and can still break a client at run time. A new value in `HandlingEventType` is the case the type system warned about: a client with an exhaustive `switch` meets a value it has never seen. A new optional argument on `Query.cargos` is flagged for a different reason: old queries stay valid, but the resolver behind them has changed, and the tool cannot tell whether a query that omits the argument still gets the same result. Error handling's sketch of a result union expected the same risk in a new union member, and the tool agrees: adding `Voyage` to a union prints `⚠  Member Voyage was added to Union type SearchResult`. For interfaces the tool classifies by the type that changed. An existing type that starts to implement `Node` prints `⚠  Leg object implements Node interface`. A brand-new type that implements `Node` prints `✔  Type Vessel was added`; `Query.node` can return a `Vessel` from then on, and a client with no default branch meets it as it would a new union member, so reviewers treat a new implementer as a dangerous change.

**Breaking** changes make some valid old query invalid or change its result type. Removing `Leg.unloadTime`, removing the enum value `UNKNOWN`, adding a required input field and loosening `Cargo.trackingId` from `TrackingId!` to `TrackingId` all print a cross and fail the gate.

The classes describe risk, not correctness. A dangerous change is often the right one: a handling event type for transshipment is a real requirement. The class tells reviewers where to look, and the next sections show how this chapter's gate treats each class.

## Nullability cuts both ways

Nullability propagation made nullability a promise, and promises change in two directions. For an output field, the server promises a value, so tightening is safe and loosening is not. For an input field, the client promises a value, so the rule flips. The fixtures cover all four moves, each with the line the tool printed:

| Move | Fixture edit | Class | Printed |
|---|---|---|---|
| Output tightened | `itinerary: Itinerary` to `Itinerary!` on `Cargo` | safe | `✔  Field Cargo.itinerary changed type from Itinerary to Itinerary!` |
| Output loosened | `trackingId: TrackingId!` to `TrackingId` on `Cargo` | breaking | `✖  Field Cargo.trackingId changed type from TrackingId! to TrackingId` |
| Input tightened | `voyageNumber: String` to `String!` | breaking | `✖  Input field RegisterHandlingEventInput.voyageNumber changed type from String to String!` |
| Input loosened | `completionTime: DateTime!` to `DateTime` | safe | `✔  Input field RegisterHandlingEventInput.completionTime changed type from DateTime! to DateTime` |

A client written for a nullable output already handles a value, so a non-null promise costs it nothing. A client written for a non-null output has no code for `null`, so loosening it breaks the client. A new required input field breaks every caller that does not send it, and the same holds for tightening an optional one.

The first row has a catch, and the contract-first conformance check set it up. The gate says a tightened output is safe, and for clients it is, but for the server it removes the fuse. With `itinerary: Itinerary!` a routing outage on one cargo no longer costs one field. The `null` travels up to `Query.cargo`, and the client loses the whole cargo. That is the failure nullability propagation designed `Cargo.itinerary` to avoid, and the breaking gate cannot see it, because the tool classifies the change by what clients can write and not by what the server can survive. The contract-first conformance check does see it, because it diffs each stack against the contract in both directions. The two checks answer different questions, and the contract needs both.

## The deprecation path, live

The correction that schema design left open is now in the contract:

```graphql
"""When the final leg arrives."""
finalArrivalTime: DateTime!
"""When the final leg arrives."""
finalArrivalDate: DateTime! @deprecated(reason: "Use `finalArrivalTime`.")
```

The change takes three steps in the order the lifecycle demands. First, the replacement is added, so that clients can move before anything is taken away. Second, the old field is marked `@deprecated` with a reason that names the replacement. Third, the old field stays fully functional. Both stacks answer one query with the same instant in both fields, and the response carries no warning about the deprecated one:

```graphql
{ cargo(trackingId: "ABC123") { itinerary { finalArrivalTime finalArrivalDate } } }
```

`verify.sh` asserts both values are `2026-10-11T18:00:00Z`, that the response has no `errors` and no mention of deprecation, and that a query selecting only `finalArrivalDate` is served as before. A deprecated field is a signal to tools and humans, and not a behaviour change. `Cargo.delivery` now reads the arrival from `finalArrivalTime`, and `estimatedTimeOfArrival` still returns the same value.

The signal travels through introspection. The September 2025 edition of the GraphQL specification defines the `@deprecated` directive, with a `reason` that defaults to "No longer supported", and describes in "Schema Introspection" how `__Field` reports `isDeprecated` and `deprecationReason`. It also defines a hiding rule: the `fields` selection on `__Type` takes `includeDeprecated`, which is false unless a client asks for it. So a code generator or an editor that lists fields shows only the supported ones, and a client that wants the whole history can ask:

```graphql
{ __type(name: "Itinerary") { fields(includeDeprecated: true) { name isDeprecated deprecationReason } } }
```

`verify.sh` asserts, on both stacks, that `fields` returns `finalArrivalTime` and `legs` and no `finalArrivalDate`, that `fields(includeDeprecated: false)` returns the same, and that `fields(includeDeprecated: true)` adds it. `assert_deprecated` checks that `isDeprecated` is true and that the reason equals ``Use `finalArrivalTime`.`` exactly. `assert_not_deprecated` checks the replacement. A third assertion walks every type and counts the deprecated elements across fields, arguments, input fields and enum values: the only one in the schema is `Itinerary.finalArrivalDate`.

The reason string is the part a client author reads, so it should name the replacement and nothing else. A reason like "legacy" gives no direction.

## Removing a field with a sign-off

Deprecation without removal is a note nobody acts on, and removal without evidence is an outage. Figure 11.2 shows the whole lifecycle with the gate's output at each step.

{% include excalidraw.html file="11-deprecation-lifecycle" alt="A four-step timeline runs left to right across three rows. The change row shows adding the replacement finalArrivalTime, deprecating finalArrivalDate with a reason, observing usage through operation telemetry, and removing the field with a sign-off. The gate row shows the real output for each step: a check mark for the added field, a check mark for the deprecated field, no schema change for the observation step, and a cross reporting that the deprecated field was removed, with exit 1 by default and a warning with exit 0 when the sign-off rule is set. The clients row shows existing clients unchanged, both fields executing with the old one hidden from fields by default, clients migrating on their own schedule, and a client that still selects the old field failing validation." caption="Figure 11.2: The deprecation lifecycle. Each step has a gate line from a real run, and the last step is a decision and not a side effect." %}

The first two steps ship together in this chapter, and the gate reports them as one change: `✔  Field Itinerary.finalArrivalDate is deprecated` and `✔  Field finalArrivalTime was added to object type Itinerary`. Then comes the waiting. Operation-level telemetry, built later, shows which clients still select `finalArrivalDate`. Until that count is zero, the field stays.

Removal fails by default, with a message that says what was deleted: `✖  Field finalArrivalDate (deprecated) was removed from object type Itinerary`. That failure is intended. Deleting a deprecated field is still a breaking change for any client that never moved, so the gate does not relax because the field was marked. A pull request that removes it after the usage evidence is in can say so by setting the `suppressRemovalOfDeprecatedField` rule. The same line then prints with a warning sign, `⚠  Field finalArrivalDate (deprecated) was removed from object type Itinerary`, and the gate exits 0. The rule is a sign-off recorded in the pull request, not a default.

A client that selects the removed field after the removal fails validation, and the request returns no data. `verify.sh` checks that failure shape with a field the schema does not have, `finalArrivalDay`: an error naming it, and no `data`.

## Running the gate

`contracts/scripts/breaking.sh`, available as `npm --prefix contracts run breaking`, compares the working tree's `contracts/schema/**/*.graphql` with the same files on a base ref, `origin/main` by default. It extracts the base with `git archive`, runs `graphql-inspector diff` between the two and exits with the tool's code, 0 for a pass and 1 for a breaking change, or with 2 when the base ref does not resolve.

When the base ref holds no `.graphql` files under `contracts/schema`, as on the pull request that first adds the contract, the script prints `no baseline schema on origin/main yet - skipping breaking check (first introduction)` and exits 0. A base ref that does not resolve exits 2 instead, so a missing fetch cannot pass by accident. To show each kind of change without a commit per case, this chapter runs the gate on fixture directories. Three environment variables make that possible:

| Variable | Effect |
|---|---|
| `BASE_DIR=<dir>` | Compare against a directory of `.graphql` files instead of a git ref |
| `NEW_DIR=<dir>` | Use a directory as the new side instead of the working tree |
| `BREAKING_RULES=<list>` | Pass each comma-separated name to the tool as a `--rule` |

Once a baseline exists on `main`, every later change to the contract is diffed against it with no fixtures involved, and these variables remain the way to test the gate itself.

`verify.sh` builds each fixture the same way. It copies `contracts/schema` into a base directory and a new directory, applies one textual edit to the new side and runs `assert_gate`, which passes only when the exit code and a needle from the tool's output both match. The edit is a replacement that must match exactly once:

```bash
edit() {
  python3 -I -c '
import sys

path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit("fixture did not apply: %d occurrences in %s of %r" % (text.count(old), path, old))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
' "$@" || { echo "lib.sh: FAIL — fixture did not apply: $1" >&2; return 1; }
}
```

The guard matters. A fixture whose edit silently did nothing would report "no changes" and pass a case that expected a failure. The needles are full change lines, including the check, warning or cross mark, so the test pins the classification as well as the exit code. The cases run once, after both stack checks, and not per stack, because the contract is the same for both.

## Should dangerous changes fail?

The default gate fails only on breaking changes. A dangerous change exits 0, and the result is a decision for the reviewer, not a red build. An added enum value or an added optional argument is routine evolution. A gate that blocks it teaches teams to avoid the evolution that GraphQL makes cheap, or to switch the gate off.

The warning still has to be seen. When the script runs with `GITHUB_ACTIONS=true`, it echoes each warning-marked line as `::warning title=Dangerous schema change::<line>`, which GitHub shows as an annotation on the pull request without failing the job. `verify.sh` runs the enum-value fixture with that variable set and asserts three facts: exit 0, the annotation prefix, and the change line inside the annotation.

Teams that cannot tolerate that risk, such as a public API with generated clients, can run the strict mode, `BREAKING_RULES=dangerousBreaking`. The same enum-value fixture then prints `✖  Enum value TRANSSHIP was added to enum HandlingEventType` and exits 1. Strict mode changes the verdict and the marker, and it leaves the schema alone.

## What the gate cannot see

A diff of two schemas sees structure. Several things that matter during evolution sit outside it.

**Behaviour.** A field that keeps its name and type and starts returning a different value, such as an arrival time that moves from local time to UTC, is invisible. No schema diff catches it. Behavioural changes need a new field, which the lifecycle above already provides, and tests in the example that assert values.

**Default values.** The gate sees a default only as text: adding one is dangerous and passes, as the contract-first conformance check showed. What an omitted argument means to the resolver is invisible, so a server that starts treating a missing `first` differently changes every caller with no line in the diff. Conformance does not catch a stray default either, because `assert_sdl_conforms` looks only at breaking lines and descriptions.

**Error codes.** The `extensions.code` values from error handling live in the response, not in the SDL, so no schema diff sees a new code. They follow the enum rules anyway: a client with a default branch survives a new code, and one without it does not. The contract for codes has to be kept in the documentation and in tests.

**Deprecation state in conformance.** `assert_sdl_conforms` fails on breaking changes and on description changes. Removing `@deprecated` is a safe change, so a stack that forgot the deprecation would still conform. `verify.sh` proves that with a fixture: a copy of the contract without the directive prints `✔  Field Itinerary.finalArrivalDate is no longer deprecated`, and `assert_sdl_conforms` passes against it. That is why the earlier error-handling and schema-design examples can serve `finalArrivalDate` without the directive and still conform, and why this chapter's example calls `assert_deprecated` and `assert_not_deprecated` for each stack. Where a state matters and the structural check ignores it, an explicit assertion covers it.

## Evolving the two stacks

Both stacks are code-first, so the deprecation is a line of code in each, and the contract is the yardstick that checks it.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Type("Itinerary")
@Description("The planned sequence of legs moving a cargo from origin to destination.")
public record Itinerary(
        @NonNull @Description("Ordered legs of the route; never empty for an assigned itinerary.")
                List<@NonNull Leg> legs,
        @NonNull @Description("When the final leg arrives.") Instant finalArrivalTime,
        @NonNull
                @Description("When the final leg arrives.")
                @Deprecated(reason = "Use `finalArrivalTime`.")
                Instant finalArrivalDate) {}
```

```python
class Itinerary:
    legs: list[Leg] = strawberry.field(
        description="Ordered legs of the route; never empty for an assigned itinerary."
    )
    final_arrival_time: datetime = strawberry.field(description="When the final leg arrives.")
    final_arrival_date: datetime = strawberry.field(
        description="When the final leg arrives.",
        deprecation_reason="Use `finalArrivalTime`.",
    )
```

Strawberry takes the reason as a keyword argument, `deprecation_reason`, and introspection reports it with no further work. SmallRye GraphQL offers its own annotation, `io.smallrye.graphql.api.Deprecated` with a `reason`. The reason is written once, on the record component, and `ContractSchemaDetails`, the schema observer the examples already use, applies it to the schema with graphql-java's `deprecate(reason)`. `java.lang.Deprecated` carries no reason, so the example uses the SmallRye annotation:

```java
String reason = annotatedDeprecationReason(node);
if (!stripSuffix && reason == null) {
    return TraversalControl.CONTINUE;
}
return changeNode(context, node.transform(field -> {
    if (stripSuffix) {
        field.description(description.substring(0, description.length() - ISO_SUFFIX.length()));
    }
    if (reason != null) {
        field.deprecate(reason);
    }
}));
```

The annotation stays the one place a developer writes the reason, and the observer reads it from there. The same observer trims the generated ` (ISO-8601)` suffix from date descriptions, which keeps the description of the new `finalArrivalTime` equal to the contract's. The two stacks return `fields` in different orders, so `verify.sh` sorts the names before comparing.

Nothing else in the stacks changed from the schema-design example. `verify.sh` still runs the scalar checks and the conformance diff on both stacks.

## On the wire

Start the stack and ask Quarkus, on port 8210, for both fields. Use 8211 for Python.

```bash
docker compose -f examples/11-evolution/compose.yaml up -d --build
gql() { curl -s localhost:8210/graphql -H 'Content-Type: application/json' -d "$1"; echo; }
gql '{"query":"{ cargo(trackingId: \"ABC123\") { itinerary { finalArrivalTime finalArrivalDate } } }"}'
gql '{"query":"{ __type(name: \"Itinerary\") { fields { name } } }"}'
gql '{"query":"{ __type(name: \"Itinerary\") { fields(includeDeprecated: true) { name isDeprecated deprecationReason } } }"}'
```

```json
{"data":{"cargo":{"itinerary":{"finalArrivalTime":"2026-10-11T18:00:00Z","finalArrivalDate":"2026-10-11T18:00:00Z"}}}}
{"data":{"__type":{"fields":[{"name":"legs"},{"name":"finalArrivalTime"}]}}}
{"data":{"__type":{"fields":[{"name":"finalArrivalDate","isDeprecated":true,"deprecationReason":"Use `finalArrivalTime`."},{"name":"legs","isDeprecated":false,"deprecationReason":null},{"name":"finalArrivalTime","isDeprecated":false,"deprecationReason":null}]}}}
```

Then run the gate on two copies of the contract, the second without the deprecated field, and again with the sign-off rule:

```bash
mkdir -p /tmp/old /tmp/new && cp -r contracts/schema /tmp/old/ && cp -r contracts/schema /tmp/new/
sed -i '/When the final leg arrives/{N;/finalArrivalDate/d}' /tmp/new/schema/shipping/cargo.graphql
BASE_DIR=/tmp/old/schema NEW_DIR=/tmp/new/schema bash contracts/scripts/breaking.sh | tail -2
BASE_DIR=/tmp/old/schema NEW_DIR=/tmp/new/schema BREAKING_RULES=suppressRemovalOfDeprecatedField bash contracts/scripts/breaking.sh | tail -2
```

```text
[log] ✖  Field finalArrivalDate (deprecated) was removed from object type Itinerary
[error] Detected 1 breaking change
[log] ⚠  Field finalArrivalDate (deprecated) was removed from object type Itinerary
[success] No breaking changes detected
```

The first command exits 1 and the second exits 0. `bash examples/11-evolution/verify.sh` runs the checks below on both stacks and then the gate cases:

| Check | Expected |
|---|---|
| `itinerary { finalArrivalTime finalArrivalDate }` for `ABC123` | both `2026-10-11T18:00:00Z`; no `errors`; no mention of deprecation in the response |
| `itinerary { finalArrivalDate }` alone; `delivery { estimatedTimeOfArrival }` | `2026-10-11T18:00:00Z` for both |
| `Itinerary.finalArrivalDate` in introspection | `isDeprecated` true, reason ``Use `finalArrivalTime`.`` |
| `Itinerary.finalArrivalTime` | `isDeprecated` false |
| every deprecated element in the schema | exactly `Itinerary.finalArrivalDate` |
| `fields`, `fields(includeDeprecated: false)` | `finalArrivalTime`, `legs` |
| `fields(includeDeprecated: true)` | `finalArrivalDate`, `finalArrivalTime`, `legs` |
| a selection the schema lacks, `finalArrivalDay` | an error naming the field; no `data` |
| scalars `TrackingId`, `UnLocode`, `DateTime` | `SCALAR`; `specifiedByURL` null, the UNECE page, RFC 3339 |
| live schema vs `contracts/schema/` | conforms (slice) |
| `npm --prefix contracts run lint` | exit 0 |
| no change | exit 0, `No changes detected` |
| the real change: base without `finalArrivalTime` and `@deprecated` | exit 0, `✔  Field Itinerary.finalArrivalDate is deprecated` and `✔  Field finalArrivalTime was added to object type Itinerary` |
| safe: `timeZone: String` added to `Location` | exit 0, `✔  Field timeZone was added to object type Location` |
| the same edit with `dangerousBreaking` | exit 0, `✔  Field timeZone was added to object type Location` |
| safe: optional `operatorId: String` on the input | exit 0, `✔  Input field operatorId of type String was added to input object type RegisterHandlingEventInput` |
| safe: `itinerary: Itinerary!` | exit 0, `✔  Field Cargo.itinerary changed type from Itinerary to Itinerary!` |
| safe: `completionTime: DateTime` on the input | exit 0, `✔  Input field RegisterHandlingEventInput.completionTime changed type from DateTime! to DateTime` |
| dangerous: `TRANSSHIP` added to `HandlingEventType` | exit 0, `⚠  Enum value TRANSSHIP was added to enum HandlingEventType`; with `GITHUB_ACTIONS=true` also a `::warning` annotation |
| the same edit with `dangerousBreaking` | exit 1, `✖  Enum value TRANSSHIP was added to enum HandlingEventType` |
| dangerous: optional `destination: UnLocode` on `Query.cargos` | exit 0, `⚠  Argument destination: UnLocode added to field Query.cargos` |
| dangerous: `Voyage` added to a union | exit 0, `⚠  Member Voyage was added to Union type SearchResult` |
| dangerous: `Leg` implements `Node` | exit 0, `⚠  Leg object implements Node interface` |
| safe: a new type `Vessel` implements `Node` | exit 0, `✔  Type Vessel was added` |
| breaking: `Leg.unloadTime` removed | exit 1, `✖  Field unloadTime was removed from object type Leg` |
| breaking: `trackingId: TrackingId` on `Cargo` | exit 1, `✖  Field Cargo.trackingId changed type from TrackingId! to TrackingId` |
| breaking: `voyageNumber: String!` on the input | exit 1, `✖  Input field RegisterHandlingEventInput.voyageNumber changed type from String to String!` |
| breaking: required `operatorId: String!` | exit 1, `✖  Input field operatorId of type String! was added to input object type RegisterHandlingEventInput` |
| breaking: `UNKNOWN` removed from `TransportStatus` | exit 1, `✖  Enum value UNKNOWN was removed from enum TransportStatus` |
| lifecycle: `finalArrivalDate` removed | exit 1, `✖  Field finalArrivalDate (deprecated) was removed from object type Itinerary` |
| the same with `suppressRemovalOfDeprecatedField` | exit 0, `⚠  Field finalArrivalDate (deprecated) was removed from object type Itinerary` |
| a copy of the contract without `@deprecated` | gate exit 0, `✔  Field Itinerary.finalArrivalDate is no longer deprecated`; `assert_sdl_conforms` passes |

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Evolution is where the <em>contract and evolution style</em> axis of the decision framework is paid for or collected. One schema with additive changes, deprecation with a reason and a gate on removals replaces version numbers, and the cost moves from clients, who never need to upgrade, to the team, which has to watch usage before it deletes anything. The <em>client diversity and shape variance</em> axis is why: with clients nobody on the team has met, a field cannot be removed on a guess. The <em>team ownership and federation</em> axis shows in who signs off: the gate is a file in the repository that every owning team can read and every pull request runs through. The <em>operational and security cost</em> axis registers a small recurring charge, a pinned diff tool and a policy for dangerous changes. The tracking view uses one endpoint, deprecates <code>finalArrivalDate</code> in favour of <code>finalArrivalTime</code> on both stacks, fails the default gate on breaking changes only, annotates dangerous ones on the pull request and keeps <code>dangerousBreaking</code> for teams that want it.</p></div>

## Review

- The GraphQL Inspector diff classifies a schema change as safe, dangerous, or breaking, and each class costs clients differently.
- Nullability runs opposite directions for outputs and inputs: tightening an output is safe, while tightening an input is breaking.
- `Itinerary.finalArrivalTime` ran through the full deprecation lifecycle: added, with `finalArrivalDate` deprecated with a reason, leaving removal for later with a sign-off.
- Introspection reports `isDeprecated` and `deprecationReason` through `__Field`, and `includeDeprecated` reveals fields hidden by default.
- `contracts/scripts/breaking.sh` run against fixture schemas shows what a given edit costs before it ships.

## Where this goes next

This chapter classified changes as safe, dangerous or breaking, followed nullability in both directions, deprecated a field live on both stacks and ran the breaking gate on fixtures, from no change to a field removed outright. The usage evidence that step three of the lifecycle depends on comes from operation telemetry, built later.

The next example starts from the error-handling example and carries `nodes` and this chapter's deprecation forward, then builds the Relay connection that `handlingHistory` has been waiting for. DataLoader batching collapses the source calls counted by the resolver and schema-design chapters.

For the formal definitions, read "Field Deprecation", "@deprecated" and "Schema Introspection" in the [GraphQL specification](https://spec.graphql.org/). The diff rules and their names are in the [GraphQL Inspector](https://the-guild.dev/graphql/inspector/docs) documentation. Martin Kleppmann and Chris Riccomini's *Designing Data-Intensive Applications*, 2nd edition, covers backward and forward compatibility, and it is listed on the [Bibliography](../../bibliography/) page together with Artur Czemiel's *GraphQL Best Practices*, which covers schema design more broadly.

## For deeper coverage

- [GraphQL specification: Field Deprecation, @deprecated, Schema Introspection](https://spec.graphql.org/).
- [GraphQL Inspector documentation](https://the-guild.dev/graphql/inspector/docs): the diff rules and change classes (safe/dangerous/breaking) this chapter's gate runs.
- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd ed. (O'Reilly, 2026): backward and forward compatibility.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): schema design and evolution more broadly.
- *Cloud Native Design Patterns*, "Versioning & Evolution" (Appendix B): the wider evolution patterns this chapter's deprecation lifecycle is one instance of.
