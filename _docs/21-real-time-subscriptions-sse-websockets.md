---
title: "Real-time: subscriptions vs SSE vs WebSockets"
order: 21
part: "Real-time & Client Integration"
description: "Pushing handling events to a client three ways on both stacks: Subscription.cargoHandled over graphql-transport-ws, GraphQL over SSE, and a plain SSE feed that resumes from Last-Event-ID. The event path from store to frame, what each event costs, how subscribers are cleaned up, and where a raw WebSocket protocol fits."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Serve `Subscription.cargoHandled` over `graphql-transport-ws` on both stacks and trace the six-frame handshake: `connection_init`, `connection_ack`, `subscribe`, `next`, `next`, `complete`.
- Contrast a GraphQL subscription, GraphQL-over-SSE and a plain SSE feed on selection, resume and transport cost, and pick the right one from a client's needs.
- Resume a plain SSE feed correctly from `Last-Event-ID` by joining the broadcast before replaying stored events, so no event is lost or duplicated.
- Clear per-event state (`DataLoader` caches, `beginSubscribedFieldEvent`) between subscription events so a long-lived stream never serves stale batched data.
- Bound a subscriber's queue and verify cleanup on `complete` and on a dropped connection, so a slow or disconnected client can't grow the process.

## Why this matters

Every chapter so far answered a request with a response. The tracking view also has a field for clients that want to be told: `Subscription.cargoHandled(trackingId:)` emits each handling event for one cargo as it is registered. Chapter 1 introduced it as an operation that produces a stream of results over a long-lived connection, and Chapter 2 placed it among the axes as a read delivered as a stream. This chapter serves it.

The code is in `examples/21-real-time/`. It starts from the Chapter 13 example and serves the whole canonical SDL, `Subscription` included, so the contract diff that Chapters 5 and 11 describe now compares a complete schema. Both stacks serve the subscription over WebSocket. Strawberry also serves it over server-sent events. Both stacks serve a plain SSE feed that is not GraphQL at all. A small Python client on `gql` runs on the compose network and reads each transport, and `verify.sh` asserts what arrives, in what order, with what reads behind it, and what is cleaned up afterwards.

## Asking once, hearing many times

A query asks once and gets one answer. A subscription is a document that stays open: the client sends it once and the server answers with a result for every event. Each result has the shape of the client's own selection set, because each event executes that selection:

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

The payload of `cargoHandled` is a `HandlingEvent`, an ordinary object type. `location` and `cargo` are the resolvers of Chapter 13, so the sources behind them run for every event: one `location` read, one `cargo` read, and the itinerary and event reads that `delivery` needs. The specification describes the mechanism in two steps. CreateSourceEventStream turns the field into a stream of source events, and MapSourceToResponseEvent executes the selection set once for each event and yields the result. The resolver of the subscription field produces events, and everything below it is the executor of Chapter 6 running again.

That is the difference from a feed. A client that wants only `id` and `type` writes a smaller selection and the sources behind `location` and `delivery` are not touched. A client that wants the delivery status as of this event gets it, computed from the handling history at that moment.

## Four ways to push

A server has four reasonable ways to tell a client that something happened, and the example serves three of them.

{% include excalidraw.html file="21-three-ways-to-push" alt="A grid with four columns and seven rows. The columns are GraphQL over WebSocket using graphql-transport-ws, GraphQL over SSE using graphql-sse, a plain SSE feed at GET events cargos trackingId, and a raw WebSocket with your own protocol. The rows are direction, framing, selection, resume, HTTP path, credentials and served here. The two GraphQL columns carry the client's selection set and have no resume. The plain feed has a fixed payload and resumes by Last-Event-ID replay. The raw WebSocket column is dashed because its cells are all yours to design. The last row shows Quarkus and Python serve the WebSocket subscription and the feed, Python serves GraphQL over SSE, and the raw WebSocket is prose only." caption="Figure 21.1 — Four ways to push. The GraphQL columns keep the selection set and the schema; the plain feed trades them for HTTP semantics and resume." %}

