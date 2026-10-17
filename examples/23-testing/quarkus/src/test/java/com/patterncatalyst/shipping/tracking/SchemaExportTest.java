package com.patterncatalyst.shipping.tracking;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.RestAssured;

/**
 * Schema layer. SmallRye serves the SDL it built at {@code /graphql/schema.graphql};
 * the test fetches it, checks the types the contract names, and writes it to the
 * export directory so verify.sh can diff it against {@code contracts/schema/}.
 */
@QuarkusTest
class SchemaExportTest {

    @ConfigProperty(name = "tracking.test.export-dir")
    String exportDir;

    @Test
    void exportedSchemaDeclaresTheContractTypesAndScalars() throws IOException {
        String sdl = RestAssured.get("/graphql/schema.graphql")
                .then()
                .statusCode(200)
                .extract()
                .asString();

        assertTrue(sdl.contains("type Cargo implements Node"), "Cargo implements Node");
        assertTrue(sdl.contains("scalar TrackingId"), "the TrackingId scalar is declared");
        assertTrue(sdl.contains("input RegisterHandlingEventInput"), "the mutation input is declared");

        Path target = Path.of(exportDir);
        Files.createDirectories(target);
        Files.writeString(target.resolve("schema.graphql"), sdl, StandardCharsets.UTF_8);
    }
}
