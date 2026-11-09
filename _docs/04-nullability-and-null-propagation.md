---
title: "Nullability and null propagation"
order: 4
part: "The Schema: SDL & the Type System"
description: "What a null means in a GraphQL response, how list and non-null wrappers decide where a failure lands, and how the tracking schema places its nullable fields so one failed source costs a field instead of the page."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Read the six list/non-null wrapper combinations (`T`, `T!`, `[T]`, `[T!]`, `[T]!`, `[T!]!`) and what each permits in a response.
- Trace a `null` bubbling from a failed `Leg.loadLocation` up to the nearest nullable ancestor.
- Distinguish a request error from an execution error and explain where each leaves `data`.
- Place nullable "fuses" (`Cargo.itinerary`, `Leg.voyage`, `CargoEdge.node`) at service-ownership boundaries so one failure costs a field, not the page.
- Contrast SmallRye's and Strawberry's opposite nullability defaults and the mistake each default invites.

## Why this matters

A `null` in a non-null position can't be returned, so something else has to give. In most APIs a failure is an exception, a status code and an empty body. In GraphQL a failure is a field that could not be filled, and the schema's nullability decides how much of the response goes with it.

The code is in `examples/04-nullability/`. The fields that cross a service boundary (`Leg.voyage`, `Leg.loadLocation`, `Leg.unloadLocation` and `Cargo.delivery`) are resolvers over sources, and three seeded cargos make a source fail in three different ways.

## Null is a value with a contract

Two things produce a `null` in a response, and the schema is the only place a client can tell them apart. The first is absence. Cargo `XYZ789` is booked and has no itinerary yet, so `itinerary` is `null` and nothing is wrong: the response has no `errors`, and the field's description says "Null until the routing service has assigned one." The second is failure. The voyage service is down, location reference data has no entry for a code, or the delivery service raises. The field is `null` there too, and `errors` says what happened and where.

A client has to handle both, and it can't guess which fields may be `null` from the data it has seen. The wrapper on each field is a promise. `Cargo.id` is `ID!` and is never `null`. `Leg.voyage` is `Voyage` without a bang, so a client that renders a voyage must be ready for it to be missing. A non-null wrapper is a stronger promise for the server, and when the server can't keep it, the failure has to go somewhere. The rules are in the specification's "Non-Null", "List" and "Handling Execution Errors" sections.

## Reading wrapper types

`T!` means the value is never `null`. `[T]` means a list whose items are `T`. They nest, and a chain reads inside-out: the innermost type is the item, and each wrapper outside it qualifies what it wraps. That gives six combinations for a field.

{% include excalidraw.html file="04-wrapper-matrix" alt="A table of six rows and four columns. The columns are the SDL wrapper, what the response may hold, the Quarkus spelling and the Python spelling. The rows are T, T!, [T], [T!], [T]! and [T!]!. The rows for T, T! and [T!]! are highlighted in light amber and labelled with the tracking view fields Leg.voyage, Leg.loadLocation and Itinerary.legs. For example the T row allows an object or null and is spelled T with no annotation in Java and T | None in Python, and the [T!]! row allows an empty list or a list of objects and is spelled @NonNull List<@NonNull T> in Java and list[T] in Python." caption="Figure 4.1: The six wrapper combinations, what each allows in a response, and how each stack spells it" %}

`[Leg]` is the loosest. The field may be `null`, the list may be empty, and any item may be `null`. Each `!` removes one case. `[Leg!]` forbids `null` items but allows a `null` list. `[Leg]!` forbids a `null` list but allows `null` items. `[Leg!]!` forbids all of them, and is the promise `Itinerary.legs` makes. Empty is a separate question no wrapper answers: `[Leg!]!` permits `[]`, and the description "never empty for an assigned itinerary" states the rest.

Position matters more than presence. `[Leg!]` and `[Leg]!` look alike and fail differently. A `null` item in `[Leg]!` leaves the list intact with a hole in it. A `null` item in `[Leg!]` can't be placed, so the list itself becomes `null`. A client should know which one the schema promises before it writes the loop.

## Defaults are opposite on the two stacks

