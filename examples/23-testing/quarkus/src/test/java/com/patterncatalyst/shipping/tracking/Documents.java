package com.patterncatalyst.shipping.tracking;

import static org.hamcrest.Matchers.containsString;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

import io.restassured.RestAssured;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;

/**
 * The client documents of the example, shared with the Python suite, graphql-inspector
 * and the load runner: {@code documents/<name>.graphql} on the test classpath.
 * {@link #post} sends one as a GraphQL-over-HTTP POST to the application under test.
 */
final class Documents {

    private Documents() {}

    /** The text of {@code documents/<path>.graphql}. */
    static String read(String path) {
        try (InputStream in = Documents.class.getResourceAsStream("/documents/" + path + ".graphql")) {
            if (in == null) {
                throw new IllegalArgumentException("no document " + path);
            }
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** POST {@code query} with {@code variables} to {@code /graphql}; 200 and a JSON body are part of the contract. */
    static ValidatableResponse post(String query, Map<String, Object> variables) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("query", query);
        if (variables != null && !variables.isEmpty()) {
            body.put("variables", variables);
        }
        return RestAssured.given()
                .contentType(ContentType.JSON)
                .body(body)
                .post("/graphql")
                .then()
                .statusCode(200)
                .contentType(containsString("json"));
    }

    static ValidatableResponse post(String query) {
        return post(query, null);
    }

    /** The document {@code name} from {@code documents/}, posted with {@code variables}. */
    static ValidatableResponse postDocument(String name, Map<String, Object> variables) {
        return post(read(name), variables);
    }
}
