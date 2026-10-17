#!/usr/bin/env bash
# examples/19-observability/verify.sh
#
# Ch19 Observability: both stacks export traces, metrics and logs over OTLP to
# the collector in the lgtm service. Every traced request carries a trace id
# chosen here (W3C traceparent), and every assertion reads that trace back from
# Tempo by its id; the metrics are read from Prometheus and the log records from
# Loki.
#
#   Quarkus  quarkus-opentelemetry + the OpenTelemetry graphql-java
#            instrumentation (installed through the GraphQL.Builder event):
#            spans "POST /graphql", "query <operation>", one span per data
#            fetcher named for the field, "source.call".
#   Python   opentelemetry-instrument (FastAPI) + Strawberry's
#            OpenTelemetryExtension: spans "POST /graphql",
#            "GraphQL Query: <operation>", "GraphQL Resolving: <field>",
#            "source.call".
#
# Both stacks add two metrics a span cannot give: graphql.errors (by
# extensions.code and operation) and graphql.field.deprecated.usage (by field
# coordinate, operation and client).
#
# Q_FAN pages four cargos with itinerary legs and delivery: 8 source calls on
# Quarkus and 6 on Python (Chapter 13). The trace of that request has 25 resolver
# spans on both stacks and one source.call span per source call.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch19-observability"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
TEMPO="http://localhost:8293"
PROM="http://localhost:8294"
LOKI="http://localhost:8295"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
Q_FAN='query FanOut { cargos(first: 4) { edges { node { trackingId itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } } delivery { transportStatus } } } } }'
# shellcheck disable=SC2016
TRACK='query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }'
# shellcheck disable=SC2016
LEGACY='query LegacyArrival($id: TrackingId!) { cargo(trackingId: $id) { itinerary { finalArrivalDate again: finalArrivalDate } } }'
FAULT='query CargoPage { cargos(last: 2) { edges { node { trackingId } } } }'
LITERAL='query TrackLiteral { cargo(trackingId: "ABC123") { trackingId } }'

# --- local helpers over the normalized trace document (see _lib/README.md) ----

# span_count <trace> <name-regex> [<attr> <value>] - spans whose name matches and,
# when given, whose attribute (or "@status") equals the value.
span_count() {
  python3 -I -c '
import json, re, sys
spans = json.load(sys.stdin)["spans"]
name, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
def has(span):
    if not key:
        return True
    got = span["status"] if key == "@status" else span["attributes"].get(key)
    return str(got).lower() == value.lower() if isinstance(got, bool) else str(got) == value
print(sum(1 for s in spans if re.search(name, s["name"]) and has(s)))
' "$2" "${3:-}" "${4:-}" <<<"$1"
}

# assert_span_count <trace> <n> <context> <name-regex> [<attr> <value>]
assert_span_count() {
  local actual
  actual="$(span_count "$1" "$4" "${5:-}" "${6:-}")" || return 1
  assert_eq "$2" "$actual" "$3"
}

# assert_parent_span <trace> <name-regex> <parent-span-id> <context> - the span's
# parent is the span id the caller sent in its traceparent.
assert_parent_span() {
  local actual
  actual="$(python3 -I -c '
import json, re, sys
spans = [s for s in json.load(sys.stdin)["spans"] if re.search(sys.argv[1], s["name"])]
print(",".join(sorted({s["parentSpanId"] for s in spans})))
' "$2" <<<"$1")" || return 1
  assert_eq "$3" "$actual" "$4"
}

# assert_no_attr_value <trace> <needle> <context> - no attribute of any span holds the needle.
assert_no_attr_value() {
  local hits
  hits="$(python3 -I -c '
import json, sys
spans = json.load(sys.stdin)["spans"]
print(",".join(sorted({s["name"] + " " + k for s in spans for k, v in s["attributes"].items() if sys.argv[1] in str(v)})))
' "$2" <<<"$1")" || return 1
  assert_eq "" "$hits" "$3"
}

