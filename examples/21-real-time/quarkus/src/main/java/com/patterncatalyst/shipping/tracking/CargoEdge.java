package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Ignore;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

/**
 * An edge holds the cursor and the key of the cargo it points at. The
 * {@code node} field is not a component: {@link TrackingApi} loads the cargo
 * from the booking source when a query selects it, so an edge whose cargo
 * cannot be loaded fails alone.
 */
@Type("CargoEdge")
@Description("A cargo and its cursor.")
public record CargoEdge(
        @NonNull @Description("An opaque cursor for this edge.") String cursor, @Ignore String trackingId) {}
