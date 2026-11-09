---
title: "SDL and the type system in depth"
order: 3
part: "The Schema: SDL & the Type System"
description: "The type kinds a GraphQL schema is built from (scalars, enums, objects, interfaces, unions, input types), how a selection maps onto them, and how SmallRye and Strawberry express each one code-first."
duration: "13 min read"
---

## Learning objectives

By the end of this chapter you can:

- Identify the GraphQL type kinds (scalars, enums, objects, interfaces, unions, input types) and the wrappers (`T!`, `[T]`, `[T!]!`) that modify them.
- Implement a custom scalar (`TrackingId`, `UnLocode`, `DateTime`) with its three coercions (serialize, parse value, parse literal) on both SmallRye GraphQL and Strawberry.
- Use the `Node` interface and `Query.node` for Relay-style global object identification.
- Explain why the tracking schema uses an interface rather than a union when types share an `id`.
- Map a client selection onto the schema's type graph and classify the request-time validation failures it can trigger.

## Why this matters

Every GraphQL service is described by a schema, the schema is made of a small set of type kinds, and nearly every question a client or reviewer asks about the API reduces to which kind a type is and how it is wrapped. The code is in `examples/03-sdl-type-system/`: an in-memory seed of five locations, three voyages and two cargos, served on Quarkus and Python, which return the same bytes for the same selection.

## The schema is a type graph

A schema is a set of named types connected by fields. Schema Definition Language (SDL) is the text form: `type Cargo { ... }` declares a node, and each field inside it is an edge to another type or to a leaf. A client never asks for a type. It starts at a root operation type and walks edges, and the shape of what it wrote is the shape of what comes back. The roots are declared once, in `contracts/schema/shipping/schema.graphql`:

```graphql
schema {
  query: Query
  mutation: Mutation
  subscription: Subscription
}
```

`Query` holds the read entry points: `cargo`, `cargos`, `location`, `voyage` and `node`. `Mutation` and `Subscription` are the write and push entry points. A type no root can reach is dead weight, and a field no type exposes cannot be queried.

The canonical schema is split across six files by ownership: `scalars.graphql` (the custom scalars, `Node` and `PageInfo`), `location.graphql` and `voyage.graphql` (reference types), `cargo.graphql` and `handling.graphql` (aggregates) and `schema.graphql` (roots). GraphQL has no notion of a file. Tools load the six as one document, so a type in `location.graphql` is usable in `cargo.graphql` without an import, and a duplicate name in two files is an error. The conformance check in `lib.sh` therefore points at a glob.

{% include excalidraw.html file="03-type-system-map" alt="Map of the tracking view's types grouped by kind in five horizontal bands. The Interface band holds Node with the field id of type ID non-null, drawn in light amber with three amber arrows labelled implements pointing down to Cargo, Location and Voyage. The Object types band holds Cargo, Location and Voyage in light amber on one row, then RouteSpecification, Itinerary and Leg, and below them CarrierMovement, Delivery and HandlingActivity. The Enums band holds TransportStatus with five values, RoutingStatus with three and HandlingEventType with five. The Scalars band holds one box for the built-in String, Int, Float, Boolean and ID, and boxes for the custom scalars TrackingId, UnLocode and DateTime, the last two marked as carrying a specifiedBy URL. The last band holds a dashed box for the input type RegisterHandlingEventInput, used by the handling-event mutation, and a box explaining the wrappers T non-null, list of T and list of non-null T non-null, with Itinerary.legs read inside-out as list of Leg non-null." caption="Figure 3.1: The tracking view's types by kind. Only three object types implement Node, and every leaf of a selection ends in a scalar or an enum." %}

## Scalars: built-in and custom

A scalar is a leaf. A selection can't go below it, so `trackingId { x }` is rejected. GraphQL has five built-in scalars: `Int` (signed 32-bit), `Float` (double precision), `String` (UTF-8), `Boolean` and `ID` (an opaque identifier, serialized as a string, accepting a string or an integer on input). The tracking view uses `String`, `Boolean` and `ID` and adds three custom scalars.

`TrackingId` and `UnLocode` are string-backed. They exist so the schema says what the string is: a client sees `location(unLocode: UnLocode!)` and not `location(code: String!)`, and a code generator can map each to its own type. `DateTime` carries an instant:

