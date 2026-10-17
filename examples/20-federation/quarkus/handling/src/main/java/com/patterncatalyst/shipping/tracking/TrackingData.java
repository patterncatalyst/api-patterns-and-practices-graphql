package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import jakarta.enterprise.context.ApplicationScoped;

/**
 * The in-memory seed behind the handling subgraph: the places and voyages it
 * knows by key, and the booking and routing facts the delivery derivation and
 * the registration rules read. The cargo subgraph holds the same six cargos,
 * five locations and three voyages with all their fields; this subgraph keeps
 * the keys and the route facts, the data stands in for the booking and routing
 * services that both subgraphs read. One cargo is a fault seed: the booking
 * service cannot load {@code GHI345} (see {@link BookingSource#getCargo}). The
 * handling events, the one mutable part, live in {@link HandlingStore}.
 */
@ApplicationScoped
public class TrackingData {

    private static final Location NEW_YORK = new Location(new UnLocode("USNYC"));
    private static final Location ROTTERDAM = new Location(new UnLocode("NLRTM"));
    private static final Location HAMBURG = new Location(new UnLocode("DEHAM"));
    private static final Location SINGAPORE = new Location(new UnLocode("SGSIN"));
    private static final Location SHANGHAI = new Location(new UnLocode("CNSHA"));

    private static final Instant V100S_DEPARTS = Instant.parse("2026-10-01T08:00:00Z");
    private static final Instant V100S_ARRIVES = Instant.parse("2026-10-09T14:00:00Z");
    private static final Instant V200E_DEPARTS = Instant.parse("2026-10-10T06:00:00Z");
    private static final Instant V200E_ARRIVES = Instant.parse("2026-10-11T18:00:00Z");
    private static final Instant V300A_DEPARTS = Instant.parse("2026-11-02T04:00:00Z");
    private static final Instant V300A_ARRIVES = Instant.parse("2026-11-06T10:00:00Z");

    /** The two-leg New York to Rotterdam route of ABC123 and DEF456. */
    private static final Itinerary VIA_HAMBURG = new Itinerary(
            List.of(
                    new Leg("V100S", "USNYC", "DEHAM", V100S_DEPARTS, V100S_ARRIVES),
                    new Leg("V200E", "DEHAM", "NLRTM", V200E_DEPARTS, V200E_ARRIVES)),
            V200E_ARRIVES);

    /** The one-leg Singapore to Shanghai route of VWX901 and STU678. */
    private static final Itinerary SINGAPORE_TO_SHANGHAI = new Itinerary(
            List.of(new Leg("V300A", "SGSIN", "CNSHA", V300A_DEPARTS, V300A_ARRIVES)), V300A_ARRIVES);

    private final Map<String, Location> locations = Stream.of(NEW_YORK, ROTTERDAM, HAMBURG, SINGAPORE, SHANGHAI)
            .collect(Collectors.toUnmodifiableMap(l -> l.unLocode().value(), l -> l));
    private final Map<String, Voyage> voyages = Stream.of("V100S", "V200E", "V300A")
            .collect(Collectors.toUnmodifiableMap(number -> number, Voyage::new));
    private final Map<String, Cargo> cargos = Stream.of(
                    newCargo("ABC123", NEW_YORK, ROTTERDAM),
                    newCargo("DEF456", NEW_YORK, ROTTERDAM),
                    newCargo("GHI345", NEW_YORK, HAMBURG),
                    newCargo("STU678", SINGAPORE, ROTTERDAM),
                    newCargo("VWX901", SINGAPORE, SHANGHAI),
                    newCargo("XYZ789", SINGAPORE, ROTTERDAM))
            .collect(Collectors.toUnmodifiableMap(c -> c.trackingId().value(), c -> c));
    private final Map<String, Itinerary> itineraries = Map.of(
            "ABC123", VIA_HAMBURG,
            "DEF456", VIA_HAMBURG,
            "STU678", SINGAPORE_TO_SHANGHAI,
            "VWX901", SINGAPORE_TO_SHANGHAI);

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

    private static Cargo newCargo(String trackingId, Location origin, Location destination) {
        return new Cargo(new TrackingId(trackingId), new RouteSpecification(origin, destination));
    }
}
