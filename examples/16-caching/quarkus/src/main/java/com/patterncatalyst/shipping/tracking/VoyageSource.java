package com.patterncatalyst.shipping.tracking;

import java.util.List;

import io.quarkus.cache.Cache;
import io.quarkus.cache.CacheKey;
import io.quarkus.cache.CacheName;
import io.quarkus.cache.CacheResult;
import io.quarkus.cache.CaffeineCache;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * The voyage service's side of the tracking view: getVoyage and getVoyages.
 * Voyages are reference data, so both operations sit behind the {@code voyages}
 * cache (300 s, see application.properties): a hit is not a call to the owner
 * and is not logged.
 */
@ApplicationScoped
public class VoyageSource {

    private final TrackingData data;
    private final SourceCalls calls;
    private final CaffeineCache cache;

    VoyageSource(TrackingData data, SourceCalls calls, @CacheName("voyages") Cache cache) {
        this.data = data;
        this.calls = calls;
        this.cache = cache.as(CaffeineCache.class);
    }

    /** Null when the voyage service has nothing under that key. */
    @CacheResult(cacheName = "voyages")
    public Uni<Voyage> getVoyage(String request, @CacheKey String number) {
        return calls.call(request, "voyage", "getVoyage", number, () -> data.voyage(number));
    }

    /** Many voyages in one call: one outcome per voyage number, in the order asked; null when unknown. */
    public Uni<List<Outcome<Voyage>>> getVoyages(String request, List<String> numbers) {
        return BulkCache.through(
                cache,
                Voyage.class,
                numbers,
                misses -> calls.callBatch(request, "voyage", "getVoyages", misses, data::voyage));
    }
}
