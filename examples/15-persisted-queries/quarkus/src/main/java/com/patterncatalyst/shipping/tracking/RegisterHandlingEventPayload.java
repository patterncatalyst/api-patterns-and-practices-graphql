package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("RegisterHandlingEventPayload")
@Description("Result of `Mutation.registerHandlingEvent`.")
public record RegisterHandlingEventPayload(
        @Description("The recorded event. Null when `userErrors` is non-empty.") HandlingEvent handlingEvent,
        @Description("The cargo with its delivery state recomputed. Null when `userErrors` is non-empty.")
                Cargo cargo,
        @NonNull
                @Description(
                        "Domain validation failures returned as data; empty on success. Distinct from the response's top-level `errors`.")
                List<@NonNull UserError> userErrors) {

    static RegisterHandlingEventPayload rejected(List<UserError> userErrors) {
        return new RegisterHandlingEventPayload(null, null, userErrors);
    }

    static RegisterHandlingEventPayload recorded(HandlingEvent event, Cargo cargo) {
        return new RegisterHandlingEventPayload(event, cargo, List.of());
    }
}
