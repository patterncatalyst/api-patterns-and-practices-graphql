package com.patterncatalyst.shipping.tracking;

import java.util.concurrent.Flow;

import io.quarkus.arc.Arc;
import io.quarkus.arc.ManagedContext;
import io.quarkus.arc.InjectableContext.ContextState;
import io.quarkus.security.identity.CurrentIdentityAssociation;
import io.quarkus.security.identity.SecurityIdentity;
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.subscription.MultiSubscriber;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * Runs every event of a subscription under the identity of the client that subscribed.
 *
 * <p>{@link #scope} takes the subscriber's {@link SecurityIdentity} when the
 * subscription starts and delivers each event in a request context of its own that
 * holds it, then restores the context that was active before. Each event's selection
 * set therefore runs with the subscriber's identity: a {@code @RolesAllowed} check or
 * a {@link Viewers#current()} read answers for the subscriber, with the same
 * annotations and the same rule as a query.
 */
@ApplicationScoped
public class SubscriberIdentity {

    private final CurrentIdentityAssociation association;

    SubscriberIdentity(CurrentIdentityAssociation association) {
        this.association = association;
    }

    /** The events, each delivered under the identity current at this call. Call it from the subscription resolver. */
    public <T> Multi<T> scope(Multi<T> events) {
        SecurityIdentity subscriber = association.getIdentity();
        return Multi.createFrom().safePublisher(downstream -> events.subscribe().withSubscriber(new MultiSubscriber<T>() {
            @Override
            public void onSubscribe(Flow.Subscription subscription) {
                downstream.onSubscribe(subscription);
            }

            @Override
            public void onItem(T item) {
                // The event gets a request context of its own, holding the subscriber's identity. The
                // context propagates to the continuations that resume after a source's latency, so the
                // identity is still the subscriber's when a field further down the selection is resolved.
                ManagedContext requests = Arc.container().requestContext();
                ContextState registering = requests.isActive() ? requests.getState() : null;
                if (registering != null) {
                    requests.deactivate();
                }
                requests.activate();
                try {
                    association.setIdentity(subscriber);
                    downstream.onNext(item);
                } finally {
                    requests.deactivate();
                    if (registering != null) {
                        requests.activate(registering);
                    }
                }
            }

            @Override
            public void onFailure(Throwable failure) {
                downstream.onError(failure);
            }

            @Override
            public void onCompletion() {
                downstream.onComplete();
            }
        }));
    }
}
