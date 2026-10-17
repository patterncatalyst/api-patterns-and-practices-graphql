package com.patterncatalyst.shipping.tracking;

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
import io.smallrye.graphql.api.Subscription;
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;

/**
 * The write surface of the tracking view, and the fields of {@code HandlingEvent}
 * that other services own. A mutation is an ordinary resolver on the
 * {@code Mutation} root; what differs is the engine's rule: the top-level
 * mutation fields of one request run one after another. The {@code Subscription}
 * root has one field, {@code cargoHandled}: a {@link Multi} the engine subscribes
 * to, executing the selection set once for each event it emits.
 */
@GraphQLApi
public class HandlingApi {

    private final HandlingRegistration registration;
    private final BookingSource booking;
    private final LocationSource locations;
    private final VoyageSource voyages;
    private final HandlingStore store;

    HandlingApi(
            HandlingRegistration registration,
            BookingSource booking,
            LocationSource locations,
            VoyageSource voyages,
            HandlingStore store) {
        this.store = store;
        this.registration = registration;
        this.booking = booking;
        this.locations = locations;
        this.voyages = voyages;
    }

    @Mutation
    @NonNull
    @Description("Record that a cargo was handled. Domain failures are returned in `userErrors`.")
    public Uni<RegisterHandlingEventPayload> registerHandlingEvent(
            @Name("input") @NonNull @Description("The handling to record.") RegisterHandlingEventInput input,
            Context context) {
        return registration.register(context.getExecutionId(), input);
    }

    @Subscription
    @NonNull
    @Description("Emits each new handling event for one cargo as it is registered.")
    public Multi<HandlingEvent> cargoHandled(
            @Name("trackingId") @NonNull @Description("The tracking id of the cargo to watch.") TrackingId trackingId) {
        return store.watch(trackingId.value(), HandlingStore.Channel.GRAPHQL, null).map(HandlingEvent::of);
    }

    @Description("The cargo that was handled. Null when the cargo service is unavailable.")
    public Uni<List<Cargo>> cargo(@Source List<HandlingEvent> events, Context context) {
        return booking.getCargos(
                        context.getExecutionId(),
                        events.stream().map(event -> event.trackingId().value()).toList())
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
