package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.util.List;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("Itinerary")
@Description("The planned sequence of legs moving a cargo from origin to destination.")
public record Itinerary(
        @NonNull @Description("Ordered legs of the route; never empty for an assigned itinerary.")
                List<@NonNull Leg> legs,
        @NonNull @Description("When the final leg arrives.") Instant finalArrivalDate) {}
