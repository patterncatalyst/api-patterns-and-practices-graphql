package com.patterncatalyst.shipping.tracking;

import java.util.List;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/** The handling service's side of the tracking view: listEvents. */
@ApplicationScoped
public class HandlingSource {

    private final TrackingData data;
    private final SourceCalls calls;

    HandlingSource(TrackingData data, SourceCalls calls) {
        this.data = data;
        this.calls = calls;
    }

    /** Every event recorded for the cargo; empty when there are none. */
    public Uni<List<HandlingRecord>> listEvents(String request, String trackingId) {
        return calls.call(request, "handling", "listEvents", trackingId, () -> data.events(trackingId));
    }
}
