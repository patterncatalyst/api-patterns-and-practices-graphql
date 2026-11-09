---
title: "Client integration"
order: 22
part: "Real-time & Client Integration"
description: "A normalized cache, types generated from the canonical SDL, gql with local validation, the SmallRye typesafe and dynamic clients, partial results, and a header that names the client."
duration: "17 min read"
---


## Learning objectives

By the end of this chapter you can:

- Configure `InMemoryCache` type policies so a normalized cache answers a repeated query from memory and merges a mutation payload into the same entry.
- Generate typed documents with GraphQL Code Generator's `client` preset, and fail the build on a document that no longer matches the schema.
- Validate a `gql` document against the schema before it is sent, and build one with `gql.dsl`.
- Call a GraphQL API from Java with the SmallRye typesafe and dynamic clients, using `ErrorOr` for a field that may fail.
- Identify every client on the wire with `X-Client-Name`, `X-Client-Version` and a named operation.

## Why this matters

`curl` is enough to prove a server right and leaves everything else a consumer needs to the reader: a document that still matches the schema next month, a typed result, what the client already knows, and what to do when half of an answer failed. A client library takes those jobs on, and the choice of client decides how much of the contract the consumer sees at build time instead of at run time.

The same schema is served from both stacks, so there is no new server code. Three clients, one per language, run as one-off containers against Quarkus and then Python: Apollo Client with GraphQL Code Generator in TypeScript, `gql` in Python, and the SmallRye GraphQL typesafe and dynamic clients in Java.

## What a client is for

`curl` gives a transport and nothing else. A client adds five things:

- **Documents.** The operation text lives in a file or a type, not in a shell string, and something other than the server checks it.
- **Typed results.** The response is a value with fields the compiler knows.
- **Errors as data.** The `errors` array becomes something a program branches on.
- **A cache.** What the client has been told is kept and reused.
- **A transport.** Headers, retries and, for a subscription, a connection that stays open.

Apollo Client checks documents at build time and caches by object identity (Figure 22.1). `gql` checks them when a request is made, against the SDL it was given. The SmallRye clients leave both to the server and to Java's own types.

{% include excalidraw.html file="22-client-landscape" alt="Three columns, one per client, each with six stacked rows: Document, Typing, Schema check, Cache, Partial result and Subscriptions. The SmallRye column says an annotated interface whose return type is the selection, records and enums, the server validates, none built in, ErrorOr on the field that may fail, and Multi methods. The gql column says gql text or gql dot dsl built from the schema, dicts with ariadne-codegen adding models, local against the SDL given to the client, none built in, TransportQueryError carries data and errors, and session subscribe over WebSocket. The Apollo Client column says graphql files compiled by codegen, TypedDocumentNode from the client preset, at build time by codegen, a normalized InMemoryCache, errors beside data under an error policy, and GraphQLWsLink over graphql-ws. The Schema check and Cache rows are highlighted in every column." caption="Figure 22.1: Three clients against one contract. The rows that differ most are where the schema is checked and what is cached." %}

The same call, `TrackCargo` for `ABC123`, in each:

{% include codetabs.html langs="Java|Python|TypeScript" %}

```java
var cargo = tracking.cargo(new TrackingId("ABC123"));
```

```python
data = await session.execute(TRACK_CARGO, variable_values={"id": "ABC123"})
```

```typescript
const track = await client.query({ query: TrackCargoDocument, variables: { id: "ABC123" } });
```

All three print `IN_PORT` for `ABC123` after the first client has written to it, `ONBOARD_CARRIER` before.

## The normalized cache

A client that stores each response whole can reuse only a response that repeats the request exactly. Apollo Client's `InMemoryCache` stores objects. Every `Node` has a stable `id`, and the cache keys any object with an `id` and a `__typename` by the pair, `Cargo:cargo_ABC123`. A response is flattened into those entries, and a field that holds an object becomes a reference to its entry.

Three operations run against one server (Figure 22.2). `TrackCargo` asks for the cargo's `id`, `trackingId`, `description`, origin and destination and two delivery fields. `TrackCargoBrief` asks for a subset on the same root field and arguments. `RegisterHandling` is the mutation.

