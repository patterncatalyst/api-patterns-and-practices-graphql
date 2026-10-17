package com.patterncatalyst.shipping.tracking;

import jakarta.enterprise.context.ApplicationScoped;

/**
 * The location reference data behind {@code Leg.loadLocation} and
 * {@code Leg.unloadLocation}. A code it does not know, such as the dangling
 * {@code XXBAD}, comes back as {@code null}.
 */
@ApplicationScoped
public class LocationSource {

    private final TrackingData data;

    LocationSource(TrackingData data) {
        this.data = data;
    }

    public Location getLocation(String unLocode) {
        return data.location(unLocode);
    }
}
