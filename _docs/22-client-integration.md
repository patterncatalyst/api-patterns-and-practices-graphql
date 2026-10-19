---
title: "Client integration"
order: 22
part: "Real-time & Client Integration"
description: "What a GraphQL client adds over curl: a normalized cache that answers a second query with no request and takes a mutation payload into the cached object, types generated from the canonical SDL that stop a build on a stale document, gql with local schema validation, the SmallRye typesafe and dynamic clients, partial results as data a client keeps, and a header that names the client."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Configure `InMemoryCache` type policies so a normalized cache answers a repeated query from memory and merges a mutation payload into the same entry.
- Generate typed documents with GraphQL Code Generator's `client` preset, and make a document that no longer matches the schema fail the build.
- Validate a `gql` document against the schema before it is sent, and build one with `gql.dsl` instead of a string.
- Call a GraphQL API from Java with the SmallRye typesafe and `DynamicGraphQLClient` clients, including `ErrorOr` for a field that may fail.
- Identify every client on the wire with `X-Client-Name`, `X-Client-Version`, and a named operation.

## Why this matters

Every chapter so far sent documents with `curl` and read the JSON that came back. That is enough to prove a server right, and it leaves everything a real consumer needs to the reader: writing a document that still matches the schema next month, reading the result as a typed value, keeping what it already knows, deciding what to do when half of an answer failed. A client library takes those jobs on, and the choice of client decides how much of the contract the consumer sees at build time instead of at run time.

The code is in `examples/22-client-integration/`. It starts from the Chapter 13 example and serves the same schema from both stacks, so there is no new server code. What is new is three clients, one per language, each run as a one-off container against Quarkus and then Python: Apollo Client with GraphQL Code Generator in TypeScript, `gql` in Python, and the SmallRye GraphQL typesafe and dynamic clients in Java. `verify.sh` asserts what each prints.

## What a client is for

`curl` gives a transport and nothing else. A client adds five things, and each of the three examples shows a different mix of them.

- **Documents.** The operation text lives in a file or a type, not in a shell string, and it is checked by something other than the server.
- **Typed results.** The response is a value with fields the compiler knows, not a JSON blob.
- **Errors as data.** The `errors` array of Chapter 9 becomes something a program branches on.
- **A cache.** What the client has already been told is kept and reused.
- **A transport.** Headers, retries and, for Chapter 21's subscriptions, a connection that stays open.

Figure 22.1 puts the three clients side by side. The orange rows are where they differ most: where the schema is checked, and whether anything is cached. Apollo Client checks documents at build time and caches by object identity. `gql` checks them when a request is made, against the SDL it was given. The SmallRye clients leave both to the server and to Java's own types.

{% include excalidraw.html file="22-client-landscape" alt="Three columns, one per client, each with six stacked rows: Document, Typing, Schema check, Cache, Partial result and Subscriptions. The SmallRye column says an annotated interface whose return type is the selection, records and enums, the server validates, none built in, ErrorOr on the field that may fail, and Multi methods. The gql column says gql text or gql dot dsl built from the schema, dicts with ariadne-codegen adding models, local against the SDL given to the client, none built in, TransportQueryError carries data and errors, and session subscribe over WebSocket. The Apollo Client column says graphql files compiled by codegen, TypedDocumentNode from the client preset, at build time by codegen, a normalized InMemoryCache, errors beside data under an error policy, and GraphQLWsLink over graphql-ws. The Schema check and Cache rows are highlighted in every column." caption="Figure 22.1 — Three clients against one contract. The rows that differ most are where the schema is checked and what is cached." %}

The same call, `TrackCargo` for `ABC123`, reads like this in each:

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

A client that stores each response whole can reuse only a response that repeats the request exactly. Apollo Client's `InMemoryCache` stores objects instead. Chapter 10 gave every `Node` a stable `id`, and the cache keys any object that has an `id` and a `__typename` by the pair: `Cargo:cargo_ABC123`. A response is flattened into those entries, and a field that holds an object becomes a reference to its entry. Chapter 16 listed this as the first of four places to keep an answer. Here it runs.

The example's JS client makes three operations against one server. `TrackCargo` asks for the cargo's `id`, `trackingId`, `description`, its origin and destination locations and two delivery fields. `TrackCargoBrief` asks for a subset of that on the same root field and arguments: `id`, `trackingId` and `delivery { transportStatus }`. `RegisterHandling` is the mutation of Chapter 8. Figure 22.2 follows the cache through them.