A **GraphQL subscription over WebSocket** is the default for the ecosystem. The client opens a socket, offers the `graphql-transport-ws` subprotocol, and sends subscribe messages that carry ordinary GraphQL documents. One socket can carry several subscriptions, and the same socket can run queries and mutations.

**GraphQL over SSE** carries the same documents over HTTP. The client sends a `POST` with `Accept: text/event-stream`, and the response is an event stream with one `next` event per result. It needs no upgrade, so anything that handles an HTTP response handles it. The `graphql-sse` protocol calls this the distinct connections mode, one HTTP request per subscription.

A **plain SSE feed** drops GraphQL. `GET /events/cargos/{trackingId}` returns a stream of events with a fixed payload and no selection. What it gains is everything SSE defines: event ids, automatic reconnection in the browser's `EventSource`, and a header, `Last-Event-ID`, that lets a server resume.

A **raw WebSocket** with a protocol of your own is the fourth and appears in prose only; a later section says when it is worth its cost.

## The event path

An event starts as a mutation. `registerHandlingEvent` validates, appends to the handling store, and returns. The subscription does not read the mutation's payload: it listens to the store.

{% include excalidraw.html file="21-event-path" alt="A flow from left to right on two rows. A user box, registerHandlingEvent for ABC123 UNLOAD at DEHAM on V100S, leads to a handling store box that appends evt_10 and does nothing for an idempotent replay. That leads to a broadcast box holding a bounded queue per watcher. From broadcast, a dashed arrow goes to a ghost box, watcher DEF456, which does not match and receives nothing. An amber arrow goes to watcher ABC123, which leads down to a box that executes the selection set with four reads: location.getLocations DEHAM, booking.getCargos ABC123, routing.getItineraries ABC123 and handling.listEventsFor ABC123. That leads left to a dark box, the next frame or SSE event for evt_10 in Hamburg at IN_PORT, and then to a subscriber box that receives evt_10 and then evt_12 and never DEF456's event." caption="Figure 21.2 — From a registration to a frame. The store broadcasts after it writes; each watcher takes the events of its own cargo and executes its selection for each." %}

The store broadcasts after the write succeeds and never for an idempotent replay. A retried mutation with the same `idempotencyKey` returns the original event and writes nothing, so a watcher hears each event once. Each watcher owns a queue, takes only the events of the cargo it named, and the framework executes the selection for each event it takes. Listening to the store and not to the mutation's payload means any writer reaches a subscriber: a retried request, a batch import, another service. In process this is a few lines. Across several server instances the store would publish to a message broker and every instance's watchers would subscribe to it; the chapter's subscribers and frames do not change.

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

SmallRye's `@Subscription` annotation marks a method that returns a Mutiny `Multi`, the stream type that the `BroadcastProcessor` behind the store implements. Strawberry's `@strawberry.subscription` marks an async generator. In both, the resolver is only the source of events. Selection, serialization and the transport belong to the framework.

## Subscriptions over WebSocket

The `graphql-transport-ws` protocol is small. The client opens the socket and offers the subprotocol, then sends `connection_init` with an optional payload. The server answers `connection_ack`. The client sends `subscribe` with an id and the document. The server sends one `next` per result with that id, and `complete` when the stream ends. Either side may send `complete` to end a subscription, and `ping` and `pong` keep an idle socket alive.

{% include excalidraw.html file="21-transport-ws-sequence" alt="A sequence diagram with a client lifeline on the left and a server lifeline on the right. Six arrows run between them. The client sends connection_init with an empty payload. The server answers connection_ack. The client sends subscribe with id 1 for the subscription Watch with trackingId ABC123. The server sends two amber next frames with id 1, the first for evt_10, UNLOAD, Hamburg, IN_PORT, and the second for evt_12, LOAD, Hamburg, ONBOARD_CARRIER. The client sends complete with id 1. Notes beside the arrows say that evt_10 and evt_12 were registered at the two next frames and that the DEF456 event sends no frame." caption="Figure 21.3 — Six frames for a subscription that delivers two events, as the client logged them." %}

