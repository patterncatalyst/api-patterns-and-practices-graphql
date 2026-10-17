package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Mutation;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Source;

import io.smallrye.graphql.api.Context;
import io.smallrye.mutiny.Uni;

/**
 * The write surface of the tracking view, and the fields of {@code HandlingEvent}
 * that other services own. A mutation is an ordinary resolver on the
 * {@code Mutation} root; what differs is the engine's rule: the top-level
 * mutation fields of one request run one after another.
 */
@GraphQLApi
public class HandlingApi {

    private final HandlingRegistration registration;
    private final BookingSource booking;
    private final LocationSource locations;
    private final VoyageSource voyages;

    HandlingApi(
            HandlingRegistration registration, BookingSource booking, LocationSource locations, VoyageSource voyages) {
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

    @Description("The cargo that was handled. Null when the cargo service is unavailable.")
    public Uni<Cargo> cargo(@Source HandlingEvent event, Context context) {
        return booking.getCargo(context.getExecutionId(), event.trackingId().value());
    }

    @NonNull
    @Description("Where it occurred.")
    public Uni<Location> location(@Source HandlingEvent event, Context context) {
        return locations.getLocation(context.getExecutionId(), event.unLocode());
    }

    @Description("The voyage involved. Null for RECEIVE, CUSTOMS and CLAIM.")
    public Uni<Voyage> voyage(@Source HandlingEvent event, Context context) {
        return event.voyageNumber() == null
                ? Uni.createFrom().nullItem()
                : voyages.getVoyage(context.getExecutionId(), event.voyageNumber());
    }
}