{% include excalidraw.html file="22-normalized-cache-update" alt="Three operation boxes on the left and the cache on the right. TrackCargo for ABC123 is request 1 and returns ONBOARD_CARRIER; an amber arrow labelled fills leads to ROOT_QUERY, which holds the key cargo with trackingId ABC123, and a reference leads to the entry Cargo cargo_ABC123 with trackingId, description, delivery routing status ROUTED and delivery transport status ONBOARD_CARRIER then IN_PORT. Two arrows from that entry lead to Location loc_USNYC, New York, the origin, and Location loc_NLRTM, Rotterdam, the destination. TrackCargoBrief is a subset of the first query and makes zero requests; a dashed arrow labelled answered from the entry reaches the cargo entry. RegisterHandling, an unload at DEHAM on V100S, is request 2; an amber arrow labelled merges delivery reaches the cargo entry and a second arrow adds HandlingEvent evt_10." caption="Figure 22.2 — The cache across three operations. Two requests leave the client; the second query is answered from the entry the first one wrote, and the mutation payload changes that same entry." %}

The client is built from three pieces, and the file shows all of them:

```typescript
let fetches = 0;
const countingFetch: typeof fetch = (input, init) => {
  fetches += 1;
  return fetch(input, init);
};

const cache = new InMemoryCache({
  typePolicies: {
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

`HttpLink` takes the `fetch` implementation as an option, which is the documented place to wrap it, so the counter sees every request that leaves the process. The first query prints `{"step":"track","status":"ONBOARD_CARRIER","fetches":1}`. The second, with the default `cache-first` policy, finds every field it selects already in `Cargo:cargo_ABC123` and prints `"fetches":1`: no request. `verify.sh` confirms it from the other side. After the whole run the servers' source-call log holds exactly three request ids, one each for the first query, the mutation and a page query that comes later, and no call belongs to the subset query.

`cache.extract()` shows the shape. It holds one `Cargo:cargo_ABC123` entry and two `Location:` entries, `loc_USNYC` and `loc_NLRTM`, keyed by id. A second cargo with the same origin would reuse `Location:loc_USNYC`, and a change to that location would show in both.

The mutation is why the server returns the changed object (Chapters 8 and 16). `registerHandlingEvent` answers with `cargo { id delivery { transportStatus } }`. The client reads `Cargo` and `cargo_ABC123` in the payload, finds the entry, and writes `IN_PORT` into it. A cache-only `readQuery` of the first document then returns `IN_PORT` with no request, and the step prints `"fetches":2`. Nothing in the client says "refetch the cargo"; the identity in the payload did the work. A mutation payload that omits `id` updates nothing, so the identity rule is a rule for the payload as much as for the queries.

The cache has a policy per request, and the example uses two. `cache-first`, the default for `client.query`, answers from the cache when every selected field is present and otherwise asks the server. `network-only` always asks, and the `ListCargos` step uses it so that the page is fetched whatever the cache holds. `readQuery` is the cache alone: it returns what is stored or nothing. Between them they cover the usual cases, a screen that should render at once from what is known and a screen that must be current. A cached answer is only as fresh as the last response that touched its entries, so a client that needs a freshness bound sets one per query. Chapter 16's TTLs apply to the layers behind the server; the client's bound is its own.

Variables are part of the cache key as well. The root entry stores `cargo({"trackingId":"ABC123"})`, so a query for `DEF456` is a different field of `ROOT_QUERY` that points at a different `Cargo` entry, and two queries for the same cargo with different selections share the entry and add fields to it. That is why the example passes the id as a variable (`$id: TrackingId!`) and never builds a document by string concatenation: the document stays constant, the cache keys stay predictable, and the server sees the same operation text for every cargo.

`Delivery` has no `id`, so the cache stores it inside the cargo entry and, by default, replaces it as a whole whenever a response brings a new one. The payload selects only `transportStatus`, while the first query also stored `routingStatus`. The type policy `Delivery: { merge: true }` merges the fields of the two objects instead, so `routingStatus` stays `ROUTED` after the update. Apollo's documentation on configuring the cache covers `typePolicies` and `merge`, and the next time a type without an id appears in a payload, that policy is the place to look.

## Types from the contract

A cache saves requests. Types prevent a different failure, the document that was right when it was written. GraphQL Code Generator's `client` preset reads two things: the schema and the documents. Its output is one `TypedDocumentNode` per operation, a document carrying its result and variable types.

The schema is the canonical SDL. The example does not copy `contracts/schema/` into the client; the compose file passes it to the image build as a named context, and the Containerfile mounts it at `/schema`:

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

The codegen configuration points at it and at the example's `.graphql` files:

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

The three custom scalars map to `string`, which is what they are on the wire (Chapter 3). Without the mapping the generated type of `trackingId` is `unknown`. `enumsAsTypes` emits `TransportStatus` as a union of string literals, and `importExtension` makes the generated files import each other with their extension.

That last setting matters because of how the client runs. Figure 22.3 shows the build. `npm ci` installs from the committed `package-lock.json`, codegen writes `src/gql/graphql.ts`, `tsc --noEmit` checks `main.ts` against it, and the runtime image, `ubi10/nodejs-24-minimal`, runs `node src/main.ts`. Node 24 strips the type annotations and runs the TypeScript files as they are, so there is no compile step to ship. Imports with extensions are what both Node and `tsc` accept in that mode.

{% include excalidraw.html file="22-codegen-loop" alt="Two bands. The upper band, Image build, shows contracts schema shipping graphql as a build context named schema and src operations graphql with TrackCargo, TrackCargoBrief, RegisterHandling and ListCargos both feeding graphql-codegen with the client preset; an amber arrow leads to src gql graphql.ts with the typed documents, which feeds tsc no-emit at TypeScript 7.0.2 checking main.ts, and an amber arrow from tsc leads to a dark box, node src main.ts, running the client with type stripping on Node 24. The lower band, codegen-check, shows a fixture cargo-weight.graphql that selects trackingId and weight, an arrow to graphql-codegen run as codegen check, and an amber arrow labelled refused to a box that reads exit 1, no files generated, Cannot query field weight on type Cargo, at the fixture line 4 column 5." caption="Figure 22.3 — Types and the refusal come from the same schema. A document that selects a field the contract lacks never becomes a type." %}

The lower half of the figure is the useful half. A second compose service, `codegen-check`, runs the build stage of the same image with a different configuration, `codegen.fail.ts`, whose only document selects `Cargo.weight`. The contract has no such field, and codegen stops:

```text
✖ Generate [FAILED: GraphQL Document Validation failed with 1 errors;
  Error 0: Cannot query field "weight" on type "Cargo".
    at /opt/app-root/src/fixtures/cargo-weight.graphql:4:5]
