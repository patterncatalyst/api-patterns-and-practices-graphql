---
title: "The GraphQL decision framework"
order: 2
part: "Why GraphQL & the Decision Lens"
description: "Seven axes for deciding whether an interaction belongs in GraphQL, REST or gRPC, applied to the shipping domain and closed by the Decision callout every later chapter reuses."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Apply the seven decision axes (client diversity, aggregation, read/write balance, caching, contract evolution, operational cost, team ownership) to any interaction.
- Score the four shipping interactions (the customer tracking view, booking a cargo, internal routing and partner bulk feeds) against those axes.
- Justify why the tracking view lands on GraphQL while booking stays REST and internal routing stays gRPC.
- Write a `Decision` callout in the shared vocabulary every later chapter reuses.

## Why this matters

The shipping domain has four interactions that look alike from a distance and differ sharply up close. A customer's mobile app shows where a cargo is and what happens next. A booking screen creates a cargo and returns its tracking id. The booking service asks the routing service for candidate itineraries, hundreds of times a minute. A partner terminal operator uploads a nightly batch of forty thousand handling events. All four move cargo data over a network, and a team that picks one paradigm for all of them will serve at least two of them badly.

The tracking view, a GraphQL layer that aggregates cargo, route legs and handling events for clients, has already surfaced where GraphQL gains and loses ground. This chapter converts that list into seven axes you can apply to any interaction, then applies them to the four above. The result is a map of the system: the tracking view is GraphQL, booking writes are REST, internal routing is gRPC, and partner bulk feeds are none of the three. Every later chapter ends with a **Decision** callout that applies these axes by name.

## Client diversity and shape variance

The first axis asks who calls and how much their needs differ. If an API has one client, written by the team that writes the server, a fixed response shape can be tuned to that client and the flexibility GraphQL offers goes unused. If it has many clients, such as a public tracking page, two mobile apps, an operations console and a customer's integration, each with its own set of required fields and its own release schedule, then a fixed shape is always wrong for most of them.

Shape variance is the sharper form of the question. Consider the fields of a cargo. The mobile list view needs `trackingId` and `delivery.transportStatus`. The detail screen adds the origin and destination names and the next expected activity. The operations console needs the itinerary, every leg's voyage and the full handling history. In REST, the server either returns the union of everything and wastes bandwidth for the smallest client, or ships several representations and endpoints and maintains all of them. In GraphQL the three clients differ only in their selections:

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

The score on this axis is high when clients are many, heterogeneous and released independently. It is low when there is one consumer, or when every consumer wants the same fields. A high score favors GraphQL. A low score means the main benefit of the paradigm is absent, and the remaining axes have to carry the case on their own.

## Aggregation across sources

The second axis asks whether a single client request needs data owned by several services. The tracking question needs the cargo record, the itinerary from routing and the delivery state derived from handling events. Without an aggregation layer, either the client calls three services and joins the results, which spreads the join logic across every client, or the booking service grows into a backend-for-frontend that proxies everything, which couples its release cycle to every screen.

A GraphQL layer is a structured aggregation point. Resolvers hide which service owns which field, so the graph a client sees can differ from the service boundaries behind it, and boundaries can move without a client change. The canonical schema shows this: `Cargo.itinerary` is filled by the routing service, `Cargo.handlingHistory` by the handling store, and `Leg.voyage` by whichever service owns voyage schedules. The client writes one selection and never learns the topology.

The axis has a cost side. Aggregation means the tracking view depends on every service it fronts, and a slow dependency slows every query that touches it. The schema encodes this in its nullability: `Leg.voyage` is nullable because the voyage service can be unavailable while the rest of the leg is still useful. Score this axis high when one screen regularly needs fields from more than one owner, and low when each interaction touches one service. For a single-source interaction, a GraphQL layer adds a hop and a translation without removing a join.

## Read and write balance

The third axis compares the volume and importance of reads against writes. GraphQL's selection model pays off on reads, where the shape of the response varies. A write usually carries a known set of inputs and returns a known acknowledgment, so there is little shaping to do, and what matters instead is validation, idempotency, authorization and transactional behavior. Those concerns live in the service that owns the data, and routing writes through an aggregation layer puts a second place where they could be implemented inconsistently.

