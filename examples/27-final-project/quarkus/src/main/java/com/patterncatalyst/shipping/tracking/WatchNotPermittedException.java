package com.patterncatalyst.shipping.tracking;

import io.smallrye.graphql.api.ErrorCode;

/**
 * A signed-in caller asked to watch a cargo it may not see. The code is
 * {@code FORBIDDEN}, the same one {@link OperatorRoleRequiredException} carries,
 * and the message is shown to the client like the other exceptions of the
 * vocabulary. An unknown cargo answers the same way, so the error does not tell
 * a caller which tracking ids exist.
 */
@ErrorCode("FORBIDDEN")
public class WatchNotPermittedException extends RuntimeException {

    public WatchNotPermittedException() {
        super("not permitted to watch this cargo");
    }
}
