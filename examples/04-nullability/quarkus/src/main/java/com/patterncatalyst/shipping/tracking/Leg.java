package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Ignore;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

/**
 * One hop of an itinerary. The leg stores the keys of the things it refers to
 * ({@code voyageNumber}, {@code loadUnLocode}, {@code unloadUnLocode}) and
 * none of them is a GraphQL field. {@code voyage}, {@code loadLocation} and
 * {@code unloadLocation} are resolvers in {@link TrackingApi} that call the
 * voyage and location sources.
 */
@Type("Leg")
@Description("One hop of an itinerary on a single voyage.")
public record Leg(
        @Ignore String voyageNumber,
        @Ignore String loadUnLocode,
        @Ignore String unloadUnLocode,
        @NonNull @Description("When the cargo is loaded.") Instant loadTime,
        @NonNull @Description("When the cargo is unloaded.") Instant unloadTime) {}