{% include excalidraw.html file="22-normalized-cache-update" alt="Three operation boxes on the left and the cache on the right. TrackCargo for ABC123 is request 1 and returns ONBOARD_CARRIER; an amber arrow labelled fills leads to ROOT_QUERY, which holds the key cargo with trackingId ABC123, and a reference leads to the entry Cargo cargo_ABC123 with trackingId, description, delivery routing status ROUTED and delivery transport status ONBOARD_CARRIER then IN_PORT. Two arrows from that entry lead to Location loc_USNYC, New York, the origin, and Location loc_NLRTM, Rotterdam, the destination. TrackCargoBrief is a subset of the first query and makes zero requests; a dashed arrow labelled answered from the entry reaches the cargo entry. RegisterHandling, an unload at DEHAM on V100S, is request 2; an amber arrow labelled merges delivery reaches the cargo entry and a second arrow adds HandlingEvent evt_10." caption="Figure 22.2: The cache across three operations. Two requests leave the client; the second query is answered from the entry the first one wrote, and the mutation payload changes that same entry." %}

The client is built from three pieces: a counting `fetch`, the cache with its type policy, and the link:

```typescript
let fetches = 0;
const countingFetch: typeof fetch = (input, init) => {
  fetches += 1;
  return fetch(input, init);
};

const cache = new InMemoryCache({
  typePolicies: {
    // Delivery has no id of its own. Merging lets a response that selects some of
    // its fields update the same stored object instead of replacing it.
    Delivery: { merge: true },
  },
});

const client = new ApolloClient({
  link: new HttpLink({
    uri: url,
    fetch: countingFetch,
    headers: { "X-Client-Name": "ch22-js", "X-Client-Version": "1.0.0" },
  }),
  cache,
});
```

`HttpLink` takes the `fetch` implementation as an option, which is the documented place to wrap it, so a counter sees every request that leaves the process. The first query makes one fetch. The second, with the default `cache-first` policy, finds every field it selects already in `Cargo:cargo_ABC123` and makes none. The servers' source-call log agrees: no call belongs to the subset query.

`cache.extract()` holds one `Cargo:cargo_ABC123` entry and two `Location:` entries, `loc_USNYC` and `loc_NLRTM`. A second cargo with the same origin would reuse `Location:loc_USNYC`, and a change to that location would show in both.

The mutation is why the server returns the changed object, a convention both mutation design and caching depend on. `registerHandlingEvent` answers with `cargo { id delivery { transportStatus } }`. The client reads `Cargo` and `cargo_ABC123` in the payload, finds the entry and writes `IN_PORT` into it. A cache-only `readQuery` of the first document then returns `IN_PORT` with no request. Nothing says "refetch the cargo"; the identity in the payload did the work. A payload that omits `id` updates nothing, so the identity rule applies to payloads as much as to queries.

`Delivery` has no `id`, so the cache stores it inside the cargo entry and by default replaces it whole when a response brings a new one. The payload selects only `transportStatus`, while the first query also stored `routingStatus`. The type policy `Delivery: { merge: true }` merges the two objects' fields instead, so `routingStatus` stays `ROUTED` after the update. Apollo's "Configuring the cache" page covers `typePolicies` and `merge`; a type without an id in a payload is the case to check it for.

The cache has a policy per request:

| Read | Behavior | Use it for |
|---|---|---|
| `cache-first` (default for `client.query`) | Answers from the cache when every selected field is present, else asks the server | A screen that should render at once from what is known |
| `network-only` (the `ListCargos` step) | Always asks the server | A screen that must be current |
| `readQuery` | The cache alone: what is stored, or nothing | Reading after a mutation without a request |

A cached answer is only as fresh as the last response that touched its entries, so a client that needs a freshness bound sets one per query. The TTLs behind the server are separate from the client's bound.

Variables are part of the cache key. The root entry stores `cargo({"trackingId":"ABC123"})`, so a query for `DEF456` is a different field of `ROOT_QUERY` pointing at a different `Cargo` entry, and two queries for the same cargo with different selections share the entry and add fields to it. Pass the id as a variable (`$id: TrackingId!`) and never build a document by string concatenation: the document stays constant, the cache keys stay predictable, and the server sees the same operation text for every cargo.

## Types from the contract

A cache saves requests. Types prevent a different failure: the document that was right when it was written. GraphQL Code Generator's `client` preset reads the schema and the documents and writes one `TypedDocumentNode` per operation, a document carrying its result and variable types.

The schema is the canonical SDL. The client doesn't copy `contracts/schema/`; compose passes it to the image build as a named context, and the Containerfile mounts it at `/schema`:

```yaml
js-client:
  profiles: ["client"]
  build:
    context: ./clients/js
    dockerfile: Containerfile
    target: runtime
    additional_contexts:
      schema: ../../contracts/schema
```

The codegen configuration points at it and at the `.graphql` documents:

