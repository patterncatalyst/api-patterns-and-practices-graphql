package com.patterncatalyst.shipping.tracking;

import static org.hamcrest.Matchers.equalTo;

import java.util.Map;

import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;

/**
 * A test profile overrides configuration for the classes that name it. Here the
 * budget is 52, one unit under the price of FanOut, so the refusal states the
 * price: 53.
 */
@QuarkusTest
@TestProfile(FanOutPriceTest.BudgetOfFiftyTwo.class)
class FanOutPriceTest {

    public static class BudgetOfFiftyTwo implements QuarkusTestProfile {
        @Override
        public Map<String, String> getConfigOverrides() {
            return Map.of("tracking.query.max-cost", "52");
        }
    }

    @Test
    void fanOutIsPricedAtFiftyThree() {
        Documents.postDocument("fan-out", null)
                .body("errors[0].message", equalTo("maximum query complexity exceeded 53 > 52"));
    }
}
