---
title: "The GraphQL decision framework"
order: 2
part: "Why GraphQL & the Decision Lens"
description: "Seven axes for deciding whether an interaction belongs in GraphQL, REST or gRPC, applied to four shipping interactions and closed by the Decision callout."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Apply the seven decision axes (client diversity, aggregation, read/write balance, caching, contract evolution, operational cost, team ownership) to any interaction.
- Score the four shipping interactions (the customer tracking view, booking a cargo, internal routing and partner bulk feeds) against those axes.
- Justify why the tracking view lands on GraphQL while booking stays REST and internal routing stays gRPC.
- Write a `Decision` callout in the shared vocabulary.

## Why this matters

The shipping domain has four interactions that look alike from a distance and differ sharply up close. A customer's mobile app shows where a cargo is and what happens next. A booking screen creates a cargo and returns its tracking id. The booking service asks the routing service for candidate itineraries, hundreds of times a minute. A partner terminal operator uploads a nightly batch of forty thousand handling events. All four move cargo data over a network, and a team that picks one paradigm for all of them serves at least two badly.

Seven axes turn "GraphQL or not" into a set of questions you can answer per interaction. The result for this system: the tracking view is GraphQL, booking writes are REST, internal routing is gRPC, and partner bulk feeds are none of the three. Each technique chapter carries a **Decision** callout that applies these axes by name.

## Client diversity and shape variance

Who calls, and how much do their needs differ? With one client, written by the team that writes the server, a fixed response shape can be tuned to that client and GraphQL's flexibility goes unused. With many clients (a public tracking page, two mobile apps, an operations console, a customer integration), each with its own required fields and release schedule, a fixed shape is wrong for most of them.

Take the fields of a cargo. The mobile list view needs `trackingId` and `delivery.transportStatus`. The detail screen adds the origin and destination names and the next expected activity. The operations console needs the itinerary, every leg's voyage and the handling history. In REST the server either returns the union of everything and wastes bandwidth for the smallest client, or maintains several representations. In GraphQL the three clients differ only in their selections:

```graphql
query MobileListRow {
  cargo(trackingId: "ABC123") { trackingId delivery { transportStatus } }
}

query DetailScreen {
  cargo(trackingId: "ABC123") {
    trackingId
    origin { name }
    destination { name }
    delivery { transportStatus nextExpectedActivity { type location { name } } }
  }
}

query OperationsConsole {
  cargo(trackingId: "ABC123") {
    trackingId
    delivery { transportStatus misdirected }
    itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } }
    handlingHistory(first: 20) { edges { node { type location { unLocode } completionTime } } }
  }
}
```

Score this axis high when clients are many, heterogeneous and released independently, and low when there is one consumer or every consumer wants the same fields. A low score removes the main benefit of the paradigm, and the other axes have to carry the case.

## Aggregation across sources

Does one request need data owned by several services? The tracking question needs the cargo record, the itinerary from routing and the delivery state derived from handling events. Without an aggregation layer, either every client calls three services and joins the results, or the booking service grows into a backend-for-frontend that couples its release cycle to every screen.

A GraphQL layer is a structured aggregation point. Resolvers hide which service owns which field: `Cargo.itinerary` is filled by routing, `Cargo.handlingHistory` by the handling store, and `Leg.voyage` by whichever service owns voyage schedules. Boundaries can move without a client change.

The cost is dependency. The tracking view depends on every service it fronts, and a slow dependency slows every query that touches it. The schema encodes this in nullability: `Leg.voyage` is nullable because the voyage service can be down while the rest of the leg is still useful. Score high when one screen regularly needs fields from more than one owner. For a single-source interaction, a GraphQL layer adds a hop and a translation without removing a join.

## Read and write balance

GraphQL's selection model pays off on reads, where the response shape varies. A write usually carries known inputs and returns a known acknowledgment, and what matters is validation, idempotency, authorization and transactional behavior. Those live in the service that owns the data, and routing writes through an aggregation layer creates a second place to implement them inconsistently.

