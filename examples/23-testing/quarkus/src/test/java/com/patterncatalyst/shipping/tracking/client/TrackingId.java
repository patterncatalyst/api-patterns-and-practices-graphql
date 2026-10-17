package com.patterncatalyst.shipping.tracking.client;

import org.eclipse.microprofile.graphql.Name;

/**
 * The contract's {@code TrackingId} scalar as the client sees it. The typesafe client
 * treats a class with a static {@code of(String)} factory as a scalar, and {@code @Name}
 * is the type name a variable is declared with.
 */
@Name("TrackingId")
public record TrackingId(String value) {

    public static TrackingId of(String value) {
        return new TrackingId(value);
    }

    @Override
    public String toString() {
        return value;
    }
}
