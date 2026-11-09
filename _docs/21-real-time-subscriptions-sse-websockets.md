---
title: "Real-time: subscriptions vs SSE vs WebSockets"
order: 21
part: "Real-time & Client Integration"
description: "Push handling events with a GraphQL subscription over WebSocket or SSE, or a plain SSE feed that resumes from Last-Event-ID, and keep the per-event reads, queues and cleanup bounded."
duration: "17 min read"
---


## Learning objectives

By the end of this chapter you can:

- Serve `Subscription.cargoHandled` over `graphql-transport-ws` on both stacks and read its six frames: `connection_init`, `connection_ack`, `subscribe`, `next`, `next`, `complete`.
- Choose between a GraphQL subscription, GraphQL over SSE and a plain SSE feed on selection, resume and transport cost.
- Resume a plain SSE feed from `Last-Event-ID` by joining the broadcast before replaying stored events, so no event is lost or duplicated.
- Clear per-event state between subscription events so a long-lived stream never serves stale batched data.
- Bound each subscriber's queue and remove it on `complete` and on a dropped connection.

## Why this matters

Requests get responses. Some clients want to be told instead: `Subscription.cargoHandled(trackingId:)` emits each handling event for one cargo as it is registered. A subscription is a long-lived operation, so it holds a connection and a registry entry for as long as the client wants, and does work for every event.

Both stacks serve the subscription over WebSocket. Strawberry also serves it over server-sent events (SSE), and both stacks serve a plain SSE feed that isn't GraphQL at all. The schema served is the complete canonical SDL, `Subscription` included.

## Asking once, hearing many times

A query asks once and gets one answer. A subscription is a document that stays open: the client sends it once and the server answers with a result for every event, each in the shape of the client's own selection set, because each event executes that selection:

```graphql
subscription Watch($id: TrackingId!) {
  cargoHandled(trackingId: $id) {
    id
    type
    location { name }
    cargo { trackingId delivery { transportStatus } }
  }
}
```

The payload of `cargoHandled` is a `HandlingEvent`, an ordinary object type. `location` and `cargo` are batch resolvers, so the sources behind them run for every event. The GraphQL specification describes two steps: CreateSourceEventStream turns the field into a stream of source events, and MapSourceToResponseEvent executes the selection set once per event and yields the result. The subscription field's resolver produces events, and everything below it is the executor running again.

That is the difference from a feed. A client that wants only `id` and `type` writes a smaller selection, and the sources behind `location` and `delivery` aren't touched. A client that wants the delivery status as of this event gets it, computed from the handling history at that moment.

## Four ways to push

{% include excalidraw.html file="21-three-ways-to-push" alt="A grid with four columns and seven rows. The columns are GraphQL over WebSocket using graphql-transport-ws, GraphQL over SSE using graphql-sse, a plain SSE feed at GET events cargos trackingId, and a raw WebSocket with your own protocol. The rows are direction, framing, selection, resume, HTTP path, credentials and served here. The two GraphQL columns carry the client's selection set and have no resume. The plain feed has a fixed payload and resumes by Last-Event-ID replay. The raw WebSocket column is dashed because its cells are all yours to design. The last row shows Quarkus and Python serve the WebSocket subscription and the feed, Python serves GraphQL over SSE, and the raw WebSocket is prose only." caption="Figure 21.1: Four ways to push. The GraphQL columns keep the selection set and the schema; the plain feed trades them for HTTP semantics and resume." %}

- A **GraphQL subscription over WebSocket** is the ecosystem default. The client opens a socket, offers the `graphql-transport-ws` subprotocol, and sends subscribe messages that carry ordinary GraphQL documents. One socket can carry several subscriptions, queries and mutations.
- **GraphQL over SSE** carries the same documents over HTTP. The client sends a `POST` with `Accept: text/event-stream` and gets one `next` event per result. It needs no upgrade. The `graphql-sse` protocol calls this the distinct connections mode: one HTTP request per subscription.
- A **plain SSE feed** drops GraphQL. `GET /events/cargos/{trackingId}` returns events with a fixed payload and no selection, and gains what SSE defines: event ids, automatic reconnection in the browser's `EventSource`, and a `Last-Event-ID` header that lets a server resume.
- A **raw WebSocket** with a protocol of your own is the fourth; the section on raw WebSockets says when it pays.