```graphql
scalar DateTime @specifiedBy(url: "https://www.rfc-editor.org/rfc/rfc3339")
```

`@specifiedBy` points a custom scalar at the document that defines its format. `UnLocode` points at the UN/LOCODE list. `TrackingId` has no URL because its value is opaque by design.

The specification defines result coercion (resolver value to response) and input coercion (argument or variable to internal value). Implementations split input in two, so each scalar has three functions: **serialize** for results, **parse value** for a JSON value from the variables map, and **parse literal** for a value written inline, which is an abstract syntax tree node and not yet a JSON value.

{% include excalidraw.html file="03-scalar-coercion" alt="Flow of a DateTime value through its three coercions. On the left, two blue entry boxes: a literal in the document, completionTime with the string 2026-10-15T00:00:00Z, and a variable in the JSON, a map with t set to 2026-10-15T02:00:00+02:00. The literal goes into a box labelled parse literal, the AST string value, and the variable into a box labelled parse value, the JSON string. A dashed box between them, labelled rejected, lists a number, bad text and a value with no offset, and ends in a request error with no data; dashed arrows run to it from both parse boxes. Amber arrows run from both parse boxes into a light amber box in the middle, the internal value, a Java Instant or a Python datetime in UTC. A further amber arrow leads to a box labelled serialize, UTC with whole seconds and the suffix Z, and down to a blue output box holding the JSON string 2026-10-15T00:00:00Z." caption="Figure 3.2: Three coercions around one internal value. Whatever enters, the output is one canonical string." %}

A loose scalar on the input side makes the stacks disagree, so both reject a number for `UnLocode`, as a literal and as a variable, with errors and no `data`. In Python, `parse_value=str` would have turned `123` into `"123"`, so the scalar checks the type first. SmallRye's `CustomStringScalar` refuses a non-string literal at validation.

`DateTime` is pinned to one output form on both stacks: UTC, whole seconds, a `Z` suffix, as in `2026-10-15T00:00:00Z`. RFC 3339 also permits offsets and fractional seconds, so two correct serializers can print `2026-10-15T00:00:00Z` and `2026-10-15T00:00:00+00:00`, and every client that compares or caches by string sees two values for one instant. Strawberry needs a custom serializer for the pinned form. SmallRye's built-in mapping for `java.time.Instant` already prints it for whole-second values.

## Object types and fields

An object type is a named set of fields, and each field has a type, optional arguments and a description. `Cargo` is the root of the tracking view:

```graphql
type Cargo implements Node {
  id: ID!
  trackingId: TrackingId!
  description: String!
  origin: Location!
  destination: Location!
  routeSpecification: RouteSpecification!
  delivery: Delivery!
  itinerary: Itinerary
  handlingHistory(first: Int, after: String, last: Int, before: String): HandlingEventConnection!
}
```

Read it as edges. `origin` and `destination` lead to `Location`. `itinerary` leads to `Itinerary`, whose `legs` lead to `Leg`, whose `voyage` leads to `Voyage`, whose `schedule` leads to `CarrierMovement`. The graph has a cycle, through `Cargo.handlingHistory` to `HandlingEvent` and its `cargo` field back to `Cargo`. A response is still finite, because a selection is finite text and every branch must end in leaves.

Descriptions are part of the contract. Every type, field, argument and enum value in the canonical SDL has one, documentation panels display them, linters require them, and the conformance check fails when a served description differs from the canonical text.

Here the objects are embedded: a `Leg` holds its `Voyage` and `Location` as ordinary properties and `Delivery` is a stored constant, so no field below `Query` has a resolver. Reading the parent's property, the default in both frameworks, does all the work.

## Enums

An enum is a closed set of names. `TransportStatus` has five values (`NOT_RECEIVED`, `IN_PORT`, `ONBOARD_CARRIER`, `CLAIMED`, `UNKNOWN`), `RoutingStatus` three and `HandlingEventType` five. On the wire a value is always its name as a JSON string, never a number. In a document it's written bare (`type: LOAD`), and a variable carries it as `"LOAD"`. A client that sends `"TELEPORT"` gets a coercion error before any resolver runs.

