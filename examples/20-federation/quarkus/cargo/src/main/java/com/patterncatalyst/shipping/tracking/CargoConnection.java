package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

@Type("CargoConnection")
@Description("A Relay connection of cargos.")
public record CargoConnection(
        @NonNull @Description("The edges in this page.") List<@NonNull CargoEdge> edges,
        @NonNull @Description("Pagination metadata.") PageInfo pageInfo,
        @Description("Total matching cargos. Null when counting is too expensive.") Integer totalCount) {}
