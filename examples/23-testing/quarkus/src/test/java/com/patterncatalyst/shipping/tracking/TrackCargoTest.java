package com.patterncatalyst.shipping.tracking;

import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.everyItem;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;

import java.util.Map;

import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;

/**
 * Operation layer. The four documents Chapter 22's clients send, posted over
 * HTTP to the application in process and read the way a client reads them:
 * {@code data} beside {@code errors}, never the status line alone.
 */
@QuarkusTest
class TrackCargoTest {

    @Test
    void trackCargoReturnsTheCargoItsPlacesAndItsDelivery() {
        Documents.postDocument("track-cargo", Map.of("id", "ABC123"))
                .body("errors", nullValue())
                .body("data.cargo.trackingId", equalTo("ABC123"))
                .body("data.cargo.description", equalTo("Palletized electronics"))
                .body("data.cargo.origin.name", equalTo("New York"))
                .body("data.cargo.destination.name", equalTo("Rotterdam"))
                .body("data.cargo.delivery.transportStatus", equalTo("ONBOARD_CARRIER"))
                .body("data.cargo.delivery.routingStatus", equalTo("ROUTED"));
    }

    @Test
    void trackCargoBriefIsASubsetOfTrackCargo() {
        Documents.postDocument("track-cargo-brief", Map.of("id", "ABC123"))
                .body("errors", nullValue())
                .body("data.cargo.id", equalTo("cargo_ABC123"))
                .body("data.cargo.delivery.transportStatus", equalTo("ONBOARD_CARRIER"));
    }

    @Test
    void registerHandlingAcceptsAnEventAndReturnsNoUserErrors() {
        Map<String, Object> input = Map.of(
                "trackingId", "DEF456",
                "type", "CUSTOMS",
                "location", "NLRTM",
                "completionTime", "2026-10-09T16:00:00Z",
                "idempotencyKey", "ch23-test-operations");

        Documents.postDocument("register-handling", Map.of("input", input))
                .body("errors", nullValue())
                .body("data.registerHandlingEvent.handlingEvent.id", notNullValue())
                .body("data.registerHandlingEvent.userErrors", hasSize(0))
                .body("data.registerHandlingEvent.cargo.id", equalTo("cargo_DEF456"));
    }

    @Test
    void listCargosReturnsSixEdgesAndReportsTheBookingOutageAtEachNode() {
        // One cargo cannot be loaded. SmallRye resolves a page's nodes in one
        // bulk call, so the outage reaches all six nodes of the page.
        Documents.postDocument("list-cargos", null)
                .body("data.cargos.edges", hasSize(6))
                .body("errors", hasSize(6))
                .body("errors.extensions.code", everyItem(equalTo("SERVICE_UNAVAILABLE")))
                .body("errors.path[0]", contains("cargos", "edges", 0, "node"));
    }
}