## The event path

An event starts as a mutation. `registerHandlingEvent` validates, appends to the handling store, and returns. The subscription doesn't read the mutation's payload. It listens to the store, so any writer reaches a subscriber: a retried request, a batch import, another service.

{% include excalidraw.html file="21-event-path" alt="A flow from left to right on two rows. A user box, registerHandlingEvent for ABC123 UNLOAD at DEHAM on V100S, leads to a handling store box that appends evt_10 and does nothing for an idempotent replay. That leads to a broadcast box holding a bounded queue per watcher. From broadcast, a dashed arrow goes to a ghost box, watcher DEF456, which does not match and receives nothing. An amber arrow goes to watcher ABC123, which leads down to a box that executes the selection set with four reads: location.getLocations DEHAM, booking.getCargos ABC123, routing.getItineraries ABC123 and handling.listEventsFor ABC123. That leads left to a dark box, the next frame or SSE event for evt_10 in Hamburg at IN_PORT, and then to a subscriber box that receives evt_10 and then evt_12 and never DEF456's event." caption="Figure 21.2: From a registration to a frame. The store broadcasts after it writes; each watcher takes the events of its own cargo and executes its selection for each." %}

The store broadcasts after the write succeeds and never for an idempotent replay, so a watcher hears each event once. Each watcher owns a queue and takes only the events of the cargo it named. In process this is a few lines. Across several server instances the store would publish to a message broker and every instance's watchers would subscribe to it, with the same subscribers and frames.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Subscription
@NonNull
@Description("Emits each new handling event for one cargo as it is registered.")
public Multi<HandlingEvent> cargoHandled(
        @Name("trackingId") @NonNull @Description("The tracking id of the cargo to watch.") TrackingId trackingId) {
    return store.watch(trackingId.value(), HandlingStore.Channel.GRAPHQL, null).map(HandlingEvent::of);
}
```

```python
@strawberry.subscription(
    description="Emits each new handling event for one cargo as it is registered."
)
async def cargo_handled(
    self,
    info: Info[TrackingContext],
    tracking_id: Annotated[
        TrackingId,
        strawberry.argument(
            name="trackingId", description="The tracking id of the cargo to watch."
        ),
    ],
) -> AsyncGenerator[HandlingEvent]:
    # The generator resumes only after the previous event has been executed
    # and sent, so renewing the context here cannot affect an event in flight.
    async for record in info.context.store.watch(tracking_id, "graphql"):
        info.context.begin_event()
        yield HandlingEvent.of(record)