```typescript
const config: CodegenConfig = {
  schema: "/schema/**/*.graphql",
  documents: ["src/**/*.graphql"],
  generates: {
    "src/gql/": {
      preset: "client",
      presetConfig: { fragmentMasking: false },
      config: {
        useTypeImports: true,
        enumsAsTypes: true,
        importExtension: ".ts",
        scalars: { TrackingId: "string", UnLocode: "string", DateTime: "string" },
      },
    },
  },
  // A document that no longer matches the schema stops the run.
  ignoreNoDocuments: false,
};
```

The three custom scalars map to `string`, which is what they are on the wire. Without the mapping the generated type of `trackingId` is `unknown`. `enumsAsTypes` emits `TransportStatus` as a union of string literals, and `importExtension` makes generated files import each other with their extension, which both Node and `tsc` accept when Node 24 strips type annotations and runs the TypeScript as written. There is no compile step to ship.

The build (Figure 22.3) runs `npm ci` from the committed lockfile, codegen, then `tsc --noEmit` on `main.ts`. A second compose service, `codegen-check`, runs the same image with a configuration whose only document selects `Cargo.weight`. The contract has no such field, and codegen stops with exit status 1:

{% include excalidraw.html file="22-codegen-loop" alt="Two bands. The upper band, Image build, shows contracts schema shipping graphql as a build context named schema and src operations graphql with TrackCargo, TrackCargoBrief, RegisterHandling and ListCargos both feeding graphql-codegen with the client preset; an amber arrow leads to src gql graphql.ts with the typed documents, which feeds tsc no-emit at TypeScript 7.0.2 checking main.ts, and an amber arrow from tsc leads to a dark box, node src main.ts, running the client with type stripping on Node 24. The lower band, codegen-check, shows a fixture cargo-weight.graphql that selects trackingId and weight, an arrow to graphql-codegen run as codegen check, and an amber arrow labelled refused to a box that reads exit 1, no files generated, Cannot query field weight on type Cargo, at the fixture line 4 column 5." caption="Figure 22.3: Types and the refusal come from the same schema. A document that selects a field the contract lacks never becomes a type." %}

```text
✖ Generate [FAILED: GraphQL Document Validation failed with 1 errors;
  Error 0: Cannot query field "weight" on type "Cargo".
    at /opt/app-root/src/fixtures/cargo-weight.graphql:4:5]
✔ Generate outputs
  ✖ One or more errors occurred, no files were generated. To allow output on errors, set config.allowPartialOutputs=true
```

The same happens to a real document the day the contract drops a field. This is the client's half of the contract-first loop: the server's build checks that it still conforms to the SDL, and the client's build checks that its documents still do. A removal the breaking-change gate would flag shows up as a failed document before any consumer runs it.

With `persistedDocuments: true` the preset also writes `persisted-documents.json`, a map from `sha256:` hashes to document text, which is the persisted-query registration step done at build time. Apollo's manifest format is an `operations` list, so a server that reads one needs a small conversion to read the other. The option is off here, and the choice between the formats is the server's.

## Python: gql

`gql` validates at run time, but before anything is sent, and against the contract:

```python
sdl = "\n".join(path.read_text() for path in sorted(SCHEMA_DIR.rglob("*.graphql")))
...
client = Client(transport=transport, schema=sdl)
```

With a schema in hand, `session.execute` checks each document against it first. A document that selects `weight` on `Cargo` is refused locally with graphql-core's message, `Cannot query field 'weight' on type 'Cargo'.`, and no request leaves the client.

The same schema builds documents. `gql.dsl` is a query builder whose fields come from the schema object, so a misspelled field fails when the document is built:

```python
ds = DSLSchema(client.schema)
query = dsl_gql(DSLQuery(ds.Query.location.args(unLocode="NLRTM").select(ds.Location.name)))
```

That asks for `location(unLocode: "NLRTM") { name }` and gets `Rotterdam`. Text and DSL documents go through the same session and validation.

The transport is `HTTPXAsyncTransport`, which hands its options to httpx: `event_hooks` to count requests and `headers` for the client name. Results are plain dicts. A project that wants models has the route Apollo takes at build time: `ariadne-codegen` generates a typed client from the same SDL and a set of documents. `gql` is also the client for subscriptions.

## Java: SmallRye typesafe and dynamic clients

The Java client inverts the Apollo approach. There is no document file. An interface describes the operations, and the return types describe the selection:

```java
@GraphQLClientApi(configKey = "tracking")
public interface TrackingClient {

    @Query("cargo")
    Cargo cargo(@NonNull @Name("trackingId") TrackingId trackingId);

    @Query("cargos")
    CargoPage cargos(@Name("first") int first);

    @Mutation("registerHandlingEvent")
    RegisterPayload registerHandlingEvent(@NonNull @Name("input") RegisterInput input);
}
```

