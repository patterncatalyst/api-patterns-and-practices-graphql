package com.patterncatalyst.shipping.tracking;

import static graphql.util.TreeTransformerUtil.changeNode;

import com.apollographql.federation.graphqljava.printer.ServiceSDLPrinter;
import graphql.GraphQL;
import graphql.schema.DataFetcher;
import graphql.schema.FieldCoordinates;
import graphql.schema.GraphQLCodeRegistry;
import graphql.schema.GraphQLDirective;
import graphql.schema.GraphQLFieldDefinition;
import graphql.schema.GraphQLInputObjectField;
import graphql.schema.GraphQLInterfaceType;
import graphql.schema.GraphQLNamedType;
import graphql.schema.GraphQLObjectType;
import graphql.schema.GraphQLScalarType;
import graphql.schema.GraphQLSchema;
import graphql.schema.GraphQLSchemaElement;
import graphql.schema.GraphQLTypeUtil;
import graphql.schema.GraphQLTypeVisitorStub;
import graphql.schema.GraphQLUnionType;
import graphql.schema.SchemaTransformer;
import graphql.schema.TypeResolver;
import graphql.util.TraversalControl;
import graphql.util.TraverserContext;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;

/**
 * Applies the details of the canonical SDL to the generated schema:
 *
 * <ul>
 *   <li>the descriptions of the {@code Query} and {@code Mutation} root types,
 *       as the contract words them;
 *   <li>the {@code @specifiedBy} URL of the {@code UnLocode} and {@code DateTime}
 *       scalars, set with graphql-java's {@code specifiedByUrl};
 *   <li>the description of the built-in {@code DateTime} scalar, in the contract's
 *       RFC 3339 wording;
 *   <li>the field descriptions of date-typed fields, which carry the contract's
 *       text without the generated " (ISO-8601)" suffix;
 *   <li>deprecation reasons: the reason given to
 *       {@code @io.smallrye.graphql.api.Deprecated} is applied with graphql-java's
 *       {@code deprecate(reason)}.
 * </ul>
 *
 * SmallRye completes the federated schema (the {@code _service} and
 * {@code _entities} fields and the {@code _Entity} union) and then fires the
 * graphql-java {@code GraphQL.Builder} as a CDI event (enabled by
 * {@code quarkus.smallrye-graphql.events.enabled=true}); this observer applies
 * all of it to that schema with graphql-java's {@link SchemaTransformer} and
 * hands the result back to the builder.
 */
@ApplicationScoped
public class ContractSchemaDetails {

    private static final String QUERY_DESCRIPTION =
            "The tracking view: read-oriented aggregation of cargo, routing and handling data.";
    private static final String MUTATION_DESCRIPTION =
            "The write surface; deliberately small because writes belong to the owning services.";
    private static final String UN_LOCODE_SPECIFIED_BY = "https://unece.org/trade/uncefact/unlocode";
    private static final String DATE_TIME_DESCRIPTION =
            "An RFC 3339 date-time in UTC, for example `2026-10-15T09:30:00Z`.";
    private static final String DATE_TIME_SPECIFIED_BY = "https://www.rfc-editor.org/rfc/rfc3339";
    private static final String ISO_SUFFIX = " (ISO-8601)";

    void applyContractDetails(@Observes GraphQL.Builder builder) {
        GraphQLSchema federated = builder.build().getGraphQLSchema();
        GraphQLSchema schema = SchemaTransformer.transformSchema(federated, new GraphQLTypeVisitorStub() {
            @Override
            public TraversalControl visitGraphQLObjectType(
                    GraphQLObjectType node, TraverserContext<GraphQLSchemaElement> context) {
                return switch (node.getName()) {
                    case "Query" -> changeNode(context, node.transform(type -> type.description(QUERY_DESCRIPTION)));
                    case "Mutation" -> changeNode(
                            context, node.transform(type -> type.description(MUTATION_DESCRIPTION)));
                    default -> TraversalControl.CONTINUE;
                };
            }

            @Override
            public TraversalControl visitGraphQLFieldDefinition(
                    GraphQLFieldDefinition node, TraverserContext<GraphQLSchemaElement> context) {
                String description = node.getDescription();
                boolean dateField = "DateTime".equals(GraphQLTypeUtil.unwrapAll(node.getType()).getName());
                boolean stripSuffix = dateField && description != null && description.endsWith(ISO_SUFFIX);
                String reason = annotatedDeprecationReason(node);
                if (!stripSuffix && reason == null) {
                    return TraversalControl.CONTINUE;
                }
                return changeNode(context, node.transform(field -> {
                    if (stripSuffix) {
                        field.description(description.substring(0, description.length() - ISO_SUFFIX.length()));
                    }
                    if (reason != null) {
                        field.deprecate(reason);
                    }
                }));
            }

            @Override
            public TraversalControl visitGraphQLInputObjectField(
                    GraphQLInputObjectField node, TraverserContext<GraphQLSchemaElement> context) {
                String description = node.getDescription();
                boolean dateField = "DateTime".equals(GraphQLTypeUtil.unwrapAll(node.getType()).getName());
                return dateField && description != null && description.endsWith(ISO_SUFFIX)
                        ? changeNode(
                                context,
                                node.transform(field -> field.description(
                                        description.substring(0, description.length() - ISO_SUFFIX.length()))))
                        : TraversalControl.CONTINUE;
            }

            @Override
            public TraversalControl visitGraphQLScalarType(
                    GraphQLScalarType node, TraverserContext<GraphQLSchemaElement> context) {
                return switch (node.getName()) {
                    case "UnLocode" -> changeNode(context, node.transform(scalar -> scalar.specifiedByUrl(UN_LOCODE_SPECIFIED_BY)));
                    case "DateTime" -> changeNode(
                            context,
                            node.transform(scalar -> scalar.description(DATE_TIME_DESCRIPTION)
                                    .specifiedByUrl(DATE_TIME_SPECIFIED_BY)));
                    default -> TraversalControl.CONTINUE;
                };
            }
        });
        builder.schema(withCurrentTypes(schema));
    }