✔ Generate outputs
  ✖ One or more errors occurred, no files were generated. To allow output on errors, set config.allowPartialOutputs=true
```

The exit status is 1, `verify.sh` asserts the message, and the same would happen to a real document the day the contract dropped a field. This is the client's half of Chapter 5's contract loop. The server's build checks that it still conforms to the SDL, and the client's build checks that its documents still do. A removal that Chapter 11's breaking-change gate would flag shows up in the client build as a failed document before any consumer runs it.

The preset can also emit a persisted-document manifest. With `persistedDocuments: true` it writes `persisted-documents.json`, a map from `sha256:` hashes to document text, which is the registration step of Chapter 15 done at build time. Chapter 15's manifest is an `operations` list in Apollo's format, so a server that reads one needs a small conversion to read the other. The example leaves the option off, and the choice between the two formats is the server's.

## Python: gql

`gql` takes a different position on the same question. It validates at run time, but before anything is sent, and against the contract:

```python
sdl = "\n".join(path.read_text() for path in sorted(SCHEMA_DIR.rglob("*.graphql")))
...
client = Client(transport=transport, schema=sdl)
```

`SCHEMA_DIR` is `/schema`, filled by the same `additional_contexts` entry. With a schema in hand, `session.execute` checks each document against it first. The example runs a document that selects `weight` on `Cargo`, and the client refuses it with graphql-core's message: `Cannot query field 'weight' on type 'Cargo'.` The step prints `"sent":0`: the transport's request hook counted no request for it. The run sends three requests in all, the text query, the DSL query and the page query, and the server's log holds the same three.

The same schema builds documents. `gql.dsl` is a query builder whose fields come from the schema object, so a misspelled field fails when the document is built:

```python
ds = DSLSchema(client.schema)
query = dsl_gql(DSLQuery(ds.Query.location.args(unLocode="NLRTM").select(ds.Location.name)))
```

That asks for `location(unLocode: "NLRTM") { name }` and gets `Rotterdam`. Text documents and DSL documents go through the same session and the same validation.

The transport is `HTTPXAsyncTransport`, which hands its options to httpx. The example uses `event_hooks` to count requests and `headers` for the client name. Results are plain dicts. A project that wants models for them has the route the Apollo example takes at build time: `ariadne-codegen` generates a typed client from the same SDL and a set of documents. The example stays with `gql`, which is also the client Chapter 21 uses for subscriptions.

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

The Quarkus extension implements the interface and injects it. `Cargo` is a record of `trackingId`, `description` and `delivery`, so the generated document selects those three fields and nothing else. Adding a field to the record adds it to every request that returns it. The URL and the client-name header come from configuration under the same key:

```properties
quarkus.smallrye-graphql-client.tracking.url=${TRACKING_URL}
quarkus.smallrye-graphql-client.tracking.header.X-Client-Name=ch22-java
```

The custom scalars need one adaptation, which is the client's version of the mapping in the codegen configuration. A class with a static `of(String)` factory is treated as a scalar, and `@Name` gives the variable its declared type:

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

The input object takes `@Input("RegisterHandlingEventInput")`, which names the variable's type the way the SDL does. The mutation registers a `RECEIVE` at `SGSIN` for `VWX901` and gets `evt_11` with `IN_PORT` back, and `verify.sh` counts one `handling.appendEvent`.

Where a schema validates at build time for Apollo and at the client for `gql`, the typesafe client leaves it to the server, which answers a mismatched variable or field with a validation error. What the client gains is Java's own type system: the record is the selection and the result in one declaration.

The **dynamic** client is for a shape decided at run time. `DynamicGraphQLClient` takes a `Document` built with the `Document`, `Operation` and `Field` helpers:

```java
Document document = document(operation(
        field("location", args(arg("unLocode", "NLRTM")), field("name"))));
