package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Input;
import org.eclipse.microprofile.graphql.NonNull;

@Input("RegisterHandlingEventInput")
@Description("Input for `Mutation.registerHandlingEvent`.")
public record RegisterHandlingEventInput(
        @NonNull @Description("The cargo that was handled.") TrackingId trackingId,
        @NonNull @Description("What kind of handling occurred.") HandlingEventType type,
        @NonNull @Description("Where it occurred.") UnLocode location,
        @Description("The voyage number; required for LOAD and UNLOAD, forbidden otherwise.") String voyageNumber,
        @NonNull @Description("When the handling actually happened.") Instant completionTime,
        @Description(
                        "Client-supplied key making retries safe: a repeated request with the same key returns the originally recorded event instead of recording a second one.")
                String idempotencyKey) {}
