package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import jakarta.enterprise.context.ApplicationScoped;

/**
 * The handling service's data: every recorded event, by cargo and by id, and
 * the idempotency index from a client's key to the event it produced. It is
 * shared by concurrent requests, so every structure is thread-safe and the one
 * compound step, "look the key up, and record the event only if it is absent",
 * is a single {@link ConcurrentHashMap#computeIfAbsent} call. Two requests that
 * carry the same key cannot both record an event.
 */
@ApplicationScoped
public class HandlingStore {

    /** What {@link #append} did: the event now on record, and whether this call wrote it. */
    public record Appended(HandlingRecord event, boolean created) {}

    private final AtomicInteger lastNumber = new AtomicInteger();
    private final Map<String, List<HandlingRecord>> byCargo = new ConcurrentHashMap<>();
    private final Map<String, HandlingRecord> byId = new ConcurrentHashMap<>();
    private final Map<String, HandlingRecord> byIdempotencyKey = new ConcurrentHashMap<>();

    HandlingStore() {
        // The seed: ABC123 was received in New York and loaded onto V100S.
        seed(new NewHandling("ABC123", HandlingEventType.RECEIVE, "USNYC", null, Instant.parse("2026-09-30T16:00:00Z")));
        seed(new NewHandling("ABC123", HandlingEventType.LOAD, "USNYC", "V100S", Instant.parse("2026-10-01T08:30:00Z")));
    }

    private void seed(NewHandling handling) {
        // A seeded event was registered five minutes after it completed.
        insert(handling, handling.completionTime().plus(5, ChronoUnit.MINUTES));
    }

    /** Every event recorded for the cargo; empty when there are none. */
    public List<HandlingRecord> events(String trackingId) {
        return List.copyOf(byCargo.getOrDefault(trackingId, List.of()));
    }

    public Optional<HandlingRecord> event(String id) {
        return Optional.ofNullable(byId.get(id));
    }

    public Optional<HandlingRecord> findByIdempotencyKey(String key) {
        return Optional.ofNullable(byIdempotencyKey.get(key));
    }

    /**
     * Records the event. With a key, a second call with the same key returns the
     * first event and writes nothing; without one, every call writes.
     */
    public Appended append(NewHandling handling, String idempotencyKey) {
        if (idempotencyKey == null) {
            return new Appended(insert(handling, now()), true);
        }
        AtomicBoolean created = new AtomicBoolean();
        HandlingRecord event = byIdempotencyKey.computeIfAbsent(idempotencyKey, key -> {
            created.set(true);
            return insert(handling, now());
        });
        return new Appended(event, created.get());
    }

    /** The server clock in whole seconds, the wire format of {@code DateTime}. */
    private static Instant now() {
        return Instant.now().truncatedTo(ChronoUnit.SECONDS);
    }

    private HandlingRecord insert(NewHandling handling, Instant registered) {
        HandlingRecord event = new HandlingRecord(
                "evt_" + lastNumber.incrementAndGet(),
                handling.trackingId(),
                handling.type(),
                handling.unLocode(),
                handling.voyageNumber(),
                handling.completionTime(),
                registered);
        byCargo.computeIfAbsent(event.trackingId(), id -> new CopyOnWriteArrayList<>()).add(event);
        byId.put(event.id(), event);
        return event;
    }
}
