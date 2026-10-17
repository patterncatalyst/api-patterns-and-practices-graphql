package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Query;

/**
 * The tracking view, Ch0 slice: one query returning one canned cargo. The
 * method name becomes the field name ({@code cargo}); the class is the
 * GraphQL API surface, discovered at build time.
 */
@GraphQLApi
public class TrackingApi {

    private static final Location NEW_YORK =
            new Location("loc_USNYC", new UnLocode("USNYC"), "New York", "US");
    private static final Location ROTTERDAM =
            new Location("loc_NLRTM", new UnLocode("NLRTM"), "Rotterdam", "NL");
    private static final Cargo ABC123 = new Cargo(
            "cargo_ABC123",
            new TrackingId("ABC123"),
            "Palletized electronics",
            NEW_YORK,
            ROTTERDAM);

    @Query
    @Description("Look up one cargo by its tracking id. Null when no such cargo exists.")
    public Cargo cargo(
            @Name("trackingId") @NonNull @Description("The tracking id issued at booking.") TrackingId trackingId) {
        return ABC123.trackingId().equals(trackingId) ? ABC123 : null;
    }
}
