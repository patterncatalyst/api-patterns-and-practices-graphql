---
title: "SDL and the type system in depth"
order: 3
part: "The Schema: SDL & the Type System"
description: "The kinds of type a GraphQL schema is built from (scalars, enums, objects, interfaces, unions, input types and their wrappers), how a selection maps onto them, and how SmallRye and Strawberry express each one code-first."
duration: "16 min read"
---

## Learning objectives

By the end of this chapter you can:

- Identify the GraphQL type kinds (scalars, enums, objects, interfaces, unions, input types) and the wrapper combinations (`T!`, `[T]`, `[T!]!`) that modify them.
- Implement a custom scalar (`TrackingId`, `UnLocode`, `DateTime`) with its three coercions (serialize, parse value, parse literal) on both SmallRye GraphQL and Strawberry.
- Use the `Node` interface and `Query.node` for Relay-style global object identification.
- Explain why the tracking schema reaches for an interface rather than a union when types share an `id`.
- Map a client selection onto the schema's type graph and classify the request-time validation failures it can trigger.

## Why this matters

The tracking view already has a role and a boundary. This chapter gives it a vocabulary. Every GraphQL service is described by a schema, the schema is made of a small set of type kinds, and nearly every question a client or a reviewer asks about the API reduces to which kind a type is and how it is wrapped. You will read the canonical SDL for the tracking view kind by kind, run the full cargo graph on Quarkus and on Python, and watch the same selection produce the same bytes on both.

The code is in `examples/03-sdl-type-system/`. It starts from the lab in [the prerequisites and lab setup](../00-prerequisites-and-the-lab/) and replaces the canned cargo with an in-memory seed of five locations, three voyages and two cargos. Its `verify.sh` asserts every value in the "On the wire" section.

## The schema is a type graph

A schema is a set of named types connected by fields. Schema Definition Language (SDL) is the text form: `type Cargo { ... }` declares a node, and each field inside it is an edge to another type or to a leaf. A client never asks for a type. It starts at one of the root operation types and walks edges, and the shape of what it wrote is the shape of what comes back.

The root operation types are declared once, in `contracts/schema/shipping/schema.graphql`:

```graphql
schema {
  query: Query
  mutation: Mutation
  subscription: Subscription
}
```

`Query` holds the read entry points: `cargo`, `cargos`, `location`, `voyage` and `node`. `Mutation` and `Subscription` are the write and push entry points. Everything else in the schema is reachable only through them. A type that no root can reach is dead weight, and a field that no type exposes cannot be queried.

The canonical schema is split across six files, and the split follows ownership rather than syntax. `scalars.graphql` holds the three custom scalars, `Node` and `PageInfo`. `location.graphql` and `voyage.graphql` hold the reference types, `cargo.graphql` and `handling.graphql` hold the aggregates, and `schema.graphql` holds the roots. GraphQL has no notion of a file. The tools load the six files as one document, so a type declared in `location.graphql` is usable in `cargo.graphql` without an import, and a duplicate name in two files is an error. That is why the conformance check in `lib.sh` points at a glob.

{% include excalidraw.html file="03-type-system-map" alt="Map of the tracking view's types grouped by kind in five horizontal bands. The Interface band holds Node with the field id of type ID non-null, drawn in light amber with three amber arrows labelled implements pointing down to Cargo, Location and Voyage. The Object types band holds Cargo, Location and Voyage in light amber on one row, then RouteSpecification, Itinerary and Leg, and below them CarrierMovement, Delivery and HandlingActivity. The Enums band holds TransportStatus with five values, RoutingStatus with three and HandlingEventType with five. The Scalars band holds one box for the built-in String, Int, Float, Boolean and ID, and boxes for the custom scalars TrackingId, UnLocode and DateTime, the last two marked as carrying a specifiedBy URL. The last band holds a dashed box for the input type RegisterHandlingEventInput, served by the handling-event mutation later in the book, and a box explaining the wrappers T non-null, list of T and list of non-null T non-null, with Itinerary.legs read inside-out as list of Leg non-null." caption="Figure 3.1: The tracking view's types by kind. Only three object types implement Node, and every leaf of a selection ends in a scalar or an enum." %}

The sections below take the kinds in dependency order: leaves first (scalars and enums), then the object types that hang them together, then the abstract types, and finally the wrappers and the input side.

## Scalars: built-in and custom

