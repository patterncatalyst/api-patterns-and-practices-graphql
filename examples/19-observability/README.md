# Ch19 - Observability

Both stacks export traces, metrics and logs over OTLP to one container, `grafana/otel-lgtm`, and
`verify.sh` reads the result back from it. Every traced request carries a trace id chosen by the script,
and every assertion fetches that trace from Tempo by its id. The responses, the schema and the source
calls are Chapter 13's; the telemetry around them is new.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything in it except
`Subscription`, which Chapter 21 builds. Telemetry changes no field, argument or nullability, and
`assert_sdl_conforms` proves it. The seed, the cursors, the error contract and the `finalArrivalTime`
deprecation are Chapter 13's.

### What each stack adds

| Concern | Quarkus | Python |
|---|---|---|
| HTTP span | `quarkus-opentelemetry` | `opentelemetry-instrument` (FastAPI) |
| Operation span and a span per resolver | the OpenTelemetry project's `opentelemetry-graphql-java-20.0`, installed through the `GraphQL.Builder` event in `Telemetry.java`; SmallRye's own operation span is off | Strawberry's `OpenTelemetryExtension`, with `drop_arguments` as its `arg_filter` |
| `source.call` span | `@WithSpan` on `SourceCalls.call` and `write` | `start_as_current_span` in `app/sources.py` |
| `graphql.errors`, `graphql.field.deprecated.usage` | a graphql-java `Instrumentation` in `Telemetry.java` | `OperationMetrics`, a `SchemaExtension`, in `app/telemetry.py` |
| Logs | `quarkus.otel.logs.enabled=true` | `OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true` |

## Run it

```bash
bash examples/19-observability/verify.sh
```

`verify.sh` brings the stack up with `docker compose`, runs the cases below in a fixed order on both
stacks, diffs each live schema against `contracts/schema/` and tears the stack down. It prints `PASS`
only if every check holds on both stacks. It needs Docker Engine with the `docker compose` plugin and
Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/19-observability/compose.yaml up -d --build
open http://localhost:8292    # Grafana; Explore has Tempo, Prometheus and Loki data sources
docker compose -f examples/19-observability/compose.yaml down -v
```

The apps start after `lgtm` is healthy. Metrics export every 5 seconds and spans every second, which is
shorter than the defaults (60 s and 5 s); span metrics and Loki add a few seconds on top.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the log
and answers `204`, as in Chapter 13. The endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true`
(compose sets it). The number of `source.call` spans of a request equals the number of log entries for
it, which `verify.sh` asserts.

## Ports

| Stack or service | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8290 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8291 | `/graphql` (health at `/health`) |
| Grafana | 3000 | 8292 | UI, anonymous Admin (lab only) |
| Tempo | 3200 | 8293 | `/api/traces/<trace id>` |
| Prometheus | 9090 | 8294 | `/api/v1/query` |
| Loki | 3100 | 8295 | `/loki/api/v1/query_range` |

Compose project `gql-ch19-observability`, containers `ch19-observability-*`. The collector's OTLP ports
(4317, 4318) stay inside the compose network. The stores sit on this chapter's block of ports, so the
example does not collide with an observability stack of your own on 3000, 4317, 9090, 3100 or 3200.

## On the wire

Each value below is asserted by `verify.sh`. The trace of `FanOut` has 25 resolver spans on both stacks.

