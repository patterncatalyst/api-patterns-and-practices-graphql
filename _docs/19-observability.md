---
title: "Observability"
order: 19
part: "Observability & the Gateway"
description: "Telemetry for an API with one endpoint: OpenTelemetry on both stacks, a span per resolver and per source call, errors by code and deprecated-field usage as metrics, span metrics, logs found by trace id, and what to leave out."
duration: "13 min read"
---

## Learning objectives

By the end of this chapter you can:

- Join a server-side trace to the caller's own trace via the W3C `traceparent` header, with no application code on either stack.
- Instrument a span per resolver and per source call (`opentelemetry-graphql-java-20.0`, Strawberry's `OpenTelemetryExtension`) and read the result back from Tempo by trace id.
- Derive RED metrics per GraphQL operation from Tempo's span-metrics generator instead of a per-URL histogram that can't tell `FanOut` apart from `TrackCargo`.
- Record `graphql.errors` by `error.code` and `graphql.field.deprecated.usage` by `client.name` as engine-level counters that no resolver can forget to call.
- Decide what belongs in a span attribute or a metric label (operation name, field coordinate, error code) and what must never appear there (variable values, tokens, owner lists).

## Why this matters

Every GraphQL request hits one route, and a response with errors still answers `200`. A server that answers every question the same way at the HTTP layer has to be observed at the GraphQL layer: by operation, by field and by error code.

Three signals answer different questions. Traces say where the time of one request went. Metrics say how often and how slow across many requests, and which errors by code. Logs hold the detail of one failure that a response must not carry. They are useful together only if one id joins them, and the trace id is that id.

## One endpoint, every operation

An access log and a latency histogram keyed by URL and status describe `POST /graphql` and nothing finer. A fan-out page and a single cargo lookup share the route, the status and the histogram. A response that carries `SERVICE_UNAVAILABLE` at one edge is a `200` like all the others, so a dashboard built from those two labels cannot tell a healthy service from one that fails a field in every response.

The operation name restores the distinction. `query TrackCargo` is a name a person can read in a trace and a team can own, and it comes from the client's own document. A span or metric keyed by operation name, and an error counted by `extensions.code`, sees the same traffic as separate things.

{% include excalidraw.html file="19-one-endpoint-blind-spot" alt="Two panels. The left panel, keyed by URL and status, shows three boxes: POST /graphql with nine requests on one route, status 200 for nine of nine including the request that carried an error, and one latency distribution shared by the fan-out page and the single lookup. An amber arrow labelled split by name leads to the right panel, keyed by operation name, error code and field. It lists FanOut with one request, TrackCargo with three, TrackLiteral with one, CargoPage with one request and one error, and LegacyArrival with three. Two dark boxes follow: the error code SERVICE_UNAVAILABLE counted once, and the field Itinerary.finalArrivalDate used three times, twice by legacy-app. A grey box notes that each operation has its own latency curve." caption="Figure 19.1: The same nine requests, keyed two ways. The operation name and the error code separate what the URL and the status cannot." %}

Operation names are not free. An anonymous operation is named `anonymous` in these metrics, and a client that omits names loses the split. The server cannot enforce naming without rejecting documents, so it belongs in the client's code generation or lint step.

## Three signals, one collector

OpenTelemetry is the vendor-neutral API, SDK and wire protocol for telemetry. An application records traces, metrics and logs through the API and exports them over OTLP to a collector, which routes each signal to a store. The stack runs `grafana/otel-lgtm`, an open source image that bundles a collector with Tempo for traces, Prometheus for metrics, Loki for logs and Grafana in front of them. Both stacks export to the collector on port 4317 inside the compose network. Grafana is on 8292, Tempo on 8293, Prometheus on 8294 and Loki on 8295, apart from the usual 3000, 9090 and 3200 so the lab can run beside an observability stack of your own.

{% include excalidraw.html file="19-telemetry-pipeline" alt="Two boxes on the left, quarkus on port 8290 with quarkus-opentelemetry, the graphql-java instrumentation and a Telemetry observer, and python on port 8291 with opentelemetry-instrument, the OpenTelemetryExtension and OperationMetrics. Amber arrows labelled OTLP lead from both into an OpenTelemetry Collector box on port 4317 that is not published. A dashed box labelled traceparent in from the caller, between the two stacks, points at both of them. From the collector, arrows lead to Tempo for traces on 8293, Prometheus for metrics on 8294 and Loki for logs on 8295. A dashed amber arrow from Tempo to Prometheus is labelled span metrics. Dashed arrows lead from all three stores to Grafana on 8292." caption="Figure 19.2: Three signals leave over one protocol. A caller's traceparent header puts the request in the caller's trace, and the trace id then links spans, span metrics and log records." %}

A trace belongs to the caller when the caller says so. The W3C Trace Context `traceparent` header carries a version, a 16-byte trace id, an 8-byte parent span id and flags. A server that honors it starts its HTTP span as a child of the caller's span, in the caller's trace. Both stacks do that without code, because the HTTP instrumentation reads the header. A gateway in front of several subgraphs works the same way once its OpenTelemetry integration is on (Hive Gateway has one): it propagates `traceparent` to each, so one trace holds the gateway's plan and every subgraph's operation span.

Sampling decides which traces are kept. The lab runs `parentbased_always_on`, the default: keep every trace whose parent was sampled and start a sampled trace when there is no parent. A busy service samples a fraction, and the percentage is a cost choice that belongs to configuration, not to the schema.

## A trace per request, a span per resolver

One request produces one tree: the HTTP server span, an operation span below it, a span for each resolver that does work, and a span for each call into a source. The HTTP span comes from the web framework's instrumentation. The other layers come from the GraphQL engine, and each stack gets them from its own ready-made component.

Quarkus adds `quarkus-opentelemetry` for the SDK, the exporter and the HTTP span, and the OpenTelemetry project's `opentelemetry-graphql-java-20.0`, which instruments graphql-java and produces the operation span and a span per data fetcher. SmallRye fires a `GraphQL.Builder` event before it builds the engine, and that is the seam for appending the instrumentation:

{% include codetabs.html langs="Quarkus|Python" %}

```java
    void instrument(@Observes GraphQL.Builder builder) {
        Instrumentation smallrye = builder.build().getInstrumentation();
        Instrumentation spans = GraphQLTelemetry.builder(openTelemetry)
                .setDataFetcherInstrumentationEnabled(true)
                .setQuerySanitizationEnabled(true)
                .setOperationNameInSpanNameEnabled(true)
                .build()
                .createInstrumentation();
        builder.instrumentation(new ChainedInstrumentation(List.of(smallrye, spans, tracking)));
    }
```

```python
schema = strawberry.Schema(
    query=Query,
    mutation=Mutation,
    config=StrawberryConfig(scalar_map=SCALAR_MAP),
    extensions=[
        partial(MaskErrors, should_mask_error=should_mask, error_message="Internal server error."),
        partial(OpenTelemetryExtension, arg_filter=drop_arguments),
        OperationMetrics,
    ],
)
```

SmallRye has an operation span of its own, turned off with `quarkus.smallrye-graphql.tracing.enabled=false`, so each request has one operation span, from the OpenTelemetry instrumentation.

Python gets the HTTP span from `opentelemetry-instrument`, the zero-code wrapper in the Containerfile's entrypoint, and the rest from Strawberry's `OpenTelemetryExtension`. Strawberry builds one extension per request, so the schema lists a class or a factory such as `partial`. The instrumentation skips introspection fields and plain attribute reads, so a trivial field costs nothing.

The stacks name their spans differently:

| Layer | Quarkus | Python |
|---|---|---|
| HTTP | `POST /graphql` | `POST /graphql` |
| Operation | `query FanOut` | `GraphQL Query: FanOut` |
| Resolver | `itinerary`, with `graphql.field.path` | `GraphQL Resolving: itinerary`, with `graphql.path` |
| Source | `source.call` | `source.call` |

The `source.call` span is the same on both. It wraps the one place every source read goes through, `SourceCalls`, and carries `source.name` and `source.operation`. On Quarkus the `@WithSpan` annotation creates it, and the span ends when the returned `Uni` completes:

```java
    @WithSpan("source.call")
    public <T> Uni<T> call(
            String request,
            @SpanAttribute("source.name") String source,
            @SpanAttribute("source.operation") String op,
            String key,
            Supplier<T> lookup) {
        return Uni.createFrom().deferred(() -> {
            long startMs = nowMs();
            return afterLatency(Uni.createFrom().item(lookup))
                    .eventually(() -> calls.add(new SourceCall(request, source, op, key, startMs, nowMs())));
        });
    }
```

On Python the tracer from the OpenTelemetry API opens it around the lookup:

```python
        # One span per source call: the OpenTelemetry API's manual-instrumentation
        # idiom. It is a child of whichever resolver span is current.
        with _TRACER.start_as_current_span(
            "source.call",
            attributes={"source.name": source, "source.operation": op},
        ):
            try:
                await asyncio.sleep(self._latency)
                return lookup()
            finally:
                self._calls.append(SourceCall(request, source, op, key, start_ms, _now_ms()))
```

## Reading the trace

The trace of the batched fan-out below was read back from Tempo by the id the script sent. The query pages four cargos with each cargo's itinerary legs and delivery. It has four levels, and each level is one tick of the DataLoader machinery.

{% include excalidraw.html file="19-span-per-resolver" alt="A waterfall of one FanOut trace from a Python run, with a time axis from 0 to 1000 milliseconds. At the top, a POST /graphql bar spans the whole request, and a dark GraphQL Query FanOut bar sits below it. Level one shows the cargos resolver and a source.call listCargos bar from 0 to 250 milliseconds. Level two shows four node resolvers and one source.call getCargos bar from 250 to 500. Level three shows four itinerary and four delivery resolvers with source.call getItineraries and source.call listEventsFor from 500 to 750. Level four shows four voyage, four loadLocation and four unloadLocation resolvers with source.call getVoyages and one source.call getLocations from 750 to 1000." caption="Figure 19.3: Twenty-five resolver spans in four levels, and one source.call per batch. Eight location resolvers share a single getLocations span." %}

In Grafana, Explore with the Tempo data source takes a trace id and draws the same waterfall. The slowest resolver span is rarely the answer. The question is which level the time sits in and whether the batch below it served many resolvers or one. Here every level costs one source latency, so the query is as slow as its depth: four levels, about a second. Fewer calls would not make it faster. A shallower selection would.

Both stacks produce 25 resolver spans for this query: `cargos` once, then `node`, `itinerary`, `delivery`, `voyage`, `loadLocation` and `unloadLocation` four times each. `trackingId`, `number`, `unLocode`, `transportStatus`, `edges` and `legs` have none. The resolver spans of a level overlap, because the resolvers start together and wait for the same batch, and end when the value arrives, 250 ms later with the latency compose sets.

The batch is the visible part. Python has six `source.call` spans, one per bulk call, and one is a `getLocations` span under eight location resolvers. Quarkus has eight, with two `getLocations` spans, because SmallRye batches per field and the two location fields have separate loaders. The trace shows that 8-against-6 difference without the call log.

A batched `source.call` serves many resolvers, so it has no single resolver to hang under. On Python it is a child of the resolver span whose turn dispatched the batch. On Quarkus it is a child of whichever context was current when the engine dispatched it. In both it belongs to the request's trace, descends from the HTTP span, and overlaps in time the resolvers it serves.

### Errors in a trace

`GHI345` is the cargo whose booking load fails. The page `cargos(last: 2)`, named `CargoPage`, reaches it. The response carries `SERVICE_UNAVAILABLE` at the failing edge, the message `booking service unavailable`, and no class name or stack frame. The trace holds the rest.

On both stacks the span of the failing resolver ends in status `ERROR` with an exception event holding the type, message and stack trace. On Quarkus both `node` spans of the failed batch end in `ERROR`, and so does the operation span, since SmallRye fails the whole batch. On Python only the span for `GHI345`'s edge does. The `source.call` span for the bulk read is not an error on either stack: the call returned, and one key in it failed.

## Metrics from spans

Tempo's metrics generator turns the spans it receives into Prometheus series without application code: `traces_spanmetrics_calls_total` and a latency histogram, labelled by `service`, `span_name`, `span_kind` and `status_code`. Because operation spans carry the operation name, the series are RED metrics per operation: rate, errors and duration.

Generated metrics count spans by name and status. An error carried inside a `200` response is counted where it is recorded, by code, which is what the next two metrics do.

### Metrics the spans cannot give

Two counters answer questions spans do not: how often each error code occurs, and which clients still select a deprecated field. Both are recorded once per request at the operation level, through the engine's own hook: a graphql-java `Instrumentation` on Quarkus and a Strawberry `SchemaExtension` on Python. No resolver changes, and no field can forget to count.

- `graphql.errors` counts each error of an executed operation, with `error.code` and `graphql.operation.name`. A document that fails to parse or validate never executes and is not counted. An error without a declared code, such as a masked one, counts as `unclassified`, so unexpected failures are visible as their own bucket. On Quarkus the instrumentation reads the code through the same provider that writes `extensions.code`, so metric and response agree.
- `graphql.field.deprecated.usage` counts requests that select a deprecated field, once per field coordinate per request, with `graphql.field.coordinate`, `graphql.operation.name` and `client.name`. Both stacks find the fields by walking the selected operation against the schema, with graphql-java's `QueryTraverser` and graphql-core's `TypeInfo`, so aliases, fragments and variables resolve the way execution resolves them. The client name is the `X-Client-Name` header, or `unknown`. It is read when execution starts, on the thread that holds the HTTP request, and carried to later callbacks in the instrumentation's per-request state.

Prometheus translates the OTLP names: `graphql.errors` becomes `graphql_errors_total` and `error.code` becomes `error_code`. When the count for a deprecated field stays at zero for a release cycle, the field can be removed, and a breaking-change gate will then agree.

The error counter also shows the DataLoader blast radius as a number. One failed key produces one error on Python and two on Quarkus, so `graphql_errors_total{error_code="SERVICE_UNAVAILABLE"}` is 1 and 2 for the same request.

## Logs that point at traces

A log record written while a span is current carries that span's trace id and span id. Both stacks export logs over OTLP: Quarkus with `quarkus.otel.logs.enabled=true` and Python through the logging instrumentation that `opentelemetry-instrument` enables. Loki stores the trace id as structured metadata, so a query can select by it:

```text
{service_name="ch19-observability-python"} | trace_id="<the id the script sent>" | exception_type=~".*SourceUnavailable.*"
```

The record for `CargoPage` holds the exception that the response masked down to a code and a message, with its stack. An operator with the trace id from a trace or a support ticket reaches it in one query. The record does not carry the GraphQL path or a request id, so the trace id is the join key.

## What to record

Telemetry leaves the process and lives longer than the request. Record the shape of a request and keep its values out. Authentication kept the token out of the context for the same reason: the subject is an identity a span may carry, and the token and owner list stay out.

{% include excalidraw.html file="19-what-to-record" alt="Two columns. The left column, record a small set of names, lists the operation name and type, the field coordinate, the error code, the client name and the source name and operation, each with an example. The right column, leave out anything that is a value, lists variable values, resolver arguments, credentials, owner lists and personal data, and literals in a document: Quarkus replaces literals by a question mark, and values belong in variables. A bottom strip about label cardinality shows operation name, field coordinate and error code as labels, and the document and the tracking id as not labels." caption="Figure 19.4: Record the names that describe a request, leave out the values it carries, and keep unbounded values out of metric labels." %}

Span names follow the same rule as labels. The operation span is named for the operation, `query TrackCargo`, not for the document, so the span metrics have one series per operation. That is why the Quarkus instrumentation is configured with the operation name in the span name: without it every operation would share the name `query` and the generated metrics would be as blind as the URL dashboard.

Variable values never reach a span. The operation span's document attribute shows `query TrackCargo($id: TrackingId!)` for a request sent with `{"id": "ABC123"}`. A literal written into the document is part of the document. The OpenTelemetry instrumentation replaces literals with `?` when it records the document, giving `query TrackLiteral{cargo(trackingId:?){trackingId}}`, and the Python extension records the document as sent. The convention that serves both is the one clients already follow: send values as variables. Python's `arg_filter` is `drop_arguments`, which returns an empty dict, so no span has a `graphql.param.*` attribute. The field coordinate says which resolver ran, and the argument would say for whom.

Metric labels have a stricter rule, because every distinct label value becomes its own time series in Prometheus:

| Value | As a label | Why |
|---|---|---|
| Operation name | yes | a client has tens, and they change by deployment |
| Field coordinate, error code | yes | bounded by the schema |
| `client.name` | with care | set by a client header; keep it to issued names and map the rest to `unknown` |
| Tracking id, document | no | unbounded; at most a span attribute, and generated documents multiply the series count without limit |
| Credential | never | the HTTP instrumentation records no `Authorization` header |

> **Decision**
>
> When every client writes its own selection, the only stable units are the operation name, the field coordinate and the error code. One document fans out to several owners, so a span per resolver and per source call is worth its cost: a total latency alone cannot say which source was slow. Export OpenTelemetry over OTLP, join the caller's trace, record the operation, the field and the code and never a value, count errors by code and deprecated usage by client, and find a failure's log record by trace id.

> **🤖 Explore with your agent**
>
> "In examples/19-observability, add a counter `graphql.operations` with the attributes `graphql.operation.name` and `client.name` to the Quarkus `Telemetry` bean and the Python `OperationMetrics` extension, recorded once per executed operation next to graphql.errors. Follow the rule that metric labels are bounded names and never values: leave out variables, tracking ids and the document."
>
> Check: run `bash examples/19-observability/verify.sh`, send `TrackCargo` twice with `X-Client-Name: web`, and query Prometheus on 8294 for `graphql_operations_total` by `client_name`.

## Build, run, observe

`bash examples/19-observability/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold. To explore by hand, start the stack. Quarkus is on `8290`, Python on `8291`, and the stores on `8292` to `8295`.

```bash
docker compose -f examples/19-observability/compose.yaml up -d --build
TID=$(python3 -I -c 'import secrets; print(secrets.token_hex(16))')
curl -s localhost:8291/graphql -H 'Content-Type: application/json' \
  -H "traceparent: 00-$TID-00f067aa0ba902b7-01" \
  -d '{"query":"query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }","variables":{"id":"ABC123"}}'
```

```json
{"data":{"cargo":{"trackingId":"ABC123","delivery":{"transportStatus":"ONBOARD_CARRIER"}}}}
```

Read the trace by the id you sent. Tempo answers a few seconds after the request:

```bash
curl -s localhost:8293/api/traces/$TID | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(sorted({s["name"] for b in d["batches"] for ss in b["scopeSpans"] for s in ss["spans"]}))'
```

```text
['GraphQL Parsing', 'GraphQL Query: TrackCargo', 'GraphQL Resolving: cargo', 'GraphQL Resolving: delivery', 'GraphQL Validation', 'POST /graphql', 'POST /graphql http receive', 'POST /graphql http send', 'source.call']
```

Count the errors by code and the deprecated field by client from Prometheus:

```bash
curl -sG localhost:8294/api/v1/query --data-urlencode 'query=sum by (error_code) (graphql_errors_total)'
curl -sG localhost:8294/api/v1/query --data-urlencode 'query=sum by (client_name) (graphql_field_deprecated_usage_total{graphql_field_coordinate="Itinerary.finalArrivalDate"})'
```

Send the failing page under a trace id of its own, then find the failure's log record by that id in Loki:

```bash
FID=$(python3 -I -c 'import secrets; print(secrets.token_hex(16))')
curl -s localhost:8291/graphql -H 'Content-Type: application/json' \
  -H "traceparent: 00-$FID-00f067aa0ba902b7-01" \
  -d '{"query":"query CargoPage { cargos(last: 2) { edges { node { trackingId } } } }"}'
curl -sG localhost:8295/loki/api/v1/query_range \
  --data-urlencode "query={service_name=\"ch19-observability-python\"} | trace_id=\"$FID\""
```

Stop the stack when done:

```bash
docker compose -f examples/19-observability/compose.yaml down -v
```

The table lists what `verify.sh` asserts on each stack.

| Check | Quarkus | Python |
|---|---|---|
| `FanOut` data and source calls | DataLoader batching's data, 8 calls | DataLoader batching's data, 6 calls |
| HTTP span | one `POST /graphql`, child of the caller's span | the same |
| operation span | one `query FanOut`, descends from the HTTP span | one `GraphQL Query: FanOut` |
| resolver spans | `cargos` 1; `node`, `itinerary`, `delivery`, `voyage`, `loadLocation`, `unloadLocation` 4 each; all descend from the operation span | the same, named `GraphQL Resolving: <field>` |
| trivial fields | no span for `trackingId`, `edges`, `legs`, `number`, `unLocode`, `transportStatus` | the same |
| `source.call` spans | 8, equal to the call log; 2 for `getLocations` | 6; 1 for `getLocations` |
| `TrackCargo` | `ONBOARD_CARRIER`; the document attribute lacks `ABC123`; no `graphql.param.*` | the same |
| `TrackLiteral` | the document attribute is `query TrackLiteral{cargo(trackingId:?){trackingId}}` | the document is recorded as sent |
| `CargoPage` | `SERVICE_UNAVAILABLE` at the edge; both `node` spans and the operation span in `ERROR`; no class name or frame in the response | the edge's `node` span in `ERROR`, the other `UNSET` |
| span metrics | 3 calls and a latency count of 3 for `query TrackCargo` | the same for `GraphQL Query: TrackCargo` |
| `graphql_errors_total` | `SERVICE_UNAVAILABLE` on `CargoPage`: 2 | 1 |
| `graphql_field_deprecated_usage_total` | `Itinerary.finalArrivalDate`: `legacy-app` 2, `unknown` 1, total 3 | the same |
| log record | found by the trace id, exception type and message | the same |
| schema | conforms; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

- Send `TrackCargo` with the id as a literal in the document instead of a variable: Quarkus records `?` in its place, and Python records the document as sent.
- Run without a collector: set `OTEL_SDK_DISABLED=true` for Python and `QUARKUS_OTEL_SDK_DISABLED=true` for Quarkus. The other examples in the series keep telemetry off by default and add the collector with `compose.observability.yaml`; here the collector is a default service and the apps wait for it to be healthy.

## For deeper coverage

- Charity Majors, Liz Fong-Jones & George Miranda, *Observability Engineering* (O'Reilly, 2022): the three-signal model (traces, metrics, logs) for a single-route API.
- Cloud Native Design Patterns, chapter "Observability": the broader tracing, metrics and log-correlation patterns, applied here to a GraphQL engine.
- W3C Trace Context recommendation: the `traceparent` header that joins traces.
- OpenTelemetry specification's "Trace Context" overview and its semantic conventions for GraphQL spans (`graphql.operation.name`, `graphql.operation.type`, `graphql.document`).
- Grafana Tempo documentation, "Metrics-generator": the span-metrics mechanism behind the RED metrics.
- Quarkus guides "Using OpenTelemetry", "Using OpenTelemetry Tracing" and "Using OpenTelemetry Metrics", and the OpenTelemetry Java instrumentation's graphql-java library page.
- Strawberry's OpenTelemetry extension page and the OpenTelemetry Python zero-code instrumentation page.
