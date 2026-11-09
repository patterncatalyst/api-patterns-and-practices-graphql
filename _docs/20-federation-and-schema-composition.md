---
title: "Federation & schema composition"
order: 20
part: "Observability & the Gateway"
description: "Split one graph across teams with entities, references and batched entity resolution, gate deploys on composition, and read a query plan from the subgraphs' logs."
duration: "16 min read"
---


## Learning objectives

By the end of this chapter you can:

- Split a schema into subgraphs by ownership, with `@key` entities and `resolvable: false` references for types another team owns.
- Batch entity resolution so a gateway's `_entities` request doesn't bring back the N+1 problem across a network.
- Gate deployment on composition and read `FIELD_TYPE_MISMATCH` and `INVALID_FIELD_SHARING`.
- Read a query plan from the subgraphs' own source-call logs.
- Choose the nullability of a federated field as a decision about team boundaries.

## Why this matters

With one schema owner, every new field is a pull request to one repository, reviewed by one team that knows the whole graph. That stops working when the cargo team waits on the handling team to approve a `Cargo` field, or when one person is the only one who knows which service backs which field. The schema owner becomes the queue.

Federation moves the queue. Each team owns a **subgraph**, a GraphQL service with its own schema, and a **gateway** composes the subgraphs into one **supergraph** that clients query. A gateway is an aggregation point one level up from a resolver: a field is backed by another team's GraphQL service.

It costs something. A query that crosses a team boundary becomes several requests between services, a composition step has to pass before anything deploys, and a failure in one team's service reaches fields that look like another team's. If one team owns the tracking view, one schema is cheaper. Federation pays when the ownership is real.

The tracking view splits into a cargo subgraph and a handling subgraph on each stack. A composer turns a pair of subgraphs into a supergraph file, and two gateways serve the two pairs. Clients see the canonical schema, minus `Query.node`, `Query.nodes` and `Subscription`: `Node` lookup across subgraphs needs entity interfaces and `@interfaceObject`, and subscriptions can't cross a gateway as a plain request and response.

## Subgraphs by ownership

The split follows who owns the data, not how the types are shaped (Figure 20.1). The booking and routing team's cargo subgraph holds `Cargo`, `Location` and `Voyage` with their itineraries, legs and route specifications, and the root fields `cargo`, `cargos`, `location` and `voyage`. The handling team's subgraph holds `HandlingEvent`, `Delivery`, `HandlingActivity`, `Mutation.registerHandlingEvent` and its input and payload types. Both read the booking and routing sources, because delivery state compares an itinerary with a handling history, but only the cargo subgraph exposes them as types.

{% include excalidraw.html file="20-subgraph-ownership" alt="Two columns of boxes inside bands, with a third band underneath. The left band, the cargo subgraph owned by the booking and routing team, holds Cargo keyed by trackingId with its description, origin, destination, route specification and itinerary, Location keyed by unLocode, Voyage keyed by number, and the root queries with the itinerary types. The right band, the handling subgraph owned by the handling team, holds Cargo keyed by trackingId with delivery and handlingHistory, HandlingEvent keyed by id, dashed reference boxes for Location and Voyage marked resolvable false, and the mutation with the delivery types. An amber double arrow between the two Cargo boxes is labelled the same entity, the same key. Dashed arrows from the two reference boxes point to the cargo subgraph's Location and Voyage and are labelled reference. The bottom band lists what both subgraphs define identically: PageInfo, Node with the scalars, and RoutingStatus." caption="Figure 20.1: Each field has one owner. An entity is shared by its key, and a reference names a place and nothing else." %}

## Entities, keys and references

An **entity** is an object type that more than one subgraph contributes fields to. `@key` names the fields that identify it, and those fields are the contract between subgraphs. `Cargo` is keyed by `trackingId`: the cargo subgraph defines its description, route and itinerary, the handling subgraph defines `delivery` and `handlingHistory`, and the supergraph merges the two definitions.

The handling subgraph has to say where an event happened, but it doesn't own locations. It declares `Location` with the key `unLocode` and `resolvable: false`: this subgraph can name a location by its key and has no entity resolver for it. `Voyage` is declared the same way. These are **references**. They keep the handling team from copying the cargo team's data, and they tell the gateway that a location's `name` comes from the cargo subgraph.

