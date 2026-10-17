package com.patterncatalyst.shipping.tracking;

import java.io.IOException;
import java.io.InputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import graphql.language.OperationDefinition;
import graphql.parser.Parser;
import io.quarkus.cache.Cache;
import io.quarkus.cache.CacheName;
import io.quarkus.cache.CaffeineCache;
import io.vertx.core.http.HttpHeaders;
import io.vertx.core.http.HttpMethod;
import io.vertx.core.json.JsonArray;
import io.vertx.core.json.JsonObject;
import io.vertx.ext.web.Router;
import io.vertx.ext.web.RoutingContext;
import io.vertx.ext.web.handler.BodyHandler;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.json.Json;
import jakarta.json.JsonReader;

/**
 * Apollo persisted queries and trusted documents, in front of SmallRye GraphQL.
 *
 * <p>The example implements Apollo's persisted-query protocol in this route, in front of
 * SmallRye's. The route runs before SmallRye's, resolves the hash to a document and
 * hands SmallRye the text with {@code rc.reroute(...)} as a {@code query} URL
 * parameter, which SmallRye accepts through {@code http.get.enabled} and
 * {@code http.post.queryparameters.enabled}.
 *
 * <p>The route enforces GraphQL-over-HTTP's rules for every request it hands on: a
 * mutation sent over GET is refused with 405 and {@code Allow: POST}, a GET whose document
 * does not parse gets 400, and the check runs on the text the handler executes. In
 * {@code trusted} mode a POST body must be a JSON object or {@code application/graphql}
 * text, and the manifest text is what runs. Trusted mode covers every transport the
 * endpoint serves; this example serves HTTP only, so the route refuses any request on
 * {@code /graphql} that carries an {@code Upgrade} header (Chapter 21 covers GraphQL over WebSocket).
 *
 * <p>The store is {@code quarkus-cache} (Caffeine), bounded to 1000 entries. In
 * {@code trusted} mode the manifest is the only source of documents: nothing is
 * stored, and text that is not in the manifest is refused.
 */
@ApplicationScoped
public class PersistedDocumentRoute {

    private static final String RESOLVED = "persisted.resolved";
    private static final String JSON = "application/json";
    private static final String GRAPHQL = "application/graphql";

    private final Cache documents;
    private final boolean trusted;
    private final Map<String, String> manifest;

    PersistedDocumentRoute(
            @CacheName("persisted-documents") Cache documents,
            @ConfigProperty(name = "tracking.documents.mode", defaultValue = "apq") String mode,
            @ConfigProperty(name = "tracking.documents.manifest") Optional<String> manifestPath) {
        this.documents = documents;
        this.trusted = "trusted".equals(mode);
        this.manifest = manifestPath.map(path -> loadManifest(Path.of(path))).orElse(Map.of());
    }

    /** Registered on Quarkus' router; order -10 runs before SmallRye's route, -100 before its transports. */
    void init(@Observes Router router) {
        router.route("/graphql").order(-100).handler(PersistedDocumentRoute::refuseUpgrade);
        router.route(HttpMethod.POST, "/graphql").order(-10).handler(BodyHandler.create(false));
        router.route("/graphql").order(-10).handler(this::resolve);
    }

    /** This example serves HTTP only: any request that carries an Upgrade header is refused in both modes. */
    private static void refuseUpgrade(RoutingContext rc) {
        if (rc.request().headers().contains(HttpHeaders.UPGRADE)) {
            reject(rc, 400, "BAD_USER_INPUT", "this endpoint serves HTTP only");
            return;
        }
        rc.next();
    }

    void resolve(RoutingContext rc) {
        HttpMethod method = rc.request().method();
        if (rc.get(RESOLVED) != null || (!HttpMethod.GET.equals(method) && !HttpMethod.POST.equals(method))) {
            rc.next();
            return;
        }
        String text;
        JsonObject body;
        try {
            body = new JsonObject();
            String bodyText = null;
            if (HttpMethod.POST.equals(method)) {
                String type = mediaType(rc);
                if (GRAPHQL.equals(type)) {
                    bodyText = Objects.requireNonNullElse(rc.body().asString(), ""); // the whole body is the document
                } else if (JSON.equals(type)) {
                    body = rc.body().length() == 0 ? body : rc.body().asJsonObject();
                } else if (trusted) {
                    reject(rc, 400, "PERSISTED_QUERY_REQUIRED", "only persisted documents are accepted");
                    return;
                } else {
                    rc.next(); // SmallRye reports it
                    return;
                }
            }
            // The text is the URL parameter if present, else the body's.
            text = rc.request().getParam("query");
            if (text == null) {
                text = bodyText != null ? bodyText : body.getString("query");
            }
        } catch (RuntimeException unreadable) {
            if (trusted) {
                reject(rc, 400, "PERSISTED_QUERY_REQUIRED", "only persisted documents are accepted");
            } else {
                rc.next(); // not a JSON object: SmallRye reports it
            }
            return;
        }
        String hash = hashOf(rc, body);

        if (hash == null) {
            // No persistedQuery extension. APQ accepts any text; trusted mode accepts manifest text only.
            if (trusted && text != null && !manifest.containsKey(sha256(text))) {
                refuse(rc, "PERSISTED_QUERY_REQUIRED", "only persisted documents are accepted");
                return;
            }
            proceed(rc, text, false);
            return;
        }

        if (text != null) {
            if (!sha256(text).equals(hash)) {
                refuse(rc, "BAD_USER_INPUT", "provided sha does not match query");
                return;
            }
            if (trusted) {
                if (!manifest.containsKey(hash)) {
                    refuse(rc, "PERSISTED_QUERY_REQUIRED", "only persisted documents are accepted");
                    return;
                }
            } else {
                documents.as(CaffeineCache.class).put(hash, CompletableFuture.completedFuture(text));
            }
            proceed(rc, text, false);
            return;
        }

        String known = manifest.get(hash);
        if (known == null && !trusted) {
            CompletableFuture<Object> stored = documents.as(CaffeineCache.class).getIfPresent(hash);
            known = stored == null ? null : (String) stored.getNow(null);
        }
        if (known == null) {
            refuse(rc, "PERSISTED_QUERY_NOT_FOUND", "PersistedQueryNotFound");
            return;
        }
        proceed(rc, known, true);
    }

