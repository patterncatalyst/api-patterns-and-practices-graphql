package com.patterncatalyst.shipping.tracking;

import io.smallrye.graphql.api.ErrorCode;

/**
 * A signed-in caller without the {@code operator} role reached an operation or a
 * field that needs it. {@link SecurityErrorTranslator} raises it in place of
 * Quarkus's {@code ForbiddenException}, with the contract's message.
 */
@ErrorCode("FORBIDDEN")
public class OperatorRoleRequiredException extends RuntimeException {

    public OperatorRoleRequiredException() {
        super("operator role required");
    }
}
