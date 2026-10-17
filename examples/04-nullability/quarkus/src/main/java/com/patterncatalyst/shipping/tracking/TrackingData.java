package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import jakarta.enterprise.context.ApplicationScoped;

/**
 * The in-memory seed behind the tracking view: five locations, three voyages
 * and five cargos, the same data on both stacks. A {@link Leg} stores the keys
 * of its voyage and locations, and a cargo's {@link Delivery} is stored apart
 * from the cargo; the sources in this package look them up. Three cargos carry
 * a fault: JKL567 names a voyage whose service raises, MNO901 has a leg whose
 * load location is a dangling code, and PQR234 has a delivery service that
 * raises. Every object is reachable by its global id through
 * {@link #node(String)}.
 */
@ApplicationScoped
public class TrackingData {

    private static final Location NEW_YORK = newLocation("USNYC", "New York", "US");
    private static final Location ROTTERDAM = newLocation("NLRTM", "Rotterdam", "NL");
    private static final Location HAMBURG = newLocation("DEHAM", "Hamburg", "DE");
    private static final Location SINGAPORE = newLocation("SGSIN", "Singapore", "SG");
    private static final Location SHANGHAI = newLocation("CNSHA", "Shanghai", "CN");

    private static final Instant V100S_DEPARTS = Instant.parse("2026-10-01T08:00:00Z");
    private static final Instant V100S_ARRIVES = Instant.parse("2026-10-09T14:00:00Z");
    private static final Instant V200E_DEPARTS = Instant.parse("2026-10-10T06:00:00Z");
    private static final Instant V200E_ARRIVES = Instant.parse("2026-10-11T18:00:00Z");

    private static final Voyage V100S =
            newVoyage("V100S", new CarrierMovement(NEW_YORK, HAMBURG, V100S_DEPARTS, V100S_ARRIVES));
    private static final Voyage V200E =
            newVoyage("V200E", new CarrierMovement(HAMBURG, ROTTERDAM, V200E_DEPARTS, V200E_ARRIVES));
    private static final Voyage V300A = newVoyage(
            "V300A",
            new CarrierMovement(
                    SINGAPORE,
                    SHANGHAI,
                    Instant.parse("2026-11-02T04:00:00Z"),
                    Instant.parse("2026-11-06T10:00:00Z")));

    private static final Instant FAULT_LOADS = Instant.parse("2026-10-20T08:00:00Z");
    private static final Instant FAULT_UNLOADS = Instant.parse("2026-10-28T14:00:00Z");
    private static final Instant FAULT_DEADLINE = Instant.parse("2026-11-15T00:00:00Z");

    private static final Itinerary ABC123_ITINERARY = new Itinerary(
            List.of(
                    new Leg("V100S", "USNYC", "DEHAM", V100S_DEPARTS, V100S_ARRIVES),
                    new Leg("V200E", "DEHAM", "NLRTM", V200E_DEPARTS, V200E_ARRIVES)),
            V200E_ARRIVES);

    private static final Cargo ABC123 = new Cargo(
            "cargo_ABC123",
            new TrackingId("ABC123"),
            "Palletized electronics",
            NEW_YORK,
            ROTTERDAM,
            new RouteSpecification(NEW_YORK, ROTTERDAM, Instant.parse("2026-10-15T00:00:00Z")),
            ABC123_ITINERARY);

    private static final Cargo XYZ789 = new Cargo(
            "cargo_XYZ789",
            new TrackingId("XYZ789"),
            "Frozen seafood",
            SINGAPORE,
            ROTTERDAM,
            new RouteSpecification(SINGAPORE, ROTTERDAM, Instant.parse("2026-11-20T00:00:00Z")),
            null);

    // JKL567: its one leg is on V404X, and the voyage source raises for V404X.
    private static final Cargo JKL567 = faultCargo("JKL567", "Machine parts", oneLegItinerary("V404X", "USNYC"));

