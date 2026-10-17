package com.patterncatalyst.shipping.tracking;

/** What the booking service holds about the route a cargo must satisfy; the delivery derivation compares the itinerary with it. */
public record RouteSpecification(Location origin, Location destination) {}
