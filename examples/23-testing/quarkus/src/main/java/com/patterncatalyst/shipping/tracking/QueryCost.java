package com.patterncatalyst.shipping.tracking;

import graphql.GraphQL;
import graphql.execution.AbortExecutionException;
import graphql.analysis.MaxQueryComplexityInstrumentation;
import graphql.execution.instrumentation.ChainedInstrumentation;
import graphql.execution.instrumentation.Instrumentation;
import graphql.execution.instrumentation.InstrumentationContext;
import graphql.execution.instrumentation.InstrumentationState;
import graphql.execution.instrumentation.SimplePerformantInstrumentation;
import graphql.execution.instrumentation.parameters.InstrumentationExecuteOperationParameters;
import graphql.language.Document;
import graphql.language.Field;
import graphql.language.FragmentDefinition;
import graphql.language.FragmentSpread;
import graphql.language.InlineFragment;
import graphql.language.OperationDefinition;
import graphql.language.SelectionSet;
import graphql.parser.ParserOptions;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Adds the cost budget to SmallRye's own instrumentation.
 *
 * <p>SmallRye builds its chain (the depth limit from
 * {@code quarkus.smallrye-graphql.instrumentation-query-depth} and its parsed
 * query cache) and then fires {@code GraphQL.Builder} as a CDI event, enabled by
 * {@code quarkus.smallrye-graphql.events.enabled=true}. The builder has no
 * getter, and {@code instrumentation(...)} replaces whatever is set, so the
 * observer reads the chain from a throwaway {@code build()} and appends the cost
 * check to it. Depth keeps firing first.
 *
 * <p>The same observer sets the token limit for operations through
 * graphql-java's {@code ParserOptions} (see the README).
 *
 * <p>The configured {@code tracking.query.max-cost} is the budget. The
 * framework's own {@code instrumentation-query-complexity} stays unset because
 * it counts every field as 1 (see {@link TrackingCostCalculator}).
 */
@ApplicationScoped
public class QueryCost {

    private final int maxCost;
    private final int maxTokens;
    private final int maxAliases;

    QueryCost(
            @ConfigProperty(name = "tracking.query.max-cost") int maxCost,
            @ConfigProperty(name = "tracking.query.max-tokens") int maxTokens,
            @ConfigProperty(name = "tracking.query.max-aliases") int maxAliases) {
        this.maxCost = maxCost;
        this.maxTokens = maxTokens;
        this.maxAliases = maxAliases;
    }

    void addCostLimit(@Observes GraphQL.Builder builder) {
        // The token limit is set through graphql-java's ParserOptions: the
        // operation default is the one that bounds a request.
        ParserOptions.setDefaultOperationParserOptions(
                ParserOptions.getDefaultOperationParserOptions().transform(options -> options.maxTokens(maxTokens)));
        Instrumentation smallrye = builder.build().getInstrumentation();
        builder.instrumentation(new ChainedInstrumentation(List.of(
                smallrye,
                new MaxAliasesInstrumentation(maxAliases),
                new MaxQueryComplexityInstrumentation(maxCost, new TrackingCostCalculator(maxTokens)))));
    }

    /**
     * Refuses a document with more than {@code max} aliased fields, before any resolver runs.
     *
     * <p>An alias limit complements the cost budget: the budget prices what a selection
     * fetches, and an alias repeats a cheap selection at no extra charge. The
     * rule and the message mirror Strawberry's {@code MaxAliasesLimiter} so that both
     * stacks refuse the same documents in the same words: every aliased field counts,
     * inside fields, inline fragments and fragment spreads alike, a spread counts again
     * wherever it appears, and {@code @skip} does not exempt anything.
     */
    static final class MaxAliasesInstrumentation extends SimplePerformantInstrumentation {

        private final int max;

        MaxAliasesInstrumentation(int max) {
            this.max = max;
        }

        @Override
        public InstrumentationContext<graphql.ExecutionResult> beginExecuteOperation(
                InstrumentationExecuteOperationParameters parameters, InstrumentationState state) {
            Document document = parameters.getExecutionContext().getDocument();
            Map<String, FragmentDefinition> fragments = parameters.getExecutionContext().getFragmentsByName();
            long total = 0;
            Map<String, Long> memo = new HashMap<>();
            for (OperationDefinition operation : document.getDefinitionsOfType(OperationDefinition.class)) {
                total += countAliases(operation.getSelectionSet(), fragments, memo);
            }
            if (total > max) {
                throw new AbortExecutionException(Math.min(total, Integer.MAX_VALUE) + " aliases found. Allowed: " + max);
            }
            return super.beginExecuteOperation(parameters, state);
        }

        private static long countAliases(
                SelectionSet selections, Map<String, FragmentDefinition> fragments, Map<String, Long> memo) {
            if (selections == null) {
                return 0;
            }
            long count = 0;
            for (var selection : selections.getSelections()) {
                if (selection instanceof Field field) {
                    count += (field.getAlias() != null ? 1 : 0) + countAliases(field.getSelectionSet(), fragments, memo);
                } else if (selection instanceof InlineFragment inline) {
                    count += countAliases(inline.getSelectionSet(), fragments, memo);
                } else if (selection instanceof FragmentSpread spread) {
                    FragmentDefinition fragment = fragments.get(spread.getName());
                    if (fragment != null) {
                        Long counted = memo.get(spread.getName());
                        if (counted == null) {
                            counted = countAliases(fragment.getSelectionSet(), fragments, memo);
                            memo.put(spread.getName(), counted);
                        }
                        count += counted;
                    }
                }
            }
            return count;
        }
    }
}
