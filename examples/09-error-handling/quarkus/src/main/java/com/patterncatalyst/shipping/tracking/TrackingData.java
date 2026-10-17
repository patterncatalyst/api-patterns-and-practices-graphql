package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import jakarta.enterprise.context.ApplicationScoped;

/**
 * The in-memory seed behind the tracking view: five locations, three voyages,
 * five cargos, the same data on both stacks. Three cargos are fault seeds, each
 * breaking one source: JKL567 sails on V404X, a voyage the voyage service
 * cannot serve; MNO901 loads at XXBAD, a code the location service does not
 * know; PQR234 is healthy except that the handling service fails when asked
 * for its events. It stands in for the services that own the data. The booking source reads {@link #cargo}, the routing
 * source {@link #itinerary} and the voyage and location sources their own maps;
 * {@link DeliveryDerivation} reads {@link #location} and {@link #voyage} as
 * reference data for the objects a derived {@code Delivery} embeds; every other
 * read goes through a source, which is what records the call. The handling
 * events, the one mutable part, live in {@link HandlingStore}.
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

    private static final Cargo ABC123 = new Cargo(
            "cargo_ABC123",
            new TrackingId("ABC123"),
            "Palletized electronics",
            NEW_YORK,
            ROTTERDAM,
            new RouteSpecification(NEW_YORK, ROTTERDAM, Instant.parse("2026-10-15T00:00:00Z")));

    private static final Itinerary ABC123_ITINERARY = new Itinerary(
            List.of(
                    new Leg("V100S", "USNYC", "DEHAM", V100S_DEPARTS, V100S_ARRIVES),
                    new Leg("V200E", "DEHAM", "NLRTM", V200E_DEPARTS, V200E_ARRIVES)),
            V200E_ARRIVES);

    private static final Cargo XYZ789 = new Cargo(
            "cargo_XYZ789",
            new TrackingId("XYZ789"),
            "Frozen seafood",
            SINGAPORE,
            ROTTERDAM,
            new RouteSpecification(SINGAPORE, ROTTERDAM, Instant.parse("2026-11-20T00:00:00Z")));

    // JKL567: its one leg is on V404X; the voyage source fails for that number.
    private static final Cargo JKL567 = routedCargo("JKL567", "Machine parts");
    private static final Itinerary JKL567_ITINERARY = new Itinerary(
            List.of(new Leg("V404X", "USNYC", "NLRTM", V100S_DEPARTS, V100S_ARRIVES)), V100S_ARRIVES);

    // MNO901: its one leg loads at XXBAD, which the location source answers with null.
    private static final Cargo MNO901 = routedCargo("MNO901", "Textiles");
    private static final Itinerary MNO901_ITINERARY = new Itinerary(
            List.of(new Leg("V100S", "XXBAD", "NLRTM", V100S_DEPARTS, V100S_ARRIVES)), V100S_ARRIVES);

    // PQR234: itinerary as ABC123; the handling source fails when it lists this cargo's events.
    private static final Cargo PQR234 = routedCargo("PQR234", "Coffee beans");

    private final Map<String, Location> locations = Stream.of(NEW_YORK, ROTTERDAM, HAMBURG, SINGAPORE, SHANGHAI)
            .collect(Collectors.toUnmodifiableMap(l -> l.unLocode().value(), l -> l));
    private final Map<String, Voyage> voyages = Stream.of(V100S, V200E, V300A)
            .collect(Collectors.toUnmodifiableMap(Voyage::number, v -> v));
    private final Map<String, Cargo> cargos = Stream.of(ABC123, XYZ789, JKL567, MNO901, PQR234)
            .collect(Collectors.toUnmodifiableMap(c -> c.trackingId().value(), c -> c));
    private final Map<String, Itinerary> itineraries = Map.of(
            "ABC123", ABC123_ITINERARY,
            "JKL567", JKL567_ITINERARY,
            "MNO901", MNO901_ITINERARY,
            "PQR234", ABC123_ITINERARY);

    public Cargo cargo(String trackingId) {
        return cargos.get(trackingId);
    }

    public Location location(String unLocode) {
        return locations.get(unLocode);
    }

    public Voyage voyage(String number) {
        return voyages.get(number);
    }

    /** The planned route, or null when the cargo has none yet. */
    public Itinerary itinerary(String trackingId) {
        return itineraries.get(trackingId);
    }

    /** A New York to Rotterdam cargo, booked with the ABC123 deadline. */
    private static Cargo routedCargo(String trackingId, String description) {
        return new Cargo(
                "cargo_" + trackingId,
                new TrackingId(trackingId),
                description,
                NEW_YORK,
                ROTTERDAM,
                new RouteSpecification(NEW_YORK, ROTTERDAM, Instant.parse("2026-10-15T00:00:00Z")));
    }

    private static Location newLocation(String unLocode, String name, String country) {
        return new Location("loc_" + unLocode, new UnLocode(unLocode), name, country);
    }

    private static Voyage newVoyage(String number, CarrierMovement... schedule) {
        return new Voyage("voy_" + number, number, List.of(schedule));
    }
}
