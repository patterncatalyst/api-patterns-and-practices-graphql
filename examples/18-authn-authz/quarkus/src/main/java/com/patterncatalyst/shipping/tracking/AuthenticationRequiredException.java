package com.patterncatalyst.shipping.tracking;

import io.smallrye.graphql.api.ErrorCode;

/**
 * An anonymous caller reached an operation that needs a signed-in one. Like
 * {@link SourceUnavailableException}, it is shown to the client, with a code from
 * the vocabulary. {@link SecurityErrorTranslator} raises it in place of Quarkus's
 * {@code UnauthorizedException}, with the contract's message.
 */
@ErrorCode("UNAUTHENTICATED")
public class AuthenticationRequiredException extends RuntimeException {

    public AuthenticationRequiredException() {
        super("authentication required");
    }
}
