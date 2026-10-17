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
 * The location service's side of the tracking view: getLocation and getLocations.
 * Locations are reference data, so both operations sit behind the {@code locations}
 * cache (300 s): a hit is not a call to the owner and is not logged.
 */
@ApplicationScoped
public class LocationSource {

    private final TrackingData data;
    private final SourceCalls calls;
    private final CaffeineCache cache;

    LocationSource(TrackingData data, SourceCalls calls, @CacheName("locations") Cache cache) {
        this.data = data;
        this.calls = calls;
        this.cache = cache.as(CaffeineCache.class);
    }

    /** Null when the location service has nothing under that key. */
    @CacheResult(cacheName = "locations")
    public Uni<Location> getLocation(String request, @CacheKey String unLocode) {
        return calls.call(request, "location", "getLocation", unLocode, () -> data.location(unLocode));
    }

    /** Many locations in one call: one outcome per UN/LOCODE, in the order asked; null when unknown. */
    public Uni<List<Outcome<Location>>> getLocations(String request, List<String> unLocodes) {
        return BulkCache.through(
                cache,
                Location.class,
                unLocodes,
                misses -> calls.callBatch(request, "location", "getLocations", misses, data::location));
    }
}
