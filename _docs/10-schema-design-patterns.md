---
title: "Schema design patterns"
order: 10
part: "Schema Evolution & the Living Contract"
description: "How the tracking view's schema is designed from the screens that read it: naming conventions, Node and global ids with Query.nodes, objects instead of foreign keys, interfaces and unions, one input and one payload per mutation, and conventions checked mechanically on the canonical SDL and on both live schemas."
duration: "13 min read"
---

## Learning objectives

By the end of this chapter you can:

- Design schema fields from client demand (e.g. the tracking screen's three panels) rather than mirroring backing tables.
- Apply the naming, input, and payload conventions (`...Input`, `...Payload`, `...Connection`) that make a type's role readable from its name.
- Implement the `Node` interface and global ids so any client can refetch an object with `node(id:)` or batch-refetch with `nodes(ids:)`.
- Choose between an interface and a union based on whether a client would select shared fields or branch on `__typename`.
- Check schema conventions mechanically against the canonical SDL and each live `__schema`, instead of relying on review.

## Why this matters

Every type, name and nullability marker in the schema is a decision a client will depend on for years. A field can't be renamed once a dashboard selects it without breaking that dashboard, and an identity rule can't be added after caches have been keyed on something else. The patterns here keep those decisions cheap to live with.

The schema gains one root field, `Query.nodes(ids: [ID!]!): [Node]!`, which fetches several objects by global id in one request, and checks the naming, input, payload and description conventions on each live schema. It serves `finalArrivalDate` without a deprecation and without `finalArrivalTime`; the deprecation lifecycle corrects that.

## Design from demand

A schema that mirrors the tables behind it describes the producers. A schema designed from demand describes what the clients ask. The tracking view has one primary client, a screen with three panels, and the schema exists to answer it in one request.

| Panel | Selects | Owned by |
|---|---|---|
| Status header | `cargo(trackingId)` and `cargo.delivery`: `transportStatus`, `estimatedTimeOfArrival`, `nextExpectedActivity` | booking, routing and handling |
| Route | `cargo.itinerary.legs`: `loadLocation`, `voyage`, `unloadLocation` | routing, voyage, location |
| Timeline | `cargo.handlingHistory`: `type`, `location`, `completionTime` | handling, location |

The panels name the fields, and the fields name their owners. `Cargo.delivery` exists in no service: it is derived from the itinerary and the handling events, this layer's read-oriented aggregation. The client asks for `delivery { transportStatus }` and never learns that two services answered.

{% include excalidraw.html file="10-demand-oriented-schema" alt="The tracking screen has three panels: Status header, Route and Timeline. Each selects a field in the middle: cargo and cargo.delivery, cargo.itinerary.legs, and cargo.handlingHistory. The fields read five sources on the right: cargo(trackingId) reads booking, cargo.delivery reads routing and handling, cargo.itinerary.legs reads routing, voyage and location, and cargo.handlingHistory reads handling and location. A note says one screen, one query, five owners." caption="Figure 10.1: One screen, one query, five owners. The panels choose fields; each field is answered by one or more sources." %}

Demand also decides what stays out. Nothing on the screen reads a price, so the graph has no `Money` type, and no panel creates a booking, so booking writes stay a REST call with the service that owns them. A field earns a place when a client reads it. Adding one later is a safe change and removing one is not, so the cheap mistake is the field left out.

A list that a screen shows in full today and in part tomorrow is a connection from the start, because turning a list into a connection later changes the field's type. `Cargo.handlingHistory` is a Relay connection for that reason.

## Names are the interface

A name is the first thing a client reads and the last thing the server can change. The canonical SDL follows one set of conventions, and the checks described below enforce them.

| Element | Convention | Examples |
|---|---|---|
| Types, interfaces, unions, enums | PascalCase nouns | `Cargo`, `HandlingEvent`, `RoutingStatus` |
| Fields and arguments | camelCase | `trackingId`, `unLocode`, `completionTime` |
| Enum values | SCREAMING_SNAKE_CASE | `IN_PORT`, `NOT_ROUTED` |
| Input types | the operation or noun, then `Input` | `RegisterHandlingEventInput` |
| Mutation results | the mutation name, then `Payload` | `RegisterHandlingEventPayload` |
| Pagination types | the element, then `Connection` or `Edge` | `HandlingEventConnection` |
| Time-valued fields | end in `Time` or `Deadline` | `completionTime`, `arrivalDeadline` |

The suffixes make a type's role readable from its name: a client author who sees `...Payload` knows it is a mutation result, and a linter can enforce the shape. The time suffix is a promise about the type: a field ending in `Time` holds a `DateTime`, an instant in UTC, and nothing else. A field named `date` that holds an instant makes a client wonder whether it is a calendar day.

`Itinerary.finalArrivalDate` breaks that rule. It is a `DateTime`, so it should be `finalArrivalTime`. It was named before the convention was written down, and it can't be corrected by renaming, because every client that selects it would break. The correction is an addition followed by a deprecation. The checks leave the name alone, because they test the shape of names, not their meaning.

Prefer the domain's word to the implementation's: `Leg`, `Voyage` and `HandlingEvent` come from the shipping domain, not from the table or the service that holds them.

## Pattern: Global Object Identification

### The problem

A client that caches objects needs a key that identifies an object across the whole graph, not only within a type. A cargo and a location can share a key, and a cache keyed on the bare key mixes them up. Refetching one object, or a list from a push message, needs a root field that accepts any of them.

### The solution

**Global Object Identification gives every refetchable type a graph-unique `id` through a `Node` interface, and a root field that returns any `Node` by that id.**

The Relay specification defines it: an interface `Node { id: ID! }`, a root field that fetches any `Node` by id, and the rule that the id is unique across every type.

### How Quarkus and Python model it

```graphql
interface Node {
  id: ID!
}

type Query {
  node(id: ID!): Node
  nodes(ids: [ID!]!): [Node]!
}
```

Four types implement `Node`: `Cargo`, `Location`, `Voyage` and `HandlingEvent`. Their ids carry a type prefix, `cargo_ABC123`, `loc_USNYC`, `voy_V200E` and `evt_1`, and the resolver dispatches on it. The prefix keeps two types with overlapping keys distinct.

The ids are readable, and the contract says to treat them as opaque: a client stores an id, compares it, sends it back and never takes it apart. If clients parse `cargo_ABC123`, the server can no longer change how a cargo is keyed. Many APIs enforce opacity by encoding the id, commonly as base64 of `Type:key`. The encoding isn't what protects the contract; clients that are told the id is opaque are protected. Readable ids are easier to debug, so the tracking view keeps them.

The pattern gives one testable rule, the refetch rule: for any object `x` returned by the graph, `node(id: x.id)` returns an object with the same `id` and the same type. Check it with a field that proves the contents, because `__typename` alone passes for an object with the right type and the wrong contents. Get the id the way a client would, through a field, and send it back:

| Implementer | Obtained through | Id | Fragment field after refetch |
|---|---|---|---|
| `Cargo` | `cargo(trackingId: "ABC123") { id }` | `cargo_ABC123` | `trackingId` is `ABC123` |
| `Location` | the first leg's `loadLocation { id }` | `loc_USNYC` | `unLocode` is `USNYC` |
| `Voyage` | the second leg's `voyage { id }` | `voy_V200E` | `number` is `V200E` |
| `HandlingEvent` | `node(id: "evt_1") { id }` | `evt_1` | `type` is `RECEIVE` |

{% include excalidraw.html file="10-node-identity" alt="Three client paths on the left, cargo id, leg load location id and handling event id, deliver an id to a client cache keyed by id. An arrow labelled refetch by id leads from the cache to node and nodes on the right. Below it, prefix dispatch lists the prefixes cargo_, loc_, voy_ and evt_, over the owning source. An arrow labelled the same object returns from the source to the cache." caption="Figure 10.2: Ids reach a client cache along any path. node and nodes turn any of them back into the same object through the prefix dispatch." %}

### nodes(ids:)

A client with a list of ids can fetch them one `node` call at a time or in one request. `nodes` returns a list of the same length in the same order. An id that resolves to nothing yields `null` at its position, so the client doesn't match results back to ids. An empty list returns an empty list. The return type is `[Node]!`: the list is never null and each element may be. The argument is `[ID!]!`, so a `null` id is a request error.

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

Both stacks route every id through the helper `node` already uses, `resolveNode` on Quarkus and `resolve_node` on Python, so `node` and `nodes` can't disagree about what an id means. `Uni.join().all(...)` and `asyncio.gather` preserve input order while running the lookups concurrently. On Quarkus the `ids` argument is declared `List<@NonNull String>`, and the schema observer `ContractSchemaDetails` gives it the contract's type `[ID!]!`.

Each id is one source call, and nothing deduplicates them. `nodes(ids: ["cargo_ABC123", "loc_NLRTM", "nope", "voy_V200E", "cargo_ABC123"])` makes four calls: `booking.getCargo` for `ABC123` twice, `location.getLocation` for `NLRTM` and `voyage.getVoyage` for `V200E`. The unknown `nope` has no recognized prefix and makes none, and neither does a bare prefix such as `cargo` or an empty key such as `cargo_`. This is the N+1 shape, and DataLoader batching collapses it: four calls become three.

`nodes` is the bounded exception to the connection rule. The caller chose the ids and the answer has the same length. A server can still cap the length of `ids`, which is a job for depth and cost limits.

## Objects, not foreign keys

A relational schema points from one row to another with a key. A graph points with the object. `Leg.voyage` returns a `Voyage`, not a `voyageNumber`, and `Leg.loadLocation` returns a `Location`, not a code. A client that wants the vessel's name selects it in the same query, and the schema never needs a second field for the key of every relation.

The cost moves to the resolvers. Each of those fields is a source call, and a list of legs makes a call per leg. DataLoader batching exists to fix that cost behind the schema, because the reverse, a schema full of keys that clients join by hand, can't be fixed without a breaking change.

There is one documented exception. `HandlingEvent` has both `trackingId` and `cargo`. The tracking id is a scalar copy of the key, kept so a client can say which cargo an event belongs to when the booking service is down. Then `cargo` is null ("Null when the cargo service is unavailable", says its description) and `trackingId` survives. It is a denormalization chosen for resilience, and the only one in the schema.

## Interfaces versus unions

| | Interface | Union |
|---|---|---|
| Members | share fields | share nothing a client would select |
| Client | selects the shared fields without knowing the concrete type | branches on `__typename` |
| Fits | `Node`: a caching client needs only `id` | a search result that is a cargo or a location; a mutation result that is a success or a failure |

`__type(name: "Node") { possibleTypes { name } }` lists `Cargo`, `HandlingEvent`, `Location` and `Voyage` on both stacks.

Adding a member to a union or a new implementer to an interface is a change clients can break on: a client that switches on `__typename` with no default branch fails on the new type. The breaking-change gate files a new union member, and an existing type that starts to implement the interface, under dangerous changes. It passes a brand-new implementing type as safe, and a reviewer should still treat that one as dangerous. This schema keeps payload fields over a union of mutation results because a payload keeps the common path flat: the success fields are there and `userErrors` is an empty list.

## Inputs and payloads

Every mutation takes exactly one argument, named `input`, whose type is a non-null input object, and returns a non-null payload object holding what changed and a list of `userErrors`.

```graphql
type Mutation {
  registerHandlingEvent(input: RegisterHandlingEventInput!): RegisterHandlingEventPayload!
}
```

One input object means the mutation can gain fields without changing its signature: a new optional field on the input, or a new field on the payload, is a safe addition. One payload per mutation means the result isn't shared with another mutation that needs to differ. The non-null payload means a client never asks whether the mutation ran. It always gets an object, and a refusal is data inside it: `RECEIVE` with a voyage returns `VOYAGE_NOT_ALLOWED` at `["input","voyageNumber"]` and no `errors` key. A new required input field is a breaking change for every client and a new optional one is not, so `voyageNumber` and `idempotencyKey` were optional from the start.

The September 2025 edition of the specification adds "OneOf Input Objects", an input type annotated `@oneOf` in which exactly one field must be set. It models a choice, such as finding a cargo by tracking id or by id. This schema doesn't use it. Strawberry 0.335.0 accepts `strawberry.input(one_of=True)`, prints `@oneOf` in the SDL and rejects a request that sets two fields with "OneOf Input Object ... must specify exactly one key". SmallRye GraphQL 2.18.5 ships `io.smallrye.graphql.api.OneOf`. Consider either when a mutation or lookup takes alternative keys.

## Enums, scalars and nullability as design

**Enums for closed sets.** `HandlingEventType`, `TransportStatus` and `RoutingStatus` are enums because the set is closed and the domain logic switches on it. A client can render each value and the server rejects anything else during coercion. Adding a value is a dangerous change, because a client with an exhaustive switch meets a value it has never seen. An open set, such as a list of carriers, is a type with a field, not an enum.

**Custom scalars for values with rules.** `TrackingId`, `UnLocode` and `DateTime` are string-backed scalars that validate on the way in and out. `UnLocode` and `DateTime` point at their definitions with `@specifiedBy`. The SDL diff covers types, fields and arguments, and a separate check covers the URLs.

**Nullability as a statement about failure.** Non-null is a promise the server must keep, and a broken promise propagates upward. `Leg.loadLocation` is non-null because a leg without a location isn't a leg. `Cargo.itinerary` is nullable because routing may not have assigned one. `Leg.voyage` is nullable because the voyage service can fail on its own, and a failed field shouldn't erase the leg. A field fed by a service that can fail on its own is nullable, and a field that is part of what the type means is not.

## Checking design mechanically

Conventions that rely on review decay. Two checks hold them.

The first is the canonical SDL. `npm --prefix contracts run lint` runs GraphQL ESLint with the recommended schema rules plus two more: every type, field, argument and enum value needs a description, and every entity (a type that implements `Node`) needs an `id`, while value objects, payloads and connections are exempt. It runs before any stack starts, so a convention break in the contract fails first.

The second is each live schema. The SDL can be perfect and a stack can still serve something else: a name derived from a Java class, a generated description in place of the contract's. One `__schema` request per stack goes to a checker, written with the Python standard library, that requires:

- type names in PascalCase, and field, argument and input field names in camelCase;
- enum values matching `^[A-Z][A-Z0-9_]*$`;
- every input object's name ending in `Input`;
- every `Mutation` field taking exactly one argument, `input`, of a non-null input object type, and returning a non-null object whose name ends in `Payload`;
- a non-empty description on every type, field, argument, input field and enum value;
- `id: ID!` on every implementer of `Node`.

The checker skips introspection types, the built-in scalars and the framework types that `LGTM_SDL_FRAMEWORK_TYPES` names, and prints each offender on its own line. The conformance check compares the live schema to the contract; this one asks whether the schema, whatever it is, follows the rules.

> **Decision**
>
> Keep later changes additive. Design fields from what a screen reads and keep writes with their owners. Name by convention, give every mutation one `input` and one payload, point at objects instead of keys, make fields fed by a separately failing service nullable, give refetchable types opaque global ids, and make a list that can grow a connection in its first release. Every `node`, `nodes` id and object field is a source call until DataLoader batching collapses them. Enforce the conventions with a linter on the SDL and a check on each live schema.

> **🤖 Explore with your agent**
>
> "In `examples/10-schema-design/`, add a `Shipment` type that implements `Node` with an `id`, a `trackingId` and a `bookedTime` (a `DateTime`), prefix its ids `shp_`, and dispatch it in `resolveNode` on Quarkus and `resolve_node` on Python so `node` and `nodes` return it. Follow the repository's naming, description and `Node` conventions in the canonical SDL under `contracts/schema/`, and keep `nodes` order and `null`-for-unknown behavior."
>
> Check: run `npm --prefix contracts run lint` and `bash examples/10-schema-design/verify.sh`, then refetch a `shp_` id and confirm `node(id: x.id)` returns the same `id` and type.

## Build, run, observe

The commands run against the Quarkus stack on port 8200; use 8201 for Python. Port 8200 is also HashiCorp Vault's default, so change the published port in `compose.yaml` if it is taken.

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

The third response lists the four implementers. `bash examples/10-schema-design/verify.sh` lints the contract, runs the refetch rule on each implementer, the `nodes` checks, the live-schema convention checker and the contract conformance diff on both stacks, and prints `PASS` only when both hold. Experiments:

- **Fetch with a mix of ids.** `nodes` with `cargo`, `evt` and `cargo_` returns three `null`s and makes no source call; `nodes(ids: [])` returns `[]` and makes none.
- **Order and fragments.** `nodes` with ids `voy_V200E`, `evt_1`, `loc_NLRTM`, `cargo_ABC123` returns `number` `V200E`, `type` `RECEIVE`, `unLocode` `NLRTM`, `trackingId` `ABC123`, in that order.
- **Read the source-call log.** The five-id request above logs exactly `booking.getCargo:ABC123`, `location.getLocation:NLRTM`, `voyage.getVoyage:V200E`, `booking.getCargo:ABC123`.
- **Register `RECEIVE` at `USNYC` on `V100S`.** No `errors`, `handlingEvent` null, one `userErrors` entry, `VOYAGE_NOT_ALLOWED` at `["input","voyageNumber"]`.

## For deeper coverage

- [GraphQL specification: Interfaces, Unions, Input Objects, OneOf Input Objects](https://spec.graphql.org/).
- [Relay: Global Object Identification specification](https://relay.dev/graphql/objectidentification.htm): the `Node` interface and global-id pattern.
- The [GraphQL ESLint](https://the-guild.dev/graphql/eslint/docs) documentation lists the rules the contract uses.
- Samer Buna, *GraphQL in Action* (Manning, 2021): "Designing a GraphQL schema."
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): naming, enums, interfaces, and pagination guidance.
- *Cloud Native Design Patterns*, "Composition": designing a schema from client demand rather than from the data each service owns.
- The [Bibliography](../../bibliography/) page lists the books.
