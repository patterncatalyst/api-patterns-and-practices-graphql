---
title: "Evolution and versioning"
order: 11
part: "Schema Evolution & the Living Contract"
description: "How a GraphQL schema changes while clients depend on it: one schema without version numbers, safe, dangerous and breaking changes, nullability in both directions, deprecation on both stacks, and a breaking-change gate."
duration: "10 min read"
---

## Learning objectives

By the end of this chapter you can:

- Classify a schema change as safe, dangerous, or breaking using the GraphQL Inspector diff and know what each class costs clients.
- Apply the opposite nullability rule to outputs and inputs: tightening an output is safe, tightening an input is breaking.
- Run a field through the deprecation lifecycle: add `finalArrivalTime`, deprecate `finalArrivalDate` with a reason, then remove it only with a sign-off.
- Read `isDeprecated` and `deprecationReason` through introspection, and use `includeDeprecated` to see hidden fields.
- Run `contracts/scripts/breaking.sh` against fixture schemas to see what an edit costs before it ships.

## Why this matters

Every client that selects a field makes the same bet: the field will still be there next year. The tracking view has clients nobody on the team has met, such as a dashboard, a mobile app and a partner's integration. The schema has to keep changing without losing that bet.

The code adds `Itinerary.finalArrivalTime` and deprecates `Itinerary.finalArrivalDate` in favor of it. Both stacks serve both fields. The breaking-change gate then runs against fixture copies of the contract, one edit per case.

## One schema, many clients, no version numbers

A REST API that must change in a way old clients can't survive usually grows a second door, `/v2`, and keeps the first open until the last client leaves. GraphQL rarely needs that, because a client states exactly which fields it reads. A field the client never selected can appear, change or vanish without touching it. The server evolves one schema continuously, and the contract is whatever the clients select.

The server stops asking "which version is this client on?" and asks "does any client still select this?" Three habits follow:

- Add, don't change. A new field, a new optional argument or a new type costs existing clients nothing.
- Deprecate before removing. A deprecated field keeps working and tells every tool that reads the schema to stop using it.
- Remove only with evidence. A field leaves when nobody selects it, and the check makes that a recorded decision.

Martin Kleppmann and Chris Riccomini's *Designing Data-Intensive Applications*, 2nd edition, names the two compatibility directions. Backward compatibility means newer code reads data written by older code: a new server keeps answering old queries. Forward compatibility means older code reads data written by newer code: a client built against a newer schema may reach a server not yet upgraded during a rollout. Additive evolution with deprecation keeps both true.

The slowest client sets the pace. A web client redeploys with the server, but a mobile app or a partner integration may run a query written a year ago. Deprecation gives them a window and a machine-readable reason to move: generated types flag the field and an editor strikes it through.

A new endpoint is still justified when the whole aggregation root changes, when the authentication scheme changes for everyone, or when the transport changes. Those rewrite the contract rather than edit it.

## Safe, dangerous, breaking

GraphQL Inspector sorts every change into one of three classes, from the point of view of a client of the old schema.

{% include excalidraw.html file="11-change-classes" alt="Three columns list schema changes by class. The safe column, marked with a check, lists five changes: adding a field, adding an optional input field, tightening an output, deprecating a field and loosening an input. The dangerous column, marked with a warning sign, lists adding an enum value, adding an optional argument, adding a union member and making an existing type implement an interface. The breaking column, marked with a cross, lists removing a field, loosening an output, requiring an input, removing an enum value and removing a deprecated field. A box under each column gives the check result: exit 0 for safe changes in both modes, exit 0 with a pull request warning for dangerous changes and exit 1 in strict mode, and exit 1 for breaking changes. A strip at the bottom shows that tightening an output and loosening an input are safe, while loosening an output and tightening an input are breaking." caption="Figure 11.1: Three classes of change, with one example per class and how nullability flips between outputs and inputs." %}

