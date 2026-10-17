package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;

@Description("Whether the cargo is following its itinerary.")
public enum RoutingStatus {
    @Description("No itinerary has been assigned.")
    NOT_ROUTED,
    @Description("The itinerary satisfies the route specification.")
    ROUTED,
    @Description("The itinerary no longer satisfies the route specification.")
    MISROUTED
}