    /**
     * Hands the request to SmallRye. The check runs on the text the handler
     * executes. A GET must carry a document that parses, and its selected
     * operation must be a query (GraphQL over HTTP: a 4xx, recommended 405 with
     * {@code Allow: POST}). In trusted mode and on GET the request is re-entered
     * with the checked text as its only {@code query} parameter, so the text that
     * was checked and hashed is the text that runs.
     */
    private void proceed(RoutingContext rc, String document, boolean reroute) {
        HttpMethod method = rc.request().method();
        boolean get = HttpMethod.GET.equals(method);
        String operationName = null;
        boolean forwardOperationName = false;
        if (get && document != null) {
            List<OperationDefinition> operations;
            try {
                operations = new Parser().parseDocument(document).getDefinitionsOfType(OperationDefinition.class);
            } catch (RuntimeException invalid) {
                reject(rc, 400, "BAD_USER_INPUT", "the document could not be parsed");
                return;
            }
            String requested = rc.request().getParam("operationName");
            String selected = requested == null || requested.isEmpty() ? null : requested;
            if (selected != null && operations.stream().noneMatch(op -> selected.equals(op.getName()))) {
                reject(rc, 400, "BAD_USER_INPUT", "operationName does not match an operation in the document");
                return;
            }
            if (!operations.stream()
                    .filter(op -> selected == null || selected.equals(op.getName()))
                    .allMatch(op -> op.getOperation() == OperationDefinition.Operation.QUERY)) {
                rc.response()
                        .setStatusCode(405)
                        .putHeader("Allow", "POST")
                        .putHeader("Content-Type", "text/plain")
                        .end("mutations are not allowed when using GET");
                return;
            }
            // A single-operation document is handed on without operationName; the document alone
            // selects the operation. Otherwise only the checked operationName is handed on.
            forwardOperationName = true;
            operationName = operations.size() == 1 ? null : selected;
        }
        if (reroute || trusted || (get && document != null)) {
            rc.put(RESOLVED, Boolean.TRUE);
            rc.reroute(method, "/graphql?" + parametersWith(rc, document, forwardOperationName, operationName));
        } else {
            rc.next();
        }
    }

    /**
     * The request's own URL parameters, minus any query, plus the checked document. The values
     * carry the checked text so that the handler receives exactly
     * that text; verify.sh asserts this with '+' and '%', over GET and POST. When
     * {@code checkedOperationName} applies, it replaces the request's operationName.
     */
    private static String parametersWith(RoutingContext rc, String text, boolean replaceOperationName,
            String checkedOperationName) {
        StringBuilder out = new StringBuilder();
        rc.request().params().forEach(entry -> {
            String key = entry.getKey();
            if (!"query".equals(key) && !(replaceOperationName && "operationName".equals(key))) {
                out.append(encode(key)).append('=').append(encodeValue(entry.getValue())).append('&');
            }
        });
        if (checkedOperationName != null) {
            out.append("operationName=").append(encodeValue(checkedOperationName)).append('&');
        }
        return text == null ? out.toString() : out.append("query=").append(encodeValue(text)).toString();
    }

    private static String hashOf(RoutingContext rc, JsonObject body) {
        try {
            JsonObject extensions = body.getJsonObject("extensions");
            String param = rc.request().getParam("extensions");
            if (param != null) {
                extensions = new JsonObject(param);
            }
            JsonObject persisted = extensions == null ? null : extensions.getJsonObject("persistedQuery");
            return persisted == null ? null : persisted.getString("sha256Hash");
        } catch (RuntimeException notJson) {
            return null; // malformed extensions are treated as absent
        }
    }

    /** The request's media type, lower-cased and without parameters. */
    private static String mediaType(RoutingContext rc) {
        String type = rc.request().getHeader("Content-Type");
        return type == null ? "" : type.split(";", 2)[0].trim().toLowerCase(Locale.ROOT);
    }

    /** A request error with the given HTTP status. */
    private static void reject(RoutingContext rc, int status, String code, String message) {
        JsonObject error = new JsonObject().put("message", message).put("extensions", new JsonObject().put("code", code));
        rc.response()
                .setStatusCode(status)
                .putHeader("Content-Type", "application/json")
                .end(new JsonObject().put("errors", new JsonArray().add(error)).encode());
    }

    private static void refuse(RoutingContext rc, String code, String message) {
        reject(rc, 200, code, message);
    }

    private static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    /** A value as it is carried in the re-entered URL. */
    private static String encodeValue(String value) {
        return encode(encode(value));
    }

    static String sha256(String text) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** The Apollo persisted-query manifest: {@code operations[].id} to {@code operations[].body}. */
    private static Map<String, String> loadManifest(Path path) {
        try (InputStream in = Files.newInputStream(path); JsonReader reader = Json.createReader(in)) {
            Map<String, String> bodies = new HashMap<>();
            reader.readObject().getJsonArray("operations").forEach(op -> {
                var operation = op.asJsonObject();
                bodies.put(operation.getString("id"), operation.getString("body"));
            });
            return Map.copyOf(bodies);
        } catch (IOException e) {
            throw new IllegalStateException("cannot read the persisted-document manifest " + path, e);
        }
    }
}
