package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Ignore;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

import io.smallrye.graphql.api.federation.FieldSet;
import io.smallrye.graphql.api.federation.Key;

/**
 * The handling subgraph's view of a cargo. {@code Cargo} is an entity the cargo
 * subgraph owns; this subgraph shares its {@code trackingId} key and adds the
 * fields it owns, {@code delivery} and {@code handlingHistory}, which
 * {@link TrackingApi} resolves. The route specification is what the delivery
 * derivation reads from the booking source; it is not part of this subgraph's
 * schema.
 */
@Type("Cargo")
@Key(fields = @FieldSet("trackingId"))
@Description("A consignment of goods being shipped, tracked end to end by its tracking id.")
public record Cargo(
        @NonNull @Description("The public tracking identifier.") TrackingId trackingId,
        @Ignore RouteSpecification routeSpecification) {}