The figure is one run of `verify.sh`. The client asked for two events and then ended its subscription; the server removed the subscriber. A registration for DEF456 between the two ABC123 events produced no frame, because the watcher was registered for ABC123.

The older `graphql-ws` subprotocol is the one the `subscriptions-transport-ws` library spoke, with `start`, `data` and `stop` where the newer protocol has `subscribe`, `next` and `complete`. Both stacks accept it, `verify.sh` asserts it once, and new clients should use `graphql-transport-ws`. The subprotocol is the first thing a client and server negotiate: a client offers a list, and the server's choice is the protocol for that socket.

Neither server contains protocol code. SmallRye GraphQL speaks both subprotocols on `/graphql` by default. Strawberry's `GraphQLRouter` takes a tuple of protocols to serve, and the example names all three:

```python
GraphQLRouter(
    schema,
    context_getter=get_context,
    subscription_protocols=(
        GRAPHQL_TRANSPORT_WS_PROTOCOL,
        GRAPHQL_WS_PROTOCOL,
        GRAPHQL_SSE_PROTOCOL,
    ),
)
```

The WebSocket upgrade itself needs an implementation in the ASGI server, so the Python image installs `uvicorn[standard]`. The test client has no protocol code either. It is a `gql` `Client` over `WebsocketsTransport`, and the subprotocol is an argument:

```python
transport = WebsocketsTransport(url=args.url, subprotocols=[args.subprotocol])
async with asyncio.timeout(args.timeout):
    async with Client(transport=transport) as session:
        async for result in session.subscribe(
            document, variable_values={"id": args.tracking_id}
        ):
            print(json.dumps(result), flush=True)
            received += 1
            if received >= args.count:
                return 0
```

A document that fails validation never subscribes. `cargoHandled { weight }` gets an `error` frame that names `weight`, and the subscriber count stays at zero. Each stack words the message in its own engine's terms; `verify.sh` asserts that the field is named and that nothing was registered.

## GraphQL over SSE

Strawberry serves the same subscription over HTTP when `GRAPHQL_SSE_PROTOCOL` is in the list; the Quarkus stack serves it over WebSocket. The client sends the document as a normal GraphQL `POST` and asks for a stream:

```bash
curl -N localhost:8311/graphql -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' -d "$SUB_BODY"
```

The response is `Content-Type: text/event-stream`, and each result arrives as an `event: next` whose data is the ordinary GraphQL response, `{"data":{"cargoHandled":{...}}}`. When the stream ends the server sends `event: complete`, and while it is idle the server sends a `: ping` comment line, so a proxy with an idle timeout keeps the response open.

This transport suits clients and networks where an upgrade is awkward: a corporate proxy that only understands plain HTTP responses, a serverless platform, a client library with an HTTP stack and no WebSocket one. It is one direction, so a client that wants a second subscription opens a second request. Over HTTP/1.1 a browser spends one of its few connections per host on each open stream, and HTTP/2 multiplexes them on one.

## A plain SSE feed, and resume

Server-sent events are older and simpler than any GraphQL transport. The response is `text/event-stream`, and the stream is lines in four fields, `event:`, `data:`, `id:` and `retry:`, with a blank line ending each event. Lines that start with a colon are comments, which servers use to keep an idle connection warm.

The feed in the example is `GET /events/cargos/{trackingId}`, and each event is `handled`:

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

Quarkus REST builds each event with the injected `Sse`; FastAPI's `EventSourceResponse` encodes each `ServerSentEvent` the route yields and adds keep-alive comments while the feed is idle. Each stack writes the lines its own way, and a client reads them the same:

```text
event: handled
data: {"id":"evt_12","trackingId":"ABC123","type":"LOAD","location":"DEHAM","completionTime":"2026-10-09T18:00:00Z"}
id: evt_12
```

