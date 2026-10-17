package com.patterncatalyst.shipping.tracking;

import java.util.List;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/** The location service's side of the tracking view: getLocation and getLocations. */
@ApplicationScoped
public class LocationSource {

    private final TrackingData data;
    private final SourceCalls calls;

    LocationSource(TrackingData data, SourceCalls calls) {
        this.data = data;
        this.calls = calls;
    }

    /** Null when the location service has nothing under that key. */
    public Uni<Location> getLocation(String request, String unLocode) {
        return calls.call(request, "location", "getLocation", unLocode, () -> data.location(unLocode));
    }

    /** Many locations in one call: one outcome per UN/LOCODE, in the order asked; null when unknown. */
    public Uni<List<Outcome<Location>>> getLocations(String request, List<String> unLocodes) {
        return calls.callBatch(request, "location", "getLocations", unLocodes, data::location);
    }
}