**Safe** changes can't break any query that was valid before. A new field on `Location`, a new optional field on `RegisterHandlingEventInput` and a newly deprecated field all print a check mark. `voyageNumber` and `idempotencyKey` are optional from the start so the input can grow this way.

**Dangerous** changes keep every old query valid and can still break a client at run time:

- A new value in `HandlingEventType` hits any client with an exhaustive `switch`.
- A new optional argument on `Query.cargos` changes the resolver behind old queries, and the tool can't tell whether a query that omits it still gets the same result.
- A new union member prints `⚠  Member Voyage was added to Union type SearchResult`, and a client with no default branch meets a type it has never seen.
- An existing type that starts to implement `Node` prints `⚠  Leg object implements Node interface`. A brand-new type that implements `Node` prints only `✔  Type Vessel was added`, but `Query.node` can now return it, so reviewers treat a new implementer as dangerous.

**Breaking** changes make some valid old query invalid or change its result type. Removing `Leg.unloadTime`, removing the enum value `UNKNOWN`, adding a required input field and loosening `Cargo.trackingId` from `TrackingId!` to `TrackingId` all print a cross and fail the check.

The classes describe risk, not correctness. A dangerous change is often the right one: a transshipment event type is a real requirement. The class tells reviewers where to look.

## Nullability cuts both ways

For an output field the server promises a value, so tightening is safe and loosening is not. For an input field the client promises a value, so the rule flips.

| Move | Edit | Class | Printed |
|---|---|---|---|
| Output tightened | `itinerary: Itinerary` to `Itinerary!` on `Cargo` | safe | `✔  Field Cargo.itinerary changed type from Itinerary to Itinerary!` |
| Output loosened | `trackingId: TrackingId!` to `TrackingId` on `Cargo` | breaking | `✖  Field Cargo.trackingId changed type from TrackingId! to TrackingId` |
| Input tightened | `voyageNumber: String` to `String!` | breaking | `✖  Input field RegisterHandlingEventInput.voyageNumber changed type from String to String!` |
| Input loosened | `completionTime: DateTime!` to `DateTime` | safe | `✔  Input field RegisterHandlingEventInput.completionTime changed type from DateTime! to DateTime` |

A client written for a nullable output already handles a value, so a non-null promise costs it nothing. A client written for a non-null output has no code for `null`. A new required input field breaks every caller that doesn't send it, and so does tightening an optional one.

The first row has a catch. Tightening is safe for clients, but for the server it removes the fuse. With `itinerary: Itinerary!`, a routing outage on one cargo no longer costs one field: the `null` travels up to `Query.cargo` and the client loses the whole cargo. The check classifies the change by what clients can write, not by what the server can survive, so it can't see this. A conformance check that diffs each stack against the contract in both directions does. The two checks answer different questions, and the contract needs both.

## The deprecation lifecycle

The contract now carries the replacement and the deprecated original:

```graphql
  """When the final leg arrives."""
  finalArrivalTime: DateTime!
  """When the final leg arrives."""
  finalArrivalDate: DateTime! @deprecated(reason: "Use `finalArrivalTime`.")
```

The order matters: add the replacement so clients can move, mark the old field `@deprecated` with a reason that names the replacement, and keep the old field fully functional. Both fields return the same instant, and the response carries no warning. A deprecated field is a signal to tools and humans, not a behavior change.

The signal travels through introspection. The GraphQL specification defines `@deprecated` with a `reason` that defaults to "No longer supported", and `__Field` reports `isDeprecated` and `deprecationReason`. The `fields` selection on `__Type` takes `includeDeprecated`, false unless a client asks, so code generators and editors list only supported fields. A client that wants the whole history asks for it:

```graphql
{ __type(name: "Itinerary") { fields(includeDeprecated: true) { name isDeprecated deprecationReason } } }
```

The reason string is what a client author reads. Name the replacement and nothing else; "legacy" gives no direction.