The payload is fixed. A client that wants the location's name or the delivery status has to fetch it, which is the cost of dropping the selection set. What the feed gains is resume. The `id:` line names each event, and a browser's `EventSource` remembers the last one it saw. When the connection drops it reconnects on its own and sends that id in a `Last-Event-ID` request header. A server that kept the events can answer with everything after that id.

The id has to be something the server can order. The example uses the sequence in `evt_<n>`, which follows registration order. Completion time would not do: the store lists a cargo's history by when the handling happened, and an event registered late lands in the middle of it, so "everything after" a completion time would skip it. The feed replays by registration order for the same reason the broadcast delivers in it.

{% include excalidraw.html file="21-sse-resume" alt="Three stacked bands. The first, connected, shows a GET request for events cargos ABC123 with Accept text event-stream leading to a handled event with id evt_10, which the client remembers as Last-Event-ID evt_10. The second, dropped, shows a dark box for connection lost leading to a box saying events registered meanwhile are stored: evt_12 to evt_18. The third, reconnected, shows a GET with Last-Event-ID evt_10 leading to three steps: join the broadcast so no live event can slip by, replay in registration order evt_12 to evt_18, then live evt_19, with live ids already replayed dropped so no id is sent twice." caption="Figure 21.4 — Resume is a header and a store. The feed joins the broadcast before it reads the replay, so an event that arrives in between is neither lost nor sent twice." %}

The ordering matters. If the feed read the stored events first and joined the broadcast afterwards, an event registered between the two steps would be in neither. So the watcher joins the broadcast first, replays the stored events after the given id in registration order, then reads the live queue and skips ids it has already sent. `verify.sh` registers events while no feed is open, reconnects with `Last-Event-ID: evt_10`, registers one more once the feed is open, and asserts the exact id list: the stored events after `evt_10` in registration order, then the live one, each once.

A GraphQL subscription has no equivalent. Its ids belong to a socket and die with it, and a client that reconnects subscribes again and misses whatever happened in between. A client that must not miss events subscribes first and then queries `handlingHistory` for the events it lacks, or reads the feed.

## Raw WebSockets

A WebSocket is a bidirectional message channel over one TCP connection, defined by RFC 6455. It has no opinion about what messages mean. Choosing one without GraphQL means designing the parts the GraphQL protocols above provide: how messages are framed and typed, how a request is matched to its reply, how acknowledgements work, how credentials are sent when the browser API cannot set headers, how a client resumes after a drop, and how both sides notice a dead peer.

That cost is worth paying when the traffic is two-way and high-frequency, as in chat, collaborative editing, a game or a trading screen, and when the messages do not have the shape of a graph. For the tracking view, a client that watches a cargo and reads a few fields of each event is a subscription or a feed, and nothing is gained by inventing a protocol. The forthcoming WebSockets book in this series covers them in depth; this chapter stops at the boundary.

## Choosing between them

Three questions decide most cases.

**Does the client need a selection?** If different clients want different fields of each event, or the payload is a graph that reaches across services, a GraphQL transport saves a second round trip per event. If every client wants the same few fields, the feed is simpler to write, to cache and to read in a log.

**Does the client need to resume?** The feed does it with a header and the server's store. A GraphQL subscription does not, so a client that cannot afford to miss events pairs it with a query for the missed range, or uses the feed.

**What sits between the client and the server?** A WebSocket needs every hop to pass the upgrade and to hold an idle connection open. SSE needs every hop to pass a long-lived HTTP response without buffering it, and both need idle timeouts longer than the interval between pings or keep-alive comments. Authentication differs too. An SSE request, GraphQL or plain, carries ordinary headers, so Chapter 18's bearer token works unchanged. A browser WebSocket cannot set request headers, so GraphQL over WebSocket sends the credentials in the `connection_init` payload, and the server decides at that point whether to acknowledge. Whatever the transport, Chapter 18's rules carry over: an event is as visible as its cargo, so a secured `cargoHandled` asks the booking source for the cargo before it subscribes, and each event's `cargo` field reads through the same source. This example, like Chapter 13's, has no authentication. A `subscribe` frame carries a full document like a POST body, so Chapter 15's trusted-document rule applies to it too.

