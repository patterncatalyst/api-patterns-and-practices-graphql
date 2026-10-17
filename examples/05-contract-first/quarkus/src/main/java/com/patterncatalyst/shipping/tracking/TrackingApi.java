package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Query;

/**
 * The tracking view, Ch5 slice: the root fields {@code cargo}, {@code location},
 * {@code voyage} and {@code node}. Each method name becomes a field name; the
 * class is the GraphQL API surface, discovered at build time. These are the
 * only resolvers: every other field is read from the object it hangs off.
 */
@GraphQLApi
public class TrackingApi {

    private final TrackingData data;

    TrackingApi(TrackingData data) {
        this.data = data;
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
}
