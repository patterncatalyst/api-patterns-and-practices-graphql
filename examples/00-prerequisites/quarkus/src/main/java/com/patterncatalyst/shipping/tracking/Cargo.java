package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("Cargo")
@Description("A consignment of goods being shipped, tracked end to end by its tracking id.")
public record Cargo(
        String id,
        @NonNull @Description("The public tracking identifier.") TrackingId trackingId,
        @NonNull @Description("Free-text description of the goods.") String description,
        @NonNull @Description("Where the cargo was booked from.") Location origin,
        @NonNull @Description("Where the cargo is booked to.") Location destination)
        implements Node {

    @Override
    @Id
    @NonNull
    @Description("The globally unique identifier of this cargo.")
    public String getId() {
        return id;
    }
}
