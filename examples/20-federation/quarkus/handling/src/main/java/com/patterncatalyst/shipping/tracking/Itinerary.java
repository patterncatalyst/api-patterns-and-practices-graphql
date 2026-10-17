package com.patterncatalyst.shipping.tracking;

import java.time.Instant;
import java.util.List;

/** What the routing service returns for a cargo: the legs, and when the last one arrives. */
public record Itinerary(List<Leg> legs, Instant finalArrivalTime) {}
