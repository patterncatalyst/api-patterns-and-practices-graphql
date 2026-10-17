package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

import io.smallrye.graphql.api.federation.FieldSet;
import io.smallrye.graphql.api.federation.Key;

@Type("Location")
@Key(fields = @FieldSet("unLocode"))
@Description("A port or terminal, identified by its UN/LOCODE.")
public record Location(
        String id,
        @NonNull @Description("The UN/LOCODE, for example `NLRTM`.") UnLocode unLocode,
        @NonNull @Description("The human-readable name, for example `Rotterdam`.") String name,
        @NonNull @Description("The ISO 3166-1 alpha-2 country code, for example `NL`.") String country)
        implements Node {

    @Override
    @Id
    @NonNull
    @Description("The globally unique identifier of this location.")
    public String getId() {
        return id;
    }
}
