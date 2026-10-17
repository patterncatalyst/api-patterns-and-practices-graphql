---
title: "From REST/RPC to GraphQL"
order: 1
part: "Why GraphQL & the Decision Lens"
description: "One client question answered by REST, gRPC and GraphQL, and the path a GraphQL request takes from a single HTTP POST through parse, validate and execute to one JSON response."
duration: "17 min read"
---

A customer opens a tracking page and types a tracking id. The page has one question to answer: where is my cargo, and what happens next? Answering it takes facts that live in three places. The cargo record holds the origin, the destination and the routing requirements. The routing service holds the itinerary, an ordered list of legs on named voyages. The handling history holds what has physically happened so far: received, loaded, unloaded, cleared by customs. A mobile client showing a glanceable status needs a handful of those fields. A web dashboard for the same cargo needs most of them.

Three API paradigms can serve that question, and each makes a different party responsible for assembling the answer. REST makes the client assemble it from several resources. gRPC makes the caller invoke typed methods on each service that owns a piece. GraphQL makes the server assemble it, shaped by a selection the client writes. This book is about the third option, applied to a narrow job, and this chapter sets out what that job is, how a request travels, and where the approach costs more than it returns.

The sibling REST and gRPC books cover the other two paradigms in depth, and this site assumes you have seen their vocabulary. It does not assume you have read them. Where a REST resource or a gRPC method appears, it is introduced in a sentence.

## One intent, three paradigms

Take the intent "show the state of cargo `ABC123` and its remaining route" and express it three ways.

A **REST** client treats the cargo as a resource and its related data as further resources. A typical session issues several requests:

```http
GET /cargos/ABC123
GET /cargos/ABC123/itinerary
GET /cargos/ABC123/handling-events?limit=2
GET /voyages/V100S
GET /voyages/V200E
```

The first returns the cargo representation the server's author decided on. If that representation carries the complete delivery state, the client downloads fields a mobile screen never shows (overfetching). If it carries only identifiers, the client must follow links to get the rest (underfetching), and each followed link is another round trip over a mobile network. The server can reduce both problems with embedding, sparse fieldsets or purpose-built "view" resources, but each of those is a design decision made on the server for a client the server author has to predict. A new screen means a new representation, a new parameter or a new endpoint.

A **gRPC** client treats the intent as a set of typed calls. The routing service exposes a method that returns an itinerary for a tracking id; a handling service exposes one that lists events. The contract is a `.proto` file, the calls are binary over HTTP/2, and the generated stubs make each call a typed function in the caller's language. This is excellent between services, where one team controls both sides, volume is high and latency matters. A browser, however, cannot speak native gRPC; it needs the gRPC-Web variant and, in most deployments, a translating proxy. The methods still return fixed response messages. The caller that wants three fields from each of three services makes three calls and receives three complete messages.

A **GraphQL** client treats the intent as a selection over a graph. The server publishes one schema that describes every type and the relationships between them: a `Cargo` has an `Itinerary`, an `Itinerary` has `Leg`s, a `Leg` has a `Voyage`, a `Cargo` has a `handlingHistory` of `HandlingEvent`s. The client sends one document naming exactly the fields it wants, to whatever depth the schema allows, and receives a JSON object with exactly that shape. The number of internal lookups needed to fill the shape is the server's concern. The number of round trips on the client's network is one.

{% include excalidraw.html file="01-three-paradigms" alt="Three-column comparison of REST, gRPC and GraphQL answering the same client intent, show the state and remaining route of cargo ABC123. Each column stacks a mental model, a call shape and a result. The REST column, labelled resources and verbs, starts from GET /cargos/ABC123 and makes several GETs, one per resource such as the cargo, its itinerary and its events, which returns fixed representations that over- or under-fetch. The gRPC column, labelled typed methods, shows typed calls between services such as GetItinerary and ListEvents, made through generated stubs over binary HTTP/2 with one call per owning service, which returns fixed response messages and needs a proxy in a browser. The GraphQL column is highlighted in a light amber wash and labelled one graph, one selection: the client traverses a typed graph, cargo with its delivery and itinerary, sends one POST to /graphql with the query and variables in the JSON body, and receives JSON shaped like the query in one round trip for the screen." caption="Figure 1.1 — Three paradigms, one intent: REST, gRPC and GraphQL answering the same tracking question." %}