# traced <trace-id-traceparent> <command...> - run one harness call that joins the trace.
traced() {
  local tp="$1"
  shift
  LGTM_TRACEPARENT="$tp" "$@"
}

# expect <expected> <json-path> <context> - assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# fan_shape - the data of Q_FAN in $resp reduced to what the cases compare.
fan_shape() {
  python3 -I -c '
import json, sys
edges = json.load(sys.stdin)["data"]["cargos"]["edges"]
out = []
for edge in edges:
    node = edge["node"]
    itinerary = node["itinerary"]
    legs = None if itinerary is None else [
        [leg["voyage"]["number"], leg["loadLocation"]["unLocode"], leg["unloadLocation"]["unLocode"]]
        for leg in itinerary["legs"]
    ]
    out.append([node["trackingId"], legs])
print(json.dumps(out))
' <<<"$resp"
}

# run_stack_check <stack> <url>
run_stack_check() {
  local stack="$1" url="$2"
  local service="ch19-observability-$stack"
  local resp calls trace_id tp trace http_re op total fan_spans track_spans literal_spans fault_spans fault_trace fault_response expect_errors

  echo
  echo "=== verifying stack '$stack' at $url ==="

  # The span names are the instrumentation's own; the cases assert each stack's.
  http_re='^POST /graphql$'
  case "$stack" in
    quarkus)
      op_re() { echo "^query $1\$"; }
      res_re() { echo "^$1\$"; }
      ;;
    python)
      op_re() { echo "^GraphQL Query: $1\$"; }
      res_re() { echo "^GraphQL Resolving: $1\$"; }
      ;;
  esac

  wait_for_graphql "$url"

  # 1. FanOut: the response is Chapter 13's, the trace is the caller's.
  source_calls_reset "$url"
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(traced "$tp" gql "$url" "$Q_FAN" '{}' FanOut)"
  assert_no_errors "$resp" "$stack FanOut"
  assert_json_eq '[["VWX901",[["V300A","SGSIN","CNSHA"]]],["XYZ789",null],["STU678",[["V300A","SGSIN","CNSHA"]]],["DEF456",[["V100S","USNYC","DEHAM"],["V200E","DEHAM","NLRTM"]]]]' \
    "$(fan_shape)" "$stack FanOut returns Chapter 13's data"
  calls="$(source_calls "$url")"
  case "$stack" in
    python) total=6; fan_spans=38; track_spans=12; literal_spans=9; fault_spans=12 ;;
    quarkus) total=8; fan_spans=35; track_spans=7; literal_spans=4; fault_spans=7 ;;
  esac
  assert_source_call_count "$calls" '*' '*' "$total" "$stack FanOut: $total source calls, as in Chapter 13"

  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$fan_spans")"

  # 2. The trace joins the caller: one HTTP server span whose parent is the caller's
  #    span, one operation span below it.
  op="$(op_re FanOut)"
  assert_span "$trace" "$http_re" 1 1 "$stack: one HTTP server span"
  assert_parent_span "$trace" "$http_re" "${tp:36:16}" "$stack: the HTTP span is a child of the caller's span"
  assert_span "$trace" "$op" 1 1 "$stack: one operation span, named for the operation"
  assert_span_descends "$trace" "$op" "$http_re" "$stack: the operation span descends from the HTTP span"
  assert_span_attr "$trace" "$http_re" http.route /graphql "$stack: the HTTP span carries the route"

  # 3. A span per resolver, none for trivial fields. Every resolver span descends
  #    from the operation span.
  local field n
  for field in cargos:1 node:4 itinerary:4 delivery:4 voyage:4 loadLocation:4 unloadLocation:4; do
    n="${field#*:}"
    field="${field%:*}"
    assert_span_count "$trace" "$n" "$stack: $n resolver spans for $field" "$(res_re "$field")"
    assert_span_descends "$trace" "$(res_re "$field")" "$op" "$stack: $field spans descend from the operation span"
  done
  assert_span_count "$trace" 0 "$stack: no spans for the trivial fields" \
    "$(res_re '(trackingId|edges|legs|number|unLocode|transportStatus)')"

  # 4. Batching is visible: eight location resolvers, and as many source.call spans
  #    for the location service as the call log has entries.
  assert_span_count "$trace" "$total" "$stack: one source.call span per source call" '^source\.call$'
  assert_span_descends "$trace" '^source\.call$' "$http_re" "$stack: source.call spans belong to the request's trace"
  case "$stack" in
    python)
      assert_span_count "$trace" 1 "$stack: one location source call serves eight location resolvers" '^source\.call$' source.operation getLocations
      ;;
    quarkus)
      assert_span_count "$trace" 2 "$stack: two location source calls (one per location field) serve eight location resolvers" '^source\.call$' source.operation getLocations
      ;;
  esac
  assert_span_attr "$trace" '^source\.call$' source.name booking "$stack: source.call carries the source name"
  assert_span_attr "$trace" '^source\.call$' source.operation getCargos "$stack: source.call carries the operation"
  assert_span_count "$trace" 1 "$stack: one getCargos span for four cargo resolvers" '^source\.call$' source.operation getCargos

  # 5. TrackCargo: the answer is Chapter 13's, the document in the span has no value.
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(LGTM_HEADERS='Authorization: Bearer ch19-lab-token' traced "$tp" gql "$url" "$TRACK" '{"id":"ABC123"}' TrackCargo)"
  assert_no_errors "$resp" "$stack TrackCargo"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "TrackCargo transportStatus"
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$track_spans")"
  op="$(op_re TrackCargo)"
  assert_span "$trace" "$op" 1 1 "$stack TrackCargo: one operation span"
  case "$stack" in
    quarkus) assert_attr_not_contains "$trace" "$op" graphql.document ABC123 "$stack TrackCargo: the document attribute holds no variable value" ;;
    python) assert_attr_not_contains "$trace" "$op" query ABC123 "$stack TrackCargo: the document attribute holds no variable value" ;;
  esac
  assert_span_attr_absent "$trace" '^graphql\.param\.' "$stack: no span carries a resolver argument"
  assert_span_attr_absent "$trace" 'authorization|token' "$stack: no span carries a credential"
  assert_no_attr_value "$trace" ABC123 "$stack TrackCargo: no span attribute holds the variable value"
  assert_no_attr_value "$trace" ch19-lab-token "$stack TrackCargo: no span attribute holds the bearer token"
  assert_body_not_contains "$trace" ch19-lab-token "$stack TrackCargo: the bearer token is nowhere in the trace"
  # Values sent as variables never reach a span. A literal in the document is part of
  # the document: the OpenTelemetry instrumentation replaces literals when it records
  # the document, and the Python extension records the document as sent.
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(traced "$tp" gql "$url" "$LITERAL" '{}' TrackLiteral)"
  assert_no_errors "$resp" "$stack TrackLiteral"
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$literal_spans")"
  case "$stack" in
    quarkus)
      assert_attr_not_contains "$trace" "$(op_re TrackLiteral)" graphql.document ABC123 "$stack TrackLiteral: the recorded document has no literal"
      assert_span_attr "$trace" "$(op_re TrackLiteral)" graphql.document 'query TrackLiteral{cargo(trackingId:?){trackingId}}' "$stack TrackLiteral: the literal is replaced by ?"
      ;;
    python)
      assert_span_attr "$trace" "$(op_re TrackLiteral)" query "$LITERAL" "$stack TrackLiteral: the document is recorded as sent"
      ;;
  esac
  # Two more TrackCargo requests, so the span metrics below count exactly three.
  gql "$url" "$TRACK" '{"id":"ABC123"}' TrackCargo >/dev/null
  gql "$url" "$TRACK" '{"id":"XYZ789"}' TrackCargo >/dev/null

  # 6. An error in a trace. GHI345 fails inside the bulk booking call (Chapter 13);
  #    the client reads the code and the message, the trace holds the exception.
  trace_id="$(new_trace_id)"
  fault_trace="$trace_id"
  tp="$(traceparent_for "$trace_id")"
  resp="$(traced "$tp" gql "$url" "$FAULT" '{}' CargoPage)"
  assert_error_shape "$resp" execution "$stack CargoPage: execution error shape"
  assert_error_extension "$resp" '["cargos","edges",1,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack CargoPage: the code at GHI345's edge"
  assert_error_message_at "$resp" '["cargos","edges",1,"node"]' "booking service unavailable" "$stack CargoPage: the exposed message"
  fault_response="$resp"
  assert_body_not_contains "$resp" "SourceUnavailable" "$stack CargoPage: no exception class reaches the client"
  assert_body_not_contains "$resp" "Traceback" "$stack CargoPage: no stack trace reaches the client"
  assert_body_not_contains "$resp" "at com.patterncatalyst" "$stack CargoPage: no stack frame reaches the client"
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$fault_spans")"
  op="$(op_re CargoPage)"
  assert_span "$trace" "$op" 1 1 "$stack CargoPage: the operation span is present"
  case "$stack" in
    quarkus)
      assert_span_count "$trace" 2 "$stack CargoPage: both nodes of the failed batch end in ERROR" "$(res_re node)" @status ERROR
      assert_span_status "$trace" "$op" ERROR "$stack CargoPage: the operation span carries the error"
      expect_errors=2
      ;;
    python)
      assert_span_count "$trace" 1 "$stack CargoPage: the failing key's resolver span ends in ERROR" "$(res_re node)" @status ERROR
      assert_span_count "$trace" 1 "$stack CargoPage: the other node's span is not an error" "$(res_re node)" @status UNSET
      expect_errors=1
      ;;
  esac
  assert_span_count "$trace" 1 "$stack CargoPage: one getCargos span for both nodes" '^source\.call$' source.operation getCargos
  assert_span_count "$trace" 0 "$stack CargoPage: a source call that returned does not end in ERROR" '^source\.call$' @status ERROR

  # 7. Span metrics: Tempo turns every span into calls and latency per service and
  #    span name, with no application code. Three TrackCargo requests so far.
  local prom_op
  case "$stack" in
    quarkus) prom_op='query TrackCargo' ;;
    python) prom_op='GraphQL Query: TrackCargo' ;;
  esac
  wait_for_metric "$PROM" "sum(traces_spanmetrics_calls_total{service=\"$service\", span_name=\"$prom_op\"})" 3 180
  assert_metric_eq "$PROM" "sum(traces_spanmetrics_calls_total{service=\"$service\", span_name=\"$prom_op\"})" 3 "$stack span metrics: three TrackCargo operations"
  wait_for_metric "$PROM" "sum(traces_spanmetrics_latency_count{service=\"$service\", span_name=\"$prom_op\"})" 3 120
  assert_metric_eq "$PROM" "sum(traces_spanmetrics_latency_count{service=\"$service\", span_name=\"$prom_op\"})" 3 "$stack span metrics: the latency histogram counts the same three"

  # 8. Errors by code: one count per error in the response (Chapter 13's blast radius
  #    is visible: two errors on Quarkus, one on Python).
  wait_for_metric "$PROM" "sum(graphql_errors_total{service_name=\"$service\", error_code=\"SERVICE_UNAVAILABLE\", graphql_operation_name=\"CargoPage\"})" 1 120
  assert_metric_eq "$PROM" "sum(graphql_errors_total{service_name=\"$service\", error_code=\"SERVICE_UNAVAILABLE\", graphql_operation_name=\"CargoPage\"})" "$expect_errors" "$stack graphql.errors: SERVICE_UNAVAILABLE on CargoPage"

  # 9. Deprecated-field usage by client: when the count stays at zero, the field can go.
  resp="$(gql_any "$url" '{ cargo(trackingId:"ABC123"){ nope } }' '{}')"
  assert_status_in "200 422 400" "$(status_of "$resp")" "$stack invalid document: request error"
  resp="$(LGTM_HEADERS='X-Client-Name: legacy-app' gql "$url" "$LEGACY" '{"id":"ABC123"}' LegacyArrival)"
  assert_no_errors "$resp" "$stack LegacyArrival (1)"
  expect "2026-10-11T18:00:00Z" '.data.cargo.itinerary.finalArrivalDate' "LegacyArrival value"
  resp="$(LGTM_HEADERS='X-Client-Name: legacy-app' gql "$url" "$LEGACY" '{"id":"ABC123"}' LegacyArrival)"
  assert_no_errors "$resp" "$stack LegacyArrival (2)"
  resp="$(gql "$url" "$LEGACY" '{"id":"ABC123"}' LegacyArrival)"
  assert_no_errors "$resp" "$stack LegacyArrival (anonymous client)"
  local dep="graphql_field_deprecated_usage_total{service_name=\"$service\", graphql_field_coordinate=\"Itinerary.finalArrivalDate\""
  wait_for_metric "$PROM" "sum($dep, client_name=\"legacy-app\"})" 2 120
  assert_metric_eq "$PROM" "sum($dep, client_name=\"legacy-app\", graphql_operation_name=\"LegacyArrival\"})" 2 "$stack deprecated usage: legacy-app, twice"
  wait_for_metric "$PROM" "sum($dep, client_name=\"unknown\"})" 1 120
  assert_metric_eq "$PROM" "sum($dep, client_name=\"unknown\"})" 1 "$stack deprecated usage: a request without X-Client-Name counts as unknown"
  # The invalid document went out before the LegacyArrival requests, and both counters leave
  # in the same export, so the deprecated counts above are the barrier for this one.
  assert_metric_eq "$PROM" "sum(graphql_errors_total{service_name=\"$service\"})" "$expect_errors" "$stack graphql.errors: an invalid document is not counted"
  assert_metric_eq "$PROM" "sum(graphql_field_deprecated_usage_total{service_name=\"$service\"})" 3 "$stack deprecated usage: TrackCargo, FanOut and CargoPage add nothing"

  # 10. Logs point at traces: the server-side record of the failure carries the trace
  #     id, and holds the exception the client never saw.
  # trace_id, exception_type and exception_message are structured metadata on the record.
  loki_wait "$LOKI" "{service_name=\"$service\"} | trace_id=\"$fault_trace\" | exception_type=~\".*SourceUnavailable.*\" | exception_message=\"booking service unavailable\"" 90 1 >/dev/null
  assert_body_not_contains "$fault_response" "$fault_trace" "$stack: the trace id is not part of the response body"

  # 11. The deprecation of Chapter 11, the custom scalars, and the live schema:
  #     telemetry changes no field, argument or nullability.
  assert_deprecated "$url" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_not_deprecated "$url" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime"
  local scalar
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016
    resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    expect "SCALAR" '.data.__type.kind' "$scalar kind"
    case "$scalar" in
      UnLocode) expect "https://unece.org/trade/uncefact/unlocode" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      DateTime) expect "https://www.rfc-editor.org/rfc/rfc3339" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      *) assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL" ;;
    esac
  done
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"
  local sdl_rev sdl_removed
  sdl_rev="$(_sdl_diff "$CANONICAL_SDL_GLOB" "$url")"
  sdl_removed="$(grep '✖' <<<"$sdl_rev" | grep -vE "$LGTM_SDL_IGNORE" | sed -E 's/^.*✖ +//' | sort || true)"
  assert_eq "Schema subscription type Subscription was removed.
Type Subscription was removed" "$sdl_removed" "$stack only Subscription is unserved"

  echo "=== $stack: telemetry check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8290/graphql"
run_stack_check "python" "http://localhost:8291/graphql"

echo
echo "PASS - Ch19 Observability: Quarkus (quarkus-opentelemetry with the OpenTelemetry graphql-java" \
     "instrumentation) and Python (opentelemetry-instrument with Strawberry's OpenTelemetryExtension)" \
     "join the caller's trace, open one operation span and one span per resolver, show a batched source" \
     "call under many resolvers, record the exception on the failing span, count errors by code and" \
     "deprecated-field usage by client, feed span metrics, and log records found by trace id, with the" \
     "schema unchanged."
