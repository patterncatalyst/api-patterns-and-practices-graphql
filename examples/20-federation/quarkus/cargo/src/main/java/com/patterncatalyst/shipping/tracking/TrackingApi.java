package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Query;
import org.eclipse.microprofile.graphql.Source;

import io.smallrye.graphql.api.Context;
import io.smallrye.graphql.api.federation.Resolver;
import io.smallrye.graphql.api.federation.link.Import;
import io.smallrye.graphql.api.federation.link.Link;
import io.smallrye.mutiny.Uni;

/**
 * The cargo subgraph: the part of the tracking view that the booking and routing
 * team owns. A failing source surfaces as an execution error:
 * {@link SourceUnavailableException} is shown to the client, any other
 * exception is masked. Every resolver that reads a source returns a
 * {@code Uni}, Mutiny's lazy single-value type, so SmallRye hands the engine a
 * pending result instead of blocking a thread on it.
 *
 * <p>The fields of a type that appears in a list are batch resolvers: a method
 * whose {@code @Source} parameter is a {@code List}. SmallRye turns such a method
 * into a graphql-java {@code DataLoader}, one per field per request, and calls
 * the method once with every parent the level collected.
 *
 * <p>The three {@code @Resolver} methods are the entity resolvers behind
 * {@code Query._entities}. With {@code federation.batch-resolving-enabled} each
 * takes the list of keys of every representation of its type in the request and
 * returns one entity per key, in order, so a gateway that sends many
 * representations causes one bulk source call.
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
    private final VoyageSource voyages;
    private final LocationSource locations;

    TrackingApi(BookingSource booking, RoutingSource routing, VoyageSource voyages, LocationSource locations) {
        this.booking = booking;
        this.routing = routing;
        this.voyages = voyages;
        this.locations = locations;
    }

    @Resolver
    @Description("Entity resolver: the cargo for each tracking id, in order.")
    public Uni<List<Cargo>> cargoByTrackingId(@Name("trackingId") List<String> trackingIds, Context context) {
        return booking.getCargos(context.getExecutionId(), trackingIds).map(Outcome::values);
    }

    @Resolver
    @Description("Entity resolver: the location for each UN/LOCODE, in order.")
    public Uni<List<Location>> locationByUnLocode(@Name("unLocode") List<String> unLocodes, Context context) {
        return locations.getLocations(context.getExecutionId(), unLocodes).map(Outcome::values);
    }

    @Resolver
    @Description("Entity resolver: the voyage for each voyage number, in order.")
    public Uni<List<Voyage>> voyageByNumber(@Name("number") List<String> numbers, Context context) {
        return voyages.getVoyages(context.getExecutionId(), numbers).map(Outcome::values);
    }

    @Query
    @Description("Look up one cargo by its tracking id. Null when no such cargo exists.")
    public Uni<Cargo> cargo(
            @Name("trackingId") @NonNull @Description("The tracking id issued at booking.") TrackingId trackingId,
            Context context) {
        return booking.getCargo(context.getExecutionId(), trackingId.value());
    }

    @Query
    @Description("Look up a location by UN/LOCODE. Null when unknown.")
    public Uni<Location> location(
            @Name("unLocode") @NonNull @Description("The UN/LOCODE to look up, for example `NLRTM`.")
                    UnLocode unLocode,
            Context context) {
        return locations.getLocation(context.getExecutionId(), unLocode.value());
    }

    @Query
    @Description("Look up a voyage by voyage number. Null when unknown.")
    public Uni<Voyage> voyage(
            @Name("voyageNumber") @NonNull @Description("The carrier's voyage number, for example `V100S`.")
                    String voyageNumber,
            Context context) {
        return voyages.getVoyage(context.getExecutionId(), voyageNumber);
    }

    @Query
    @NonNull
    @Description("List cargos, newest first, as a Relay connection.")
    public Uni<CargoConnection> cargos(
            @Name("first") @Description("Return the first N cargos.") Integer first,
            @Name("after") @Description("Return cargos after this cursor.") String after,
            @Name("last") @Description("Return the last N cargos.") Integer last,
            @Name("before") @Description("Return cargos before this cursor.") String before,
            @Name("routingStatus") @Description("Only cargos with this routing status.") RoutingStatus routingStatus,
            Context context) {
        Pagination.Page<Pagination.CargoKey> page = Pagination.page(first, after, last, before, Pagination::decodeCargo);
        return booking.listCargos(context.getExecutionId(), routingStatus, page).map(slice -> {
            List<CargoEdge> edges = slice.items().stream()
                    .map(row -> new CargoEdge(Pagination.encodeCargo(row.key()), row.trackingId()))
                    .toList();
            return new CargoConnection(
                    edges,
                    PageInfo.of(
                            slice.hasNext(),
                            slice.hasPrevious(),
                            edges.stream().map(CargoEdge::cursor).toList()),
                    slice.totalCount());
        });
    }

    @Description(
            "The cargo at this edge. Null when the cargo failed to resolve, so one bad item nulls its edge instead of the whole page.")
    public Uni<List<Cargo>> node(@Source List<CargoEdge> edges, Context context) {
        return booking
                .getCargos(context.getExecutionId(), edges.stream().map(CargoEdge::trackingId).toList())
                .map(Outcome::values);
    }

    @Description("The planned route. Null until the routing service has assigned one.")
    public Uni<List<Itinerary>> itinerary(@Source List<Cargo> cargos, Context context) {
        return routing.getItineraries(context.getExecutionId(), trackingIds(cargos)).map(Outcome::values);
    }

    @Description("The voyage that carries this leg. Null when the voyage service is unavailable.")
    public Uni<List<Voyage>> voyage(@Source List<Leg> legs, Context context) {
        return voyages.getVoyages(context.getExecutionId(), legs.stream().map(Leg::voyageNumber).toList())
                .map(Outcome::values);
    }

    @NonNull
    @Description("Where the cargo is loaded.")
    public Uni<List<Location>> loadLocation(@Source List<Leg> legs, Context context) {
        return locations
                .getLocations(context.getExecutionId(), legs.stream().map(Leg::loadUnLocode).toList())
                .map(Outcome::values);
    }

    @NonNull
    @Description("Where the cargo is unloaded.")
    public Uni<List<Location>> unloadLocation(@Source List<Leg> legs, Context context) {
        return locations
                .getLocations(context.getExecutionId(), legs.stream().map(Leg::unloadUnLocode).toList())
                .map(Outcome::values);
    }

    private static List<String> trackingIds(List<Cargo> cargos) {
        return cargos.stream().map(cargo -> cargo.trackingId().value()).toList();
    }
}
