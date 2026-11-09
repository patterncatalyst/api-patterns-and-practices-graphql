---
title: "From REST/RPC to GraphQL"
order: 1
part: "Why GraphQL & the Decision Lens"
description: "One client question answered by REST, gRPC and GraphQL, and the path a GraphQL request takes from a single POST through parse, validate and execute to one JSON response."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Compare how REST, gRPC and GraphQL each assemble the answer to one client intent.
- Define the tracking view as a read-oriented aggregation layer in front of services that already exist.
- Trace a GraphQL request through `parse`, `validate`, `execute` and resolver fan-out to one JSON response.
- Explain how null propagation turns a failed `Leg.voyage` lookup into a degraded, not failed, response.
- Weigh GraphQL's strengths (shape matched to the client, fewer round trips) against its costs (HTTP caching, query cost, the N+1 problem).

## Why this matters

A customer opens a tracking page and types a tracking id. The page has one question to answer: where is my cargo, and what happens next? The facts live in three places. The cargo record holds the origin, destination and routing requirements. The routing service holds the itinerary, an ordered list of legs on named voyages. The handling history holds what has physically happened: received, loaded, unloaded, cleared by customs. A mobile client showing a glanceable status needs a handful of those fields. A web dashboard needs most of them.

Three API paradigms can serve that question, and each makes a different party assemble the answer. REST makes the client assemble it from several resources. gRPC makes the caller invoke typed methods on each service that owns a piece. GraphQL makes the server assemble it, shaped by a selection the client writes. The sibling REST and gRPC books cover the other two paradigms in depth; where a REST resource or a gRPC method appears here, it is introduced in a sentence.

## One intent, three paradigms

Take the intent "show the state of cargo `ABC123` and its remaining route".

A **REST** client treats the cargo as a resource and its related data as further resources:

```http
GET /cargos/ABC123
GET /cargos/ABC123/itinerary
GET /cargos/ABC123/handling-events?limit=2
GET /voyages/V100S
GET /voyages/V200E
```

The first response is the representation the server's author decided on. If it carries the complete delivery state, the client downloads fields a mobile screen never shows (overfetching). If it carries only identifiers, the client follows links for the rest (underfetching), and each link is another round trip over a mobile network. Embedding, sparse fieldsets and purpose-built view resources reduce both problems, but each is a server-side decision made for a client the author has to predict. A new screen means a new representation, parameter or endpoint.

A **gRPC** client treats the intent as a set of typed calls: the routing service returns an itinerary for a tracking id, and a handling service lists events. The contract is a `.proto` file, the calls are binary over HTTP/2, and generated stubs make each call a typed function. This suits calls between services, where one team controls both sides and latency matters. A browser cannot speak native gRPC; it needs gRPC-Web and, in most deployments, a translating proxy. The responses are still fixed messages, so a caller that wants three fields from each of three services makes three calls and receives three complete messages.

A **GraphQL** client treats the intent as a selection over a graph. The server publishes one schema describing every type and relationship: a `Cargo` has an `Itinerary`, an `Itinerary` has `Leg`s, a `Leg` has a `Voyage`, a `Cargo` has a `handlingHistory` of `HandlingEvent`s. The client sends one document naming the fields it wants, to whatever depth the schema allows, and receives JSON of exactly that shape. The internal lookups are the server's concern; the round trips on the client's network number one.

{% include excalidraw.html file="01-three-paradigms" alt="Three-column comparison of REST, gRPC and GraphQL answering the same client intent, show the state and remaining route of cargo ABC123. Each column stacks a mental model, a call shape and a result. The REST column, labelled resources and verbs, starts from GET /cargos/ABC123 and makes several GETs, one per resource such as the cargo, its itinerary and its events, which returns fixed representations that over- or under-fetch. The gRPC column, labelled typed methods, shows typed calls between services such as GetItinerary and ListEvents, made through generated stubs over binary HTTP/2 with one call per owning service, which returns fixed response messages and needs a proxy in a browser. The GraphQL column is highlighted in a light amber wash and labelled one graph, one selection: the client traverses a typed graph, cargo with its delivery and itinerary, sends one POST to /graphql with the query and variables in the JSON body, and receives JSON shaped like the query in one round trip for the screen." caption="Figure 1.1: Three paradigms, one intent: REST, gRPC and GraphQL answering the same tracking question." %}

