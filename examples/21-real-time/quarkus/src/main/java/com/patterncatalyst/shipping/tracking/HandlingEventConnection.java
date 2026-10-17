package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("HandlingEventConnection")
@Description("A Relay connection of handling events.")
public record HandlingEventConnection(
        @NonNull @Description("The edges in this page.") List<@NonNull HandlingEventEdge> edges,
        @NonNull @Description("Pagination metadata.") PageInfo pageInfo,
        @Description("Total events for the cargo. Null when counting is too expensive.") Integer totalCount) {}
