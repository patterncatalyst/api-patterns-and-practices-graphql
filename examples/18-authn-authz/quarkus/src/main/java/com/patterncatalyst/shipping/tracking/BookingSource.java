package com.patterncatalyst.shipping.tracking;

import java.util.List;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * The booking service's side of the tracking view: {@code getCargo},
 * {@code getCargos} and {@code listCargos}. The booking service lists {@code GHI345} but cannot load
 * it: the index is a separate, healthy store, which is what lets one edge fail
 * while its page does not.
 *
 * <p>This class is the one place the ownership rule is applied. Every read takes
 * the caller's {@link Viewer}, and a cargo the viewer may not see is null exactly
 * like an unknown id, in a single read, in a bulk read, and in the index behind
 * {@code cargos}, so {@code totalCount} counts only what the caller can see.
 */
@ApplicationScoped
public class BookingSource {

    private static final String UNAVAILABLE_CARGO = "GHI345";

    private final TrackingData data;
    private final SourceCalls calls;

    BookingSource(TrackingData data, SourceCalls calls) {
        this.data = data;
        this.calls = calls;
    }

    /** Null when the booking service has nothing under that key. */
    public Uni<Cargo> getCargo(String request, String trackingId, Viewer viewer) {
        return calls.call(request, "booking", "getCargo", trackingId, () -> load(trackingId, viewer));
    }

    /**
     * Many cargos in one call. One outcome per tracking id, in the order asked:
     * the cargo, null when unknown, or the failure for that id alone
     * ({@code GHI345}). The log key is the sorted distinct ids joined with {@code +}.
     */
    public Uni<List<Outcome<Cargo>>> getCargos(String request, List<String> trackingIds, Viewer viewer) {
        return calls.callBatch(request, "booking", "getCargos", trackingIds, id -> load(id, viewer));
    }

    private Cargo load(String trackingId, Viewer viewer) {
        // The rule runs before the load: a cargo the viewer may not see is not
        // loaded, so its outage (GHI345) cannot reveal that it exists.
        if (!viewer.canSee(data.owner(trackingId))) {
            return null;
        }
        if (UNAVAILABLE_CARGO.equals(trackingId)) {
            throw new SourceUnavailableException("booking service unavailable");
        }
        return data.cargo(trackingId);
    }

    /**
     * One page of the booking index, newest booking first, optionally only the
     * rows with {@code routingStatus}. The log key is the filter, or {@code *}
     * for none.
     */
    public Uni<Pagination.Slice<TrackingData.BookingEntry>> listCargos(
            String request, RoutingStatus routingStatus, Pagination.Page<Pagination.CargoKey> page, Viewer viewer) {
        String key = routingStatus == null ? "*" : routingStatus.name();
        return calls.call(
                request,
                "booking",
                "listCargos",
                key,
                () -> Pagination.slice(
                        data.bookingIndex().stream()
                                .filter(row -> viewer.canSee(data.owner(row.trackingId())))
                                .filter(row -> routingStatus == null || row.routingStatus() == routingStatus)
                                .toList(),
                        TrackingData.BookingEntry::key,
                        page));
    }
}