Value types both subgraphs return, such as `PageInfo`, are marked `@shareable`. Without it, composition treats a field that two subgraphs resolve as an accident and refuses it. Enums and the `Node` interface are defined identically in both, with the canonical descriptions copied verbatim, so the composed schema carries the contract's own text.

## Declaring an entity on each stack

A federated subgraph adds two root fields. `Query._service` returns the subgraph's SDL with its federation directives. `Query._entities` takes a list of **representations**, a `__typename` plus key fields such as `{__typename: "Cargo", trackingId: "ABC123"}`, and returns the matching objects. The Apollo Federation subgraph specification defines both, which is why a subgraph on one stack composes with a subgraph on the other.

SmallRye GraphQL has federation annotations: `@Key` makes a record an entity, `@Shareable` marks a shared type, and `@Link` on the API class declares the federation version. Two settings turn it on and make entity resolution batch:

```properties
quarkus.smallrye-graphql.federation.enabled=true
quarkus.smallrye-graphql.federation.batch-resolving-enabled=true
```

Strawberry has a federation module. `strawberry.federation.type(keys=[...])` declares an entity, and `strawberry.federation.Schema` adds `_service`, `_entities` and the `@link`.

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

A reference is a record with one component, and the key is the whole type:

```java
@Type("Location")
@Key(fields = @FieldSet("unLocode"), resolvable = false)
@Description("A port or terminal, identified by its UN/LOCODE.")
public record Location(@NonNull @Description("The UN/LOCODE, for example `NLRTM`.") UnLocode unLocode) {}
```

Both stacks print `@key(fields: "unLocode", resolvable: false)` on `Location` and declare Federation 2.7 with a schema-level `@link` importing `@key` and `@shareable`. SmallRye's printer writes a space before each colon, so any check on the printed SDL must allow either form.

## Resolving entities in a batch

The gateway sends `_entities` a list of representations. Resolving them one at a time reintroduces the N+1 problem across a network, so the entity resolver is a batch resolver: it turns the keys in one `_entities` request into one bulk call to the source and returns one entity per key, in order.

SmallRye's `@Resolver` marks an entity resolver without creating a query field. With `federation.batch-resolving-enabled`, the method receives the keys of every representation of its type in the request:

```java
@Resolver
@Description("Entity resolver: the cargo for each tracking id, in order.")
public Uni<List<Cargo>> cargoByTrackingId(@Name("trackingId") List<String> trackingIds, Context context) {
    return booking.getCargos(context.getExecutionId(), trackingIds).map(Outcome::values);
}
```

Strawberry calls `resolve_reference` once per representation, so the batching is a request-scoped `DataLoader`, the same one the other cargo fields use. Keys arrive as keyword arguments named as on the wire, so the parameter is `trackingId`:

```python
@classmethod
async def resolve_reference(
    cls, info: Info[TrackingContext], trackingId: TrackingId
) -> Cargo | None:
    """The entity resolver: ``_entities`` calls it once per representation.
    The parameter is named as the key is on the wire, because the representation's
    keys arrive as keyword arguments.

    Every call goes through the request's cargo loader, so the
    representations of one ``_entities`` request share one bulk booking call."""
    return await info.context.loaders.cargo.load(trackingId)
```

Five `Location` representations, with `DEHAM` twice, make one `location.getLocations` call keyed `DEHAM+NLRTM+SGSIN+USNYC`. An unknown key is `null` at its position, which is how a gateway learns that an entity doesn't exist.

## Composition as a gate

Composition is where subgraphs become a supergraph, and it can fail. The composer reads each subgraph's SDL, checks that they agree about every shared type and key, and writes the supergraph. If they disagree there is no supergraph, and that is the point: the error appears in a pipeline, before any client sees a broken graph.

Make composition an explicit step (Figure 20.2). `@theguild/federation-composition` 0.27.0, an MIT-licensed library from The Guild, exposes `composeServices`. `gateway/compose-supergraph.mjs` wraps it: it fetches `{ _service { sdl } }` from each subgraph URL, or reads an SDL file with `--file`, composes, and writes one file. On an error it prints `<code>: <message>` per error and exits `1`:

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

