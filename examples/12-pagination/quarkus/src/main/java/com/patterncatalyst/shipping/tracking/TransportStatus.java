package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;

@Description("Where a cargo currently is relative to its plan.")
public enum TransportStatus {
    @Description("Booked but not yet received.")
    NOT_RECEIVED,
    @Description("Received at origin and awaiting loading.")
    IN_PORT,
    @Description("Aboard a vessel.")
    ONBOARD_CARRIER,
    @Description("Handed over at the final destination.")
    CLAIMED,
    @Description("Whereabouts unknown.")
    UNKNOWN
}
