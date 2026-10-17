package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * Registers a handling event: validate the domain rules, then record the event
 * once. The steps run in this order and stop at the first that decides the
 * outcome:
 *
 * <ol>
 *   <li>look up the cargo, the location and (when a voyage is named) the voyage,
 *       all at once;
 *   <li>collect <em>every</em> domain failure, in the order trackingId,
 *       location, voyageNumber, completionTime; any failure returns a payload
 *       of {@code userErrors} and writes nothing;
 *   <li>with an idempotency key, return the event the key already produced;
 *   <li>otherwise append the event, atomically with respect to the key.
 * </ol>
 *
 * Input coercion has already happened by the time this runs: a malformed input
 * is rejected before it.
 */
@ApplicationScoped
public class HandlingRegistration {

    private final BookingSource booking;
    private final LocationSource locations;
    private final VoyageSource voyages;
    private final HandlingSource handling;

    HandlingRegistration(
            BookingSource booking, LocationSource locations, VoyageSource voyages, HandlingSource handling) {
        this.booking = booking;
        this.locations = locations;
        this.voyages = voyages;
        this.handling = handling;
    }

    public Uni<RegisterHandlingEventPayload> register(
            String request, RegisterHandlingEventInput input, Viewer viewer) {
        boolean needsVoyage = input.type() == HandlingEventType.LOAD || input.type() == HandlingEventType.UNLOAD;
        Uni<Voyage> voyage = needsVoyage && input.voyageNumber() != null
                ? voyages.getVoyage(request, input.voyageNumber())
                : Uni.createFrom().nullItem();
        return Uni.combine()
                .all()
                .unis(
                        booking.getCargo(request, input.trackingId().value(), viewer),
                        locations.getLocation(request, input.location().value()),
                        voyage)
                .with((cargo, location, foundVoyage) -> new Lookups(cargo, validate(input, cargo, location, foundVoyage)))
                .chain(lookups -> lookups.errors().isEmpty()
                        ? record(request, input, lookups.cargo(), viewer)
                        : Uni.createFrom().item(RegisterHandlingEventPayload.rejected(lookups.errors())));
    }

    /** The cargo the lookup found (null when unknown) and every rule it broke. */
    private record Lookups(Cargo cargo, List<UserError> errors) {}

    private static List<UserError> validate(
            RegisterHandlingEventInput input, Cargo cargo, Location location, Voyage voyage) {
        List<UserError> errors = new ArrayList<>();
        if (cargo == null) {
            errors.add(new UserError(
                    UserErrorCode.UNKNOWN_CARGO,
                    "No cargo has tracking id " + input.trackingId().value() + ".",
                    List.of("input", "trackingId")));
        }
        if (location == null) {
            errors.add(new UserError(
                    UserErrorCode.UNKNOWN_LOCATION,
                    "No location has UN/LOCODE " + input.location().value() + ".",
                    List.of("input", "location")));
        }
        boolean needsVoyage = input.type() == HandlingEventType.LOAD || input.type() == HandlingEventType.UNLOAD;
        if (needsVoyage && input.voyageNumber() == null) {
            errors.add(new UserError(
                    UserErrorCode.VOYAGE_REQUIRED,
                    input.type() + " events must name a voyage.",
                    List.of("input", "voyageNumber")));
        } else if (!needsVoyage && input.voyageNumber() != null) {
            errors.add(new UserError(
                    UserErrorCode.VOYAGE_NOT_ALLOWED,
                    input.type() + " events must not name a voyage.",
                    List.of("input", "voyageNumber")));
        } else if (needsVoyage && voyage == null) {
            errors.add(new UserError(
                    UserErrorCode.UNKNOWN_VOYAGE,
                    "No voyage has number " + input.voyageNumber() + ".",
                    List.of("input", "voyageNumber")));
        }
        if (input.completionTime().isAfter(Instant.now())) {
            errors.add(new UserError(
                    UserErrorCode.INVALID_COMPLETION_TIME,
                    "The completion time " + input.completionTime() + " is in the future.",
                    List.of("input", "completionTime")));
        }
        return errors;
    }

    private Uni<RegisterHandlingEventPayload> record(
            String request, RegisterHandlingEventInput input, Cargo cargo, Viewer viewer) {
        String key = input.idempotencyKey();
        Uni<HandlingRecord> existing =
                key == null ? Uni.createFrom().nullItem() : handling.findByIdempotencyKey(request, key);
        return existing.chain(original -> original != null
                ? Uni.createFrom().item(original)
                : handling.appendEvent(
                                request,
                                new NewHandling(
                                        input.trackingId().value(),
                                        input.type(),
                                        input.location().value(),
                                        input.voyageNumber(),
                                        input.completionTime()),
                                key)
                        .map(HandlingStore.Appended::event))
                .chain(event -> cargoOf(request, event, cargo, viewer)
                        .map(recordedCargo -> RegisterHandlingEventPayload.recorded(HandlingEvent.of(event), recordedCargo)));
    }

    /** A replayed key returns the original event, which may belong to another cargo than this input names. */
    private Uni<Cargo> cargoOf(String request, HandlingRecord event, Cargo requested, Viewer viewer) {
        return event.trackingId().equals(requested.trackingId().value())
                ? Uni.createFrom().item(requested)
                : booking.getCargo(request, event.trackingId(), viewer);
    }
}
