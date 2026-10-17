---
title: "Domain Glossary — Shipping & Cargo"
layout: plan
render_with_liquid: false
---

# Domain Glossary — Shipping & Cargo

One canonical domain for the whole site, continuous with the sibling REST and gRPC
sites. Every chapter, example, SDL file and diagram uses these nouns. On the REST site
they are resources and on the gRPC site they are Protobuf messages; here they are
**GraphQL types and fields** in a read-oriented **tracking view**: an aggregation layer
that stitches cargo, route legs and handling events into one query-shaped graph. A
client asks for exactly the fields it needs, across all three, in one round trip.

## Canonical nouns

| Term | Meaning | GraphQL type |
|---|---|---|
| **Cargo** | The goods being shipped, looked up by tracking id. The root of the tracking view. | `Cargo` object type (implements `Node`) |
| **TrackingId** | The public identifier a customer uses to look up a cargo. | `TrackingId` scalar (string-backed), `Cargo.trackingId`, `HandlingEvent.trackingId` |
| **Location** | A port or terminal, identified by UN/LOCODE. | `Location` object type (implements `Node`): `unLocode`, `name`, `country` |
| **UN/LOCODE** | Five-character United Nations location code (e.g. `USNYC`, `NLRTM`, `SGSIN`). | `UnLocode` scalar (`@specifiedBy` UNECE) |
| **Voyage** | A scheduled carrier voyage, identified by its voyage number, made up of carrier movements. | `Voyage` object type (implements `Node`): `number`, `schedule` |
| **CarrierMovement** | One scheduled departure-to-arrival movement of a voyage between two locations. | `CarrierMovement` object type, `Voyage.schedule: [CarrierMovement!]!` |
| **Leg** | One hop of an itinerary: load on a voyage at one location, unload at another. | `Leg` object type: `voyage` (nullable), `loadLocation`, `unloadLocation`, `loadTime`, `unloadTime` |
| **Itinerary** | The ordered legs that move a cargo from origin to destination. | `Itinerary` object type (`legs`, `finalArrivalDate`), `Cargo.itinerary` |
| **RouteSpecification** | What the customer asked for: origin, destination and arrival deadline. | `RouteSpecification` object type, `Cargo.routeSpecification` |
| **HandlingEvent** | A recorded real-world action on a cargo (received, loaded, unloaded, cleared by customs, claimed). | `HandlingEvent` object type (implements `Node`), `Cargo.handlingHistory` |
| **Delivery** | The delivery state derived from a cargo's handling history: transport and routing status, last known location, current voyage, ETA, next expected activity. | `Delivery` object type, `Cargo.delivery: Delivery!` |
| **HandlingActivity** | An expected future handling of a cargo (type, location, optional voyage). | `HandlingActivity` object type, `Delivery.nextExpectedActivity` |
| **Money** | An amount to carry a cargo. Shared with the REST and gRPC sites; **not exposed** by the tracking view's SDL. | — |

## The tracking view in GraphQL

The graph is rooted at queries that return a `Cargo`. Everything else is reachable by
following fields, so the client controls the shape and the server resolves only what is
asked for.

| Domain idea | How it appears in the graph |
|---|---|
| Look up a cargo | `Query.cargo(trackingId: TrackingId!): Cargo` |
| List cargos | `Query.cargos(first, after, last, before, routingStatus): CargoConnection!` |
| Reference data | `Query.location(unLocode: UnLocode!): Location`, `Query.voyage(voyageNumber: String!): Voyage` |
| Refetch any entity | `Query.node(id: ID!): Node` (Relay Global Object Identification) |
| The planned journey | `Cargo.itinerary: Itinerary` with `legs: [Leg!]!`, each leg having `voyage`, `loadLocation`, `unloadLocation` |
| What was asked for | `Cargo.routeSpecification: RouteSpecification!` |
| What has happened | `Cargo.handlingHistory(first, after, last, before): HandlingEventConnection!` |
| Where it is now | `Cargo.delivery: Delivery!` (`transportStatus`, `routingStatus`, `misdirected`, `lastKnownLocation`, `currentVoyage`, `estimatedTimeOfArrival`, `nextExpectedActivity`) |
| Event kind | `HandlingEventType` enum: `RECEIVE`, `LOAD`, `UNLOAD`, `CUSTOMS`, `CLAIM` |
| Transport state | `TransportStatus` enum: `NOT_RECEIVED`, `IN_PORT`, `ONBOARD_CARRIER`, `CLAIMED`, `UNKNOWN` |
| Routing state | `RoutingStatus` enum: `NOT_ROUTED`, `ROUTED`, `MISROUTED` |
| Changing state | `Mutation.registerHandlingEvent(input: RegisterHandlingEventInput!): RegisterHandlingEventPayload!` (the only mutation) |
| Domain failures | `RegisterHandlingEventPayload.userErrors: [UserError!]!`; `UserError { code: UserErrorCode!, message, field: [String!] }` |
| Live updates (Ch21) | `Subscription.cargoHandled(trackingId: TrackingId!): HandlingEvent!` |