| | Response shape fixed by | Combining done by | Fits best |
|---|---|---|---|
| REST | Server, per resource | Client | Resource-centric APIs that rely on HTTP caching |
| gRPC | Server, per method | Caller | High-volume calls between services |
| GraphQL | Client, per selection | Server | Many clients wanting different slices of connected data |

None of the three is a general answer. GraphQL is a good trade when many clients want different slices of the same connected data, and a poor one when the interaction is a single well-known operation between two services.

## The tracking view

GraphQL is often presented as a replacement for a service tier, and that framing leads teams into trouble. The role used here is narrower: the **tracking view**, a read-oriented aggregation layer in front of services that already exist.

The services behind it own the data and the rules. The cargo service decides what a booking is. The routing service decides which itinerary satisfies a route specification. The handling service records what physically happened. Each may speak REST or gRPC, and none needs to know GraphQL exists. The tracking view owns no business data. It owns a schema, resolvers that know which service to ask for which field, and the logic that stitches the answers into a graph and derives the delivery state from the handling events and the itinerary.

This keeps each paradigm's strengths where they belong. Writes go through the owning services with the validation, idempotency and transactional rules those services already enforce. Internal calls keep the speed and typing of gRPC. Clients get one schema to learn and one round trip per screen. The schema is the contract between the tracking view and every client, and it lives in the repository as SDL under `contracts/schema/`. Quarkus with SmallRye GraphQL and Python with Strawberry are both checked against that schema, so the contract does not depend on a language.

The emphasis on reads is a design choice. The schema has one mutation, `registerHandlingEvent`, because recording a handling event is the one write a tracking client legitimately initiates. Booking a cargo and assigning its route remain REST and gRPC operations in the owning services.

## What a query looks like

The tracking question becomes one document written against the canonical schema. The shape of the selection is the shape of the answer.

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

`$id` is typed with the schema's `TrackingId` scalar and marked non-null with `!`. `itinerary` is nullable because an unrouted cargo has none, and `handlingHistory(first: 2)` uses the Relay connection pattern: edges that wrap nodes, so the client can page through events newest first. The response mirrors the selection field for field:

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

Three properties recur everywhere. The response contains nothing the query did not name, so adding a field to a response means editing the query, not the server. Every value is typed by the schema: `transportStatus` can only be `NOT_RECEIVED`, `IN_PORT`, `ONBOARD_CARRIER`, `CLAIMED` or `UNKNOWN`, and a query selecting a field the schema does not define is rejected before any code runs. And the response is one document even though the data came from at least three owners.

## How a request travels

The GraphQL specification defines the language, the type system, validation and the execution algorithm, but no transport. The GraphQL-over-HTTP specification, a GraphQL Foundation working draft, covers methods, media types and status codes. The request path has four stages.

{% include excalidraw.html file="01-request-path" alt="Left-to-right and top-to-bottom flow of one GraphQL request. A client sends a single HTTP POST to the /graphql endpoint carrying a JSON body with the query and variables. Inside a band labelled GraphQL server, the request passes through four stacked stages: parse, which turns the query text into a syntax tree; validate, which checks the tree against the schema; execute, which walks the selection set; and resolvers, one function per field. The resolvers fan out to three backing sources on the right: the cargo service over REST, the routing service over gRPC, and the handling event store, which holds the handling history. The resolvers return their results into a single JSON response containing data and errors, which travels back to the client as one HTTP response." caption="Figure 1.2: One endpoint, one POST, four server stages and a fan-out to the services that own the data." %}

**One endpoint.** Every operation goes to the same URL, conventionally `/graphql`. REST encodes intent in the path and verb; GraphQL encodes it in the document, and the server routes by the fields the document selects.

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

Variables travel beside the query text rather than inside it. A server can cache the parsed document, a client can reuse one query with many inputs, and user-supplied values stay out of the string being parsed, the same reason prepared statements exist in SQL. The specification also permits `GET` for queries, with the same parameters in the URL, and requires servers to refuse a mutation received over `GET` with a 4xx status; `405 Method Not Allowed` with an `Allow` header is recommended. The `GET` form is what makes edge caching of reads possible.

