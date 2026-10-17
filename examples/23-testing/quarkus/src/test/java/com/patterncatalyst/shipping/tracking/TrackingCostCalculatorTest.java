package com.patterncatalyst.shipping.tracking;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import graphql.analysis.FieldComplexityEnvironment;
import graphql.language.Field;

/**
 * Resolver layer, pure units. The calculator is the price list: graphql-java walks
 * the document and asks it for one field at a time, so each rule can be checked
 * with the field's name, its arguments and the cost of its children.
 */
class TrackingCostCalculatorTest {

    private final TrackingCostCalculator calculator = new TrackingCostCalculator(5000);

    private int price(String field, Map<String, Object> arguments, int children) {
        FieldComplexityEnvironment environment =
                new FieldComplexityEnvironment(Field.newField(field).build(), null, null, arguments, null);
        return calculator.calculate(environment, children);
    }

    @Test
    void aPageMultipliesItsChildrenByTheRequestedSize() {
        assertEquals(1 + 4 * 12, price("cargos", Map.of("first", 4), 12));
    }

    @Test
    void aPageWithoutASizeIsPricedAtTheDefaultPageOfTen() {
        assertEquals(1 + 10 * 3, price("handlingHistory", Map.of(), 3));
    }

    @Test
    void nodesMultipliesByTheNumberOfIds() {
        assertEquals(1 + 3 * 1, price("nodes", Map.of("ids", List.of("loc_NLRTM", "loc_DEHAM", "voy_V100S")), 1));
    }

    @Test
    void introspectionFieldsCostNothing() {
        assertEquals(0, price("__schema", Map.of(), 40));
    }

    @Test
    void aNegativePageSizeIsPricedAsAnEmptyPage() {
        assertEquals(1, price("cargos", Map.of("first", -1000), 12));
    }

    @Test
    void aFieldWithoutAPageSizeCostsOnePlusItsChildren() {
        assertEquals(1 + 5, price("itinerary", Map.of(), 5));
    }
}