A closed set has a cost for evolution. Adding a value to an output enum is additive for the schema and a possible break for a client that switches exhaustively over the known values, so the breaking-change gate treats an added value as a risk and a removed value as a failure.

The stacks list enum values differently. Strawberry uses declaration order; SmallRye returns them alphabetically (`CLAIMED`, `IN_PORT`, `NOT_RECEIVED`, `ONBOARD_CARRIER`, `UNKNOWN`). Order carries no meaning in GraphQL, so the canonical diff ignores it, and a client that renders a dropdown from introspection should sort the values itself.

## Interfaces and Node

An interface is an abstract type: fields that any implementing object type must provide. `Node` has one field, `id: ID!`, and three types implement it: `Cargo`, `Location` and `Voyage`. A field whose type is an interface can return any implementer. The selection asks for the shared fields directly and for the rest through an inline fragment.

`Node` supports Relay's Global Object Identification contract. Every object that can be fetched by itself exposes a globally unique, opaque `id`, and `Query.node(id: ID!)` takes one and returns whatever it names. Here the ids are `cargo_ABC123`, `loc_NLRTM` and `voy_V200E`. Clients must not parse the prefix. See the [Global Object Identification specification](https://relay.dev/graphql/objectidentification.htm).

```graphql
{
  node(id: "loc_NLRTM") {
    __typename
    ... on Location { unLocode }
    ... on Cargo { trackingId }
  }
}
```

The server looks up `loc_NLRTM` and finds a `Location`. Because `Node` is abstract, `__typename` reports the runtime type, and each inline fragment applies only if the runtime type matches its condition. `... on Cargo` contributes nothing: no error and no `null`. The response is `{"node":{"__typename":"Location","unLocode":"NLRTM"}}`.

{% include excalidraw.html file="03-node-dispatch" alt="Dispatch of a node query. A blue box on the left holds the operation: node with id loc_NLRTM, selecting __typename, a fragment on Location selecting unLocode, and a fragment on Cargo selecting trackingId. An arrow labelled id leads to a box for Query.node, which looks the id up in the seed and returns the object, with a grey box above it describing the id space: loc_ is Location, cargo_ is Cargo and voy_ is Voyage. An amber arrow leads to a light amber box, the runtime type Location, which implements Node. From there an amber arrow leads down to a light amber box for the fragment on Location, which applies and adds unLocode, and an arrow from that box points to a response box holding __typename Location and unLocode NLRTM. A dashed box below, the fragment on Cargo, is skipped because the object is not a Cargo, and its dashed arrow to the response box is labelled adds nothing." caption="Figure 3.3: Node dispatch. The id selects the object, the object's runtime type selects the fragments, and a fragment for another type adds nothing." %}

Validation enforces the shared-field rule. `node(id: "loc_NLRTM") { unLocode }` is rejected before execution, because `Node` has no field `unLocode`, and the server cannot know which implementer the id will name. The document must say what to do for each. Python's error suggests the fix ("Did you mean to use an inline fragment on 'Location'?"); Quarkus reports `FieldUndefined`. Both return HTTP 200 with `errors` and no `data`.

## Unions, and why this schema has none

A union is the other abstract type: one of several object types, with no fields of its own. An interface promises fields. A union promises only membership, so every selection on it needs inline fragments, and `__typename` is the only field available without one. The usual use is a result that may be one of several unrelated shapes:

```graphql
# Illustration only: not part of the canonical schema.
union SearchResult = Cargo | Location | Voyage

type Query {
  search(text: String!): [SearchResult!]!
}
```

The tracking view's abstract case has a shared field, the id, so an interface fits. A union would hide that the three types share an identity contract, which is what `Node` expresses. Use a union when the members share nothing a client can rely on, and an interface as soon as they do. Mutation results shaped as unions of success and error types are common; this schema models domain failures as `userErrors` data instead.

## Lists and non-null wrappers

`[T]` is a list of `T`, and `T!` is non-null. They nest, and a chain reads inside-out. `Itinerary.legs` is `[Leg!]!`: `Leg!` says each element is non-null, the brackets make a list, and the final `!` says the list itself is non-null. The field is never `null`, never contains a `null`, and may be empty in principle (its description says an assigned itinerary never is). `Cargo.itinerary` is the contrast: `Itinerary` without a bang is `null` until routing has assigned a route.

