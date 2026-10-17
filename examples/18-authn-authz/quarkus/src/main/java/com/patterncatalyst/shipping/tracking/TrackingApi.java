package com.patterncatalyst.shipping.tracking;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.IntStream;

import org.eclipse.microprofile.graphql.Description;
import org.eclipse.microprofile.graphql.GraphQLApi;
import org.eclipse.microprofile.graphql.Id;
import org.eclipse.microprofile.graphql.Name;
import org.eclipse.microprofile.graphql.NonNull;
import org.eclipse.microprofile.graphql.Query;
import org.eclipse.microprofile.graphql.Source;

import io.quarkus.security.Authenticated;
import io.smallrye.graphql.api.Context;
import io.smallrye.mutiny.Uni;

/**
 * The tracking view. A failing source surfaces as an execution error:
 * {@link SourceUnavailableException} is shown to the client, any other
 * exception is masked. Every resolver that reads a source returns a
 * {@code Uni}, Mutiny's lazy single-value type, so SmallRye hands the engine a
 * pending result instead of blocking a thread on it, and the engine is free to
 * start sibling fields before any of them finish.
 *
 * <p>The fields of a type that appears in a list are batch resolvers: a method
 * whose {@code @Source} parameter is a {@code List}. SmallRye turns such a method
 * into a graphql-java {@code DataLoader}, one per field per request, and calls
 * the method once with every parent the level collected. The method returns one
 * value per parent, in the parents' order. The root fields ({@code cargo},
 * {@code location}, {@code voyage}, {@code node}) have no parent to collect and
 * stay one source call each.
 *
 * <p>Each resolver takes the SmallRye {@link Context} and reads
 * {@code getExecutionId()} on entry, while it is still on the request's
 * thread: the id travels to the source as an argument, because a continuation
 * that resumes after a delay does not run where the request started. The
 * caller's {@link Viewer} is read the same way, once per resolver, and handed to
 * the booking source, which applies the ownership rule. {@code cargo} and
 * {@code cargos} need a signed-in caller ({@code @Authenticated}); {@code node} and
 * {@code nodes} stay open and return null for an object the caller may not see.
 */
@GraphQLApi
@SecurityErrors
public class TrackingApi {

    private final BookingSource booking;
    private final RoutingSource routing;
    private final VoyageSource voyages;
    private final LocationSource locations;
    private final HandlingSource handling;
    private final DeliveryDerivation derivation;
    private final Viewers viewers;

    TrackingApi(
            BookingSource booking,
            RoutingSource routing,
            VoyageSource voyages,
            LocationSource locations,
            HandlingSource handling,
            DeliveryDerivation derivation,
            Viewers viewers) {
        this.booking = booking;
        this.routing = routing;
        this.voyages = voyages;
        this.locations = locations;
        this.handling = handling;
        this.derivation = derivation;
        this.viewers = viewers;
    }

    @Query
    @Authenticated
    @Description("Look up one cargo by its tracking id. Null when no such cargo exists.")
    public Uni<Cargo> cargo(
            @Name("trackingId") @NonNull @Description("The tracking id issued at booking.") TrackingId trackingId,
            Context context) {
        return booking.getCargo(context.getExecutionId(), trackingId.value(), viewers.current());
    }

    @Query
    @Description("Look up a location by UN/LOCODE. Null when unknown.")
    public Uni<Location> location(
            @Name("unLocode") @NonNull @Description("The UN/LOCODE to look up, for example `NLRTM`.")
                    UnLocode unLocode,
            Context context) {
        return locations.getLocation(context.getExecutionId(), unLocode.value());
    }

    @Query
    @Description("Look up a voyage by voyage number. Null when unknown.")
    public Uni<Voyage> voyage(
            @Name("voyageNumber") @NonNull @Description("The carrier's voyage number, for example `V100S`.")
                    String voyageNumber,
            Context context) {
        return voyages.getVoyage(context.getExecutionId(), voyageNumber);
    }

    @Query
    @Description("Fetch any object by its global id (Relay Global Object Identification).")
    public Uni<Node> node(
            @Name("id") @Id @NonNull @Description("The global id of the object to fetch.") String id,
            Context context) {
        return resolveNode(context.getExecutionId(), id, viewers.current());
    }