The practical rule for this book is that the tracking view is read-dominant and writes remain with owners. The canonical schema reflects it. `Query` has six entry points and `Subscription` has one, `cargoHandled`, for clients watching a cargo live through a subscription. `Mutation` has one, `registerHandlingEvent`, because a client reporting a handling event often wants the updated `Cargo` and its recomputed `Delivery` back in the same round trip, which is a shaping benefit. Its input carries an `idempotencyKey` so retries are safe, and its payload returns validation failures as `UserError` values in `userErrors`. Booking a cargo is different. It creates the aggregate, allocates the tracking id, may trigger routing and charges a price. It is a REST `POST` on the booking service, with the idempotency and `201 Created` semantics that the REST sibling site describes.

Score the axis by asking what fraction of the interaction's value is in reading shaped data. High read dominance favors GraphQL. Write-dominant, command-style interactions favor REST or gRPC, with a GraphQL mutation justified only when the client needs a shaped read of the result.

## Caching needs

The fourth axis asks how much the interaction depends on caching at the network edge. Tracking data has two faces. Reference data such as a `Location` or a voyage schedule changes rarely and is read constantly. A cargo's delivery state changes with each handling event and tolerates seconds, not hours, of staleness.

REST caches by URL and method, so a `GET /locations/NLRTM` is cacheable by any browser, proxy or CDN with no cooperation from the application. GraphQL queries over `POST /graphql` are not, because intermediaries key on the URL and do not read bodies. Teams recover caching by sending persisted queries over `GET`, by caching complete responses in an HTTP cache in front of the server and individual fields inside it, and by caching backend results under the dataloaders that batch backend calls. Each of these works, and each is work that REST did not require.

This axis therefore penalizes GraphQL when the interaction's scalability depends on shared, public, long-lived cache hits. A public catalog of port codes served to millions of anonymous readers belongs behind a CDN as plain REST. It penalizes GraphQL much less when responses are personalized, short-lived or authenticated, because those responses were never going to be shared in a cache anyway. A customer's own cargo status, behind a login, is in the second group.

## Contract and evolution style

The fifth axis compares how the contract is expressed and how it changes. REST contracts are usually OpenAPI documents describing paths, with changes managed by versioned URLs or media types. gRPC contracts are `.proto` files with numbered fields, where compatibility rules are strict and checked by tools such as `buf breaking`. GraphQL contracts are a single schema, and the evolution rule is distinctive: because clients name the fields they use, adding output fields never invalidates an existing query, and removal is an observable process through `@deprecated` and field-usage data. Additive changes are not entirely free: a new enum value or union member can still surprise a client that handles the known set exhaustively.

The advantage is that a long-lived graph can change for years without a version number, provided the team treats the schema as a public contract and runs a breaking-change check on every edit. This book enforces that with a graphql-inspector comparison against the canonical SDL in CI. The disadvantage is that GraphQL demands that discipline. Changing a field's type, relaxing an output field from non-null to nullable or making an argument required are breaking changes that a casual commit can introduce, and with many unknown clients, finding out who uses a field means collecting operation-level usage data.

Score this axis high when clients are many and unknown, so that a single evolving contract beats parallel versions. Score it low when contract strictness and generated, compile-time-checked clients matter more than flexibility, which is gRPC's strength between services owned by one organization.

## Operational and security cost

The sixth axis asks what the team must run and defend to offer the interface safely. A REST endpoint is largely bounded by its design: each route does a roughly known amount of work. A gRPC method is similarly bounded by its request and response messages. A GraphQL endpoint accepts arbitrary documents, so the amount of work per request is decided by the caller.

That brings obligations a REST service mostly avoids. Depth limits and cost analysis protect the backends from expensive selections. Pagination caps keep list fields from returning unbounded data. Introspection and error messages need review so they do not leak schema details to anonymous callers. Authorization has to work per field, not per route, because one query can touch cargo owned by one customer and reference data owned by nobody. Telemetry has to be operation-aware, since every request shares a URL. And dataloaders must be in place before traffic arrives, or N+1 patterns turn a graph of modest size into hundreds of backend calls per request.

