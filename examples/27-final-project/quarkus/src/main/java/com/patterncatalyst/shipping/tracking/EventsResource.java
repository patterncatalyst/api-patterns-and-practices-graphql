package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

import org.jboss.resteasy.reactive.RestHeader;
import org.jboss.resteasy.reactive.RestPath;
import org.jboss.resteasy.reactive.RestStreamElementType;

import io.quarkus.security.Authenticated;
import io.quarkus.security.ForbiddenException;
import io.smallrye.mutiny.Multi;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.sse.OutboundSseEvent;
import jakarta.ws.rs.sse.Sse;

/**
 * The plain SSE event feed. {@code GET /events/cargos/{trackingId}} is a
 * server-sent event stream and not a GraphQL operation: its payload is fixed,
 * so there is no selection. Each event carries {@code id: <evt id>},
 * {@code event: handled} and a JSON {@code data} field. A browser
 * {@code EventSource} that loses the connection reconnects by itself and sends
 * the last id it saw as {@code Last-Event-ID}; the feed answers by replaying the
 * cargo's events registered after that id and then continuing live
 * ({@link HandlingStore#watch}).
 *
 * <p>Quarkus REST writes the stream: a {@code Multi} of {@link OutboundSseEvent}
 * built with the injected {@link Sse}, produced as {@code text/event-stream}.
 *
 * <p>The feed applies the rules of {@code Subscription.cargoHandled} (Chapter 18):
 * the caller must be signed in, and a cargo the caller may not see is refused with 403.
 */
@Path("/events/cargos/{trackingId}")
public class EventsResource {

    /** The {@code data} of a {@code handled} event: the event as the handling service recorded it. */
    public record Handled(String id, String trackingId, String type, String location, Instant completionTime) {}

    private final HandlingStore store;
    private final BookingSource booking;
    private final Viewers viewers;

    EventsResource(HandlingStore store, BookingSource booking, Viewers viewers) {
        this.store = store;
        this.booking = booking;
        this.viewers = viewers;
    }

    @GET
    @Authenticated
    @Produces(MediaType.SERVER_SENT_EVENTS)
    @RestStreamElementType(MediaType.APPLICATION_JSON)
    public Multi<OutboundSseEvent> feed(
            @RestPath String trackingId,
            @RestHeader("Last-Event-ID") String lastEventId,
            @Context Sse sse) {
        // The rules of Subscription.cargoHandled (Chapter 18), checked before the stream
        // starts: a signed-in caller (401 otherwise) who may see the cargo (403 otherwise).
        if (!booking.mayWatch(trackingId, viewers.current())) {
            throw new ForbiddenException();
        }
        return store.watch(trackingId, HandlingStore.Channel.SSE, sequence(lastEventId)).map(record -> sse.newEventBuilder()
                .id(record.id())
                .name("handled")
                .data(
                        Handled.class,
                        new Handled(
                                record.id(),
                                record.trackingId(),
                                record.type().name(),
                                record.unLocode(),
                                record.completionTime()))
                .build());
    }

    /** The number in {@code evt_<n>}; null for no header or an id this feed did not issue. */
    private static Integer sequence(String eventId) {
        return eventId != null && eventId.matches("evt_\\d+") ? Integer.valueOf(eventId.substring(4)) : null;
    }
}
