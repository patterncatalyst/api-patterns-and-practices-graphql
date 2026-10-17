package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("UserError")
@Description("A domain validation failure returned as data, not as a top-level error.")
public record UserError(
        @NonNull @Description("A stable machine-readable code.") UserErrorCode code,
        @NonNull @Description("A human-readable explanation.") String message,
        @Description(
                        "Path to the input field the error concerns, for example `[\"input\", \"voyageNumber\"]`. Null when it concerns the whole input.")
                List<@NonNull String> field) {}
