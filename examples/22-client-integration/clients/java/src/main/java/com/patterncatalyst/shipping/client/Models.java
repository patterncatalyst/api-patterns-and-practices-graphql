package com.patterncatalyst.shipping.client;

import java.time.Instant;
import java.util.List;

import org.eclipse.microprofile.graphql.Input;
import org.eclipse.microprofile.graphql.NonNull;

import io.smallrye.graphql.client.typesafe.api.ErrorOr;

/**
 * The shapes the client asks for. A typesafe client selects exactly the fields of
 * the Java type it returns, so each record below is also a selection set.
 */
public final class Models {

    private Models() {
    }

    public enum TransportStatus { NOT_RECEIVED, IN_PORT, ONBOARD_CARRIER, CLAIMED, UNKNOWN }

    public enum HandlingEventType { RECEIVE, LOAD, UNLOAD, CUSTOMS, CLAIM }

    public record Delivery(TransportStatus transportStatus) {
    }

    public record Cargo(TrackingId trackingId, String description, Delivery delivery) {
    }

    /** Only the tracking id, for a page where one edge may fail. */
    public record CargoSummary(TrackingId trackingId) {
    }

    /** The node is an {@link ErrorOr}: the value, or the errors reported at its path. */
    public record CargoEdge(String cursor, ErrorOr<CargoSummary> node) {
    }

    public record CargoPage(List<CargoEdge> edges) {
    }

    @Input("RegisterHandlingEventInput")
    public record RegisterInput(
            @NonNull TrackingId trackingId,
            @NonNull HandlingEventType type,
            @NonNull UnLocode location,
            String voyageNumber,
            @NonNull Instant completionTime) {
    }

    public record HandlingEvent(String id) {
    }

    public record UserError(String code, String message) {
    }

    public record RegisterPayload(HandlingEvent handlingEvent, Cargo cargo, List<UserError> userErrors) {
    }
}
