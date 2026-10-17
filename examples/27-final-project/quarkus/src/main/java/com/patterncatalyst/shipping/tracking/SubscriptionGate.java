package com.patterncatalyst.shipping.tracking;

import java.util.List;

import graphql.GraphQL;
import graphql.execution.instrumentation.ChainedInstrumentation;
import graphql.execution.instrumentation.Instrumentation;
import graphql.execution.instrumentation.InstrumentationState;
import graphql.execution.instrumentation.SimplePerformantInstrumentation;
import graphql.execution.instrumentation.parameters.InstrumentationFieldFetchParameters;
import graphql.schema.DataFetcher;
import graphql.schema.DataFetchingEnvironment;
import graphql.schema.GraphQLTypeUtil;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;

/**
 * Admits a client to {@code Subscription.cargoHandled} before the first event.
 *
 * <p>Chapter 18's operation and object rules apply once, when the subscription
 * starts: the caller must be signed in, and must be allowed to see the cargo it
 * asks to watch. A refusal raised here happens while the engine creates the
 * event stream, so the client receives an error message that names the code
 * ({@code UNAUTHENTICATED} or {@code FORBIDDEN}) and no event ever follows. The
 * gate is installed in the same {@code GraphQL.Builder} chain as the cost limits
 * of Chapter 14 and the loaders of Chapter 21.
 *
 * <p>The identity is the subscribing request's: the gate runs on the upgrade
 * request's thread, before any event exists. Field authorization for the events
 * themselves is {@link SubscriberIdentity}'s.
 */
@ApplicationScoped
public class SubscriptionGate {

    private final Viewers viewers;
    private final BookingSource booking;

    SubscriptionGate(Viewers viewers, BookingSource booking) {
        this.viewers = viewers;
        this.booking = booking;
    }

    void install(@Observes GraphQL.Builder builder) {
        Instrumentation smallrye = builder.build().getInstrumentation();
        builder.instrumentation(new ChainedInstrumentation(List.of(smallrye, new Admission())));
    }

    private final class Admission extends SimplePerformantInstrumentation {
        @Override
        public DataFetcher<?> instrumentDataFetcher(
                DataFetcher<?> fetcher, InstrumentationFieldFetchParameters parameters, InstrumentationState state) {
            DataFetchingEnvironment environment = parameters.getEnvironment();
            boolean cargoHandled = "Subscription".equals(GraphQLTypeUtil.simplePrint(environment.getParentType()))
                    && "cargoHandled".equals(environment.getFieldDefinition().getName());
            if (!cargoHandled) {
                return fetcher;
            }
            return env -> {
                admit(env.<TrackingId>getArgument("trackingId"));
                return fetcher.get(env);
            };
        }
    }

    private void admit(TrackingId trackingId) {
        Viewer viewer = viewers.current();
        if (viewer == Viewer.ANONYMOUS) {
            throw new AuthenticationRequiredException();
        }
        if (!booking.mayWatch(trackingId.value(), viewer)) {
            throw new WatchNotPermittedException();
        }
    }
}
