package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("HandlingActivity")
@Description("An expected future handling of a cargo.")
public record HandlingActivity(
        @NonNull @Description("The kind of handling expected.") HandlingEventType type,
        @NonNull @Description("Where it is expected.") Location location,
        @Description("On which voyage. Null for handling not tied to a voyage.") Voyage voyage) {}
