package com.patterncatalyst.shipping.tracking;

import jakarta.enterprise.context.ApplicationScoped;

/**
 * The voyage service behind {@code Leg.voyage}. It raises for voyage
 * {@code V404X}, the lab's stand-in for a service that is down.
 */
@ApplicationScoped
public class VoyageSource {

    private final TrackingData data;

    VoyageSource(TrackingData data) {
        this.data = data;
    }

    public Voyage getVoyage(String voyageNumber) {
        if ("V404X".equals(voyageNumber)) {
            throw new SourceUnavailableException("voyage service unavailable");
        }
        return data.voyage(voyageNumber);
    }
}
