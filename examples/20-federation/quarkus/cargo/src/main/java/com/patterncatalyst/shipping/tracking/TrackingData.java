package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import jakarta.enterprise.context.ApplicationScoped;

/**
 * The in-memory seed behind the tracking view: five locations, three voyages
 * and six cargos, the same data on both stacks. The booking service keeps an
 * index of its cargos, newest booking first, with the routing status it stored
 * for each; {@link #bookingIndex} is that index, and the booking source pages
 * it. One cargo is a fault seed: the booking service cannot load {@code GHI345}
 * (see {@link BookingSource#getCargo}), although its index still lists it.
 * The data stands in for the services that own it. The booking source reads
 * {@link #cargo} and {@link #bookingIndex}, the routing source {@link #itinerary} and the voyage and
 * location sources their own maps; every read goes through a source, which
 * is what records the call.
 */
@ApplicationScoped
public class TrackingData {

    /**
     * One row of the booking index: what the booking service can list without
     * loading the cargo. {@code routingStatus} is the value the service stored
     * at booking; verify.sh checks that it equals the derived one.
     */
    public record BookingEntry(String trackingId, Instant bookedAt, RoutingStatus routingStatus) {

        /** The position of this row in the connection order. */
        public Pagination.CargoKey key() {
            return new Pagination.CargoKey(bookedAt, trackingId);
        }
    }

    private static final Location NEW_YORK = newLocation("USNYC", "New York", "US");
    private static final Location ROTTERDAM = newLocation("NLRTM", "Rotterdam", "NL");
    private static final Location HAMBURG = newLocation("DEHAM", "Hamburg", "DE");
    private static final Location SINGAPORE = newLocation("SGSIN", "Singapore", "SG");
    private static final Location SHANGHAI = newLocation("CNSHA", "Shanghai", "CN");

    private static final Instant V100S_DEPARTS = Instant.parse("2026-10-01T08:00:00Z");
    private static final Instant V100S_ARRIVES = Instant.parse("2026-10-09T14:00:00Z");
    private static final Instant V200E_DEPARTS = Instant.parse("2026-10-10T06:00:00Z");
    private static final Instant V200E_ARRIVES = Instant.parse("2026-10-11T18:00:00Z");
    private static final Instant V300A_DEPARTS = Instant.parse("2026-11-02T04:00:00Z");
    private static final Instant V300A_ARRIVES = Instant.parse("2026-11-06T10:00:00Z");

    private static final Voyage V100S =
            newVoyage("V100S", new CarrierMovement(NEW_YORK, HAMBURG, V100S_DEPARTS, V100S_ARRIVES));
    private static final Voyage V200E =
            newVoyage("V200E", new CarrierMovement(HAMBURG, ROTTERDAM, V200E_DEPARTS, V200E_ARRIVES));
    private static final Voyage V300A =
            newVoyage("V300A", new CarrierMovement(SINGAPORE, SHANGHAI, V300A_DEPARTS, V300A_ARRIVES));

    /** The two-leg New York to Rotterdam route of ABC123 and DEF456. */
    private static final Itinerary VIA_HAMBURG = newItinerary(
            V200E_ARRIVES,
            new Leg("V100S", "USNYC", "DEHAM", V100S_DEPARTS, V100S_ARRIVES),
            new Leg("V200E", "DEHAM", "NLRTM", V200E_DEPARTS, V200E_ARRIVES));

    /** The one-leg Singapore to Shanghai route of VWX901 and STU678. */
    private static final Itinerary SINGAPORE_TO_SHANGHAI = newItinerary(
            V300A_ARRIVES, new Leg("V300A", "SGSIN", "CNSHA", V300A_DEPARTS, V300A_ARRIVES));