The Quarkus extension implements the interface and injects it. `Cargo` is a record of `trackingId`, `description` and `delivery`, so the generated document selects those three fields and nothing else, and adding a field to the record adds it to every request that returns it. The URL and the client-name header come from configuration under the same key:

```properties
quarkus.smallrye-graphql-client.tracking.url=${TRACKING_URL}
quarkus.smallrye-graphql-client.tracking.header.X-Client-Name=ch22-java
quarkus.smallrye-graphql-client.tracking.header.X-Client-Version=1.0.0
```

Custom scalars need one adaptation, the client's version of the mapping in the codegen configuration. A class with a static `of(String)` factory is treated as a scalar, and `@Name` gives the variable its declared type:

```java
@Name("TrackingId")
public record TrackingId(String value) {

    public static TrackingId of(String value) {
        return new TrackingId(value);
    }

    @Override
    public String toString() {
        return value;
    }
}
```

The input object takes `@Input("RegisterHandlingEventInput")`, which names the variable's type as the SDL does. The mutation registers a `RECEIVE` at `SGSIN` for `VWX901` and gets `evt_11` with `IN_PORT` back.

Where a schema validates at build time for Apollo and at the client for `gql`, the typesafe client leaves it to the server, which answers a mismatched variable or field with a validation error. What the client gains is Java's type system: the record is the selection and the result in one declaration.

The **dynamic** client is for a shape decided at run time. `DynamicGraphQLClient` takes a `Document` built with the `Document`, `Operation` and `Field` helpers:

```java
Document document = document(operation(
        field("location", args(arg("unLocode", "NLRTM")), field("name"))));
Response response = dynamic.executeSync(document);
```

The response is a `jakarta.json` object, so `getData().getJsonObject("location").getString("name")` reads `Rotterdam`. Both clients read the configuration key `tracking`, so they call the same server with the same header.

## Errors in a client

A response may carry `data` and `errors` together, and each error has a path and a code. The same page query, `cargos(first: 10)`, runs through all three clients, and the seed makes one of the six cargos, `GHI345`, fail at the booking service with `SERVICE_UNAVAILABLE`. Each client keeps the part that arrived:

| Client | Partial result |
|---|---|
| Apollo Client | Resolves with `data` and `error` when the document is sent with `errorPolicy: "all"`. `error` is a `CombinedGraphQLErrors` holding the `errors` array. With the default policy, `none`, the promise rejects with the same object and the partial data isn't returned. |
| gql | Raises `TransportQueryError`, which carries `data` and `errors` as attributes. |
| SmallRye | Declares where a failure may land. An `ErrorOr<T>` holds either the value or the errors reported at its path. Without it, the typesafe client raises for the whole call. |

For the SmallRye page, each edge's node is an `ErrorOr<CargoSummary>`, and `isPresent()` says whether it loaded while `getErrors()` lists what went wrong at that path:

```java
public record CargoEdge(String cursor, ErrorOr<CargoSummary> node) {
}
```

The counts differ by server, not by client. On Python, `GHI345`'s loader key fails alone: six edges, one null node and one error at `["cargos","edges",5,"node"]`. On Quarkus, SmallRye resolves the page's cargo loads as one batch, so the failure is reported at every edge: six null nodes and six errors. All three clients see the same on each server. A client can't depend on how many nodes arrive. It can depend on the shape: nodes that loaded are in `data`, every error carries a path, and the code is `SERVICE_UNAVAILABLE`, a value the program can branch on to show a retry or a placeholder.

## Identifying the client

All three clients send `X-Client-Name` and `X-Client-Version`: `ch22-js`, `ch22-python` and `ch22-java`, each with `1.0.0`. The servers don't read them, but observability does: a name per client turns a trace or a count of deprecated-field usage into an answer to which consumer needs to move. The header costs a line of configuration per client.

The operation name does the same job per document. Every document here has one: `TrackCargo`, `TrackCargoBrief`, `RegisterHandling`, `ListCargos`. An anonymous document shows up in a log or metric as a hash of nothing. Codegen reinforces the habit, since each named operation becomes a generated constant such as `TrackCargoDocument`.

## Subscriptions from a client

The servers here serve no subscription; `Subscription.cargoHandled` is the only unserved part of the contract. Each library has a route to one:

| Client | Route |
|---|---|
| Apollo Client | A `GraphQLWsLink` on the `graphql-ws` package, with `split` routing subscription operations to it while queries and mutations stay on `HttpLink` |
| gql | WebSocket transports and `session.subscribe`, an async iterator of results |
| SmallRye | A typesafe method annotated `@Subscription` that returns a `Multi<T>` |