## The cost of a subscription

A subscription holds a connection and a registry entry for as long as the client wants, and does work for every event. Four costs follow.

**One execution per event, with fresh reads.** Each event runs the selection set, and each `@Source` batch resolver or DataLoader runs for it. The log of a two-event subscription shows two `getCargos`, two `getLocations`, two `getItineraries` and two `listEventsFor`, all under one request id, because the subscription is one long request. That count is the point of the second event's `transportStatus`. The first event reports `IN_PORT` and the second `ONBOARD_CARRIER`, and the second is correct only because its `Cargo.delivery` read the handling events again. A DataLoader caches by key for as long as it lives, and a subscription outlives its events, so each event must start with empty loaders. On Quarkus a graphql-java `Instrumentation` clears them in `beginSubscribedFieldEvent`, which graphql-java calls before each event; it is installed through the same `GraphQL.Builder` event as Chapter 14's cost limits:

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

**A queue per subscriber.** A slow consumer must not grow the process. Each watcher has a bounded queue of 100 events. On Python it is an `asyncio.Queue(maxsize=100)`, and a watcher that falls that far behind is ended: the next result is the masked error `Internal server error.` (the lagging error is not one the schema exposes, so Chapter 9's masking hides its message) and its registry entry is removed. An in-process script in the server image appends 102 events to a fresh store before a subscriber reads again, and `verify.sh` asserts exactly that. On Quarkus the watcher's queue is an `ArrayBlockingQueue` of the same size behind a Mutiny `UnicastProcessor`, which fails its subscriber when the queue is full; `verify.sh` exercises the overflow on Python. A production service chooses the policy, drop the subscriber, drop the oldest events or coalesce them, by what the client can recover from.

**Cleanup.** A subscriber that is never removed holds a queue and a socket for ever. Both stacks decrement the registry when a subscription ends: on `complete`, on a closed socket, and on a client that disappears. `verify.sh` asserts both ends. After the client finishes its two events the count is 0 within five seconds, and so is the count after `docker kill` on a client that asked for five events and read one. The killed client sends nothing, so it is the server noticing the closed connection that clears the entry.

**Fan-out.** Every watcher of a cargo executes the selection for every event of that cargo. Ten thousand clients watching one hot cargo cost ten thousand executions per event, which is why the selection stays small and why a fixed-payload feed can be encoded once and written to every connection. A different cargo's watchers do no work: the filter runs before the execution.

## Ordering and delivery

Events for one cargo arrive in registration order: the store broadcasts under the same lock that issues ids, and each watcher's queue is first in, first out. `verify.sh` sends three registrations at once and asserts that the ids arrive in that order. Across cargos there is no order to rely on. Delivery to a connected subscriber is at most once: an event registered while no one watches is gone for that subscriber, and the GraphQL transports do not replay it. The feed's replay is the one exception, and it is what lets a client miss nothing without a broker. An idempotent retry of a mutation produces no second event.

## On the wire

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

| Check | Quarkus | Python |
|---|---|---|
| schema | `assert_sdl_equals`: the live schema equals the canonical SDL, `Subscription` included | the same |
| invalid document | `cargoHandled { weight }`: an `error` frame naming `weight`, client exit 1, no subscriber | the same |
| `graphql-transport-ws` | `evt_10` then `evt_12`, in order; `Hamburg` both; `IN_PORT` then `ONBOARD_CARRIER`; no event for DEF456 | the same |
| frames | `connection_init`, `connection_ack`, `subscribe`, `next`, `next`, `complete` | the same |
| per-event reads | two each of `getCargos`, `getLocations` (`DEHAM`), `getItineraries`, `listEventsFor`; one request id | the same |
| live order | three registrations sent at once, count 3: the ids arrive in registration order | the same |
| cleanup | count 0 within 5 s after `complete`, and within 5 s after `docker kill` | the same |
| `graphql-ws` | one event; `connection_init`, `connection_ack`, `start`, `data`, `stop`, `connection_terminate` | the same |
| GraphQL over SSE | not served | `text/event-stream`; one `event: next` with the new id; count back to 0 |
| plain feed | `handled` with `id:` equal to the new event id and the fixed payload | the same |
| resume | `Last-Event-ID: evt_10`: `evt_12` to `evt_18`, then live `evt_19`, each once | `evt_12` to `evt_19`, then live `evt_20` |
| lagging subscriber | a queue of 100 per watcher, not exercised by `verify.sh` | 102 appends before the next read: `Internal server error.`, registry back to 0 |

Stop the stack when done:

```bash
docker compose -f examples/21-real-time/compose.yaml down -v
```

`bash examples/21-real-time/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Real-time pushes the <em>read and write balance</em> axis of Chapter 2 to its edge: the one subscription is a read delivered as a stream, and the <em>client diversity and shape variance</em> axis decides the transport. Clients that differ in what they read take a GraphQL transport, and each event runs their own selection. Clients that all want the same payload, or must resume without missing events, take the plain feed. The <em>operational and security cost</em> axis shows up as connections, queues and cleanup, and the <em>contract and evolution style</em> axis as the choice of what carries a schema: the subscription is in the canonical SDL and the feed is not. The tracking view therefore serves <code>cargoHandled</code> over <code>graphql-transport-ws</code> on both stacks, over GraphQL-over-SSE on the Python stack, and a plain SSE feed that resumes from <code>Last-Event-ID</code>, bounds every subscriber's queue, executes each event with fresh loaders, and removes every subscriber when its connection ends.</p></div>

## Where this goes next

This chapter completed the canonical schema. `cargoHandled` is served over two GraphQL transports, a plain feed covers what a selection set cannot: resume and plain HTTP. The cost of an open subscription is a queue, a registry entry and one execution per event.

Chapter 22 builds clients: a normalized cache in Apollo Client, generated types, `gql` with local validation and the SmallRye clients. Its subscription support is the client side of this chapter, and it points back here. For the transports, read the `graphql-transport-ws` protocol document in the `graphql-ws` repository (`PROTOCOL.md`), the `graphql-sse` protocol document, the Subscription section of the GraphQL specification, and the WHATWG HTML Standard's section on server-sent events for `Last-Event-ID` and reconnection. RFC 6455 defines the WebSocket protocol, and RFC 8441 bootstraps WebSockets over HTTP/2. The Quarkus [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) covers subscriptions and Mutiny `Multi`, and the [Quarkus REST guide](https://quarkus.io/guides/rest) covers server-sent events. Strawberry's [subscriptions guide](https://strawberry.rocks/docs/general/subscriptions) lists the protocols it serves, and FastAPI's documentation on server-sent events covers `EventSourceResponse`. The forthcoming WebSockets book in this series takes up the raw protocol: framing, acknowledgements, authentication and resume.

## For deeper coverage

- Cloud Native Design Patterns, chapter "Appendix C: WebSockets" — the general WebSocket and bidirectional-streaming patterns this chapter applies to a GraphQL subscription specifically.
- The `graphql-ws` repository's `PROTOCOL.md` — the `graphql-transport-ws` message sequence this chapter's six-frame handshake follows.
- The `graphql-sse` protocol document — the distinct-connections mode this chapter's GraphQL-over-SSE transport implements.
- WHATWG HTML Standard, server-sent events section — `Last-Event-ID`, reconnection and the `EventSource` behavior this chapter's plain feed resumes against.
- RFC 6455, "The WebSocket Protocol" — the framing underneath both `graphql-transport-ws` and the raw-WebSocket option this chapter stops short of.
