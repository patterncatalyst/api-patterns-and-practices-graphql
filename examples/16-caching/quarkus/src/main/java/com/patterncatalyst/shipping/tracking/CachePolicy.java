package com.patterncatalyst.shipping.tracking;

import java.util.Set;

import graphql.ExecutionResult;
import graphql.language.Document;
import graphql.language.Field;
import graphql.language.OperationDefinition;
import graphql.language.Selection;
import io.quarkus.vertx.http.runtime.CurrentVertxRequest;
import io.smallrye.graphql.api.Context;
import io.smallrye.graphql.cdi.event.AfterExecute;
import io.vertx.core.http.HttpMethod;
import io.vertx.ext.web.RoutingContext;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;

/**
 * Sets {@code Cache-Control} on every GraphQL response, from what the response is.
 *
 * <p>A response is {@code public, max-age=300} when all of these hold, and
 * {@code no-store} otherwise:
 *
 * <ul>
 *   <li>the request is a GET (RFC 9111 lets a shared cache store only what a
 *       cacheable method produced; a POST body is not part of the key);
 *   <li>the result has no errors;
 *   <li>every root field is reference data: {@code location}, {@code voyage} or
 *       {@code __typename};
 *   <li>the request carries no {@code Authorization} header, because what a caller
 *       may read can depend on who the caller is.
 * </ul>
 *
 * <p>Every {@code public} response also carries {@code Vary: Accept}, so a shared cache
 * stores one entry per {@code Accept} value.
 *
 * <p>The {@code @AfterExecute} event fires once the result is known and before the
 * response is written, on the request's own thread, so the header goes on the
 * Vert.x response that is about to be sent.
 */
@ApplicationScoped
public class CachePolicy {

    static final String PUBLIC = "public, max-age=300";
    static final String NO_STORE = "no-store";
    private static final Set<String> REFERENCE_FIELDS = Set.of("location", "voyage", "__typename");

    private final CurrentVertxRequest currentRequest;

    CachePolicy(CurrentVertxRequest currentRequest) {
        this.currentRequest = currentRequest;
    }

    void decide(@Observes @AfterExecute Context context) {
        RoutingContext routing = currentRequest.getCurrent();
        if (routing == null || routing.response().headWritten()) {
            return;
        }
        String policy = policyFor(routing, context);
        routing.response().putHeader("Cache-Control", policy);
        if (PUBLIC.equals(policy)) {
            // The body depends on the Accept header, so a cache keeps one entry per Accept value.
            routing.response().putHeader("Vary", "Accept");
        }
    }

    private static String policyFor(RoutingContext routing, Context context) {
        boolean get = HttpMethod.GET.equals(routing.request().method());
        boolean anonymous = routing.request().getHeader("Authorization") == null;
        ExecutionResult result = context.unwrap(ExecutionResult.class);
        boolean clean = result != null && result.getErrors().isEmpty();
        boolean reference = onlyReferenceData(context.unwrap(Document.class), context.getOperationName().orElse(null));
        return get && anonymous && clean && reference ? PUBLIC : NO_STORE;
    }

    /** True when the selected operation is a query whose root selections are all plain reference fields. */
    private static boolean onlyReferenceData(Document document, String operationName) {
        return document != null
                && document.getDefinitionsOfType(OperationDefinition.class).stream()
                        .filter(op -> operationName == null || operationName.equals(op.getName()))
                        .allMatch(op -> op.getOperation() == OperationDefinition.Operation.QUERY
                                && op.getSelectionSet().getSelections().stream().allMatch(CachePolicy::isReferenceField));
    }

    private static boolean isReferenceField(Selection<?> selection) {
        // A fragment or inline fragment at the root could hide any field: treat it as not reference data.
        return selection instanceof Field field && REFERENCE_FIELDS.contains(field.getName());
    }
}
