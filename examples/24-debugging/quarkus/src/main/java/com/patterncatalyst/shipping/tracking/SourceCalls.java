package com.patterncatalyst.shipping.tracking;

import java.time.Duration;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;
import java.util.function.Supplier;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import io.opentelemetry.instrumentation.annotations.SpanAttribute;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * The seam every source goes through. {@link #call} runs a lookup after the
 * configured latency, without holding a thread while it waits, and records the
 * call: the request that made it, the source and operation, the key, and the
 * start and end on a monotonic clock. The log is how verify.sh observes
 * execution order and overlap; it is not part of the GraphQL schema.
 */
@ApplicationScoped
public class SourceCalls {

    private final long originNanos = System.nanoTime();
    private final Duration latency;
    private final Queue<SourceCall> calls = new ConcurrentLinkedQueue<>();

    SourceCalls(@ConfigProperty(name = "tracking.source.latency-ms", defaultValue = "0") long latencyMs) {
        this.latency = Duration.ofMillis(latencyMs);
    }

    /**
     * Returns a lazy {@code Uni}: nothing starts until the engine subscribes,
     * and the clock starts then. The entry is written when the call ends,
     * whether it returned a value, null or an error.
     */
    @WithSpan("source.call")
    public <T> Uni<T> call(
            String request,
            @SpanAttribute("source.name") String source,
            @SpanAttribute("source.operation") String op,
            String key,
            Supplier<T> lookup) {
        return Uni.createFrom().deferred(() -> {
            long startMs = nowMs();
            return afterLatency(Uni.createFrom().item(lookup))
                    .eventually(() -> calls.add(new SourceCall(request, source, op, key, startMs, nowMs())));
        });
    }

    /**
     * A bulk operation: one source call for many keys. The call is logged once,
     * under the sorted distinct keys joined with {@code +}, and answers one
     * {@link Outcome} per requested key in the order asked. A key whose lookup
     * throws fails alone: its outcome carries the failure, the others carry
     * their values.
     */
    public <T> Uni<List<Outcome<T>>> callBatch(
            String request, String source, String op, Collection<String> keys, Function<String, T> lookup) {
        List<String> distinct = keys.stream().distinct().sorted().toList();
        return call(request, source, op, String.join("+", distinct), () -> {
            Map<String, Outcome<T>> byKey = new HashMap<>();
            for (String key : distinct) {
                try {
                    byKey.put(key, Outcome.found(lookup.apply(key)));
                } catch (RuntimeException failure) {
                    byKey.put(key, Outcome.failed(failure));
                }
            }
            return keys.stream().map(byKey::get).toList();
        });
    }

    /**
     * Like {@link #call}, for an operation that writes. The write runs once the
     * latency has passed, and {@code logKey} names the entry from its result;
     * a null key logs nothing, so an operation that turned out not to write
     * leaves no trace in a log whose entries mean "wrote".
     */
    @WithSpan("source.call")
    public <T> Uni<T> write(
            String request,
            @SpanAttribute("source.name") String source,
            @SpanAttribute("source.operation") String op,
            Supplier<T> write,
            Function<T, String> logKey) {
        return Uni.createFrom().deferred(() -> {
            long startMs = nowMs();
            return afterLatency(Uni.createFrom().nullItem())
                    .map(ignored -> write.get())
                    .invoke(result -> {
                        String key = logKey.apply(result);
                        if (key != null) {
                            calls.add(new SourceCall(request, source, op, key, startMs, nowMs()));
                        }
                    });
        });
    }

    /** The log so far, ordered by start time. */
    public List<SourceCall> snapshot() {
        return calls.stream().sorted(Comparator.comparingLong(SourceCall::startMs)).toList();
    }

    public void reset() {
        calls.clear();
    }

    /** Mutiny rejects a zero delay, so a zero latency skips the delay. */
    private <T> Uni<T> afterLatency(Uni<T> uni) {
        return latency.isZero() ? uni : uni.onItem().delayIt().by(latency);
    }

    private long nowMs() {
        return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - originNanos);
    }
}
