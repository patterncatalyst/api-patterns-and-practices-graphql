---
title: "Schema design patterns"
order: 10
part: "Schema Evolution & the Living Contract"
description: "How the tracking view's schema is designed from the screens that read it: naming conventions, Node and global ids with Query.nodes, objects instead of foreign keys, interfaces and unions, one input and one payload per mutation, and conventions checked mechanically on the canonical SDL and on both live schemas."
duration: "16 min read"
---

## Learning objectives

By the end of this chapter you can:

- Design schema fields from client demand (e.g. the tracking screen's three panels) rather than mirroring backing tables.
- Apply the naming, input, and payload conventions (`...Input`, `...Payload`, `...Connection`) that make a type's role readable from its name.
- Implement the `Node` interface and global ids so any client can refetch an object with `node(id:)` or batch-refetch with `nodes(ids:)`.
- Choose between an interface and a union based on whether a client would select shared fields or branch on `__typename`.
- Check schema conventions mechanically against the canonical SDL and each live `__schema`, instead of relying on review.

## Why this matters

Nine chapters used the schema. This one asks why it looks the way it does. Every type, name and nullability marker the examples served so far came from the canonical SDL in `contracts/schema/`, and each of them is a decision a client will depend on for years. A field cannot be renamed once a dashboard selects it without breaking that dashboard, and an identity rule cannot be added after caches have been keyed on something else. The patterns here are the ones that keep those decisions cheap to live with.

The code is in `examples/10-schema-design/`. It starts from the example that added the `registerHandlingEvent` mutation and adds one root field, `Query.nodes(ids: [ID!]!): [Node]!`, which fetches several objects by global id in one request. Its `verify.sh` also reads each live schema once and checks the naming, input, payload and description conventions mechanically, and it runs the GraphQL ESLint rules on the canonical SDL. The slice predates the field's deprecation lifecycle: it serves `finalArrivalDate` without a deprecation and without `finalArrivalTime`.

## Design from demand

A schema that mirrors the tables behind it describes the producers. A schema designed from demand describes what the clients ask. The tracking view has one primary client, a screen with three panels, and the schema exists to answer it in one request.

| Panel | Selects | Owned by |
|---|---|---|
| Status header | `cargo(trackingId)` and `cargo.delivery`: `transportStatus`, `estimatedTimeOfArrival`, `nextExpectedActivity` | booking, routing and handling |
| Route | `cargo.itinerary.legs`: `loadLocation`, `voyage`, `unloadLocation` | routing, voyage, location |
| Timeline | `cargo.handlingHistory`: `type`, `location`, `completionTime` | handling, location |

The panels name the fields, and the fields name their owners. `Cargo.delivery` does not exist in any service: it is derived from the itinerary and the handling events, which is this layer's read-oriented aggregation. The client asks for `delivery { transportStatus }` and never learns that two services answered.

{% include excalidraw.html file="10-demand-oriented-schema" alt="The tracking screen has three panels: Status header, Route and Timeline. Each panel has an arrow labelled selects to a field box in the middle: cargo and cargo.delivery, cargo.itinerary.legs, and cargo.handlingHistory. The Status header also selects cargo(trackingId). Arrows labelled reads lead from the field boxes to five sources on the right: booking, routing, voyage, location and handling. cargo(trackingId) reads booking, cargo.delivery reads routing, cargo.itinerary.legs reads routing, voyage and location, and cargo.handlingHistory reads handling and location. A dashed arrow joins cargo.delivery to handling. A note below says one screen, one query, five owners." caption="Figure 10.1: One screen, one query, five owners. The panels choose fields; each field is answered by one or more sources." %}

Demand also decides what stays out. Nothing on the screen reads a price, so the graph has no `Money` type, and no panel creates a booking, so booking writes stay a REST call, keeping writes with the service that owns them. A field earns a place when a client reads it. Adding one later is a safe change, and removing one is not, so the cheap mistake is the field that was left out.

The reverse also holds. A list that a screen shows in full today and a client shows in part tomorrow is a connection from the start, because turning a list into a connection later changes the field's type, which is why `handlingHistory` becomes a Relay connection from the start.

## Names are the interface

A name is the first thing a client reads and the last thing the server can change. The canonical SDL follows one set of conventions, and the checks described later enforce them.

| Element | Convention | Examples |
|---|---|---|
| Types, interfaces, unions, enums | PascalCase nouns | `Cargo`, `HandlingEvent`, `RoutingStatus` |
| Fields and arguments | camelCase | `trackingId`, `unLocode`, `completionTime` |
| Enum values | SCREAMING_SNAKE_CASE | `IN_PORT`, `NOT_ROUTED` |
| Input types | the operation or noun, then `Input` | `RegisterHandlingEventInput` |
| Mutation results | the mutation name, then `Payload` | `RegisterHandlingEventPayload` |
| Pagination types | the element, then `Connection` or `Edge` | `HandlingEventConnection` |
| Time-valued fields | end in `Time` or `Deadline` | `completionTime`, `arrivalDeadline` |

Two of these carry more weight than they appear to. The suffixes make a type's role readable from its name, so a client author who sees `...Payload` knows it is a mutation result, and a linter can enforce the shape. The time suffix is a promise about the type: a field ending in `Time` holds a `DateTime`, an instant in UTC, and nothing else. A field named `date` that holds an instant makes a client wonder whether it is a calendar day.

The canonical SDL departs from that last rule in one place. `Itinerary.finalArrivalDate` is a `DateTime`, so by the table it should be `finalArrivalTime`. It was named before the convention was written down, and it shows what an inconsistency costs: it cannot be corrected by renaming, because every client that selects it would break. The correction is an addition followed by a deprecation, following the deprecation lifecycle in that order. Until then the chapter's checks leave this name alone, because they test the shape of names, not their meaning.

A name that reads well in the schema can still be wrong for the field. Prefer the domain's word to the implementation's: `Leg`, `Voyage` and `HandlingEvent` come from the shipping domain, not from the table or the service that holds them.

## Identity: `Node` and global ids

A client that caches objects needs a key that identifies an object across the whole graph, not only within a type. The Relay Global Object Identification specification gives the pattern: an interface `Node { id: ID! }`, a root field that fetches any `Node` by id, and the rule that the id is unique across every type.

```graphql
interface Node {
  id: ID!
}

type Query {
  node(id: ID!): Node
  nodes(ids: [ID!]!): [Node]!
}
```

In the tracking view four types implement `Node`: `Cargo`, `Location`, `Voyage` and `HandlingEvent`. Their ids carry a type prefix, `cargo_ABC123`, `loc_USNYC`, `voy_V200E` and `evt_1`, and the resolver dispatches on it. The prefix is how two types with overlapping keys, a cargo and a location, stay distinct.

The ids are readable, and the contract says to treat them as opaque. A client stores an id, compares it, sends it back and never takes it apart. That rule matters more than the encoding. If clients parse `cargo_ABC123`, the server can no longer change how a cargo is keyed. Many APIs enforce opacity by encoding the id, commonly as base64 of `Type:key`, so that nobody is tempted to read it. That works, but the encoding is not what protects the contract. Clients that are told the id is opaque and never see a reason to doubt it are protected. Readable ids are easier to debug, and the example keeps them for that reason.

The pattern gives one testable rule, the refetch rule: for any object `x` returned by the graph, `node(id: x.id)` returns an object with the same `id` and the same type. `verify.sh` applies it to each implementer. It obtains an id the way a client would, through a field, and sends it back:

| Implementer | Obtained through | Id | Fragment field after refetch |
|---|---|---|---|
| `Cargo` | `cargo(trackingId: "ABC123") { id }` | `cargo_ABC123` | `trackingId` is `ABC123` |
| `Location` | the first leg's `loadLocation { id }` | `loc_USNYC` | `unLocode` is `USNYC` |
| `Voyage` | the second leg's `voyage { id }` | `voy_V200E` | `number` is `V200E` |
| `HandlingEvent` | `node(id: "evt_1") { id }` | `evt_1` | `type` is `RECEIVE` |

Checking `__typename` alone would pass for an object with the right type and the wrong contents, so each refetch also selects a field through an inline fragment and compares it with the seed.

{% include excalidraw.html file="10-node-identity" alt="Each of three client paths on the left, cargo id, leg load location id and handling event id, delivers an id to a client cache in the middle keyed by id. An amber arrow labelled refetch by id leads from the cache to a box for node and nodes on the right. Below it, a box for prefix dispatch lists the prefixes cargo_, loc_, voy_ and evt_, and a box for the owning source sits under that. An amber arrow labelled the same object returns from the source to the cache." caption="Figure 10.2: Ids reach a client cache along any path. node and nodes turn any of them back into the same object through the prefix dispatch." %}

### `nodes(ids:)`

A client that has a list of ids, from a cache or from a push message, can fetch them one `node` call at a time or in one request. `nodes` takes a list and returns a list of the same length in the same order. An id that resolves to nothing yields `null` at its position, so the response lines up with the request and the client does not match results back to ids. An empty list returns an empty list.

The return type is `[Node]!`: the list is never null, and each element may be, which is how an unknown id is represented. The argument is `[ID!]!`, so a `null` id is a request error.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Query
@NonNull
@Description(
        "Fetch several objects by their global ids, in the order given. An unknown id yields null at its position.")
public Uni<List<Node>> nodes(
        @Name("ids") @NonNull @Description("The global ids of the objects to fetch.") List<@NonNull String> ids,
        Context context) {
    if (ids.isEmpty()) {
        return Uni.createFrom().item(List.of());
    }
    String request = context.getExecutionId();
    List<Uni<Node>> fetches = ids.stream().map(id -> resolveNode(request, id)).toList();
    // join().all() keeps the order of the list it is given; each id is its own source call.
    return Uni.join().all(fetches).andFailFast();
}
```

```python
@strawberry.field(
    description=(
        "Fetch several objects by their global ids, in the order given. "
        "An unknown id yields null at its position."
    )
)
async def nodes(
    self,
    info: Info[TrackingContext],
    ids: Annotated[
        list[strawberry.ID],
        strawberry.argument(description="The global ids of the objects to fetch."),
    ],
) -> list[Node | None]:
    # gather keeps the order of its arguments; each id is its own source call.
    return list(await asyncio.gather(*(resolve_node(info.context, id_) for id_ in ids)))
```

Both stacks route every id through the helper that `node` already used, `resolveNode` on Quarkus and `resolve_node` on Python, so there is one dispatch and `node` and `nodes` cannot disagree about what an id means. `Uni.join().all(...)` and `asyncio.gather` both preserve the order of their inputs while running the lookups concurrently.

One detail on Quarkus. The `ids` argument is declared `List<@NonNull String>`, and `ContractSchemaDetails`, the schema observer the examples already use, gives it the contract's type `[ID!]!`. The live schema reports `[ID!]!`, and `verify.sh` asserts the full signature of the field.

Each id is one source call, and nothing deduplicates them. `nodes(ids: ["cargo_ABC123", "loc_NLRTM", "nope", "voy_V200E", "cargo_ABC123"])` makes four calls: `booking.getCargo` for `ABC123` twice, `location.getLocation` for `NLRTM` and `voyage.getVoyage` for `V200E`. The unknown `nope` has no recognised prefix and makes none, and neither do a bare prefix such as `cargo` or an empty key such as `cargo_`. This is the N+1 shape that resolver fan-out measures, and DataLoader batching collapses it, so the four calls become three.

## Objects, not foreign keys

A relational schema points from one row to another with a key. A graph points with the object. `Leg.voyage` returns a `Voyage`, not a `voyageNumber`, and `Leg.loadLocation` returns a `Location`, not a code. A client that wants the vessel's name selects it in the same query, and the schema never needs a second field for the key of every relation.

The cost moves to the resolvers. Each of those fields is a source call, and a list of legs makes a call per leg. The execution model's source-call log measures that cost, and it is the reason DataLoader batching exists. The design choice is to keep the schema in terms of the domain and fix the cost behind it, because the reverse, a schema full of keys that clients join by hand, cannot be fixed without a breaking change.

The exception is documented. `HandlingEvent` has both `trackingId` and `cargo`. The tracking id is a scalar copy of the key, kept so that a client can still say which cargo an event belongs to when the booking service is down. In that case `cargo` is null and `trackingId` survives, which is why the canonical description of `cargo` says "Null when the cargo service is unavailable". It is a denormalization chosen for resilience, and it is the only one in the schema.

## Interfaces versus unions

An interface says that several types share fields and a client can select those fields without knowing the concrete type. `Node` is the example: all a caching client needs from an object is its `id`, and it selects the rest through inline fragments. The test for an interface is that a client would write a query against the shared fields alone.

A union says that a result is exactly one of several types that share nothing a client would select in common. A search result that is a cargo or a location, or a mutation result that is a success or a failure, fits a union. The client branches on `__typename`.

Introspection shows the difference. `__type(name: "Node") { possibleTypes { name } }` lists the implementers, and `verify.sh` asserts it is `Cargo`, `HandlingEvent`, `Location` and `Voyage` on both stacks. `HandlingEvent` joined that list when it gained an `id` as part of its mutation payload. A sketch of a union for mutation results, compared against payload fields, explains why this schema keeps payload fields instead.

Adding a member to a union or a new implementer to an interface is a change clients can break on: a client that switches on `__typename` and has no default branch fails on the new type. It is not breaking in the schema's own sense. The gate files a new union member, and an existing type that starts to implement the interface, under dangerous changes; the breaking-change gate passes a brand-new implementing type as safe, and a reviewer should still treat that one as dangerous.

## Inputs and payloads

The input-and-payload pattern is a rule: every mutation takes exactly one argument, named `input`, whose type is a non-null input object, and returns a non-null payload object. The payload holds what changed and a list of `userErrors`.

```graphql
type Mutation {
  registerHandlingEvent(input: RegisterHandlingEventInput!): RegisterHandlingEventPayload!
}
```

One input object means the mutation can gain fields without changing its signature, which is the kind of additive evolution the deprecation lifecycle relies on: a new optional field on the input, or a new field on the payload, is a safe addition. One payload per mutation means the result is not shared with another mutation that needs to differ. The non-null payload means a client never has to ask whether the mutation ran. It always gets an object, and a refusal is data inside it. `verify.sh` sends a failing mutation, `RECEIVE` with a voyage, and asserts that `registerHandlingEvent` is not null, that `userErrors` has exactly one entry, `VOYAGE_NOT_ALLOWED` at `["input","voyageNumber"]`, and that `errors` is absent.

Optional fields on an input stay optional. A new required field is a breaking change for every existing client, while a new optional one is not, which is why `voyageNumber` and `idempotencyKey` were optional from the start.

The September 2025 edition of the GraphQL specification adds another tool, "OneOf Input Objects", an input type annotated `@oneOf` in which exactly one field must be set. It models a choice, such as finding a cargo by tracking id or by id. This schema does not use it, so the chapter does not serve it. The README records what was checked: Strawberry 0.335.0 accepts `strawberry.input(one_of=True)`, prints `@oneOf` in the SDL and rejects a request that sets two fields with "OneOf Input Object ... must specify exactly one key". SmallRye GraphQL 2.18.5 ships `io.smallrye.graphql.api.OneOf`, which this example does not exercise. Both are tools to consider when a mutation or a lookup takes alternative keys.

## Enums, scalars and nullability as design

Three smaller choices carry most of a schema's day-to-day behaviour.

**Enums for closed sets.** `HandlingEventType`, `TransportStatus` and `RoutingStatus` are enums because the set is closed and the domain logic switches on it. A client can render each value and the server can reject anything else during coercion. The cost is that adding a value is a dangerous change, because a client with an exhaustive switch meets a value it has never seen. An open set, such as a list of carriers, should be a type with a field, not an enum.

**Custom scalars for values with rules.** `TrackingId`, `UnLocode` and `DateTime` are string-backed scalars. Each one validates on the way in and out, and `UnLocode` and `DateTime` point at their definitions with `@specifiedBy`. `verify.sh` checks that each is a real `SCALAR` and that the two URLs are exact; the SDL diff covers types, fields and arguments, and this check covers the URLs.

**Nullability as a statement about failure.** The nullability rule holds here too: non-null is a promise the server must keep, and a broken promise propagates upward. Design applies it field by field. `Leg.loadLocation` is non-null because a leg without a location is not a leg. `Cargo.itinerary` is nullable because routing may not have assigned one. `Leg.voyage` is nullable because the voyage service is a separate service that can fail, and a failed field should not erase the leg. A field fed by a service that can fail on its own is nullable, and a field that is part of what the type means is not.

## Lists that grow are connections

A list field that can grow without bound should be a connection from the first release. `Cargo.handlingHistory` returns a `HandlingEventConnection` with edges, a cursor on each edge and a `pageInfo`, built with opaque cursors that stay stable when events are added.

`nodes` is the bounded exception. Its list is as long as the client made it: the caller chose the ids and the answer has the same length. A list the caller sizes is not unbounded in the sense that matters. A server can still cap the length of `ids`, which is a job for depth and cost limits.

## Checking design mechanically

Conventions that rely on review decay. The example checks them in two places.

The first is the canonical SDL. `npm --prefix contracts run lint` runs GraphQL ESLint with the recommended schema rules, and the project adds two. Every type, field, argument and enum value needs a description. Every entity, meaning a type that implements `Node`, needs an `id`, while value objects, payloads and connections are exempt. `verify.sh` runs the linter first, so a convention break in the contract fails before any stack starts.

The second is each live schema. The SDL could be perfect and a stack could still serve something else: a name derived from a Java class, a description generated in place of the contract's. `verify.sh` sends one `__schema` request per stack and pipes the response to a small checker, written with the Python standard library, that asserts:

- type names are PascalCase, and field, argument and input field names are camelCase;
- enum values match `^[A-Z][A-Z0-9_]*$`;
- every input object's name ends in `Input`;
- every `Mutation` field takes exactly one argument, `input`, of a non-null input object type, and returns a non-null object whose name ends in `Payload`;
- every type, field, argument, input field and enum value has a non-empty description;
- every implementer of `Node` has `id: ID!`.

The checker skips introspection types, the built-in scalars and the framework types that `LGTM_SDL_FRAMEWORK_TYPES` names, and on a failure it prints each offender, one per line. The contract-first conformance check compares the live schema to the contract; this one asks whether the schema, whatever it is, follows the rules.

## On the wire

The commands below run against the Quarkus stack on port 8200. Use 8201 for Python. `verify.sh` runs the same checks against both.

```bash
gql() { curl -s localhost:8200/graphql -H 'Content-Type: application/json' -d "$1"; echo; }
gql '{"query":"{ nodes(ids: [\"cargo_ABC123\", \"loc_NLRTM\", \"nope\", \"voy_V200E\", \"cargo_ABC123\"]) { __typename } }"}'
gql '{"query":"{ nodes(ids: []) { id } }"}'
gql '{"query":"{ __type(name: \"Node\") { possibleTypes { name } } }"}'
```

```text
{"data":{"nodes":[{"__typename":"Cargo"},{"__typename":"Location"},null,{"__typename":"Voyage"},{"__typename":"Cargo"}]}}
{"data":{"nodes":[]}}
```

The third response lists the four implementers; `verify.sh` sorts them before comparing. Port 8200 is also HashiCorp Vault's default; if it is taken on your machine, change the published port in `compose.yaml`.

| Check | Expected |
|---|---|
| refetch of `cargo_ABC123`, `loc_USNYC`, `voy_V200E`, `evt_1` | the same `id` back; `__typename` `Cargo`, `Location`, `Voyage`, `HandlingEvent`; fragment fields `ABC123`, `USNYC`, `V200E`, `RECEIVE` |
| `nodes(ids: ["cargo_ABC123", "loc_NLRTM", "nope", "voy_V200E", "cargo_ABC123"])` | `__typename` `Cargo`, `Location`, `null`, `Voyage`, `Cargo`; no `errors` |
| source calls for that request | exactly `booking.getCargo:ABC123`, `location.getLocation:NLRTM`, `voyage.getVoyage:V200E`, `booking.getCargo:ABC123` |
| `nodes` with fragments, ids `voy_V200E`, `evt_1`, `loc_NLRTM`, `cargo_ABC123` | `number` `V200E`, `type` `RECEIVE`, `unLocode` `NLRTM`, `trackingId` `ABC123`, in that order |
| `nodes(ids: [])` | `[]`, no source call |
| `nodes(ids: ["cargo", "evt", "cargo_"])` | `null`, `null`, `null`; no source call |
| `__type(name: "Node") { possibleTypes { name } }`, sorted | `Cargo`, `HandlingEvent`, `Location`, `Voyage` |
| `Query.nodes` in introspection | type `[Node]!`, argument `ids` of type `[ID!]!`, the canonical description |
| one `__schema` request per stack, checked for names, input and payload shapes, descriptions and `Node` ids | no offenders |
| `npm --prefix contracts run lint` | exit 0 |
| `registerHandlingEvent` with `RECEIVE` at `USNYC` on `V100S` | no `errors`; `handlingEvent` null; one `userErrors` entry, `VOYAGE_NOT_ALLOWED` at `["input","voyageNumber"]` |
| `TrackingId`, `UnLocode`, `DateTime` scalars | `SCALAR`; `specifiedByURL` null, UNECE UN/LOCODE page, RFC 3339 |
| live schema vs `contracts/schema/` | no breaking change either way and no description change on what the stack serves (slice) |

`bash examples/10-schema-design/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Schema design is where the <em>contract and evolution style</em> axis of the decision framework is decided field by field. Names, suffixes, one <code>input</code> and one payload per mutation, and nullable fields across service boundaries are all choices that keep later changes additive. The <em>read and write balance</em> axis shows in design from demand: the graph holds what the screen reads, and writes stay small and with their owners. The <em>team ownership</em> axis shows in objects over foreign keys and in <code>Node</code> identity: each type points to its owner's data by object and by opaque id, so an owning team can change a key without a client change. The <em>operational and security cost</em> axis shows in what the design defers: every <code>node</code> and <code>nodes</code> id and every object field is a source call until DataLoader batching collapses them, and lists that grow become Relay connections. The tracking view uses global ids with an opaque contract, <code>nodes</code> for client caches, objects instead of keys with one documented denormalization, and conventions that a linter and a live-schema check enforce on every run.</p></div>

## Review

- Schema fields are designed from client demand, such as the tracking screen's three panels, rather than mirrored from backing tables.
- Naming, input, and payload conventions (`...Input`, `...Payload`, `...Connection`) make a type's role readable from its name alone.
- The `Node` interface and global ids let any client refetch an object with `node(id:)` or batch-refetch with `nodes(ids:)`, with a type prefix dispatching to the right source.
- An interface fits when a client selects shared fields; a union fits when a client branches on `__typename` across types that share nothing selectable.
- Schema conventions are checked mechanically, against the canonical SDL with GraphQL ESLint and against each live `__schema`, rather than relying on review.

## Where this goes next

This chapter named the conventions behind the schema and added `Query.nodes`, the one new field of the example. It also left two things open. `finalArrivalDate` is the one field outside the time-suffix rule, and the deprecation lifecycle corrects it the only safe way, by adding `finalArrivalTime`, deprecating the old name and letting the breaking-change gate show what each kind of change costs. The cost of resolving one id at a time is the other: the source-call row in "On the wire" shows `booking.getCargo` for `ABC123` twice, and DataLoader batching removes the duplicate.

The deprecation lifecycle continues from this example, and the Relay connection pattern builds the connection that `handlingHistory` has been waiting for, carrying `nodes` forward.

For the formal definitions, read "Interfaces", "Unions", "Input Objects" and "OneOf Input Objects" in the [GraphQL specification](https://spec.graphql.org/), and the [Global Object Identification](https://relay.dev/graphql/objectidentification.htm) specification from Relay. The [GraphQL ESLint](https://the-guild.dev/graphql/eslint/docs) documentation lists the rules the contract uses. Samer Buna's *GraphQL in Action* covers schema design in "Designing a GraphQL schema", and Artur Czemiel's *GraphQL Best Practices* covers naming, enums, interfaces and pagination in its guidance on schema design; both are listed on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- [GraphQL specification: Interfaces, Unions, Input Objects, OneOf Input Objects](https://spec.graphql.org/).
- [Relay: Global Object Identification specification](https://relay.dev/graphql/objectidentification.htm): the `Node` interface and global-id pattern this chapter implements.
- Samer Buna, *GraphQL in Action* (Manning, 2021): "Designing a GraphQL schema."
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): naming, enums, interfaces, and pagination guidance.
- *Cloud Native Design Patterns*, "Composition": designing a schema from client demand rather than from the data each service owns.
