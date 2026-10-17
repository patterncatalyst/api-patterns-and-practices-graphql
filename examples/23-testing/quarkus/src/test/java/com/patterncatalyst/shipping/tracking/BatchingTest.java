package com.patterncatalyst.shipping.tracking;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;

/**
 * Behaviour the schema cannot show: how many calls reach the sources. The test
 * reads the source-call log the application already keeps.
 */
@QuarkusTest
class BatchingTest {

    @Inject
    SourceCalls calls;

    @Test
    void fanOutMakesEightSourceCallsUnderOneRequestId() {
        calls.reset();

        Documents.postDocument("fan-out", null);

        List<SourceCall> log = calls.snapshot();
        assertEquals(8, log.size(), "FanOut calls the owners eight times");
        Set<String> requests = log.stream().map(SourceCall::request).collect(Collectors.toSet());
        assertEquals(1, requests.size(), "every call carries the request id of the one request");
    }

    @Test
    void fanOutAsksEachOwnerOnceForAllFourCargos() {
        calls.reset();

        Documents.postDocument("fan-out", null);

        List<String> entries = calls.snapshot().stream()
                .map(call -> call.source() + "." + call.op() + ":" + call.key())
                .sorted()
                .toList();
        List<String> expected = List.of(
                        "booking.getCargos:DEF456+STU678+VWX901+XYZ789",
                        "booking.listCargos:*",
                        "handling.listEventsFor:DEF456+STU678+VWX901+XYZ789",
                        "location.getLocations:CNSHA+DEHAM+NLRTM",
                        "location.getLocations:DEHAM+SGSIN+USNYC",
                        "routing.getItineraries:DEF456+STU678+VWX901+XYZ789",
                        "routing.getItineraries:DEF456+STU678+VWX901+XYZ789",
                        "voyage.getVoyages:V100S+V200E+V300A");
        assertEquals(expected, entries);
    }
}
