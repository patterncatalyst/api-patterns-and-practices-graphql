package com.patterncatalyst.shipping.tracking;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/** The delivery service's side of the tracking view: getDelivery. */
@ApplicationScoped
public class DeliverySource {

    private final TrackingData data;
    private final SourceCalls calls;

    DeliverySource(TrackingData data, SourceCalls calls) {
        this.data = data;
        this.calls = calls;
    }

    /** Null when the delivery service has nothing under that key. */
    public Uni<Delivery> getDelivery(String request, String trackingId) {
        return calls.call(request, "delivery", "getDelivery", trackingId, () -> data.delivery(trackingId));
    }
}