A `null` in a non-null position can't be returned, so it moves up to the nearest nullable parent. The default differs by stack: a Java field is nullable unless annotated `@NonNull`, and a Strawberry field is non-null unless annotated `| None`. Java code spells out every non-null and Python code every nullable, and the conformance check fails if either stack gets one wrong.

## Input types

Input types mirror object types for arguments. `input RegisterHandlingEventInput { ... }` looks like an object type but differs in three ways. Its fields can have default values. It may contain only scalars, enums and other input types, never an object, interface or union. And it appears only in input positions: an argument or a variable. A type is one or the other, never both, because an output field can take arguments and return an interface or union, and neither means anything in a value the client sends.

```graphql
input RegisterHandlingEventInput {
  trackingId: TrackingId!
  type: HandlingEventType!
  location: UnLocode!
  voyageNumber: String
  completionTime: DateTime!
  idempotencyKey: String
}
```

It combines two custom scalars, an enum and `DateTime` among the required fields with two optional strings. The seed doesn't serve it; a served mutation is where `DateTime` input coercion meets an argument.

## How a selection maps onto types

A selection is a path through the type graph, and each step has a type:

```graphql
query {
  cargo(trackingId: "ABC123") {
    itinerary { legs { voyage { number } } }
  }
}
```

`cargo` is a field of `Query` that returns `Cargo`. On `Cargo`, `itinerary` returns `Itinerary`. On that, `legs` returns `[Leg!]!`, and on each `Leg`, `voyage` returns `Voyage`, where `number` is a `String!` leaf. The response mirrors the selection: an object for each object field, an array for each list, a leaf for each scalar.

{% include excalidraw.html file="03-selection-onto-types" alt="Three columns of five rows linked by amber arrows. The left column, selection, shows the query text in blue boxes indented one step per level: query, cargo with the trackingId argument ABC123, itinerary, legs, and voyage with number. The middle column shows the type each field lands on, in light amber boxes from the second row down: Query, Cargo marked nullable, Itinerary marked nullable, a list of non-null Leg, and Voyage marked nullable, joined by grey downward arrows labelled cargo, itinerary, legs and voyage. The right column shows the response in the same nesting, indented to match: data, cargo, itinerary, legs and voyage with number V100S." caption="Figure 3.4: The walk from query text to types to response shape. Every field name selects an edge, and the result is nested the same way." %}

Validation checks each field against the type it hangs from, each argument against its declared type, each fragment condition against the possible types and each selection against the kind of its field. The specification calls these request errors, and they are raised before execution begins. Over `application/json` they return HTTP 200 with `errors` and no `data`. Three are common: a field not on the interface (`node { unLocode }`), an object field with no subselection (`cargo { origin }`, because `Location!` needs one) and a subselection on a scalar (`trackingId { x }`). Errors that arise while a resolver runs are execution errors (older editions call them field errors). They return partial `data` beside `errors`.

Nothing ran for a request error: no source was called and no state changed, so a client can fix the document and retry safely.

## Code-first on two stacks

Both stacks build their schema from code, and the canonical SDL is the yardstick. First the `Node` interface with `Location`:

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Interface
@Description("""
        A global object identifier, unique across the whole graph. Implements the
        Relay Global Object Identification contract used by `Query.node`.""")
public interface Node {

    @Id
    @NonNull
    @Description("The globally unique, opaque identifier of this object.")
    String getId();
}

@Type("Location")
@Description("A port or terminal, identified by its UN/LOCODE.")
public record Location(
        String id,
        @NonNull @Description("The UN/LOCODE, for example `NLRTM`.") UnLocode unLocode,
        @NonNull @Description("The human-readable name, for example `Rotterdam`.") String name,
        @NonNull @Description("The ISO 3166-1 alpha-2 country code, for example `NL`.") String country)
        implements Node {

    @Override
    @Id
    @NonNull
    @Description("The globally unique identifier of this location.")
    public String getId() {
        return id;
    }
}
```

```python
@strawberry.interface(
    description=(
        "A global object identifier, unique across the whole graph. Implements the\n"
        "Relay Global Object Identification contract used by `Query.node`."
    )
)
class Node:
    id: strawberry.ID = strawberry.field(
        description="The globally unique, opaque identifier of this object."
    )


