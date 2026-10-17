package com.patterncatalyst.shipping.tracking;

import graphql.analysis.FieldComplexityCalculator;
import graphql.analysis.FieldComplexityEnvironment;
import java.util.List;
import java.util.Map;

/**
 * The cost of one field: {@code 1 + multiplier * (the cost of its children)}.
 *
 * <ul>
 *   <li>Introspection fields ({@code __typename}, {@code __schema}, {@code __type}) cost 0.
 *   <li>{@code cargos} and {@code handlingHistory} multiply by the page size they
 *       will return: {@code first}, else {@code last}, else the default page of
 *       {@value Pagination#DEFAULT_PAGE_SIZE}.
 *   <li>{@code nodes} multiplies by the number of ids.
 *   <li>Every other field has a multiplier of 1; an unpaginated list such as
 *       {@code legs} is bounded by the domain, not by the client.
 * </ul>
 *
 * <p>graphql-java adds the costs of sibling fields in an {@code int}, so a field's cost is
 * clamped to {@code Integer.MAX_VALUE / maxTokens}. A request has at most {@code maxTokens}
 * fields, so the sum of any set of siblings stays within the 32-bit range (below 2,147,483,648).
 * The clamp sits far above the budget, so it
 * changes no verdict and no total below it.
 *
 * <p>The price list is this class: graphql-java supplies the traversal, the
 * variable coercion and the limit, and this class supplies the cost of each
 * field.
 */
public class TrackingCostCalculator implements FieldComplexityCalculator {

    private final int maxFieldCost;

    TrackingCostCalculator(int maxTokens) {
        this.maxFieldCost = Integer.MAX_VALUE / maxTokens;
    }

    @Override
    public int calculate(FieldComplexityEnvironment environment, int childComplexity) {
        String name = environment.getField().getName();
        if (name.startsWith("__")) {
            return 0;
        }
        Map<String, Object> arguments = environment.getArguments();
        long multiplier =
                switch (name) {
                    case "cargos", "handlingHistory" -> pageSize(arguments);
                    case "nodes" -> arguments.get("ids") instanceof List<?> ids ? ids.size() : 1;
                    default -> 1;
                };
        return (int) Math.min(maxFieldCost, 1 + multiplier * childComplexity);
    }

    /**
     * The page size the field asks for. A value from a variable arrives as a
     * {@code BigDecimal}, one written in the document as an {@code Integer}, so
     * both are read as a {@code Number}. A negative size counts as 0, so it can
     * never offset the price of another field.
     */
    private static long pageSize(Map<String, Object> arguments) {
        for (String name : List.of("first", "last")) {
            if (arguments.get(name) instanceof Number size) {
                return (long) Math.max(0, Math.min(size.doubleValue(), Integer.MAX_VALUE));
            }
        }
        return Pagination.DEFAULT_PAGE_SIZE;
    }
}
