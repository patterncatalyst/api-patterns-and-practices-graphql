---
title: "Connections and pagination"
order: 12
part: "Data Fetching at Scale"
description: "How a growing list becomes a Relay connection: offset against keyset pagination, edges, nodes and PageInfo, opaque versioned cursors, forward and backward paging, filters and totalCount, bad arguments as BAD_USER_INPUT, and one failing node nulling one edge."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Explain why keyset pagination with opaque cursors stays stable under inserts where offset pagination repeats or skips rows.
- Build a Relay connection (`edges`, `node`, `cursor`, and `pageInfo`) with a nullable `node` so one failing item nulls only its edge.
- Encode and validate an opaque, versioned cursor like `cargo|v1|<bookedAt>|<trackingId>`, rejecting anything the server didn't issue.
- Page forward with `first`/`after` and backward with `last`/`before`, computing `hasNextPage`/`hasPreviousPage` exactly from the slice.
- Reject invalid arguments such as an out-of-range `first` as an exposed `BAD_USER_INPUT` error rather than silently clamping them.

## Why this matters

A cargo has two legs and a handful of events, so a client reads all of them and nothing breaks. A cargo handled for months has hundreds of events, and the list of cargos has no natural end. Both lists become pages a client walks one at a time, and every page costs calls on the sources behind it.

The code adds `Query.cargos` and `Cargo.handlingHistory`, with the types `CargoConnection`, `CargoEdge`, `HandlingEventConnection`, `HandlingEventEdge` and `PageInfo`. The seed holds six cargos, DEF456 has a seven-event history, and one fault remains: the booking service lists `GHI345` but can't load it.

## Lists that grow need pages

An unbounded list field makes the cost of a query depend on data the client doesn't control. The same `handlingHistory` selection returns two events today and two thousand next year, and response size, handling-service time and engine memory all grow with it. A page size caps that cost, and a cursor lets the client continue where it stopped.

The cap has to hold when the client says nothing. A request without `first` or `last` gets a default page of 10, and no request may ask for more than 50. Both numbers are contract: a client written against the default breaks if the default grows to 100, so changing either is a decision, not tuning.

The shape has to be settled early. Turning a plain list into a connection changes the field's type, which is a breaking change for every client that selects it, so a list that may grow starts as a connection.

## Offset versus keyset

Offset pagination counts: skip the first N rows and take the next M. Keyset pagination seeks: take the rows whose sort key comes after the last key the client saw. Offset is simple to write and fails silently. Keyset needs a stable, unique ordering and never miscounts.

Offset breaks when data changes between two requests. DEF456's history has seven events, and the first page of three is `evt_9`, `evt_8`, `evt_7`. A customs event that completed at `2026-10-11T20:00:00Z` is then registered late as `evt_10`. By completion time it belongs between `evt_8` and `evt_7`, in the part the client has already read. "Skip 3, take 3" now returns `evt_7`, `evt_6`, `evt_5`: `evt_7` twice, because everything below the insert moved down a place. The cursor of `evt_7` returns `evt_6`, `evt_5`, `evt_4`, with no repeat and no gap, because it names a position in the ordering, not a row count.

{% include excalidraw.html file="12-offset-vs-keyset" alt="The figure has three horizontal lanes. The top lane lists the history of DEF456 after the insert, newest first: evt_9, evt_8, evt_10 highlighted, evt_7, evt_6, evt_5, evt_4 and evt_3, each with its completion time. The middle lane, offset, shows a dashed box for three skipped items and then evt_7, evt_6 and evt_5, with evt_7 highlighted and labelled as a repeat, joined by a dashed arrow to evt_7 in the top lane. The bottom lane, keyset, shows a dashed box for a seek past the key of evt_7 and then evt_6, evt_5 and evt_4. A note says that before the insert, page one was evt_9, evt_8, evt_7 and page two was evt_6, evt_5, evt_4." caption="Figure 12.1: The same insert, two pagination designs. Offset repeats evt_7; the keyset cursor seeks past it." %}

Kleppmann and Riccomini explain why the seek is cheap in *Designing Data-Intensive Applications*, 2nd edition: an ordered index keeps keys sorted, so a range scan starts at a key and reads forward, where an offset walks past every skipped row. The sort key must be total, so both connections break ties: cargos by booking time and then tracking id, events by completion time and then the number in `evt_<n>`.

Keyset has one limit. A client can't jump to page 40, because a cursor exists only for a position the server has already shown. A screen that needs numbered pages needs offset. A feed or timeline, which is how the tracking view uses its lists, doesn't.

