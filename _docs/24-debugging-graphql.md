---
title: "Debugging GraphQL"
order: 24
part: "Testing & Debugging"
description: "Diagnosing a GraphQL service from the outside in: the error path, a trace id in every execution error, the trace, the log record and the data behind it, a debug category switched at run time, and the development surfaces production never serves."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Read an error's `path` to find the field that failed before reading any resolver code.
- Follow `extensions.traceId` from a masked response to its span in Tempo and its record in Loki.
- Switch an application debug category to `DEBUG` at run time, with no restart, and read the key a resolver looked up.
- Tell a development surface (GraphiQL, the Dev UI, payload logging) apart from what a production instance serves.
- Count `source.call` spans per level in a trace to confirm a batch did not regress into an N+1.

## Why this matters

A GraphQL problem report arrives as a response that looks fine from the transport's side: status `200`, a `data` object with a hole in it, and an error that says little. Null propagation explains how a null travels, error masking explains why the message of an unexpected error is hidden, and tracing puts every request into a trace. Together they find a fault in the application's own data, resolvers and code paths.

The code is in `examples/24-debugging/` and serves the same schema as the observability example. The seed holds a seventh cargo, `JKL012`, whose route ends at a location code the location service doesn't hold. Every execution error carries `extensions.traceId`. Each stack runs twice, a production instance beside a development instance, so the surfaces a developer uses can be compared with the ones an operator ships.

## Start from the response

The seeded fault produces two failures through ordinary queries. F1 asks for the places the cargo's route unloads:

```graphql
query LegsOfJkl($id: TrackingId!) {
  cargo(trackingId: $id) {
    trackingId
    itinerary { legs { unloadLocation { name } } }
  }
}
```

The response holds `data.cargo.trackingId` as `JKL012`, a null `itinerary` and one error whose path is `["cargo","itinerary","legs",1,"unloadLocation"]`. The path names the field that failed: the second leg's `unloadLocation`. The schema says that field is `Location!`, so the null couldn't stay there and moved up to the nearest nullable ancestor, `itinerary`. The first leg is gone with the rest of the itinerary even though its own locations resolved.

The path is where the error was raised, not where the null landed. A reader who looks at the null `itinerary` and then at the itinerary resolver is looking one level too high. Read the path before reading any code.

Only an execution error has a path, so first decide which kind of error the response holds:

| Error | Has `path` | `data` | What it means |
|---|---|---|---|
| Request error (parse, validation, variable coercion) | no, only `locations` | absent on Quarkus, null on Python | Nothing executed and no source was called. The fix is in the document or the client. |
| Execution error | yes | whatever the rest of the operation produced | A resolver or the engine failed. Continue below. |

The message is each stack's to word. Quarkus answers with the engine's explanation that the field "was declared as a non null type" and returned null, with the path in the text. Python answers `Internal server error.`, because the null is an engine error raised inside a resolver and error masking hides every execution error that isn't an exposed one. Both leave the cause out: the response says which field failed, not why `XXBAD` is unknown.

## When the response says only "Internal server error."

F2 asks for the delivery state of the same cargo:

```graphql
query DeliveryOfJkl($id: TrackingId!) {
  cargo(trackingId: $id) {
    trackingId
    delivery { transportStatus }
  }
}
```

`Cargo.delivery` is `Delivery!`, so a failure inside it nulls the whole `cargo`. The error has the path `["cargo","delivery"]`, the message `Internal server error.` and nothing else of use. That is masking doing its job: an exception's class name, message and stack can teach a caller about the internals.

An operator still has to find the exception, and the client's report has to carry something that leads to it. That is the trace id. Every execution error carries `extensions.traceId`: the id the caller sent in `traceparent`, or a new one when it sent none. A masked error keeps nothing else. On Quarkus its extensions are `code` (null for an unclassified failure) and `traceId`; on Python, `traceId` alone. The id isn't a secret. Reading the trace takes access to the observability backend, so quoting the id discloses nothing, and it is what a support ticket should carry.

Each stack adds the key through the seam it provides:

{% include codetabs.html langs="Quarkus|Python" %}

```java
public class TraceIdExtensionProvider implements ErrorExtensionProvider {
    @Override
    public String getKey() {
        return "traceId";
    }

    @Override
    public JsonValue mapValueFrom(Throwable exception) {
        SpanContext context = Span.current().getSpanContext();
        return context.isValid() ? Json.createValue(context.getTraceId()) : null;
    }
}
```

```python
class TraceIdExtension(SchemaExtension):
    """Adds ``extensions.traceId`` to every execution error of the response.

    The id is the trace id of the request: the span the FastAPI instrumentation
    opened, joined to the caller's trace when the request carried a
    ``traceparent``. ``on_operation`` is the hook that wraps the whole
    operation, and the schema lists this extension before ``MaskErrors``:
    extensions leave in reverse order, so this exit runs after the masking has
    rebuilt the masked errors, and a masked error ends with ``traceId`` as its
    only extension. The id is not a secret; reading the trace takes access to
    the observability backend. A request error (parse, validation), which has no
    path, is left as the engine wrote it.
    """

    def on_operation(self) -> Generator[None]:
        yield
        errors = getattr(self.execution_context.result, "errors", None)
        context = trace.get_current_span().get_span_context()
        if not errors or not context.is_valid:
            return
        trace_id = trace.format_trace_id(context.trace_id)
        for error in errors:
            if error.path:
                error.extensions = {**(error.extensions or {}), "traceId": trace_id}
```

SmallRye asks each registered `ErrorExtensionProvider` for its value when it serializes an error, and `quarkus.smallrye-graphql.error-extension-fields=code,traceId` names the keys that reach the response. The provider is listed in the `ServiceLoader` file beside the one that writes `code`. A graphql-java instrumentation adds the same key to the errors the engine raises itself, such as F1's null.

Strawberry's `on_operation` hook wraps the whole operation, and extensions leave in reverse list order. The schema lists `TraceIdExtension` before `MaskErrors`, so its exit runs after masking has rebuilt each masked error, and the key survives. Request errors have no path and are left as the engine wrote them.

## From the trace id to the cause

The response gives an id; the id opens the trace, the log record and finally the data. The figure follows F2 on the Python stack.

{% include excalidraw.html file="24-diagnosis-path" alt="Six boxes on a path. Box one, the response, shows data.cargo null, the path cargo and delivery, the message Internal server error and extensions.traceId. An amber arrow labelled id leads to box two, the trace in Tempo, which lists the operation span GraphQL Query DeliveryOfJkl and the resolver span GraphQL Resolving delivery with status ERROR and an exception KeyError. An amber arrow labelled same id leads to box three, the record in Loki, with the same trace_id, exception_type KeyError and exception_message XXBAD. An amber arrow labelled XXBAD leads to box four, the data, which shows event evt_10 unloading at XXBAD, leg two ending at XXBAD and no XXBAD in the location source. Below, an arrow from the data leads to box five, the fix, which is either adding XXBAD to the location owner or treating an unknown location as null in the derivation, and then to a dark box six, a regression test. A note says the client sees only step one." caption="Figure 24.1: One masked error, followed to the data. The trace id in the response is the key to the trace, to the log record and to the event that names the unknown location." %}

Tempo answers a trace by id. The operation span `GraphQL Query: DeliveryOfJkl` (Quarkus names it `query DeliveryOfJkl`) is the root, and below it one resolver span, `delivery`, ends in status `ERROR` with an exception event carrying the type and message. Quarkus marks the operation span `ERROR` too and Python leaves it `UNSET`; the resolver span is `ERROR` on both, so look there.

Loki holds the record the server wrote when the exception passed through the engine, with the trace id as structured metadata:

```text
{service_name="ch24-debugging-python"} | trace_id="<the id from the response>" | exception_type="KeyError"
```

`exception_type` is `KeyError` on Python and `java.util.NoSuchElementException` on Quarkus, and `exception_message` holds `XXBAD` on one and `no location XXBAD` on the other. The derivation looks up the location of the cargo's last handling event, and the lookup failed on a code it was never given.