**Parse, validate, execute.** The server parses the text into a syntax tree; a syntax error ends the request. It then validates the tree against the schema without touching data: every selected field must exist on its parent type, arguments must match their declared types, every variable must be declared and used where its type allows, and fragments must be well formed and acyclic. A typo in a field name therefore fails fast and cheaply. The server then coerces the supplied variables against their declared types, so a missing `$id` or a wrong-typed value is rejected before any resolver runs. Only a valid document with valid variables is executed.

**Resolvers.** Execution walks the selection set from the root. Each field has a resolver, a function that receives the parent object, the field's arguments and a request context and returns a value. The `cargo` resolver calls the cargo service, `itinerary` may call the routing service, and `handlingHistory` reads the handling event store. Resolvers for sibling fields can run concurrently, and when a field returns an object the executor recurses into the sub-selection. Top-level mutation fields run serially while query fields may run in parallel. Subscriptions pass through the same parse and validate stages but produce a stream of results over a long-lived connection instead of one response.

**One response.** The result is a JSON map with at most three entries:

| Entry | Contents |
|---|---|
| `data` | Mirrors the selection |
| `errors` | When present, a non-empty list. Each error has a `message`; `locations` (line and column) when it ties to a point in the text; `path` (response keys and list indices) when it arose during field execution; and an optional `extensions` map for application codes |
| `extensions` | Server metadata such as tracing data |

A request error (a document that fails parsing or validation, or variables that fail coercion) produces a response with no `data` entry, because execution never started. A request that fails partway returns both the fields that resolved and the errors for those that did not.

Partial results lead to the null-propagation rule. When a resolver fails for a nullable field, the field becomes `null` in `data` and an entry appears in `errors`. When it fails for a non-null field, the `null` cannot be placed there, so it propagates to the nearest nullable parent, which becomes `null` instead; if no parent is nullable, all of `data` becomes `null`. That is why the canonical schema marks `Leg.voyage` nullable. If the voyage service is down, the leg still returns its locations and times, the client sees `voyage: null` and an error whose `path` is `["cargo", "itinerary", "legs", 0, "voyage"]`, and the screen renders a degraded but useful answer.

## Where GraphQL wins

| Strength | Why |
|---|---|
| Shape matched to the client | A mobile screen and a web dashboard query the same schema and receive different payloads, and neither waits for a server release to get a field already in the graph. Most valuable when client diversity is high and release cycles differ |
| Fewer round trips for connected data | A screen needing the cargo, its legs, each leg's voyage and the last events makes one request. On a high-latency link that is often the difference users notice |
| One introspectable contract | Tooling validates queries before they ship, generates typed client code, powers editor completion and diffs two schema versions to find breaking changes |
| An aggregation point | One field can be backed by a REST call, another by a gRPC call and a third by a database read. Moving a field to another backing service does not change the schema, and federation extends the idea across teams |
| Evolution without version numbers | Adding a field never invalidates an existing query. Retiring one uses `@deprecated` and usage data rather than a `/v2` path. New enum values and union members still need care, because a client may handle the existing set exhaustively |

## Where GraphQL loses

The properties that make the model flexible make several things harder than they are in REST or gRPC. Each has an established answer, and each costs something.

**HTTP caching.** A `POST` to a single URL is in practice not cached by browsers, CDNs or shared proxies, which key on method and URL and do not read request bodies. REST gets caching from `GET` on stable URIs and `ETag` validators. GraphQL needs persisted queries that turn a document into a short identifier a `GET` can carry, plus response caching in front of the server and field-level caching inside it.

**Query cost.** The client chooses the shape, so it can choose an expensive one. A query nesting `cargos`, `handlingHistory`, each event's `cargo` and its `handlingHistory` again can fan out across thousands of backend calls from a few hundred bytes of text. REST bounds cost by endpoint; GraphQL must bound it by analyzing the document, with depth limits, complexity scoring and pagination caps.

**The N+1 problem.** The natural resolver design asks for a location once per field that needs one: twice per leg (load and unload) and once per event. A cargo with six legs and twelve events resolves twenty-four locations one at a time unless the server batches the lookups. The DataLoader pattern turns that fan-out into a few batched calls.

