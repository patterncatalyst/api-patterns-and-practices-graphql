package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.Interface;
import org.eclipse.microprofile.graphql.NonNull;

/**
 * The {@code Node} interface. SmallRye GraphQL maps an interface's fields from
 * its getter-named methods, so the interface declares {@code getId()} and each
 * implementing record carries an explicit {@code getId()}.
 */
@Interface
@Description("""
        A global object identifier, unique across the whole graph. Implements the
        Relay Global Object Identification contract used by `Query.node`.""")
public interface Node {

    @Id
    @NonNull
    @Description("The globally unique, opaque identifier of this object.")
    String getId();
}
