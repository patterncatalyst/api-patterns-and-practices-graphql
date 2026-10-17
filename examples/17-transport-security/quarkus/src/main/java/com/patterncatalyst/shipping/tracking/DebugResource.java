package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/**
 * The source-call log over HTTP, for the example's verification. It is a lab
 * tool: it answers only when {@code TRACKING_DEBUG_ENDPOINTS=true} (compose
 * sets it) and is a plain REST resource beside {@code /graphql}, so it adds
 * nothing to the GraphQL schema.
 */
@Path("/debug/source-calls")
public class DebugResource {

    /** The response body: {@code {"calls":[...]}}. */
    public record CallLog(List<SourceCall> calls) {}

    private final SourceCalls calls;
    private final boolean enabled;

    DebugResource(SourceCalls calls, @ConfigProperty(name = "tracking.debug-endpoints", defaultValue = "false") boolean enabled) {
        this.calls = calls;
        this.enabled = enabled;
    }

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public CallLog list() {
        requireEnabled();
        return new CallLog(calls.snapshot());
    }

    @DELETE
    public void reset() {
        requireEnabled();
        calls.reset();
    }

    private void requireEnabled() {
        if (!enabled) {
            throw new NotFoundException();
        }
    }
}
