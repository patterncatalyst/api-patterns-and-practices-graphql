package com.patterncatalyst.shipping.tracking;

import io.smallrye.graphql.api.ErrorCode;

/**
 * A value that passed input coercion but is not acceptable: a page size out of
 * range, or a cursor this connection did not issue. Like
 * {@link SourceUnavailableException} it is shown to the client, because
 * {@code show-runtime-exception-message} lists the class, and its
 * {@code extensions.code} is {@code BAD_USER_INPUT}.
 */
@ErrorCode("BAD_USER_INPUT")
public class BadUserInputException extends RuntimeException {

    public BadUserInputException(String message) {
        super(message);
    }
}
