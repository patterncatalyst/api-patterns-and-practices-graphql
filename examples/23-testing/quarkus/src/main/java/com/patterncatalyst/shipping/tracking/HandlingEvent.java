package com.patterncatalyst.shipping.tracking;

import java.time.Instant;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.Ignore;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Type;

/**
 * A recorded handling. Like {@link Leg}, it keeps the keys of what other
 * services own ({@code unLocode}, {@code voyageNumber}) out of the schema;
 * {@link HandlingApi} resolves {@code location}, {@code voyage} and
 * {@code cargo} from the location, voyage and booking sources.
 */
@Type("HandlingEvent")
@Description("A recorded handling of a cargo at a location, optionally on a voyage.")
public record HandlingEvent(
        String id,
        @NonNull @Description("The tracking id of the cargo that was handled.") TrackingId trackingId,
        @NonNull @Description("What kind of handling occurred.") HandlingEventType type,
        @Ignore String unLocode,
        @Ignore String voyageNumber,
        @NonNull @Description("When the handling actually happened.") Instant completionTime,
        @NonNull @Description("When the event was registered in the system.") Instant registrationTime)
        implements Node {

    static HandlingEvent of(HandlingRecord record) {
        return new HandlingEvent(
                record.id(),
                new TrackingId(record.trackingId()),
                record.type(),
                record.unLocode(),
                record.voyageNumber(),
                record.completionTime(),
                record.registrationTime());
    }

    @Override
    @Id
    @NonNull
    @Description("The globally unique identifier of this event.")
    public String getId() {
        return id;
    }
}
