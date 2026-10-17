package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

/** One hop of an itinerary, as the routing service returns it: a voyage number, two UN/LOCODEs and two times. */
public record Leg(
        String voyageNumber, String loadUnLocode, String unloadUnLocode, Instant loadTime, Instant unloadTime) {}