```

SmallRye's `@Subscription` marks a method that returns a Mutiny `Multi`, which the `BroadcastProcessor` behind the store implements. Strawberry's `@strawberry.subscription` marks an async generator. In both, the resolver is only the source of events. Selection, serialization and the transport belong to the framework.

## Subscriptions over WebSocket

The `graphql-transport-ws` protocol is small. The client opens the socket and offers the subprotocol, then sends `connection_init` with an optional payload and the server answers `connection_ack`. The client sends `subscribe` with an id and the document. The server sends one `next` per result with that id, and `complete` when the stream ends. Either side may send `complete` to end a subscription, and `ping` and `pong` keep an idle socket alive.

{% include excalidraw.html file="21-transport-ws-sequence" alt="A sequence diagram with a client lifeline on the left and a server lifeline on the right. Six arrows run between them. The client sends connection_init with an empty payload. The server answers connection_ack. The client sends subscribe with id 1 for the subscription Watch with trackingId ABC123. The server sends two amber next frames with id 1, the first for evt_10, UNLOAD, Hamburg, IN_PORT, and the second for evt_12, LOAD, Hamburg, ONBOARD_CARRIER. The client sends complete with id 1. Notes beside the arrows say that evt_10 and evt_12 were registered at the two next frames and that the DEF456 event sends no frame." caption="Figure 21.3: Six frames for a subscription that delivers two events, as the client logged them." %}

A registration for DEF456 between the two ABC123 events produces no frame, because the watcher was registered for ABC123.

The older `graphql-ws` subprotocol, from the `subscriptions-transport-ws` library, uses `start`, `data` and `stop` where the newer one has `subscribe`, `next` and `complete`. Both stacks accept it. New clients should use `graphql-transport-ws`. The subprotocol is the first thing client and server negotiate: the client offers a list and the server's choice governs that socket.

Neither server contains protocol code. SmallRye GraphQL speaks both subprotocols on `/graphql` by default. Strawberry's `GraphQLRouter` takes a tuple of protocols to serve, and the Python server names all three:

```python
app.include_router(
    GraphQLRouter(
        schema,
        context_getter=get_context,
        subscription_protocols=(
            GRAPHQL_TRANSPORT_WS_PROTOCOL,
            GRAPHQL_WS_PROTOCOL,
            GRAPHQL_SSE_PROTOCOL,
        ),
    ),
    prefix="/graphql",
)
```

The WebSocket upgrade itself needs an implementation in the ASGI server, so the Python image installs `uvicorn[standard]`. The client under `client/` has no protocol code either. It is a `gql` `Client` over `WebsocketsTransport`, and the subprotocol is an argument:

```python
async def watch(args: argparse.Namespace) -> int:
    document = gql(Path(args.query).read_text() if args.query else DEFAULT_DOCUMENT)
    transport = WebsocketsTransport(url=args.url, subprotocols=[args.subprotocol])
    received = 0
    try:
        async with asyncio.timeout(args.timeout):
            async with Client(transport=transport) as session:
                async for result in session.subscribe(
                    document, variable_values={"id": args.tracking_id}
                ):
                    print(json.dumps(result), flush=True)
                    received += 1
                    if received >= args.count:
                        return 0
        print(json.dumps({"complete": True}), flush=True)
        return 0
    except TransportQueryError as failure:
        print(json.dumps({"error": failure.errors}), flush=True)
        return 1
    except TimeoutError:
        return 2
```

A document that fails validation never subscribes. `cargoHandled { weight }` gets an `error` frame that names `weight`, and no subscriber is registered. Each stack words the message in its own engine's terms.

## GraphQL over SSE

Strawberry serves the same subscription over HTTP when `GRAPHQL_SSE_PROTOCOL` is in the list. The client sends the document as a normal GraphQL `POST` and asks for a stream:

```bash
curl -N localhost:8311/graphql -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' -d "$SUB_BODY"
```

The response is `Content-Type: text/event-stream`. Each result is an `event: next` whose data is the ordinary GraphQL response. The server sends `event: complete` when the stream ends and a `: ping` comment line while idle, so a proxy with an idle timeout keeps the response open.

This transport suits places where an upgrade is awkward: a proxy that only understands plain HTTP responses, a serverless platform, a client library with an HTTP stack and no WebSocket one. It is one direction, so a second subscription is a second request. Over HTTP/1.1 a browser spends one of its few connections per host on each open stream, and HTTP/2 multiplexes them on one.

## A plain SSE feed, and resume

Server-sent events are older and simpler than any GraphQL transport. The response is `text/event-stream`, and the stream is lines in four fields, `event:`, `data:`, `id:` and `retry:`, with a blank line ending each event. Lines that start with a colon are comments, which servers use to keep an idle connection warm.

The feed is `GET /events/cargos/{trackingId}`, and each event is `handled`:

{% include codetabs.html langs="Quarkus|Python" %}

```java
@GET
@Produces(MediaType.SERVER_SENT_EVENTS)
@RestStreamElementType(MediaType.APPLICATION_JSON)
public Multi<OutboundSseEvent> feed(
        @RestPath String trackingId,
        @RestHeader("Last-Event-ID") String lastEventId,
        @Context Sse sse) {
    return store.watch(trackingId, HandlingStore.Channel.SSE, sequence(lastEventId)).map(record -> sse.newEventBuilder()
            .id(record.id())
            .name("handled")
            .data(
                    Handled.class,
                    new Handled(
                            record.id(),
                            record.trackingId(),
                            record.type().name(),
                            record.unLocode(),
                            record.completionTime()))
            .build());
}
```

```python
@router.get("/events/cargos/{tracking_id}", response_class=EventSourceResponse)
async def cargo_events(
    tracking_id: str,
    store: Annotated[HandlingStore, Depends(get_store)],
    last_event_id: Annotated[str | None, Header()] = None,
) -> AsyncIterator[ServerSentEvent]:
    async for record in store.watch(tracking_id, "sse", after=_sequence(last_event_id)):
        yield ServerSentEvent(data=Handled.of(record), event="handled", id=record.id)
