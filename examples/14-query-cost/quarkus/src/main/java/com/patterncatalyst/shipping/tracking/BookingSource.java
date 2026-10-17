package com.patterncatalyst.shipping.tracking;

import java.util.List;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * The booking service's side of the tracking view: {@code getCargo},
 * {@code getCargos} and {@code listCargos}. The booking service lists {@code GHI345} but cannot load
 * it: the index is a separate, healthy store, which is what lets one edge fail
 * while its page does not.
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
    public Uni<Cargo> getCargo(String request, String trackingId) {
        return calls.call(request, "booking", "getCargo", trackingId, () -> load(trackingId));
    }

    /**
     * Many cargos in one call. One outcome per tracking id, in the order asked:
     * the cargo, null when unknown, or the failure for that id alone
     * ({@code GHI345}). The log key is the sorted distinct ids joined with {@code +}.
     */
    public Uni<List<Outcome<Cargo>>> getCargos(String request, List<String> trackingIds) {
        return calls.callBatch(request, "booking", "getCargos", trackingIds, this::load);
    }

    private Cargo load(String trackingId) {
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
            String request, RoutingStatus routingStatus, Pagination.Page<Pagination.CargoKey> page) {
        String key = routingStatus == null ? "*" : routingStatus.name();
        return calls.call(
                request,
                "booking",
                "listCargos",
                key,
                () -> Pagination.slice(
                        data.bookingIndex().stream()
                                .filter(row -> routingStatus == null || row.routingStatus() == routingStatus)
                                .toList(),
                        TrackingData.BookingEntry::key,
                        page));
    }
}
