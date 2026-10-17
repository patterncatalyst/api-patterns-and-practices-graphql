package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;

@Description("Machine-readable reasons a mutation input was rejected.")
public enum UserErrorCode {
    @Description("No cargo exists with the given tracking id.")
    UNKNOWN_CARGO,
    @Description("No location exists with the given UN/LOCODE.")
    UNKNOWN_LOCATION,
    @Description("No voyage exists with the given voyage number.")
    UNKNOWN_VOYAGE,
    @Description("LOAD and UNLOAD events must name a voyage.")
    VOYAGE_REQUIRED,
    @Description("RECEIVE, CUSTOMS and CLAIM events must not name a voyage.")
    VOYAGE_NOT_ALLOWED,
    @Description("The completion time is in the future or otherwise invalid.")
    INVALID_COMPLETION_TIME
}