```

Quarkus REST builds each event with the injected `Sse`. FastAPI's `EventSourceResponse` encodes each `ServerSentEvent` the route yields and adds keep-alive comments while the feed is idle. A client reads the same lines from either stack:

```text
event: handled
data: {"id":"evt_12","trackingId":"ABC123","type":"LOAD","location":"DEHAM","completionTime":"2026-10-09T18:00:00Z"}
id: evt_12
```

The payload is fixed. A client that wants the location's name or the delivery status has to fetch it, which is the cost of dropping the selection set. What the feed gains is resume. The `id:` line names each event, and a browser's `EventSource` remembers the last one it saw. When the connection drops it reconnects on its own and sends that id in a `Last-Event-ID` request header. A server that kept the events can answer with everything after it.

The id has to be something the server can order. The feed uses the sequence in `evt_<n>`, which follows registration order. Completion time would not do: the store lists a cargo's history by when the handling happened, and an event registered late lands in the middle of it, so "everything after" a completion time would skip it.

{% include excalidraw.html file="21-sse-resume" alt="Three stacked bands. The first, connected, shows a GET request for events cargos ABC123 with Accept text event-stream leading to a handled event with id evt_10, which the client remembers as Last-Event-ID evt_10. The second, dropped, shows a dark box for connection lost leading to a box saying events registered meanwhile are stored: evt_12 to evt_18. The third, reconnected, shows a GET with Last-Event-ID evt_10 leading to three steps: join the broadcast so no live event can slip by, replay in registration order evt_12 to evt_18, then live evt_19, with live ids already replayed dropped so no id is sent twice." caption="Figure 21.4: Resume is a header and a store. The feed joins the broadcast before it reads the replay, so an event that arrives in between is neither lost nor sent twice." %}

The ordering of the steps matters. If the feed read stored events first and joined the broadcast afterwards, an event registered between the two would be in neither. So the watcher joins the broadcast first, replays stored events after the given id in registration order, then reads the live queue and skips ids it has already sent.

A GraphQL subscription has no equivalent. Its ids belong to a socket and die with it, and a client that reconnects subscribes again and misses whatever happened in between. A client that must not miss events subscribes first and then queries `handlingHistory` for the events it lacks, or reads the feed.

## Raw WebSockets

A WebSocket (RFC 6455) is a bidirectional message channel over one TCP connection with no opinion about what messages mean. Choosing one without GraphQL means designing what the GraphQL protocols provide: message framing and types, matching a request to its reply, acknowledgements, credentials when the browser API can't set headers, resume after a drop, and dead-peer detection.

That cost is worth paying when the traffic is two-way and high-frequency, as in chat, collaborative editing, a game or a trading screen, and the messages don't have the shape of a graph. A client that watches a cargo and reads a few fields of each event needs a subscription or a feed.

## Choosing between them

| Question | Answer |
|---|---|
| Does the client need a selection? | Different fields per client, or a payload that reaches across services: a GraphQL transport saves a round trip per event. The same few fields for everyone: the feed is simpler to write, cache and read in a log. |
| Does the client need to resume? | The feed does it with a header and the server's store. A subscription doesn't, so pair it with a query for the missed range, or use the feed. |
| What sits between client and server? | A WebSocket needs every hop to pass the upgrade and hold an idle connection. SSE needs every hop to pass a long-lived response without buffering it. Both need idle timeouts longer than the ping or keep-alive interval. |

Authentication differs too. An SSE request, GraphQL or plain, carries ordinary headers, so bearer tokens work unchanged. A browser WebSocket can't set request headers, so GraphQL over WebSocket sends credentials in the `connection_init` payload, and the server decides there whether to acknowledge. Field-level authorization carries over whatever the transport: an event is as visible as its cargo, so a secured `cargoHandled` asks the booking source for the cargo before it subscribes. `examples/21-real-time` has no authentication. A `subscribe` frame carries a full document like a POST body, so a persisted-query trusted-document rule applies to it too.

## The cost of a subscription

**One execution per event, with fresh reads.** Each event runs the selection set, and each batch resolver or DataLoader runs for it. A two-event subscription makes two `getCargos`, two `getLocations`, two `getItineraries` and two `listEventsFor`, all under one request id, because the subscription is one long request. The first event reports `IN_PORT` and the second `ONBOARD_CARRIER`, and the second is correct only because its `Cargo.delivery` read the handling events again. A DataLoader caches by key for as long as it lives, and a subscription outlives its events, so each event must start with empty loaders. On Quarkus a graphql-java `Instrumentation` clears them in `beginSubscribedFieldEvent`, which graphql-java calls before each event, installed through the same `GraphQL.Builder` event as depth and cost limits. On Python the subscription resolver renews the context's loaders before it yields each event.

{% include codetabs.html langs="Quarkus|Python" %}

```java
static final class ClearLoaders extends SimplePerformantInstrumentation {
    @Override
    public InstrumentationContext<ExecutionResult> beginSubscribedFieldEvent(
            InstrumentationFieldParameters parameters, InstrumentationState state) {
        parameters.getExecutionContext().getDataLoaderRegistry().getDataLoaders().forEach(DataLoader::clearAll);
        return super.beginSubscribedFieldEvent(parameters, state);
    }
}
```

```python
def begin_event(self) -> None:
    """Give the next event of a subscription loaders with empty caches."""
    self.loaders = self._new_loaders()
