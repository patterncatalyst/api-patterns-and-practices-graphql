package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

/** A validated registration, before the store gives it an id and a registration time. */
public record NewHandling(
        String trackingId, HandlingEventType type, String unLocode, String voyageNumber, Instant completionTime) {}
