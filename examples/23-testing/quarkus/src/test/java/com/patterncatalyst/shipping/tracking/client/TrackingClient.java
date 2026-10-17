package com.patterncatalyst.shipping.tracking.client;

import java.util.List;

import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Query;

import io.smallrye.graphql.client.typesafe.api.ErrorOr;
import io.smallrye.graphql.client.typesafe.api.GraphQLClientApi;

/**
 * The typesafe client of Chapter 22, here as a consumer of the endpoint under
 * test: each method is an operation, and each return type is its selection set.
 */
@GraphQLClientApi
public interface TrackingClient {

    record Cargo(TrackingId trackingId, String description) {}

    /** Only the tracking id, for a page where an edge's node may be an error. */
    record CargoSummary(TrackingId trackingId) {}

    record CargoEdge(String cursor, ErrorOr<CargoSummary> node) {}

    record CargoPage(List<CargoEdge> edges) {}

    @Query("cargo")
    Cargo cargo(@NonNull @Name("trackingId") TrackingId trackingId);

    @Query("cargos")
    CargoPage cargos(@Name("first") int first);
}
