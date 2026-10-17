package com.patterncatalyst.shipping.client;

import static io.smallrye.graphql.client.core.Argument.arg;
import static io.smallrye.graphql.client.core.Argument.args;
import static io.smallrye.graphql.client.core.Document.document;
import static io.smallrye.graphql.client.core.Field.field;
import static io.smallrye.graphql.client.core.Operation.operation;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.TreeSet;

import com.patterncatalyst.shipping.client.Models.CargoPage;
import com.patterncatalyst.shipping.client.Models.HandlingEventType;
import com.patterncatalyst.shipping.client.Models.RegisterInput;
import com.patterncatalyst.shipping.client.Models.RegisterPayload;

import io.quarkus.runtime.QuarkusApplication;
import io.quarkus.runtime.annotations.QuarkusMain;
import io.smallrye.graphql.client.Response;
import io.smallrye.graphql.client.core.Document;
import io.smallrye.graphql.client.dynamic.api.DynamicGraphQLClient;
import io.smallrye.graphql.client.GraphQLClient;
import jakarta.inject.Inject;
import jakarta.json.Json;

/** Calls the tracking view with the typesafe and dynamic clients and prints one JSON line per step. */
@QuarkusMain
public class Main implements QuarkusApplication {

    @Inject
    TrackingClient tracking;

    @Inject
    @GraphQLClient("tracking")
    DynamicGraphQLClient dynamic;

    @Override
    public int run(String... args) throws Exception {
        var cargo = tracking.cargo(new TrackingId("ABC123"));
        say(Json.createObjectBuilder()
                .add("step", "typesafe-cargo")
                .add("trackingId", cargo.trackingId().value())
                .add("description", cargo.description())
                .add("status", cargo.delivery().transportStatus().name()));

        // A page where one edge fails: the node is an ErrorOr, so the page is
        // returned with the other nodes present and the failed edge's errors in hand.
        CargoPage page = tracking.cargos(10);
        List<String> messages = new ArrayList<>();
        List<Integer> failedEdges = new ArrayList<>();
        TreeSet<String> presentIds = new TreeSet<>();
        for (int i = 0; i < page.edges().size(); i++) {
            var node = page.edges().get(i).node();
            if (node.isPresent()) {
                presentIds.add(node.get().trackingId().value());
            } else {
                failedEdges.add(i);
                node.getErrors().forEach(error -> messages.add(error.getMessage()));
            }
        }
        say(Json.createObjectBuilder()
                .add("step", "typesafe-page")
                .add("edges", page.edges().size())
                .add("present", presentIds.size())
                .add("errors", messages.size())
                .add("failedEdges", Json.createArrayBuilder(failedEdges))
                .add("presentIds", Json.createArrayBuilder(presentIds))
                .add("messages", Json.createArrayBuilder(new TreeSet<>(messages))));

        RegisterPayload payload = tracking.registerHandlingEvent(new RegisterInput(
                new TrackingId("VWX901"),
                HandlingEventType.RECEIVE,
                new UnLocode("SGSIN"),
                null,
                Instant.parse("2026-10-09T10:00:00Z")));
        say(Json.createObjectBuilder()
                .add("step", "typesafe-mutation")
                .add("event", payload.handlingEvent().id())
                .add("status", payload.cargo().delivery().transportStatus().name())
                .add("userErrors", payload.userErrors().size()));

        // The dynamic client builds the document at run time.
        Document document = document(operation(
                field("location", args(arg("unLocode", "NLRTM")), field("name"))));
        Response response = dynamic.executeSync(document);
        say(Json.createObjectBuilder()
                .add("step", "dynamic-location")
                .add("name", response.getData().getJsonObject("location").getString("name")));
        return 0;
    }

    private static void say(jakarta.json.JsonObjectBuilder line) {
        System.out.println(line.build());
    }
}
