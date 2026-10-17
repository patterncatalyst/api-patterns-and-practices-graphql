package com.patterncatalyst.shipping.client;

import org.eclipse.microprofile.graphql.Mutation;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Query;

import com.patterncatalyst.shipping.client.Models.Cargo;
import com.patterncatalyst.shipping.client.Models.CargoPage;
import com.patterncatalyst.shipping.client.Models.RegisterInput;
import com.patterncatalyst.shipping.client.Models.RegisterPayload;

import io.smallrye.graphql.client.typesafe.api.GraphQLClientApi;

/**
 * The typesafe client: an interface whose methods are operations. The method name
 * (or {@code @Query}/{@code @Mutation} value) is the root field, the parameters
 * are its arguments, and the return type defines the selection. The endpoint and
 * headers come from the {@code tracking} configuration key.
 */
@GraphQLClientApi(configKey = "tracking")
public interface TrackingClient {

    @Query("cargo")
    Cargo cargo(@NonNull @Name("trackingId") TrackingId trackingId);

    @Query("cargos")
    CargoPage cargos(@Name("first") int first);

    @Mutation("registerHandlingEvent")
    RegisterPayload registerHandlingEvent(@NonNull @Name("input") RegisterInput input);
}
