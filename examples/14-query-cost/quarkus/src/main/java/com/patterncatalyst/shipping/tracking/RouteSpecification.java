package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("RouteSpecification")
@Description("The customer's routing requirements for a cargo.")
public record RouteSpecification(
        @NonNull @Description("Required origin.") Location origin,
        @NonNull @Description("Required destination.") Location destination,
        @NonNull @Description("The date by which the cargo must arrive.") Instant arrivalDeadline) {}
