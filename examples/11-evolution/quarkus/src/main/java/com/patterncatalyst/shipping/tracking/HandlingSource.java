package com.patterncatalyst.shipping.tracking;

import java.util.List;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * The handling service's side of the tracking view: the reads {@code listEvents},
 * {@code getEvent} and {@code findByIdempotencyKey}, and the write
 * {@code appendEvent}.
 */
@ApplicationScoped
public class HandlingSource {

    private final HandlingStore store;
    private final SourceCalls calls;

    HandlingSource(HandlingStore store, SourceCalls calls) {
        this.store = store;
        this.calls = calls;
    }

    /** Every event recorded for the cargo; empty when there are none. */
    public Uni<List<HandlingRecord>> listEvents(String request, String trackingId) {
        return calls.call(request, "handling", "listEvents", trackingId, () -> store.events(trackingId));
    }

    /** Null when no event has that id. */
    public Uni<HandlingRecord> getEvent(String request, String id) {
        return calls.call(request, "handling", "getEvent", id, () -> store.event(id).orElse(null));
    }

    /** The event a key already produced, or null when the key is new. */
    public Uni<HandlingRecord> findByIdempotencyKey(String request, String key) {
        return calls.call(
                request, "handling", "findByIdempotencyKey", key, () -> store.findByIdempotencyKey(key).orElse(null));
    }

    /**
     * Records the event, or returns the event the key already produced. The
     * log entry is keyed by the new event's id and exists only when this call
     * wrote: a call that lost a race to the same key writes, and logs, nothing.
     */
    public Uni<HandlingStore.Appended> appendEvent(String request, NewHandling handling, String idempotencyKey) {
        return calls.write(
                request,
                "handling",
                "appendEvent",
                () -> store.append(handling, idempotencyKey),
                appended -> appended.created() ? appended.event().id() : null);
    }
}