@strawberry.type(description="A port or terminal, identified by its UN/LOCODE.")
class Location(Node):
    id: strawberry.ID = strawberry.field(
        description="The globally unique identifier of this location."
    )
    un_locode: UnLocode = strawberry.field(description="The UN/LOCODE, for example `NLRTM`.")
    name: str = strawberry.field(description="The human-readable name, for example `Rotterdam`.")
    country: str = strawberry.field(
        description="The ISO 3166-1 alpha-2 country code, for example `NL`."
    )
```

SmallRye maps an interface's fields from getter-named methods only, so implementing records carry an explicit `getId()`. `@Id` turns a `String` into `ID`. `@Type` marks objects, `@NonNull` a bang, `List<@NonNull Leg>` gives `[Leg!]`, a primitive `boolean` is `Boolean!` with no annotation, and `@Description` documents types, fields, arguments and enum constants. Strawberry needs no annotation for a bang, because non-null is the default, and camelCase is automatic: `un_locode` becomes `unLocode`. An enum is a Python `Enum` with `strawberry.enum_value(..., description=...)` per member.

`DateTime` shows the largest difference between the stacks:

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Type("RouteSpecification")
@Description("The customer's routing requirements for a cargo.")
public record RouteSpecification(
        @NonNull @Description("Required origin.") Location origin,
        @NonNull @Description("Required destination.") Location destination,
        @NonNull @Description("The date by which the cargo must arrive.") Instant arrivalDeadline) {}
```

```python
    datetime: strawberry.scalar(
        name="DateTime",
        description="An RFC 3339 date-time in UTC, for example `2026-10-15T09:30:00Z`.",
        specified_by_url="https://www.rfc-editor.org/rfc/rfc3339",
        serialize=_serialize_datetime,
        parse_value=_parse_datetime,
    ),
}
```

SmallRye maps `java.time.Instant` and the other `java.time` date types to its built-in `DateTime` scalar, so the field needs no scalar code. Strawberry has a default for `datetime` too, but its output differs from the pinned form, so `scalar_map` replaces it with a definition whose serializer writes the pinned form and whose parser refuses a datetime with no UTC offset. Fields stay annotated with the plain `datetime`. The same map turns the two `NewType` strings into `TrackingId` and `UnLocode`.

SmallRye's defaults differ from the contract in three places, and `ContractSchemaDetails` corrects each through the CDI event SmallRye fires before it builds the schema (`quarkus.smallrye-graphql.events.enabled=true`):

| SmallRye default | Correction |
|---|---|
| Appends ` (ISO-8601)` to the description of every date-typed field | Strips the suffix |
| Describes `DateTime` as "Scalar for DateTime" and gives it no `@specifiedBy` URL | Sets the `DateTime` description, the scalars' URLs and the `Query` description |
| `SchemaTransformer` rebuilds types, so an interface's type resolver returns stale ones and `... on Location` fails to match | Re-points each interface's type resolver at the executing schema's own types |

> **🤖 Explore with your agent**
>
> "In examples/03-sdl-type-system, add a `Container` object type with `id: ID!` and `containerNumber: String!` that implements `Node`, in both quarkus/ and python/. Give it a `container_` id prefix, make `Query.node` return it, and update contracts/schema/shipping/ so the three types that share an `id` stay an interface and not a union."
>
> Check: `node(id: "container_1") { __typename ... on Container { containerNumber } }` returns `Container` on ports 8130 and 8131, and introspection lists four possible types for `Node`.

## Build, run, observe

Start the stack and send the cargo query. Quarkus is on `8130` and Python on `8131`; both return the same bytes.

```bash
docker compose -f examples/03-sdl-type-system/compose.yaml up -d --build
curl -s localhost:8130/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId routeSpecification { arrivalDeadline } itinerary { finalArrivalDate legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } loadTime unloadTime } } delivery { transportStatus routingStatus misdirected lastKnownLocation { unLocode } currentVoyage { number } estimatedTimeOfArrival nextExpectedActivity { type location { unLocode } voyage { number } } } } }"}'
```