```

**A queue per subscriber.** A slow consumer must not grow the process. Each watcher has a bounded queue of 100 events. On Python it is an `asyncio.Queue(maxsize=100)`, and a watcher that falls that far behind is ended: the next result is the masked error `Internal server error.` (the lagging error isn't one the schema exposes, so error masking hides its message) and its registry entry is removed. On Quarkus the queue is an `ArrayBlockingQueue` of the same size behind a Mutiny `UnicastProcessor`, which fails its subscriber when the queue is full. A production service chooses the policy by what the client can recover from: drop the subscriber, drop the oldest events or coalesce them.

**Cleanup.** A subscriber that is never removed holds a queue and a socket for ever. Both stacks decrement the registry when a subscription ends: on `complete`, on a closed socket, and on a client that disappears. A client killed mid-stream sends nothing, so it is the server noticing the closed connection that clears the entry.

**Fan-out.** Every watcher of a cargo executes the selection for every event of that cargo. Ten thousand clients watching one hot cargo cost ten thousand executions per event, which is why the selection stays small and why a fixed-payload feed can be encoded once and written to every connection. Another cargo's watchers do no work: the filter runs before the execution.

## Ordering and delivery

Events for one cargo arrive in registration order: the store broadcasts under the same lock that issues ids, and each watcher's queue is first in, first out. Across cargos there is no order to rely on. Delivery to a connected subscriber is at most once: an event registered while no one watches is gone for that subscriber, and the GraphQL transports don't replay it. The feed's replay is the exception, and it lets a client miss nothing without a broker. An idempotent retry of a mutation produces no second event.

> **Decision**
>
> Clients that differ in what they read take a GraphQL transport, and each event runs their own selection: `graphql-transport-ws` by default, GraphQL over SSE where an upgrade is awkward. Clients that all want the same payload, or must resume without missing events, take the plain SSE feed. Whatever the transport, bound every subscriber's queue, execute each event with fresh loaders, and remove every subscriber when its connection ends.

> **🤖 Explore with your agent**
>
> "In examples/21-real-time, review how Quarkus and Python serve `Subscription.cargoHandled` against three rules: each event starts with empty DataLoaders, each watcher has a bounded queue, and a subscriber is removed on `complete` and on a dropped connection. List every path where a subscriber could stay registered or an event could read a cached value, and name the file for each."
>
> Check: subscribe with the `gql` client under `client/`, register events with `registerHandlingEvent`, and confirm `curl -s localhost:8311/debug/subscribers` returns to zero after the client completes.

## Build, run, observe

Start the stack and define two helpers. `C` runs the subscription client on the compose network, where the servers are `quarkus` and `python` on port 8080. `R` registers a handling event.

```bash
docker compose -f examples/21-real-time/compose.yaml up -d --build
C() { COMPOSE_PROGRESS=quiet docker compose -f examples/21-real-time/compose.yaml run --rm -T client "$@"; }
R() { curl -s localhost:$1/graphql -H 'Content-Type: application/json' \
  -d "{\"query\":\"mutation(\$i: RegisterHandlingEventInput!) { registerHandlingEvent(input: \$i) { handlingEvent { id } userErrors { code } } }\",\"variables\":{\"i\":$2}}"; echo; }
