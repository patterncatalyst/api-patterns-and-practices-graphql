package com.patterncatalyst.shipping.tracking;

import io.smallrye.graphql.api.ErrorCode;

/**
 * A source that cannot answer. It is the one exception this service chooses to
 * show a client: its message reaches the response because
 * {@code quarkus.smallrye-graphql.show-runtime-exception-message} lists the class
 * (see application.properties), and {@link ErrorCode} sets
 * {@code extensions.code} from the service's vocabulary.
 */
@ErrorCode("SERVICE_UNAVAILABLE")
public class SourceUnavailableException extends RuntimeException {

    public SourceUnavailableException(String message) {
        super(message);
    }
}