```json
{"data":{"cargo":{"trackingId":"ABC123","routeSpecification":{"arrivalDeadline":"2026-10-15T00:00:00Z"},"itinerary":{"finalArrivalDate":"2026-10-11T18:00:00Z","legs":[{"voyage":{"number":"V100S"},"loadLocation":{"unLocode":"USNYC"},"unloadLocation":{"unLocode":"DEHAM"},"loadTime":"2026-10-01T08:00:00Z","unloadTime":"2026-10-09T14:00:00Z"},{"voyage":{"number":"V200E"},"loadLocation":{"unLocode":"DEHAM"},"unloadLocation":{"unLocode":"NLRTM"},"loadTime":"2026-10-10T06:00:00Z","unloadTime":"2026-10-11T18:00:00Z"}]},"delivery":{"transportStatus":"ONBOARD_CARRIER","routingStatus":"ROUTED","misdirected":false,"lastKnownLocation":{"unLocode":"USNYC"},"currentVoyage":{"number":"V100S"},"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V100S"}}}}}}
```

The second cargo has no route yet, and absence is data. With `XYZ789` (dropping `routeSpecification`, `legs` and `misdirected` to keep the line short):

```json
{"data":{"cargo":{"trackingId":"XYZ789","itinerary":null,"delivery":{"transportStatus":"NOT_RECEIVED","routingStatus":"NOT_ROUTED","lastKnownLocation":null,"currentVoyage":null,"estimatedTimeOfArrival":null,"nextExpectedActivity":{"type":"RECEIVE","location":{"unLocode":"SGSIN"},"voyage":null}}}}}
```

Selecting a field that is not on the interface is a validation failure, and the stacks word it differently:

```bash
curl -s localhost:8130/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ node(id: \"loc_NLRTM\") { unLocode } }"}'
```

```json
{"errors":[{"message":"Validation error (FieldUndefined@[node/unLocode]) : Field 'unLocode' in type 'Node' is undefined","locations":[{"line":1,"column":27}],"extensions":{"classification":"ValidationError"}}]}
```

The specification says `data` should be absent when an error is raised before execution begins. Quarkus omits it; Python answers `"data":null` with the message `Cannot query field 'unLocode' on type 'Node'. Did you mean to use an inline fragment on 'Location'?`.

`bash examples/03-sdl-type-system/verify.sh` runs everything on both stacks, ends with the conformance check against `contracts/schema/`, and prints `PASS` only when both stacks hold. Experiments:

- Query `node` with an unknown id, `location(unLocode: "ZZZZZ")` or `voyage(voyageNumber: "V999X")`: each returns `null` under its own name, with no error.
- Select `cargo { origin }` with no subselection, or `trackingId { x }`: HTTP 200, `errors`, no `data`.
- Pass `location(unLocode: 123)`: `errors`, no `data`, on both stacks.
- Ask `node(id: "loc_NLRTM")` with only `... on Cargo { trackingId }`: exactly `{"__typename":"Location"}`.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>The type system is where the <em>contract and evolution style</em> axis becomes concrete. Every type, field and enum value in the canonical SDL is a public promise that many unknown clients read, so naming a scalar <code>UnLocode</code> instead of <code>String</code>, closing a set as an enum and describing every field push the cost of ambiguity to the schema author, where it is cheapest to pay. <em>Client diversity and shape variance</em> is served by the object graph itself: three clients select three slices of <code>Cargo</code> with no change to the server. <em>Aggregation across sources</em> shows in <code>Node</code>, one id space spanning three owners behind one field. <em>Operational and security cost</em> registers a small charge, since an abstract type and a custom scalar need per-stack code the contract does not generate, and a conformance gate to catch drift in it. The tracking view uses interfaces where members share a field, avoids unions until members share nothing, and pins <code>DateTime</code> to one wire format, because one canonical string per instant costs less than every client normalizing two.</p></div>

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): "Designing a GraphQL schema" covers scalars, enums, interfaces and unions. See the [Bibliography](../../bibliography/) page.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): schema design choices, including when to prefer an interface over a union.
- [GraphQL specification: Type System](https://spec.graphql.org/): the authoritative definitions of scalars (including `@specifiedBy`), enums, objects, interfaces, unions and input types.
- [Relay: Global Object Identification](https://relay.dev/graphql/objectidentification.htm): the `Node` interface contract behind `Query.node`.
