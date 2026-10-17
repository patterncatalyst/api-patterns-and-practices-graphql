### Describe the bug

A field or query annotated with `@io.smallrye.graphql.api.Deprecated(reason = "…")` (or with `@java.lang.Deprecated`) appears with `@deprecated` in the printed schema. Introspection still reports `isDeprecated: false` and `deprecationReason: null`, and `fields` without `includeDeprecated` still lists the field. So clients and tools that read introspection, such as GraphiQL, codegen or schema registries, never see the deprecation.

The cause looks like this:
- `Bootstrap` attaches the annotation as a generic `GraphQLDirective` through `withDirective(...)`.
- graphql-java's `GraphQLFieldDefinition.isDeprecated()` is `deprecationReason != null`, and that field is set only by `GraphQLFieldDefinition.Builder.deprecate(reason)`.
- `deprecate(...)` is never called anywhere in `server/` or `common/`, and no test asserts `isDeprecated`.

### Reproducer

Runnable project: [deprecated-introspection](https://github.com/patterncatalyst/smallrye-graphql-reproducers/tree/main/deprecated-introspection) in https://github.com/patterncatalyst/smallrye-graphql-reproducers. Its `@QuarkusTest` asserts the expected behaviour, so it fails until this is fixed:

```console
git clone https://github.com/patterncatalyst/smallrye-graphql-reproducers.git && cd smallrye-graphql-reproducers
mvn clean verify -pl deprecated-introspection                                            # Quarkus 3.40.1 / SmallRye 2.18.5
mvn clean verify -pl deprecated-introspection -Dquarkus.platform.version=4.0.0.Beta1     # SmallRye 3.0.0.Beta7
mvn clean verify -pl deprecated-introspection -Dquarkus.platform.version=4.0.0.Beta1 -Dsmallrye-graphql.version=3.0.0.Beta-SNAPSHOT   # local main
```

Result on all three: Tests run: 5, Failures: 4 (every introspection assertion); the printed-schema test passes.

The same code inline:
Quarkus 3.40.1 with `quarkus-smallrye-graphql` only, and this single class:

```java
package org.acme;

import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Query;
import org.eclipse.microprofile.graphql.Type;

@GraphQLApi
public class Api {

    @Type("Item")
    public record Item(
            String current,
            @io.smallrye.graphql.api.Deprecated(reason = "Use `current`.") String withSmallRye,
            @java.lang.Deprecated String withJavaLang) {}

    @Query
    public Item item() {
        return new Item("a", "b", "c");
    }

    @Query
    @io.smallrye.graphql.api.Deprecated(reason = "Use `item`.")
    public Item oldItem() {
        return item();
    }
}
```

Introspection:

```console
{ __type(name:"Item"){ fields(includeDeprecated:true){ name isDeprecated deprecationReason } } }
{"data":{"__type":{"fields":[{"name":"current","isDeprecated":false,"deprecationReason":null},{"name":"withSmallRye","isDeprecated":false,"deprecationReason":null},{"name":"withJavaLang","isDeprecated":false,"deprecationReason":null}]}}}

{ __type(name:"Item"){ fields { name } } }
{"data":{"__type":{"fields":[{"name":"current"},{"name":"withSmallRye"},{"name":"withJavaLang"}]}}}

{ __schema{ queryType{ fields(includeDeprecated:true){ name isDeprecated deprecationReason } } } }
{"data":{"__schema":{"queryType":{"fields":[{"name":"item","isDeprecated":false,"deprecationReason":null},{"name":"oldItem","isDeprecated":false,"deprecationReason":null}]}}}}
```

The printed schema, `/graphql/schema.graphql` with `quarkus.smallrye-graphql.schema-include-directives=true`, claims the opposite:

```graphql
directive @deprecated(reason: String) on FIELD_DEFINITION | ARGUMENT_DEFINITION | ENUM_VALUE | INPUT_FIELD_DEFINITION

  withJavaLang: String @deprecated
  withSmallRye: String @deprecated(reason : "Use `current`.")
  oldItem: Item @deprecated(reason : "Use `item`.")
```

### Expected behavior

- `withSmallRye` and `oldItem` report `isDeprecated: true` with their reasons.
- `withJavaLang` reports `isDeprecated: true`, with the spec's default reason or `null`.
- Deprecated fields are left out of `fields` when `includeDeprecated` is `false`, which is the default.

A related point: SmallRye registers its own `@deprecated` definition (`reason: String`, no default) in place of the spec's built-in `directive @deprecated(reason: String! = "No longer supported")`.

### Suggested fix

When `Bootstrap` applies the deprecation, call `deprecate(reason)` on the graphql-java builder, falling back to the spec default `"No longer supported"` when there is no reason. Do this for field definitions, arguments, input fields and enum values, and let graphql-java's built-in `@deprecated` definition stand.

### Workaround

In an `@Observes GraphQLSchema.Builder` method, rebuild each affected field with `field.transform(b -> b.deprecate(reason))`, taking the reason from the annotation.

### Environment

The same output was reproduced on:

| Quarkus | SmallRye GraphQL | graphql-java |
|---|---|---|
| 3.40.1 | 2.18.5 | 25.0 |
| 4.0.0.Beta1 | 3.0.0.Beta7 (BOM-managed) | 26.0 |
| 4.0.0.Beta1 | `main` at 8a13b16, built locally as `3.0.0.Beta-SNAPSHOT` (3 commits ahead of `3.0.0.Beta8`) | 26.0 |

Also: OpenJDK 25.0.3, Fedora 44, JVM mode.