None of this is exotic, and the later chapters give each its own example. It is cost nonetheless, and it belongs on the scale. A team with no capacity for it should keep the interface small, or choose another paradigm for the first release. For an interaction whose callers are internal, trusted and few, most of this cost buys little protection, and gRPC or REST is cheaper to operate.

## Team ownership and federation

The seventh axis is organizational. Who owns the schema, who owns each resolver's backing service, and how do changes get coordinated? One team can own the tracking view, its schema and all its resolvers, which is the arrangement in this book and the simplest one that works. Once several teams each want to contribute types, such as cargo, routing and handling teams publishing their own parts of the graph, a single owner becomes a bottleneck. Federation addresses this by letting each team own a subgraph and composing those subgraphs into one supergraph behind a router.

Federation is a scaling answer for organizations, not a starting point for a single team's first graph. Adopting it early adds a composition step, a router and cross-team schema governance that a single team gets nothing from. The axis is therefore best read as a trigger: stay with a single schema owner while one team can review every change, and consider federation when schema review becomes the queue everyone waits in.

The reverse concern applies to the services behind the graph. A backing service that is owned by another team and speaks REST or gRPC should not be forced to adopt GraphQL to participate. The tracking view's resolvers adapt those protocols, and the owning team keeps its own release cadence and its own contract.

## Applying the axes to the shipping domain

Taken together, the seven axes give a profile for each interaction. The table scores each with a plain direction rather than a number, since a total would imply a precision the axes do not have.

| Interaction | Client diversity | Aggregation | Read/write | Caching | Contract style | Op./security cost | Ownership | Result |
|---|---|---|---|---|---|---|---|---|
| Customer tracking view (web, mobile, console) | many, varied | three owners | read-heavy | personalized, short-lived | many unknown clients | acceptable, controls in place | one owner | GraphQL |
| Booking a cargo | few, known | one owner | write | none needed | strict, versioned | low | booking team | REST |
| Routing candidates for a booking | one internal caller | one owner | request-response | none | strict, generated | low | routing team | gRPC |
| Partner bulk handling feed | one partner | one owner | bulk write | none | file or batch schema | high if opened to arbitrary queries | handling team | not GraphQL |

The **customer tracking view** scores toward GraphQL on nearly every axis. Clients are varied and released independently, a single screen needs data from three owners, the traffic is read-dominated, and the responses are personalized, so the loss of edge caching costs little. Later chapters meet the operational obligations. This is the interaction the book builds.

**Booking a cargo** is a command. One client family, the booking screens and partner APIs, sends known inputs, expects a known result and needs strong validation and idempotency. There is nothing to aggregate and little shape to vary. REST gives it the verbs, status codes (`201 Created` with a `Location` header) and retry semantics the booking service already implements, and exposing it through the graph would duplicate those rules in a second place.

**Internal routing** is a service-to-service call with one trusted caller, a fixed message pair and a latency budget. The booking service asks the routing service for candidate itineraries and waits for the answer. gRPC's generated, typed stubs and binary encoding suit it, and nothing about the call benefits from a client choosing its own fields. The routing service's results do reach clients, through the tracking view, whose `Cargo.itinerary` resolver calls routing and reshapes the result. That is a different interaction with a different caller.

**Partner bulk feeds** fail the test in a different way. A terminal operator delivers forty thousand handling events in a night. The shape is known and fixed, the volume is high, the transfer is write-only, and the right tools are a batch endpoint, a file drop or a message stream with backpressure and retry. Wrapping that in GraphQL mutations would force thousands of operations through a per-request execution model designed to serve selections, and would expose a security surface (arbitrary documents) to a partner who needs none of its flexibility. The single `registerHandlingEvent` mutation exists for a client reporting one event and wanting the recalculated cargo back; it is not a bulk ingestion interface.

