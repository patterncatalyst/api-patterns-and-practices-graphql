---
title: "Nullability and null propagation"
order: 4
part: "The Schema: SDL & the Type System"
description: "What a null means in a GraphQL response, how list and non-null wrappers decide where a failure lands, and how the tracking schema places its nullable fields so one failed source costs a field instead of the page."
duration: "15 min read"
---

## Learning objectives

By the end of this chapter you can:

- Read the six list/non-null wrapper combinations (`T`, `T!`, `[T]`, `[T!]`, `[T]!`, `[T!]!`) and what each permits in a response.
- Trace a `null` bubbling from a failed `Leg.loadLocation` up to the nearest nullable ancestor.
- Distinguish a request error from an execution error and explain where each leaves `data`.
- Place nullable "fuses" (`Cargo.itinerary`, `Leg.voyage`, `CargoEdge.node`) at service-ownership boundaries so one failure costs a field, not the page.
- Contrast SmallRye's and Strawberry's opposite nullability defaults and the mistake each default invites.

## Why this matters

Chapter 3 introduced the list and non-null wrappers and left one question open: a `null` in a non-null position cannot be returned, so what happens instead? This chapter answers it. In most APIs a failure is an exception, a status code and an empty body. In GraphQL a failure is a field that could not be filled, and the schema's nullability decides how much of the response goes with it. You will read the six wrapper combinations, follow one `null` up a response tree, see where the error path points, and then look at which fields of the tracking schema are nullable and why.

The code is in `examples/04-nullability/`. It starts from the Chapter 3 example and turns the fields that cross a service boundary (`Leg.voyage`, `Leg.loadLocation`, `Leg.unloadLocation` and `Cargo.delivery`) into resolvers over sources. Three new cargos make a source fail in three different ways. The `verify.sh` there asserts every value in the "On the wire" section.

## Null is a value with a contract

Two different things produce a `null` in a response, and the schema is the only place where a client can tell them apart. The first is absence. Cargo `XYZ789` has been booked and no itinerary has been assigned, so `itinerary` is `null` and nothing is wrong: the response has no `errors`, and the field's description in the canonical SDL says "Null until the routing service has assigned one." The second is failure. The voyage service is down, the location reference data has no entry for a code, or the delivery service raises. The field is `null` there too, and the response carries an entry in `errors` that says what happened and where.

Both are legitimate, and a client needs to handle both. What the client cannot do is guess which fields may be `null` from the data it has seen. That information is the wrapper on each field, and the wrapper is a promise. `Cargo.id` is `ID!` and will never be `null`. `Leg.voyage` is `Voyage` without a bang, so a client that renders a voyage must be ready for it to be missing. A non-null wrapper is a stronger promise for the server to keep, and it has a price: when the server cannot keep it, the failure has to go somewhere.

The specification defines this precisely in its Type System sections "Non-Null" and "List", and in "Handling Execution Errors". Samer Buna's *GraphQL in Action* introduces the same wrappers in "Designing a GraphQL schema"; both are listed on the [Bibliography](../../bibliography/) page.

## Reading wrapper types

Two wrappers modify any type `T`. `T!` means the value is never `null`. `[T]` means a list whose items are `T`. They nest, and a wrapper chain reads inside-out: the innermost type is the item, and each wrapper outside it says something about the thing it wraps. That gives six combinations for a list-or-not field.

{% include excalidraw.html file="04-wrapper-matrix" alt="A table of six rows and four columns. The columns are the SDL wrapper, what the response may hold, the Quarkus spelling and the Python spelling. The rows are T, T!, [T], [T!], [T]! and [T!]!. The rows for T, T! and [T!]! are highlighted in light amber and labelled with the tracking view fields Leg.voyage, Leg.loadLocation and Itinerary.legs. For example the T row allows an object or null and is spelled T with no annotation in Java and T | None in Python, and the [T!]! row allows an empty list or a list of objects and is spelled @NonNull List<@NonNull T> in Java and list[T] in Python." caption="Figure 4.1 — The six wrapper combinations, what each allows in a response, and how each stack spells it" %}