    // MNO901: its one leg loads at XXBAD, a code the location source does not know.
    private static final Cargo MNO901 = faultCargo("MNO901", "Textiles", oneLegItinerary("V100S", "XXBAD"));

    // PQR234: a healthy itinerary; the delivery source raises for it.
    private static final Cargo PQR234 = faultCargo("PQR234", "Coffee beans", ABC123_ITINERARY);

    private static final Delivery ABC123_DELIVERY = new Delivery(
            TransportStatus.ONBOARD_CARRIER,
            RoutingStatus.ROUTED,
            false,
            NEW_YORK,
            V100S,
            V200E_ARRIVES,
            new HandlingActivity(HandlingEventType.UNLOAD, HAMBURG, V100S));

    private static final Delivery XYZ789_DELIVERY = new Delivery(
            TransportStatus.NOT_RECEIVED,
            RoutingStatus.NOT_ROUTED,
            false,
            null,
            null,
            null,
            new HandlingActivity(HandlingEventType.RECEIVE, SINGAPORE, null));

    private static final Delivery FAULT_DELIVERY = new Delivery(
            TransportStatus.NOT_RECEIVED,
            RoutingStatus.ROUTED,
            false,
            null,
            null,
            FAULT_UNLOADS,
            new HandlingActivity(HandlingEventType.RECEIVE, NEW_YORK, null));

    private final Map<String, Location> locations = Stream.of(NEW_YORK, ROTTERDAM, HAMBURG, SINGAPORE, SHANGHAI)
            .collect(Collectors.toUnmodifiableMap(l -> l.unLocode().value(), l -> l));
    private final Map<String, Voyage> voyages = Stream.of(V100S, V200E, V300A)
            .collect(Collectors.toUnmodifiableMap(Voyage::number, v -> v));
    private final Map<String, Cargo> cargos = Stream.of(ABC123, XYZ789, JKL567, MNO901, PQR234)
            .collect(Collectors.toUnmodifiableMap(c -> c.trackingId().value(), c -> c));
    private final Map<String, Delivery> deliveries = Map.of(
            "ABC123", ABC123_DELIVERY, "XYZ789", XYZ789_DELIVERY, "JKL567", FAULT_DELIVERY, "MNO901", FAULT_DELIVERY);
    private final Map<String, Node> nodes = Stream.of(locations.values(), voyages.values(), cargos.values())
            .flatMap(Collection::stream)
            .collect(Collectors.toUnmodifiableMap(Node::getId, node -> node));

    public Cargo cargo(String trackingId) {
        return cargos.get(trackingId);
    }

    /** The stored delivery of a cargo, or null when none is stored. */
    public Delivery delivery(String trackingId) {
        return deliveries.get(trackingId);
    }

    public Location location(String unLocode) {
        return locations.get(unLocode);
    }

    public Voyage voyage(String number) {
        return voyages.get(number);
    }

    /** Resolves a global id to the object it names, or null when no object has that id. */
    public Node node(String id) {
        return nodes.get(id);
    }

    private static Itinerary oneLegItinerary(String voyageNumber, String loadUnLocode) {
        return new Itinerary(
                List.of(new Leg(voyageNumber, loadUnLocode, "NLRTM", FAULT_LOADS, FAULT_UNLOADS)), FAULT_UNLOADS);
    }

    private static Cargo faultCargo(String trackingId, String description, Itinerary itinerary) {
        return new Cargo(
                "cargo_" + trackingId,
                new TrackingId(trackingId),
                description,
                NEW_YORK,
                ROTTERDAM,
                new RouteSpecification(NEW_YORK, ROTTERDAM, FAULT_DEADLINE),
                itinerary);
    }

    private static Location newLocation(String unLocode, String name, String country) {
        return new Location("loc_" + unLocode, new UnLocode(unLocode), name, country);
    }

    private static Voyage newVoyage(String number, CarrierMovement... schedule) {
        return new Voyage("voy_" + number, number, List.of(schedule));
    }
}
