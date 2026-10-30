---
title: "Connections and pagination"
order: 12
part: "Data Fetching at Scale"
description: "How a growing list becomes a Relay connection: offset against keyset pagination, edges, nodes and PageInfo, opaque versioned cursors, forward and backward paging, stability under inserts, filters and totalCount, bad arguments as BAD_USER_INPUT, one failing node nulling one edge, and the source calls a page costs."
duration: "15 min read"
---

## Learning objectives

By the end of this chapter you can:

- Explain why keyset pagination with opaque cursors stays stable under inserts where offset pagination repeats or skips rows.
- Build a Relay connection (`edges`, `node`, `cursor`, and `pageInfo`) with a nullable `node` so one failing item nulls only its edge.
- Encode and validate an opaque, versioned cursor like `cargo|v1|<bookedAt>|<trackingId>`, rejecting anything the server didn't issue.
- Page forward with `first`/`after` and backward with `last`/`before`, computing `hasNextPage`/`hasPreviousPage` exactly from the slice.
- Reject invalid arguments such as an out-of-range `first` as an exposed `BAD_USER_INPUT` error rather than silently clamping them.

## Why this matters

Every list in the tracking view so far has been short. A cargo has two legs and a handful of events, so a client reads all of them and nothing breaks. A cargo that has been handled for months has hundreds of events, and the list of cargos itself has no natural end. Both lists become pages a client walks one at a time, and the walk has a cost on the sources behind it.

The code is in `examples/12-pagination/`. It starts from the error-handling example, so the exposed and masked error machinery is still there, and it carries `Query.nodes` from schema design and the `finalArrivalTime` deprecation from the evolution chapter. The earlier fault seeds are gone. The seed now holds six cargos, DEF456 has a full seven-event history, and one fault remains: the booking service lists `GHI345` but cannot load it. The example adds `Query.cargos` and `Cargo.handlingHistory`, with the types `CargoConnection`, `CargoEdge`, `HandlingEventConnection`, `HandlingEventEdge` and `PageInfo`. Only `Subscription`, built later, is left unserved.

## Lists that grow need pages

An unbounded list field makes the cost of a query depend on data the client does not control. The same `handlingHistory` selection returns two events today and two thousand next year, and the response size, the time spent in the handling service and the memory held while the engine assembles the result all grow with it. A page size puts a ceiling on that cost, and a cursor lets the client continue from where it stopped. Query cost as a property of the whole query is covered later. Here the concern is the shape of one list.

The ceiling has to hold when the client says nothing. A server that returns everything when `first` is absent has no ceiling at all, so a request without `first` or `last` gets a default page of 10, and no request may ask for more than 50. Those two numbers are part of the contract in the sense that matters: a client written against the default will break if the default grows to 100, so a change to either is a decision, not a tuning knob.

The shape also has to be settled early. Turning a plain list into a connection changes the field's type, which is a breaking change for every client that selects it, so a list that may grow starts as a connection.

## Offset versus keyset

Two designs answer "give me the next page". Offset pagination counts: skip the first N rows and take the next M. Keyset pagination seeks: take the rows whose sort key comes after the last key the client saw. The first is simple to write, and its failure is silent. The second needs an ordering that is stable and unique, and it never miscounts.

Offset breaks when the data changes between two requests, and the tracking view shows it. DEF456's history has seven events. Read three at a time, the first page is `evt_9`, `evt_8`, `evt_7`. Then a customs event that completed at `2026-10-11T20:00:00Z` is registered late and becomes `evt_10`. By completion time it belongs between `evt_8` and `evt_7`, in the part of the list the client has already read. A client that asks for "skip 3, take 3" now gets `evt_7`, `evt_6`, `evt_5`: `evt_7` twice, because everything below the insert moved down one place. A client that sends the cursor of `evt_7` gets `evt_6`, `evt_5`, `evt_4`, with no repeat and no gap, because the cursor names a position in the ordering and not a row count.