Take `[Leg]` first, because it is the loosest. The field may be `null`, the list may be empty, and any item may be `null`. Each `!` removes one of those cases. `[Leg!]` forbids `null` items but still allows a `null` list. `[Leg]!` forbids a `null` list but still allows `null` items. `[Leg!]!` forbids all of them, which is the strongest promise and the one `Itinerary.legs` makes. Empty is a separate question that no wrapper answers: `[Leg!]!` permits `[]`, and the description "never empty for an assigned itinerary" is how the schema states the rest.

The position of the `!` matters more than its presence. `[Leg!]` and `[Leg]!` look alike and fail differently. A `null` item in `[Leg]!` leaves the list intact with a hole in it. A `null` item in `[Leg!]` cannot be placed, so the list itself becomes `null`. Clients that iterate over a list should know which of these the schema promises before they write the loop.

## Defaults are opposite on the two stacks

The six combinations exist in both frameworks, but each framework has a different default, and the difference is the most common source of drift between a code-first schema and the contract.

SmallRye follows Java. A type is nullable unless it is annotated, so a plain `Leg` is `Leg` and `@NonNull Leg` is `Leg!`. Primitives cannot be `null`, so a Java `boolean` is `Boolean!` with no annotation. For lists the annotation goes on the position it describes: `@NonNull List<@NonNull Leg>` is `[Leg!]!`, and a bare `List<Leg>` is `[Leg]`. Strawberry follows Python's type hints. An annotation is non-null unless it says otherwise, so `Leg` is `Leg!`, `Leg | None` is `Leg`, and `list[Leg]` is `[Leg!]!`. A nullable list of nullable items has to be spelled out as `list[Leg | None] | None`.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Type("Leg")
public record Leg(
        @Ignore String voyageNumber,
        @Ignore String loadUnLocode,
        @Ignore String unloadUnLocode,
        @NonNull Instant loadTime,
        @NonNull Instant unloadTime) {}

// In the @GraphQLApi class: nullable by default, @NonNull where the contract has a bang.
public Voyage voyage(@Source Leg leg) { ... }

@NonNull
public Location loadLocation(@Source Leg leg) { ... }
```

```python
@strawberry.type
class Leg:
    voyage_number: strawberry.Private[str]
    load_un_locode: strawberry.Private[str]
    unload_un_locode: strawberry.Private[str]
    load_time: datetime
    unload_time: datetime

    # Non-null by default, nullable where the contract has none.
    @strawberry.field
    def voyage(self) -> Voyage | None: ...

    @strawberry.field
    def load_location(self) -> Location: ...
```

The two defaults produce opposite mistakes. In Java the failure is a forgotten `@NonNull`: the field is looser than the contract, and the field prints as `Location` where the contract says `Location!`. In Python the failure is a forgotten `| None`: the field is stricter than the contract, which hides a missing case from clients until one request fails and blanks its parent. The conformance check from Chapter 0 catches both, because it diffs in both directions. This chapter's `verify.sh` also reads five wrapper chains through introspection, so a changed default cannot go unnoticed.

SmallRye has a scoped way to flip its default. `io.smallrye.graphql.api.DefaultNonNull` on a class or a package makes everything inside it non-null, and `io.smallrye.graphql.api.Nullable` on a position turns it back. Both are marked experimental and are not part of the specification. The example keeps explicit `@NonNull`, which reads the same on every field and survives a move to another package.

## Execution errors and the nullable boundary

A request can fail in two places. A request error means the document failed to parse, failed validation, or carried variables that did not coerce. Nothing ran, and the response has `errors` and no `data`. Chapter 3 showed three of them. An execution error means a field failed while the server was producing data: a resolver raised, or returned a value that does not fit the field's type. Execution errors are the subject here. The specification calls them execution errors in its current text, and earlier editions call them field errors; the two terms name the same thing.

The rule in "Handling Execution Errors" has three parts. When a field produces an execution error, the field's value is `null` and an entry is appended to `errors`. If the field's type is non-null, `null` is not a legal value for it, so the nearest parent field takes the `null` instead. If that parent is non-null as well, the rule applies again to the parent's parent. When the chain reaches the root with no nullable position left, `data` itself is `null`. The server stops at the first position that can hold a `null`, which this chapter calls the nullable boundary.

Two consequences follow. First, an error is reported once, at the field that failed, however far the `null` travels. Second, nullability is a blast-radius setting. Every non-null wrapper between a failing field and the next nullable ancestor widens the part of the response that disappears, and every nullable field narrows it. The schema author sets that radius once, for every client, and only one direction of change is free. Making a field nullable later is breaking for clients that relied on the promise. Making it non-null later is safe for output fields, but it still counts as drift against the contract.

GraphQL-over-HTTP does not change this. Null propagation happens during execution, so `data` is present, and the current draft then asks for a `2xx` status (required when `data` is not null) and recommends `294` when `errors` sit beside `data`. Both stacks answer `200` (Chapter 6 compares this with the draft). Either way a client reads the body, not the status code.

## Walking a null up the tree

The seed has a cargo built for this: `MNO901`, "Textiles". It has one leg, and the leg loads at a code, `XXBAD`, that the location source has never heard of. The location source does not raise. It returns `null`, which is how a dangling reference looks from the inside.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@ApplicationScoped
public class LocationSource {
    public Location getLocation(String unLocode) {
        return data.location(unLocode);   // null for XXBAD
    }
}
```

