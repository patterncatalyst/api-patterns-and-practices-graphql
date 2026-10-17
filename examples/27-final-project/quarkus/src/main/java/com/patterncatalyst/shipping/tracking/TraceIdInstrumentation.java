package com.patterncatalyst.shipping.tracking;

import graphql.ExceptionWhileDataFetching;
import graphql.ExecutionResult;
import graphql.GraphQLError;
import graphql.GraphqlErrorBuilder;
import graphql.execution.instrumentation.InstrumentationState;
import graphql.execution.instrumentation.SimplePerformantInstrumentation;
import graphql.execution.instrumentation.parameters.InstrumentationExecutionParameters;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanContext;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

/**
 * extensions.traceId on the execution errors the engine raises itself: a null in a
 * non-null position. An error raised by a resolver reaches the client through
 * SmallRye's error serialization, where {@link TraceIdExtensionProvider} adds the
 * same key; this instrumentation covers the rest, so every execution error of a
 * response (an error with a path) carries the trace id of its request. A request
 * error, which has no path, is left as the engine wrote it. It runs as the last
 * step of the instrumentation chain, on the finished result.
 */
final class TraceIdInstrumentation extends SimplePerformantInstrumentation {

    static final String KEY = "traceId";

    @Override
    public CompletableFuture<ExecutionResult> instrumentExecutionResult(
            ExecutionResult result, InstrumentationExecutionParameters parameters, InstrumentationState state) {
        SpanContext context = Span.current().getSpanContext();
        if (!context.isValid() || result.getErrors().isEmpty()) {
            return super.instrumentExecutionResult(result, parameters, state);
        }
        List<GraphQLError> errors = result.getErrors().stream()
                .map(error -> error instanceof ExceptionWhileDataFetching || error.getPath() == null
                        ? error
                        : withTraceId(error, context.getTraceId()))
                .toList();
        return CompletableFuture.completedFuture(result.transform(builder -> builder.errors(errors)));
    }

    /** A copy of the error whose extensions are its serialized extensions plus the trace id. */
    @SuppressWarnings("unchecked")
    private static GraphQLError withTraceId(GraphQLError error, String traceId) {
        Map<String, Object> extensions = new LinkedHashMap<>();
        Object serialized = error.toSpecification().get("extensions");
        if (serialized instanceof Map<?, ?> existing) {
            extensions.putAll((Map<String, Object>) existing);
        }
        extensions.put(KEY, traceId);
        return GraphqlErrorBuilder.newError()
                .message(error.getMessage())
                .locations(error.getLocations())
                .path(error.getPath())
                .errorType(error.getErrorType())
                .extensions(extensions)
                .build();
    }
}