Enums model closed sets (event type, transport status, routing status). Nullability
follows the domain: a cargo that has not been routed has a nullable `itinerary`, a leg's
`voyage` is nullable because it is resolved from another service, and
`Delivery.estimatedTimeOfArrival` is nullable when no estimate exists, while
`routeSpecification` and `delivery` are always present (Ch4).

## Identifiers & formats

- **TrackingId** — opaque string, e.g. `ABC123`; compare for equality only.
- **Voyage number** — `Voyage.number`, e.g. `V100S`; the same value is the `voyageNumber` argument/input field.
- **Location** — UN/LOCODE (e.g. `USNYC`, `NLRTM`, `SGSIN`); `Location.country` is ISO 3166-1 alpha-2.
- **Money** — `{ currency: "USD", amount: "1250.00" }` on the REST and gRPC sites (decimal **string** to avoid float drift); no `Money` type in this SDL.
- **Timestamps** — RFC 3339 UTC, exposed as the `DateTime` scalar (`@specifiedBy` RFC 3339).
- **Global object id** — Relay-style opaque `ID` on every `Node` implementer (`Cargo`, `Location`, `Voyage`, `HandlingEvent`), resolvable through `Query.node`.

## GraphQL-specific vocabulary

These terms exist only in the GraphQL part of the story; the domain nouns above are shared
across all three sites.

| Term | Meaning |
|---|---|
| **SDL** | Schema Definition Language: the textual form of the schema. The canonical SDL lives in `contracts/schema/`. |
| **Node** | The Relay `Node` interface (`id: ID!`) implemented by every refetchable entity; `Query.node(id:)` fetches any of them. |
| **Connection** | The paginated-list shape (`edges`, `pageInfo`, `totalCount`) from the Relay cursor-connections spec. `HandlingEventConnection` and `CargoConnection` are the two in this domain. |
| **Edge** | One element of a connection: a `node` plus its `cursor` (`CargoEdge`, `HandlingEventEdge`). `node` is nullable, so an item that fails to resolve nulls only its own edge (Ch4). |
| **PageInfo** | `hasNextPage`, `hasPreviousPage`, `startCursor`, `endCursor` for a connection page. |
| **Cursor** | An opaque position token passed back as `after`/`before`; clients never parse it. |
| **DataLoader** | A per-request batching and caching helper that collapses many field fetches (the N+1 pattern) into one backend call. |
| **Persisted query** | A query registered ahead of time and invoked by hash, so the server can reject unknown operations and clients send less. APQ is the automatic variant. |
| **Input type** | An argument-only object type, used for mutation inputs such as `RegisterHandlingEventInput`. |
| **Payload type** | The mutation result wrapper (`RegisterHandlingEventPayload`), carrying the changed objects and a `userErrors` list. Retries are made safe by `RegisterHandlingEventInput.idempotencyKey`. |
| **UserError** | A domain validation failure returned as data (`code: UserErrorCode!`, `message`, `field` path), distinct from the top-level `errors` array (Ch9). |
| **Resolver** | The function that produces the value of one field. |
| **Subscription** | A long-lived operation that pushes results to the client; covered once, in Ch21. |

## Contract vocabulary

These names are fixed across `contracts/schema/`. A type is defined **once** in the
canonical SDL and both stacks export a schema that must match it; the graphql-inspector
gate flags any breaking change.

| File | Defines |
|---|---|
| `scalars.graphql` | `DateTime`, `TrackingId`, `UnLocode` scalars; `Node` interface; `PageInfo` |
| `location.graphql` | `Location` |
| `voyage.graphql` | `Voyage`, `CarrierMovement` |
| `cargo.graphql` | `Cargo`, `RouteSpecification`, `Itinerary`, `Leg`, `Delivery`, `HandlingActivity`, `TransportStatus`, `RoutingStatus`, `CargoConnection`, `CargoEdge` |
| `handling.graphql` | `HandlingEventType`, `HandlingEvent`, `HandlingEventConnection`, `HandlingEventEdge`, `RegisterHandlingEventInput`, `RegisterHandlingEventPayload`, `UserError`, `UserErrorCode` |
| `schema.graphql` | `schema { query mutation subscription }`, `Query`, `Mutation`, `Subscription` |
