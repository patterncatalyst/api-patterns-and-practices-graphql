package com.patterncatalyst.shipping.tracking;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.time.Instant;
import java.util.List;

import org.junit.jupiter.api.Test;

/**
 * Resolver layer, pure units. {@link DeliveryDerivation} calls no source, so it
 * runs with no server: seed cargo and itinerary in, events in, a delivery out.
 */
class DeliveryDerivationTest {

    private final TrackingData data = new TrackingData();
    private final DeliveryDerivation derivation = new DeliveryDerivation(data);

    private Delivery derive(String trackingId, List<HandlingRecord> events) {
        return derivation.derive(data.cargo(trackingId), data.itinerary(trackingId), events);
    }

    @Test
    void anUnloadAtAPortLeavesTheCargoInPort() {
        HandlingRecord unload = new HandlingRecord(
                "evt_t1",
                "ABC123",
                HandlingEventType.UNLOAD,
                "DEHAM",
                "V100S",
                Instant.parse("2026-10-09T15:00:00Z"),
                Instant.parse("2026-10-09T15:01:00Z"));

        Delivery delivery = derive("ABC123", List.of(unload));

        assertEquals(TransportStatus.IN_PORT, delivery.transportStatus());
        assertNull(delivery.currentVoyage(), "a cargo in port is on no voyage");
        assertEquals("DEHAM", delivery.lastKnownLocation().unLocode().value());
    }

    @Test
    void aCargoWithNoEventsIsNotReceived() {
        Delivery delivery = derive("ABC123", List.of());

        assertEquals(TransportStatus.NOT_RECEIVED, delivery.transportStatus());
        assertNull(delivery.lastKnownLocation());
    }
}