```python
class LocationSource:
    def get_location(self, un_locode: str) -> Location | None:
        return LOCATIONS.get(un_locode)   # None for XXBAD
```

Now ask for the leg:

```graphql
{
  cargo(trackingId: "MNO901") {
    trackingId
    itinerary { legs { loadLocation { unLocode } voyage { number } } }
  }
}
```

`Leg.loadLocation` is `Location!`, so the `null` is not allowed there. Figure 4.2 follows it.

{% include excalidraw.html file="04-null-bubbling-walk" alt="A vertical tree of five response positions. Four of them are numbered steps, joined by three amber arrows pointing upward, and no arrow leaves step 4. From the bottom: step 1, Leg.loadLocation of type Location non-null, where the source returned null for XXBAD; step 2, legs index 0 of type Leg non-null, which cannot hold a null; step 3, Itinerary.legs of type list of non-null Leg, non-null, which cannot hold a null; step 4, Cargo.itinerary of type Itinerary, which is nullable and holds the null. Above them Query.cargo is untouched. To the right of each position is the value in data after that step. On the far right an error box shows errors[0].path as cargo, itinerary, legs, 0, loadLocation, with an amber arrow pointing at step 1. A blue box at the bottom shows the whole response." caption="Figure 4.2 — One null climbing from Leg.loadLocation to Cargo.itinerary, with the error path fixed at the field that failed" %}

Follow the numbers in the figure. At step 1, the resolver for `loadLocation` returns `null` for a `Location!` field. That is the failure, and the server records the error here. At step 2, the leg at index 0 would have to hold a missing `loadLocation`, and the field is non-null, so the leg itself becomes `null`. But `legs` is `[Leg!]!`, so at step 3 a `null` item is not allowed in the list, and the list becomes `null`. `Itinerary.legs` is non-null too, so the whole `Itinerary` object would be left without a valid `legs`. At step 4 the climb reaches `Cargo.itinerary`, which is `Itinerary` without a bang. It accepts the `null` and the climb stops.

Everything outside that boundary survives. The `trackingId` selected next to `itinerary` is still in the response, and so is the cargo. The part that disappeared is one subtree, the itinerary. Python answers:

```json
{"data":{"cargo":{"trackingId":"MNO901","itinerary":null}},"errors":[{"message":"Cannot return null for non-nullable field Leg.loadLocation.","locations":[{"line":1,"column":63}],"path":["cargo","itinerary","legs",0,"loadLocation"]}]}
```

The `voyage` selected next to `loadLocation` is gone with the rest of the leg, even though the voyage service is healthy and `V100S` exists. That is the cost of the non-null promise made visible. A resolver that works perfectly cannot rescue a sibling of a failure that bubbled over it.

## Error paths name where it broke, not where the null landed

Compare `data` and `errors` in that response. The `null` is at `data.cargo.itinerary`. The error path ends at `loadLocation`. The two differ because they answer different questions. `data` tells a client what it can render. `path` tells an operator which resolver to look at. If the path named the nullable boundary, every log line for a failure in a leg would say `itinerary`, and nobody could find the field that produced it.