A scalar is a leaf. A selection can never go below it, which is why `trackingId { x }` is rejected: `TrackingId` has no fields to select. GraphQL has five built-in scalars. `Int` is a signed 32-bit integer, `Float` is a double-precision float, `String` is UTF-8 text, `Boolean` is true or false, and `ID` is an opaque identifier that is serialized as a string and accepts either a string or an integer on input. The tracking view uses `String`, `Boolean` and `ID` directly and adds three custom scalars.

`TrackingId` and `UnLocode` are string-backed. They exist so the schema says what the string is: a client sees `location(unLocode: UnLocode!)` and not `location(code: String!)`, and a code generator can map each to its own type. `DateTime` carries an instant in time. The canonical SDL defines it once:

```graphql
scalar DateTime @specifiedBy(url: "https://www.rfc-editor.org/rfc/rfc3339")
```

`@specifiedBy` points a custom scalar at the document that defines its format, so a client author knows what the string means without asking. The [Scalars section of the specification](https://spec.graphql.org/) describes it; `UnLocode` points at the UN/LOCODE list and `TrackingId` has no URL because its value is opaque by design.

A scalar is more than a name. The specification defines two coercions for it: result coercion, from a resolver's internal value to the response, and input coercion, from an argument or variable to an internal value. Implementations split the input side in two, so each scalar has three functions: serialize for results, parse value for a JSON value from the variables map, and parse literal for a value written inline in the document. The input pair exists because an inline argument is part of the query text, an abstract syntax tree node, while a variable arrives as already-parsed JSON.

{% include excalidraw.html file="03-scalar-coercion" alt="Flow of a DateTime value through its three coercions. On the left, two blue entry boxes: a literal in the document, completionTime with the string 2026-10-15T00:00:00Z, and a variable in the JSON, a map with t set to 2026-10-15T02:00:00+02:00. The literal goes into a box labelled parse literal, the AST string value, and the variable into a box labelled parse value, the JSON string. A dashed box between them, labelled rejected, lists a number, bad text and a value with no offset, and ends in a request error with no data; dashed arrows run to it from both parse boxes. Amber arrows run from both parse boxes into a light amber box in the middle, the internal value, a Java Instant or a Python datetime in UTC. A further amber arrow leads to a box labelled serialize, UTC with whole seconds and the suffix Z, and down to a blue output box holding the JSON string 2026-10-15T00:00:00Z." caption="Figure 3.2: Three coercions around one internal value. Whatever enters, the output is one canonical string." %}

Input is where a loose scalar does damage, because a scalar that accepts too much makes the stacks disagree. Both stacks reject a number for `UnLocode`, as a literal and as a variable, and return errors with no `data`. `parse_value=str` would have turned `123` into `"123"`, so the Python scalar checks the type first, and SmallRye's `CustomStringScalar` refuses a non-string literal at validation. `verify.sh` asserts both rejections.

`DateTime` is pinned to one output format on both stacks: UTC, whole seconds, a `Z` suffix, as in `2026-10-15T00:00:00Z`. RFC 3339 permits offsets and fractional seconds, so left to defaults two correct serializers print `2026-10-15T00:00:00Z` and `2026-10-15T00:00:00+00:00`, and every client that compares or caches by string sees two values for one instant. Pinning one form removes the ambiguity. Strawberry needs a custom serializer for it. SmallRye's built-in mapping for `java.time.Instant` already prints that form for whole-second values, and the example checks every timestamp as an exact string to prove it.

## Object types and fields

An object type is a named set of fields, and each field has a type, optional arguments, and a description. `Cargo` is the root of the tracking view:

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

Read it as edges. `origin` and `destination` lead to `Location`. `routeSpecification` leads to a small object holding the two locations again and `arrivalDeadline`. `itinerary` leads to `Itinerary`, whose `legs` lead to `Leg`, whose `voyage` leads to `Voyage`, whose `schedule` leads to `CarrierMovement`. The type graph also has a cycle, through `Cargo.handlingHistory` to `HandlingEvent` and its `cargo` field back to `Cargo`. A response is still finite, because a selection is finite text and every branch of it must end in leaves.

Descriptions are part of the contract. Every type, field, argument and enum value in the canonical SDL has one, tools display them in documentation panels and linters require them, and the conformance check in `lib.sh` fails when a served description differs from the canonical text. This chapter's check compares the date-field descriptions too (see the last section).

In this chapter the objects are embedded. A `Leg` holds its `Voyage` and `Location` as ordinary properties, and `Delivery` is a stored constant, so no field below `Query` has a resolver. The default behavior of both frameworks, reading the property of the parent object, does all the work. Later chapters replace those properties with resolvers that call backing services.

## Enums

An enum is a closed set of names. `TransportStatus` has five: `NOT_RECEIVED`, `IN_PORT`, `ONBOARD_CARRIER`, `CLAIMED` and `UNKNOWN`. `RoutingStatus` has three and `HandlingEventType` has five. On the wire an enum value is always its name as a JSON string, never a number, so `"transportStatus": "ONBOARD_CARRIER"` is the whole representation. In a document an enum value is written bare, as in `type: LOAD`, and a variable carries it as the string `"LOAD"`. A client that sends `"TELEPORT"` gets a coercion error before any resolver runs, which is the point of closing the set.

Closed sets have a cost for evolution. Adding a value to an output enum is an additive change for the schema and a possible break for a client that switches exhaustively over the known values, which is why the breaking-change gate treats an added value as a risk and a removed value as a failure. The breaking-change gate revisits this in more depth later.

Descriptions work on enum values too, and the example asserts the sets through introspection. The stacks differ in one respect here. Strawberry lists values in declaration order. SmallRye returns them alphabetically (`CLAIMED`, `IN_PORT`, `NOT_RECEIVED`, `ONBOARD_CARRIER`, `UNKNOWN`). The order of enum values carries no meaning in GraphQL, so `verify.sh` compares the sets and the canonical diff ignores order, but a client that renders a dropdown from introspection should sort the values itself rather than rely on either.

## Interfaces and Node

An interface is an abstract type: a set of fields that any implementing object type must provide. `Node` has one field, `id: ID!`, and three types implement it: `Cargo`, `Location` and `Voyage`. A field whose type is an interface can return any implementer, and the selection can ask for the shared fields directly and for the rest through an inline fragment.

`Node` exists to support Relay's Global Object Identification contract. Every object that can be fetched by itself exposes a globally unique, opaque `id`, and `Query.node(id: ID!)` takes one and returns whatever it names. In this schema the ids are `cargo_ABC123`, `loc_NLRTM` and `voy_V200E`. The prefix is an implementation detail that clients must not parse. It lets the server find the object, and it is why a single field can serve three types. The contract is described in the [Global Object Identification specification](https://relay.dev/graphql/objectidentification.htm).

Take one query with a fragment for each of two types:

```graphql
{
  node(id: "loc_NLRTM") {
    __typename
    ... on Location { unLocode }
    ... on Cargo { trackingId }
  }
}
```

The server looks up `loc_NLRTM` and finds a `Location`. `Node` is abstract, so the server must decide the object's runtime type, and `__typename` reports it. Each inline fragment applies only if the runtime type matches its condition. `... on Location` matches and contributes `unLocode`. `... on Cargo` does not match and contributes nothing: no error and no `null`. The response is `{"node":{"__typename":"Location","unLocode":"NLRTM"}}`.

{% include excalidraw.html file="03-node-dispatch" alt="Dispatch of a node query. A blue box on the left holds the operation: node with id loc_NLRTM, selecting __typename, a fragment on Location selecting unLocode, and a fragment on Cargo selecting trackingId. An arrow labelled id leads to a box for Query.node, which looks the id up in the seed and returns the object, with a grey box above it describing the id space: loc_ is Location, cargo_ is Cargo and voy_ is Voyage. An amber arrow leads to a light amber box, the runtime type Location, which implements Node. From there an amber arrow leads down to a light amber box for the fragment on Location, which applies and adds unLocode, and an arrow from that box points to a response box holding __typename Location and unLocode NLRTM. A dashed box below, the fragment on Cargo, is skipped because the object is not a Cargo, and its dashed arrow to the response box is labelled adds nothing." caption="Figure 3.3: Node dispatch. The id selects the object, the object's runtime type selects the fragments, and a fragment for another type adds nothing." %}

The shared-field rule is what validation enforces. `node(id: "loc_NLRTM") { unLocode }` is rejected before execution, because `Node` has no field `unLocode`. The server cannot know which implementer the id will name, so the document must say what to do for each. Python's error suggests the fix ("Did you mean to use an inline fragment on 'Location'?"), while Quarkus reports `FieldUndefined`. Both return HTTP 200 with `errors` and no `data`.

## Unions, and why this schema has none

A union is the other abstract type: one of several object types, with no fields of its own. The difference from an interface is the contract. An interface promises fields. A union promises only membership, so every selection on it needs inline fragments, and `__typename` is the only field available without one. The usual use is a result that may be one of several unrelated shapes:

```graphql
# Illustration only: not part of the canonical schema.
union SearchResult = Cargo | Location | Voyage

type Query {
  search(text: String!): [SearchResult!]!
}
```

The tracking view does not need one. Its abstract case has a shared field, the id, so an interface fits better. A union would also hide that the three types share an identity contract, which is exactly what `Node` expresses. Reach for a union when the members share nothing a client can rely on, and for an interface as soon as they do. Mutation results shaped as unions of success and error types are a common pattern, and the error-handling design explains why this book models domain failures as `userErrors` data instead.

## Lists and non-null wrappers

Two wrappers modify any type. `[T]` is a list of `T`, and `T!` is non-null. They nest, and a wrapper chain reads inside-out. `Itinerary.legs` is `[Leg!]!`: the innermost `Leg!` says each element is non-null, the brackets make a list, and the final `!` says the list itself is non-null. So the field is never `null`, never contains a `null`, and may be empty in principle (the description says an assigned itinerary never is). `Cargo.itinerary` is the contrast: `Itinerary` without a bang, so it is `null` until routing has assigned a route.

Nullability is a promise about failure as much as about data, because a `null` in a non-null position cannot be returned and the `null` moves up to the nearest nullable parent. That is the subject of null propagation. The one fact needed here is the default difference between the stacks. A Java field is nullable unless annotated `@NonNull`, and a Strawberry field is non-null unless annotated `| None`. The example spells out every non-null in Java and every nullable in Python, and the conformance check fails if either stack gets one wrong.

## Input types

Input types are the mirror of object types for arguments. `input RegisterHandlingEventInput { ... }` looks like an object type but differs in three ways. Its fields can have default values. It may contain only scalars, enums and other input types, never an object, an interface or a union. And it appears only in input positions: an argument or a variable. A type is one or the other, never both, because an output field can take arguments and return an interface or a union, and neither means anything in a value the client sends.

The canonical schema has one, used by the one mutation:

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

It combines everything covered so far: two custom scalars, an enum and `DateTime` among the required fields, and two optional strings. This chapter does not serve it. The handling-event mutation does, and that is where `DateTime` input coercion meets a served argument. For now it is a map of what the input side can hold.

## How a selection maps onto types

A selection is a path through the type graph, and each step has a type. Take the operation a client writes to see a cargo's legs and voyages:

```graphql
query {
  cargo(trackingId: "ABC123") {
    itinerary { legs { voyage { number } } }
  }
}
```

`cargo` is a field of `Query` that returns `Cargo`. On `Cargo`, `itinerary` returns `Itinerary`. On that, `legs` returns `[Leg!]!`, and on each `Leg`, `voyage` returns `Voyage`, where `number` is a `String!` leaf. Each step is checked against the type the previous step produced. The response then mirrors the selection: an object for each object field, an array for each list, a leaf for each scalar. Figure 3.4 pairs the three side by side.

{% include excalidraw.html file="03-selection-onto-types" alt="Three columns of five rows linked by amber arrows. The left column, selection, shows the query text in blue boxes indented one step per level: query, cargo with the trackingId argument ABC123, itinerary, legs, and voyage with number. The middle column shows the type each field lands on, in light amber boxes from the second row down: Query, Cargo marked nullable, Itinerary marked nullable, a list of non-null Leg, and Voyage marked nullable, joined by grey downward arrows labelled cargo, itinerary, legs and voyage. The right column shows the response in the same nesting, indented to match: data, cargo, itinerary, legs and voyage with number V100S." caption="Figure 3.4: The walk from query text to types to response shape. Every field name selects an edge, and the result is nested the same way." %}

This is also what validation does, and it runs before any data is touched. The server checks each field against the type it hangs from, each argument against its declared type, each fragment condition against the possible types and each selection against the kind of its field. The specification calls these request errors: they are raised before execution begins. They return HTTP 200 with `errors` and no `data` over `application/json`, and the example asserts three: a field not on the interface (`node { unLocode }`), an object field with no subselection (`cargo { origin }`, rejected because `Location!` needs one) and a subselection on a scalar (`trackingId { x }`). Errors that arise while a resolver runs are execution errors in the current specification, which older editions called field errors. They return partial `data` beside `errors`, and they are the subject of execution-error handling, covered in depth next.

The three failures share a property that matters for caching and clients: nothing ran. No source was called and no state changed, so a client may fix the document and retry safely.

## Code-first on two stacks

Both stacks build their schema from code, and the canonical SDL is the yardstick. The following sections show the same type in each stack: the `Node` interface with `Location`, then the `DateTime` handling.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Interface
@Description("A global object identifier, unique across the whole graph. ...")
public interface Node {
    @Id @NonNull
    @Description("The globally unique, opaque identifier of this object.")
    String getId();
}

@Type("Location")
public record Location(
        String id,
        @NonNull UnLocode unLocode,
        @NonNull String name,
        @NonNull String country) implements Node {

    @Override @Id @NonNull
    public String getId() { return id; }
}
```

```python
@strawberry.interface(description="A global object identifier, unique across the whole graph. ...")
class Node:
    id: strawberry.ID = strawberry.field(description="The globally unique, opaque identifier of this object.")


@strawberry.type(description="A port or terminal, identified by its UN/LOCODE.")
class Location(Node):
    id: strawberry.ID = strawberry.field(description="The globally unique identifier of this location.")
    un_locode: UnLocode = strawberry.field(description="The UN/LOCODE, for example `NLRTM`.")
    name: str = strawberry.field(description="The human-readable name, for example `Rotterdam`.")
    country: str = strawberry.field(description="The ISO 3166-1 alpha-2 country code, for example `NL`.")
```

SmallRye maps an interface's fields from getter-named methods only, so the implementing records carry an explicit `getId()`. `@Id` is what turns a `String` into `ID`. Annotations carry everything else: `@Type` for objects, `@NonNull` for a bang, `List<@NonNull Leg>` for `[Leg!]`, a primitive `boolean` for `Boolean!` without any annotation, and `@Description` on types, fields, arguments and enum constants. Strawberry needs no annotation for a bang, because non-null is the default. camelCase is automatic: `un_locode` becomes `unLocode` and `final_arrival_date` becomes `finalArrivalDate`. An enum is a Python `Enum` with `strawberry.enum_value(..., description=...)` per member.

`DateTime` shows the largest difference between the stacks:

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Type("RouteSpecification")
public record RouteSpecification(
        @NonNull Location origin,
        @NonNull Location destination,
        @NonNull @Description("The date by which the cargo must arrive.") Instant arrivalDeadline) {}
```

```python
SCALAR_MAP = {
    # ... TrackingId and UnLocode, both NewType strings ...
    datetime: strawberry.scalar(
        name="DateTime",
        description="An RFC 3339 date-time in UTC, for example `2026-10-15T09:30:00Z`.",
        specified_by_url="https://www.rfc-editor.org/rfc/rfc3339",
        serialize=_serialize_datetime,   # UTC, whole seconds, suffix Z
        parse_value=_parse_datetime,     # rejects non-strings and datetimes with no offset
    ),
}

schema = strawberry.Schema(query=Query, config=StrawberryConfig(scalar_map=SCALAR_MAP))
```

SmallRye maps `java.time.Instant`, and the other `java.time` date types, to its built-in `DateTime` scalar, so the field needs no scalar code at all. Strawberry also has a default for `datetime`, but its output form differs from the pinned form, so the schema's `scalar_map` replaces it with a definition whose serializer writes the pinned form and whose parser refuses a datetime with no UTC offset. Fields stay annotated with the plain `datetime`. The same map turns the two `NewType` strings into `TrackingId` and `UnLocode`; the map is Strawberry's current form for custom scalars.

SmallRye's defaults differ from the contract in three places, and the canonical SDL stays as it is in each. First, SmallRye appends ` (ISO-8601)` to the description of every date-typed field, which the description comparison reports. Second, it describes the `DateTime` scalar as "Scalar for DateTime" and gives it no `@specifiedBy` URL. Third, `ContractSchemaDetails` rewrites types with graphql-java's `SchemaTransformer`, so each interface's type resolver has to return the rebuilt types, and a fragment such as `... on Location` matches them. `ContractSchemaDetails` applies all three through the CDI event SmallRye fires before it builds the schema (`quarkus.smallrye-graphql.events.enabled=true`): it sets the `Query` description, the two scalars' URLs and the `DateTime` description, strips the suffix, and re-points each interface's type resolver at the executing schema's own types. The node-dispatch assertion checks the third: a fragment on each implementer of `Node` selects its fields.

## On the wire

Start the stack and send the cargo query. Quarkus is on `8130` and Python on `8131`; both return the same bytes.

```bash
docker compose -f examples/03-sdl-type-system/compose.yaml up -d --build
curl -s localhost:8130/graphql -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId routeSpecification { arrivalDeadline } itinerary { finalArrivalDate legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } loadTime unloadTime } } delivery { transportStatus routingStatus misdirected lastKnownLocation { unLocode } currentVoyage { number } estimatedTimeOfArrival nextExpectedActivity { type location { unLocode } voyage { number } } } } }"}'
```

```json
{"data":{"cargo":{"trackingId":"ABC123","routeSpecification":{"arrivalDeadline":"2026-10-15T00:00:00Z"},"itinerary":{"finalArrivalDate":"2026-10-11T18:00:00Z","legs":[{"voyage":{"number":"V100S"},"loadLocation":{"unLocode":"USNYC"},"unloadLocation":{"unLocode":"DEHAM"},"loadTime":"2026-10-01T08:00:00Z","unloadTime":"2026-10-09T14:00:00Z"},{"voyage":{"number":"V200E"},"loadLocation":{"unLocode":"DEHAM"},"unloadLocation":{"unLocode":"NLRTM"},"loadTime":"2026-10-10T06:00:00Z","unloadTime":"2026-10-11T18:00:00Z"}]},"delivery":{"transportStatus":"ONBOARD_CARRIER","routingStatus":"ROUTED","misdirected":false,"lastKnownLocation":{"unLocode":"USNYC"},"currentVoyage":{"number":"V100S"},"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V100S"}}}}}}
```

The second cargo has no route yet, and absence is data. Replace the argument with `XYZ789` and drop `routeSpecification`, `legs` and `misdirected` to keep the line short:

```json
{"data":{"cargo":{"trackingId":"XYZ789","itinerary":null,"delivery":{"transportStatus":"NOT_RECEIVED","routingStatus":"NOT_ROUTED","lastKnownLocation":null,"currentVoyage":null,"estimatedTimeOfArrival":null,"nextExpectedActivity":{"type":"RECEIVE","location":{"unLocode":"SGSIN"},"voyage":null}}}}}
```

Node dispatch uses the query from earlier, with a fragment for each of two types:

```bash
curl -s localhost:8131/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ node(id: \"loc_NLRTM\") { __typename ... on Location { unLocode } ... on Cargo { trackingId } } }"}'
```

```json
{"data":{"node":{"__typename":"Location","unLocode":"NLRTM"}}}
```

An unknown id is `{"data":{"node":null}}`, and so are `location(unLocode: "ZZZZZ")` and `voyage(voyageNumber: "V999X")` under their own names. Selecting a field that is not on the interface is a validation failure, and the two stacks word it differently:

```bash
curl -s localhost:8130/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ node(id: \"loc_NLRTM\") { unLocode } }"}'
```

```json
{"errors":[{"message":"Validation error (FieldUndefined@[node/unLocode]) : Field 'unLocode' in type 'Node' is undefined","locations":[{"line":1,"column":27}],"extensions":{"classification":"ValidationError"}}]}
```

The specification says `data` should be absent when an error is raised before execution begins; Quarkus omits it and Python answers with `"data":null` and the message `Cannot query field 'unLocode' on type 'Node'. Did you mean to use an inline fragment on 'Location'?`. `verify.sh` asserts that the response has errors, that `data` is absent or null, and that the message names `unLocode`, and nothing more.

| Check | Expected |
|---|---|
| `ABC123` | the values above, `DateTime` as `...Z`, enums as names, `misdirected` `false` |
| `XYZ789` | `itinerary`, `lastKnownLocation`, `currentVoyage`, `estimatedTimeOfArrival` and `nextExpectedActivity.voyage` null, no `errors` |
| `location(unLocode: "DEHAM")` | `loc_DEHAM`, `Hamburg`, `DE` |
| `voyage(voyageNumber: "V100S")` | `voy_V100S`, `USNYC` to `DEHAM`, `2026-10-01T08:00:00Z` to `2026-10-09T14:00:00Z` |
| `node` on `loc_NLRTM`, `cargo_ABC123`, `voy_V200E` | `Location`/`NLRTM`, `Cargo`/`ABC123`, `Voyage`/`V200E` |
| `node` on `loc_NLRTM` with only `... on Cargo` selecting | exactly `{"__typename":"Location"}` |
| `node { unLocode }`, `cargo { origin }`, `trackingId { x }` | HTTP 200, `errors`, no `data` |
| `location(unLocode: 123)` | `errors`, no `data` |
| `TransportStatus` values | `CLAIMED, IN_PORT, NOT_RECEIVED, ONBOARD_CARRIER, UNKNOWN` (as a set) |
| `RoutingStatus`, `HandlingEventType` values | `MISROUTED, NOT_ROUTED, ROUTED` and `CLAIM, CUSTOMS, LOAD, RECEIVE, UNLOAD` (as sets) |
| `Node` | kind `INTERFACE`, possible types `Cargo`, `Location`, `Voyage` |
| `DateTime` | kind `SCALAR`, `specifiedByURL` `https://www.rfc-editor.org/rfc/rfc3339` |

`bash examples/03-sdl-type-system/verify.sh` runs all of it on both stacks, ends with the conformance check against `contracts/schema/`, and prints `PASS` only when both stacks hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>The type system is where the <em>contract and evolution style</em> axis introduced earlier becomes concrete. Every type, field and enum value in the canonical SDL is a public promise that many unknown clients read, so naming a scalar <code>UnLocode</code> instead of <code>String</code>, closing a set as an enum and giving every field a description all push the cost of ambiguity to the schema author, which is where it is cheapest to pay. The <em>client diversity and shape variance</em> axis is served by the object graph itself: three clients select three different slices of <code>Cargo</code> with no change to the server. <em>Aggregation across sources</em> shows in the shape of <code>Node</code>, one id space spanning three owners behind one field. The <em>operational and security cost</em> axis registers a small charge here, since an abstract type and a custom scalar mean each stack needs code that the contract does not generate, and a conformance gate to catch drift in it. The tracking view uses interfaces where members share a field, avoids unions until members share nothing, and pins <code>DateTime</code> to one wire format, because one canonical string per instant costs less than every client normalizing two.</p></div>

## Review

- The tracking schema is built from six type kinds (scalars, enums, objects, interfaces, unions and input types), each modified by the wrapper combinations `T!`, `[T]` and `[T!]!`.
- Each custom scalar (`TrackingId`, `UnLocode`, `DateTime`) carries three coercions: serialize for results, parse value for variables parsed from JSON, and parse literal for values written inline in a document, implemented on both SmallRye GraphQL and Strawberry.
- The `Node` interface and `Query.node` give `Cargo`, `Location` and `Voyage` a shared, globally unique id, so one field can resolve to any of the three runtime types and dispatch the matching inline fragment.
- An interface suits the tracking schema's abstract case because all three types share the `id` field; a union would hide that shared identity contract instead of expressing it.
- A client selection walks the schema's type graph field by field, and the response mirrors its shape; validation catches request errors, such as an undefined field or a missing subselection, before any resolver runs.
- Errors that surface while a resolver runs are execution errors, distinct from request errors, and they return partial data alongside the error list rather than none at all.

## Where this goes next

Every type kind the tracking view uses is now written on both stacks, a selection maps onto those types, and a bad document fails in one of a few known ways. Three SmallRye defaults needed `ContractSchemaDetails` to align them with the contract.

Following a `null` up the tree comes next: how a non-null field that cannot be filled empties its parent, and which fields the schema makes nullable. A later chapter builds the export-and-diff loop that keeps both stacks aligned with the canonical SDL. Another serves the input type from this chapter and exercises the `DateTime` input paths, and enum evolution and the breaking-change gate get revisited further on.

For the formal definitions, read the Type System section of the [GraphQL specification](https://spec.graphql.org/), including Scalars and `@specifiedBy`, and the Relay Global Object Identification specification linked above. Samer Buna's *GraphQL in Action* covers the same ground in "Introduction to GraphQL" and "Designing a GraphQL schema"; both are listed on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): "Designing a GraphQL schema" covers scalars, enums, interfaces and unions in the same depth as this chapter.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): schema design choices, including when to prefer an interface over a union.
- [GraphQL specification: Type System](https://spec.graphql.org/): the authoritative definitions of scalars, enums, objects, interfaces, unions and input types.
- [Relay: Global Object Identification](https://relay.dev/graphql/objectidentification.htm): the `Node` interface contract this chapter's `Query.node` implements.