{% include excalidraw.html file="11-deprecation-lifecycle" alt="A four-step timeline runs left to right across three rows. The change row shows adding the replacement finalArrivalTime, deprecating finalArrivalDate with a reason, observing usage through operation telemetry, and removing the field with a sign-off. The check row shows the check output for each step: a check mark for the added field, a check mark for the deprecated field, no schema change for the observation step, and a cross reporting that the deprecated field was removed, with exit 1 by default and a warning with exit 0 when the sign-off rule is set. The clients row shows existing clients unchanged, both fields executing with the old one hidden from fields by default, clients migrating on their own schedule, and a client that still selects the old field failing validation." caption="Figure 11.2: The deprecation lifecycle. Each step has a gate line, and the last step is a recorded decision, not a side effect." %}

The first two steps ship together, and the check reports them as `✔  Field Itinerary.finalArrivalDate is deprecated` and `✔  Field finalArrivalTime was added to object type Itinerary`. Then comes the waiting: operation-level telemetry shows which clients still select `finalArrivalDate`, and until that count is zero the field stays.

Removal fails by default with a message that says what was deleted: `✖  Field finalArrivalDate (deprecated) was removed from object type Itinerary`. Deleting a deprecated field is still breaking for any client that never moved, so the check doesn't relax because the field was marked. A pull request that removes it after the usage evidence is in sets the `suppressRemovalOfDeprecatedField` rule. The same line then prints with a warning sign and the check exits 0. The rule is a sign-off recorded in the pull request, not a default.

A client that selects the removed field fails validation: the response is an error that names the field, with no `data`.

## Running the check

`contracts/scripts/breaking.sh`, also available as `npm --prefix contracts run breaking`, compares the working tree's `contracts/schema/**/*.graphql` with the same files on a base ref, `origin/main` by default. It runs `graphql-inspector diff` and exits 0 for a pass, 1 for a breaking change, and 2 when the base ref doesn't resolve, so a missing fetch can't pass by accident. When the base ref holds no `.graphql` files, as on the pull request that first adds the contract, it prints `no baseline schema on origin/main yet - skipping breaking check (first introduction)` and exits 0.

Three environment variables test the check without a commit per case:

| Variable | Effect |
|---|---|
| `BASE_DIR=<dir>` | Compare against a directory of `.graphql` files instead of a git ref |
| `NEW_DIR=<dir>` | Use a directory as the new side instead of the working tree |
| `BREAKING_RULES=<list>` | Pass each comma-separated name to the tool as a `--rule` |

Each fixture copies the contract into a base and a new directory, applies one textual edit to the new side, and passes only when both the exit code and the full change line, including its check, warning or cross mark, match. The edit must match exactly once: an edit that silently did nothing would report "no changes" and pass a case that expected a failure.

```bash
edit() {
  python3 -I -c '
import sys

path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit("fixture did not apply: %d occurrences in %s of %r" % (text.count(old), path, old))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
' "$@" || { echo "lib.sh: FAIL, fixture did not apply: $1" >&2; return 1; }
}
```

### Should dangerous changes fail?

The default gate fails only on breaking changes. An added enum value or optional argument is routine evolution, and a gate that blocks it teaches teams to avoid the evolution GraphQL makes cheap, or to switch the check off. The warning still has to be seen: with `GITHUB_ACTIONS=true` the script echoes each warning line as `::warning title=Dangerous schema change::<line>`, which GitHub shows as an annotation on the pull request without failing the job.

A public API with generated clients can run strict mode, `BREAKING_RULES=dangerousBreaking`. The enum-value fixture then prints `✖  Enum value TRANSSHIP was added to enum HandlingEventType` and exits 1. Strict mode changes the verdict, not the schema.

### What the check cannot see

A diff sees structure. Four things sit outside it:

