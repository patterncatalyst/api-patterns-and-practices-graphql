package com.patterncatalyst.shipping.tracking;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/** The routing service's side of the tracking view: getItinerary. */
@ApplicationScoped
public class RoutingSource {

    private final TrackingData data;
    private final SourceCalls calls;

    RoutingSource(TrackingData data, SourceCalls calls) {
        this.data = data;
        this.calls = calls;
    }

    /** Null when the routing service has nothing under that key. */
    public Uni<Itinerary> getItinerary(String request, String trackingId) {
        return calls.call(request, "routing", "getItinerary", trackingId, () -> data.itinerary(trackingId));
    }
}