| Case | Quarkus | Python |
|---|---|---|
| FanOut data and calls | Chapter 13's data; 8 calls | Chapter 13's data; 6 calls |
| trace | one `POST /graphql` whose parent is the caller's span; one `query FanOut` below it | one `POST /graphql`; one `GraphQL Query: FanOut` below it |
| resolver spans | `cargos` 1; `node`, `itinerary`, `delivery`, `voyage`, `loadLocation`, `unloadLocation` 4 each, named for the field | the same, named `GraphQL Resolving: <field>` |
| trivial fields | `trackingId`, `edges`, `legs`, `number`, `unLocode`, `transportStatus`: no span | the same |
| `source.call` | 8 spans (= call log); `getLocations` 2 | 6 spans; `getLocations` 1 |
| TrackCargo | `ONBOARD_CARRIER`; document attribute `graphql.document` has no `ABC123` | the same with attribute `query` |
| TrackLiteral | `graphql.document` is `query TrackLiteral{cargo(trackingId:?){trackingId}}` | `query` is the document as sent |
| CargoPage | `SERVICE_UNAVAILABLE` at edge 1, message `booking service unavailable`; both `node` spans and the operation span `ERROR` | the same at edge 1; the edge-1 `node` span `ERROR`, the other `UNSET` |
| span metrics | `traces_spanmetrics_calls_total{service, span_name="query TrackCargo"}` 3, latency count 3 | `span_name="GraphQL Query: TrackCargo"`, 3 and 3 |
| `graphql_errors_total` | `error_code="SERVICE_UNAVAILABLE", graphql_operation_name="CargoPage"`: 2 | 1 |
| `graphql_field_deprecated_usage_total` | `Itinerary.finalArrivalDate`: `client_name="legacy-app"` 2, `"unknown"` 1, total 3 | the same |
| Loki | `{service_name="ch19-observability-quarkus"} \| trace_id="<id>" \| exception_type=~".*SourceUnavailable.*"` finds the record | the same for `ch19-observability-python` |
| schema | conforms; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

## Code-first notes

The example runs on the pinned versions (Quarkus 3.40.1 with OpenTelemetry SDK 1.62.0 and
`opentelemetry-graphql-java-20.0` 2.28.1-alpha, the version the platform manages; Strawberry 0.335.0 with
`opentelemetry-*` 1.45.1 and 0.66b1; `grafana/otel-lgtm` 0.37.0).

**Prometheus names.** OTLP names translate by replacing dots with underscores and appending `_total` to
monotonic counters: `graphql.errors` is `graphql_errors_total`, `error.code` is `error_code`. The
resource attribute `service.name` becomes the label `service_name` (and `job`). Tempo's span metrics
use the label `service`.

**Span metrics.** Tempo's generator emits `traces_spanmetrics_calls_total` and
`traces_spanmetrics_latency_*` per `service`, `span_name`, `span_kind` and `status_code`. The operation
name is in the span name on both stacks, so the series are per operation. On Quarkus this needs
`setOperationNameInSpanNameEnabled(true)`.

**Durations.** Quarkus passes `quarkus.otel.metric.export.interval` and `quarkus.otel.bsp.schedule.delay`
to the SDK as written, and the SDK reads lowercase units: `5s`, `1s`.

**Instrumentation chain.** `Telemetry.instrument` reads SmallRye's chain from a throwaway `build()` and
appends the OpenTelemetry instrumentation and `TrackingInstrumentation`, as Chapter 14's `QueryCost`
does. The tracking instrumentation reads `X-Client-Name` from `CurrentVertxRequest` when the execution
state is created and carries it in that state.

**Error codes on Quarkus.** SmallRye writes `extensions.code` through `DeclaredErrorCodeProvider` when
it serializes an error. The metric asks the same class about the exception behind the graphql-java
error (`DeclaredErrorCodeProvider.codeOf`), so metric and response agree. An error with no declared
code counts as `unclassified`.

**Span parentage.** Resolver spans descend from the operation span on both stacks. A batched
`source.call` serves several resolvers: on Python it is a child of a resolver span of its level, on
Quarkus a child of the context that dispatched the batch. In every case it is in the request's trace,
below the HTTP span.

**Attributes.** Quarkus: `graphql.operation.name`, `graphql.operation.type`, `graphql.document`
(literals replaced by `?`), `graphql.field.name`, `graphql.field.path`. Python: `component`, `query`,
`graphql.parentType`, `graphql.path`; `drop_arguments` leaves no `graphql.param.*`.

**Logs.** On both stacks the exception log record carries `trace_id` as structured metadata in Loki,
together with `exception_type` and `exception_message`.

**Healthcheck.** The `lgtm` healthcheck is a `curl` against Grafana, Tempo and Loki.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/19-observability-architecture.py`) show the compose topology: a client
with a `traceparent` sending queries to each stack, both stacks exporting OTLP to `lgtm`, and each
stack diffed against the canonical SDL.