None of the three is a general answer. They trade where the shaping work happens. REST and gRPC fix the response shape on the server and let the client combine responses. GraphQL lets the client fix the shape and makes the server do the combining. That is a good trade when many different clients want different slices of the same connected data, and a poor one when the interaction is a single well-known operation between two services.

## The tracking view: what this book builds

GraphQL is often presented as a replacement for a service tier, and that framing leads teams into trouble. This book uses it for a narrower and more defensible role: the **tracking view**, a read-oriented aggregation layer in front of services that already exist.

The services behind the tracking view own the data and the rules. The cargo service decides what a booking is. The routing service decides which itinerary satisfies a route specification. The handling service records what physically happened and derives the delivery state from it. Each of them may speak REST or gRPC, exactly as the sibling books describe, and none of them needs to know GraphQL exists. The tracking view owns no business data. It owns a schema, a set of resolvers that know which service to ask for which field, and the logic that stitches the answers into a graph.

This division keeps the strengths of each paradigm where they belong. Writes go through the owning services with the validation, idempotency and transactional rules those services already enforce. Internal calls keep the speed and typing of gRPC. Clients get one place to ask questions, one schema to learn and one round trip per screen. The schema is the contract between the tracking view and every client, and it lives in the repository as SDL under `contracts/schema/`. Both implementation stacks in this book, Quarkus with SmallRye GraphQL and Python with Strawberry, are checked against that same schema, so the contract does not depend on a language.

The read-only emphasis is a design choice, not a limit of GraphQL. The schema does contain one mutation, `registerHandlingEvent`, because recording a handling event is the one write a tracking client legitimately initiates, and Chapter 8 treats mutations in detail. Booking a cargo and assigning its route remain REST and gRPC operations in the owning services. Chapter 2 gives the criteria that put each interaction on its side of that line.

## What a query looks like

The tracking question becomes one GraphQL document, written against the canonical schema. The shape of the selection is the shape of the answer.

```graphql
query TrackCargo($id: TrackingId!) {
  cargo(trackingId: $id) {
    trackingId
    origin { unLocode name }
    destination { unLocode name }
    delivery {
      transportStatus
      lastKnownLocation { name }
      estimatedTimeOfArrival
      nextExpectedActivity {
        type
        location { unLocode }
        voyage { number }
      }
    }
    itinerary {
      legs {
        voyage { number }
        loadLocation { unLocode }
        unloadLocation { unLocode }
        unloadTime
      }
    }
    handlingHistory(first: 2) {
      edges {
        node { type location { unLocode } completionTime }
      }
    }
  }
}
```

The operation takes one variable, `$id`, typed with the schema's `TrackingId` scalar and marked non-null with `!`. The root field `cargo` resolves one `Cargo` by tracking id. Inside it, `origin`, `destination` and `lastKnownLocation` are `Location` objects of which the client asks only for the UN/LOCODE and the name. `itinerary` is nullable in the schema because a cargo that has not been routed has none, and `handlingHistory(first: 2)` uses the Relay connection pattern that Chapter 12 covers: edges that wrap nodes, so the client can page through events newest first.

The response mirrors the selection field for field:

```json
{
  "data": {
    "cargo": {
      "trackingId": "ABC123",
      "origin": { "unLocode": "USNYC", "name": "New York" },
      "destination": { "unLocode": "NLRTM", "name": "Rotterdam" },
      "delivery": {
        "transportStatus": "ONBOARD_CARRIER",
        "lastKnownLocation": { "name": "New York" },
        "estimatedTimeOfArrival": "2026-10-11T18:00:00Z",
        "nextExpectedActivity": {
          "type": "UNLOAD",
          "location": { "unLocode": "DEHAM" },
          "voyage": { "number": "V100S" }
        }
      },
      "itinerary": {
        "legs": [
          {
            "voyage": { "number": "V100S" },
            "loadLocation": { "unLocode": "USNYC" },
            "unloadLocation": { "unLocode": "DEHAM" },
            "unloadTime": "2026-10-09T14:00:00Z"
          },
          {
            "voyage": { "number": "V200E" },
            "loadLocation": { "unLocode": "DEHAM" },
            "unloadLocation": { "unLocode": "NLRTM" },
            "unloadTime": "2026-10-11T18:00:00Z"
          }
        ]
      },
      "handlingHistory": {
        "edges": [
          { "node": { "type": "LOAD", "location": { "unLocode": "USNYC" }, "completionTime": "2026-10-01T08:30:00Z" } },
          { "node": { "type": "RECEIVE", "location": { "unLocode": "USNYC" }, "completionTime": "2026-09-30T16:00:00Z" } }
        ]
      }
    }
  }
}
```

