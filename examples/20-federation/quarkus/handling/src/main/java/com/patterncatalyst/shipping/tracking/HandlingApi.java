package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Mutation;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Source;

import io.smallrye.graphql.api.Context;
import io.smallrye.mutiny.Uni;

/**
 * The write surface of the handling subgraph, and the fields of {@code HandlingEvent}
 * that other services own. A mutation is an ordinary resolver on the
 * {@code Mutation} root; what differs is the engine's rule: the top-level
 * mutation fields of one request run one after another.
 */
@GraphQLApi
public class HandlingApi {

    private final HandlingRegistration registration;
    private final BookingSource booking;
    HandlingApi(HandlingRegistration registration, BookingSource booking) {
        this.registration = registration;
        this.booking = booking;
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
    public Uni<List<Cargo>> cargo(@Source List<HandlingEvent> events, Context context) {
        return booking.getCargos(
                        context.getExecutionId(),
                        events.stream().map(event -> event.trackingId().value()).toList())
                .map(Outcome::values);
    }

    /** A reference: the key is all this subgraph holds of a location; the cargo subgraph resolves the rest. */
    @NonNull
    @Description("Where it occurred.")
    public Location location(@Source HandlingEvent event) {
        return new Location(new UnLocode(event.unLocode()));
    }

    /** A reference, like {@link #location}; null for the events that name no voyage. */
    @Description("The voyage involved. Null for RECEIVE, CUSTOMS and CLAIM.")
    public Voyage voyage(@Source HandlingEvent event) {
        return event.voyageNumber() == null ? null : new Voyage(event.voyageNumber());
    }
}
