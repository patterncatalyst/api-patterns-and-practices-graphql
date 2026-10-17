package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("CarrierMovement")
@Description("One scheduled departure-to-arrival movement of a voyage between two locations.")
public record CarrierMovement(
        @NonNull @Description("Where the movement departs from.") Location departureLocation,
        @NonNull @Description("Where the movement arrives.") Location arrivalLocation,
        @NonNull @Description("Scheduled departure time.") Instant departureTime,
        @NonNull @Description("Scheduled arrival time.") Instant arrivalTime) {}
