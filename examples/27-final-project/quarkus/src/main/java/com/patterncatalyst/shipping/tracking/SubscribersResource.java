package com.patterncatalyst.shipping.tracking;

import java.util.LinkedHashMap;
import java.util.Map;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/**
 * The live subscriber counts over HTTP, for the example's verification: per
 * channel ({@code graphql} for {@code Subscription.cargoHandled}, {@code sse}
 * for the event feed) and tracking id, how many subscriptions are open. A lab
 * tool beside {@link DebugResource}: it answers only when
 * {@code TRACKING_DEBUG_ENDPOINTS=true}, and it adds nothing to the schema.
 */
@Path("/debug/subscribers")
public class SubscribersResource {

    private final HandlingStore store;
    private final boolean enabled;

    SubscribersResource(
            HandlingStore store,
            @ConfigProperty(name = "tracking.debug-endpoints", defaultValue = "false") boolean enabled) {
        this.store = store;
        this.enabled = enabled;
    }

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, Map<String, Integer>> list() {
        if (!enabled) {
            throw new NotFoundException();
        }
        Map<String, Map<String, Integer>> byChannel = new LinkedHashMap<>();
        store.watcherCounts().forEach((channel, counts) -> byChannel.put(channel.name().toLowerCase(), counts));
        return byChannel;
    }
}
