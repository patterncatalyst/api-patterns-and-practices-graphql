# examples/_lib - shared verification harness

Every hands-on example's `verify.sh` sources `lib.sh`. The harness brings up the
example's Docker Compose stack, waits for the GraphQL endpoint, sends operations
with `curl`, and asserts **response semantics against the canonical SDL** - not
just an HTTP `200`. GraphQL-over-HTTP answers `200` for `application/json`
responses even when the body holds `errors`, so a `200` proves nothing: a
wrong-shaped or wrong-valued result must fail the check (this is the "On the
wire" box of each chapter, encoded).

## Functions

| Function | Purpose |
|---|---|
| `compose_up <file> <project>` | `docker compose up -d --build`; registers an EXIT trap that tears the stack down automatically and, when the run failed, first prints the last 200 log lines of each service. Then it runs the `on_exit` hooks. |
| `on_exit <command...>` | Register a command to run when the script exits, after the stack teardown. Several calls run in registration order; a failing hook is reported and does not stop the others or change the exit status. Quote the command as one string (`on_exit 'rm -rf "$scratch"'`). Use it instead of a hand-chained trap. |
| `compose_logs <service>` | `docker compose logs --no-color <service>` for the running stack; fails when no stack is up. Lets a chapter assert that detail was kept server-side. |
| `compose_down <file> <project>` | `docker compose down -v --remove-orphans` (called by the trap). |
| `wait_for_graphql <url> [timeout]` | Poll a `{ __typename }` POST until it answers `200` with `data.__typename == "Query"` (default 90s, covers JVM cold start). |
| `gql <url> <query> [variables-json] [operationName]` | POST `{query, variables[, operationName]}` as `application/json`; print the response body; non-zero on any non-200 or after `LGTM_HTTP_TIMEOUT` seconds (default 30). |
| `json_field <dot.path>` | Extract a value from JSON on stdin (numeric indices: `.data.cargo.itinerary.legs.0.loadTime`; JSON null prints `null`). |
| `assert_eq <expected> <actual> <ctx>` / `assert_contains <needle> <hay> <ctx>` | Value assertions. |
| `assert_no_errors <json> [ctx]` / `assert_has_errors <json> [ctx]` | Success path: no top-level `errors` key. Failure path: a non-empty `errors` array. |
| `assert_sdl_equals <url> [ctx]` | The live schema equals the canonical SDL; for the complete schema in the final project. |
| `gql_any <url> <query> [variables-json] [operationName] [accept]` | POST like `gql` but never fails on the status. Line 1 of the output is the HTTP status, the rest is the body. The optional fifth argument sets the `Accept` header (default `application/json`). Non-zero only on a transport failure. |
| `gql_meta <url> <accept> <query> [variables-json]` | POST with that `Accept`; prints one line, `<status> <media-type>` (the response `Content-Type` without parameters). Non-zero only on a transport failure. |
| `gql_get <url> <query> [variables-json]` | GET with URL-encoded `query` and `variables` (`Accept: application/json`). Output as `gql_any`. |
| `status_of <output>` / `body_of <output>` | Split a `gql_any` or `gql_get` result into the status and the body. |
| `assert_status_in <"200 400"> <status> [ctx]` | The status is in the space-separated set. |
| `assert_no_data <json> [ctx]` | `data` is absent or JSON null. |
| `assert_null_at <json> <path> [ctx]` | The path exists and is JSON null. An absent path fails, and the message says absent. |
| `assert_absent <json> <path> [ctx]` | The final key is not present in its parent (null fails; a missing parent fails too, so a mistyped path cannot pass). |
| `assert_error_count <json> <n> [ctx]` | `len(errors) == n`; absent counts as 0. |
| `assert_error_path <json> <path-json-array> [ctx]` | Some `errors[i].path` equals the array exactly; types matter (`0` is not `"0"`). Prints every path on failure. |
| `assert_error_message_contains <json> <needle> [ctx]` | Some error message contains the needle. |
| `assert_error_message_at <json> <path-json-array> <expected> [ctx]` | The error whose `path` equals the array has exactly this message. |
| `assert_error_extension <json> <path-json-array> <key> <expected-json> [ctx]` | That error's `extensions[key]` equals the JSON value; types matter (`1` is not `"1"`). |
| `assert_error_extension_absent <json> <path-json-array> <key> [ctx]` | That error has no `extensions[key]`; an error without `extensions` passes. |
| `assert_error_shape <json> <request\|execution> [ctx]` | At least one error. `request`: every error has a non-empty `message` and `locations` and none has a `path`. `execution`: every error has `message`, `locations` and a non-empty `path`. |
| `assert_body_not_contains <text> <needle> [ctx]` | The needle occurs nowhere in the text; the failure prints its offset. Use it to prove internals never reach a client. |
| `assert_json_eq <expected-json> <actual-json> [ctx]` | Parsed equality: object key order ignored, list order significant, and a boolean never equals a number (`false` is not `0`). |
| `json_len <path>` / `json_keys <path>` | JSON on stdin: the length of a list or object; the keys of an object, comma-joined, in document order. |
| `graphql_base <url>` | The URL without a trailing `/graphql`. |
| `source_calls_reset <graphql-url>` / `source_calls <graphql-url>` | `DELETE` / `GET` `<base>/debug/source-calls` (see below). Reset expects `204`. |
| `assert_source_call_count <calls> <source or *> <op or *> <n> [ctx]` | The number of calls to a source (and operation). `*` for the source matches every source, so `'*' '*' n` is the total. |
| `assert_source_call_keys <calls> <source> <op> <k1,k2,...> [ctx]` | The multiset of `key` values for `source.op` equals the list; order ignored; an empty list means no such calls. |
| `assert_source_calls_exactly <calls> <k1,k2,...> [ctx]` | The multiset of `source.op:key` entries equals the list; order ignored. |
| `assert_calls_ordered <calls> <keyA> <keyB> [ctx]` | Each key matches exactly one call, and A ended before B started. Fails on an empty log and when both keys are the same. |
| `assert_calls_overlap <calls> <keyA> <keyB> [ctx]` | Each key matches exactly one call, and the two were in flight at the same time. Fails on an empty log and when both keys are the same. |
| `assert_single_request <calls> [ctx]` / `assert_distinct_requests <calls> [ctx]` | Every entry shares one non-empty request id / at least two distinct request ids appear. |
| `assert_sdl_conforms <pointer> [ctx]` | The schema behind `<pointer>` agrees with `contracts/schema/**/*.graphql`; passes for a slice of the schema. A pointer is a GraphQL endpoint URL (read by introspection) or an SDL file or glob (a schema a stack exported). |
| `assert_sdl_same <ptrA> <ptrB> [ctx]` | Two schemas are identical: diffs A to B and B to A; no change line remains after `LGTM_SDL_IGNORE` and the `@specifiedBy` filter. |
| `assert_sdl_drift <pointer> <needle> [ctx]` | The negative test of the gate: passes only when `assert_sdl_conforms` fails on the pointer and its change lines contain the needle (the context string is never matched). A comparison that could not run is a failure, not drift. |
| `assert_deprecated <url> <Type> <field> <reason> [ctx]` | One `__type` request with `fields(includeDeprecated: true)`: the field exists, `isDeprecated` is true and `deprecationReason` equals the reason exactly. `assert_sdl_conforms` does not compare deprecation state. |
| `assert_not_deprecated <url> <Type> <field> [ctx]` | The field exists and `isDeprecated` is false. |
| `run_gate <base-dir> <new-dir> [rule,...]` | Run `contracts/scripts/breaking.sh` with `BASE_DIR`, `NEW_DIR` and `BREAKING_RULES`; print the combined output and return the gate's exit code. `GITHUB_ACTIONS` is unset for the run. |
| `assert_gate <expected-rc> <needle> <base-dir> <new-dir> [rules] [ctx]` | `run_gate`, then pass only when the exit code equals the expectation and the needle is in the output (`lib.sh:` lines excluded). A gate that could not run (an exit code above 1, or "could not" / "Error:" in the output with the wrong code) is reported as a tool error, not a verdict. |
| `documents_validate <glob> [extra-args...]` | Validate client documents against the canonical SDL: `ensure_contracts_tools`, then `graphql-inspector validate '<glob>' 'contracts/schema/**/*.graphql'`. The glob is expanded by the tool, relative to the working directory. Prints the combined output and returns the tool's exit code (0 when every document is valid, 1 when one is not), so a caller asserts success or failure and the needle, as it does with `run_gate`. |
| `session_start` | Install the harness EXIT trap without a compose stack, so `on_exit` hooks run for a script that never calls `compose_up` (a cluster `smoke.sh`). Safe to call more than once; a later `compose_up` keeps the one trap. |
| `compose_inspect <service> <go-template>` | `docker inspect -f <template>` on the service's container of the running stack (found with `docker compose ps -q`). FAIL when no stack is up or the service has no container. |
| `compose_exec_http <service> <method> <path> [curl-args...]` | One request made inside the service's container, to `http://localhost:8080<path>`, for endpoints the edge does not route. Output as `http_any`: the status on line 1, then the body. The image needs `curl`. |
| `source_calls_in <service>` / `source_calls_reset_in <service>` | The source-call log of a backend read inside its container (`compose_exec_http ... /debug/source-calls`): prints the same JSON as `source_calls`; the reset expects `204`. |
| `run_load <service> <run> <expected-iterations> [-e K=V ...]` | One load run of a compose service (k6): `compose_run -e RUN=<run>` with the extra `-e` pairs, then the summary JSON on the last line of stdout is read. Passes when `metrics.iterations.values.count` equals the expectation and `metrics.checks.values.rate` is `1`; prints the summary line for further fields. A non-zero exit (a failed threshold) fails with the tail of the output. The service's `handleSummary` writes k6's summary object to stdout as one line. |
| `LGTM_CACERT` (env) | A PEM file. When set, every `curl` in the harness adds `--cacert "$LGTM_CACERT"` (`wait_for_graphql`, `gql`, `gql_any`, `gql_meta`, `gql_get`, `gql_raw`, `http_*`, `wait_for_http`, `assert_transport_fails`, `oidc_token`, the `__type` helpers and `source_calls*`), and `assert_sdl_*` exports it to graphql-inspector as `NODE_EXTRA_CA_CERTS`. Unset or empty: nothing changes. Set it for an HTTPS stack with a private CA (Ch17, Ch18). |
| `LGTM_BEARER` (env) | An access token. When set, the same callers add `-H "Authorization: Bearer $LGTM_BEARER"` (not `oidc_token`), and `assert_sdl_*` passes `--header "Authorization: Bearer ..."` to graphql-inspector. Unset or empty: nothing changes. Leave it unset for anonymous runs. |
| `LGTM_TRACEPARENT` (env) | A W3C traceparent value. When set, the same callers add `-H "traceparent: $LGTM_TRACEPARENT"`, so every GraphQL and HTTP helper joins the trace the script chose (Ch19). Unset or empty: nothing changes. |
| `LGTM_HEADERS` (env) | Newline-separated `Name: value` lines; each becomes a `-H` on the same callers (for example `X-Client-Name: web`). Blank lines are skipped. Unset or empty: nothing changes. |
| `_lib_curl_opts [--no-bearer] [--no-trace]` (internal) | Fills `_LIB_CURL_OPTS` from the four variables; every caller above expands `"${_LIB_CURL_OPTS[@]}"`, so the options cannot drift apart. `--no-trace` leaves out `traceparent` and `LGTM_HEADERS`; the Tempo, Prometheus and Loki helpers use it, so a backend query is not part of the trace under test. |
| `gql_raw <url> <json-body> [accept] [content-type]` | POST the body verbatim (APQ hash-only, arrays, `text/plain`). Output as `gql_any`: the status on line 1, then the body. |
| `http_any <method> <url> [curl-args...]` | Any method plus extra curl arguments. Line 1 is the status, the rest is the body. Non-zero only on a transport failure. |
| `http_headers <method> <url> [curl-args...]` | The response headers of the final response as lowercase `name: value` lines; the body is discarded. |
| `header_value <headers> <name>` | The value of the (case-insensitive) header in an `http_headers` result, or nothing; repeated headers are joined with `, `. |
| `assert_header <headers> <name> <expected> [ctx]` / `assert_header_absent <headers> <name> [ctx]` | The header is present with exactly this value / does not occur. |
| `assert_transport_fails <ctx> <curl-args...>` | Passes only when `curl` exits non-zero (TLS verification, a protocol floor, a closed port); an HTTP answer of any status fails. `LGTM_CACERT`/`LGTM_BEARER` apply, so run a no-CA case as `LGTM_CACERT= assert_transport_fails ...`. |
| `sha256_hex <text>` | Lowercase hex SHA-256 of the UTF-8 text. |
| `apq_body <query-or-empty> <hash> [variables-json] [operationName]` | The APQ JSON body with `extensions.persistedQuery {version: 1, sha256Hash}`; `query` only when non-empty (hash-only first attempt). Send it with `gql_raw`. |
| `apq_get_url <url> <hash> [variables-json]` | The URL-encoded GET form (`variables`, `extensions`), for `http_any GET`. |
| `wait_for_http <url> [timeout] [expected-status]` | Poll a GET until the status matches (default 200, timeout 90s); honours the curl options, so it waits for HTTPS endpoints too. |
| `oidc_token <token-url> <client-id> <username> <password>` | Password-grant POST (form-encoded); prints the `access_token`; FAIL with the identity provider's error text otherwise. Lab only: RFC 9700 removes the password grant. |
| `ensure_contracts_tools` | `npm ci --prefix contracts` when the pinned `graphql-inspector` is missing, under an exclusive `flock` on `${TMPDIR:-/tmp}/gql-contracts-npm.lock`, so verify.sh runs started concurrently never race the install. |
| `compose_run <service> [args...]` | `COMPOSE_PROGRESS=quiet docker compose -p <project> -f <file> run --rm -T --build <service> args...` for the stack `compose_up` started, so the service's own output is all a caller captures; FAIL when none is up. A service behind a compose profile runs explicitly through it, so `compose_up` is the same for every example. |
| `wait_for_json <url> <dot.path> <expected> [timeout]` | Poll a GET until the JSON value at the path (`json_field` syntax) equals the expectation (default timeout 60s). For a counter a stack publishes, such as a subscriber count. |
| `assert_request_count <calls-json> <n> [ctx]` | The number of distinct non-empty request ids in a source-call log equals n. |
| `assert_calls_per_request <calls-json> <n> [ctx]` | Every distinct non-empty request id in the log made exactly n calls; a failure prints the first offending id and its count. An empty log fails. |
| `assert_calls_same_per_request <calls-json> <k1,k2,...> [ctx]` | For every request id, the multiset of `source.op:key` entries equals the list; order ignored. The per-request form of `assert_source_calls_exactly`, for load runs where many requests share one log. |
| `assert_junit <report-file-or-dir> <expected-tests> [ctx]` | Reads JUnit XML (one file, or every `TEST-*.xml` in a directory: Maven Surefire writes one per class, pytest one `junit.xml`). The total `tests` equals the expectation and `failures`, `errors` and `skipped` are all 0; a failure lists the names of the failing tests. The exact count shows the suite ran what it should. |
| `new_trace_id` | 32 lowercase hex characters (`secrets.token_hex(16)`). |
| `traceparent_for <trace-id>` | `00-<trace-id>-<16 hex>-01`; FAIL when the id is not 32 lowercase hex characters. Export the result as `LGTM_TRACEPARENT`. |
| `tempo_trace <tempo-base> <trace-id> [timeout] [min-spans]` | Poll `GET <base>/api/traces/<id>` (and `/api/v2/traces/<id>` when the first answers 404) until the trace holds at least `min-spans` spans (default 1); print a normalized document `{"spans":[{"name","spanId","parentSpanId","service","kind","status","attributes":{...}}]}`. Both Tempo response shapes (`{"batches":[...]}` and `{"trace":{"resourceSpans":[...]}}`) are read; ids print as hex whether Tempo sent hex or base64; `kind` is `SERVER`, `CLIENT`, `INTERNAL` ...; `status` is `OK`, `ERROR` or `UNSET`; attribute values are plain JSON values. FAIL after the timeout (default 60). |
| `assert_span <trace> <name-regex> [min] [max] [ctx]` | The number of spans whose name matches (`re.search`) is within [min, max]; defaults 1 and unbounded. |
| `assert_span_attr <trace> <name-regex> <attr> <expected> [ctx]` | Some span matching the name has the attribute with this value (compared as text; booleans are `true`/`false`). |
| `assert_span_attr_absent <trace> <attr-regex> [ctx]` | No span has an attribute whose key matches the regex. |
| `assert_span_descends <trace> <child-regex> <ancestor-regex> [ctx]` | At least one span matches the child regex, and every one has an ancestor whose name matches the other regex. |
| `assert_span_status <trace> <name-regex> <OK\|ERROR\|UNSET> [ctx]` | Some span matching the name has that status. |
| `assert_attr_not_contains <trace> <name-regex> <attr> <needle> [ctx]` | At least one span matches the name, and the attribute of every matching span does not contain the needle (a span without the attribute passes). |
| `prom_query <prom-base> <promql>` | Instant query, `GET /api/v1/query`; prints the `data.result` JSON. Non-zero unless Prometheus answers `success`. |
| `wait_for_metric <prom-base> <promql> <min> [timeout]` | Poll until the first sample's value is at least `min` (default timeout 120s). |
| `assert_metric_eq <prom-base> <promql> <value> [ctx]` | The first sample's value equals the number; no sample fails. |
| `loki_wait <loki-base> <logql> [timeout] [min-lines]` | Poll `GET /loki/api/v1/query_range` (last hour, up to 1000 lines, oldest first) until at least `min-lines` lines (default 1) match; print the lines. FAIL after the timeout (default 60). |
| `sse_collect <url> <max-secs> <max-events> [curl-args...]` | Read a `text/event-stream` with `curl -sN --max-time`; print one JSON line per event, `{"event","id","data"}`, as each completes. Comment lines are skipped, `event` defaults to `message`, `id` is the event's own id or empty, several `data` lines join with a newline. Stops after `max-events`. Pass headers as curl arguments (`-H 'Accept: text/event-stream'`). Non-zero only when the transport fails; reaching the time or event limit is not an error. |

## Notes

- `lib.sh` is **bash-only** (`BASH_SOURCE`, `[[ ]]`, arrays). Run a `verify.sh` with `bash`
  and never source `lib.sh` from zsh or sh.
- Do not set your own `EXIT` trap in a `verify.sh`: it would replace the one `compose_up`
  registers. Register cleanup with `on_exit`; the hooks run after the stack teardown, in
  registration order, and the script keeps its exit status.
- Helpers called inside `$(...)` need `|| return 1` after each assertion, or a failed
  assertion is swallowed by the command substitution.

## Telemetry (Ch19)

A script picks the trace id, sends it, and reads that trace back by id:

```bash
trace_id="$(new_trace_id)"
export LGTM_TRACEPARENT="$(traceparent_for "$trace_id")"
gql "$URL" '{ cargo(trackingId: "ABC123") { description } }' >/dev/null
trace="$(tempo_trace http://localhost:3200 "$trace_id" 60 3)"
assert_span "$trace" 'POST' 1
assert_span_descends "$trace" 'booking' 'POST'
```

Every assertion names the trace id the script sent, never "the latest trace".
`tempo_trace` hands the assertions a normalized document, so they read the same
whichever Tempo endpoint answered. The Tempo, Prometheus and Loki calls never
send `LGTM_TRACEPARENT`, `LGTM_HEADERS` or the bearer token.

## Source-call log

From Ch6 on, each stack can record every call into its sources when started with
`TRACKING_DEBUG_ENDPOINTS=true` (lab-only; default off). `GET /debug/source-calls`
returns `{"calls":[{"request","source","op","key","startMs","endMs"}, ...]}`
sorted by `startMs`, `DELETE` clears it (`204`). `startMs` and `endMs` are
monotonic milliseconds. Only calls to the owners are logged: a cache hit (Ch16) is not a source call. A call key reads `source.op:key`, for example
`booking.getCargo:ABC123`. Batch operations (Ch13) use plural names (`getCargos`, `getItineraries`, `getVoyages`, `getLocations`, `listEventsFor`) and their key is the sorted distinct keys joined with `+`, for example `booking.getCargos:ABC123+DEF456`; never `,`, which `assert_source_calls_exactly` splits on. Ch12 adds `booking.listCargos` (key: the `routingStatus` filter, or `*` for none) and `handling.pageEvents` (key: the tracking id). The log is not part of the schema. The ordering and
overlap assertions compare those windows and never absolute durations.

## Contract conformance

Both stacks are code-first, so the schema is whatever the annotated or decorated
code builds. `assert_sdl_conforms` reads it through standard introspection
(`graphql-inspector` accepts a URL as a schema pointer) and diffs it with the
canonical SDL in two directions:

- **live to canonical**: any breaking change means the stack exposes something
  the contract lacks (an extra field, type or argument) or is looser than the
  contract (for example `Cargo` where the contract says `Cargo!`).
- **canonical to live**: a removed type, a removed output field, or an unserved
  mutation or subscription root is the part of the schema the example does not
  serve yet, which is expected for a slice. Any other breaking change means
  something the stack does serve differs from the contract: a nullable field
  the contract makes non-null, a different type, a missing argument, enum value
  or union member. A changed, added or removed description on a type, field or
  argument both sides have fails too.

Framework-injected differences (SmallRye's `@constraint`, `@defer`,
`@experimental_disableErrorPropagation` and `@rolesAllowed` directives and its
`BigDecimal`/`BigInteger` scalars) are filtered by name through
`LGTM_SDL_IGNORE`, an extended regex you can override. A tool failure
(unreachable endpoint, schema that will not load) fails the check; it never
reads as "conforms".

The diff covers types, fields, arguments and enum values. A scalar's
`@specifiedBy` is asserted in `verify.sh` with
`__type(name: "UnLocode") { specifiedByURL }`.

`graphql-inspector` comes from `contracts/node_modules`, pinned in
`contracts/package.json` and installed with `npm ci`. `verify.sh` needs Node and
npm on the host (CI sets up the same Node version as the contracts job).

## Minimal example

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch00-prereq"
compose_up "$SCRIPT_DIR/compose.yaml" "$PROJECT"
wait_for_graphql http://localhost:8080/graphql

resp="$(gql http://localhost:8080/graphql \
  'query($t: TrackingId!) { cargo(trackingId: $t) { description } }' '{"t":"ABC123"}')"
assert_no_errors "$resp"
assert_eq "Palletized electronics" "$(json_field '.data.cargo.description' <<<"$resp")" "description"
assert_sdl_conforms http://localhost:8080/graphql
```
