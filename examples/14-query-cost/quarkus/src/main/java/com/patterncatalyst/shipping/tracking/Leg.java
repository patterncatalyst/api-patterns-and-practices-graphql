package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Ignore;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

/**
 * One hop of an itinerary. The routing service returns the voyage number and
 * the two UN/LOCODEs; {@code voyage}, {@code loadLocation} and
 * {@code unloadLocation} are resolved from the voyage and location sources by
 * {@link TrackingApi}, so those three components are kept out of the schema.
 */
@Type("Leg")
@Description("One hop of an itinerary on a single voyage.")
public record Leg(
        @Ignore String voyageNumber,
        @Ignore String loadUnLocode,
        @Ignore String unloadUnLocode,
        @NonNull @Description("When the cargo is loaded.") Instant loadTime,
        @NonNull @Description("When the cargo is unloaded.") Instant unloadTime) {}
