package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentSkipListSet;
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
 *
 * <p>Each cargo's events live in a sorted set, newest first by completion time
 * and then by id sequence, so {@code handlingHistory} reads them already in
 * connection order and an event registered late lands in its place.
 */
@ApplicationScoped
public class HandlingStore {

    /** What {@link #append} did: the event now on record, and whether this call wrote it. */
    public record Appended(HandlingRecord event, boolean created) {}

    private static final Comparator<HandlingRecord> NEWEST_FIRST =
            Comparator.comparing(HandlingRecord::key).reversed();

    private final AtomicInteger lastNumber = new AtomicInteger();
    private final Map<String, ConcurrentSkipListSet<HandlingRecord>> byCargo = new ConcurrentHashMap<>();
    private final Map<String, HandlingRecord> byId = new ConcurrentHashMap<>();
    private final Map<String, HandlingRecord> byIdempotencyKey = new ConcurrentHashMap<>();

    HandlingStore() {
        // The seed: ABC123 was received in New York and loaded onto V100S (evt_1, evt_2);
        // DEF456 made the whole trip and was claimed in Rotterdam (evt_3 to evt_9).
        seed("ABC123", HandlingEventType.RECEIVE, "USNYC", null, "2026-09-30T16:00:00Z");
        seed("ABC123", HandlingEventType.LOAD, "USNYC", "V100S", "2026-10-01T08:30:00Z");
        seed("DEF456", HandlingEventType.RECEIVE, "USNYC", null, "2026-09-30T15:00:00Z");
        seed("DEF456", HandlingEventType.LOAD, "USNYC", "V100S", "2026-10-01T08:15:00Z");
        seed("DEF456", HandlingEventType.UNLOAD, "DEHAM", "V100S", "2026-10-09T14:30:00Z");
        seed("DEF456", HandlingEventType.LOAD, "DEHAM", "V200E", "2026-10-10T06:15:00Z");
        seed("DEF456", HandlingEventType.UNLOAD, "NLRTM", "V200E", "2026-10-11T18:20:00Z");
        seed("DEF456", HandlingEventType.CUSTOMS, "NLRTM", null, "2026-10-12T08:00:00Z");
        seed("DEF456", HandlingEventType.CLAIM, "NLRTM", null, "2026-10-12T15:00:00Z");
    }

    private void seed(String trackingId, HandlingEventType type, String unLocode, String voyageNumber, String completed) {
        Instant completionTime = Instant.parse(completed);
        // A seeded event was registered five minutes after it completed.
        insert(
                new NewHandling(trackingId, type, unLocode, voyageNumber, completionTime),
                completionTime.plus(5, ChronoUnit.MINUTES));
    }

    /** Every event recorded for the cargo, newest first; empty when there are none. */
    public List<HandlingRecord> events(String trackingId) {
        ConcurrentSkipListSet<HandlingRecord> events = byCargo.get(trackingId);
        return events == null ? List.of() : List.copyOf(events);
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
                handling.completionTime().truncatedTo(ChronoUnit.SECONDS),
                registered);
        byCargo.computeIfAbsent(event.trackingId(), id -> new ConcurrentSkipListSet<>(NEWEST_FIRST)).add(event);
        byId.put(event.id(), event);
        return event;
    }
}