Three properties of this exchange recur throughout the book. First, the response contains nothing the query did not name: no `description`, no `routeSpecification`, no event identifiers. Adding a field to the response means editing the query, not the server. Second, every value is typed by the schema, so `transportStatus` can only be one of the enum values `NOT_RECEIVED`, `IN_PORT`, `ONBOARD_CARRIER`, `CLAIMED` or `UNKNOWN`, and the server rejects a query that selects a field the schema does not define before running any code. Third, the response is one document even though the data came from at least three owners.

## How a request travels

The GraphQL specification at spec.graphql.org defines the language, the type system, validation and the execution algorithm. It does not define a transport. The GraphQL-over-HTTP specification, a GraphQL Foundation working draft that current servers already follow, covers HTTP, and it is what the servers in this book implement. The request path has four stages, drawn in Figure 1.2.

{% include excalidraw.html file="01-request-path" alt="Left-to-right and top-to-bottom flow of one GraphQL request. A client sends a single HTTP POST to the /graphql endpoint carrying a JSON body with query, variables and operationName. Inside a band labelled GraphQL server, the request passes through four stacked stages: parse, which turns the query text into a syntax tree; validate, which checks the tree against the schema; execute, which walks the selection set; and resolvers, one function per field. The resolvers fan out to three backing sources on the right: the cargo service over REST, the routing service over gRPC, and the handling event store. The resolvers return their results into a single JSON response containing data and errors, which travels back to the client as one HTTP response." caption="Figure 1.2 — One endpoint, one POST, four server stages and a fan-out to the services that own the data." %}

**One endpoint.** Every operation goes to the same URL, conventionally `/graphql`. Where REST encodes intent in the path and the verb, GraphQL encodes it in the document. The server does not route by URL; it routes by the fields the document selects.

**One POST.** The client sends a JSON object with a `query` string, an optional `variables` object and an optional `operationName` that selects one operation when the document defines several:

```http
POST /graphql HTTP/1.1
Host: tracking.example.test
Content-Type: application/json
Accept: application/graphql-response+json, application/json;q=0.9

{"query": "query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId } }",
 "variables": {"id": "ABC123"},
 "operationName": "TrackCargo"}
```

Variables travel beside the query text rather than inside it. That separation lets a server cache the parsed document, lets a client reuse one query with many inputs, and keeps user-supplied values out of the string that gets parsed, which is the same reason prepared statements exist in SQL. The GraphQL-over-HTTP specification also permits `GET` for queries, with the same parameters in the URL, and requires servers to refuse a mutation received over `GET` with a 4xx status instead of executing it; `405 Method Not Allowed`, with an `Allow` header, is the recommended choice. That `GET` form is what makes edge caching of reads possible, and Chapters 15 and 16 build on it.

**Parse, validate, execute.** The server first parses the text into an abstract syntax tree; a syntax error ends the request here. It then validates the tree against the schema: every selected field must exist on its parent type, arguments must match their declared types, every variable must be declared and used in positions its type allows, fragments must be well formed and must not form cycles. Validation runs without touching any data, which is why a typo in a field name fails fast and cheaply. The server then coerces the supplied variable values against their declared types; a missing `$id` or a value of the wrong type is rejected at this point, still before any resolver runs. Only a valid document with valid variable values is executed.