A `path` is the list of response keys from the root to the failing field. A string is a field's response key and an integer is a list index, so `["cargo","itinerary","legs",0,"loadLocation"]` reads as "the `loadLocation` of the first leg". The types matter: `0` and `"0"` are different paths, and the `verify.sh` assertion compares the whole array with types intact. Chapter 1 quoted a path of this shape for a voyage failure, and `JKL567` produces it exactly. Its leg is on voyage `V404X`, and the voyage source raises. `Leg.voyage` is nullable, so nothing climbs:

```json
{"errors":[{"message":"System error","locations":[{"line":1,"column":89}],"path":["cargo","itinerary","legs",0,"voyage"],"extensions":{"classification":"DataFetchingException"}}],"data":{"cargo":{"trackingId":"JKL567","itinerary":{"legs":[{"loadLocation":{"unLocode":"USNYC"},"voyage":null}]}}}}
```

This is the response a client can render: the cargo, its itinerary, the leg, the load location, and a `null` voyage to explain with a placeholder. The path stays at the field and the failure stays one level deep.

Aliases change the keys. A path uses the response key, the alias when there is one, so `{ ok: cargo(...) bad: cargo(...) }` reports `["bad","delivery"]` rather than `["cargo","delivery"]`. The two aliased fields are independent siblings, and a `null` that stops at `bad` does not touch `ok`. This is also how a client with several lookups in one request keeps one failure from taking the others: each lookup sits under its own nullable root field.

The message text is another matter. SmallRye hides the message of an unchecked exception by default and answers `"System error"` with a classification. Strawberry passes `str(exc)`, so the same failure reads `voyage service unavailable`. The null-in-a-non-null-position messages differ as well. The example asserts the path, the count and the shape of `data`, and one message: the `MNO901` message contains `loadLocation`, because both engines name the field. What an error message should carry, and what it should withhold, is the subject of Chapter 9.

## Placing the fuses in the tracking schema

Think of each nullable field as a fuse. When something downstream fails, a fuse blows and stops the failure from taking out the circuit. The schema author decides where the fuses go, and the rule of thumb is to put one wherever a field's value comes from a different owner than its parent.

The tracking schema does that in four places, shown in Figure 4.3.

{% include excalidraw.html file="04-nullable-fuses" alt="Three panels side by side. The left panel lists the tracking schema as an indented tree: Query.cargo, Cargo.itinerary and Leg.voyage drawn in light amber as nullable fuses, with Itinerary.legs drawn in white as non-null, and a second branch Query.cargos, edges and CargoEdge.node, where node is a fuse. The middle panel, canonical, shows five rows from data down to edges[1].node for a page of three edges where the node of edge 1 fails: only the node row is amber and null, a dashed arrow reads stops here, and the result is two of three cargos delivered with one error and data present. The right panel, strict, shows the same five rows all amber with four upward arrows from edges[1].node to data, and the result is zero of three cargos delivered with one error and data null." caption="Figure 4.3 — The nullable fuses in the tracking schema, and the blast radius of one failed edge with and without the fuse on CargoEdge.node" %}

`Query.cargo` is nullable. A cargo that does not exist is absence, and a cargo that fails to resolve is a failure, and neither should turn `data` into `null`. `PQR234` shows the second case. Its delivery source raises, `Cargo.delivery` is `Delivery!`, and so the `null` leaves the cargo, and `Query.cargo` takes it:

```json
{"errors":[{"message":"System error","locations":[{"line":1,"column":44}],"path":["cargo","delivery"],"extensions":{"classification":"DataFetchingException"}}],"data":{"cargo":null}}
```

`data` is still an object, because `Query.cargo` can hold the `null`. If it did not, `data` would be `null` and the client would lose every other field in the request. `Cargo.itinerary` is nullable for a reason of its own, which is absence before routing, and it doubles as the fuse for everything below it, as `MNO901` showed. `Leg.voyage` is nullable because the voyage service is a separate owner whose outage should degrade a leg and not the cargo.

The fourth fuse belongs to Chapter 12, which builds the connection types, but its effect shows up here. `CargoEdge.node` is `Cargo` and not `Cargo!`, with a description that says why: "Null when the cargo failed to resolve, so one bad item nulls its edge instead of the whole page." The right panel of the figure shows the alternative. With a strict `node: Cargo!`, one failing item cannot be placed in its edge, the edge is non-null in `[CargoEdge!]!`, the list is non-null in the connection, and the connection is non-null on `Query.cargos`. Every position up to the root is non-null, so `data` becomes `null` and a page of fifty cargos is lost to one failure. The strict schema is shown here as an illustration and is not in the canonical SDL. A nullable item buys a page that survives; its price is that the client must check `node` for `null` on every edge.

