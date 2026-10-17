package com.patterncatalyst.shipping.tracking;

import graphql.introspection.Introspection;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Turns introspection off for the whole JVM when {@code tracking.introspection.enabled} is false.
 *
 * <p>This is graphql-java's documented switch, {@link Introspection#enabledJvmWide(boolean)}. It
 * refuses the root fields {@code __schema} and {@code __type}, so a real and an unknown type name
 * are answered identically.
 *
 * <p>Each instance runs in its own JVM, so the flag applies per instance: the public one sets
 * {@code TRACKING_INTROSPECTION_ENABLED=false}, the internal one leaves the default.
 */
@ApplicationScoped
public class IntrospectionSwitch {

    @ConfigProperty(name = "tracking.introspection.enabled", defaultValue = "true")
    boolean enabled;

    void onStart(@Observes StartupEvent event) {
        if (!enabled) {
            Introspection.enabledJvmWide(false);
        }
    }
}