```

Subscribe to ABC123 for two events in the background, with the frames on stderr, then register three events. The subscriber count says when the subscription exists, and the mutations wait for it:

```bash
C --url ws://python:8080/graphql --tracking-id ABC123 --count 2 --frames 2>frames.txt &
until curl -s localhost:8311/debug/subscribers | grep -q '"ABC123":1'; do sleep 1; done
curl -s localhost:8311/debug/subscribers
R 8311 '{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z"}'
R 8311 '{"trackingId":"DEF456","type":"CUSTOMS","location":"NLRTM","completionTime":"2026-10-09T16:00:00Z"}'
R 8311 '{"trackingId":"ABC123","type":"LOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T18:00:00Z"}'
wait
```

```json
{"graphql":{"ABC123":1},"sse":{}}
{"data":{"registerHandlingEvent":{"handlingEvent":{"id":"evt_10"},"userErrors":[]}}}
{"data":{"registerHandlingEvent":{"handlingEvent":{"id":"evt_11"},"userErrors":[]}}}
{"data":{"registerHandlingEvent":{"handlingEvent":{"id":"evt_12"},"userErrors":[]}}}
{"cargoHandled": {"id": "evt_10", "type": "UNLOAD", "location": {"name": "Hamburg"}, "cargo": {"trackingId": "ABC123", "delivery": {"transportStatus": "IN_PORT"}}}}
{"cargoHandled": {"id": "evt_12", "type": "LOAD", "location": {"name": "Hamburg"}, "cargo": {"trackingId": "ABC123", "delivery": {"transportStatus": "ONBOARD_CARRIER"}}}}
```

The client printed two events and no event for DEF456's `evt_11`. `frames.txt` holds the six frames of Figure 21.3 (`>>>` is the client's, `<<<` the server's; the subscribe frame is shortened):

```text
>>> {"type": "connection_init", "payload": {}}
<<< {"type":"connection_ack"}
>>> {"id": "1", "type": "subscribe", "payload": {"query": "subscription Watch($id: TrackingId!) {...}", "variables": {"id": "ABC123"}}}
<<< {"id":"1","type":"next","payload":{"data":{"cargoHandled":{"id":"evt_10","type":"UNLOAD","location":{"name":"Hamburg"},"cargo":{"trackingId":"ABC123","delivery":{"transportStatus":"IN_PORT"}}}}}}
<<< {"id":"1","type":"next","payload":{"data":{"cargoHandled":{"id":"evt_12","type":"LOAD","location":{"name":"Hamburg"},"cargo":{"trackingId":"ABC123","delivery":{"transportStatus":"ONBOARD_CARRIER"}}}}}}
>>> {"id": "1", "type": "complete"}
```

Once the client has completed, `curl -s localhost:8311/debug/subscribers` answers `{"graphql":{"ABC123":0},"sse":{}}`. Replace `python` and 8311 with `quarkus` and 8310 and the same registrations give the same events and frames.

Resume the plain feed from `evt_10` while one more event is registered. Python:

```bash
(sleep 2; R 8311 '{"trackingId":"ABC123","type":"CUSTOMS","location":"DEHAM","completionTime":"2026-10-09T19:00:00Z"}' >/dev/null) &
curl -sN -m 6 localhost:8311/events/cargos/ABC123 -H 'Last-Event-ID: evt_10'
```

```text
event: handled
data: {"id":"evt_12","trackingId":"ABC123","type":"LOAD","location":"DEHAM","completionTime":"2026-10-09T18:00:00Z"}
id: evt_12

