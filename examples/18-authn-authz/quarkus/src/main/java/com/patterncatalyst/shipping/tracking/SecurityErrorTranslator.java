package com.patterncatalyst.shipping.tracking;

import io.quarkus.security.ForbiddenException;
import io.quarkus.security.UnauthorizedException;
import io.smallrye.mutiny.Uni;
import jakarta.annotation.Priority;
import jakarta.interceptor.AroundInvoke;
import jakarta.interceptor.Interceptor;
import jakarta.interceptor.InvocationContext;

/**
 * Gives the failures of {@code @Authenticated} and {@code @RolesAllowed} a message
 * and a code a GraphQL client can use. Quarkus signals them with
 * {@code UnauthorizedException} and {@code ForbiddenException}. This interceptor
 * gives both refusals the contract's messages: it runs outside Quarkus's own security interceptor (priority 150) and swaps the two
 * exceptions for {@link AuthenticationRequiredException} and
 * {@link OperatorRoleRequiredException}, which {@code application.properties}
 * allows through the error mask. The check itself stays the framework's.
 *
 * <p>Every {@code ForbiddenException} maps to "operator role required", because in
 * this example the operator role is the only one that can refuse.
 *
 * <p>A synchronous resolver fails by throwing; a resolver that returns a
 * {@code Uni} fails inside the {@code Uni}. Both are handled.
 */
@SecurityErrors
@Interceptor
@Priority(Interceptor.Priority.PLATFORM_BEFORE + 100)
public class SecurityErrorTranslator {

    @AroundInvoke
    Object translate(InvocationContext context) throws Exception {
        try {
            Object result = context.proceed();
            return result instanceof Uni<?> uni ? uni.onFailure().transform(SecurityErrorTranslator::translated) : result;
        } catch (UnauthorizedException failure) {
            throw new AuthenticationRequiredException();
        } catch (ForbiddenException failure) {
            throw new OperatorRoleRequiredException();
        }
    }

    private static Throwable translated(Throwable failure) {
        return switch (failure) {
            case UnauthorizedException ignored -> new AuthenticationRequiredException();
            case ForbiddenException ignored -> new OperatorRoleRequiredException();
            default -> failure;
        };
    }
}
