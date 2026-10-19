---
title: "Federation & schema composition"
order: 20
part: "Observability & the Gateway"
description: "One graph owned by several teams: the tracking view split into a cargo subgraph and a handling subgraph on both stacks, entities and references, batched entity resolution, composition as a failing build step, a query plan counted from the subgraphs' logs, and two cross-wired Hive gateways that serve the canonical contract."
duration: "16 min read"
---

## Learning objectives

By the end of this chapter you can:

- Split a single schema into subgraphs by ownership, using `@key` to declare `Cargo` as a shared entity and `resolvable: false` references for types another team owns.
- Batch entity resolution (`@Resolver` with `federation.batch-resolving-enabled`, `resolve_reference` behind a `DataLoader`) so a gateway's `_entities` request doesn't reintroduce the N+1 problem across a network boundary.
- Gate deployment on composition (`composeServices`) and read `FIELD_TYPE_MISMATCH`/`INVALID_FIELD_SHARING` as the failure modes a broken subgraph produces.
- Trace a query plan across subgraph fetches from the subgraphs' own source-call logs, rather than trusting the gateway's documentation.
- Explain why a federated field's nullability choice, such as `Cargo.delivery`, is a decision about team boundaries and not just data shape.

## Why this matters

Chapter 2 named an axis that has stayed quiet since: who owns the schema, and who owns the services behind each field. Every chapter so far gave both answers to one team. This chapter gives them to two. The booking and routing team owns cargo, locations and voyages. The handling team owns handling events and the delivery state derived from them. Each team ships its own service and its own part of the graph, and clients still see one schema.

The code is in `examples/20-federation/`. It starts from the Chapter 13 example, cut into four services: a cargo subgraph and a handling subgraph on each stack. A composer turns a pair of subgraphs into a supergraph file, and two gateways serve the two pairs. The schema a client sees is the canonical one, minus `Query.node`, `Query.nodes` and `Subscription`, and `verify.sh` diffs both gateways against `contracts/schema/`.

## When one schema owner becomes the queue

Federation solves a coordination problem, not a technical one. With one schema owner, every new field is a pull request to one repository, reviewed by one team that understands the whole graph. That works while the graph is small and the team is one team. It stops working when the cargo team waits on the handling team to approve a `Cargo` field, or when the schema owner is the only person who knows which service backs which field. Chapter 2's seventh axis put the threshold in terms of people: several teams each want to contribute types, and a single owner becomes the queue.

Federation moves the queue. Each team owns a **subgraph**, a GraphQL service with its own schema, and a **gateway** composes the subgraphs into one **supergraph** that clients query. Chapter 1 described a resolver as an aggregation point: one field backed by a REST call, another by a database read, one graph on top. A gateway is the same idea one level up, where a field is backed by another team's GraphQL service.

It costs something. Every query that crosses a team boundary becomes several requests between services, a composition step has to pass before anything deploys, and a failure in one team's service reaches fields that look like another team's. If one team owns the tracking view, as in every earlier chapter, one schema is cheaper and simpler. Federation pays when the ownership is real.

## Subgraphs by ownership

The split follows who owns the data, not how the types are shaped (Figure 20.1). The cargo subgraph holds `Cargo`, `Location` and `Voyage` with their itineraries, legs and route specifications, and it serves the root fields `cargo`, `cargos`, `location` and `voyage`. The handling subgraph holds `HandlingEvent`, `Delivery`, `HandlingActivity`, `Mutation.registerHandlingEvent` and its input and payload types. Both read the booking and routing sources from Chapter 13, because the delivery state compares a cargo's itinerary with its handling history. Only the cargo subgraph exposes them as types.

