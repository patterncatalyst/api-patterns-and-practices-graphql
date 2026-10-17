package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

/**
 * The derived delivery state. In this chapter the values are stored constants;
 * a primitive {@code boolean} is {@code Boolean!} without any annotation.
 */
@Type("Delivery")
@Description("The derived delivery state of a cargo.")
public record Delivery(
        @NonNull @Description("Current transport status.") TransportStatus transportStatus,
        @NonNull @Description("Whether the cargo follows its itinerary.") RoutingStatus routingStatus,
        @Description("True when the last handling event was off-itinerary.") boolean misdirected,
        @Description("Where the cargo was last handled. Null before the first handling event.")
                Location lastKnownLocation,
        @Description("The voyage the cargo is on. Null unless aboard a carrier.") Voyage currentVoyage,
        @Description("Estimated arrival. Null when the estimate is unavailable.") Instant estimatedTimeOfArrival,
        @Description("The next expected handling. Null when none is expected.")
                HandlingActivity nextExpectedActivity) {}