Now the data can be read with a question instead of a guess. The handling event `evt_10` records an `UNLOAD` of `JKL012` at `XXBAD`, and the second leg ends there. F1 failed for the same reason at a different field: the location source answers `null` for `XXBAD`, and `Leg.unloadLocation` promises a value. One missing reference explains both failures.

There are two repairs. The location owner adds `XXBAD`, which fixes the data. Or the derivation treats an unknown location as `lastKnownLocation: null`, which the schema already allows because that field is nullable, and which turns a masked failure into a degraded answer. The derivation stays unchanged so the fault stays reproducible. Either way the fix isn't finished until a test reproduces `JKL012` and keeps it answered.

## The application's debug category

A trace and a log record say what failed. The next question is what the application looked up on the way. The application has a logger of its own for that, `com.patterncatalyst.shipping.tracking.resolve` on Quarkus and `app.resolve` on Python, at `INFO` by default. At `DEBUG` each reference resolver writes one line when its bulk read returns:

```text
resolve Leg.unloadLocation key=DEHAM outcome=found
resolve Leg.unloadLocation key=XXBAD outcome=missing
```

The line names the field coordinate, the key the resolver asked for and whether the owner had it. For F1 the response names the field and the debug line names the key. It is written after the bulk read returns, so it reports an outcome and not an intention. Quarkus writes one line per distinct key of a batch and Python one per resolver call, so on Python a key shared by several legs appears once per leg; for F1 both write exactly one line for `XXBAD`. The line carries reference keys, a UN/LOCODE or a voyage number, and never a tracking id, a variable value or a token.

{% include codetabs.html langs="Quarkus|Python" %}

```java
static <T> void batch(String coordinate, List<String> keys, List<Outcome<T>> outcomes) {
    if (!LOG.isDebugEnabled()) {
        return;
    }
    Set<String> seen = new HashSet<>();
    for (int i = 0; i < keys.size(); i++) {
        Outcome<T> outcome = outcomes.get(i);
        if (outcome.failure() == null && seen.add(keys.get(i))) {
            LOG.debugf(
                    "resolve %s key=%s outcome=%s", coordinate, keys.get(i), outcome.value() == null ? "missing" : "found");
        }
    }
}
```

```python
def record(coordinate: str, key: str, value: object | None) -> None:
    """One debug line for a reference the resolver looked up."""
    _LOG.debug("resolve %s key=%s outcome=%s", coordinate, key, "missing" if value is None else "found")
```

A debug category is only useful if it can be turned on without a restart, because a restart clears the state a production fault lives in. Both stacks change a level on the running process:

- **Quarkus** uses `quarkus-logging-manager`. `POST /q/logging-manager` with the form fields `loggerName` and `loggerLevel` sets the level, and `GET /q/logging-manager?loggerName=...` reads it back.
- **Python** uses the standard library's `Logger.setLevel` behind a route with the same fields, `POST /debug/loggers` and `GET /debug/loggers?loggerName=...`.

Both answer `201` to a change and `{"name": ..., "effectiveLevel": ...}` to a read. Both are served only when `TRACKING_DEBUG_ENDPOINTS=true`: a route that changes log levels is an administrative surface, and an instance that serves the public doesn't carry it. The compose file sets it on all four instances so `verify.sh` can drive the switch; with it unset both routes answer `404`. On Quarkus `quarkus.logging-manager.enable` takes its value from the same setting.

The working loop is: read the level, raise it, reproduce the failure once, read the lines, lower it again. The debug lines are log records like the exception record, so they reach Loki with the request's trace id and a query by id shows the lines of one request and no other. The Quarkus console format carries the id as well (`traceId=%X{traceId}`), so a terminal line can be matched to a response.

## Development surfaces

Quarkus dev mode, started with `mvn quarkus:dev`, recompiles on a change and serves the Dev UI at `/q/dev-ui` (extensions, configuration, endpoints) and the GraphQL UI at `/q/graphql-ui`, a GraphiQL page wired to the schema. The dev profile also sets `quarkus.smallrye-graphql.log-payload=queryOnly`, which writes each document into the log:

```text
Payload In [query LegsOfJkl($id: TrackingId!) { cargo(trackingId: $id) { trackingId itinerary { legs { unloadLocation { name } } } } }]
```

Strawberry serves GraphiQL on the GraphQL path itself. `GraphQLRouter` takes `graphql_ide`, and it is set from a `TRACKING_PROFILE` setting:

```python
app.include_router(
    GraphQLRouter(
        schema,
        context_getter=get_context,
        graphql_ide="graphiql" if settings.profile == "dev" else None,
    ),
    prefix="/graphql",
)
```

A production build carries none of this. The GraphQL UI and the Dev UI belong to dev and test mode, and the Python production instance sets `graphql_ide=None`.

{% include excalidraw.html file="24-dev-vs-prod-surfaces" alt="Two columns of boxes, a development instance on the left with quarkus-dev on port 8342 and python-dev on 8343, and a production instance on the right with quarkus on 8340 and python on 8341. Three rows have amber boxes on the left and dashed boxes on the right: the GraphQL IDE, which is slash q slash graphql-ui on Quarkus and GraphiQL on slash graphql on Python and is 404 in production; the Dev UI, which is slash q slash dev-ui and is 404 in production; and payload logging, which writes each document in the development log and is off in production. Four rows have white boxes on both sides: the lab level switch, masked errors, extensions.traceId on every execution error, and traces and logs exported over OTLP to lgtm." caption="Figure 24.2: The development surfaces live on the development instances. Masking, the trace id and telemetry are the same in both profiles." %}

The profiles differ in what they offer a developer and not in what they promise a client. Masking and `extensions.traceId` are identical and both export to the same backend, because a development instance that is easier to read than production in any way a client could depend on is a second system to debug. Paste F1 into the GraphQL UI on port 8342 or GraphiQL on port 8343 and the response has the same path and nulls as production; the development log adds the document as received, and dev mode applies a code fix on the next request.

Dev mode in a container needs three settings. Dev Services start backing containers for extensions that have one, here an LGTM stack for OpenTelemetry. This instance exports to the compose `lgtm` service instead, so the dev profile sets `%dev.quarkus.devservices.enabled=false`. The `dev` target of the Containerfile also passes `-Dquarkus.console.enabled=false`, since the container has no terminal, and `-Ddebug=false`, since no debugger port is published.

A debugger answers why a value was what it was, by stopping at the line. Quarkus dev mode opens a JDWP port (5005 by default) on the machine where it runs, and a Python service runs under `debugpy` or an IDE configuration the same way, on a developer's machine and never on a shared instance. Stopping a request stops its sources and timeouts, and a fault that depends on timing, such as a batch window, can disappear under a debugger. Observe first and use the debugger for the one value observation couldn't explain.

## Reading a trace for fan-out

Tracing is read for time elsewhere; debugging reads it for count. The `FanOut` query pages four cargos with itineraries and delivery. On Quarkus its trace holds eight `source.call` spans, two of them `getLocations`; on Python six, one of them `getLocations`. Eight location resolver spans share those calls. The number of `getLocations` spans equals the number of location calls in the source-call log for the same request.

That agreement is a diagnostic. An N+1 is a call per parent where the batch should have made one, and in a trace it is a row of `source.call` spans with the same operation at the same level, one beside every resolver span that triggered it. A deployed service has no source-call log, so the trace is the only place the count is visible. Across a gateway the same method reads the query plan: pick the trace by id and count the requests each subgraph received for one operation.

## A checklist

1. **The response.** Does the error have a path? Without one the request was rejected before execution and the fix is in the client.
2. **The path and the code.** Which field failed, which nullable ancestor became null, and is the code one the service declared?
3. **The trace id.** Take `extensions.traceId`, or the `traceparent` the client sent.
4. **The trace.** Find the resolver span in `ERROR` and read the exception type and the source calls under it.
5. **The log.** Query Loki by the same id for the exception message.
6. **The data or the code.** Turn the debug category on, reproduce once, read the keys, and turn it off.
7. **The test.** Reproduce the fault in a development instance, fix it, and keep a test that fails without the fix.