    private static final Cargo ABC123 = newCargo(
            "ABC123", "Palletized electronics", NEW_YORK, ROTTERDAM, "2026-10-15T00:00:00Z");
    private static final Cargo DEF456 = newCargo(
            "DEF456", "Auto parts", NEW_YORK, ROTTERDAM, "2026-10-15T00:00:00Z");
    private static final Cargo GHI345 = newCargo(
            "GHI345", "Medical supplies", NEW_YORK, HAMBURG, "2026-10-20T00:00:00Z");
    private static final Cargo STU678 = newCargo(
            "STU678", "Rubber goods", SINGAPORE, ROTTERDAM, "2026-11-20T00:00:00Z");
    private static final Cargo VWX901 = newCargo(
            "VWX901", "Furniture", SINGAPORE, SHANGHAI, "2026-11-10T00:00:00Z");
    private static final Cargo XYZ789 = newCargo(
            "XYZ789", "Frozen seafood", SINGAPORE, ROTTERDAM, "2026-11-20T00:00:00Z");

    private final Map<String, Location> locations = Stream.of(NEW_YORK, ROTTERDAM, HAMBURG, SINGAPORE, SHANGHAI)
            .collect(Collectors.toUnmodifiableMap(l -> l.unLocode().value(), l -> l));
    private final Map<String, Voyage> voyages = Stream.of(V100S, V200E, V300A)
            .collect(Collectors.toUnmodifiableMap(Voyage::number, v -> v));
    private final Map<String, Cargo> cargos = Stream.of(ABC123, DEF456, GHI345, STU678, VWX901, XYZ789)
            .collect(Collectors.toUnmodifiableMap(c -> c.trackingId().value(), c -> c));
    private final Map<String, Itinerary> itineraries = Map.of(
            "ABC123", VIA_HAMBURG,
            "DEF456", VIA_HAMBURG,
            "STU678", SINGAPORE_TO_SHANGHAI,
            "VWX901", SINGAPORE_TO_SHANGHAI);

    /** The booking index, newest booking first. */
    private final List<BookingEntry> bookingIndex = Stream.of(
                    entry("VWX901", "2026-09-29T09:00:00Z", RoutingStatus.ROUTED),
                    entry("XYZ789", "2026-09-28T09:00:00Z", RoutingStatus.NOT_ROUTED),
                    entry("STU678", "2026-09-27T09:00:00Z", RoutingStatus.MISROUTED),
                    entry("DEF456", "2026-09-26T09:00:00Z", RoutingStatus.ROUTED),
                    entry("ABC123", "2026-09-25T09:00:00Z", RoutingStatus.ROUTED),
                    entry("GHI345", "2026-09-24T09:00:00Z", RoutingStatus.NOT_ROUTED))
            .sorted(Comparator.comparing(BookingEntry::key).reversed())
            .toList();

    public Cargo cargo(String trackingId) {
        return cargos.get(trackingId);
    }

    /** The booking index, newest booking first. */
    public List<BookingEntry> bookingIndex() {
        return bookingIndex;
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

    private static BookingEntry entry(String trackingId, String bookedAt, RoutingStatus routingStatus) {
        return new BookingEntry(trackingId, Instant.parse(bookedAt), routingStatus);
    }

    private static Cargo newCargo(
            String trackingId, String description, Location origin, Location destination, String arrivalDeadline) {
        return new Cargo(
                "cargo_" + trackingId,
                new TrackingId(trackingId),
                description,
                origin,
                destination,
                new RouteSpecification(origin, destination, Instant.parse(arrivalDeadline)));
    }

    /** Both final-arrival components carry the same instant: the old name is deprecated, not different. */
    private static Itinerary newItinerary(Instant finalArrival, Leg... legs) {
        return new Itinerary(List.of(legs), finalArrival, finalArrival);
    }

    private static Location newLocation(String unLocode, String name, String country) {
        return new Location("loc_" + unLocode, new UnLocode(unLocode), name, country);
    }

    private static Voyage newVoyage(String number, CarrierMovement... schedule) {
        return new Voyage("voy_" + number, number, List.of(schedule));
    }
}