The tracking view is read-dominant and writes stay with their owners. `Query` has six entry points and `Subscription` has one, `cargoHandled`, for watching a cargo live. `Mutation` has one, `registerHandlingEvent`, because a client reporting a handling event often wants the updated `Cargo` and its recomputed `Delivery` back in the same round trip. Its input carries an `idempotencyKey` so retries are safe, and its payload returns validation failures as `UserError` values in `userErrors`. Booking is different: it creates the aggregate, allocates the tracking id, may trigger routing and charges a price. It is a REST `POST` on the booking service, with idempotency and `201 Created` semantics.

Score high for read-dominant interactions. Command-style interactions favor REST or gRPC, with a GraphQL mutation justified only when the client needs a shaped read of the result.

## Caching needs

Tracking data has two faces. Reference data such as a `Location` or a voyage schedule changes rarely and is read constantly. A cargo's delivery state changes with each handling event and tolerates seconds of staleness, not hours.

REST caches by URL and method, so `GET /locations/NLRTM` is cacheable by any browser, proxy or CDN with no help from the application. GraphQL queries over `POST /graphql` are not, because intermediaries key on the URL and do not read bodies. Teams recover caching three ways:

| Technique | Where it caches |
|---|---|
| Persisted queries over `GET` | HTTP caches and CDNs, keyed on the URL |
| Response and field caches | Inside or in front of the server |
| Caching under the dataloaders | Backend results |

Each works, and each is work REST did not require. This axis penalizes GraphQL when scalability depends on shared, public, long-lived cache hits: a public catalog of port codes served to millions of anonymous readers belongs behind a CDN as plain REST. It penalizes GraphQL much less for personalized, short-lived or authenticated responses, which were never going to be shared. A customer's own cargo status, behind a login, is in that group.

## Contract and evolution style

REST contracts are usually OpenAPI documents describing paths, with changes managed by versioned URLs or media types. gRPC contracts are `.proto` files with numbered fields and strict compatibility rules checked by tools such as `buf breaking`. A GraphQL contract is a single schema. Because clients name the fields they use, adding output fields never invalidates an existing query, and removal is an observable process through `@deprecated` and field-usage data. Additive changes are not entirely free: a new enum value or union member can surprise a client that handles the known set exhaustively.

A long-lived graph can change for years without a version number, provided the schema is treated as a public contract and a breaking-change check runs on every edit. Here that check is a graphql-inspector comparison against the canonical SDL in CI. The discipline is the price. Changing a field's type, relaxing an output field from non-null to nullable or making an argument required are breaking changes a casual commit can introduce, and with many unknown clients, finding out who uses a field means collecting operation-level usage data.

Score high when clients are many and unknown, so one evolving contract beats parallel versions. Score low when strictness and generated, compile-time-checked clients matter more than flexibility, which is gRPC's strength between services owned by one organization.

## Operational and security cost

A REST endpoint or a gRPC method does a roughly known amount of work per call. A GraphQL endpoint accepts arbitrary documents, so the caller decides the work. That brings obligations:

- Depth limits and cost analysis protect backends from expensive selections.
- Pagination caps keep list fields from returning unbounded data.
- Introspection and error messages need review so they do not leak schema details to anonymous callers.
- Authorization works per field, not per route, because one query can touch cargo owned by one customer and reference data owned by nobody.
- Telemetry is operation-aware, since every request shares a URL.
- Dataloaders are in place before traffic arrives, or N+1 patterns turn a modest graph into hundreds of backend calls per request.

None of this is exotic, and it still belongs on the scale. A team with no capacity for it should keep the interface small or choose another paradigm for the first release. For internal, trusted, few callers, most of this cost buys little, and gRPC or REST is cheaper to run.

## Team ownership and federation

One team can own the tracking view, its schema and all its resolvers, which is the simplest arrangement that works. When several teams each want to contribute types, with cargo, routing and handling teams publishing their own parts of the graph, a single owner becomes a bottleneck. Federation lets each team own a subgraph and composes the subgraphs into one supergraph behind a router.