**Error semantics.** Many GraphQL servers answer `200 OK` for every well-formed request, including one that failed validation, and both stacks here do the same. A dashboard that counts non-2xx responses then sees a healthy service while operations fail. The current GraphQL-over-HTTP draft makes the status meaningful. Its rules are written for `application/graphql-response+json`, and it asks servers to apply the same codes to a legacy client that accepts only `application/json`, keeping that media type on a `2xx`. A response with no `data` entry is a request error and gets a `4xx` or `5xx`: `400` when the document fails parsing and `422` when it fails validation. Once execution has started the response is `2xx` even when `data` is `null`: `200` when there are no errors, and `294` (a custom code, not registered with IANA, that the draft recommends only with its own media type) when errors accompany the data. Monitoring has to read the `errors` array either way. Expected domain failures belong in typed data in the payload, as `registerHandlingEvent` does with its `userErrors` list of `UserError` values.

**File upload.** The core specification has no notion of binary payloads, and a JSON body is the wrong carrier. A community multipart convention exists, but many teams upload through a separate HTTP endpoint and refer to the stored object by identifier in a mutation.

**Observability of one endpoint.** Every request hits `POST /graphql`, so URL-keyed dashboards and access logs show one route with every latency mixed together. Useful telemetry has to name the operation and trace each resolver.

**Server complexity.** The cost the client no longer pays in round trips moves into the server as resolvers, batching, cost analysis and schema governance. A team adopting GraphQL for a small, stable client set with one backing service takes on that complexity without much of the benefit.

## When to reach for GraphQL

| Reach for it | Look elsewhere |
|---|---|
| Several kinds of client with different data needs over the same connected domain | A single internal service-to-service operation |
| Clients outside the server team's release schedule | High-volume binary or bulk transfers |
| Data behind several services | Resource-centric public APIs whose consumers rely on HTTP caching |
| Read-heavy interactions, where selection shape matters most | Teams that cannot yet staff cost control and observability |

That profile is a starting instinct, not a decision procedure. A decision framework turns it into seven explicit axes applied to each interaction in the shipping domain, so that "REST, gRPC or GraphQL" is answered per interaction instead of by whichever paradigm a team already prefers.

> **🤖 Explore with your agent**
>
> "In `examples/00-prerequisites/`, start the lab and send a `TrackCargo` request as a JSON POST to the Quarkus stack on port 8080 and to the Python stack on port 8081, selecting only `trackingId` and `origin { unLocode name }` with variable `$id` set to `ABC123`. Then take the full `TrackCargo` query and list which of its fields the lab's schema does not define yet, and for each say whether REST would need another request or GraphQL only a deeper selection."
>
> Check: both ports return the same `data` object, and a request selecting `delivery`, `itinerary` or `handlingHistory` returns `errors` and no data (Quarkus omits `data`, Python returns `"data":null`).

## Build, run, observe

This topic has no example of its own. It runs on the lab from Prerequisites and the lab, which serves a slice of the tracking view on Quarkus (port 8080) and Python (port 8081).

```bash
docker compose -f examples/00-prerequisites/compose.yaml up -d --build
curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
  -d '{"query":"query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId origin { unLocode name } } }","variables":{"id":"ABC123"},"operationName":"TrackCargo"}'
docker compose -f examples/00-prerequisites/compose.yaml down -v
```

Port 8081 answers the same request with the same `data`.

- Omit `variables`: the missing `$id` fails variable coercion before any resolver runs, and the response carries `errors` and no data. Quarkus omits the `data` entry; Python returns `"data":null`.
- Select a field the slice does not define, such as `delivery`: validation fails the same way.
- Send `"id":"NOPE99"`: `data.cargo` is `null` with no `errors`, because `Query.cargo` is nullable.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): the schema, resolvers and client side the tracking view sketches.
- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022): the end-to-end application view of the same request path. Both books are listed on the [Bibliography](../../bibliography/) page, next to the primary specifications.
- Cloud Native Design Patterns, [Communications](https://patterncatalyst.github.io/cloud-native-design-patterns/docs/02-communications/) chapter, for the REST and RPC styles GraphQL is contrasted against here.
- [GraphQL specification](https://spec.graphql.org/): the authoritative definition of the language, type system and execution algorithm.
- [GraphQL-over-HTTP specification](https://http-spec.graphql.org/draft/): the working draft for methods, media types and status codes.