| Blind spot | Why | Cover it with |
|---|---|---|
| Behavior | A field that keeps its name and type but returns a different value, such as local time becoming UTC, produces no diff | A new field through the lifecycle above, and tests that assert values |
| Default values | The check sees a default only as text, and what an omitted argument means to the resolver is invisible | Tests on how the resolver treats an omitted argument |
| Error codes | `extensions.code` values live in the response, not the SDL | Documentation and tests; they follow the enum rules, so a client with a default branch survives a new code |
| Deprecation state | Removing `@deprecated` is a safe change, so a stack that forgot the directive still conforms (the check prints `✔  Field Itinerary.finalArrivalDate is no longer deprecated`) | An explicit assertion on `isDeprecated` per stack |

## How Quarkus and Python model it

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

Strawberry takes the reason as a keyword argument, `deprecation_reason`, and introspection reports it with no further work. SmallRye GraphQL has its own annotation, `io.smallrye.graphql.api.Deprecated`, with a `reason`; `java.lang.Deprecated` carries no reason. The reason is written once on the record component, and the schema observer `ContractSchemaDetails` applies it with graphql-java's `deprecate(reason)`:

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

The same observer trims the generated ` (ISO-8601)` suffix from date descriptions, which keeps the description of `finalArrivalTime` equal to the contract's.

> **🤖 Explore with your agent**
>
> "In `examples/11-evolution`, add an optional `timeZone: String` field to `Location` in `contracts/schema/shipping/` and on both stacks, then sketch the removal of `Itinerary.finalArrivalDate`. Classify each edit as safe, dangerous or breaking, say which one the default gate fails and what sign-off lets it through, and keep the deprecation reason naming `finalArrivalTime`."
>
> Check: copy `contracts/schema` to a base directory before editing, then run `BASE_DIR=<base>/schema NEW_DIR=contracts/schema bash contracts/scripts/breaking.sh`: it exits 0 with `✔  Field timeZone was added to object type Location`.

## Build, run, observe

Start the stack. Quarkus listens on port 8210 and Python on 8211.

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

Then run the check on two copies of the contract, the second without the deprecated field, and again with the sign-off rule:

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

The first command exits 1 and the second exits 0.

`bash examples/11-evolution/verify.sh` runs the checks on both stacks and then every gate case. It passes when both fields return the same instant with no deprecation warning, introspection reports the one deprecated element in the schema, and each fixture's exit code and change line match its class.

Experiments:

- Remove `finalArrivalDate` from a fixture copy of the contract: the check exits 1 until `suppressRemovalOfDeprecatedField` is set.
- Change `trackingId: TrackingId!` to `TrackingId` on `Cargo`: breaking, exit 1.
- Change `voyageNumber: String` to `String!` on the input: breaking, exit 1.
- Add `TRANSSHIP` to `HandlingEventType`: exit 0 with a warning, and exit 1 under `dangerousBreaking`.
- Add an optional `destination: UnLocode` argument to `Query.cargos`: dangerous, exit 0.

> **Decision**
>
> Evolution is where the contract and evolution style axis of the decision framework is paid for. One schema with additive changes, deprecation with a reason and a gate on removals replaces version numbers, and the cost moves from clients, who never need to upgrade, to the team, which has to watch usage before it deletes anything. With clients nobody on the team has met, a field can't be removed on a guess. The check is a file in the repository that every owning team can read and every pull request runs through. The tracking view uses one endpoint, deprecates `finalArrivalDate` in favor of `finalArrivalTime` on both stacks, fails the default gate on breaking changes only, annotates dangerous ones on the pull request and keeps `dangerousBreaking` for teams that want it.

## For deeper coverage

- [GraphQL specification: Field Deprecation, @deprecated, Schema Introspection](https://spec.graphql.org/).
- [GraphQL Inspector documentation](https://the-guild.dev/graphql/inspector/docs): the diff rules and change classes (safe, dangerous, breaking) the check runs.
- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd ed. (O'Reilly, 2026): backward and forward compatibility. Listed on the [Bibliography](../../bibliography/) page.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): schema design and evolution more broadly.
- *Cloud Native Design Patterns*, "Versioning & Evolution" (Appendix B): the wider evolution patterns this deprecation lifecycle is one instance of.