{% include excalidraw.html file="20-composition-pipeline" alt="Two rows, each with two subgraph boxes on the left. The first row has cargo on Quarkus at host 8302 and handling on Python at host 8305; the second has cargo on Python at host 8303 and handling on Quarkus at host 8304. Arrows labelled _service sdl lead from each pair to a composer box, composer-a and composer-b, which run composeServices and exit 0. An amber arrow from each composer leads to a supergraph file, supergraph-a.graphql and supergraph-b.graphql, in the supergraph volume, and from there to a gateway, gateway-a at host 8300 and gateway-b at host 8301, labelled loads. A black box between the two composers reads fixture run, exit 1, FIELD_TYPE_MISMATCH and INVALID_FIELD_SHARING, with a note that nothing is written, so there is nothing for a gateway to load." caption="Figure 20.2: Composition is a build step. A failed composition exits 1 and writes no file, so no gateway starts on a broken graph." %}

In compose, the composer is a one-shot service that waits for its subgraphs to be healthy, and each gateway waits for its composer to complete. The gateways load the file and compose nothing. Hive Gateway also has a development mode that composes at startup. Don't use it for deploys: a gate that runs inside the service it protects isn't a gate.

Two committed fixtures show what failure reads like. Each is the handling subgraph's SDL with one mistake, composed against a copy of the cargo subgraph's SDL. In the first, `Location.unLocode` is `String!` instead of `UnLocode!`, so the subgraphs disagree about the type of a key field:

```text
FIELD_TYPE_MISMATCH: Type of field "Location.unLocode" is incompatible across subgraphs: it has type "UnLocode!" in subgraph "cargo" but type "String!" in subgraph "handling"
```

In the second, `PageInfo` lacks `@shareable` in the handling subgraph, so both subgraphs resolve `PageInfo.hasNextPage` and composition reports `INVALID_FIELD_SHARING` once for each of the four fields. The codes are stable names: a pipeline can match on them and a team can look them up in the composition rules.

## A query plan

The gateway turns one client query into requests to subgraphs, a **query plan**. `TrackCargo` asks for fields from both teams:

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

The plan has three fetches (Figure 20.3). One request to the cargo subgraph covers the root field and everything it owns. The gateway then sends the cargo's key to the handling subgraph as an `_entities` request for `delivery` and `handlingHistory`. Those fields name locations, and only the cargo subgraph knows a location's `name`, so a third fetch goes back to the cargo subgraph with the locations handling named.

{% include excalidraw.html file="20-query-plan" alt="A gateway box on the left, labelled TrackCargo for ABC123 as one request, with three arrows to three subgraph boxes stacked on the right. Fetch 1 goes to the cargo subgraph for the cargo, description, itinerary and the legs' load locations. Fetch 2, drawn in amber, goes to the handling subgraph for the Cargo entity's delivery and handling history. Fetch 3 goes to the cargo subgraph for the Location entities. Dashed arrows lead from each fetch to the source calls it made: fetch 1 made booking getCargo, routing getItineraries and location getLocations for DEHAM plus USNYC; fetch 2 made booking getCargos, routing getItineraries, handling pageEvents and handling listEventsFor; fetch 3 made one location getLocations for USNYC. A note says fetch 3 waits for fetch 2, and that the logs show two distinct requests at the cargo subgraph and one at the handling subgraph." caption="Figure 20.3: One client request, three subgraph fetches. The cargo subgraph is asked twice and the handling subgraph once." %}

The plan's footprint is readable in the subgraphs' source-call logs, which carry a request id for each HTTP request that reached them. After one `TrackCargo`, the cargo subgraph's log holds two distinct request ids and the handling subgraph's holds one.

## References and one bulk call

Fetch 3 is the reference mechanism at work (Figure 20.4). The handling subgraph returns `Location { unLocode }` for every event it names. The gateway collects the distinct locations into one `_entities` request to the cargo subgraph, and the entity resolver turns the keys into one bulk call. DEF456's history has seven events at three places, and the log shows one location call:

```text
2 ['booking.getCargo:DEF456', 'location.getLocations:DEHAM+NLRTM+USNYC']
1 ['booking.getCargos:DEF456', 'handling.pageEvents:DEF456']
```

The first line is the cargo subgraph, the second the handling subgraph. More events change the size of one list, not the number of calls. This is DataLoader batching across a network boundary, and it works only because the entity resolver is a batch resolver: one that looked up a location per representation would make three calls.

