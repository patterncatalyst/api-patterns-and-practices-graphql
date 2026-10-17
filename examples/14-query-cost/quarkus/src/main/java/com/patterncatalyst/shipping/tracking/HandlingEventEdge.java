package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("HandlingEventEdge")
@Description("A handling event and its cursor.")
public record HandlingEventEdge(
        @NonNull @Description("An opaque cursor for this edge.") String cursor,
        @Description(
                        "The event at this edge. Null when the event failed to resolve, so one bad item nulls its edge instead of the whole page.")
                HandlingEvent node) {}