Federation adds a composition step, a router and cross-team schema governance, which a single team's first graph gets nothing from. Read the axis as a trigger: stay with one schema owner while one team can review every change, and consider federation when schema review becomes the queue everyone waits in.

The reverse concern applies to the services behind the graph. A backing service owned by another team that speaks REST or gRPC should not have to adopt GraphQL to participate. The tracking view's resolvers adapt those protocols, and the owning team keeps its own release cadence and contract.

## Applying the axes to the shipping domain

The table scores each interaction with a direction rather than a number, since a total would imply precision the axes don't have.

| Interaction | Client diversity | Aggregation | Read/write | Caching | Contract style | Op./security cost | Ownership | Result |
|---|---|---|---|---|---|---|---|---|
| Customer tracking view (web, mobile, console) | many, varied | three owners | read-heavy | personalized, short-lived | many unknown clients | acceptable, controls in place | one owner | GraphQL |
| Booking a cargo | few, known | one owner | write | none needed | strict, versioned | low | booking team | REST |
| Routing candidates for a booking | one internal caller | one owner | request-response | none | strict, generated | low | routing team | gRPC |
| Partner bulk handling feed | one partner | one owner | bulk write | none | file or batch schema | high if opened to arbitrary queries | handling team | not GraphQL |

The **customer tracking view** scores toward GraphQL on nearly every axis. Clients are varied and independently released, one screen needs data from three owners, traffic is read-dominated, and responses are personalized, so losing edge caching costs little.

**Booking a cargo** is a command. One client family sends known inputs, expects a known result and needs strong validation and idempotency. There is nothing to aggregate and little shape to vary. REST gives it the verbs, status codes (`201 Created` with a `Location` header) and retry semantics the booking service already implements, and exposing it through the graph would duplicate those rules.

**Internal routing** is a service-to-service call with one trusted caller, a fixed message pair and a latency budget. gRPC's generated, typed stubs and binary encoding suit it, and nothing about the call benefits from a client choosing its own fields. Routing's results do reach clients through the tracking view, whose `Cargo.itinerary` resolver calls routing and reshapes the result. That is a different interaction with a different caller.

**Partner bulk feeds** are ruled out for a different reason. A terminal operator delivers forty thousand handling events in a night: fixed shape, high volume, write-only. The right tools are a batch endpoint, a file drop or a message stream with backpressure and retry. GraphQL mutations would push thousands of operations through an execution model built to serve selections, and would expose arbitrary documents to a partner who needs none of that flexibility. `registerHandlingEvent` serves a client reporting one event and wanting the recalculated cargo back. It is not a bulk ingestion interface.

{% include excalidraw.html file="02-decision-framework" alt="Diagram of a decision framework. On the left, seven stacked boxes list the axes: client diversity and shape variance, aggregation across sources, read and write balance, caching needs, contract and evolution style, operational and security cost, and team ownership and federation. Each has an arrow pointing right into one tall central box labelled run each interaction through the axes. From the central box, four arrows lead to outcome boxes on the right: the customer tracking view resolves to GraphQL and is highlighted in light amber, booking writes resolve to REST, internal routing resolves to gRPC, and partner bulk feeds are drawn dashed and resolve to not GraphQL." caption="Figure 2.1: Seven axes feed one decision per interaction. The same system lands on four different answers." %}

A "no" for one interaction does not forbid GraphQL elsewhere in the system. The question at each boundary is which paradigm fits what crosses it. The axes are also judgments, not measurements: two reasonable teams can weigh caching or ownership differently on a borderline case. What the framework guarantees is that the reasons are written in shared terms, so a disagreement is about a specific axis and not about preference.

## The tracking view topology

Clients reach the tracking view with GraphQL reads and the one `registerHandlingEvent` mutation. Bookings go to the booking service over REST. The tracking view's resolvers call the booking service's read endpoints for cargo data, the routing service over gRPC for itineraries and the handling event store for history. Partner feeds go around the graph and reach the handling store through their own channel.

