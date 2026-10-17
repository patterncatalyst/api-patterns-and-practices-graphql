package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

import io.smallrye.graphql.api.federation.FieldSet;
import io.smallrye.graphql.api.federation.Key;

/**
 * A reference to a location. The cargo subgraph owns {@code Location}; this
 * subgraph names a place by its key, and {@code resolvable = false} tells a
 * gateway that this subgraph has no entity resolver for it, so the rest of the
 * fields come from the cargo subgraph.
 */
@Type("Location")
@Key(fields = @FieldSet("unLocode"), resolvable = false)
@Description("A port or terminal, identified by its UN/LOCODE.")
public record Location(@NonNull @Description("The UN/LOCODE, for example `NLRTM`.") UnLocode unLocode) {}