{% include excalidraw.html file="20-subgraph-ownership" alt="Two columns of boxes inside bands, with a third band underneath. The left band, the cargo subgraph owned by the booking and routing team, holds Cargo keyed by trackingId with its description, origin, destination, route specification and itinerary, Location keyed by unLocode, Voyage keyed by number, and the root queries with the itinerary types. The right band, the handling subgraph owned by the handling team, holds Cargo keyed by trackingId with delivery and handlingHistory, HandlingEvent keyed by id, dashed reference boxes for Location and Voyage marked resolvable false, and the mutation with the delivery types. An amber double arrow between the two Cargo boxes is labelled the same entity, the same key. Dashed arrows from the two reference boxes point to the cargo subgraph's Location and Voyage and are labelled reference. The bottom band lists what both subgraphs define identically: PageInfo, Node with the scalars, and RoutingStatus." caption="Figure 20.1 — Each field has one owner. An entity is shared by its key, and a reference names a place and nothing else." %}

Two things stay out of this example. `Query.node` and `Query.nodes` would need the `Node` lookup to dispatch across subgraphs, which takes entity interfaces and `@interfaceObject`. `Subscription` is Chapter 21. Everything else in the canonical SDL has exactly one owning subgraph, apart from the few types both subgraphs must define.

## Entities, keys and references

An **entity** is an object type that more than one subgraph contributes fields to. The `@key` directive names the fields that identify it, and those fields are the contract between subgraphs. `Cargo` is an entity with the key `trackingId`: the cargo subgraph defines its description, route and itinerary, and the handling subgraph defines `delivery` and `handlingHistory`. Neither subgraph defines the whole type, and the supergraph merges the two definitions.

The handling subgraph also needs to say where an event happened. It does not own locations. It declares `Location` with the key `unLocode` and `resolvable: false`, which means "this subgraph can name a location by its key but has no entity resolver for it". The type carries one field, `unLocode`. `Voyage` is declared the same way. These are **references**. A reference keeps the handling team from copying the cargo team's data, and it tells the gateway that a location's `name` has to come from the cargo subgraph.

Value types that both subgraphs return, such as `PageInfo`, are marked `@shareable`. Without the directive, composition treats a field that two subgraphs resolve as an accident and refuses it, which is the second failure the composition section shows. Enums and the `Node` interface are defined identically in both, with every description copied from the canonical SDL, so the composed schema carries the contract's own text.

## Declaring an entity on each stack

A federated subgraph adds two root fields to its own schema. `Query._service` returns the subgraph's SDL, including the federation directives, and `Query._entities` takes a list of **representations** and returns the matching objects. A representation is a `__typename` and the key fields, such as `{__typename: "Cargo", trackingId: "ABC123"}`. Both are defined by the Apollo Federation subgraph specification, which is why a subgraph from any stack composes with any other.

On Quarkus, SmallRye GraphQL has federation annotations. `@Key` makes a record an entity, `@Shareable` marks a shared type, and `@Link` on the API class declares the federation version the subgraph speaks. Two settings in `application.properties` turn it on and make entity resolution batch:

```properties
quarkus.smallrye-graphql.federation.enabled=true
quarkus.smallrye-graphql.federation.batch-resolving-enabled=true
```