**Resolvers.** Execution walks the selection set from the root. Each field has a resolver, a function that receives the parent object and the field's arguments and returns a value or a promise of one. The `cargo` resolver calls the cargo service. The `itinerary` resolver may call the routing service. The `handlingHistory` resolver reads from the handling event store. Resolvers for sibling fields can run concurrently, and when a field returns an object, the executor recurses into the sub-selection. Chapter 6 covers this algorithm precisely, including the guarantee that top-level mutation fields run serially while query fields may run in parallel. Subscriptions, the third operation type, pass through the same parse and validate stages but produce a stream of results, one per event, over a long-lived connection instead of a single response. The canonical schema's `cargoHandled` subscription is the subject of Chapter 21, which compares GraphQL subscriptions with server-sent events and plain WebSockets.

**One response.** The result is a JSON map with at most three entries. `data` mirrors the selection. `errors`, when present, is a non-empty list of error objects. Each has a `message`; `locations` (line and column in the document) when the error can be tied to a point in the text; `path` (the response keys and list indices leading to the field) when it arose while executing a field; and an optional `extensions` map for application-defined codes. A third entry, `extensions`, carries server metadata such as tracing data. A request error, meaning a document that fails parsing or validation or variables that fail coercion, produces a response with no `data` entry at all, because execution never started. A request that fails partway through execution returns both: the fields that resolved, and the errors for the fields that did not.

Partial results lead to the null-propagation rule. When a resolver fails for a nullable field, that field becomes `null` in `data` and an entry appears in `errors`. When it fails for a non-null field, the `null` cannot be placed there, so it propagates to the nearest nullable parent, which becomes `null` instead; if no parent is nullable, the whole `data` becomes `null`. This is why the canonical schema marks `Leg.voyage` as nullable. If the voyage service is down, the leg still returns its locations and times, the client sees `voyage: null` and an error whose `path` is `["cargo", "itinerary", "legs", 0, "voyage"]`, and the screen can render a degraded but useful answer. Chapter 4 is devoted to this behavior and Chapter 9 to the error model around it.

## Where GraphQL wins

The strengths follow from putting shape control in the client's hands over a typed graph.

**Shape matched to the client.** The mobile screen and the web dashboard query the same schema and receive different payloads. Neither waits for a server release to get a field it needs, provided the field already exists in the graph. This is most valuable when client diversity is high and release cycles differ, which is the common situation with a public tracking page, two mobile apps and an internal operations console.

**Fewer round trips for connected data.** A screen that needs the cargo, its legs, each leg's voyage and the last events makes one request. On a high-latency link, one round trip against five is often the difference users notice.

**A single, introspectable contract.** The schema is machine-readable. Tooling can validate queries before they ship, generate typed client code, power editor completion and diff two versions of the schema to find breaking changes. Chapters 3 and 5 cover the type system and contract-first workflow, and Chapter 11 covers the breaking-change gate that fails a pull request when a schema edit would break an existing client.

**An aggregation point.** Because resolvers are arbitrary code, one field can be backed by a REST call, another by a gRPC call and a third by a database read, and the client sees one graph. Moving a field from one backing service to another does not change the schema. Chapter 20 extends this idea across teams with federation.

**Evolution without version numbers.** Adding a field never invalidates an existing query, because queries name only what they want. New enum values and new union members still need care, since a client may handle the existing set exhaustively. Retiring a field is done with `@deprecated` and usage data rather than a `/v2` path. This works only with discipline, which Chapters 10 and 11 describe.

## Where GraphQL loses

The same properties that make the model flexible make several things harder than they are in REST or gRPC. Each has an established answer, and each costs something.

**HTTP caching.** A `POST` to a single URL is, in practice, not cached by browsers, CDNs or shared proxies, which key their caches on the method and URL and do not read request bodies. REST gets caching with no extra work from `GET` on stable URIs and `ETag` validators. GraphQL needs persisted queries that turn a document into a short identifier a `GET` can carry (Chapter 15), plus response caching in front of the server and field-level caching inside it (Chapter 16).

**Query cost and denial of service.** The client chooses the shape, so a client can choose an expensive one. A query nesting `cargos`, `handlingHistory`, each event's `cargo` and its `handlingHistory` again can fan out across thousands of backend calls from a few hundred bytes of text. REST bounds cost by endpoint; GraphQL must bound it by analysis of the document, using depth limits, complexity scoring and pagination caps. Chapter 14 covers these defenses. Chapter 17 covers transport security and introspection control, and Chapter 18 the authentication and authorization that sit beside them.