Response response = dynamic.executeSync(document);
```

The response is a `jakarta.json` object, so `getData().getJsonObject("location").getString("name")` reads `Rotterdam`. Both clients read the configuration key `tracking`, so they call the same server with the same header.

## Errors in a client

Chapter 9 gave failures a contract: a response may carry `data` and `errors` together, and each error has a path and a code. A client decides what that means for the program. The example runs the same page query, `cargos(first: 10)`, through all three clients, and the seed makes one of the six cargos, `GHI345`, fail at the booking service with `SERVICE_UNAVAILABLE`.

Each client keeps the part that arrived:

- **Apollo Client** resolves the promise with `data` and `error` when the document is sent with `errorPolicy: "all"`. `error` is a `CombinedGraphQLErrors` object holding the `errors` array. With the default policy, `none`, the promise rejects with the same object, and the partial data is not returned.
- **gql** raises `TransportQueryError` for a response with errors, and the exception carries `data` and `errors` as attributes. The example catches it and reads both.
- **SmallRye** declares where a failure may land. The node of each edge is an `ErrorOr<CargoSummary>`, which holds either the value or the errors reported at its path:

```java
public record CargoEdge(String cursor, ErrorOr<CargoSummary> node) {
}
```

  The page returns, each edge's `isPresent()` says whether its node loaded, and `getErrors()` lists what went wrong at that path. Without `ErrorOr`, the typesafe client raises an exception for the whole call.

The numbers are the part to read carefully, because they differ by server and not by client. On Python, `GHI345`'s loader key fails alone: the page has six edges, one null node and one error at `["cargos","edges",5,"node"]`. On Quarkus, SmallRye resolves the cargo loads of the page as one batch (Chapter 13), so the failure is reported at every edge: six null nodes and six errors. All three clients see the same on each server, and `verify.sh` asserts both outcomes per stack. A client cannot depend on how many nodes arrive. It can depend on the shape: nodes that loaded are in `data`, every error carries a path, and the code is `SERVICE_UNAVAILABLE`, which is a value the program can branch on to show a retry or a placeholder.

## Identifying the client

All three clients send `X-Client-Name` and `X-Client-Version`: `ch22-js`, `ch22-python` and `ch22-java`, each with `1.0.0`. The example's servers do not read them, so nothing asserts them here. Chapter 19 does read the header: a name per client is what turns a trace or a count of deprecated-field usage (Chapter 11) into an answer to which consumer needs to move. The header costs a line in each client's configuration, and the servers can ask for it later.

The operation name does the same job per document, and the example gives every document one: `TrackCargo`, `TrackCargoBrief`, `RegisterHandling`, `ListCargos`. An anonymous document shows up in a log or a metric as a hash of nothing. Codegen reinforces the habit: each named operation becomes a generated constant, such as `TrackCargoDocument`, and an anonymous one has nothing to call it by.

## Subscriptions from a client

This chapter's servers serve no subscription; `Subscription.cargoHandled` arrives with Chapter 21, which builds the server side and a client that speaks both WebSocket subprotocols. The three client libraries each have a route:

- **Apollo Client** adds a `GraphQLWsLink`, built on the `graphql-ws` package, and routes subscription operations to it with `split`, while queries and mutations stay on `HttpLink`.
- **gql** has WebSocket transports and `session.subscribe`, which is an async iterator of results.
- **SmallRye** returns a `Multi<T>` from a typesafe method annotated `@Subscription`.

The cache above does not change. A subscription event that carries `id` and `__typename` is written into the same entries, and a screen showing that object updates, which is the same mechanism the mutation payload used.

## On the wire

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

| Check | Quarkus | Python |
|---|---|---|
| codegen on the `Cargo.weight` fixture | exit 1, `Cannot query field "weight" on type "Cargo"`, no files | |
| JS `TrackCargo(ABC123)` then `TrackCargoBrief` | `ONBOARD_CARRIER`, `fetches` 1 and 1 | the same |
| JS cache | one `Cargo:cargo_ABC123`; `Location:loc_NLRTM`, `Location:loc_USNYC` | the same |
| JS `RegisterHandling` and cache-only read | `evt_10`, `IN_PORT`, `fetches` 2 | the same |
| JS `ListCargos` with `errorPolicy: "all"` | 6 edges, 6 null nodes, 6 errors, `fetches` 3 | 6 edges, 1 null node, 1 error |
| server log of the JS run | 3 request ids, 1 `handling.appendEvent` | the same |
| Python `TrackCargo`, DSL `location` | `IN_PORT`; `Rotterdam` | the same |
| Python document selecting `weight` | refused locally, 0 sent; 3 requests at the server | the same |
| Python `cargos(first: 10)` | 6 null nodes, 6 errors | 1 null node, 1 error at edge 5 |
| Java `cargo(ABC123)` | `Palletized electronics`, `IN_PORT` | the same |
| Java `CargoPage` with `ErrorOr` | 0 present, 6 edges with errors | 5 present, 1 edge with errors |
| Java `registerHandlingEvent` for `VWX901` | `evt_11`, `IN_PORT`, 1 `appendEvent` | the same |
| Java dynamic `location(NLRTM)` | `Rotterdam` | the same |
| schema | conforms; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

```bash
docker compose down -v
```

`bash examples/22-client-integration/verify.sh` runs the whole sequence in a fixed order and prints `PASS` only when both servers satisfy every row. The order matters: the JS client writes `evt_10` first, the Python client then reads the written state, and the Java client writes `evt_11`.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>The client is where the <em>client diversity and shape variance</em> axis of Chapter 2 stops being an argument and becomes code: three consumers in three languages ask for three shapes of the same data. The <em>contract and evolution style</em> axis decides how much of that is checked before it runs, which is the reason to generate types from the canonical SDL or to validate against it rather than trust a document written once. The <em>aggregation across sources</em> axis is why the normalized cache pays: objects from several sources share an identity, so one payload refreshes every view of them. The <em>operational and security cost</em> axis shows in the details, a client-name header on every request and an operation name on every document. The tracking view therefore ships one client per language with the idiomatic tool for each, builds the TypeScript client's types from <code>contracts/schema/</code> so a stale document fails the build, keeps partial results and branches on <code>extensions.code</code>, and identifies every client by name.</p></div>

## Where this goes next

This chapter put clients on the contract: a normalized cache that answered one query from another's response and took a mutation payload into the same entry, generated types that fail the build for a document the schema no longer supports, local validation in `gql`, the SmallRye typesafe and dynamic clients with `ErrorOr` for the node that may fail, partial results kept by all three, and a client name on every request.

Chapter 23 tests the whole of it: what a GraphQL API suite asserts at each layer, and the load-testing harness that runs the same documents at volume. For the client side, read the Apollo Client documentation on caching ("Caching in Apollo Client" and "Configuring the cache") and on `HttpLink`, the GraphQL Code Generator documentation for the client preset, the `gql` documentation on schema validation, the DSL module and transports, and the Quarkus guide to the SmallRye GraphQL client for the typesafe and dynamic clients and `ErrorOr`. The GraphQL-over-HTTP draft describes what a client sends, the media types and the `GET` and `POST` forms Chapter 15 used. *Full Stack GraphQL Applications* by William Lyon builds a React client on Apollo Client, and *GraphQL in Action* by Samer Buna covers consuming a GraphQL API from a client application.

## For deeper coverage

- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022) — a React client built on Apollo Client, with pagination and authorization.
- Samer Buna, *GraphQL in Action* (Manning, 2021) — consuming a GraphQL API from a client application.
- [Apollo Client — Caching in Apollo Client](https://www.apollographql.com/docs/react/caching/overview)
- [GraphQL Code Generator](https://the-guild.dev/graphql/codegen) — the `client` preset this chapter's TypeScript build runs.
- [Quarkus — SmallRye GraphQL Client](https://quarkus.io/guides/smallrye-graphql-client) — the typesafe and dynamic clients, and `ErrorOr`.
