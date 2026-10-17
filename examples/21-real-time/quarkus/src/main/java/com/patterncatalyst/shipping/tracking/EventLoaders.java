package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.dataloader.DataLoader;

import graphql.ExecutionResult;
import graphql.GraphQL;
import graphql.execution.instrumentation.ChainedInstrumentation;
import graphql.execution.instrumentation.Instrumentation;
import graphql.execution.instrumentation.InstrumentationContext;
import graphql.execution.instrumentation.InstrumentationState;
import graphql.execution.instrumentation.SimplePerformantInstrumentation;
import graphql.execution.instrumentation.parameters.InstrumentationFieldParameters;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;

/**
 * Gives each subscription event the loaders a request gets.
 *
 * <p>A subscription is one execution that outlives its events, and the
 * DataLoaders {@code @Source} batch resolvers use belong to the execution. Their
 * caches are keyed by the parent object, so a {@code Cargo} that two events
 * share would be answered from the first event's reads. graphql-java calls
 * {@code beginSubscribedFieldEvent} before it executes the selection set for
 * each event; this instrumentation empties every loader there, so each event
 * reads the sources afresh. It is installed after SmallRye's own
 * instrumentation, in one {@code ChainedInstrumentation}, through the
 * {@code GraphQL.Builder} event, the seam the cost limits of Chapter 14 use.
 */
@ApplicationScoped
public class EventLoaders {

    void clearLoadersPerEvent(@Observes GraphQL.Builder builder) {
        Instrumentation smallrye = builder.build().getInstrumentation();
        builder.instrumentation(new ChainedInstrumentation(List.of(smallrye, new ClearLoaders())));
    }

    static final class ClearLoaders extends SimplePerformantInstrumentation {
        @Override
        public InstrumentationContext<ExecutionResult> beginSubscribedFieldEvent(
                InstrumentationFieldParameters parameters, InstrumentationState state) {
            parameters.getExecutionContext().getDataLoaderRegistry().getDataLoaders().forEach(DataLoader::clearAll);
            return super.beginSubscribedFieldEvent(parameters, state);
        }
    }
}
