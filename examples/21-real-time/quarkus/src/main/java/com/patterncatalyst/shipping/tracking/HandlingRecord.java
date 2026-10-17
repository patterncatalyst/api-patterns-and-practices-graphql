package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

/**
 * What the handling service stores for one event. It is the internal form:
 * the GraphQL {@code HandlingEvent} type is built from it by
 * {@link HandlingEvent#of}, and {@link DeliveryDerivation} reads it directly.
 */
public record HandlingRecord(
        String id,
        String trackingId,
        HandlingEventType type,
        String unLocode,
        String voyageNumber,
        Instant completionTime,
        Instant registrationTime) {

    /** The number in {@code evt_<n>}: ids are issued in registration order. */
    public int sequence() {
        return Integer.parseInt(id.substring("evt_".length()));
    }

    /** The position of this event in {@code handlingHistory}. */
    public Pagination.EventKey key() {
        return new Pagination.EventKey(completionTime, sequence());
    }
}
