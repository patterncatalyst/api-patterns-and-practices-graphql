package com.patterncatalyst.shipping.tracking;

import graphql.ErrorType;
import graphql.ExceptionWhileDataFetching;
import graphql.ExecutionResult;
import graphql.GraphQL;
import graphql.GraphQLError;
import graphql.analysis.QueryTraverser;
import graphql.analysis.QueryVisitorFieldEnvironment;
import graphql.analysis.QueryVisitorStub;
import graphql.execution.ExecutionContext;
import graphql.execution.instrumentation.ChainedInstrumentation;
import graphql.execution.instrumentation.Instrumentation;
import graphql.execution.instrumentation.InstrumentationContext;
import graphql.execution.instrumentation.InstrumentationState;
import graphql.execution.instrumentation.SimplePerformantInstrumentation;
import graphql.execution.instrumentation.parameters.InstrumentationCreateStateParameters;
import graphql.execution.instrumentation.parameters.InstrumentationExecuteOperationParameters;
import graphql.execution.instrumentation.parameters.InstrumentationExecutionParameters;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.metrics.LongCounter;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.instrumentation.graphql.v20_0.GraphQLTelemetry;
import io.quarkus.vertx.http.runtime.CurrentVertxRequest;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CompletableFuture;

/**
 * Wires OpenTelemetry into the GraphQL engine.
 *
 * <p>SmallRye builds its instrumentation chain and then fires {@code GraphQL.Builder}
 * as a CDI event (enabled by {@code quarkus.smallrye-graphql.events.enabled=true}),
 * the same seam the cost budget of Chapter 14 uses. The observer reads the chain from
 * a throwaway {@code build()} and appends two instrumentations:
 *
 * <ol>
 *   <li>the OpenTelemetry project's graphql-java instrumentation, which opens the
 *       operation span and one span per data fetcher that does real work. SmallRye's
 *       own operation span is off ({@code quarkus.smallrye-graphql.tracing.enabled=false}),
 *       so each request has exactly one;
 *   <li>{@link TrackingInstrumentation}, which records the two metrics a span cannot
 *       give: {@code graphql.errors} by {@code extensions.code} and
 *       {@code graphql.field.deprecated.usage} by field coordinate, operation and client.
 * </ol>
 */
@ApplicationScoped
public class Telemetry {

    static final AttributeKey<String> OPERATION_NAME = AttributeKey.stringKey("graphql.operation.name");
    static final AttributeKey<String> ERROR_CODE = AttributeKey.stringKey("error.code");
    static final AttributeKey<String> FIELD_COORDINATE = AttributeKey.stringKey("graphql.field.coordinate");
    static final AttributeKey<String> CLIENT_NAME = AttributeKey.stringKey("client.name");

    private final OpenTelemetry openTelemetry;
    private final TrackingInstrumentation tracking;

    Telemetry(OpenTelemetry openTelemetry, Meter meter, CurrentVertxRequest request) {
        this.openTelemetry = openTelemetry;
        this.tracking = new TrackingInstrumentation(
                meter.counterBuilder("graphql.errors")
                        .setDescription("Errors in GraphQL responses, by extensions.code and operation name.")
                        .setUnit("{error}")
                        .build(),
                meter.counterBuilder("graphql.field.deprecated.usage")
                        .setDescription("Requests that select a deprecated field, by field coordinate, operation name and client.")
                        .setUnit("{request}")
                        .build(),
                request);
    }

    void instrument(@Observes GraphQL.Builder builder) {
        Instrumentation smallrye = builder.build().getInstrumentation();
        Instrumentation spans = GraphQLTelemetry.builder(openTelemetry)
                .setDataFetcherInstrumentationEnabled(true)
                .setQuerySanitizationEnabled(true)
                .setOperationNameInSpanNameEnabled(true)
                .build()
                .createInstrumentation();
        builder.instrumentation(new ChainedInstrumentation(List.of(smallrye, spans, tracking)));
    }