    /**
     * The reason given to {@code @io.smallrye.graphql.api.Deprecated}, or null
     * when the field has no such annotation or is already deprecated. SmallRye records the
     * annotation as a {@code deprecated} directive on the field; the reason is
     * applied to the field with graphql-java's {@code deprecate(reason)}.
     */
    private static String annotatedDeprecationReason(GraphQLFieldDefinition field) {
        GraphQLDirective deprecated = field.getDirective("deprecated");
        if (deprecated == null || field.isDeprecated()) {
            return null;
        }
        return (String) deprecated.getArgument("reason").getArgumentValue().getValue();
    }

    /**
     * Rebuilds the transformed schema with a code registry that stays in step
     * with it. Each interface and union resolver is wrapped to look the object
     * type up by name in the schema being executed, so a fragment such as
     * {@code ... on Location} matches the transformed implementers of
     * {@code Node} and the members of {@code _Entity}. The {@code _service { sdl }}
     * field answers with the federation SDL of the transformed schema, the
     * text a composer reads.
     */
    private static GraphQLSchema withCurrentTypes(GraphQLSchema schema) {
        GraphQLCodeRegistry.Builder registry = GraphQLCodeRegistry.newCodeRegistry(schema.getCodeRegistry());
        for (GraphQLNamedType type : schema.getAllTypesAsList()) {
            TypeResolver smallRye = null;
            if (type instanceof GraphQLInterfaceType iface) {
                smallRye = schema.getCodeRegistry().getTypeResolver(iface);
            } else if (type instanceof GraphQLUnionType union) {
                smallRye = schema.getCodeRegistry().getTypeResolver(union);
            }
            if (smallRye != null) {
                TypeResolver current = smallRye;
                registry.typeResolver(
                        type.getName(),
                        env -> env.getSchema().getObjectType(current.getType(env).getName()));
            }
        }
        String federationSdl = serviceSdl(schema);
        registry.dataFetcher(FieldCoordinates.coordinates("_Service", "sdl"), (DataFetcher<String>) env -> federationSdl);
        return GraphQLSchema.newSchema(schema).codeRegistry(registry.build()).build();
    }

    /**
     * The federation SDL a composer reads: the federation printer's SDL of the
     * subgraph's types and directives, which opens with the schema-level
     * {@code @link} that declares Federation 2.7, with each scalar's
     * {@code @specifiedBy} URL added from the schema, so the gateway composes
     * Federation 2 and keeps {@code specifiedByURL}. A missing target throws an
     * IllegalStateException when the schema is built, and {@code verify.sh} fails
     * on the subgraph's SDL.
     */
    private static String serviceSdl(GraphQLSchema schema) {
        String sdl = ServiceSDLPrinter.generateServiceSDLV2(schema);
        if (!sdl.startsWith("schema @link(")) {
            throw new IllegalStateException("the federation SDL has no schema-level @link");
        }
        for (GraphQLNamedType type : schema.getAllTypesAsList()) {
            if (type instanceof GraphQLScalarType scalar && scalar.getSpecifiedByUrl() != null) {
                if (!sdl.contains("\nscalar " + scalar.getName() + "\n")) {
                    throw new IllegalStateException("the federation SDL has no scalar " + scalar.getName());
                }
                sdl = sdl.replace(
                        "\nscalar " + scalar.getName() + "\n",
                        "\nscalar " + scalar.getName() + " @specifiedBy(url: \"" + scalar.getSpecifiedByUrl() + "\")\n");
            }
        }
        return sdl;
    }
}
