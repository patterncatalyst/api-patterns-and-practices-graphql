package com.patterncatalyst.shipping.tracking;

import static graphql.util.TreeTransformerUtil.changeNode;

import graphql.schema.GraphQLObjectType;
import graphql.schema.GraphQLScalarType;
import graphql.schema.GraphQLSchema;
import graphql.schema.GraphQLSchemaElement;
import graphql.schema.GraphQLTypeVisitorStub;
import graphql.schema.SchemaTransformer;
import graphql.util.TraversalControl;
import graphql.util.TraverserContext;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;

/**
 * Two details of the canonical SDL that this observer sets on the schema: the
 * description of the {@code Query} root type (SmallRye's default is "Query
 * root") and the {@code @specifiedBy} URL of the {@code UnLocode} scalar.
 * SmallRye fires the
 * graphql-java schema builder as a CDI event just before it builds the schema
 * (enabled by {@code quarkus.smallrye-graphql.events.enabled=true}); this
 * observer sets both with graphql-java's {@link SchemaTransformer}.
 */
@ApplicationScoped
public class ContractSchemaDetails {

    private static final String QUERY_DESCRIPTION =
            "The tracking view: read-oriented aggregation of cargo, routing and handling data.";
    private static final String UN_LOCODE_SPECIFIED_BY = "https://unece.org/trade/uncefact/unlocode";

    void applyContractDetails(@Observes GraphQLSchema.Builder builder) {
        GraphQLSchema schema = SchemaTransformer.transformSchema(builder.build(), new GraphQLTypeVisitorStub() {
            @Override
            public TraversalControl visitGraphQLObjectType(
                    GraphQLObjectType node, TraverserContext<GraphQLSchemaElement> context) {
                return "Query".equals(node.getName())
                        ? changeNode(context, node.transform(type -> type.description(QUERY_DESCRIPTION)))
                        : TraversalControl.CONTINUE;
            }

            @Override
            public TraversalControl visitGraphQLScalarType(
                    GraphQLScalarType node, TraverserContext<GraphQLSchemaElement> context) {
                return "UnLocode".equals(node.getName())
                        ? changeNode(context, node.transform(scalar -> scalar.specifiedByUrl(UN_LOCODE_SPECIFIED_BY)))
                        : TraversalControl.CONTINUE;
            }
        });
        // SmallRye keeps building from the builder it fired, so write the
        // transformed types back into it rather than returning a new one.
        builder.query(schema.getQueryType())
                .clearAdditionalTypes()
                .additionalTypes(schema.getAdditionalTypes())
                .codeRegistry(schema.getCodeRegistry());
    }
}