{% include excalidraw.html file="20-entity-reference-fetch" alt="A row of three boxes from left to right. The handling subgraph's HandlingEvent.location returns Location with only an unLocode, seven events and seven references. An arrow labelled reference leads to a gateway box that sends one _entities request with representations of type Location and an unLocode to the cargo subgraph. An amber arrow labelled entities leads to the cargo subgraph box, which resolves with an at Resolver method on Quarkus or resolve_reference and a DataLoader on Python, one call for every key. An amber arrow labelled sorted, distinct leads down to a box reading location getLocations DEHAM plus NLRTM plus USNYC. Arrows labelled names and response lead back through the gateway, which merges each name into its event, to the client. A dashed box at the right notes that handling has no entity resolver for Location." caption="Figure 20.4: From a reference to a resolved entity. Seven references to three locations cost the cargo subgraph one bulk call." %}

## Mutations across subgraphs

`registerHandlingEvent` belongs to the handling subgraph, so the gateway sends the whole mutation there. The payload is where the graph crosses a boundary: `payload.cargo` is a `Cargo` whose `description` belongs to the cargo subgraph, so the gateway makes an entity fetch to it after the write:

```graphql
mutation($i: RegisterHandlingEventInput!) {
  registerHandlingEvent(input: $i) {
    handlingEvent { id }
    cargo { trackingId description delivery { transportStatus } }
    userErrors { code }
  }
}
```

The unload registers as `evt_10`, `description` is `Palletized electronics` from the cargo subgraph, and `delivery.transportStatus` is `IN_PORT`. The delivery is fresh because the team that wrote the event also computes the delivery. The handling subgraph logs one `handling.appendEvent:evt_10` and the cargo subgraph one `booking.getCargos:ABC123`. Repeating the request with the same idempotency key returns `evt_10` and writes nothing, so the idempotency convention holds across the gateway.

## The contract still holds

Composition adds federation directives and fields to the subgraph schemas, and none of it should reach a client. The gateway publishes an API schema with the directives and the `_service` and `_entities` fields removed. Diffed against the canonical schema, the only differences are the three unserved pieces: `Query.node`, `Query.nodes` and `Subscription`. The deprecation of `Itinerary.finalArrivalDate`, the `specifiedByURL` of `UnLocode` and `DateTime`, and every description survive composition.

`Node` is defined in both subgraphs with its implementers split between them: `Cargo`, `Location` and `Voyage` in one, `HandlingEvent` in the other. The gateway lists all four as possible types, so the interface survives a split without a contract change. The descriptions are copied verbatim into both subgraphs because composition merges the text and any drift would show in the diff.

## Two stacks, one supergraph

Two supergraphs run over the same four subgraph contracts (Figure 20.5). Gateway A, on `8300`, composes the cargo subgraph on Quarkus with the handling subgraph on Python. Gateway B, on `8301`, composes the cargo subgraph on Python with the handling subgraph on Quarkus.

{% include excalidraw.html file="20-cross-stack-topology" alt="A client box at the top with dashed arrows to two gateway boxes, gateway-a at host 8300 with supergraph-a and gateway-b at host 8301 with supergraph-b. Four subgraph boxes are in a row at the bottom: cargo on Quarkus at host 8302 and cargo on Python at host 8303, then handling on Quarkus at host 8304 and handling on Python at host 8305. Quarkus boxes are white and Python boxes are amber. Amber arrows cross: gateway-a leads to cargo on Quarkus and to handling on Python, and gateway-b leads to cargo on Python and to handling on Quarkus. A note says that either stack can own either subgraph." caption="Figure 20.5: Cross-wired gateways over the same subgraph contract. The supergraph does not know which stack is behind a subgraph." %}

The stacks differ only where their frameworks do. A failed key in a batch fails one edge on Strawberry and every edge of the batch on SmallRye, so the `cargos(first: 10)` page through gateway B carries one `SERVICE_UNAVAILABLE` error at the `GHI345` edge and five cargos, while the page through gateway A carries six errors and six null nodes. The code survives the gateway, which adds `extensions.serviceName` naming the subgraph that reported the error, useful when a team has to find an owner. Both pairs compose and answer `TrackCargo` with the same values in the same three fetches.

## When a subgraph is down

