package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

import io.smallrye.graphql.api.federation.FieldSet;
import io.smallrye.graphql.api.federation.Key;

/** A reference to a voyage, by its number; the cargo subgraph owns the rest (see {@link Location}). */
@Type("Voyage")
@Key(fields = @FieldSet("number"), resolvable = false)
@Description("A scheduled carrier movement made up of one or more legs.")
public record Voyage(@NonNull @Description("The carrier's voyage number, for example `V100S`.") String number) {}
