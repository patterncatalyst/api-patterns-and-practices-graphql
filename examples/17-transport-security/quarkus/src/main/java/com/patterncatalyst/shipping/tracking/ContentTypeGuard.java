package com.patterncatalyst.shipping.tracking;

import io.quarkus.vertx.http.runtime.filters.Filters;
import io.vertx.core.http.HttpHeaders;
import io.vertx.core.http.HttpMethod;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.util.Locale;
import java.util.Set;

/**
 * Refuses a POST to /graphql whose Content-Type is not a JSON media type.
 *
 * <p>A GraphQL endpoint should accept only JSON request bodies. A browser sends a form or a
 * {@code text/plain} POST to any origin without a CORS preflight (the Fetch standard's "simple
 * request"), and the OWASP CSRF cheat sheet recommends disallowing simple content types. The
 * example adds the check as a Vert.x filter, registered through Quarkus's documented
 * {@link Filters} event, and it runs before the GraphQL handler. A GraphQL request body is JSON, so
 * only {@code application/json} (and the {@code application/graphql-response+json} media type of
 * the GraphQL-over-HTTP draft) passes; anything else gets 415.
 */
@ApplicationScoped
public class ContentTypeGuard {

    private static final Set<String> JSON = Set.of("application/json", "application/graphql-response+json");

    void register(@Observes Filters filters) {
        // Filters run before every route; among filters, higher priority runs first.
        filters.register(rc -> {
            if (rc.request().method() == HttpMethod.POST && rc.normalizedPath().startsWith("/graphql")
                    && !isJson(rc.request().getHeader(HttpHeaders.CONTENT_TYPE))) {
                rc.response().setStatusCode(415).putHeader(HttpHeaders.CONTENT_TYPE, "text/plain")
                        .end("Unsupported Media Type: send application/json");
                return;
            }
            rc.next();
        }, 100);
    }

    private static boolean isJson(String contentType) {
        if (contentType == null) {
            return false;
        }
        int semicolon = contentType.indexOf(';');
        String mediaType = (semicolon < 0 ? contentType : contentType.substring(0, semicolon))
                .trim().toLowerCase(Locale.ROOT);
        return JSON.contains(mediaType);
    }
}
