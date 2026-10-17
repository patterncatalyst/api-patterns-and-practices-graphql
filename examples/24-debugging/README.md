# Ch24 - Debugging GraphQL

One seeded data fault, diagnosed from the response to its cause. Cargo `JKL012` is routed to `XXBAD`, a
location code the location service does not hold, and two ordinary queries show it. `verify.sh` reads
each error from the response, follows the trace id in it to Tempo and Loki, switches an application debug
category on and off at run time, and checks which development surfaces each instance serves. The schema,
the sources and the telemetry are Chapter 19's; what is new is the fault, the trace id in every execution
error, the debug category and a development instance beside each production instance.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything in it except
`Subscription`, which Chapter 21 builds. `extensions.traceId` is a response extension and not part of the
schema, and `assert_sdl_conforms` proves the schema is unchanged. The seed adds one cargo and one handling
event and nothing else.

### The seeded fault

| Part | Value |
|---|---|
| booking | `JKL012`, "Machine parts", origin `NLRTM`, destination `USNYC`, booked before every other cargo, so `cargos(first: 4)` and `FanOut` answer as in Chapter 19 and the index now holds seven cargos |
| routing | two legs: `NLRTM` to `DEHAM` on `V100S`, then `DEHAM` to `XXBAD` on `V200E` |
| handling | `evt_10`, an `UNLOAD` at `XXBAD` on `V200E` |
| location | the five codes of the seed; `XXBAD` is well formed and unknown |

Two documents reach it:

| Name | Document | Result |
|---|---|---|
| F1 | `cargo { itinerary { legs { unloadLocation { name } } } }` | `itinerary` is null; one error at `["cargo","itinerary","legs",1,"unloadLocation"]` |
| F2 | `cargo { delivery { transportStatus } }` | `cargo` is null; one error at `["cargo","delivery"]`, `Internal server error.` |

The derivation is the application's own code and the example leaves it unchanged. The fix is either the
location owner adding `XXBAD`, or the derivation treating an unknown location as `lastKnownLocation: null`.

## Run it

```bash
bash examples/24-debugging/verify.sh
```

