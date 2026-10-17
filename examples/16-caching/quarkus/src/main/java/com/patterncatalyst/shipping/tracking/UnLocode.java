package com.patterncatalyst.shipping.tracking;

import org.eclipse.microprofile.graphql.Description;

import io.smallrye.graphql.api.CustomScalar;
import io.smallrye.graphql.api.CustomStringScalar;

/** The {@code UnLocode} custom scalar (see {@link TrackingId} for the mapping). */
@CustomScalar("UnLocode")
@Description("""
        A UN/LOCODE port or terminal code: two letters of country plus three of
        location, for example `USNYC`, `NLRTM` or `SGSIN`.""")
public record UnLocode(String value) implements CustomStringScalar {

    @Override
    public String stringValueForSerialization() {
        return value;
    }
}
