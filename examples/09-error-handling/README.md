# Ch9 - Error handling

What a failure looks like on the wire, and what a client is allowed to see of it. The example adds
three fault seeds to the tracking view and gives both stacks the same error contract: an outage is
an **exposed** error with a stable `extensions.code`, any other failure is **masked** as
`Internal server error.` while the detail stays in the server log. `verify.sh` asserts the
response of each case on both stacks, reads each stack's log for the detail the client never gets,
records the HTTP status and media type of request and execution errors, and diffs each schema
against the canonical SDL.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves exactly what
Chapter 8 served: no type, field or argument changes. It serves `Itinerary.finalArrivalDate` without a deprecation and has no `finalArrivalTime` or `Query.nodes`; that is
the contract as it stood before those additions, which is why the conformance check still passes
(it compares what a stack serves, not deprecation state).

What changes is the data and the error behaviour. Three cargos are added to the seed, all with no
handling events:

| Cargo | Itinerary | Fault |
|---|---|---|
| `JKL567` Machine parts | one leg, `V404X`, `USNYC` to `NLRTM` | the voyage source fails for `V404X` with the **exposed** `SourceUnavailable("voyage service unavailable")`, code `SERVICE_UNAVAILABLE` |
| `MNO901` Textiles | one leg, `V100S`, loads at `XXBAD` | the location source answers null for `XXBAD`, where `Leg.loadLocation` is non-null |
| `PQR234` Coffee beans | as `ABC123` | `handling.listEvents("PQR234")` raises an **unexpected** error: `IllegalStateException` on Quarkus, `RuntimeError` on Python, message `handling projection corrupted on shard handling-primary-3` |

| Source | Operation | Fails for |
|---|---|---|
| voyage | `getVoyage(number)` | `V404X`, exposed |
| handling | `listEvents(trackingId)` | `PQR234`, unexpected |
| booking, routing, location | as in Chapter 8 | nothing |

### The error contract

| `extensions.code` | Raised for | Message | Shown to the client |
|---|---|---|---|
| `SERVICE_UNAVAILABLE` | a source outage (`V404X`) | `voyage service unavailable` | yes |
| none | anything unexpected | `Internal server error.` | masked; detail only in the server log |

Request errors (parse, validation, coercion) keep each engine's own message and get no code.

Masking is an allowlist on both stacks:

- **Quarkus.** `SourceUnavailableException` is annotated `@ErrorCode("SERVICE_UNAVAILABLE")` and
  listed in `quarkus.smallrye-graphql.show-runtime-exception-message`. SmallRye hides the message of
  every other unchecked exception and answers `default-error-message`.
- **Python.** `app/errors.py` defines `ExposedError` (a `code` class attribute, and
  `extensions = {"code": code}`) and `SourceUnavailable`. Strawberry's `MaskErrors` extension masks
  every error whose `should_mask` predicate is true, and `should_mask` is true for any resolver error
  that is not an `ExposedError`. Nothing in the example catches an exception to rewrite it.

## Run it

```bash
bash examples/09-error-handling/verify.sh
```

