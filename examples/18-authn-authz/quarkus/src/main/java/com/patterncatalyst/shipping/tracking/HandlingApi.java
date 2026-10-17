package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Objects;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Mutation;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Source;

import io.smallrye.graphql.api.Context;
import io.smallrye.mutiny.Uni;
import jakarta.annotation.security.RolesAllowed;

/**
 * The write surface of the tracking view, and the fields of {@code HandlingEvent}
 * that other services own. A mutation is an ordinary resolver on the
 * {@code Mutation} root; what differs is the engine's rule: the top-level
 * mutation fields of one request run one after another. The mutation and
 * {@code HandlingEvent.registrationTime} need the {@code operator} role; the
 * role check is the {@code @RolesAllowed} annotation, enforced by Quarkus
 * security before the method runs.
 */
@GraphQLApi
@SecurityErrors
public class HandlingApi {

    private final HandlingRegistration registration;
    private final BookingSource booking;
    private final LocationSource locations;
    private final VoyageSource voyages;
    private final Viewers viewers;

    HandlingApi(
            HandlingRegistration registration,
            BookingSource booking,
            LocationSource locations,
            VoyageSource voyages,
            Viewers viewers) {
        this.registration = registration;
        this.booking = booking;
        this.locations = locations;
        this.voyages = voyages;
        this.viewers = viewers;
    }

    @Mutation
    @RolesAllowed("operator")
    @NonNull
    @Description("Record that a cargo was handled. Domain failures are returned in `userErrors`.")
    public Uni<RegisterHandlingEventPayload> registerHandlingEvent(
            @Name("input") @NonNull @Description("The handling to record.") RegisterHandlingEventInput input,
            Context context) {
        return registration.register(context.getExecutionId(), input, viewers.current());
    }

    @RolesAllowed("operator")
    @NonNull
    @Description("When the event was registered in the system.")
    public Instant registrationTime(@Source HandlingEvent event) {
        return event.registrationTime();
    }

    @Description("The cargo that was handled. Null when the cargo service is unavailable.")
    public Uni<List<Cargo>> cargo(@Source List<HandlingEvent> events, Context context) {
        return booking.getCargos(
                        context.getExecutionId(),
                        events.stream().map(event -> event.trackingId().value()).toList(),
                        viewers.current())
                .map(Outcome::values);
    }

    @NonNull
    @Description("Where it occurred.")
    public Uni<List<Location>> location(@Source List<HandlingEvent> events, Context context) {
        return locations
                .getLocations(context.getExecutionId(), events.stream().map(HandlingEvent::unLocode).toList())
                .map(Outcome::values);
    }

    @Description("The voyage involved. Null for RECEIVE, CUSTOMS and CLAIM.")
    public Uni<List<Voyage>> voyage(@Source List<HandlingEvent> events, Context context) {
        // Events without a voyage never reach the voyage service: only the
        // others are asked for, and their voyages are put back in order.
        List<String> numbers =
                events.stream().map(HandlingEvent::voyageNumber).filter(Objects::nonNull).toList();
        if (numbers.isEmpty()) {
            return Uni.createFrom().item(Collections.nCopies(events.size(), null));
        }
        return voyages.getVoyages(context.getExecutionId(), numbers).map(outcomes -> {
            Iterator<Voyage> found = Outcome.values(outcomes).iterator();
            return events.stream()
                    .map(event -> event.voyageNumber() == null ? null : found.next())
                    .toList();
        });
    }
}
