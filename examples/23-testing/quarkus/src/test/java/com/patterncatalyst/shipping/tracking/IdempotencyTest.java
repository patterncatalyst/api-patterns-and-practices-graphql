package com.patterncatalyst.shipping.tracking;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.Map;

import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;

/** Retrying a registration with the same idempotency key writes one event. */
@QuarkusTest
class IdempotencyTest {

    private static final Map<String, Object> REGISTRATION = Map.of(
            "trackingId", "DEF456",
            "type", "CUSTOMS",
            "location", "NLRTM",
            "completionTime", "2026-10-09T16:00:00Z",
            "idempotencyKey", "ch23-test-d1");

    @Inject
    SourceCalls calls;

    @Test
    void replayingARegistrationReturnsTheSameEventAndWritesOnce() {
        calls.reset();

        String first = Documents.postDocument("register-handling", Map.of("input", REGISTRATION))
                .extract()
                .path("data.registerHandlingEvent.handlingEvent.id");
        String second = Documents.postDocument("register-handling", Map.of("input", REGISTRATION))
                .extract()
                .path("data.registerHandlingEvent.handlingEvent.id");

        assertEquals(first, second, "the replay answers with the first event");
        long writes = calls.snapshot().stream()
                .filter(call -> call.source().equals("handling") && call.op().equals("appendEvent"))
                .count();
        assertEquals(1, writes, "one handling.appendEvent for two requests");
    }
}