On Python, Strawberry has a federation module. `strawberry.federation.type(keys=[...])` declares an entity, and `strawberry.federation.Schema` adds `_service` and `_entities` and the `@link` for the version.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Type("Cargo")
@Key(fields = @FieldSet("trackingId"))
@Description("A consignment of goods being shipped, tracked end to end by its tracking id.")
public record Cargo(
        String id,
        @NonNull @Description("The public tracking identifier.") TrackingId trackingId,
        @NonNull @Description("Free-text description of the goods.") String description,
        ...
```

```python
@strawberry.federation.type(
    keys=["trackingId"],
    description="A consignment of goods being shipped, tracked end to end by its tracking id.",
)
class Cargo(Node):
    id: strawberry.ID = strawberry.field(
        description="The globally unique identifier of this cargo."
    )
    tracking_id: TrackingId = strawberry.field(description="The public tracking identifier.")
    ...
```

The handling subgraph's reference is a record with one component. The key is the whole type:

```java
@Type("Location")
@Key(fields = @FieldSet("unLocode"), resolvable = false)
@Description("A port or terminal, identified by its UN/LOCODE.")
public record Location(@NonNull @Description("The UN/LOCODE, for example `NLRTM`.") UnLocode unLocode) {}
```

Both stacks print the same directive on `Location`, `@key(fields: "unLocode", resolvable: false)`, and both declare Federation 2.7 with a schema-level `@link` that imports `@key` and `@shareable`. SmallRye's printer writes a space before each colon, so `verify.sh` matches these lines with a pattern that allows either.

## Resolving entities in a batch

The gateway sends `_entities` a list of representations, and each one has to become an object. Answering them one at a time is the N+1 problem from Chapter 13 across a network, so the entity resolver is a batch resolver.

SmallRye's `@Resolver` marks an entity resolver without creating a query field. With `federation.batch-resolving-enabled`, the method takes the list of keys of every representation of its type in the request, and returns one entity per key in the same order. It calls the same bulk source Chapter 13 introduced:

```java
@Resolver
@Description("Entity resolver: the cargo for each tracking id, in order.")
public Uni<List<Cargo>> cargoByTrackingId(@Name("trackingId") List<String> trackingIds, Context context) {
    return booking.getCargos(context.getExecutionId(), trackingIds).map(Outcome::values);
}
```

Strawberry calls `resolve_reference` once per representation, so the batching is a request-scoped `DataLoader`, the same one the other cargo fields use. The keys arrive as keyword arguments named as they are on the wire, so the parameter is `trackingId`:

```python
@classmethod
async def resolve_reference(
    cls, info: Info[TrackingContext], trackingId: TrackingId
) -> Cargo | None:
    return await info.context.loaders.cargo.load(trackingId)
```

The results are the same on both stacks. Five `Location` representations, with `DEHAM` twice, make one `location.getLocations` call keyed `DEHAM+NLRTM+SGSIN+USNYC`. An unknown key is `null` at its position, which is how a gateway learns that an entity does not exist.

## Composition as a gate

Composition is where subgraphs become a supergraph, and it can fail. The composer reads each subgraph's SDL, checks that the subgraphs agree about every shared type and key, and writes the supergraph. If they disagree, there is no supergraph, and that is the point: the error appears at build time, in a pipeline, before any client sees a broken graph. Chapter 11's breaking-change gate stops a pull request that would break clients, and composition is the same kind of gate for the seams between teams.

The example makes composition an explicit step (Figure 20.2). `@theguild/federation-composition` 0.27.0, an MIT-licensed library from The Guild, exposes a `composeServices` function. `gateway/compose-supergraph.mjs` is a short script around it. It fetches `{ _service { sdl } }` from each subgraph URL, or reads an SDL file with `--file`, composes, and writes one file. On an error it prints one line per error, `<code>: <message>`, and exits `1`:

```js
const result = composeServices(services);
if (result.errors?.length) {
  for (const error of result.errors) {
    console.log(`${error.extensions?.code ?? 'COMPOSITION_ERROR'}: ${error.message}`);
  }
  process.exit(1);
}
writeFileSync(values.out, result.supergraphSdl);
```

{% include excalidraw.html file="20-composition-pipeline" alt="Two rows, each with two subgraph boxes on the left. The first row has cargo on Quarkus at host 8302 and handling on Python at host 8305; the second has cargo on Python at host 8303 and handling on Quarkus at host 8304. Arrows labelled _service sdl lead from each pair to a composer box, composer-a and composer-b, which run composeServices and exit 0. An amber arrow from each composer leads to a supergraph file, supergraph-a.graphql and supergraph-b.graphql, in the supergraph volume, and from there to a gateway, gateway-a at host 8300 and gateway-b at host 8301, labelled loads. A black box between the two composers reads fixture run, exit 1, FIELD_TYPE_MISMATCH and INVALID_FIELD_SHARING, with a note that nothing is written, so there is nothing for a gateway to load." caption="Figure 20.2 — Composition is a build step. A failed composition exits 1 and writes no file, so no gateway starts on a broken graph." %}

In compose, the composer is a one-shot service that waits for its two subgraphs to be healthy, and each gateway waits for its composer to complete successfully. The gateways load the file and compose nothing. Hive Gateway also has a development mode that composes at startup; the example does not use it, because a gate that runs inside the service it protects is not a gate.

Two committed fixtures show what a failure reads like. Each is the handling subgraph's SDL with one mistake, composed against `fixtures/cargo.graphql`, a copy of the cargo subgraph's SDL. In the first, `Location.unLocode` is `String!` instead of `UnLocode!`. The two subgraphs now disagree about the type of a key field:

```text
FIELD_TYPE_MISMATCH: Type of field "Location.unLocode" is incompatible across subgraphs: it has type "UnLocode!" in subgraph "cargo" but type "String!" in subgraph "handling"
```

In the second, `PageInfo` lacks `@shareable` in the handling subgraph, so both subgraphs resolve `PageInfo.hasNextPage`, and composition reports `INVALID_FIELD_SHARING` once for each of the four fields. The codes are stable names. A pipeline can match on them, and a team can look them up in the composition rules.

## A query plan

The gateway turns one client query into requests to subgraphs, called a **query plan**. `TrackCargo` asks for fields from both teams:

```graphql
query TrackCargo($id: TrackingId!) {
  cargo(trackingId: $id) {
    trackingId description
    itinerary { legs { loadLocation { name } } }
    delivery { transportStatus lastKnownLocation { name } }
    handlingHistory(first: 2) { edges { node { type location { name } } } }
  }
}
```

The plan has three fetches (Figure 20.3). The root field and everything the cargo subgraph owns come from one request to it. The gateway then sends the cargo's key to the handling subgraph as an `_entities` request for `delivery` and `handlingHistory`. Those fields name locations, and only the cargo subgraph knows a location's `name`, so a third fetch goes back to the cargo subgraph with the locations handling named.

{% include excalidraw.html file="20-query-plan" alt="A gateway box on the left, labelled TrackCargo for ABC123 as one request, with three arrows to three subgraph boxes stacked on the right. Fetch 1 goes to the cargo subgraph for the cargo, description, itinerary and the legs' load locations. Fetch 2, drawn in amber, goes to the handling subgraph for the Cargo entity's delivery and handling history. Fetch 3 goes to the cargo subgraph for the Location entities. Dashed arrows lead from each fetch to the source calls it made: fetch 1 made booking getCargo, routing getItineraries and location getLocations for DEHAM plus USNYC; fetch 2 made booking getCargos, routing getItineraries, handling pageEvents and handling listEventsFor; fetch 3 made one location getLocations for USNYC. A note says fetch 3 waits for fetch 2, and that the logs show two distinct requests at the cargo subgraph and one at the handling subgraph." caption="Figure 20.3 — One client request, three subgraph fetches. The cargo subgraph is asked twice and the handling subgraph once." %}

The plan is not asserted from the gateway's internals. `verify.sh` reads the plan's footprint from the subgraphs' source-call logs, which carry a request id for each HTTP request that reached them. After one `TrackCargo`, the cargo subgraph's log holds two distinct request ids and the handling subgraph's holds one, and the calls under them are the ones in the figure. The numbers are properties of the run, not of the gateway's documentation: a different planner, or a different selection, would give different counts, and the log would show it.

## References and one bulk call

Fetch 3 is the reference mechanism at work (Figure 20.4). The handling subgraph returns `Location { unLocode }` for every event it names. The gateway collects them into one `_entities` request to the cargo subgraph, with one representation per distinct location, and the cargo subgraph's entity resolver turns the list of keys into one bulk call. DEF456's history has seven events at three places, and the log shows one call:

```text
2 ['booking.getCargo:DEF456', 'location.getLocations:DEHAM+NLRTM+USNYC']
1 ['booking.getCargos:DEF456', 'handling.pageEvents:DEF456']
```

The first line is the cargo subgraph, with its two requests and the one location call. The second is the handling subgraph, with its one request. The number of events does not change the number of calls; it changes the size of one list. This is Chapter 13's batching applied across a network boundary, and it only works because the entity resolver is a batch resolver. The gateway sends each distinct location once, so the request carries three representations, and a resolver that looked up one location per representation would make three calls instead of one.

{% include excalidraw.html file="20-entity-reference-fetch" alt="A row of three boxes from left to right. The handling subgraph's HandlingEvent.location returns Location with only an unLocode, seven events and seven references. An arrow labelled reference leads to a gateway box that sends one _entities request with representations of type Location and an unLocode to the cargo subgraph. An amber arrow labelled entities leads to the cargo subgraph box, which resolves with an at Resolver method on Quarkus or resolve_reference and a DataLoader on Python, one call for every key. An amber arrow labelled sorted, distinct leads down to a box reading location getLocations DEHAM plus NLRTM plus USNYC. Arrows labelled names and response lead back through the gateway, which merges each name into its event, to the client. A dashed box at the right notes that handling has no entity resolver for Location." caption="Figure 20.4 — From a reference to a resolved entity. Seven references to three locations cost the cargo subgraph one bulk call." %}

## Mutations across subgraphs

`registerHandlingEvent` is a field of the handling subgraph, so the gateway sends the whole mutation there. The payload is where the graph crosses a boundary. `payload.cargo` is a `Cargo`, and its `description` belongs to the cargo subgraph, so the gateway makes an entity fetch to it after the write:

```graphql
mutation($i: RegisterHandlingEventInput!) {
  registerHandlingEvent(input: $i) {
    handlingEvent { id }
    cargo { trackingId description delivery { transportStatus } }
    userErrors { code }
  }
}
```

The unload registers as `evt_10`, the `description` is `Palletized electronics` from the cargo subgraph, and `delivery.transportStatus` is `IN_PORT`. The delivery is fresh because the team that wrote the event also computes the delivery. The handling subgraph's log shows one `handling.appendEvent:evt_10`, and the cargo subgraph's shows one `booking.getCargos:ABC123`. Repeating the request with the same idempotency key returns `evt_10` and writes nothing, so Chapter 8's idempotency still holds across the gateway.

## The contract still holds

Composition adds federation directives and fields to the subgraph schemas, and none of it should reach a client. The gateway publishes an API schema with the directives and the `_service` and `_entities` fields removed. `verify.sh` checks the gateway as it checks every other example: `assert_sdl_conforms` diffs the introspected schema against `contracts/schema/`, and the only differences are the three unserved pieces, `Query.node`, `Query.nodes` and `Subscription`. The deprecation of `Itinerary.finalArrivalDate`, the `specifiedByURL` of `UnLocode` and `DateTime`, and every description survive composition. The directives a client can see are the five built-in ones, and the fields of `Query` are `cargo`, `cargos`, `location` and `voyage`.

`Node` is defined in both subgraphs, with its implementers split between them: `Cargo`, `Location` and `Voyage` in one, `HandlingEvent` in the other. The gateway's schema lists all four as possible types. That is why Chapter 3's interface can survive a split without a change to the contract, and why the descriptions are copied verbatim into both subgraphs: composition merges the text, and any drift would show in the diff.

## Two stacks, one supergraph

The example runs two supergraphs over the same four subgraph contracts (Figure 20.5). Gateway A, on `8300`, composes the cargo subgraph on Quarkus with the handling subgraph on Python. Gateway B, on `8301`, composes the cargo subgraph on Python with the handling subgraph on Quarkus. Every assertion that reads a gateway runs against both.

{% include excalidraw.html file="20-cross-stack-topology" alt="A client box at the top with dashed arrows to two gateway boxes, gateway-a at host 8300 with supergraph-a and gateway-b at host 8301 with supergraph-b. Four subgraph boxes are in a row at the bottom: cargo on Quarkus at host 8302 and cargo on Python at host 8303, then handling on Quarkus at host 8304 and handling on Python at host 8305. Quarkus boxes are white and Python boxes are amber. Amber arrows cross: gateway-a leads to cargo on Quarkus and to handling on Python, and gateway-b leads to cargo on Python and to handling on Quarkus. A note says that either stack can own either subgraph." caption="Figure 20.5 — Cross-wired gateways over the same subgraph contract. The supergraph does not know which stack is behind a subgraph." %}

The stacks differ only where their frameworks do, and the differences are the ones earlier chapters recorded. A failed key in a batch fails one edge on Strawberry and every edge of the batch on SmallRye, so the `cargos(first: 10)` page through gateway B carries one `SERVICE_UNAVAILABLE` error at the `GHI345` edge and five cargos, while the page through gateway A carries six errors and six null nodes. The code survives the gateway in both cases. The gateway adds `extensions.serviceName`, which names the subgraph that reported the error and is useful when a team has to find an owner. Everything else is the same: both pairs compose, and both answer `TrackCargo` with the same values in the same three fetches.

## When a subgraph is down

A supergraph is one graph with several failure domains. `Cargo.delivery` is `Delivery!` and `handlingHistory` is `HandlingEventConnection!`, both owned by the handling subgraph. With that subgraph stopped, `TrackCargo` fails the `_entities` fetch, the error lands at `["cargo", "delivery"]`, and Chapter 4's rule applies at the seam: a null cannot sit in a non-null field, so it climbs to the nearest nullable parent, which is `cargo`. `data.cargo` is `null`. The gateway reports the failed fetch with its own error, `Unexpected error.` with code `INTERNAL_SERVER_ERROR`, and its log names the subgraph, `handling`.

Everything the cargo subgraph owns still answers. The same cargo asked for `description`, an `itinerary` or a `location` returns data. The choice of nullability at a seam is a decision about the team boundary. A non-null `delivery` tells clients that a cargo always has a delivery state, and it makes the cargo depend on the handling team's availability. A nullable `delivery` would let the cargo survive and push the null check to every client. Chapter 4 gave the trade-off for one service, and federation turns it into a question for two teams.

## Operating a supergraph

A few practices turn the example into an operating model, and the example demonstrates only the first.

**Composition in CI.** Each team's pipeline composes its subgraph with the others' published schemas before it deploys, and fails on any code. Composition against the other teams' current schemas catches the change that is valid alone and invalid together. Teams also run the canonical-contract diff on the composed result, so a subgraph change that alters the API schema is a visible, reviewable change.

**Trace propagation.** A request that crosses a gateway crosses services, and Chapter 19's trace id has to follow it. Hive Gateway ships an OpenTelemetry integration that creates a span for the gateway's plan and propagates the W3C `traceparent` header to each subgraph request, so one trace holds the gateway's work and each subgraph's operation span. This example does not run the integration; it keeps the compose stack to the services the chapter needs. The "Monitoring and Tracing" page of the Hive Gateway documentation covers the configuration.

**`@requires` and `@provides`.** An entity field sometimes needs data that only another subgraph has. `@requires` declares the fields the gateway must fetch and pass in the representation before it calls the resolver, and `@provides` lets a subgraph resolve fields of a type it normally only references. Both add coupling between teams, so they are for the cases where the alternative is a copy of the data. The example does not use them.

## On the wire

Start the stack. The gateways are on `8300` and `8301`, and the subgraphs publish `8302` to `8305` for the source-call logs. The composers ran before the gateways started.

```bash
docker compose -f examples/20-federation/compose.yaml up -d --build
G() {  # G <port> <query> [variables-json]
  curl -s localhost:$1/graphql -H 'Content-Type: application/json' \
    -d "$(python3 -I -c 'import json,sys; print(json.dumps({"query": sys.argv[1], "variables": json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}}))' "$2" "${3:-{\}}")"; echo
}
SC() {  # SC <port>: the distinct request ids and the calls in a subgraph's log
  curl -s localhost:$1/debug/source-calls | python3 -I -c 'import json,sys; c=json.load(sys.stdin)["calls"]; print(len({x["request"] for x in c}), [x["source"]+"."+x["op"]+":"+x["key"] for x in c])'
}
```

A subgraph publishes its schema and answers entity requests directly. The cargo subgraph on Quarkus resolves one known and one unknown cargo:

```bash
G 8302 '{ _entities(representations: [{__typename: "Cargo", trackingId: "ABC123"}, {__typename: "Cargo", trackingId: "ZZZ999"}]) { ... on Cargo { description } } }'
```

```json
{"data":{"_entities":[{"description":"Palletized electronics"},null]}}
```

Composition rejects a broken subgraph and names the rule. The run exits `1` and writes nothing:

```bash
docker compose -f examples/20-federation/compose.yaml run --rm -T composer-a --out /tmp/rejected.graphql \
  --file cargo=/fixtures/cargo.graphql --file handling=/fixtures/handling-key-type-conflict.graphql
```

```text
FIELD_TYPE_MISMATCH: Type of field "Location.unLocode" is incompatible across subgraphs: it has type "UnLocode!" in subgraph "cargo" but type "String!" in subgraph "handling"
```

`TrackCargo` through gateway A, with the cargo subgraph on `8302` and the handling subgraph on `8305`. Clear the logs first:

```bash
for p in 8302 8305; do curl -s -X DELETE localhost:$p/debug/source-calls; done
G 8300 'query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId description itinerary { legs { loadLocation { name } } } delivery { transportStatus lastKnownLocation { name } } handlingHistory(first: 2) { edges { node { type location { name } } } } } }' '{"id":"ABC123"}'
SC 8302; SC 8305
```

```json
{"data":{"cargo":{"trackingId":"ABC123","description":"Palletized electronics","itinerary":{"legs":[{"loadLocation":{"name":"New York"}},{"loadLocation":{"name":"Hamburg"}}]},"delivery":{"transportStatus":"ONBOARD_CARRIER","lastKnownLocation":{"name":"New York"}},"handlingHistory":{"edges":[{"node":{"type":"LOAD","location":{"name":"New York"}}},{"node":{"type":"RECEIVE","location":{"name":"New York"}}}]}}}}
```

```text
2 ['booking.getCargo:ABC123', 'routing.getItineraries:ABC123', 'location.getLocations:DEHAM+USNYC', 'location.getLocations:USNYC']
1 ['booking.getCargos:ABC123', 'handling.pageEvents:ABC123', 'routing.getItineraries:ABC123', 'handling.listEventsFor:ABC123']
```

The page of cargos through gateway B, whose cargo subgraph is Python, carries one error at the `GHI345` edge:

```bash
G 8301 '{ cargos(first: 10) { edges { node { trackingId } } } }'
```

```json
{"errors":[{"message":"booking service unavailable","path":["cargos","edges",5,"node"],"extensions":{"code":"SERVICE_UNAVAILABLE","serviceName":"cargo"}}],"data":{"cargos":{"edges":[{"node":{"trackingId":"VWX901"}},{"node":{"trackingId":"XYZ789"}},{"node":{"trackingId":"STU678"}},{"node":{"trackingId":"DEF456"}},{"node":{"trackingId":"ABC123"}},{"node":null}]}}}
```

Stop the handling subgraph behind gateway A and ask again. The cargo is null, and the cargo subgraph's own fields still answer:

```bash
docker compose -f examples/20-federation/compose.yaml stop handling-python
G 8300 'query($id: TrackingId!) { cargo(trackingId: $id) { trackingId description delivery { transportStatus } } }' '{"id":"ABC123"}'
G 8300 '{ cargo(trackingId: "ABC123") { description } location(unLocode: "NLRTM") { name } }'
docker compose -f examples/20-federation/compose.yaml down -v
```

```json
{"errors":[{"message":"Unexpected error.","path":["cargo","delivery"],"extensions":{"code":"INTERNAL_SERVER_ERROR"}}],"data":{"cargo":null}}
{"data":{"cargo":{"description":"Palletized electronics"},"location":{"name":"Rotterdam"}}}
```

| Check | Gateway A (cargo Quarkus, handling Python) | Gateway B (cargo Python, handling Quarkus) |
|---|---|---|
| subgraph SDL | `Cargo` keyed by `trackingId`; `Location` and `Voyage` references (`resolvable: false`) in handling; Federation 2.7 | the same |
| `_entities`, Cargo | `[{description}, null]` on cargo; `ONBOARD_CARRIER` on handling | the same |
| `_entities`, five Locations | one `location.getLocations:DEHAM+NLRTM+SGSIN+USNYC` | the same |
| composition fixtures | `FIELD_TYPE_MISMATCH`, `INVALID_FIELD_SHARING`, exit 1 | the same |
| `TrackCargo(ABC123)` | values as above; cargo subgraph 2 request ids, handling 1 | the same |
| DEF456 history, seven locations | one `location.getLocations:DEHAM+NLRTM+USNYC` | the same |
| `cargos(first: 10)` | 6 errors at the six edges, all nodes null | 1 error at edge 5, five nodes resolved |
| `registerHandlingEvent` | `evt_10`, `IN_PORT`, one `appendEvent`; a repeat writes nothing | the same |
| schema | conforms; only `node`, `nodes` and `Subscription` unserved; `finalArrivalDate` deprecated | the same |
| `Node` possible types | `Cargo`, `HandlingEvent`, `Location`, `Voyage` | the same |
| handling subgraph stopped | `data.cargo` null, error at `["cargo","delivery"]`; `location(NLRTM)` is `Rotterdam` | the same |

`bash examples/20-federation/verify.sh` runs the whole sequence and prints `PASS` only when every check holds on both gateways.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Federation is the <em>team ownership and federation</em> axis of Chapter 2 made concrete, and it brings the <em>aggregation across sources</em> axis up a level: a field is now backed by another team's graph. The <em>contract and evolution style</em> axis is where it pays off, because the canonical schema is the contract and composition is the gate that keeps every subgraph inside it. The <em>operational and security cost</em> axis is what it spends: a build step to run, a gateway to operate, and a request that crosses a boundary for every field a team does not own. The <em>client diversity and shape variance</em> axis is untouched, since clients see one schema. The tracking view therefore stays one schema while one team owns it, and splits into a cargo subgraph and a handling subgraph, composed by an explicit step that fails the deploy, when two teams each own their part. Each subgraph shares an entity by its key, names the other team's types as references, and batches entity resolution into one bulk call.</p></div>

## Where this goes next

This chapter split the tracking view by ownership: two subgraphs on each stack, entities shared by key, references that name another team's types, batched entity resolvers, composition as a failing step with two fixtures that show its errors, a query plan counted from the subgraphs' logs, and two cross-wired gateways that serve the canonical contract and null a cargo when the handling team's service is down.

Chapter 21 returns to the one operation that cannot cross a gateway as a plain request and response. `Subscription.cargoHandled` pushes each new event to a client as it is registered, and the chapter compares GraphQL over WebSocket and server-sent events. For the specifications, read the Apollo Federation subgraph specification, in particular the sections on `Query._service`, `Query._entities`, `@key`, `@shareable`, `@external`, `@requires` and `@provides`, and the Hive documentation for the composition library and for Hive Gateway's "Gateway: Supergraph schema" and "Monitoring and Tracing" pages. The Quarkus [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) has a section on federation, and Strawberry's [federation guide](https://strawberry.rocks/docs/guides/federation) covers `strawberry.federation` and `resolve_reference`.

## For deeper coverage

- Vlad Khononov, *Learning Domain-Driven Design* (O'Reilly, 2021) — bounded contexts and team ownership, the organizational question federation turns into a schema split.
- Cloud Native Design Patterns, chapter "API Management" — governing an API surface across teams and services, the broader concern a gateway and composition gate address.
- Apollo Federation subgraph specification — `Query._service`, `Query._entities`, `@key`, `@shareable`, `@requires` and `@provides`, the directives this chapter's subgraphs declare.
- Hive documentation — the composition library (`composeServices`) and Hive Gateway's "Gateway: Supergraph schema" and "Monitoring and Tracing" pages.
- [SmallRye GraphQL guide, federation section](https://quarkus.io/guides/smallrye-graphql) and Strawberry's [federation guide](https://strawberry.rocks/docs/guides/federation) — the framework APIs behind `@Key`/`@Resolver` and `strawberry.federation`/`resolve_reference`.