**The N+1 problem.** The natural resolver design asks for a location once per field that needs one: twice per leg (load and unload) and once per event. A cargo with six legs and twelve events resolves twenty-four locations one at a time unless the server batches the lookups. Chapter 13 builds the dataloader pattern that turns that fan-out into a few batched calls, and the example asserts the call count so a regression fails a test.

**Error semantics.** An HTTP status code tells REST clients and monitors whether a request worked. Many GraphQL servers answer `200 OK` for every well-formed request, including one that failed validation, and the two stacks in this book do the same (Chapter 6 compares them with the specification), so a dashboard that counts non-2xx responses sees a healthy service while operations are failing. The current GraphQL-over-HTTP draft makes the status meaningful. Its rules are written for `application/graphql-response+json`, and it asks servers to apply the same codes to a legacy client that accepts only `application/json`, keeping that media type on a `2xx`. A response with no `data` entry is a request error and gets a `4xx` or `5xx`: `400` when the document fails parsing and `422` when it fails validation. Once execution has started, the response is `2xx` even when `data` is `null`: `200` when there are no errors, and `294` (a custom code, not registered with IANA, that the draft recommends only with its own media type) when errors accompany the data. Monitoring has to read the `errors` array either way. Chapter 9 sets out the conventions, including returning expected domain failures as typed data in a payload, as `registerHandlingEvent` does with its `userErrors` list of `UserError` values.

**File upload.** The core specification has no notion of binary payloads, and a JSON query body is the wrong carrier for them. A community multipart-request convention exists, but many teams avoid it and upload through a separate HTTP endpoint, then refer to the stored object by identifier in a mutation. The tracking view is read-oriented, and bulk binary transfer stays outside the graph.

**Observability of one endpoint.** Every request hits `POST /graphql`, so URL-keyed dashboards and access logs show one route with every latency mixed together. Useful telemetry has to name the operation and trace each resolver. Chapter 19 covers operation-level metrics and resolver traces with OpenTelemetry.

**Server complexity.** The cost the client no longer pays in round trips moves into the server as resolvers, batching, cost analysis and schema governance. A team that adopts GraphQL for a small, stable client set with one backing service gets that complexity without much of the benefit.

## When to reach for GraphQL

Put the two lists together and a profile emerges. GraphQL fits an interface that serves several kinds of client with different data needs over the same connected domain, where those clients are outside the server team's release schedule and the data lives behind several services. It fits reads better than writes, since reads are where selection shape matters most. It fits poorly for a single internal service-to-service operation, for high-volume binary or bulk transfers, for resource-centric public APIs whose consumers rely on HTTP caching, and for teams that cannot yet staff the operational work of cost control and observability.

That profile is a starting instinct and not a decision procedure. Chapter 2 turns it into seven explicit axes and applies them to each interaction in the shipping domain, so that "REST, gRPC or GraphQL" is answered per interaction instead of by whichever paradigm a team already prefers. The chapter ends with the **Decision** callout that every later chapter reuses.

For deeper background on the language and execution model, Samer Buna's *GraphQL in Action* walks through the schema, resolvers and client side in sequence, and William Lyon's *Full Stack GraphQL Applications* shows the end-to-end application view. Both are listed on the [Bibliography](../../bibliography/) page, next to the primary specifications: the GraphQL specification at [spec.graphql.org](https://spec.graphql.org/) and the [GraphQL-over-HTTP specification](https://http-spec.graphql.org/draft/).

## Where this goes next

This chapter put three paradigms next to one intent, defined the tracking view as the role GraphQL plays in this book, traced a request from a single `POST` through parse, validate and execute to a JSON response, and listed the places where the model gains and loses ground. Chapter 2 formalizes the choice with a decision framework applied to the shipping domain.

From there the book follows the request path in order. Chapters 3 to 5 cover the schema: the SDL and type system, nullability, and the contract-first workflow that keeps both stacks aligned with one schema. Chapters 6 to 8 cover execution, queries and resolvers, and mutations. Chapter 9 covers errors and partial results. Chapters 10 and 11 cover schema design and evolution, Chapters 12 to 16 cover pagination, batching, cost limits, persisted queries and caching, and the remaining chapters address security, observability, federation, real-time delivery, client integration, testing and running the stack.
