package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Query;
import org.eclipse.microprofile.graphql.Source;

import io.smallrye.graphql.api.Context;
import io.smallrye.mutiny.Uni;

/**
 * The tracking view, Ch8 slice. Every resolver that reads a source returns a
 * {@code Uni}, Mutiny's lazy single-value type, so SmallRye hands the engine a
 * pending result instead of blocking a thread on it, and the engine is free to
 * start sibling fields before any of them finish.
 *
 * <p>Each resolver takes the SmallRye {@link Context} and reads
 * {@code getExecutionId()} on entry, while it is still on the request's
 * thread: the id travels to the source as an argument, because a continuation
 * that resumes after a delay does not run where the request started.
 */
@GraphQLApi
public class TrackingApi {

    private final BookingSource booking;
    private final RoutingSource routing;
    private final VoyageSource voyages;
    private final LocationSource locations;
    private final HandlingSource handling;
    private final DeliveryDerivation derivation;

    TrackingApi(
            BookingSource booking,
            RoutingSource routing,
            VoyageSource voyages,
            LocationSource locations,
            HandlingSource handling,
            DeliveryDerivation derivation) {
        this.booking = booking;
        this.routing = routing;
        this.voyages = voyages;
        this.locations = locations;
        this.handling = handling;
        this.derivation = derivation;
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
    @Description("Fetch any object by its global id (Relay Global Object Identification).")
    public Uni<Node> node(
            @Name("id") @Id @NonNull @Description("The global id of the object to fetch.") String id,
            Context context) {
        String request = context.getExecutionId();
        if (id.startsWith("cargo_")) {
            return booking.getCargo(request, id.substring("cargo_".length())).map(Node.class::cast);
        }
        if (id.startsWith("loc_")) {
            return locations.getLocation(request, id.substring("loc_".length())).map(Node.class::cast);
        }
        if (id.startsWith("voy_")) {
            return voyages.getVoyage(request, id.substring("voy_".length())).map(Node.class::cast);
        }
        if (id.startsWith("evt_")) {
            return handling.getEvent(request, id).<Node>map(record -> record == null ? null : HandlingEvent.of(record));
        }
        return Uni.createFrom().nullItem();
    }

    @Description("The planned route. Null until the routing service has assigned one.")
    public Uni<Itinerary> itinerary(@Source Cargo cargo, Context context) {
        return routing.getItinerary(context.getExecutionId(), cargo.trackingId().value());
    }

    @NonNull
    @Description("Delivery status derived from handling history.")
    public Uni<Delivery> delivery(@Source Cargo cargo, Context context) {
        String request = context.getExecutionId();
        String trackingId = cargo.trackingId().value();
        // The two inputs are independent, so they are fetched together; the
        // derivation itself calls no source.
        return Uni.combine()
                .all()
                .unis(routing.getItinerary(request, trackingId), handling.listEvents(request, trackingId))
                .with((itinerary, events) -> derivation.derive(cargo, itinerary, events));
    }

    @Description("The voyage that carries this leg. Null when the voyage service is unavailable.")
    public Uni<Voyage> voyage(@Source Leg leg, Context context) {
        return voyages.getVoyage(context.getExecutionId(), leg.voyageNumber());
    }

    @NonNull
    @Description("Where the cargo is loaded.")
    public Uni<Location> loadLocation(@Source Leg leg, Context context) {
        return locations.getLocation(context.getExecutionId(), leg.loadUnLocode());
    }

    @NonNull
    @Description("Where the cargo is unloaded.")
    public Uni<Location> unloadLocation(@Source Leg leg, Context context) {
        return locations.getLocation(context.getExecutionId(), leg.unloadUnLocode());
    }
}
