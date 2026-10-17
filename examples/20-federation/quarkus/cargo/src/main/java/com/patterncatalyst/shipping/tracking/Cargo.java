package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

import io.smallrye.graphql.api.federation.FieldSet;
import io.smallrye.graphql.api.federation.Key;

/**
 * What the booking service owns: the cargo and its route specification. The
 * {@code itinerary} and {@code delivery} fields belong to other services, so
 * they are not components of this record; {@link TrackingApi} resolves
 * {@code itinerary} from the routing source. {@code delivery} and
 * {@code handlingHistory} belong to the handling subgraph, which extends the
 * {@code Cargo} entity by its {@code trackingId} key.
 */
@Type("Cargo")
@Key(fields = @FieldSet("trackingId"))
@Description("A consignment of goods being shipped, tracked end to end by its tracking id.")
public record Cargo(
        String id,
        @NonNull @Description("The public tracking identifier.") TrackingId trackingId,
        @NonNull @Description("Free-text description of the goods.") String description,
        @NonNull @Description("Where the cargo was booked from.") Location origin,
        @NonNull @Description("Where the cargo is booked to.") Location destination,
        @NonNull @Description("What the customer asked for and the route must satisfy.")
                RouteSpecification routeSpecification)
        implements Node {

    @Override
    @Id
    @NonNull
    @Description("The globally unique identifier of this cargo.")
    public String getId() {
        return id;
    }
}