{% include excalidraw.html file="02-decision-framework" alt="Diagram of a decision framework. On the left, seven stacked boxes list the axes: client diversity and shape variance, aggregation across sources, read and write balance, caching needs, contract and evolution style, operational and security cost, and team ownership and federation. Each has an arrow pointing right into one tall central box labelled run each interaction through the axes. From the central box, four arrows lead to outcome boxes on the right: the customer tracking view resolves to GraphQL and is highlighted in light amber, booking writes resolve to REST, internal routing resolves to gRPC, and partner bulk feeds are drawn dashed and resolve to not GraphQL." caption="Figure 2.1: Seven axes feed one decision per interaction; in the shipping domain the same system lands on four different answers." %}

Two clarifications apply. First, a "no" for an interaction does not forbid GraphQL elsewhere in the same system. Every one of these paradigms has a place in the shipping system, and the question at each boundary is which one fits what crosses it. Second, the axes are judgments and not measurements. Two reasonable teams can weigh caching or ownership differently and reach different answers for borderline cases. What the framework guarantees is that the reasons are written down in shared terms, so a disagreement is about a specific axis rather than about preference.

## The tracking view topology

With the decisions made, the architecture follows from them. Clients reach the tracking view with GraphQL reads and the one `registerHandlingEvent` mutation. Bookings go to the booking service over REST. The tracking view's resolvers call the booking service's read endpoints for cargo data, the routing service over gRPC for itineraries and the handling event store for history. Partner feeds go around the graph and reach the handling store through their own channel.

{% include excalidraw.html file="02-tracking-view-topology" alt="Topology of the tracking view. On the left, a box for web and mobile clients sends GraphQL queries to the central tracking view box, highlighted in light amber, which is labelled as the GraphQL endpoint at /graphql. The same client box also has a separate arrow along the top for writes, labelled POST /cargos, going directly to the booking service on the right, which speaks REST. The tracking view box lists the reads it serves: cargo, itinerary, delivery and handling history. From it, three arrows lead to backing sources on the right: one labelled REST to the booking service, one labelled gRPC to the routing service, and one labelled read, register to the handling event store, which holds the handling history. A dashed box at the lower left for partner bulk feeds has a dashed arrow to the handling event store labelled bulk feed, not GraphQL, bypassing the tracking view." caption="Figure 2.2: The tracking view fronts three sources for reads; writes and bulk feeds take their own paths." %}

The tracking view owns no data, so it can be scaled, redeployed and replaced without a migration. It depends on the services behind it, which is why its schema marks the fields at ownership boundaries nullable, such as `Cargo.itinerary` and `Leg.voyage`, and why its resolvers must tolerate a missing source. Its schema is its public contract, stored in the repository as canonical SDL and enforced against both language stacks. And no service behind it is required to change to participate: the booking service keeps its REST contract and the routing service keeps its `.proto`.

## The Decision callout

From this chapter on, every chapter ends with a callout labeled **Decision**. It does one thing: it takes the chapter's topic and runs it through the seven axes above, then states in a few sentences where the topic lands and why. It is an argument in the shared vocabulary, not a summary. Reading every Decision callout in sequence reconstructs the book's reasoning without rereading the prose that produced it.

The callout names axes explicitly. When a later chapter on persisted queries says that persisted documents "answer two axes of the decision framework at once", naming the *caching needs* and *operational and security cost* axes, the sentence relies on this chapter having defined both. Without that shared vocabulary each chapter would have to restate its criteria, and the book would drift into a collection of independent recommendations.

## A worked decision: the tracking view

Apply the axes to the interaction the later chapters build.

*Client diversity and shape variance* is high. A public tracking page, two mobile apps and an operations console need different slices of `Cargo`, and their releases are not coordinated with the server's. The selection model removes the need for a representation per client.

*Aggregation across sources* is high. One screen needs the cargo record, the itinerary and the handling history, which three services own. Resolvers hide those boundaries, and the schema's nullable cross-service fields let a failure in one source degrade a response instead of failing it.

