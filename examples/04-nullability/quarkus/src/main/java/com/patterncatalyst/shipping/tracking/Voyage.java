package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("Voyage")
@Description("A scheduled carrier movement made up of one or more legs.")
public record Voyage(
        String id,
        @NonNull @Description("The carrier's voyage number, for example `V100S`.") String number,
        @NonNull @Description("The scheduled movements of this voyage in departure order.")
                List<@NonNull CarrierMovement> schedule)
        implements Node {

    @Override
    @Id
    @NonNull
    @Description("The globally unique identifier of this voyage.")
    public String getId() {
        return id;
    }
}