## The connection shape

The Relay [Cursor Connections](https://relay.dev/graphql/connections.htm) specification defines the connection: `edges` and `pageInfo`, where each edge has a `node` and a `cursor`. The canonical SDL adds a nullable `totalCount`.

{% include excalidraw.html file="12-connection-anatomy" alt="Query.cargos returns a CargoConnection with three fields: edges, a list of CargoEdge, pageInfo, a PageInfo, and totalCount, a nullable Int. A CargoEdge has a cursor, a non-null String, and a node, a nullable Cargo, marked in amber. PageInfo has hasNextPage and hasPreviousPage, both non-null Boolean, and startCursor and endCursor, both nullable String. Cargo has a handlingHistory field that is itself a connection." caption="Figure 12.2: The shape of a connection. The edge's node is the one nullable link in the chain." %}

The cursor sits on the edge, not the node, because it names a position in this connection and the same cargo could appear in another connection with a different cursor. `pageInfo` answers what a client asks after a page: is there more in each direction, and where do I continue. `startCursor` and `endCursor` are null on an empty page.

The node is nullable by design: "Null when the cargo failed to resolve, so one bad item nulls its edge instead of the whole page." That is a nullability fuse, covered below on a live page.

## Cursors are opaque

A client holds a cursor and hands it back. It must not read it, build one or compare two, and the specification says so: a client treats a cursor as opaque and sends it back as `after` or `before`. The server is then free to change what a cursor contains.

The cargo cursor is the URL-safe base64, without padding, of `cargo|v1|<bookedAt>|<trackingId>`, and the event cursor is `evt|v1|<completionTime>|<n>`. Both stacks return the same bytes. The prefix names the connection, so a cargo cursor handed to `handlingHistory` is rejected. The version lets a later release change the key without misreading cursors clients still hold. The key fields are what the server seeks on.

The decoder accepts only text it could have issued. A wrong prefix, an unknown version, a different number of fields, a time with a fraction, a padded or non-canonical encoding, garbage, and a cursor from the other connection all fail the same way: `BAD_USER_INPUT` with `after is not a valid cursor for this connection` (`before` where that argument carried it). Opaque is a rule for clients, and the server enforces it. It doesn't mean encrypted: anyone can decode the base64. A cursor that must hide data needs a signature or a server-side lookup.

## Paging forward

`first` and `after` read forward: the edges after the `after` cursor, then the first `first` of them. `hasNextPage` is true when edges remain beyond the page, and `endCursor` is the next `after`.

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

The resolver validates, asks the booking source for one page of its index, and wraps the result. A small `Pagination` helper on each stack owns the argument rules, the cursor codec and the slice, so `Query.cargos` and `Cargo.handlingHistory` can't drift apart. The Python arguments are `strawberry.Maybe` values with a default of `None`: an omitted argument arrives as `None`, a sent one as `Some(value)`, and the printed SDL stays free of `= null`, which would be a dangerous change.

Walked two at a time, the six cargos give `VWX901, XYZ789`, then `STU678, DEF456`, then `ABC123` and `GHI345`. `hasNextPage` is true, true, false; `hasPreviousPage` is false, true, true; `totalCount` is 6 on every page.

## Paging backward

`last` and `before` read the other way: the edges before the `before` cursor, then the last `last` of them. The page stays in connection order, newest first, so `last: 2` before the cursor of `ABC123` returns `STU678` and `DEF456`, the same middle page as the second forward step. `last: 2` with no cursor returns the end of the list, `ABC123` and `GHI345`.

{% include excalidraw.html file="12-cursor-movement" alt="A strip shows the six cargos in booking order: VWX901, XYZ789, STU678, DEF456, ABC123 and GHI345, each with its booking date and the last characters of its cursor. Below it, three highlighted boxes show the forward pages: page one VWX901 and XYZ789 with hasNext true and hasPrev false, page two STU678 and DEF456 with both true, page three ABC123 and GHI345 with hasNext false and hasPrev true. Arrows labelled endCursor join the pages. A fourth box below shows the backward request, last two before the cursor of ABC123, which selects STU678 and DEF456 with both flags true." caption="Figure 12.3: Three forward pages, each after the previous endCursor, and one backward page selecting the middle of the list." %}

The specification lets a server approximate the flag for the direction a client isn't paging. Here both flags are exact, because the slice knows the page's position in the whole ordered list.

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
    """The slice algorithm of "Pagination algorithm" in the specification: take
    the edges after the ``after`` cursor and before the ``before`` cursor, then
    the first or last N of those. ``newest_first`` is in connection order, so a
    larger key comes earlier."""
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

The two windows are positions found by comparing keys, never by remembering rows. `first: 0` returns no edges, null cursors, `hasNextPage` true and `hasPreviousPage` false: an empty page is a valid answer to a valid question.

A registration that lands in the part of the history a client has already read can't disturb the next page, because the slice compares keys. After the late `evt_10`, the cursor of `evt_7` still continues with `evt_6`, `evt_5`, `evt_4`, and a fresh first page is `evt_9`, `evt_8`, `evt_10` with `totalCount` 8. The store keeps completion times in whole seconds because the cursor encodes the sort key at that precision: an event registered at `2026-10-02T09:00:00.5Z` is stored and returned as `2026-10-02T09:00:00Z`, and the page after its cursor skips nothing.

## Filters and `totalCount`

`routingStatus` narrows `cargos` to one status. Apply the filter where the data is: the booking source reads the status stored in its index and pages only the matching rows. A filter applied after the page was cut returns short pages and a wrong `hasNextPage`, because a page of two that loses one cargo to the filter looks like the end of the list. Filtering first keeps a filtered page full whenever matches remain, and its cursors are positions in the same global ordering as the unfiltered list. The stored status must also agree with the derived one, since `Cargo.delivery` computes `routingStatus` from the itinerary.

`totalCount` is the number of matches regardless of the page: 6 with no filter, 3 for `ROUTED`, 2 for `NOT_ROUTED`, 1 for `MISROUTED`. It's nullable because counting isn't free. A count over a filtered, joined or sharded list can cost more than the page it accompanies, so a client that doesn't select it shouldn't pay for it, and a server that can't count cheaply may return null.

## Bad arguments are errors

Some arguments pass coercion and are still wrong. `first` and `last` must be between 0 and 50, and a request without either gets 10. The specification asks that they not be negative and strongly discourages combining `first` and `last`; the server rejects the combination.

| Input | Error message |
|---|---|
| `first: -1` or `first: 51` | `first must be between 0 and 50` |
| `last: 51` | `last must be between 0 and 50` |
| `first: 1, last: 1` | `first and last cannot be combined` |
| a cursor the server didn't issue | `after is not a valid cursor for this connection` |

Rejecting beats clamping: a client that asks for 500 and silently gets 50 believes it has the whole list. These are exposed execution errors with the code `BAD_USER_INPUT`, the same machinery that exposes `SERVICE_UNAVAILABLE`. On Quarkus, `BadUserInputException` carries `@ErrorCode("BAD_USER_INPUT")` and is added to the `show-runtime-exception-message` allowlist. On Python, `BadUserInput` subclasses `ExposedError`.

The null lands where the non-null chain ends. `Query.cargos` is `CargoConnection!`, so nothing can hold the failure and `data` is null. `Cargo.handlingHistory` is `HandlingEventConnection!` and `Query.cargo` is nullable, so the failure nulls `cargo` and stops, with the error path `["cargo","handlingHistory"]`.

## One bad node, one null edge

The booking service lists `GHI345` and can't load it. On the last page of `cargos(first: 2)`, edge 1 points at it. `CargoEdge.node` loads the cargo when a query selects it, so the failure happens there. Because `node` is nullable, the null stops at the edge: one error with the path `["cargos","edges",1,"node"]`, the edge keeps its cursor, edge 0 resolves as `ABC123`, and `pageInfo` and `totalCount` are intact. Were `node` non-null, the null would climb to the edge, then the connection, then `data`.

{% include excalidraw.html file="12-edge-node-fuse" alt="The figure has two panels. The left panel, data.cargos, holds four boxes: edges zero with the cursor and the node ABC123, the cursor of edges one kept, edges one node null highlighted in amber as the fuse, and pageInfo with hasNextPage false and hasPreviousPage true, beside totalCount 6. The right panel, errors, holds one amber box: booking service unavailable, code SERVICE_UNAVAILABLE, path cargos, edges, 1, node. An amber arrow labelled path joins the error to the null node." caption="Figure 12.4: The page-three response. The error's path points at the one null; the cursor, the sibling edge and pageInfo survive." %}

The same holds through a filter: the `NOT_ROUTED` page is `XYZ789` and a null node for `GHI345`, with the same path, because the index lists a cargo its owner can't load.

## How Quarkus and Python model it

Both stacks use plain types: five records on Quarkus, five `@strawberry.type` classes on Python, with the canonical descriptions. The edge holds the cursor and a private key for its node, and a `node` resolver loads the cargo.

Strawberry ships `strawberry.relay`, which models connections differently from this contract:

| `strawberry.relay` | This contract |
|---|---|
| `ListConnection` pages by offset, with cursors like `arrayconnection:<n>`, so a late insert repeats an item | keyset cursors |
| `node` is non-null | `node` is nullable |
| no `totalCount` | nullable `totalCount` |
| `Node` and `GlobalID` use their own id encoding | the canonical `Node.id` |

## The cost of hydrating a page

A page of cargo edges is a list of keys. Selecting anything about each cargo costs one lookup per edge, and that is where N+1 appears. A query that pages four cargos and selects each one's itinerary legs, with voyage and both locations per leg, and its delivery status makes 29 source calls: one `booking.listCargos`, four `booking.getCargo`, eight `routing.getItinerary`, four `handling.listEvents`, four `voyage.getVoyage` and eight `location.getLocation`.

Itinerary and delivery each read the routing source, so four cargos make eight calls. The four cargos have four legs between them, each with a voyage and two locations, and the voyage log shows `V300A` fetched twice in one request. `nodes(ids:)` has the same shape: five ids cost five calls. DataLoader batching collapses these calls and removes the repetition. The number to beat is 29.

> **🤖 Explore with your agent**
>
> "In examples/12-pagination, add a `shipperName: String` filter to `Query.cargos` on both stacks. Apply it in the booking source's index before the page is cut, keep the cursors as positions in the same global ordering, and keep `totalCount` as the number of matches. Do not filter after slicing."
>
> Check: query `cargos(first: 1, shipperName: ...)` on ports 8220 and 8221 and confirm that every page is full while matches remain, that `hasNextPage` is correct on the last page, and that `totalCount` equals the match count.

## Build, run, observe

Start the stack. Quarkus is on 8220 and Python on 8221.

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

Python sends `data` before `errors`; the values don't differ. A bad argument and the history after the late insert:

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

Timestamps and column numbers can differ by stack. The cursors, ids, paths, flags and counts don't.

`bash examples/12-pagination/verify.sh` runs the whole sequence on both stacks and prints `PASS` when both agree. Experiments:

- Request `cargos(first: 51)` or `first: -1`: one `BAD_USER_INPUT` error at path `["cargos"]`, and `data` is null.
- Send `first: 1, last: 1`: `first and last cannot be combined`.
- Send `after: "nope"`, a padded cursor, a `v2` cursor or an event cursor to `cargos`: `after is not a valid cursor for this connection`.
- Send a cargo cursor to `cargo(trackingId: "DEF456") { handlingHistory(after: ...) }`: the same message, path `["cargo","handlingHistory"]`, and `cargo` null.
- Register the late `CUSTOMS` event and compare an offset page of 3 with the cursor page: `first: 6` shows `evt_7` again at items 4 to 6, while the cursor continues at `evt_6`.
- Select `node` on the `GHI345` edge: one error, a null node, the cursor and `pageInfo` intact.

> **Decision**
>
> Pagination is where the aggregation across sources axis of the decision framework meets volume: a page of edges is one index read, and each selected field adds a call to another owner, so page size multiplies every source behind it. The contract and evolution style axis decides the shape and the cursor: a list that may grow starts as a connection, the cursor is opaque and versioned so its contents can change, and the sort key is total so a keyset never repeats an item. The operational and security cost axis decides the limits: a page ceiling of 50, rejection of cursors the server didn't issue, a nullable `totalCount` that is not computed unless selected, and a nullable `node` so one failing source costs one edge. The tracking view uses keyset connections with exposed `BAD_USER_INPUT` errors, and measures the 29 calls that DataLoader batching reduces.

## For deeper coverage

- [Relay: GraphQL Cursor Connections specification](https://relay.dev/graphql/connections.htm): "Connection Types", "Edge Types", "Arguments", "Pagination algorithm" and "PageInfo".
- [GraphQL specification: List, Non-Null](https://spec.graphql.org/): the nullability rule behind `CargoEdge.node`.
- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd ed. (O'Reilly, 2026): ordered indexes and range scans, the reason a keyset seek beats an offset count. Listed on the [Bibliography](../../bibliography/) page.
- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022): pagination, in its closing chapter "Advanced GraphQL considerations."
- Quarkus [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) and the [Strawberry documentation](https://strawberry.rocks/docs): framework behavior.
- *Cloud Native Design Patterns*, "Data": read-model indexes and the cost of serving a page from them.