    @Query
    @NonNull
    @Description(
            "Fetch several objects by their global ids, in the order given. An unknown id yields null at its position.")
    public Uni<List<Node>> nodes(
            @Name("ids") @NonNull @Description("The global ids of the objects to fetch.") List<@NonNull String> ids,
            Context context) {
        if (ids.isEmpty()) {
            return Uni.createFrom().item(List.of());
        }
        String request = context.getExecutionId();
        Viewer viewer = viewers.current();
        // A root field has no parents for the engine to collect, so it groups
        // its own ids by type: one bulk call per type instead of one per id.
        List<Uni<Map<String, Node>>> groups = List.of(
                bulk(ids, "cargo_", keys -> booking.getCargos(request, keys, viewer)),
                bulk(ids, "loc_", keys -> locations.getLocations(request, keys)),
                bulk(ids, "voy_", keys -> voyages.getVoyages(request, keys)),
                events(request, ids, viewer));
        return Uni.join().all(groups).andFailFast().map(maps -> {
            Map<String, Node> byId = new HashMap<>();
            maps.forEach(byId::putAll);
            // An id nobody resolved (unknown, or a bare prefix) is null at its position.
            return ids.stream().map(byId::get).toList();
        });
    }

    /** The ids of one type, fetched with one bulk call and keyed by their global id. */
    private <T extends Node> Uni<Map<String, Node>> bulk(
            List<String> ids, String prefix, Function<List<String>, Uni<List<Outcome<T>>>> fetch) {
        List<String> keys = ids.stream()
                .filter(id -> id.startsWith(prefix) && id.length() > prefix.length())
                .map(id -> id.substring(prefix.length()))
                .toList();
        if (keys.isEmpty()) {
            return Uni.createFrom().item(Map.of());
        }
        return fetch.apply(keys).map(outcomes -> {
            List<T> values = Outcome.values(outcomes);
            Map<String, Node> byId = new HashMap<>();
            for (int i = 0; i < keys.size(); i++) {
                byId.put(prefix + keys.get(i), values.get(i));
            }
            return byId;
        });
    }

    /** Events have no bulk read, so each id stays its own call. */
    private Uni<Map<String, Node>> events(String request, List<String> ids, Viewer viewer) {
        List<Uni<Node>> fetches = ids.stream()
                .filter(id -> id.startsWith("evt_") && id.length() > "evt_".length())
                .distinct()
                .map(id -> visibleEvent(request, id, viewer))
                .toList();
        if (fetches.isEmpty()) {
            return Uni.createFrom().item(Map.of());
        }
        return Uni.join().all(fetches).andFailFast().map(nodes -> {
            Map<String, Node> byId = new HashMap<>();
            for (Node node : nodes) {
                if (node != null) {
                    byId.put(node.getId(), node);
                }
            }
            return byId;
        });
    }

    /**
     * An event is as visible as the cargo it belongs to: the booking source, the
     * one place the ownership rule lives, decides. Null when either is missing.
     */
    private Uni<Node> visibleEvent(String request, String id, Viewer viewer) {
        return handling.getEvent(request, id).chain(record -> record == null
                ? Uni.createFrom().nullItem()
                : booking.getCargo(request, record.trackingId(), viewer)
                        .<Node>map(cargo -> cargo == null ? null : HandlingEvent.of(record)));
    }

    /** One global id to its object, dispatching on the type prefix. Unknown ids resolve to null. */
    private Uni<Node> resolveNode(String request, String id, Viewer viewer) {
        int sep = id.indexOf('_');
        if (sep < 0 || sep == id.length() - 1) {
            return Uni.createFrom().nullItem();
        }
        if (id.startsWith("cargo_")) {
            return booking.getCargo(request, id.substring("cargo_".length()), viewer).map(Node.class::cast);
        }
        if (id.startsWith("loc_")) {
            return locations.getLocation(request, id.substring("loc_".length())).map(Node.class::cast);
        }
        if (id.startsWith("voy_")) {
            return voyages.getVoyage(request, id.substring("voy_".length())).map(Node.class::cast);
        }
        if (id.startsWith("evt_")) {
            return visibleEvent(request, id, viewer);
        }
        return Uni.createFrom().nullItem();
    }

