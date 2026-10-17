package com.patterncatalyst.shipping.tracking;

import static graphql.util.TreeTransformerUtil.changeNode;

import graphql.Scalars;
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
import graphql.schema.GraphQLInputType;
import graphql.schema.GraphQLList;
import graphql.schema.GraphQLNonNull;
import graphql.schema.GraphQLTypeUtil;
import graphql.schema.GraphQLTypeVisitorStub;
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
 *   <li>the {@code ids} argument of {@code Query.nodes}, typed {@code [ID!]!} as the
 *       contract declares it;
 *   <li>deprecation reasons: the reason given to
 *       {@code @io.smallrye.graphql.api.Deprecated} is applied with graphql-java's
 *       {@code deprecate(reason)}.
 * </ul>
 *
 * The graphql-java schema builder is fired as a CDI event just before it
 * builds the schema (enabled by {@code quarkus.smallrye-graphql.events.enabled=true});
 * this observer sets all of it with graphql-java's {@link SchemaTransformer}.
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
    private static final GraphQLInputType ID_LIST =
            GraphQLNonNull.nonNull(GraphQLList.list(GraphQLNonNull.nonNull(Scalars.GraphQLID)));

    void applyContractDetails(@Observes GraphQLSchema.Builder builder) {
        GraphQLSchema schema = SchemaTransformer.transformSchema(builder.build(), new GraphQLTypeVisitorStub() {
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
                if (context.getParentNode() instanceof GraphQLObjectType parent
                        && "Query".equals(parent.getName())
                        && "nodes".equals(node.getName())) {
                    return changeNode(context, node.transform(field -> field.replaceArguments(node.getArguments().stream()
                            .map(argument -> "ids".equals(argument.getName())
                                    ? argument.transform(builder -> builder.type(ID_LIST))
                                    : argument)
                            .toList())));
                }
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
                    case "UnLocode" -> changeNode(
                            context, node.transform(scalar -> scalar.specifiedByUrl(UN_LOCODE_SPECIFIED_BY)));
                    case "DateTime" -> changeNode(
                            context,
                            node.transform(scalar -> scalar.description(DATE_TIME_DESCRIPTION)
                                    .specifiedByUrl(DATE_TIME_SPECIFIED_BY)));
                    default -> TraversalControl.CONTINUE;
                };
            }
        });
        // SmallRye keeps building from the builder it fired, so write the
        // transformed types back into it rather than returning a new one.
        builder.query(schema.getQueryType())
                .mutation(schema.getMutationType())
                .clearAdditionalTypes()
                .additionalTypes(schema.getAdditionalTypes())
                .codeRegistry(withCurrentTypes(schema));
    }

    /**
     * The reason given to {@code @io.smallrye.graphql.api.Deprecated}, or null.
     * SmallRye 2.18.5 records the annotation as a {@code deprecated} directive
     * on the field. The reason is applied to the field with graphql-java's
     * {@code deprecate(reason)}, so introspection reports
     * {@code isDeprecated: true} with the reason.
     */
    private static String annotatedDeprecationReason(GraphQLFieldDefinition field) {
        GraphQLDirective deprecated = field.getDirective("deprecated");
        if (deprecated == null || field.isDeprecated()) {
            return null;
        }
        return (String) deprecated.getArgument("reason").getArgumentValue().getValue();
    }

    /**
     * graphql-java matches {@code ... on Location} against the schema's own
     * instance of the type. Each interface resolver is wrapped to look the type
     * up by name in the schema being executed, so a fragment on any implementer
     * of {@code Node} selects its fields.
     */
    private static GraphQLCodeRegistry withCurrentTypes(GraphQLSchema schema) {
        GraphQLCodeRegistry.Builder registry = GraphQLCodeRegistry.newCodeRegistry(schema.getCodeRegistry());
        for (GraphQLNamedType type : schema.getAllTypesAsList()) {
            if (type instanceof GraphQLInterfaceType iface) {
                TypeResolver smallRye = schema.getCodeRegistry().getTypeResolver(iface);
                registry.typeResolver(
                        iface.getName(),
                        env -> env.getSchema().getObjectType(smallRye.getType(env).getName()));
            }
        }
        return registry.build();
    }
}