*Read and write balance* is read-dominant. Almost every request is a query, and the one subscription, `cargoHandled`, is a read delivered as a stream. The one mutation, `registerHandlingEvent`, is in the schema because the caller wants the recomputed cargo back. Bookings and route assignment stay with their owners.

*Caching needs* is moderate and mostly favorable. Responses depend on the signed-in customer and change with each handling event, so shared edge caching was never the main tool. Reference data such as locations benefits from persisted queries and server-side caching, both of which later chapters build.

*Contract and evolution style* favors GraphQL. Clients are numerous and unknown to the server team, so a single schema that grows by addition and retires fields through deprecation and usage data suits them. The breaking-change gate in CI is the control that makes the approach safe.

*Operational and security cost* is accepted. The team takes on depth and cost limits, field-level authorization, batching and operation-level telemetry, and the book gives each its own chapter and example.

*Team ownership and federation* points to a single schema owner for now. One team owns the tracking view and its schema, and federation shows what changes when several teams must contribute.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>The customer tracking view is a GraphQL interaction. Client diversity is high and the clients release independently, so a selection-shaped response replaces per-client representations. One screen needs data from the cargo, routing and handling owners, so a single graph with nullable cross-service fields replaces client-side joins. The traffic is read-dominated, with <code>registerHandlingEvent</code> as the only mutation, so writes such as booking stay REST and internal routing stays gRPC. Caching is a cost rather than a barrier, because responses are personalized and short-lived, and persisted queries plus server-side caching cover the shared reference data. The contract is one schema that evolves by addition and deprecation under a breaking-change gate. The operational price (cost limits, field-level authorization, dataloaders, operation-aware telemetry) is accepted, and one team owns the schema until review volume justifies federation. Partner bulk feeds fail the same test and stay outside the graph.</p></div>

## Review

- Seven decision axes were defined: client diversity and shape variance, aggregation across sources, read and write balance, caching needs, contract and evolution style, operational and security cost, and team ownership and federation.
- Scored against those axes, the four shipping interactions landed on four different outcomes: the customer tracking view on GraphQL, booking a cargo on REST, internal routing on gRPC, and partner bulk feeds outside all three.
- The tracking view's high client diversity, three-owner aggregation and read-dominant traffic justify GraphQL; booking's command shape keeps it on REST, and internal routing's fixed, trusted request-response pair keeps it on gRPC.
- A `Decision` callout, built from the same seven axes, now closes this chapter and will close every chapter that follows.
- The worked decision on the tracking view showed each axis scored in turn, from high client diversity and aggregation through moderate caching to an accepted operational cost and a single schema owner.

## Where this goes next

This chapter turned the tracking view's strengths and weaknesses into seven axes, applied them to four shipping interactions with four different results, and defined the Decision callout that closes every later chapter. The tracking view now has a role, a boundary and a topology.

The SDL and type-system chapter starts building it, going through object types, interfaces such as `Node`, enums, input types, custom scalars like `TrackingId` and `UnLocode`, and how the canonical schema uses each. The nullability chapter explains null propagation, the mechanism behind the nullable fields at ownership boundaries. The contract-first workflow chapter sets up checking both stacks against one schema. Federation, caching and cost controls return in later chapters.

For the formal definitions behind the terms used here, the [GraphQL specification](https://spec.graphql.org/) covers the type system and execution, and the [GraphQL-over-HTTP specification](https://http-spec.graphql.org/draft/) covers the transport. Samer Buna's *GraphQL in Action* is a good companion for schema and resolver design, and William Lyon's *Full Stack GraphQL Applications* extends the same ideas to clients and authorization; both are on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- Mastering API Architecture, Gough, J., Bryant, D. & Auburn, M. (O'Reilly, 2022): style selection and tradeoff analysis across REST, RPC and event-driven APIs.
- Cloud Native Design Patterns: [API Management](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/08-api-management/) chapter, for governing which style an interaction should use at scale.
- Cloud Native Design Patterns: [Communications](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/02-communications/) chapter, for the same REST/gRPC/GraphQL/async decision made from a platform-wide view.
- Samer Buna, *GraphQL in Action* (Manning, 2021): schema and resolver design for the GraphQL side of the decision.