{% include excalidraw.html file="02-tracking-view-topology" alt="Topology of the tracking view. On the left, a box for web and mobile clients sends GraphQL queries to the central tracking view box, highlighted in light amber, which is labelled as the GraphQL endpoint at /graphql. The same client box also has a separate arrow along the top for writes, labelled POST /cargos, going directly to the booking service on the right, which speaks REST. The tracking view box lists the reads it serves: cargo, itinerary, delivery and handling history. From it, three arrows lead to backing sources on the right: one labelled REST to the booking service, one labelled gRPC to the routing service, and one labelled read, register to the handling event store, which holds the handling history. A dashed box at the lower left for partner bulk feeds has a dashed arrow to the handling event store labelled bulk feed, not GraphQL, bypassing the tracking view." caption="Figure 2.2: The tracking view fronts three sources for reads; writes and bulk feeds take their own paths." %}

The tracking view owns no data, so it can be scaled, redeployed and replaced without a migration. Because it depends on the services behind it, its schema marks the fields at ownership boundaries nullable, such as `Cargo.itinerary` and `Leg.voyage`, and its resolvers tolerate a missing source. The schema is its public contract, stored as canonical SDL and enforced against both language stacks. No backing service has to change to participate: booking keeps its REST contract and routing keeps its `.proto`.

## The Decision callout

A **Decision** callout takes a chapter's topic, runs it through the seven axes by name, and states where the topic lands and why. It is an argument in shared vocabulary, not a summary. When a chapter on persisted queries says they "answer two axes of the decision framework at once", naming *caching needs* and *operational and security cost*, the sentence relies on these definitions. The callout below applies it to the tracking view.

> **🤖 Explore with your agent**
>
> "Read the canonical SDL in contracts/schema/shipping/ and pick one field of Cargo that a second client family would not need, such as handlingHistory. Score the tracking view's use of it on the seven decision axes from the table above, using the table's wording, and say which axis would first push that field out of the graph into REST."
>
> Check: the reply names all seven axes, cites the field's type in the SDL, and reaches a result that follows from the scores in the table.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>The customer tracking view is a GraphQL interaction. <em>Client diversity</em> is high and clients release independently, so a selection-shaped response replaces per-client representations. <em>Aggregation</em> is high: one screen needs the cargo, routing and handling owners, so a single graph with nullable cross-service fields replaces client-side joins. <em>Read and write balance</em> is read-dominant, with <code>registerHandlingEvent</code> as the only mutation, so booking stays REST and internal routing stays gRPC. <em>Caching</em> is a cost and not a barrier, because responses are personalized and short-lived, and persisted queries plus server-side caching cover shared reference data. The <em>contract</em> is one schema that evolves by addition and deprecation under a breaking-change gate. The <em>operational and security</em> price (cost limits, field-level authorization, dataloaders, operation-aware telemetry) is accepted, and one team owns the schema until review volume justifies federation. Partner bulk feeds fail the same test and stay outside the graph.</p></div>

## For deeper coverage

- [GraphQL specification](https://spec.graphql.org/): type system and execution.
- [GraphQL-over-HTTP specification](https://http-spec.graphql.org/draft/): the transport.
- Mastering API Architecture, Gough, J., Bryant, D. & Auburn, M. (O'Reilly, 2022): style selection and tradeoff analysis across REST, RPC and event-driven APIs.
- Samer Buna, *GraphQL in Action* (Manning, 2021): schema and resolver design for the GraphQL side of the decision. William Lyon's *Full Stack GraphQL Applications* extends the ideas to clients and authorization. Both are on the [Bibliography](../../bibliography/) page.
- Cloud Native Design Patterns: [API Management](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/08-api-management/) chapter, for governing which style an interaction should use at scale.
- Cloud Native Design Patterns: [Communications](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/02-communications/) chapter, for the same REST/gRPC/GraphQL/async decision made from a platform-wide view.
