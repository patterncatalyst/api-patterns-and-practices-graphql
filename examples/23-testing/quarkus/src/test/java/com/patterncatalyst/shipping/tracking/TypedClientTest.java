package com.patterncatalyst.shipping.tracking;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.URL;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.patterncatalyst.shipping.tracking.client.TrackingClient;
import com.patterncatalyst.shipping.tracking.client.TrackingId;

import io.quarkus.test.common.http.TestHTTPResource;
import io.quarkus.test.junit.QuarkusTest;
import io.smallrye.graphql.client.typesafe.api.TypesafeGraphQLClientBuilder;

/**
 * Operation layer through a client library. The SmallRye typesafe client builds
 * its requests from the interface and reads {@code data} and {@code errors}
 * into the return type; {@code @TestHTTPResource} supplies the address of the
 * application under test.
 */
@QuarkusTest
class TypedClientTest {

    @TestHTTPResource("/graphql")
    URL endpoint;

    TrackingClient client;

    @BeforeEach
    void connect() throws Exception {
        client = TypesafeGraphQLClientBuilder.newBuilder()
                .endpoint(endpoint.toString())
                .build(TrackingClient.class);
    }

    @Test
    void cargoQueryReturnsTheTypedCargo() {
        TrackingClient.Cargo cargo = client.cargo(TrackingId.of("ABC123"));

        assertEquals("ABC123", cargo.trackingId().value());
        assertEquals("Palletized electronics", cargo.description());
    }

    @Test
    void aFailedNodeArrivesAsAnErrorOrWithItsMessage() {
        TrackingClient.CargoPage page = client.cargos(10);

        assertEquals(6, page.edges().size());
        List<TrackingClient.CargoEdge> failed =
                page.edges().stream().filter(edge -> !edge.node().isPresent()).toList();
        assertFalse(failed.isEmpty(), "the booking outage reaches the page");
        assertTrue(
                failed.getFirst().node().getErrors().stream()
                        .anyMatch(error -> "booking service unavailable".equals(error.getMessage())),
                "the error keeps the message the server chose to show");
    }
}
