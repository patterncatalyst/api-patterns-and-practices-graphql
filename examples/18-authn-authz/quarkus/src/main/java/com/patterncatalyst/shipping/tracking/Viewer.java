package com.patterncatalyst.shipping.tracking;

/**
 * Who is asking, as far as ownership is concerned: an operator sees every
 * cargo, a shipper sees the cargos its organisation owns, and an anonymous
 * caller sees none. {@link Viewers} builds it from the request's
 * {@code SecurityIdentity} at resolver entry; {@link BookingSource} is the only
 * class that applies it.
 */
public record Viewer(boolean operator, String shipper) {

    public static final Viewer ANONYMOUS = new Viewer(false, null);

    /** Whether this viewer may see a cargo owned by {@code owner} (null for an unknown cargo). */
    public boolean canSee(String owner) {
        return operator || (owner != null && owner.equals(shipper));
    }
}