`verify.sh` brings the stack up with `docker compose`, runs the cases below in a fixed order on both
stacks, diffs each production schema against `contracts/schema/` and tears the stack down. It prints
`PASS` only if every check holds on both stacks. It needs Docker Engine with the `docker compose` plugin
and Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/24-debugging/compose.yaml up -d --build
open http://localhost:8344    # Grafana; Explore has Tempo, Prometheus and Loki data sources
docker compose -f examples/24-debugging/compose.yaml down -v
```

The apps start after `lgtm` is healthy. The Quarkus development instance compiles from sources, so it
needs up to two minutes to become ready.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the log and
answers `204`, as in Chapter 13. The endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose
sets it).

## Ports

| Instance or service | Container | Host | Endpoint |
|---|---|---|---|
| `quarkus` (production) | 8080 | 8340 | `/graphql` (health at `/q/health`) |
| `python` (production) | 8080 | 8341 | `/graphql` (health at `/health`) |
| `quarkus-dev` (development) | 8080 | 8342 | `/graphql`, `/q/graphql-ui`, `/q/dev-ui` |
| `python-dev` (development) | 8080 | 8343 | `/graphql`, GraphiQL on the same path |
| Grafana | 3000 | 8344 | UI, anonymous Admin (lab only) |
| Tempo | 3200 | 8345 | `/api/traces/<trace id>` |
| Prometheus | 9090 | 8346 | `/api/v1/query` |
| Loki | 3100 | 8347 | `/loki/api/v1/query_range` |

Compose project `gql-ch24-debugging`, containers `ch24-debugging-*`. The collector's OTLP ports (4317,
4318) stay inside the compose network. The chapter departs from "Quarkus +0, Python +1" only for the
development instances and the observability stores.

## Dev and production instances

| | Development | Production |
|---|---|---|
| Quarkus | the `dev` target of `quarkus/Containerfile`: `mvn quarkus:dev` from the sources | the fast-jar runtime image |
| Python | the production image with `TRACKING_PROFILE=dev`: `graphql_ide="graphiql"` | the same image with `TRACKING_PROFILE=prod`: `graphql_ide=None` |
| GraphQL UI / GraphiQL | `/q/graphql-ui/` answers `200`; GraphiQL on `/graphql` for `Accept: text/html` answers `200` | `404` on both |
| Dev UI | `/q/dev-ui/` answers `200` | `404` |
| Payload logging | `%dev.quarkus.smallrye-graphql.log-payload=queryOnly`: each document is in the log | off |
| Masking, `extensions.traceId`, telemetry | as production | as the development instance |

The Python development instance runs the production image, so the only difference is the profile
setting. The Quarkus development instance sets `OTEL_EXPORTER_OTLP_ENDPOINT` and its service name through
the environment, and the dev profile disables dev services (`%dev.quarkus.devservices.enabled=false`):
the compose network already supplies the collector. The container starts dev mode with
`-Dquarkus.console.enabled=false` (no terminal), `-Ddebug=false` (no debugger port is published),
`-Dquarkus.test.continuous-testing=disabled` and `-Dquarkus.analytics.disabled=true`.

## On the wire

Each value below is asserted by `verify.sh`.

| Case | Quarkus | Python |
|---|---|---|
| `TrackCargo` for ABC123 | `ONBOARD_CARRIER`; no `errors`, no `extensions` | the same |
| `cargos(first: 1) { totalCount }` | 7 | 7 |
| `FanOut` | Chapter 19's data; 8 source calls; 2 `getLocations` spans | the same data; 6 calls; 1 `getLocations` span; 8 location resolver spans on both |
| F1 | `itinerary` null; one error at the path above; the message contains `declared as a non null type`; no `XXBAD` in the body | the same path; message `Internal server error.` |
| F1 source calls | `booking.getCargo:JKL012`, `routing.getItineraries:JKL012`, `location.getLocations:DEHAM+XXBAD` | the same |
| F1 trace | one `query LegsOfJkl`, two `unloadLocation` spans | one `GraphQL Query: LegsOfJkl`, two `GraphQL Resolving: unloadLocation` spans |
| F2 | `cargo` null; one error at `["cargo","delivery"]`; `Internal server error.`; extensions `code` null and `traceId` | the same with `traceId` as the only extension |
| `traceId` | equals the `traceparent` sent; without one, 32 lowercase hex characters, and Tempo finds the trace by it | the same |
| F2 trace | `query DeliveryOfJkl`; the `delivery` span descends from it and ends in `ERROR` | `GraphQL Query: DeliveryOfJkl`; `GraphQL Resolving: delivery` ends in `ERROR` |
| F2 log record | `{service_name="ch24-debugging-quarkus"} \| trace_id="<id>" \| exception_type=~".*NoSuchElementException.*"`, message contains `XXBAD` | `... \| exception_type="KeyError"`, message contains `XXBAD` |
| GHI345 | `SERVICE_UNAVAILABLE` and a `traceId` | the same |
| debug category | INFO, then DEBUG, then INFO; at DEBUG one `resolve Leg.unloadLocation key=XXBAD outcome=missing` line and one `key=DEHAM outcome=found` line for the F1 request, found in Loki by its trace id and in the log | the same |
| GraphQL UI, Dev UI | development `200`, production `404` | GraphiQL: development `200`, production `404` |
| payload logging | the development log holds the `LegsOfJkl` document; the production log holds no payload | not applicable |
| development instance | F1 and F2 answer as on production | the same |
| schema | conforms; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

## Code-first notes

The example runs on the pinned versions: Quarkus 3.40.1 with `quarkus-logging-manager` 3.4.2,
`opentelemetry-graphql-java-20.0` 2.28.1-alpha (the version the platform manages), Strawberry 0.335.0,
FastAPI 0.143.2, `python-multipart` 0.0.32 (FastAPI's form parsing for `/debug/loggers`), and
`grafana/otel-lgtm` 0.37.0.

**The trace id on Quarkus.** SmallRye asks each `ErrorExtensionProvider` for a value when it serializes an
error raised by a resolver, so `TraceIdExtensionProvider` is listed in the `ServiceLoader` file beside
`DeclaredErrorCodeProvider`, and `quarkus.smallrye-graphql.error-extension-fields=code,traceId` lets both
keys reach the response. An execution error the engine raises itself, such as a null in a non-null
position, is not a resolver's exception; `TraceIdInstrumentation` adds the key to those errors on the
finished result. Request errors, which have no path, keep the engine's own extensions.

**The trace id on Python.** `TraceIdExtension` uses `on_operation`, which wraps the whole operation.
Extensions exit in reverse order of the schema's list, so it is listed before `MaskErrors`: its exit
runs after the masking, and a masked error ends with `traceId` as its only extension.

**Messages and exceptions per stack.** F1 on Quarkus is the engine's own text for a null in a non-null
field, with the path and without `locations`; on Python it is `Internal server error.`, because Chapter
9's allowlist masks every execution error that is not an exposed one. F2 is masked on both. The exception
behind F2 is `java.util.NoSuchElementException` ("no location XXBAD", from `TrackingData.requireLocation`)
on Quarkus and `KeyError` (`'XXBAD'`, from the locations mapping) on Python.

**Spans.** F2 on Quarkus ends both the `delivery` span and the operation span in `ERROR`; on Python only
the `delivery` span. The resolver span is the place to look on both. The F2 trace has 7 spans on Quarkus
and 12 on Python, F1 has 9 and 14.

**The debug category.** `ResolveLog` (Quarkus) and `app/resolve.py` (Python) write the line after the
bulk read returns. Quarkus writes one line per distinct key of a batch, Python one per resolver call.
The Quarkus console format is `%d{HH:mm:ss.SSS} %-5p traceId=%X{traceId} [%c{3.}] %s%e%n`, so a console
line carries the id of its request. Python's console line has no trace id; its debug lines reach Loki with
`trace_id` as structured metadata, as every record does.

**The level switch.** On Quarkus, `quarkus-logging-manager` 3.4.2 serves `POST /q/logging-manager`
(`loggerName`, `loggerLevel`; answers `201`) and `GET /q/logging-manager?loggerName=...` (answers
`{"name","effectiveLevel"[,"configuredLevel"]}`). `quarkus.logging-manager.enable=${tracking.debug-endpoints:false}`
switches it off unless `TRACKING_DEBUG_ENDPOINTS=true`; off, both answer `404`. On Python, `app/debug.py`
serves the same two routes over `logging.getLogger(name).setLevel(...)`, mounted only with
`TRACKING_DEBUG_ENDPOINTS=true`; an unknown level answers `422`.

**Payload logging.** `quarkus.smallrye-graphql.log-payload` takes `off`, `queryOnly` or
`queryAndVariables`. The example uses `queryOnly` in the dev profile, which logs the document and not the
variables.

**Dev mode in a container.** The Dev UI and the GraphQL UI answer on the published port of the
development instance with no host setting. Dev mode needs no terminal and no debugger port inside the
container (`-Dquarkus.console.enabled=false`, `-Ddebug=false`). `mvn quarkus:go-offline` in the `dev`
target resolves what dev mode needs while the image builds.

**Healthcheck.** The `lgtm` healthcheck is a `curl` against Grafana, Tempo and Loki. The `quarkus-dev` check has `start_period: 120s`.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/24-debugging-architecture.py`) show the compose topology: a client with a
`traceparent` sending F1 and F2 to the four instances, all four exporting OTLP to `lgtm`, and the
production schemas diffed against the canonical SDL.