The fuses are not free, and they are not the default. Each one is a field a client has to check. The tracking schema puts them at ownership boundaries and keeps the fields inside one owner's data non-null, so a client's null checks cluster where failures come from.

## Input-side nullability

The same wrappers apply to arguments and variables, with rules for what may be passed where. An argument declared `TrackingId!` cannot receive `null`, as a literal or as a variable's value. `cargo(trackingId: null)` fails validation before anything runs. A variable that is declared nullable cannot be used in a non-null position either: `query($t: TrackingId) { cargo(trackingId: $t) { trackingId } }` is rejected, because a client could send no value, and the argument cannot take one. The specification allows the combination only when the variable or the argument has a non-null default. The reverse is fine: a `TrackingId!` variable can feed a nullable argument. A non-null variable that receives `null` at run time fails during coercion, before execution.

All three of these are request errors. Both stacks return `200` with `errors` and no `data` (Chapter 6 compares this with the draft), the same shape as Chapter 3's validation failures, and they never reach a resolver.

For nullable inputs there is a third state that outputs do not have. An absent argument and an argument set to `null` are different inputs, and a server may treat them differently. Chapter 8 shows how each stack declares the optional fields of `RegisterHandlingEventInput`, and which declaration keeps the two states apart.

## The experimental escape hatch

A specification working group has been exploring ways to let a client opt out of propagation, and there is vocabulary for it, such as semantic nullability: a field that is `null` only on error, and so is documented as non-null for data and nullable for failures. None of it is in the published specification.

SmallRye registers one experimental directive for the idea, `@experimental_disableErrorPropagation`, and the live schema lists it. Placed on an operation, it asks the engine to keep a `null` where it was produced and not move it. On Quarkus the `MNO901` query with the directive leaves `loadLocation` as `null` in `legs[0]` and still returns `voyage`, with the same error path. Strawberry's schema does not define the directive, so it answers with a request error. A directive that only one engine defines is not part of a contract two stacks share, and the canonical schema does not use it. Treat it as something to read about and not as a setting.

## On the wire

Start the stack and ask for the three fault seeds. Quarkus is on `8140` and Python on `8141`.

```bash
docker compose -f examples/04-nullability/compose.yaml up -d --build
curl -s localhost:8140/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"JKL567\") { trackingId itinerary { legs { loadLocation { unLocode } voyage { number } } } } }"}'
```

`JKL567`, the nullable boundary at `voyage`. Python (`8141`) answers with the same data and the message `voyage service unavailable`:

```json
{"data":{"cargo":{"trackingId":"JKL567","itinerary":{"legs":[{"loadLocation":{"unLocode":"USNYC"},"voyage":null}]}}},"errors":[{"message":"voyage service unavailable","locations":[{"line":1,"column":89}],"path":["cargo","itinerary","legs",0,"voyage"]}]}
```

`MNO901`, the null climbing to `itinerary`. Quarkus names the position in its message:

```json
{"errors":[{"message":"The field at path '/cargo/itinerary/legs[0]/loadLocation' was declared as a non null type, but the code involved in retrieving data has wrongly returned a null value.  The graphql specification requires that the parent field be set to null, or if that is non nullable that it bubble up null to its parent and so on. The non-nullable type is 'Location' within parent type 'Leg'","path":["cargo","itinerary","legs",0,"loadLocation"],"extensions":{"classification":"NullValueInNonNullableField"}}],"data":{"cargo":{"trackingId":"MNO901","itinerary":null}}}
```

`PQR234`, `delivery` nulling `cargo` on Python:

```json
{"data":{"cargo":null},"errors":[{"message":"delivery service unavailable","locations":[{"line":1,"column":44}],"path":["cargo","delivery"]}]}
```

Two aliased lookups, one of them failing, on Python:

```json
{"data":{"ok":{"trackingId":"ABC123"},"bad":null},"errors":[{"message":"delivery service unavailable","locations":[{"line":1,"column":96}],"path":["bad","delivery"]}]}
```

Selecting `PQR234` without `delivery` returns `{"data":{"cargo":{"trackingId":"PQR234"}}}` with no `errors`, because the delivery source is never called. A source that is not asked cannot fail.