A supergraph is one graph with several failure domains. `Cargo.delivery` is `Delivery!` and `handlingHistory` is `HandlingEventConnection!`, both owned by the handling subgraph. With that subgraph stopped, `TrackCargo` fails the `_entities` fetch and the error lands at `["cargo", "delivery"]`. A null can't sit in a non-null field, so it climbs to the nearest nullable parent, `cargo`, and `data.cargo` is `null`. The gateway reports the fetch as `Unexpected error.` with code `INTERNAL_SERVER_ERROR`, and its log names the subgraph, `handling`.

Everything the cargo subgraph owns still answers. Nullability at a seam is a decision about the team boundary:

| `delivery` is | Clients get | The cargo depends on |
|---|---|---|
| `Delivery!` | a guarantee that every cargo has a delivery state | the handling team's availability |
| `Delivery` | a cargo that survives a handling outage, and a null check in every client | nothing from handling |

Null propagation posed this trade-off for one service. Federation poses it between two teams.

## Operating a supergraph

- **Composition in CI.** Each team's pipeline composes its subgraph with the others' published schemas before it deploys and fails on any code. That catches the change that is valid alone and invalid together. Diffing the composed API schema against the canonical contract makes a subgraph change that alters the contract a visible, reviewable change.
- **Trace propagation.** Hive Gateway's OpenTelemetry integration creates a span for the gateway's plan and propagates the W3C `traceparent` header to each subgraph request, so one trace holds the gateway's work and each subgraph's operation span. See "Monitoring and Tracing" in the Hive Gateway documentation.
- **`@requires` and `@provides`.** `@requires` declares fields the gateway must fetch and pass in the representation before it calls the resolver. `@provides` lets a subgraph resolve fields of a type it normally only references. Both add coupling between teams, so use them where the alternative is a copy of the data.

`examples/20-federation` runs neither the tracing integration nor `@requires` and `@provides`.

> **Decision**
>
> Keep one schema while one team owns the tracking view. When two teams each own their part, split it into a cargo subgraph and a handling subgraph, composed by an explicit step that fails the deploy. Each subgraph shares an entity by its key, names the other team's types as references, and batches entity resolution into one bulk call. Clients still see one schema, so client diversity is untouched; the cost is a build step, a gateway to operate, and a cross-service request for every field a team doesn't own.

> **🤖 Explore with your agent**
>
> "In examples/20-federation, add a `Cargo.customsStatus: String` field owned by the handling subgraph on both stacks. Share `Cargo` by its `trackingId` key without moving any cargo-subgraph field, batch any new entity lookup into one source call, and make the field nullable so a handling outage doesn't null the whole cargo. Then compose both pairs with `gateway/compose-supergraph.mjs` and show the composer exits 0."
>
> Check: `bash examples/20-federation/verify.sh` still prints `PASS`, and a composition against `fixtures/handling-key-type-conflict.graphql` still exits 1 with `FIELD_TYPE_MISMATCH`.

## Build, run, observe

Start the stack. The gateways are on `8300` and `8301`, and the subgraphs publish `8302` to `8305` for the source-call logs. The composers run before the gateways start.

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

Experiments:

- Remove `@shareable` from `PageInfo` in the handling subgraph: composition exits 1 with `INVALID_FIELD_SHARING` for each of the four fields.
- Change `Location.unLocode` in the handling subgraph to `String!`: composition exits 1 with `FIELD_TYPE_MISMATCH` and writes no supergraph file.
- Stop the handling subgraph: `data.cargo` is `null` with an error at `["cargo","delivery"]`, and `location(unLocode: "NLRTM")` still returns `Rotterdam`.

## For deeper coverage

- Vlad Khononov, *Learning Domain-Driven Design* (O'Reilly, 2021): bounded contexts and team ownership, the organizational question federation turns into a schema split.
- Cloud Native Design Patterns, chapter "API Management": governing an API surface across teams and services, the broader concern a gateway and composition gate address.
- Apollo Federation subgraph specification: `Query._service`, `Query._entities`, `@key`, `@shareable`, `@external`, `@requires` and `@provides`.
- Hive documentation: the composition library (`composeServices`) and Hive Gateway's "Gateway: Supergraph schema" and "Monitoring and Tracing" pages.
- [SmallRye GraphQL guide, federation section](https://quarkus.io/guides/smallrye-graphql) and Strawberry's [federation guide](https://strawberry.rocks/docs/guides/federation): the framework APIs behind `@Key`/`@Resolver` and `strawberry.federation`/`resolve_reference`.
