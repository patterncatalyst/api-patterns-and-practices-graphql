package com.patterncatalyst.shipping.tracking;

import java.util.List;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * The voyage service's side of the tracking view: getVoyage and getVoyages.
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

    /** Many voyages in one call: one outcome per voyage number, in the order asked; null when unknown. */
    public Uni<List<Outcome<Voyage>>> getVoyages(String request, List<String> numbers) {
        return calls.callBatch(request, "voyage", "getVoyages", numbers, data::voyage);
    }
}
