package com.patterncatalyst.shipping.tracking;

import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;

/** A request over the cost budget is refused with a stated price, before any source is called. */
@QuarkusTest
class CostLimitTest {

    @Inject
    SourceCalls calls;

    @Test
    void overBudgetDocumentIsRefusedBeforeAnySourceCall() {
        calls.reset();

        Documents.post(Documents.read("load/over-budget"))
                .body("data", nullValue())
                .body("errors", hasSize(1))
                .body("errors[0].message", equalTo("maximum query complexity exceeded 7651 > 1000"));

        assertEquals(0, calls.snapshot().size(), "a refused request makes no source call");
    }

    @Test
    void aPageWithinTheBudgetStillRuns() {
        Documents.post("{ cargos(first: 4) { edges { node { trackingId } } } }")
                .body("errors", nullValue())
                .body("data.cargos.edges", hasSize(4));
    }
}
