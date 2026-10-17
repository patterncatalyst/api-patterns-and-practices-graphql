package com.patterncatalyst.shipping.tracking;

import java.util.List;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Type;

/** The page metadata of Relay's "PageInfo"; both directions are computed, not approximated. */
@Type("PageInfo")
@Description("""
        Relay cursor-connection page metadata.
        See https://relay.dev/graphql/connections.htm""")
public record PageInfo(
        @Description("True when more edges exist after `endCursor`.") boolean hasNextPage,
        @Description("True when more edges exist before `startCursor`.") boolean hasPreviousPage,
        @Description("Cursor of the first edge in this page; null when the page is empty.") String startCursor,
        @Description("Cursor of the last edge in this page; null when the page is empty.") String endCursor) {

    /** The metadata of a page whose edges carry {@code cursors}, in order. */
    static PageInfo of(boolean hasNextPage, boolean hasPreviousPage, List<String> cursors) {
        return new PageInfo(
                hasNextPage,
                hasPreviousPage,
                cursors.isEmpty() ? null : cursors.getFirst(),
                cursors.isEmpty() ? null : cursors.getLast());
    }
}
