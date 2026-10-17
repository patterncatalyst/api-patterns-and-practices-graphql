package com.patterncatalyst.shipping.tracking;

import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.nullValue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.smallrye.mutiny.Uni;

/**
 * Resolver layer with a stubbed source. {@code @InjectMock} replaces the
 * application-scoped {@link BookingSource} for the test, so the resolver runs
 * as written and the booking service fails on demand.
 */
@QuarkusTest
class BookingFailureTest {

    @InjectMock
    BookingSource booking;

    @Test
    void anUnavailableBookingServiceIsAnErrorAtTheCargoFieldWithItsCode() {
        when(booking.getCargo(any(), eq("ABC123")))
                .thenReturn(Uni.createFrom().failure(new SourceUnavailableException("booking service unavailable")));

        Documents.post("{ cargo(trackingId: \"ABC123\") { trackingId } }")
                .body("data.cargo", nullValue())
                .body("errors", hasSize(1))
                .body("errors[0].path", contains("cargo"))
                .body("errors[0].message", equalTo("booking service unavailable"))
                .body("errors[0].extensions.code", equalTo("SERVICE_UNAVAILABLE"));
    }
}