| Check | Expected |
|---|---|
| `XYZ789` `itinerary` | `null`, no `errors` |
| `JKL567` | 1 error, path `["cargo","itinerary","legs",0,"voyage"]`; `voyage` null; `loadLocation.unLocode` `USNYC`; `trackingId` `JKL567` |
| `MNO901` | `itinerary` null; `trackingId` `MNO901`; 1 error, path `["cargo","itinerary","legs",0,"loadLocation"]`, message contains `loadLocation` |
| `PQR234` with `delivery` | `data.cargo` null, `data` still an object; 1 error, path `["cargo","delivery"]` |
| `ok` and `bad` aliases | `ok.trackingId` `ABC123`; `bad` null; path `["bad","delivery"]` |
| `PQR234` without `delivery` | no `errors` |
| `cargo(trackingId: null)`; nullable variable in a non-null position; `null` for a `TrackingId!` variable | `errors`, no `data` |
| `Itinerary.legs`, `Leg.voyage`, `Leg.loadLocation`, `Cargo.delivery`, `Cargo.itinerary` | `NON_NULL>LIST>NON_NULL>OBJECT(Leg)`, `OBJECT(Voyage)`, `NON_NULL>OBJECT(Location)`, `NON_NULL>OBJECT(Delivery)`, `OBJECT(Itinerary)` |

`bash examples/04-nullability/verify.sh` runs all of it on both stacks, ends with the conformance check against `contracts/schema/`, and prints `PASS` only when both stacks hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Nullability is where the <em>aggregation across sources</em> axis of Chapter 2 costs something concrete. A graph that stitches the cargo, routing and handling owners together will see one of them fail, and the nullable fields at each ownership boundary (<code>Cargo.itinerary</code>, <code>Leg.voyage</code>, <code>CargoEdge.node</code>) decide whether that failure costs a field or the page. The <em>client diversity and shape variance</em> axis is served by the same choice: every client selects its own slice, so the schema, not each client, has to say which fields may be missing. The <em>contract and evolution style</em> axis explains why the choice is made carefully, because loosening a field to nullable later breaks clients that trusted the bang, so the tracking schema starts strict inside an owner's data and nullable at the boundaries. The <em>operational and security cost</em> axis shows in the two stacks' opposite defaults and in error messages that differ by engine, which the conformance gate and path-level assertions cover. The tracking view keeps <code>Query.cargo</code> nullable so one bad cargo never nulls <code>data</code>, keeps <code>Delivery!</code> and <code>Location!</code> non-null where a missing value is a defect, and treats propagation as the rule to design around, not a setting to disable.</p></div>

## Where this goes next

This chapter covered what a `null` can mean, the six wrapper combinations, how a failed field climbs to the first nullable ancestor, why the error path stays at the origin, and where the tracking schema places its fuses. It also showed the two stacks' opposite defaults and the one place they differ on the wire, the error message.

Chapter 5 turns the conformance check into a workflow, with each stack exporting its schema and a diff in two directions, and uses a tightened nullability as the example of drift that only one direction catches. Chapter 6 looks at how the engine orders the resolvers whose failures this chapter caused. Chapter 9 returns to errors as data, with `userErrors`, error extensions and what a message should say. Chapter 11 runs nullability changes through the breaking-change gate in both directions: loosening an output or tightening an input breaks clients, while tightening an output passes the gate even though it removes a fuse. Chapter 12 builds the connection whose `node` field is the fourth fuse.

For the formal definitions, read the Type System sections "Non-Null" and "List" and the execution section "Handling Execution Errors" of the [GraphQL specification](https://spec.graphql.org/), and the [GraphQL-over-HTTP specification](https://http-spec.graphql.org/draft/) for status codes. *GraphQL in Action* covers schema design in "Designing a GraphQL schema", which is listed on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021) — "Designing a GraphQL schema" covers nullability and wrapper design.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024) — error handling and schema-design practices around partial failure.
- Cloud Native Design Patterns — [Communications](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/02-communications/) chapter, for pushing resilience to a boundary instead of into every caller.
- [GraphQL specification](https://spec.graphql.org/) — the "Non-Null", "List" and "Handling Execution Errors" sections this chapter is built on.