The cache doesn't change. A subscription event that carries `id` and `__typename` is written into the same entries, and a screen showing that object updates, the same mechanism the mutation payload used.

> **Decision**
>
> Ship one client per language with the idiomatic tool for each. Build the TypeScript client's types from `contracts/schema/` so a stale document fails the build, or validate against the SDL before sending as `gql` does. Keep partial results and branch on `extensions.code`, return the changed object with its `id` from every mutation, and name every client and every operation.

> **🤖 Explore with your agent**
>
> "In examples/22-client-integration/clients/js, add a `TrackCargoSummary` operation that selects `trackingId` and `delivery { routingStatus }` and a step in src/main.ts that runs it after `TrackCargo`. Pass the id as a variable and give the document a name. Then show from the `fetches` counter whether it is answered from the cache, and say which `Delivery` type policy decides what `routingStatus` holds after `RegisterHandling`."
>
> Check: run `docker compose --profile client run --rm --build js-client http://quarkus:8080/graphql` and read `fetches` on the new step; codegen must still generate `TrackCargoSummaryDocument`.

## Build, run, observe

Start the servers. Quarkus is on `8320` and Python on `8321`; the clients run on the compose network and reach the servers by service name.

```bash
cd examples/22-client-integration
docker compose up -d --build
docker compose --profile client run --rm --build js-client http://quarkus:8080/graphql
```

```text
{"step":"track","status":"ONBOARD_CARRIER","fetches":1}
{"step":"brief","status":"ONBOARD_CARRIER","fetches":1}
{"step":"normalized","cargoKeys":["Cargo:cargo_ABC123"],"locationKeys":["Location:loc_NLRTM","Location:loc_USNYC"]}
{"step":"after-mutation","event":"evt_10","userErrors":0,"status":"IN_PORT","fetches":2}
```

The `partial` step follows. The Python and Java clients run the same way:

```bash
docker compose --profile client run --rm --build python-client http://quarkus:8080/graphql
docker compose --profile client run --rm --build -e TRACKING_URL=http://quarkus:8080/graphql java-client
docker compose --profile client run --rm --build codegen-check
```

```bash
docker compose down -v
```

| Check | Quarkus | Python |
|---|---|---|
| codegen on the `Cargo.weight` fixture | exit 1, `Cannot query field "weight" on type "Cargo"`, no files | |
| JS `TrackCargo` then `TrackCargoBrief` | `ONBOARD_CARRIER`, `fetches` 1 and 1 | the same |
| JS `ListCargos` with `errorPolicy: "all"` | 6 edges, 6 null nodes, 6 errors | 6 edges, 1 null node, 1 error |
| Python document selecting `weight` | refused locally, 0 sent | the same |
| Java `CargoPage` with `ErrorOr` | 0 present, 6 edges with errors | 5 present, 1 edge with errors |
| Java `registerHandlingEvent` for `VWX901` | `evt_11`, `IN_PORT` | the same |
| Java dynamic `location(NLRTM)` | `Rotterdam` | the same |

`bash examples/22-client-integration/verify.sh` runs the sequence in a fixed order and prints `PASS` when both servers satisfy every row. The order matters: the JS client writes `evt_10` first, the Python client then reads the written state, and the Java client writes `evt_11`.

Experiments:

- Select `Cargo.weight` in a document: codegen exits 1 and writes no files, and `gql` refuses the document before sending it.
- Send a mutation payload without `id`: the cache entry isn't updated.
- Remove `Delivery: { merge: true }`: `routingStatus` no longer survives the mutation payload.
- Use the default error policy on `ListCargos`: the promise rejects and the partial data isn't returned.

## For deeper coverage

- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022): a React client built on Apollo Client, with pagination and authorization.
- Samer Buna, *GraphQL in Action* (Manning, 2021): consuming a GraphQL API from a client application.
- [Apollo Client: Caching in Apollo Client](https://www.apollographql.com/docs/react/caching/overview), and the "Configuring the cache" and `HttpLink` pages.
- [GraphQL Code Generator](https://the-guild.dev/graphql/codegen): the `client` preset.
- The `gql` documentation on schema validation, the DSL module and transports.
- [Quarkus: SmallRye GraphQL Client](https://quarkus.io/guides/smallrye-graphql-client): the typesafe and dynamic clients, and `ErrorOr`.
- The GraphQL-over-HTTP draft: what a client sends, the media types, and the `GET` and `POST` forms used for persisted queries.
