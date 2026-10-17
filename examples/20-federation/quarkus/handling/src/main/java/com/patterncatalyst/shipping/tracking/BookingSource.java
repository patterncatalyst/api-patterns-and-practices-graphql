package com.patterncatalyst.shipping.tracking;

import java.util.List;

import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * The booking service's side of the tracking view: {@code getCargo} and
 * {@code getCargos}. The booking service cannot load {@code GHI345}.
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
}
