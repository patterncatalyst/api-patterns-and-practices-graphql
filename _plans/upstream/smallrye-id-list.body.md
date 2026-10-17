### Describe the bug

A `@Query` argument declared as `@Id List<String>` is published as `[ID]` in the generated schema. Every request that passes a value for it then fails, whether the value is a literal or a variable:

```
argument 'ids' with value 'StringValue{value='a'}' is not a valid 'Unknown Scalar Type [java.util.List]'
```

A single `@Id String` argument works. The problem is specific to a collection or array of IDs.

The pattern is documented in SmallRye's own [federation guide](https://github.com/smallrye/smallrye-graphql/blob/main/docs/federation.md), `public List<Product> product(@Id List<String> id)`, so it looks like it is meant to work.

### Reproducer

Runnable project: [id-list-argument](https://github.com/patterncatalyst/smallrye-graphql-reproducers/tree/main/id-list-argument) in https://github.com/patterncatalyst/smallrye-graphql-reproducers. Its `@QuarkusTest` asserts the expected behaviour, so it fails until this is fixed:

```console
git clone https://github.com/patterncatalyst/smallrye-graphql-reproducers.git && cd smallrye-graphql-reproducers
mvn clean verify -pl id-list-argument                                            # Quarkus 3.40.1 / SmallRye 2.18.5
mvn clean verify -pl id-list-argument -Dquarkus.platform.version=4.0.0.Beta1     # SmallRye 3.0.0.Beta7
mvn clean verify -pl id-list-argument -Dquarkus.platform.version=4.0.0.Beta1 -Dsmallrye-graphql.version=3.0.0.Beta-SNAPSHOT   # local main
```

Result on all three: Tests run: 4, Failures: 2 (`listOfIdsAsLiteral`, `listOfIdsAsVariable`); the schema and single-`@Id` control tests pass.

The same code inline:
Quarkus 3.40.1 (`quarkus-smallrye-graphql`, no other extensions), with this as the only class:

```java
package org.acme;

import java.util.List;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.Query;

@GraphQLApi
public class Api {
    @Query
    public List<String> echoIds(@Id List<String> ids) {
        return ids;
    }

    @Query
    public String echoId(@Id String id) {
        return id;
    }
}
```

Generated schema (`/graphql/schema.graphql`), which looks correct:

```graphql
echoId(id: ID): String
echoIds(ids: [ID]): [String]
```

Requests:

```console
$ curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
    -d '{"query":"{ echoIds(ids: [\"a\", \"b\"]) }"}'
{"errors":[{"message":"argument 'ids' with value 'StringValue{value='a'}' is not a valid 'Unknown Scalar Type [java.util.List]'","locations":[{"line":1,"column":11}],"extensions":{"classification":"ValidationError"}}],"data":{"echoIds":null}}

$ curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
    -d '{"query":"query($ids:[ID]){ echoIds(ids: $ids) }","variables":{"ids":["a","b"]}}'
{"errors":[{"message":"argument 'ids' with value 'StringValue{value='a'}' is not a valid 'Unknown Scalar Type [java.util.List]'","locations":[{"line":1,"column":27}],"extensions":{"classification":"ValidationError"}}],"data":{"echoIds":null}}

$ curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
    -d '{"query":"{ echoId(id: \"a\") }"}'
{"data":{"echoId":"a"}}
```

### Expected behavior

`echoIds(ids: ["a", "b"])` returns `["a", "b"]`, as it does when the parameter is a plain `List<String>` (schema type `[String]`).

### Variants tried (all on the same versions)

| Declaration | Schema | Result |
|---|---|---|
| `@Id List<String>` | `[ID]` | fails as above |
| `@Id @NonNull List<@NonNull String>` | `[ID!]!` | fails as above |
| `@Id String[]` | `[ID]` | fails the same way, naming `[Ljava.lang.String;` |
| `@AdaptToScalar(Scalar.ID.class) List<String>` | n/a | NPE at startup (`Reference.getType()` is null) |
| `List<@Id String>` | n/a | does not compile: MicroProfile GraphQL 2.0 `@Id` has no `TYPE_USE` target |
| `@Id String` (control) | `ID` | works |

The failure also happens with no `SchemaTransformer` or `GraphQLSchema.Builder` observer in the application.

### Workaround

Declare the parameter as `List<@NonNull String>` and rewrite the argument type to `[ID!]!` in an `@Observes GraphQLSchema.Builder` method. Introspection and the schema export then both report `[ID!]!`, and ID-typed variables coerce correctly.

### Environment

Reproduced with the same class and requests, and identical output, on three combinations:

| Quarkus | SmallRye GraphQL | graphql-java |
|---|---|---|
| 3.40.1 | 2.18.5 | 25.0 |
| 4.0.0.Beta1 | 3.0.0.Beta7 (the version the 4.0.0.Beta1 BOM manages) | 26.0 |
| 4.0.0.Beta1 | `main` at 8a13b16, built locally as `3.0.0.Beta-SNAPSHOT` (3 commits ahead of `3.0.0.Beta8`) and pinned over the BOM | 26.0 |

Also: MicroProfile GraphQL API 2.0, OpenJDK 25.0.3, Fedora 44, JVM mode.