event: handled
data: {"id":"evt_13","trackingId":"ABC123","type":"CUSTOMS","location":"DEHAM","completionTime":"2026-10-09T19:00:00Z"}
id: evt_13
```

`evt_12` is the replay and `evt_13` is live. On Quarkus the same fields are written as `id:evt_12`, `event:handled` and `data:{...}`, without the space after each colon. GraphQL over SSE is the same subscription as a `POST`, on Python:

```bash
(sleep 2; R 8311 '{"trackingId":"ABC123","type":"CUSTOMS","location":"DEHAM","completionTime":"2026-10-09T20:00:00Z"}' >/dev/null) &
curl -sN -m 6 localhost:8311/graphql -H 'Content-Type: application/json' -H 'Accept: text/event-stream' \
  -d '{"query":"subscription Watch($id: TrackingId!) { cargoHandled(trackingId: $id) { id type } }","variables":{"id":"ABC123"}}'
```

```text
event: next
data: {"data":{"cargoHandled":{"id":"evt_14","type":"CUSTOMS"}}}
```

Stop the stack when done:

```bash
docker compose -f examples/21-real-time/compose.yaml down -v
```

`bash examples/21-real-time/verify.sh` runs the whole sequence on both stacks and prints `PASS` when both hold.

| Check | Quarkus | Python |
|---|---|---|
| `graphql-transport-ws` | `evt_10` then `evt_12`; `IN_PORT` then `ONBOARD_CARRIER`; nothing for DEF456 | the same |
| `graphql-ws` | one event; `connection_init`, `connection_ack`, `start`, `data`, `stop`, `connection_terminate` | the same |
| GraphQL over SSE | not served | one `event: next` with the new id |
| Plain feed | `handled` with the fixed payload | the same |
| Resume from `evt_10` | `evt_12` to `evt_18`, then live `evt_19` | `evt_12` to `evt_19`, then live `evt_20` |
| Lagging subscriber | queue of 100 per watcher | 102 appends before the next read: `Internal server error.`, registry back to 0 |

Experiments:

- Subscribe with `cargoHandled { weight }`: an `error` frame names `weight`, the client exits 1, and no subscriber is registered.
- Register three events at once: ids arrive in registration order.
- Run `docker kill` on a client that asked for five events and read one: the subscriber count returns to 0 within five seconds.
- Reconnect the plain feed with `Last-Event-ID: evt_10`: stored events after `evt_10` arrive in registration order, then the live one, each once.

## For deeper coverage

- Cloud Native Design Patterns, chapter "Appendix C: WebSockets": the general WebSocket and bidirectional-streaming patterns.
- The `graphql-ws` repository's `PROTOCOL.md`: the `graphql-transport-ws` message sequence.
- The `graphql-sse` protocol document: the distinct-connections mode.
- WHATWG HTML Standard, server-sent events section: `Last-Event-ID`, reconnection and the `EventSource` behavior.
- RFC 6455, "The WebSocket Protocol", and RFC 8441, which bootstraps WebSockets over HTTP/2.
- [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) and [Quarkus REST guide](https://quarkus.io/guides/rest): subscriptions with Mutiny `Multi` and server-sent events.
- Strawberry's [subscriptions guide](https://strawberry.rocks/docs/general/subscriptions) and FastAPI's documentation on server-sent events (`EventSourceResponse`).
