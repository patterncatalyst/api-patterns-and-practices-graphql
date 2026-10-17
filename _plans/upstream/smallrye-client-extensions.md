**Title:** Client request `extensions` never reach graphql-java's `ExecutionInput`, so `ApolloPersistedQuerySupport` cannot be plugged in

### Describe the bug

SmallRye parses the request's `extensions` into `SmallRyeContext#getExtensionsFromClient()`. When it builds the graphql-java `ExecutionInput` in `ExecutionService.execute`, though, it never calls `ExecutionInput.Builder.extensions(...)`. Instrumentation and `PreparsedDocumentProvider`s therefore always see `getExtensions()` as `{}`.

Two further checks in the same method block graphql-java's own persisted-query support even when it is installed through the documented `@Observes GraphQL.Builder` hook:

- A request with no `query`, such as an Apollo APQ hash-only request, is rejected with `Missing 'query' field in the request` before graphql-java runs (`ExecutionService.java:164–167` on `main`).
- graphql-java's convention for transports that require a query, `PersistedQuerySupport.PERSISTED_QUERY_MARKER` (`"PersistedQueryMarker"`), is rejected with `Unparseable input document`. `SmallRyeContextManager.populateFromExecutionInput` parses the query text itself, through `DocumentSupplier` → `QueryCache` → `ParseAndValidate.parse`, and throws `UnparseableDocumentException` (`SmallRyeContextManager.java:259`).

This is narrower than #2321 (server-side Apollo persisted queries with a manifest or annotations). Forwarding the extensions and letting a hash-only request through would let applications use graphql-java's existing `ApolloPersistedQuerySupport` today, through the `GraphQL.Builder` event. Any built-in feature for #2321 would likely need the same plumbing.

### Reproducer

Runnable project: [client-extensions](https://github.com/patterncatalyst/smallrye-graphql-reproducers/tree/main/client-extensions) in https://github.com/patterncatalyst/smallrye-graphql-reproducers. Its `@QuarkusTest` asserts the expected behaviour, so it fails until this is fixed:

```console
git clone https://github.com/patterncatalyst/smallrye-graphql-reproducers.git && cd smallrye-graphql-reproducers
mvn clean verify -pl client-extensions                                            # Quarkus 3.40.1 / SmallRye 2.18.5
mvn clean verify -pl client-extensions -Dquarkus.platform.version=4.0.0.Beta1     # SmallRye 3.0.0.Beta7
mvn clean verify -pl client-extensions -Dquarkus.platform.version=4.0.0.Beta1 -Dsmallrye-graphql.version=3.0.0.Beta-SNAPSHOT   # local main
```

Result on all three: Tests run: 5, Failures: 3 (`clientExtensionsReachExecutionInput`, `hashOnlyRequestRunsKnownDocument`, `persistedQueryMarkerRunsKnownDocument`). The two controls pass: the customization is active, and a full query with its hash runs.

The same code inline. The application uses only the documented `GraphQL.Builder` event, with `quarkus.smallrye-graphql.events.enabled=true`:

```java
@ApplicationScoped
public class GraphQLCustomizer {

    static final String HELLO = "{ hello }";
    static final String HELLO_SHA256 = "001c3174e099bd72b729d0c0a529ba9f5a740c446e2a6e1d71b283cb84ec3065";

    void customize(@Observes GraphQL.Builder builder) {
        // GraphQL.Builder has no getters; build once to read SmallRye's own instrumentation chain and keep it.
        var smallRyeInstrumentation = builder.build().getInstrumentation();
        builder.instrumentation(new ChainedInstrumentation(List.of(smallRyeInstrumentation, new EchoExtensions())));
        // One known document, so a hash-only request for it should run without sending the query text.
        builder.preparsedDocumentProvider(new ApolloPersistedQuerySupport(
                InMemoryPersistedQueryCache.newInMemoryPersistedQueryCache()
                        .addQuery(HELLO_SHA256, HELLO).build()));
    }

    /** Adds {@code extensions.received}: the map graphql-java saw as ExecutionInput#getExtensions(). */
    static final class EchoExtensions extends SimplePerformantInstrumentation {
        @Override
        public CompletableFuture<ExecutionResult> instrumentExecutionResult(ExecutionResult result,
                InstrumentationExecutionParameters parameters, InstrumentationState state) {
            var received = parameters.getExecutionInput().getExtensions();
            return CompletableFuture.completedFuture(ExecutionResultImpl.newExecutionResult().from(result)
                    .addExtension("received", received == null ? Map.of() : received).build());
        }
    }
}
```

Requests and responses (Quarkus 3.40.1):

```console
$ curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
    -d '{"query":"{ hello }","extensions":{"probe":"x"}}'
{"data":{"hello":"world"},"extensions":{"received":{}}}

$ curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
    -d '{"extensions":{"persistedQuery":{"version":1,"sha256Hash":"001c3174e099bd72b729d0c0a529ba9f5a740c446e2a6e1d71b283cb84ec3065"}}}'
{"errors":[{"message":"Missing 'query' field in the request","locations":[],"extensions":{"classification":"DataFetchingException"}}]}

$ curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
    -d '{"query":"PersistedQueryMarker","extensions":{"persistedQuery":{"version":1,"sha256Hash":"001c3174e099bd72b729d0c0a529ba9f5a740c446e2a6e1d71b283cb84ec3065"}}}'
{"errors":[{"message":"Unparseable input document","locations":[],"extensions":{"classification":"DataFetchingException"}}]}
```

### Expected behavior

- `ExecutionInput#getExtensions()` holds the client's `extensions`; the first response should carry `"received":{"probe":"x"}`.
- A hash-only request for a document known to the installed `ApolloPersistedQuerySupport` runs and returns `{"data":{"hello":"world"}}`.
- For an unknown hash, graphql-java's own `PersistedQueryNotFound` error comes back, so Apollo clients can retry with the query text.

### Suggested fix

In `ExecutionService.execute`:

1. Call `executionBuilder.extensions(smallRyeContext.getExtensionsFromClient())`. Treat a null map as empty.
2. When `query` is missing or empty but `extensions.persistedQuery` is present, build the `ExecutionInput` with `PersistedQuerySupport.PERSISTED_QUERY_MARKER` as the query instead of sending `Missing 'query' field`.
3. Make `DocumentSupplier` use the `Document` that the installed `PreparsedDocumentProvider` resolved, instead of re-parsing the marker text through `QueryCache`.

The Quarkus HTTP handler would also need to accept a POST or GET without `query` when `extensions` is present.

### Workaround

None inside SmallRye. Applications have to resolve the hash to the query text before SmallRye's handler runs, for example with a Vert.x route that rewrites the request body and then reroutes to `/graphql`.

### Environment

The same output was reproduced on:

| Quarkus | SmallRye GraphQL | graphql-java |
|---|---|---|
| 3.40.1 | 2.18.5 | 25.0 |
| 4.0.0.Beta1 | 3.0.0.Beta7 (BOM-managed) | 26.0 |
| 4.0.0.Beta1 | `main` at 8a13b16, built locally as `3.0.0.Beta-SNAPSHOT` (3 commits ahead of `3.0.0.Beta8`) | 26.0 |

Also: OpenJDK 25.0.3, Fedora 44, JVM mode. Related: #2321.