> **🤖 Explore with your agent**
>
> "In `examples/24-debugging`, the query `DeliveryOfJkl` for `JKL012` returns `Internal server error.` Starting only from `extensions.traceId` in that response, find the `delivery` span in Tempo and the `KeyError` record for `XXBAD` in Loki, then change the derivation so an unknown location gives `lastKnownLocation: null`, and write the regression test that fails without your change."
>
> Check: send `DeliveryOfJkl` to `localhost:8341/graphql` again; the reply has `data.cargo.delivery` and no `errors`, and the new test fails when you revert the derivation.

## Build, run, observe

Production Quarkus is on `8340`, production Python on `8341`, their development instances on `8342` and `8343`, and Grafana, Tempo, Prometheus and Loki on `8344` to `8347`.

```bash
docker compose -f examples/24-debugging/compose.yaml up -d --build
curl -s localhost:8341/graphql -H 'Content-Type: application/json' \
  -d '{"query":"query LegsOfJkl($id: TrackingId!) { cargo(trackingId: $id) { trackingId itinerary { legs { unloadLocation { name } } } } }","variables":{"id":"JKL012"}}'
```

```json
{"data":{"cargo":{"trackingId":"JKL012","itinerary":null}},"errors":[{"message":"Internal server error.","locations":[{"line":1,"column":92}],"path":["cargo","itinerary","legs",1,"unloadLocation"],"extensions":{"traceId":"9d22ab8bbd0fb356a9ae5598548455d9"}}]}
```

Send F2 under a trace id of your own, then read the response and the trace:

```bash
TID=$(python3 -I -c 'import secrets; print(secrets.token_hex(16))')
curl -s localhost:8341/graphql -H 'Content-Type: application/json' \
  -H "traceparent: 00-$TID-00f067aa0ba902b7-01" \
  -d '{"query":"query DeliveryOfJkl($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }","variables":{"id":"JKL012"}}'
```

```json
{"data":{"cargo":null},"errors":[{"message":"Internal server error.","locations":[{"line":1,"column":77}],"path":["cargo","delivery"],"extensions":{"traceId":"156c5bf9e9cc30502aad07ac2cec876b"}}]}
```

The `traceId` equals `$TID`. Ask Tempo for the spans that ended in an error, and Loki for the exception record:

```bash
curl -s localhost:8345/api/traces/$TID | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print([s["name"] for b in d["batches"] for ss in b["scopeSpans"] for s in ss["spans"] if s.get("status",{}).get("code")=="STATUS_CODE_ERROR"])'
curl -sG localhost:8347/loki/api/v1/query_range --data-urlencode "query={service_name=\"ch24-debugging-python\"} | trace_id=\"$TID\"" | python3 -I -c 'import json,sys; s=json.load(sys.stdin)["data"]["result"][0]["stream"]; print(s["exception_type"], s["exception_message"])'
```

```text
['GraphQL Resolving: delivery']
KeyError XXBAD
```

Switch the debug category on, repeat F1 and read the lines, then switch it off:

```bash
curl -s -X POST localhost:8341/debug/loggers -d loggerName=app.resolve -d loggerLevel=DEBUG
curl -s 'localhost:8341/debug/loggers?loggerName=app.resolve'
docker compose -f examples/24-debugging/compose.yaml logs --no-color python | grep 'resolve Leg'
curl -s -X POST localhost:8341/debug/loggers -d loggerName=app.resolve -d loggerLevel=INFO
```

```text
{"name":"app.resolve","effectiveLevel":"DEBUG","configuredLevel":"DEBUG"}
ch24-debugging-python  | 2026-10-17 03:39:25,748 DEBUG app.resolve: resolve Leg.unloadLocation key=DEHAM outcome=found
ch24-debugging-python  | 2026-10-17 03:39:25,748 DEBUG app.resolve: resolve Leg.unloadLocation key=XXBAD outcome=missing
```