`verify.sh` brings both services up with `docker compose`, runs the cases below in a fixed order,
reads the log of each service, diffs each live schema against `contracts/schema/` and tears the
stack down. It prints `PASS` only if every check holds on **both** stacks. It needs Docker Engine
with the `docker compose` plugin and Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/09-error-handling/compose.yaml up -d --build
curl -s localhost:8190/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"PQR234\") { trackingId delivery { transportStatus } } }"}'
docker compose -f examples/09-error-handling/compose.yaml logs quarkus | grep handling-primary-3
docker compose -f examples/09-error-handling/compose.yaml down -v
```

Use port `8191` and the service `python` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8190`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8191`. Set
`TRACKING_SOURCE_LATENCY_MS=250 TRACKING_DEBUG_ENDPOINTS=true` for the behaviour compose gives;
both default to off.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the
log and answers `204`. Each entry has `request`, `source`, `op`, `key`, `startMs` and `endMs`
(monotonic milliseconds). The endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets
it) and sit beside `/graphql`, so the GraphQL schema is the same with them on or off. A failing call
is logged like any other. This chapter uses the log for one claim: a request error calls no source.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8190 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8191 | `/graphql` (health at `/health`) |

Compose project `gql-ch09-errors`, containers `ch09-errors-*`. Telemetry is off by default. Add the
observability file (`docker compose -f compose.yaml -f compose.observability.yaml up --build`) to
send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so run
one example's observability stack at a time.

## On the wire

Each value below is asserted by `verify.sh` on both stacks unless a stack is named.

| Case | Request | Response |
|---|---|---|
| exposed error | `JKL567` itinerary legs, `loadLocation` and `voyage` | one error, path `["cargo","itinerary","legs",0,"voyage"]`, message `voyage service unavailable`, `extensions.code` `"SERVICE_UNAVAILABLE"`, with `locations`; `voyage` null, `loadLocation` `USNYC` |
| masked error | `PQR234` `cargo { trackingId delivery { transportStatus } }` | `data.cargo` null; one error, path `["cargo","delivery"]`, message `Internal server error.`; the body has none of `handling-primary-3`, `IllegalStateException`, `RuntimeError`, `com.patterncatalyst`; the log has `handling-primary-3` |
| masked error, code | same | Quarkus `extensions.code` is JSON `null` ; Python has no `extensions` key |
| partial data | aliases `ok` (`ABC123`), `outage` (`JKL567`), `bug` (`PQR234`) | two errors, paths `["outage","itinerary","legs",0,"voyage"]` and `["bug","delivery"]`; `data.ok.trackingId` `ABC123`; `data.bug` null; `data` keys `ok,outage,bug` |
| null in non-null | `MNO901` itinerary legs `loadLocation` | `data.cargo.itinerary` null; one error, path `["cargo","itinerary","legs",0,"loadLocation"]`; Quarkus message contains `loadLocation`, no `locations`, `extensions.classification` `"NullValueInNonNullableField"`; Python message `Internal server error.` |
| request error | `{ cargo(trackingId:"ABC123"){ weight } }` | errors with `message` and `locations`, no `path`, no `data` (Python sends `"data":null`); no source call |
| `Accept: application/json` | request error and execution error | `200 application/json` on both stacks. The GraphQL-over-HTTP working draft asks for a 4xx on the request error; 294 is recommended only with `application/graphql-response+json` |
| `Accept: application/graphql-response+json` | request error and execution error | Quarkus `200 application/graphql-response+json`, Python `200 application/json`; the draft asks for the same 4xx and recommends 294 with this media type |
| errors as data | `registerHandlingEvent` LOAD at `DEHAM` on `V999X` | no `errors`; `userErrors` `[{"code":"UNKNOWN_VOYAGE","field":["input","voyageNumber"]}]`; `handlingEvent` null; no `appendEvent` call |
| siblings | `a: voyage("V404X")`, `b: voyage("V100S")` | one error, path `["a"]`, code `SERVICE_UNAVAILABLE`; `data.a` null; `data.b.number` `V100S` |
| scalars, SDL | `TrackingId`, `UnLocode`, `DateTime`; the live schema | `SCALAR`, `specifiedByURL` as in Chapter 8; conforms to `contracts/schema/` |

## Code-first notes

The example runs on the pinned versions (SmallRye GraphQL 2.18.5 on Quarkus 3.40.1,
Strawberry 0.335.0 on graphql-core 3.3.0).

**Error codes on Quarkus.** `extensions.code` comes from `@ErrorCode` alone, with no masking
layer. `DeclaredErrorCodeProvider` implements SmallRye's `ErrorExtensionProvider` SPI, registered
through `META-INF/services` (ServiceLoader), and answers the `@ErrorCode` value or JSON `null`.
Quarkus `quarkus.class-loading.removed-resources` drops the service file of
`io.smallrye:smallrye-graphql` that lists the built-in providers, so the new provider is the only
source of `extensions.code`. The masked error on Quarkus reads `"code": null`, where Python sends no
`extensions`; the exposed error keeps `"SERVICE_UNAVAILABLE"`. `verify.sh` asserts both. The removed
file also listed `ExceptionNameErrorExtensionProvider`, so there is no `exception` field either;
`DeclaredErrorCodeProvider` is the only provider left.

**Extension fields on Quarkus.** With `error-extension-fields=code` an exposed or masked fetch
error carries only `code`. The Quarkus request (validation) error carries `extensions.queryPath`,
and graphql-java's own null-in-non-null error keeps its
`"classification":"NullValueInNonNullableField"`; neither is built by SmallRye's mapper.

**Server logs.** The `strawberry.execution` logger writes `ERROR strawberry.execution: handling
projection corrupted on shard handling-primary-3` with the traceback before the masked error is
built, so no `process_errors` override is needed. On Quarkus, `print-data-fetcher-exception=true`
logs `SRGQL012000: Data Fetching Error: java.lang.IllegalStateException: handling projection
corrupted on shard handling-primary-3`, so no `@ErrorDataFetch` observer is included.

**The null in a non-null field.** On Python the `TypeError` of a null `loadLocation` is
the `original_error`, `should_mask` is true for it, and the client reads `Internal server error.`.
On Quarkus the error is graphql-java's `NonNullableFieldWasNullError`, not a fetch exception, so it
is shown: the message names the field and the path, it carries no `locations`, and its
extension is the `classification` above. Both stacks null `itinerary`. `verify.sh` takes the
expected message per stack.

**Quarkus.**

- `SourceUnavailableException extends RuntimeException` with `@ErrorCode("SERVICE_UNAVAILABLE")`, and
  `quarkus.smallrye-graphql.show-runtime-exception-message` listing its class. The message of every
  other unchecked exception is replaced by `quarkus.smallrye-graphql.default-error-message`.
- `VoyageSource` and `HandlingSource` throw inside the `SourceCalls.call` lookup, so the failing call
  is still logged. A thrown failure is not delayed by the 250 ms latency.
- `SourceCalls.afterLatency` skips the delay when the latency is zero.
- `DeclaredErrorCodeProvider`, its `META-INF/services` file and the `removed-resources` line in
  `application.properties` make `extensions.code` come from `@ErrorCode` alone.
- Status and media type: Quarkus answers `200` under both `Accept` headers and echoes
  `application/graphql-response+json` when asked. The current GraphQL-over-HTTP working draft
  recommends a `4xx` or `5xx` for a request error, and the same under `application/json`; both stacks answer `200`, so a client reads the body.

**Python.**

- `app/errors.py` holds `ExposedError`, `SourceUnavailable` and `should_mask`. `ExposedError.extensions`
  is a dict, which graphql-core copies onto the `GraphQLError` it builds.
- `strawberry.Schema(..., extensions=[MaskErrors(should_mask_error=should_mask,
  error_message="Internal server error.")])`. `MaskErrors` rebuilds the masked error without
  `extensions`, so a masked error carries no code.
- Raise an `ExposedError` subclass for an error clients may read. A `GraphQLError` raised directly
  becomes the `original_error` of the located error and is masked.
- Status and media type: Strawberry answers `200 application/json` whatever the `Accept` header
  asks for. The current working draft recommends a `4xx` or `5xx` for a request error and the same
  under `application/json`; the example answers `200` and a client reads the body. Neither stack sends
  the draft's recommended `294` for data beside errors.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/09-error-handling-architecture.py`) show the compose topology: a client
sending queries to each stack, both stacks diffed against the canonical SDL, and the opt-in `compose.observability.yaml` override.
