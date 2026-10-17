package com.patterncatalyst.shipping.tracking;

import jakarta.enterprise.context.ApplicationScoped;

/**
 * The delivery service behind {@code Cargo.delivery}. It raises for cargo
 * {@code PQR234}.
 */
@ApplicationScoped
public class DeliverySource {

    private final TrackingData data;

    DeliverySource(TrackingData data) {
        this.data = data;
    }

    public Delivery getDelivery(String trackingId) {
        if ("PQR234".equals(trackingId)) {
            throw new SourceUnavailableException("delivery service unavailable");
        }
        return data.delivery(trackingId);
    }
}