On Quarkus the switch is `POST localhost:8340/q/logging-manager` with `loggerName=com.patterncatalyst.shipping.tracking.resolve`. Check the development surfaces on both profiles:

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost:8342/q/graphql-ui/
curl -s -o /dev/null -w '%{http_code}\n' localhost:8340/q/graphql-ui/
curl -s -o /dev/null -w '%{http_code}\n' -H 'Accept: text/html' localhost:8343/graphql
curl -s -o /dev/null -w '%{http_code}\n' -H 'Accept: text/html' localhost:8341/graphql
```

```text
200
404
200
404
```

Stop the stack when done:

```bash
docker compose -f examples/24-debugging/compose.yaml down -v
```

`bash examples/24-debugging/verify.sh` runs the sequence on both stacks and prints `PASS` only when both hold. It asserts the values in this table.

| Check | Quarkus | Python |
|---|---|---|
| `TrackCargo` for ABC123 | `ONBOARD_CARRIER`, no errors, no `extensions` | the same |
| `FanOut` | 8 calls, 2 `getLocations` spans | 6 calls, 1 `getLocations` span |
| F1 path and nulls | `["cargo","itinerary","legs",1,"unloadLocation"]`, `itinerary` null | the same |
| F1 message | the engine's "declared as a non null type" text | `Internal server error.` |
| F1 source calls | `location.getLocations` with key `DEHAM+XXBAD` | the same |
| F2 response | `data.cargo` null, path `["cargo","delivery"]`, `Internal server error.` | the same |
| F2 extensions | `code` null and `traceId` | `traceId` only |
| `traceId` | equals the `traceparent` sent; 32 hex characters when none was sent, and the trace is found by it | the same |
| F2 trace | `query DeliveryOfJkl` and a `delivery` span in `ERROR` below it | `GraphQL Query: DeliveryOfJkl` and a `GraphQL Resolving: delivery` span in `ERROR` |
| F2 log record | `NoSuchElementException`, message contains `XXBAD` | `KeyError`, message contains `XXBAD` |
| response body | no `XXBAD`, no exception type, no stack frame | the same |
| debug category | INFO, DEBUG, INFO; one `key=XXBAD outcome=missing` line for the F1 request | the same |
| GraphQL UI, Dev UI | development 200, production 404 | GraphiQL: development 200, production 404 |
| payload logging | development log holds the document; production holds none | not applicable |
| schema | conforms; only `Subscription` unserved | the same |

Experiments:

- Set `TRACKING_DEBUG_ENDPOINTS` off on an instance: `/q/logging-manager` and `/debug/loggers` answer `404`.
- Send F2 without a `traceparent`: `traceId` is a fresh 32-character hex id, and the trace is still found by it.
- Query the production instance's GraphQL UI path: it answers `404`, where the development instance answers `200`.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Masking keeps the cause out of the response, so the service must supply a path back to it: read the error path first because every client can, put the trace id in every execution error because a client can quote it, find the trace and the log record by that id, and count source calls per request in the trace when the cause is data owned by another service. Switch debug categories at run time, keep the IDE and Dev UI on development instances, and turn each fault into a test.</p></div>

## For deeper coverage

- *Cloud Native Design Patterns*, "Observability": the OTel-plus-LGTM correlation the trace-id path builds on.
- [W3C Trace Context](https://www.w3.org/TR/trace-context/): the `traceparent` header read and quoted back.
- [Quarkus Dev UI](https://quarkus.io/guides/dev-ui): the development surface kept off production instances.
- [Grafana Tempo documentation](https://grafana.com/docs/tempo/latest/): finding a trace by id and reading its spans.
- [Grafana Loki documentation](https://grafana.com/docs/loki/latest/): querying a log record by `trace_id`.
- The GraphQL specification's "Handling Field Errors" and "Errors" sections, and the Quarkus "SmallRye GraphQL", "Configuring logging" and Logging Manager guides, cover the mechanisms used here.
