package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;

import io.smallrye.graphql.api.CustomScalar;
import io.smallrye.graphql.api.CustomStringScalar;

/**
 * The {@code TrackingId} custom scalar. SmallRye GraphQL maps any class annotated
 * with {@code @CustomScalar} that implements {@code CustomStringScalar} to a
 * GraphQL scalar of that name: it serializes through
 * {@link #stringValueForSerialization()} and parses input through the
 * {@code String} constructor.
 */
@CustomScalar("TrackingId")
@Description("""
        A cargo tracking identifier issued at booking time, for example `ABC123`.
        Opaque to clients; compare for equality only.""")
public record TrackingId(String value) implements CustomStringScalar {

    @Override
    public String stringValueForSerialization() {
        return value;
    }
}
