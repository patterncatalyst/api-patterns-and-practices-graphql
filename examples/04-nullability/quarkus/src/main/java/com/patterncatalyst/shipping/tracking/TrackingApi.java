package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Query;
import org.eclipse.microprofile.graphql.Source;

/**
 * The tracking view, Ch4 slice. The root fields {@code cargo}, {@code location},
 * {@code voyage} and {@code node} read the seed. The {@code @Source} methods are
 * the field resolvers of this chapter: {@code Leg.voyage}, {@code Leg.loadLocation},
 * {@code Leg.unloadLocation} and {@code Cargo.delivery} call a source, and what
 * the source does (answer, return null, throw) decides what the response holds.
 * Every other field is read from the object it hangs off.
 */
@GraphQLApi
public class TrackingApi {

    private final TrackingData data;
    private final VoyageSource voyages;
    private final LocationSource locations;
    private final DeliverySource deliveries;

    TrackingApi(TrackingData data, VoyageSource voyages, LocationSource locations, DeliverySource deliveries) {
        this.data = data;
        this.voyages = voyages;
        this.locations = locations;
        this.deliveries = deliveries;
    }

    @Query
    @Description("Look up one cargo by its tracking id. Null when no such cargo exists.")
    public Cargo cargo(
            @Name("trackingId") @NonNull @Description("The tracking id issued at booking.") TrackingId trackingId) {
        return data.cargo(trackingId.value());
    }

    @Query
    @Description("Look up a location by UN/LOCODE. Null when unknown.")
    public Location location(
            @Name("unLocode") @NonNull @Description("The UN/LOCODE to look up, for example `NLRTM`.")
                    UnLocode unLocode) {
        return data.location(unLocode.value());
    }

    @Query
    @Description("Look up a voyage by voyage number. Null when unknown.")
    public Voyage voyage(
            @Name("voyageNumber") @NonNull @Description("The carrier's voyage number, for example `V100S`.")
                    String voyageNumber) {
        return data.voyage(voyageNumber);
    }

    @Query
    @Description("Fetch any object by its global id (Relay Global Object Identification).")
    public Node node(
            @Name("id") @Id @NonNull @Description("The global id of the object to fetch.") String id) {
        return data.node(id);
    }

    @Description("The voyage that carries this leg. Null when the voyage service is unavailable.")
    public Voyage voyage(@Source Leg leg) {
        return voyages.getVoyage(leg.voyageNumber());
    }

    @Description("Where the cargo is loaded.")
    @NonNull
    public Location loadLocation(@Source Leg leg) {
        return locations.getLocation(leg.loadUnLocode());
    }

    @Description("Where the cargo is unloaded.")
    @NonNull
    public Location unloadLocation(@Source Leg leg) {
        return locations.getLocation(leg.unloadUnLocode());
    }

    @Description("Delivery status derived from handling history.")
    @NonNull
    public Delivery delivery(@Source Cargo cargo) {
        return deliveries.getDelivery(cargo.trackingId().value());
    }
}
