package com.patterncatalyst.shipping.tracking;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/** The booking service's side of the tracking view: getCargo. */
@ApplicationScoped
public class BookingSource {

    private final TrackingData data;
    private final SourceCalls calls;

    BookingSource(TrackingData data, SourceCalls calls) {
        this.data = data;
        this.calls = calls;
    }

    /** Null when the booking service has nothing under that key. */
    public Uni<Cargo> getCargo(String request, String trackingId) {
        return calls.call(request, "booking", "getCargo", trackingId, () -> data.cargo(trackingId));
    }
}