Each framework has a different default, and the difference is the most common source of drift between a code-first schema and the contract.

| | SmallRye | Strawberry |
|---|---|---|
| Default | Nullable unless annotated | Non-null unless annotated |
| `Leg` | `Leg` | `Leg!` |
| Nullable `Leg` | `Leg` (no annotation) | `Leg \| None` |
| `[Leg!]!` | `@NonNull List<@NonNull Leg>` | `list[Leg]` |
| `[Leg]` | `List<Leg>` | `list[Leg \| None] \| None` |

A Java primitive such as `boolean` is `Boolean!` with no annotation. Here are the `Leg` resolvers on both stacks:

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Type("Leg")
@Description("One hop of an itinerary on a single voyage.")
public record Leg(
        @Ignore String voyageNumber,
        @Ignore String loadUnLocode,
        @Ignore String unloadUnLocode,
        @NonNull @Description("When the cargo is loaded.") Instant loadTime,
        @NonNull @Description("When the cargo is unloaded.") Instant unloadTime) {}

    @Description("The voyage that carries this leg. Null when the voyage service is unavailable.")
    public Voyage voyage(@Source Leg leg) {
        return voyages.getVoyage(leg.voyageNumber());
    }

    @Description("Where the cargo is loaded.")
    @NonNull
    public Location loadLocation(@Source Leg leg) {
        return locations.getLocation(leg.loadUnLocode());
    }
```

```python
@strawberry.type(description="One hop of an itinerary on a single voyage.")
class Leg:
    voyage_number: strawberry.Private[str]
    load_un_locode: strawberry.Private[str]
    unload_un_locode: strawberry.Private[str]
    load_time: datetime = strawberry.field(description="When the cargo is loaded.")
    unload_time: datetime = strawberry.field(description="When the cargo is unloaded.")

    @strawberry.field(
        description="The voyage that carries this leg. Null when the voyage service is unavailable."
    )
    def voyage(self) -> Voyage | None:
        return voyage_source.get_voyage(self.voyage_number)

    @strawberry.field(description="Where the cargo is loaded.")
    def load_location(self) -> Location:
        # The source returns None for a code it does not know. The field is
        # non-null, so graphql-core turns that None into an execution error.
        return location_source.get_location(self.load_un_locode)

    @strawberry.field(description="Where the cargo is unloaded.")
    def unload_location(self) -> Location:
        return location_source.get_location(self.unload_un_locode)
```

The defaults produce opposite mistakes. In Java the failure is a forgotten `@NonNull`: the field is looser than the contract and prints as `Location` where the contract says `Location!`. In Python it is a forgotten `| None`: the field is stricter than the contract, which hides a missing case from clients until one request fails and blanks its parent. The conformance check catches both, because it diffs in both directions.

SmallRye can flip its default in scope. `io.smallrye.graphql.api.DefaultNonNull` on a class or package makes everything inside non-null, and `io.smallrye.graphql.api.Nullable` turns a position back. Both are experimental and outside the specification. The code keeps explicit `@NonNull`, which reads the same on every field and survives a move to another package.

## Execution errors and the nullable boundary

A request can fail in two places. A **request error** means the document failed to parse, failed validation or carried variables that did not coerce. Nothing ran, and the response has `errors` and no `data`. An **execution error** means a field failed while the server produced data: a resolver raised, or returned a value that does not fit the field's type. Earlier editions of the specification call these field errors.

"Handling Execution Errors" has three parts. When a field errors, its value is `null` and an entry is appended to `errors`. If the field's type is non-null, `null` is not legal there, so the nearest parent field takes the `null` instead. If that parent is non-null too, the rule repeats. When the chain reaches the root with no nullable position left, `data` itself is `null`. The server stops at the first position that can hold a `null`: the **nullable boundary**.

Two consequences follow. An error is reported once, at the field that failed, however far the `null` travels. And nullability is a blast-radius setting: every non-null wrapper between a failing field and the next nullable ancestor widens the part of the response that disappears, and every nullable field narrows it. The author sets that radius once, for every client. Making a field nullable later breaks clients that relied on the promise. Making it non-null later passes for output fields, but it is still drift against the contract.

GraphQL-over-HTTP doesn't change this. Null propagation happens during execution, so `data` is present. The current draft then requires a `2xx` when `data` is not null, and recommends `294`, a custom code it ties to `application/graphql-response+json`, when `errors` sit beside `data`. Both stacks answer `200`. A client reads the body, not the status code.

## Walking a null up the tree

The seed has a cargo built for this: `MNO901`, "Textiles". It has one leg, and the leg loads at a code, `XXBAD`, that the location source has never heard of. The source doesn't raise. It returns `null`, which is how a dangling reference looks from the inside.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@ApplicationScoped
public class LocationSource {

    private final TrackingData data;

    LocationSource(TrackingData data) {
        this.data = data;
    }

    public Location getLocation(String unLocode) {
        return data.location(unLocode);
    }
}
```