    /** What one request carries between the instrumentation callbacks: the calling client. */
    record RequestState(String client) implements InstrumentationState {}

    static final class TrackingInstrumentation extends SimplePerformantInstrumentation {

        private static final String UNKNOWN_CLIENT = "unknown";
        private static final String CLIENT_HEADER = "X-Client-Name";

        private final LongCounter errors;
        private final LongCounter deprecatedUsage;
        private final CurrentVertxRequest request;

        TrackingInstrumentation(LongCounter errors, LongCounter deprecatedUsage, CurrentVertxRequest request) {
            this.errors = errors;
            this.deprecatedUsage = deprecatedUsage;
            this.request = request;
        }

        @Override
        public CompletableFuture<InstrumentationState> createStateAsync(InstrumentationCreateStateParameters parameters) {
            // The state is created on the request's own thread, where the HTTP request is current.
            return CompletableFuture.completedFuture(new RequestState(clientName()));
        }

        @Override
        public InstrumentationContext<ExecutionResult> beginExecuteOperation(
                InstrumentationExecuteOperationParameters parameters, InstrumentationState state) {
            ExecutionContext execution = parameters.getExecutionContext();
            String operation = operationName(execution.getOperationDefinition().getName());
            String client = ((RequestState) state).client();
            Set<String> coordinates = new HashSet<>();
            QueryTraverser.newQueryTraverser()
                    .schema(execution.getGraphQLSchema())
                    .document(execution.getDocument())
                    .operationName(execution.getOperationDefinition().getName())
                    .coercedVariables(execution.getCoercedVariables())
                    .build()
                    .visitPreOrder(new DeprecatedFields(coordinates));
            for (String coordinate : coordinates) {
                deprecatedUsage.add(1, Attributes.of(
                        FIELD_COORDINATE, coordinate, OPERATION_NAME, operation, CLIENT_NAME, client));
            }
            return super.beginExecuteOperation(parameters, state);
        }

        @Override
        public CompletableFuture<ExecutionResult> instrumentExecutionResult(
                ExecutionResult result, InstrumentationExecutionParameters parameters, InstrumentationState state) {
            String operation = operationName(parameters.getOperation());
            for (GraphQLError error : result.getErrors()) {
                // a document that does not validate never executes; the counter counts executed operations
                if (error.getErrorType() == ErrorType.ValidationError || error.getErrorType() == ErrorType.InvalidSyntax) {
                    continue;
                }
                errors.add(1, Attributes.of(ERROR_CODE, errorCode(error), OPERATION_NAME, operation));
            }
            return super.instrumentExecutionResult(result, parameters, state);
        }

        private String clientName() {
            var current = request.getCurrent();
            String header = current == null ? null : current.request().getHeader(CLIENT_HEADER);
            return header == null || header.isBlank() ? UNKNOWN_CLIENT : header;
        }

        private static String operationName(String name) {
            return name == null || name.isBlank() ? "anonymous" : name;
        }

        private static String errorCode(GraphQLError error) {
            // The response gets its extensions.code from DeclaredErrorCodeProvider when SmallRye
            // writes the error; the metric asks the same provider about the exception behind it.
            String code = error instanceof ExceptionWhileDataFetching failed
                    ? DeclaredErrorCodeProvider.codeOf(failed.getException())
                    : null;
            return code == null ? "unclassified" : code;
        }
    }

    /** Collects {@code Type.field} for every deprecated field the operation selects. */
    private static final class DeprecatedFields extends QueryVisitorStub {
        private final Set<String> coordinates;

        DeprecatedFields(Set<String> coordinates) {
            this.coordinates = coordinates;
        }

        @Override
        public void visitField(QueryVisitorFieldEnvironment environment) {
            if (!environment.isTypeNameIntrospectionField() && environment.getFieldDefinition().isDeprecated()) {
                coordinates.add(environment.getFieldsContainer().getName() + "." + environment.getFieldDefinition().getName());
            }
        }
    }
}
