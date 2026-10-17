package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

/**
 * What the handling service returns for one event. It is not a GraphQL type in
 * this chapter, so no resolver returns it: it is an input to
 * {@link DeliveryDerivation}, and {@code HandlingEvent} joins the schema with
 * the mutation in Chapter 8.
 */
public record HandlingRecord(
        String id,
        String trackingId,
        HandlingEventType type,
        String unLocode,
        String voyageNumber,
        Instant completionTime,
        Instant registrationTime) {}