{% include excalidraw.html file="12-offset-vs-keyset" alt="The figure has three horizontal lanes. The top lane lists the history of DEF456 after the insert, newest first: evt_9, evt_8, evt_10 highlighted, evt_7, evt_6, evt_5, evt_4 and evt_3, each with its completion time. The middle lane, offset, shows a dashed box for three skipped items and then evt_7, evt_6 and evt_5, with evt_7 highlighted and labelled as a repeat, joined by a dashed arrow to evt_7 in the top lane. The bottom lane, keyset, shows a dashed box for a seek past the key of evt_7 and then evt_6, evt_5 and evt_4. A note says that before the insert, page one was evt_9, evt_8, evt_7 and page two was evt_6, evt_5, evt_4." caption="Figure 12.1: The same insert, two pagination designs. Offset repeats evt_7; the keyset cursor seeks past it." %}

Martin Kleppmann and Chris Riccomini explain why the seek is cheap in *Designing Data-Intensive Applications*, 2nd edition, where they cover indexes. An ordered index keeps keys sorted, so a range scan starts at a key and reads forward, where an offset has to walk past every skipped row. The sort key must be total, which is why both connections here break ties: cargos by booking time and then tracking id, events by completion time and then the number in `evt_<n>`.

## The connection shape

A connection is the Relay answer to "a page of a list". The "Connection Types" and "Edge Types" sections of the [Cursor Connections](https://relay.dev/graphql/connections.htm) specification define it: a connection has `edges` and `pageInfo`, and an edge has a `node` and a `cursor`. The canonical SDL adds a nullable `totalCount`.

{% include excalidraw.html file="12-connection-anatomy" alt="Query.cargos returns a CargoConnection with three fields: edges, a list of CargoEdge, pageInfo, a PageInfo, and totalCount, a nullable Int. A CargoEdge has a cursor, a non-null String, and a node, a nullable Cargo, marked in amber. PageInfo has hasNextPage and hasPreviousPage, both non-null Boolean, and startCursor and endCursor, both nullable String. Cargo has a handlingHistory field that is itself a connection." caption="Figure 12.2: The shape of a connection. The edge's node is the one nullable link in the chain." %}

The cursor sits on the edge, not on the node, because it names a position in this connection and the same cargo could appear in another connection with a different cursor. `pageInfo` answers the two questions a client has after reading a page: is there more in each direction, and where do I continue from. `startCursor` and `endCursor` are null on an empty page, since there is no edge to take them from.

The node is nullable by design. The SDL describes it as "Null when the cargo failed to resolve, so one bad item nulls its edge instead of the whole page." That is the fourth nullability fuse that nullability propagation promised, and a later section reads it on a live page.

## Cursors are opaque

A client holds a cursor and hands it back. It must not read it, build one or compare two. The server is then free to change what a cursor contains, and the specification asks for exactly that: the "Edge Types" section says a client should treat a cursor as opaque, and "Arguments" says it comes back as `after` or `before`.

This example encodes the sort key. The cargo cursor is the URL-safe base64 of the UTF-8 text `cargo|v1|<bookedAt>|<trackingId>`, without padding, and the event cursor is `evt|v1|<completionTime>|<n>`. The cursor of the first cargo is the encoding of `cargo|v1|2026-09-29T09:00:00Z|VWX901`, and both stacks return it byte for byte. Three parts do the work. The prefix names the connection, so a cargo cursor handed to `handlingHistory` is rejected. The version lets a later release change the key without misreading cursors clients still hold. The key fields are what the server seeks on.

The decoder accepts only text it could have issued. A wrong prefix, an unknown version, a different number of fields, a time with a fraction, a padded or non-canonical encoding and plain garbage all fail the same way, and so does a cursor from the other connection. Each is `BAD_USER_INPUT` with the message `after is not a valid cursor for this connection`, or `before` where that argument carried it. Opaque is a rule for clients, and the server is what enforces it: a client that parses a cursor today will break the day the key gains a field, and the version in the prefix is the server's promise that it will notice the change first. Opaque does not mean encrypted: anyone can decode the base64, and the cursor carries nothing a client could not already read. If a cursor had to hide data, it would need a signature or a server-side lookup, and this example needs neither.

## Paging forward

`first` and `after` read forward. The specification's "Pagination algorithm" takes the edges after the `after` cursor, then the first `first` of them. `hasNextPage` is true when edges remain beyond the page, and `endCursor` is the value to send as the next `after`.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Query
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
    return booking.listCargos(context.getExecutionId(), routingStatus, page).map(slice -> {
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
```

```python
@strawberry.field(description="List cargos, newest first, as a Relay connection.")
async def cargos(
    self,
    info: Info[TrackingContext],
    first: Annotated[
        strawberry.Maybe[int | None], strawberry.argument(description="Return the first N cargos.")
    ] = None,
    after: Annotated[
        strawberry.Maybe[str | None], strawberry.argument(description="Return cargos after this cursor.")
    ] = None,
    last: Annotated[
        strawberry.Maybe[int | None], strawberry.argument(description="Return the last N cargos.")
    ] = None,
    before: Annotated[
        strawberry.Maybe[str | None], strawberry.argument(description="Return cargos before this cursor.")
    ] = None,
    routing_status: Annotated[
        strawberry.Maybe[RoutingStatus | None],
        strawberry.argument(
            name="routingStatus", description="Only cargos with this routing status."
        ),
    ] = None,
) -> CargoConnection:
    page = pagination.parse_page(
        pagination.argument(first),
        pagination.argument(after),
        pagination.argument(last),
        pagination.argument(before),
        pagination.decode_cargo,
    )
    cargos = await info.context.booking.list_cargos(pagination.argument(routing_status), page)
    edges = [
        CargoEdge(cursor=pagination.encode_cargo(row.key), tracking_id=row.tracking_id)
        for row in cargos.items
    ]
    return CargoConnection(
        edges=edges,
        page_info=PageInfo.of(cargos.has_next, cargos.has_previous, [e.cursor for e in edges]),
        total_count=cargos.total_count,
    )
```

The resolver does little: it validates, asks the booking source for one page of its index, and wraps the result. The paging itself lives in a small `Pagination` helper on each stack, which owns the argument rules, the cursor codec and the slice, so `Query.cargos` and `Cargo.handlingHistory` cannot drift apart. The Python arguments are `strawberry.Maybe` values with a Python default of `None`. That spelling makes an omitted argument arrive as `None` and a sent one as `Some(value)`, and it keeps the printed SDL free of `= null`, which would be a dangerous change that only a live check notices.

Walked two at a time, the six cargos give `VWX901, XYZ789`, then `STU678, DEF456`, then `ABC123` and `GHI345`. The first page has `hasNextPage` true and `hasPreviousPage` false, the second has both true, and the third has `hasNextPage` false. `totalCount` is 6 on every page.

## Paging backward

`last` and `before` read the other way: the edges before the `before` cursor, then the last `last` of them. The page is still in connection order, newest first, so `last: 2` before the cursor of `ABC123` returns `STU678` and then `DEF456`, the same middle page the second forward step returned. A request with `last: 2` and no cursor returns the end of the list, `ABC123` and `GHI345`.

{% include excalidraw.html file="12-cursor-movement" alt="A strip shows the six cargos in booking order: VWX901, XYZ789, STU678, DEF456, ABC123 and GHI345, each with its booking date and the last characters of its cursor. Below it, three highlighted boxes show the forward pages: page one VWX901 and XYZ789 with hasNext true and hasPrev false, page two STU678 and DEF456 with both true, page three ABC123 and GHI345 with hasNext false and hasPrev true. Arrows labelled endCursor join the pages. A fourth box below shows the backward request, last two before the cursor of ABC123, which selects STU678 and DEF456 with both flags true." caption="Figure 12.3: Three forward pages, each after the previous endCursor, and one backward page selecting the middle of the list." %}

The specification lets a server approximate in the direction a client is not paging: with `first` it may report `hasPreviousPage` as false without checking. This example computes both flags exactly. They fall out of the slice, which knows the position of the page in the whole ordered list, so the page after the first one reports `hasPreviousPage` true and the page before the last reports `hasNextPage` true.

{% include codetabs.html langs="Quarkus|Python" %}

```java
public static <T, K extends Comparable<K>> Slice<T> slice(
        List<T> newestFirst, Function<T, K> key, Page<K> page) {
    int total = newestFirst.size();
    int start = page.after() == null ? 0 : countAtLeast(newestFirst, key, page.after());
    int end = page.before() == null ? total : countGreaterThan(newestFirst, key, page.before());
    end = Math.max(start, end);
    if (page.first() != null) {
        end = Math.min(end, start + page.first());
    }
    if (page.last() != null) {
        start = Math.max(start, end - page.last());
    }
    return new Slice<>(List.copyOf(newestFirst.subList(start, end)), end < total, start > 0, total);
}
```

```python
def slice_[T, K](newest_first: Sequence[T], key: Callable[[T], K], page: Page[K]) -> Slice[T]:
    total = len(newest_first)
    # Items at or before the cursor in connection order are those with a key >= the cursor's.
    start = 0 if page.after is None else sum(1 for item in newest_first if key(item) >= page.after)
    end = total if page.before is None else sum(1 for item in newest_first if key(item) > page.before)
    end = max(start, end)
    if page.first is not None:
        end = min(end, start + page.first)
    if page.last is not None:
        start = max(start, end - page.last)
    return Slice(list(newest_first[start:end]), end < total, start > 0, total)
```

The two windows are positions in the list, found by comparing keys and not by remembering rows. The comparison needs only a key, never the row the key came from. `first: 0` returns no edges, null cursors, `hasNextPage` true and `hasPreviousPage` false: an empty page is a valid answer to a valid question.

## Stable under inserts

The slice compares keys, so a registration that lands in the part of the history a client has already read cannot disturb the next page. The `verify.sh` case is the one in Figure 12.1. It reads DEF456's history three at a time, registers the customs event as `evt_10`, and continues with the cursor of `evt_7`: the next page is `evt_6`, `evt_5`, `evt_4`, and the one after is `evt_3` alone with `hasNextPage` false. A fresh request for the first three events now returns `evt_9`, `evt_8`, `evt_10`, and `totalCount` has moved from 7 to 8. The store keeps completion times in whole seconds, because the cursor encodes the sort key at that precision: an event registered with `2026-10-02T09:00:00.5Z` is stored and returned as `2026-10-02T09:00:00Z`, and the page after its cursor skips nothing.

Keyset has one limit the offset design does not. The client cannot jump to page 40, because a cursor exists only for a position the server has already shown. A screen that needs numbered pages needs offset, or a count taken from `totalCount` and a seek strategy of its own. A feed or a timeline, which is how the tracking view uses its lists, does not need to jump.

## Filters and `totalCount`

`routingStatus` narrows `cargos` to one routing status. The filter is applied where the data is: the booking source reads the status stored in its index and pages only the matching rows, so one `booking.listCargos` call is logged with the status as its key. A filter applied after the page was cut would return short pages and a wrong `hasNextPage`: a page of two that loses one cargo to the filter is a page of one, and the client cannot tell whether the list ended. The index therefore filters first and pages what is left, so a filtered page is full whenever matches remain, and its cursors are positions in the same global ordering as the unfiltered list. The stored status must also agree with the derived one, since `Cargo.delivery` computes `routingStatus` from the itinerary. The example asserts it: the `MISROUTED` page is `STU678` with a derived status of `MISROUTED`, and the `NOT_ROUTED` and `ROUTED` pages agree the same way.

`totalCount` is the number of matches regardless of the page, so it is 6 for no filter, 3 for `ROUTED`, 2 for `NOT_ROUTED` and 1 for `MISROUTED`. It is nullable in the contract because counting is not free. A database often has to scan the matches to count them, and a count over a filtered, joined or sharded list can cost more than the page it accompanies. A client that does not select `totalCount` should not pay for it, and a server that cannot count cheaply may return null. This example counts an in-memory index, so it always has a value.

## Bad arguments are errors

Some arguments pass coercion and are still wrong. The specification's "Arguments" section asks that `first` and `last` not be negative, and the server adds its own ceiling: both must be between 0 and 50, inclusive, and a request without either gets 10. Combining `first` and `last` is rejected; the specification strongly discourages it because the meaning of the result is unclear.

These failures are exposed execution errors (older editions of the specification call them field errors) with the code `BAD_USER_INPUT`, the same machinery error handling built for `SERVICE_UNAVAILABLE`. On Quarkus, `BadUserInputException` carries `@ErrorCode("BAD_USER_INPUT")` and is added to the `show-runtime-exception-message` allowlist. On Python, `BadUserInput` subclasses `ExposedError`. The messages are exact: `first must be between 0 and 50`, `last must be between 0 and 50`, `first and last cannot be combined`, and the cursor messages above.

The null lands where the non-null chain ends. `Query.cargos` is `CargoConnection!`, so the failure leaves nothing to hold it and `data` is null. `Cargo.handlingHistory` is `HandlingEventConnection!` and `Query.cargo` is nullable, so the failure nulls `cargo` and stops there, with the error path `["cargo","handlingHistory"]`. Error handling covers where a null lands and the status codes an HTTP response carries; neither is restated here.

## One bad node, one null edge

The booking service lists `GHI345` and cannot load it. On the last page of `cargos(first: 2)`, edge 1 points at it. `CargoEdge.node` loads the cargo from the booking source when a query selects it, so the failure happens there. Because `node` is nullable, the null stops at the edge: the response has one error with the path `["cargos","edges",1,"node"]`, the edge keeps its cursor, edge 0 resolves as `ABC123`, and `pageInfo` and `totalCount` are intact. The spec rules behind this are in "List" and "Non-Null" in the type system and in "Handling Execution Errors". Were `node` non-null, the null would climb to the edge, which is itself non-null in a non-null list, then to the connection, then to `data`.

{% include excalidraw.html file="12-edge-node-fuse" alt="The figure has two panels. The left panel, data.cargos, holds four boxes: edges zero with the cursor and the node ABC123, the cursor of edges one kept, edges one node null highlighted in amber as the fuse, and pageInfo with hasNextPage false and hasPreviousPage true, beside totalCount 6. The right panel, errors, holds one amber box: booking service unavailable, code SERVICE_UNAVAILABLE, path cargos, edges, 1, node. An amber arrow labelled path joins the error to the null node." caption="Figure 12.4: The page-three response. The error's path points at the one null; the cursor, the sibling edge and pageInfo survive." %}

The same holds when the failing cargo is reached through a filter. The `NOT_ROUTED` page is `XYZ789` and a null node for `GHI345`, with the same path, because the index lists a cargo that its owner cannot load.

## Code-first connections on two stacks

Both stacks use plain types: five records on Quarkus, five `@strawberry.type` classes on Python, with the canonical descriptions. The edge holds the cursor and a private key for its node, and a `node` resolver loads the cargo. Strawberry ships `strawberry.relay`, which models connections differently from the contract. Its `ListConnection` pages by offset with cursors of the form `arrayconnection:<n>`, so a late insert repeats an item, as in Figure 12.1. Its `node` field is non-null, where the contract's is nullable. It has no `totalCount`, and its `Node` and `GlobalID` use their own id encoding in place of the canonical `Node.id`. The example uses plain types so that the keyset cursors, the nullable `node` and `totalCount` match the contract. The README records the output.

## The cost of hydrating a page

A page of cargo edges is a list of keys. Selecting anything about each cargo means one lookup per edge, and that is where the N+1 appears. The query in `verify.sh` pages four cargos and selects each one's itinerary legs, with the voyage and both locations of each leg, and its delivery status. The source-call log counts 29 calls: one `booking.listCargos`, four `booking.getCargo`, eight `routing.getItinerary`, four `handling.listEvents`, four `voyage.getVoyage` and eight `location.getLocation`.

The numbers follow from the seed. Each cargo's itinerary and its delivery both read the routing source, so four cargos make eight calls. The four cargos have one, none, one and two legs, which makes four legs, each with a voyage and two locations. The voyage log shows `V300A` twice, the same key fetched twice in one request. `nodes(ids:)` has the same shape: five ids cost five calls. DataLoader batching collapses these calls and removes the repetition. The number to beat is 29.

## On the wire

Start the stack. Quarkus is on `8220` and Python on `8221`.

```bash
docker compose -f examples/12-pagination/compose.yaml up -d --build
Q() {
  local vars="${2:-}"; [ -n "$vars" ] || vars='{}'
  curl -s localhost:${3:-8220}/graphql -H 'Content-Type: application/json' \
    -d "$(python3 -I -c 'import json,sys; print(json.dumps({"query": sys.argv[1], "variables": json.loads(sys.argv[2])}))' "$1" "$vars")"; echo
}
```

The first page of two cargos:

```bash
Q 'query($f: Int, $a: String) { cargos(first: $f, after: $a) { edges { cursor node { trackingId } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } }' '{"f":2}'
```

```json
{"data":{"cargos":{"edges":[{"cursor":"Y2FyZ298djF8MjAyNi0wOS0yOVQwOTowMDowMFp8VldYOTAx","node":{"trackingId":"VWX901"}},{"cursor":"Y2FyZ298djF8MjAyNi0wOS0yOFQwOTowMDowMFp8WFlaNzg5","node":{"trackingId":"XYZ789"}}],"pageInfo":{"hasNextPage":true,"hasPreviousPage":false,"startCursor":"Y2FyZ298djF8MjAyNi0wOS0yOVQwOTowMDowMFp8VldYOTAx","endCursor":"Y2FyZ298djF8MjAyNi0wOS0yOFQwOTowMDowMFp8WFlaNzg5"},"totalCount":6}}}
```

Send the `endCursor` as `$a` for page two, and the second page's `endCursor` for page three, where the failing edge shows:

```bash
Q 'query($f: Int, $a: String) { cargos(first: $f, after: $a) { edges { cursor node { trackingId } } pageInfo { hasNextPage hasPreviousPage } totalCount } }' '{"f":2,"a":"Y2FyZ298djF8MjAyNi0wOS0yNlQwOTowMDowMFp8REVGNDU2"}'
```

```json
{"errors":[{"message":"booking service unavailable","locations":[{"line":1,"column":76}],"path":["cargos","edges",1,"node"],"extensions":{"code":"SERVICE_UNAVAILABLE"}}],"data":{"cargos":{"edges":[{"cursor":"Y2FyZ298djF8MjAyNi0wOS0yNVQwOTowMDowMFp8QUJDMTIz","node":{"trackingId":"ABC123"}},{"cursor":"Y2FyZ298djF8MjAyNi0wOS0yNFQwOTowMDowMFp8R0hJMzQ1","node":null}],"pageInfo":{"hasNextPage":false,"hasPreviousPage":true},"totalCount":6}}}
```

Python sends `data` before `errors`; the values do not differ. A bad argument and the history after the late insert:

```bash
Q '{ cargos(first: 51) { totalCount } }'
Q 'mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } } }' '{"i":{"trackingId":"DEF456","type":"CUSTOMS","location":"NLRTM","completionTime":"2026-10-11T20:00:00Z"}}'
Q 'query($t: TrackingId!, $f: Int) { cargo(trackingId: $t) { handlingHistory(first: $f) { edges { node { id } } totalCount } } }' '{"t":"DEF456","f":3}'
docker compose -f examples/12-pagination/compose.yaml down -v
```

```json
{"errors":[{"message":"first must be between 0 and 50","locations":[{"line":1,"column":3}],"path":["cargos"],"extensions":{"code":"BAD_USER_INPUT"}}],"data":null}
{"data":{"registerHandlingEvent":{"handlingEvent":{"id":"evt_10"}}}}
{"data":{"cargo":{"handlingHistory":{"edges":[{"node":{"id":"evt_9"}},{"node":{"id":"evt_8"}},{"node":{"id":"evt_10"}}],"totalCount":8}}}}
```

Timestamps and column numbers can differ by stack. The cursors, ids, paths, flags and counts do not.

| Check | Expected |
|---|---|
| `handlingHistory(first: 2)` of `ABC123` | ids `evt_2`, `evt_1`; `hasNextPage` false |
| `cargos(first: 2)`, then `after` each `endCursor` | `VWX901, XYZ789` (next true, prev false), `STU678, DEF456` (true, true), `ABC123` and a null node (false, true); `totalCount` 6 |
| first cursor | base64url, no padding, of `cargo|v1|2026-09-29T09:00:00Z|VWX901`; identical on both stacks; no `VWX901`, `2026` or `=` in any cursor |
| the failing edge | 1 error, path `["cargos","edges",1,"node"]`, message `booking service unavailable`, code `SERVICE_UNAVAILABLE`; node null; cursor kept; `ABC123` resolved |
| `last: 2, before:` the cursor of `ABC123` | `STU678, DEF456`; next true, prev true |
| `last: 2` | `ABC123` and a null node; next false, prev true |
| `routingStatus` `MISROUTED`, `NOT_ROUTED`, `ROUTED` | `[STU678]` total 1; `[XYZ789, null]` total 2; `[VWX901, DEF456, ABC123]` total 3; stored status equals derived; one `booking.listCargos` call keyed by the filter |
| `first: 0` | no edges; next true, prev false; null cursors; `totalCount` 6 |
| `first: -1`, `first: 51`, `last: 51` | 1 error each, path `["cargos"]`, code `BAD_USER_INPUT`, the message `first must be between 0 and 50` or `last must be between 0 and 50`; `data` null |
| `first: 1, last: 1` | `first and last cannot be combined` |
| `after` with `nope`, a padded cursor, version `v2`, a time with a fraction, an extra field, or an event cursor; `before` with `nope` | `after is not a valid cursor for this connection` (`before is not ...` for `before`) |
| a cargo cursor on `cargo(DEF456) { handlingHistory(after:) }` | the same message; path `["cargo","handlingHistory"]`; `cargo` null |
| `first: 50` | no error |
| DEF456 history `first: 3` | `evt_9, evt_8, evt_7`, total 7, `endCursor` the encoding of `evt|v1|2026-10-11T18:20:00Z|7` |
| register CUSTOMS at `NLRTM` completing `2026-10-11T20:00:00Z` | `evt_10` |
| next page after `evt_7`, then the one after | `evt_6, evt_5, evt_4` (true, true); `evt_3` (false, true) |
| a fresh `first: 3` | `evt_9, evt_8, evt_10`, total 8 |
| a fresh `first: 6` | items 4 to 6 are `evt_7, evt_6, evt_5`: an offset page of 3 repeats `evt_7` |
| register CUSTOMS for `ABC123` completing `2026-10-02T09:00:00.5Z` | `evt_11`; `first: 1` returns it with `completionTime` `2026-10-02T09:00:00Z` and `endCursor` the encoding of `evt|v1|2026-10-02T09:00:00Z|11`; `after` that cursor returns `evt_2` |
| `last: 2` | `evt_4, evt_3`; next false, prev true |
| three more events, then `handlingHistory` without arguments | 10 edges, next true, total 11; delivery still `CLAIMED` |
| `args { defaultValue }` of `Query.cargos` and `Cargo.handlingHistory` | every default null |
| four-cargo query with itineraries and delivery | 29 calls: `listCargos` 1, `getCargo` 4, `getItinerary` 8, `listEvents` 4, `getVoyage` 4 (`V300A, V300A, V100S, V200E`), `getLocation` 8 |
| `nodes` with five ids | 5 calls; the ids `cargo`, `evt`, `cargo_` give `[null,null,null]` and no call |
| `Itinerary.finalArrivalDate` and `finalArrivalTime` | deprecated with reason ``Use `finalArrivalTime`.`` and not deprecated; both `2026-10-11T18:00:00Z` for `DEF456` |
| the live schema | conforms to `contracts/schema/`; only `Subscription` is unserved |

`bash examples/12-pagination/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Pagination is where the <em>aggregation across sources</em> axis of the decision framework meets volume: a page of edges is one index read, and each selected field adds a call to another owner, so the page size is also a multiplier on every source behind it. The <em>contract and evolution style</em> axis decides the shape and the cursor. A list that may grow starts as a connection, a cursor is opaque and versioned so its contents can change, and the sort key is total so a keyset never repeats an item. The <em>operational and security cost</em> axis decides the limits: a page ceiling of 50, a rejected cursor the server did not issue, a nullable <code>totalCount</code> that is not selected unless the client asks, and a nullable <code>node</code> so one failing source costs one edge. The tracking view therefore uses keyset connections with exposed <code>BAD_USER_INPUT</code> errors, and measures the 29 calls that DataLoader batching reduces.</p></div>

## Review

- Keyset pagination with opaque cursors stays stable under inserts, where offset pagination repeats or skips rows.
- A Relay connection (`edges`, `node`, `cursor`, and `pageInfo`) uses a nullable `node` so one failing item nulls only its edge.
- An opaque, versioned cursor like `cargo|v1|<bookedAt>|<trackingId>` is encoded and validated, rejecting anything the server didn't issue.
- `first`/`after` page forward and `last`/`before` page backward, with `hasNextPage`/`hasPreviousPage` computed exactly from the slice.
- An invalid argument such as an out-of-range `first` is rejected as an exposed `BAD_USER_INPUT` error rather than silently clamped.

## Where this goes next

This chapter turned two growing lists into connections: keyset paging against offset, the connection shape, opaque versioned cursors, forward and backward paging with exact flags, stability under inserts, a filter pushed to the index, argument errors as `BAD_USER_INPUT`, the fuse on `CargoEdge.node`, and a measured baseline of 29 source calls for a four-cargo page.

The next example starts from this one and batches those calls: SmallRye batch resolvers on one side and Strawberry data loaders on the other, with the call counts compared. Query cost treats the page size and the selection depth as inputs.

For the formal definitions, read the "Connection Types", "Edge Types", "Arguments", "Pagination algorithm" and "PageInfo" sections of the Relay [GraphQL Cursor Connections](https://relay.dev/graphql/connections.htm) specification, and "List" and "Non-Null" in the [GraphQL specification](https://spec.graphql.org/). Martin Kleppmann and Chris Riccomini's *Designing Data-Intensive Applications*, 2nd edition, covers ordered indexes and range scans. William Lyon's *Full Stack GraphQL Applications* closes with a chapter, "Advanced GraphQL considerations", that treats pagination among its topics. Both books are on the [Bibliography](../../bibliography/) page. The framework behaviour is in the Quarkus [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) and the [Strawberry documentation](https://strawberry.rocks/docs).

## For deeper coverage

- [Relay: GraphQL Cursor Connections specification](https://relay.dev/graphql/connections.htm): `Connection`, `Edge`, `PageInfo`, and the pagination algorithm.
- [GraphQL specification: List, Non-Null](https://spec.graphql.org/): the nullability rule behind `CargoEdge.node`.
- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd ed. (O'Reilly, 2026): ordered indexes and range scans, the reason a keyset seek beats an offset count.
- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022): pagination, in its closing chapter "Advanced GraphQL considerations."
- *Cloud Native Design Patterns*, "Data": read-model indexes and the cost of serving a page from them.
