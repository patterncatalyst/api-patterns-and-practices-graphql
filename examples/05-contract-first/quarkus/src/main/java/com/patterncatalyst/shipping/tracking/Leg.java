package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("Leg")
@Description("One hop of an itinerary on a single voyage.")
public record Leg(
        @Description("The voyage that carries this leg. Null when the voyage service is unavailable.")
                Voyage voyage,
        @NonNull @Description("Where the cargo is loaded.") Location loadLocation,
        @NonNull @Description("Where the cargo is unloaded.") Location unloadLocation,
        @NonNull @Description("When the cargo is loaded.") Instant loadTime,
        @NonNull @Description("When the cargo is unloaded.") Instant unloadTime) {}
