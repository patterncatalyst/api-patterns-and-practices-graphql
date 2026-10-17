package com.patterncatalyst.shipping.tracking;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.function.Function;

import io.quarkus.cache.CaffeineCache;
import io.smallrye.mutiny.Uni;

/**
 * Puts a {@code quarkus-cache} cache under a bulk source operation. The
 * {@code @CacheResult} annotation caches one call per key; a bulk operation
 * takes many keys in one call, so it asks the cache for each key itself
 * ({@code getIfPresent}), sends only the misses to the owner, and
 * {@code put}s what comes back. The cache, its expiry and its size bound are
 * Caffeine's, configured under {@code quarkus.cache.caffeine."<name>"}; this class only
 * splits a list of keys into hits and misses.
 *
 * <p>Only a found value is stored: an unknown key (null) and a failed key are asked
 * again next time. The entries are the same ones {@code @CacheResult} writes for
 * the single-key operation, so a bulk read warms the single-key path and back.
 */
final class BulkCache {

    private BulkCache() {}

    /**
     * One outcome per requested key, in the order asked. {@code fetch} receives the
     * distinct missing keys and is not called when every key is cached.
     */
    static <T> Uni<List<Outcome<T>>> through(
            CaffeineCache cache,
            Class<?> valueType,
            List<String> keys,
            Function<List<String>, Uni<List<Outcome<T>>>> fetch) {
        Map<String, T> cached = new HashMap<>();
        List<String> misses = new ArrayList<>();
        for (String key : keys.stream().distinct().toList()) {
            T value = cachedValue(cache, valueType, key);
            if (value == null) {
                misses.add(key);
            } else {
                cached.put(key, value);
            }
        }
        if (misses.isEmpty()) {
            return Uni.createFrom().item(inOrder(keys, key -> Outcome.found(cached.get(key))));
        }
        return fetch.apply(misses).map(fetched -> {
            Map<String, Outcome<T>> byKey = new LinkedHashMap<>();
            for (int i = 0; i < misses.size(); i++) {
                Outcome<T> outcome = fetched.get(i);
                byKey.put(misses.get(i), outcome);
                if (outcome.value() != null) {
                    cache.put(misses.get(i), CompletableFuture.completedFuture(outcome.value()));
                }
            }
            return inOrder(keys, key -> cached.containsKey(key) ? Outcome.found(cached.get(key)) : byKey.get(key));
        });
    }

    @SuppressWarnings("unchecked")
    private static <T> T cachedValue(CaffeineCache cache, Class<?> valueType, String key) {
        CompletableFuture<Object> entry = cache.getIfPresent(key);
        Object value = entry == null ? null : entry.getNow(null);
        // A completed entry holds the value itself; anything else (still loading, or Quarkus' null marker) is a miss.
        return valueType.isInstance(value) ? (T) value : null;
    }

    private static <T> List<Outcome<T>> inOrder(List<String> keys, Function<String, Outcome<T>> outcomeOf) {
        return keys.stream().map(outcomeOf).toList();
    }
}
