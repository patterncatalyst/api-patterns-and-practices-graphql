package com.patterncatalyst.shipping.tracking;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * The voyage service's side of the tracking view: getVoyage.
 */
@ApplicationScoped
public class VoyageSource {

    private final TrackingData data;
    private final SourceCalls calls;

    VoyageSource(TrackingData data, SourceCalls calls) {
        this.data = data;
        this.calls = calls;
    }

    /** Null when the voyage service has nothing under that key. */
    public Uni<Voyage> getVoyage(String request, String number) {
        return calls.call(request, "voyage", "getVoyage", number, () -> data.voyage(number));
    }
}
