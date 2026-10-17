package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;

@Description("The kind of handling a cargo underwent.")
public enum HandlingEventType {
    @Description("Received from the shipper at origin.")
    RECEIVE,
    @Description("Loaded onto a vessel.")
    LOAD,
    @Description("Unloaded from a vessel.")
    UNLOAD,
    @Description("Cleared by customs.")
    CUSTOMS,
    @Description("Claimed by the consignee at destination.")
    CLAIM
}
