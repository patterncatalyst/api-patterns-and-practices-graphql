package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

import jakarta.enterprise.context.ApplicationScoped;

/**
 * Turns booking, routing and handling facts into a {@link Delivery}. It calls
 * no source, so it can be tested without a request; {@link TrackingApi}
 * fetches the inputs and hands them over.
 *
 * <p>"Last event" is the one with the maximum completion time; a tie goes to
 * the later registration.
 *
 * <pre>
 * last event        transport        current voyage  next expected activity
 * none              NOT_RECEIVED     none            RECEIVE at the route's origin
 * RECEIVE           IN_PORT          none            LOAD on the first leg
 * LOAD at L on V    ONBOARD_CARRIER  V               UNLOAD at the matching leg's end
 * UNLOAD at L on V  IN_PORT          none            CLAIM at L if L is the destination,
 *                                                    else LOAD on the next leg
 * CUSTOMS           IN_PORT          none            none
 * CLAIM             CLAIMED          none            none
 * </pre>
 *
 * An activity that needs a leg the itinerary does not have is null.
 */
@ApplicationScoped
public class DeliveryDerivation {

    private static final Comparator<HandlingRecord> BY_COMPLETION_THEN_REGISTRATION =
            Comparator.comparing(HandlingRecord::completionTime).thenComparing(HandlingRecord::registrationTime);

    private final TrackingData data;

    DeliveryDerivation(TrackingData data) {
        this.data = data;
    }

    /** {@code itinerary} is null when the cargo has not been routed. */
    public Delivery derive(Cargo cargo, Itinerary itinerary, List<HandlingRecord> events) {
        RouteSpecification spec = cargo.routeSpecification();
        List<Leg> legs = itinerary == null ? List.of() : itinerary.legs();
        HandlingRecord last = events.stream().max(BY_COMPLETION_THEN_REGISTRATION).orElse(null);

        RoutingStatus routing = routingStatus(spec, legs);
        boolean misdirected = routing != RoutingStatus.NOT_ROUTED
                && last != null
                && (last.type() == HandlingEventType.LOAD || last.type() == HandlingEventType.UNLOAD)
                && matchingLeg(legs, last).isEmpty();
        boolean onCourse = routing == RoutingStatus.ROUTED && !misdirected;
        Instant eta = itinerary != null && onCourse ? itinerary.finalArrivalDate() : null;

        return new Delivery(
                transportStatus(last),
                routing,
                misdirected,
                last == null ? null : data.location(last.unLocode()),
                last != null && last.type() == HandlingEventType.LOAD ? voyage(last.voyageNumber()) : null,
                eta,
                nextActivity(cargo, legs, last));
    }

    private HandlingActivity nextActivity(Cargo cargo, List<Leg> legs, HandlingRecord last) {
        if (last == null) {
            return new HandlingActivity(HandlingEventType.RECEIVE, cargo.routeSpecification().origin(), null);
        }
        return switch (last.type()) {
            case RECEIVE -> legs.isEmpty() ? null : load(legs.getFirst());
            case LOAD -> matchingLeg(legs, last).map(index -> unload(legs.get(index))).orElse(null);
            case UNLOAD -> {
                if (last.unLocode().equals(cargo.routeSpecification().destination().unLocode().value())) {
                    yield new HandlingActivity(HandlingEventType.CLAIM, data.location(last.unLocode()), null);
                }
                yield matchingLeg(legs, last)
                        .filter(index -> index + 1 < legs.size())
                        .map(index -> load(legs.get(index + 1)))
                        .orElse(null);
            }
            case CUSTOMS, CLAIM -> null;
        };
    }

    private HandlingActivity load(Leg leg) {
        return new HandlingActivity(
                HandlingEventType.LOAD, data.location(leg.loadUnLocode()), voyage(leg.voyageNumber()));
    }

    private HandlingActivity unload(Leg leg) {
        return new HandlingActivity(
                HandlingEventType.UNLOAD, data.location(leg.unloadUnLocode()), voyage(leg.voyageNumber()));
    }

    private Voyage voyage(String number) {
        return number == null ? null : data.voyage(number);
    }

    private static TransportStatus transportStatus(HandlingRecord last) {
        if (last == null) {
            return TransportStatus.NOT_RECEIVED;
        }
        return switch (last.type()) {
            case LOAD -> TransportStatus.ONBOARD_CARRIER;
            case CLAIM -> TransportStatus.CLAIMED;
            case RECEIVE, UNLOAD, CUSTOMS -> TransportStatus.IN_PORT;
        };
    }

    private static RoutingStatus routingStatus(RouteSpecification spec, List<Leg> legs) {
        if (legs.isEmpty()) {
            return RoutingStatus.NOT_ROUTED;
        }
        boolean fromOrigin = legs.getFirst().loadUnLocode().equals(spec.origin().unLocode().value());
        boolean toDestination = legs.getLast().unloadUnLocode().equals(spec.destination().unLocode().value());
        return fromOrigin && toDestination ? RoutingStatus.ROUTED : RoutingStatus.MISROUTED;
    }

    /** The index of the leg a LOAD or UNLOAD belongs to: same place, same voyage. */
    private static Optional<Integer> matchingLeg(List<Leg> legs, HandlingRecord event) {
        for (int index = 0; index < legs.size(); index++) {
            Leg leg = legs.get(index);
            String place = event.type() == HandlingEventType.LOAD ? leg.loadUnLocode() : leg.unloadUnLocode();
            if (place.equals(event.unLocode()) && leg.voyageNumber().equals(event.voyageNumber())) {
                return Optional.of(index);
            }
        }
        return Optional.empty();
    }
}
