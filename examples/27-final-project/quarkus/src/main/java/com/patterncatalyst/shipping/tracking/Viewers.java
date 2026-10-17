package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.jwt.JsonWebToken;

import io.quarkus.security.identity.SecurityIdentity;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * Turns the request's {@link SecurityIdentity} into a {@link Viewer}. Quarkus
 * OIDC has already validated the token (signature from the JWKS, issuer,
 * audience, expiry) and mapped {@code realm_access/roles} to roles; this class
 * reads only the result. Call {@link #current()} at resolver entry, while the
 * request's identity is still associated with the thread: the viewer then travels
 * to the sources as an argument, like the request id.
 */
@ApplicationScoped
public class Viewers {

    private final SecurityIdentity identity;

    Viewers(SecurityIdentity identity) {
        this.identity = identity;
    }

    public Viewer current() {
        if (identity.isAnonymous()) {
            return Viewer.ANONYMOUS;
        }
        String shipper = identity.getPrincipal() instanceof JsonWebToken token ? token.getClaim("shipper") : null;
        return new Viewer(identity.hasRole("operator"), shipper);
    }
}