    @Query
    @Authenticated
    @NonNull
    @Description("List cargos, newest first, as a Relay connection.")
    public Uni<CargoConnection> cargos(
            @Name("first") @Description("Return the first N cargos.") Integer first,
            @Name("after") @Description("Return cargos after this cursor.") String after,
            @Name("last") @Description("Return the last N cargos.") Integer last,
            @Name("before") @Description("Return cargos before this cursor.") String before,
            @Name("routingStatus") @Description("Only cargos with this routing status.") RoutingStatus routingStatus,
            Context context) {
        Pagination.Page<Pagination.CargoKey> page = Pagination.page(first, after, last, before, Pagination::decodeCargo);
        return booking.listCargos(context.getExecutionId(), routingStatus, page, viewers.current()).map(slice -> {
            List<CargoEdge> edges = slice.items().stream()
                    .map(row -> new CargoEdge(Pagination.encodeCargo(row.key()), row.trackingId()))
                    .toList();
            return new CargoConnection(
                    edges,
                    PageInfo.of(
                            slice.hasNext(),
                            slice.hasPrevious(),
                            edges.stream().map(CargoEdge::cursor).toList()),
                    slice.totalCount());
        });
    }

    @Description(
            "The cargo at this edge. Null when the cargo failed to resolve, so one bad item nulls its edge instead of the whole page.")
    public Uni<List<Cargo>> node(@Source List<CargoEdge> edges, Context context) {
        return booking
                .getCargos(
                        context.getExecutionId(),
                        edges.stream().map(CargoEdge::trackingId).toList(),
                        viewers.current())
                .map(Outcome::values);
    }

    @NonNull
    @Description("Handling events for this cargo, newest first, as a Relay connection.")
    public Uni<HandlingEventConnection> handlingHistory(
            @Source Cargo cargo,
            @Name("first") @Description("Return the first N events.") Integer first,
            @Name("after") @Description("Return events after this cursor.") String after,
            @Name("last") @Description("Return the last N events.") Integer last,
            @Name("before") @Description("Return events before this cursor.") String before,
            Context context) {
        Pagination.Page<Pagination.EventKey> page = Pagination.page(first, after, last, before, Pagination::decodeEvent);
        return handling.pageEvents(context.getExecutionId(), cargo.trackingId().value(), page).map(slice -> {
            List<HandlingEventEdge> edges = slice.items().stream()
                    .map(record -> new HandlingEventEdge(Pagination.encodeEvent(record.key()), HandlingEvent.of(record)))
                    .toList();
            return new HandlingEventConnection(
                    edges,
                    PageInfo.of(
                            slice.hasNext(),
                            slice.hasPrevious(),
                            edges.stream().map(HandlingEventEdge::cursor).toList()),
                    slice.totalCount());
        });
    }

    @Description("The planned route. Null until the routing service has assigned one.")
    public Uni<List<Itinerary>> itinerary(@Source List<Cargo> cargos, Context context) {
        return routing.getItineraries(context.getExecutionId(), trackingIds(cargos)).map(Outcome::values);
    }

    @NonNull
    @Description("Delivery status derived from handling history.")
    public Uni<List<Delivery>> delivery(@Source List<Cargo> cargos, Context context) {
        String request = context.getExecutionId();
        List<String> ids = trackingIds(cargos);
        // The two inputs are independent, so they are fetched together; the
        // derivation itself calls no source.
        return Uni.combine()
                .all()
                .unis(routing.getItineraries(request, ids), handling.listEventsFor(request, ids))
                .with((itineraries, events) -> {
                    List<Itinerary> planned = Outcome.values(itineraries);
                    List<List<HandlingRecord>> recorded = Outcome.values(events);
                    return IntStream.range(0, cargos.size())
                            .mapToObj(i -> derivation.derive(cargos.get(i), planned.get(i), recorded.get(i)))
                            .toList();
                });
    }

    @Description("The voyage that carries this leg. Null when the voyage service is unavailable.")
    public Uni<List<Voyage>> voyage(@Source List<Leg> legs, Context context) {
        return voyages.getVoyages(context.getExecutionId(), legs.stream().map(Leg::voyageNumber).toList())
                .map(Outcome::values);
    }

    @NonNull
    @Description("Where the cargo is loaded.")
    public Uni<List<Location>> loadLocation(@Source List<Leg> legs, Context context) {
        return locations
                .getLocations(context.getExecutionId(), legs.stream().map(Leg::loadUnLocode).toList())
                .map(Outcome::values);
    }

    @NonNull
    @Description("Where the cargo is unloaded.")
    public Uni<List<Location>> unloadLocation(@Source List<Leg> legs, Context context) {
        return locations
                .getLocations(context.getExecutionId(), legs.stream().map(Leg::unloadUnLocode).toList())
                .map(Outcome::values);
    }

    private static List<String> trackingIds(List<Cargo> cargos) {
        return cargos.stream().map(cargo -> cargo.trackingId().value()).toList();
    }
}
