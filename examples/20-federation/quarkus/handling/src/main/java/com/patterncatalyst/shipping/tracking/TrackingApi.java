package com.patterncatalyst.shipping.tracking;

import java.util.List;
import java.util.stream.IntStream;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Source;

import io.smallrye.graphql.api.Context;
import io.smallrye.graphql.api.federation.Resolver;
import io.smallrye.graphql.api.federation.link.Import;
import io.smallrye.graphql.api.federation.link.Link;
import io.smallrye.mutiny.Uni;

/**
 * The handling subgraph's fields on {@code Cargo}, and the entity resolvers
 * behind {@code Query._entities}. A failing source surfaces as an execution
 * error: {@link SourceUnavailableException} is shown to the client, any other
 * exception is masked.
 *
 * <p>{@code delivery} is a batch resolver: a method whose {@code @Source}
 * parameter is a {@code List}. SmallRye turns it into a graphql-java
 * {@code DataLoader}, one per field per request, and calls the method once with
 * every cargo the level collected. The two {@code @Resolver} methods are the
 * entity resolvers; with {@code federation.batch-resolving-enabled} each takes
 * the keys of every representation of its type in the request and returns one
 * entity per key, in order.
 *
 * <p>Each resolver takes the SmallRye {@link Context} and reads
 * {@code getExecutionId()} on entry, while it is still on the request's
 * thread: the id travels to the source as an argument, because a continuation
 * that resumes after a delay does not run where the request started.
 */
@GraphQLApi
@Link(
        url = Link.FEDERATION_SPEC_URL + "/v2.7",
        _import = {@Import(name = "@key"), @Import(name = "@shareable")})
public class TrackingApi {

    private final BookingSource booking;
    private final RoutingSource routing;
    private final HandlingSource handling;
    private final DeliveryDerivation derivation;

    TrackingApi(
            BookingSource booking, RoutingSource routing, HandlingSource handling, DeliveryDerivation derivation) {
        this.booking = booking;
        this.routing = routing;
        this.handling = handling;
        this.derivation = derivation;
    }

    @Resolver
    @Description("Entity resolver: the cargo for each tracking id, in order.")
    public Uni<List<Cargo>> cargoByTrackingId(@Name("trackingId") List<String> trackingIds, Context context) {
        return booking.getCargos(context.getExecutionId(), trackingIds).map(Outcome::values);
    }

    @Resolver
    @Description("Entity resolver: the handling event for each id, in order.")
    public Uni<List<HandlingEvent>> handlingEventById(@Name("id") List<String> ids, Context context) {
        String request = context.getExecutionId();
        return Uni.join()
                .all(ids.stream()
                        .map(id -> handling
                                .getEvent(request, id)
                                .map(record -> record == null ? null : HandlingEvent.of(record)))
                        .toList())
                .andFailFast();
    }

    @NonNull
    @Description("Handling events for this cargo, newest first, as a Relay connection.")
    public Uni<HandlingEventConnection> handlingHistory(
            @Source Cargo cargo,
            @Name("first") @Description("Return the first N events.") Integer first,
            @Name("after") @Description("Return events after this cursor.") String after,
            @Name("last") @Description("Return the last N events.") Integer last,
            @Name("before") @Description("Return events before this cursor.") String before,
            Context context) {
        Pagination.Page<Pagination.EventKey> page = Pagination.page(first, after, last, before, Pagination::decodeEvent);
        return handling.pageEvents(context.getExecutionId(), cargo.trackingId().value(), page).map(slice -> {
            List<HandlingEventEdge> edges = slice.items().stream()
                    .map(record -> new HandlingEventEdge(Pagination.encodeEvent(record.key()), HandlingEvent.of(record)))
                    .toList();
            return new HandlingEventConnection(
                    edges,
                    PageInfo.of(
                            slice.hasNext(),
                            slice.hasPrevious(),
                            edges.stream().map(HandlingEventEdge::cursor).toList()),
                    slice.totalCount());
        });
    }

    @NonNull
    @Description("Delivery status derived from handling history.")
    public Uni<List<Delivery>> delivery(@Source List<Cargo> cargos, Context context) {
        String request = context.getExecutionId();
        List<String> ids = cargos.stream().map(cargo -> cargo.trackingId().value()).toList();
        // The two inputs are independent, so they are fetched together; the
        // derivation itself calls no source.
        return Uni.combine()
                .all()
                .unis(routing.getItineraries(request, ids), handling.listEventsFor(request, ids))
                .with((itineraries, events) -> {
                    List<Itinerary> planned = Outcome.values(itineraries);
                    List<List<HandlingRecord>> recorded = Outcome.values(events);
                    return IntStream.range(0, cargos.size())
                            .mapToObj(i -> derivation.derive(cargos.get(i), planned.get(i), recorded.get(i)))
                            .toList();
                });
    }
}