```python
class LocationSource:
    """The location reference data. A code it does not know comes back as ``None``."""

    def get_location(self, un_locode: str) -> Location | None:
        return LOCATIONS.get(un_locode)
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

`Leg.loadLocation` is `Location!`, so the `null` is not allowed there.

{% include excalidraw.html file="04-null-bubbling-walk" alt="A vertical tree of five response positions. Four of them are numbered steps, joined by three amber arrows pointing upward, and no arrow leaves step 4. From the bottom: step 1, Leg.loadLocation of type Location non-null, where the source returned null for XXBAD; step 2, legs index 0 of type Leg non-null, which cannot hold a null; step 3, Itinerary.legs of type list of non-null Leg, non-null, which cannot hold a null; step 4, Cargo.itinerary of type Itinerary, which is nullable and holds the null. Above them Query.cargo is untouched. To the right of each position is the value in data after that step. On the far right an error box shows errors[0].path as cargo, itinerary, legs, 0, loadLocation, with an amber arrow pointing at step 1. A blue box at the bottom shows the whole response." caption="Figure 4.2: One null climbing from Leg.loadLocation to Cargo.itinerary, with the error path fixed at the field that failed" %}

At step 1 the resolver returns `null` for a `Location!` field. That is the failure, and the error is recorded here. At step 2 the leg at index 0 can't hold a missing non-null `loadLocation`, so the leg itself becomes `null`. `legs` is `[Leg!]!`, so at step 3 a `null` item isn't allowed in the list, and the list becomes `null`. `Itinerary.legs` is non-null too, so the `Itinerary` is left without a valid `legs`. At step 4 the climb reaches `Cargo.itinerary`, which is `Itinerary` without a bang. It accepts the `null` and the climb stops.

Everything outside the boundary survives: the `trackingId` selected next to `itinerary` is still in the response, and so is the cargo. Python answers:

```json
{"data":{"cargo":{"trackingId":"MNO901","itinerary":null}},"errors":[{"message":"Cannot return null for non-nullable field Leg.loadLocation.","locations":[{"line":1,"column":63}],"path":["cargo","itinerary","legs",0,"loadLocation"]}]}
```

The `voyage` selected next to `loadLocation` is gone with the rest of the leg, even though the voyage service is healthy. A resolver that works perfectly can't rescue a sibling of a failure that bubbled over it.

## Error paths name where it broke, not where the null landed

The `null` is at `data.cargo.itinerary`, and the error path ends at `loadLocation`. They answer different questions. `data` tells a client what it can render. `path` tells an operator which resolver to look at. If the path named the nullable boundary, every log line for a failure in a leg would say `itinerary`, and nobody could find the field that produced it.

A `path` is the list of response keys from the root to the failing field. A string is a field's response key and an integer is a list index, so `["cargo","itinerary","legs",0,"loadLocation"]` reads as "the `loadLocation` of the first leg". `0` and `"0"` are different paths. `JKL567` has a leg on voyage `V404X`, and the voyage source raises. `Leg.voyage` is nullable, so nothing climbs:

```json
{"errors":[{"message":"System error","locations":[{"line":1,"column":89}],"path":["cargo","itinerary","legs",0,"voyage"],"extensions":{"classification":"DataFetchingException"}}],"data":{"cargo":{"trackingId":"JKL567","itinerary":{"legs":[{"loadLocation":{"unLocode":"USNYC"},"voyage":null}]}}}}
```

This is a response a client can render: the cargo, its itinerary, the leg, the load location, and a `null` voyage to explain with a placeholder.

A path uses the response key, which is the alias when there is one. `{ ok: cargo(...) bad: cargo(...) }` reports `["bad","delivery"]` and not `["cargo","delivery"]`. Aliased fields are independent siblings, and a `null` that stops at `bad` doesn't touch `ok`. That is how a client with several lookups in one request keeps one failure from taking the others: each lookup sits under its own nullable root field.

Message text differs by engine. SmallRye hides the message of an unchecked exception and answers `"System error"` with a classification. Strawberry passes `str(exc)`, so the same failure reads `voyage service unavailable`. The messages for a null in a non-null position differ too, though both name the field.

## Placing the fuses in the tracking schema

Think of each nullable field as a fuse. When something downstream fails, a fuse blows and keeps the failure from taking out the circuit. The rule of thumb is to put one wherever a field's value comes from a different owner than its parent.

{% include excalidraw.html file="04-nullable-fuses" alt="Three panels side by side. The left panel lists the tracking schema as an indented tree: Query.cargo, Cargo.itinerary and Leg.voyage drawn in light amber as nullable fuses, with Itinerary.legs drawn in white as non-null, and a second branch Query.cargos, edges and CargoEdge.node, where node is a fuse. The middle panel, canonical, shows five rows from data down to edges[1].node for a page of three edges where the node of edge 1 fails: only the node row is amber and null, a dashed arrow reads stops here, and the result is two of three cargos delivered with one error and data present. The right panel, strict, shows the same five rows all amber with four upward arrows from edges[1].node to data, and the result is zero of three cargos delivered with one error and data null." caption="Figure 4.3: The nullable fuses in the tracking schema, and the blast radius of one failed edge with and without the fuse on CargoEdge.node" %}

`Query.cargo` is nullable. A cargo that doesn't exist is absence, a cargo that fails to resolve is a failure, and neither should turn `data` into `null`. `PQR234` shows the second case. Its delivery source raises, `Cargo.delivery` is `Delivery!`, so the `null` leaves the cargo, and `Query.cargo` takes it:

```json
{"errors":[{"message":"System error","locations":[{"line":1,"column":44}],"path":["cargo","delivery"],"extensions":{"classification":"DataFetchingException"}}],"data":{"cargo":null}}
```

`data` is still an object, because `Query.cargo` can hold the `null`. If it couldn't, `data` would be `null` and the client would lose every other field in the request. `Cargo.itinerary` is nullable for its own reason, absence before routing, and doubles as the fuse for everything below it. `Leg.voyage` is nullable because the voyage service is a separate owner whose outage should degrade a leg and not the cargo.

The fourth fuse is `CargoEdge.node` in the connection types. It is `Cargo` and not `Cargo!`, with a description that says why: "Null when the cargo failed to resolve, so one bad item nulls its edge instead of the whole page." With a strict `node: Cargo!`, one failing item can't be placed in its edge, the edge is non-null in `[CargoEdge!]!`, the list is non-null in the connection, and the connection is non-null on `Query.cargos`. Every position up to the root is non-null, so `data` becomes `null` and a page of fifty cargos is lost to one failure. The strict form is an illustration and isn't in the canonical SDL. A nullable item buys a page that survives, and its price is that the client must check `node` for `null` on every edge.

Fuses aren't free, and they aren't the default. Each one is a field a client has to check. The tracking schema puts them at ownership boundaries and keeps fields inside one owner's data non-null, so a client's null checks cluster where failures come from.

## Input-side nullability

The same wrappers apply to arguments and variables. An argument declared `TrackingId!` can't receive `null`, as a literal or as a variable's value, so `cargo(trackingId: null)` fails validation before anything runs. A variable declared nullable can't be used in a non-null position either: `query($t: TrackingId) { cargo(trackingId: $t) { trackingId } }` is rejected, because a client could send no value and the argument can't take one. The specification allows it only when the variable or the argument has a non-null default. The reverse is fine: a `TrackingId!` variable can feed a nullable argument. A non-null variable that receives `null` at run time fails during coercion.

All three are request errors. Both stacks answer `200` with `errors` and no `data`, and no resolver runs.

Nullable inputs have a third state that outputs don't. An absent argument and an argument set to `null` are different inputs, and a server may treat them differently. Each stack declares the optional fields of an input type such as `RegisterHandlingEventInput` in its own way, and only some declarations keep the two states apart.

## The experimental escape hatch

A specification working group has been exploring ways to let a client opt out of propagation, with vocabulary such as semantic nullability: a field that is `null` only on error, documented as non-null for data and nullable for failures. None of it is in the published specification.

SmallRye registers one experimental directive for the idea, `@experimental_disableErrorPropagation`. On an operation, it asks the engine to keep a `null` where it was produced and not move it. On Quarkus the `MNO901` query with the directive leaves `loadLocation` as `null` in `legs[0]` and still returns `voyage`, with the same error path. Strawberry's schema doesn't define the directive, so it answers with a request error. A directive that one engine defines isn't part of a contract two stacks share, and the canonical schema doesn't use it.

> **🤖 Explore with your agent**
>
> "In examples/04-nullability, change `Leg.voyage` to non-null in the Quarkus resolver (add `@NonNull`) and the Python resolver (drop `| None`), then work out what the `JKL567` cargo query returns. Apply the rule that a field fed by another owner stays nullable, and say which ancestor now takes the `null`."
>
> Check: restart the stack and re-run the `JKL567` query on ports 8140 and 8141. The prediction holds if `itinerary` is `null` and `errors[0].path` still ends at `voyage`.

## Build, run, observe

Start the stack and ask for the fault seeds. Quarkus is on `8140` and Python on `8141`.

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

`bash examples/04-nullability/verify.sh` runs all of it on both stacks, reads the wrapper chains of `Itinerary.legs`, `Leg.voyage`, `Leg.loadLocation`, `Cargo.delivery` and `Cargo.itinerary` through introspection, ends with the conformance check against `contracts/schema/`, and prints `PASS` only when both stacks hold. Experiments:

- Select `PQR234` without `delivery`: no `errors`, because the delivery source is never called. A source that is not asked can't fail.
- Send `cargo(trackingId: null)`, the nullable-variable query above, or `null` for a `TrackingId!` variable: `errors`, no `data`.
- Add `@experimental_disableErrorPropagation` to the `MNO901` query: on Quarkus `loadLocation` stays `null` and `voyage.number` is `V100S`; on Python the directive is unknown, so the response has `errors` and no `data`.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Nullability is where the <em>aggregation across sources</em> axis costs something concrete. A graph that stitches the cargo, routing and handling owners together will see one of them fail, and the nullable fields at each ownership boundary (<code>Cargo.itinerary</code>, <code>Leg.voyage</code>, <code>CargoEdge.node</code>) decide whether that failure costs a field or the page. <em>Client diversity and shape variance</em> is served by the same choice: every client selects its own slice, so the schema, not each client, says which fields may be missing. <em>Contract and evolution style</em> explains the care, because loosening a field to nullable later breaks clients that trusted the bang, so the tracking schema starts strict inside an owner's data and nullable at the boundaries. <em>Operational and security cost</em> shows in the two stacks' opposite defaults and in engine-specific error messages, which the conformance gate and path-level checks cover. The tracking view keeps <code>Query.cargo</code> nullable so one bad cargo never nulls <code>data</code>, keeps <code>Delivery!</code> and <code>Location!</code> non-null where a missing value is a defect, and treats propagation as the rule to design around, not a setting to disable.</p></div>

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): "Designing a GraphQL schema" covers nullability and wrapper design. See the [Bibliography](../../bibliography/) page.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): error handling and schema-design practices around partial failure.
- Cloud Native Design Patterns: [Communications](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/02-communications/) chapter, for pushing resilience to a boundary instead of into every caller.
- [GraphQL specification](https://spec.graphql.org/): the "Non-Null", "List" and "Handling Execution Errors" sections.
- [GraphQL-over-HTTP specification](https://http-spec.graphql.org/draft/): status codes.
