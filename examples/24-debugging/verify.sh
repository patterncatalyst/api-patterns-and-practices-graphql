#!/usr/bin/env bash
# examples/24-debugging/verify.sh
#
# Ch24 Debugging: one seeded data fault, diagnosed from the response to the
# cause. Cargo JKL012 is routed to XXBAD, a code the location service does not
# hold. Two ordinary queries show it:
#
#   F1  itinerary { legs { unloadLocation { name } } }  a null in a non-null
#       position: the error path names the field, and the nullable ancestor
#       (itinerary) becomes null.
#   F2  delivery { transportStatus }  an unexpected exception inside the
#       delivery derivation: the response says only "Internal server error.",
#       the error carries extensions.traceId, and the trace and the log hold
#       the rest.
#
# Four instances run beside the observability stack: a production instance and
# a development instance of each stack. verify.sh reads the error from the
# response, follows the trace id to Tempo and Loki, switches the application's
# debug category on and off at run time, and checks which development surfaces
# each instance serves.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch24-debugging"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
TEMPO="http://localhost:8345"
LOKI="http://localhost:8347"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
F1='query LegsOfJkl($id: TrackingId!) { cargo(trackingId: $id) { trackingId itinerary { legs { unloadLocation { name } } } } }'
# shellcheck disable=SC2016
F2='query DeliveryOfJkl($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }'
# shellcheck disable=SC2016
HEALTHY='query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }'
# shellcheck disable=SC2016
UNAVAILABLE='query CargoOf($id: TrackingId!) { cargo(trackingId: $id) { trackingId } }'
Q_FAN='query FanOut { cargos(first: 4) { edges { node { trackingId itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } } delivery { transportStatus } } } } }'
COUNT='query Count { cargos(first: 1) { totalCount } }'

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

# traced <traceparent> <command...> - run one harness call that joins the trace.
traced() {
  local tp="$1"
  shift
  LGTM_TRACEPARENT="$tp" "$@"
}

# log_count <service> <fixed-string> - how many lines of the service's log contain the text.
log_count() {
  local logs
  logs="$(compose_logs "$1")" || return 1
  grep -cF -- "$2" <<<"$logs" || true
}

# loki_count <lines> <fixed-string> - how many of the lines contain the text.
loki_count() {
  grep -cF -- "$2" <<<"$1" || true
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

# routes_off <stack> - the production image started without TRACKING_DEBUG_ENDPOINTS
# answers 404 on its debug routes. The container has no published port and no
# collector; the check runs curl inside it.
routes_off() {
  local stack="$1" name="e2r1-quiet-$1" env route code i
  case "$stack" in
    quarkus) env=QUARKUS_OTEL_SDK_DISABLED; route='/q/logging-manager?loggerName=x' ;;
    python) env=OTEL_SDK_DISABLED; route='/debug/loggers?loggerName=x' ;;
  esac
  docker rm -f "$name" >/dev/null 2>&1 || true
  on_exit "docker rm -f $name >/dev/null 2>&1 || true"
  docker run -d --name "$name" -e "$env=true" "gql-ch24-debugging-$stack:local" >/dev/null
  for i in $(seq 1 60); do
    docker exec "$name" curl -fsS -o /dev/null http://localhost:8080/graphql -H 'Accept: application/json' -d '{"query":"{ __typename }"}' -H 'Content-Type: application/json' 2>/dev/null && break
    sleep 2
  done
  code="$(docker exec "$name" curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080$route")"
  assert_eq "404" "$code" "$stack: the level switch is not served without TRACKING_DEBUG_ENDPOINTS"
  code="$(docker exec "$name" curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/debug/source-calls)"
  assert_eq "404" "$code" "$stack: the source-call log is not served without TRACKING_DEBUG_ENDPOINTS"
  docker rm -f "$name" >/dev/null
}

# check_f1 <stack> <url> <label> - F1 on one instance: the error path and the nulls.
check_f1() {
  local stack="$1" url="$2" label="$3" resp
  resp="$(gql "$url" "$F1" '{"id":"JKL012"}' LegsOfJkl)"
  assert_eq "JKL012" "$(json_field '.data.cargo.trackingId' <<<"$resp")" "$label F1: the cargo still answers"
  assert_null_at "$resp" '.data.cargo.itinerary' "$label F1: itinerary is the nullable ancestor that became null"
  assert_error_count "$resp" 1 "$label F1: one error"
  assert_error_path "$resp" '["cargo","itinerary","legs",1,"unloadLocation"]' "$label F1: the path names the second leg's unloadLocation"
  case "$stack" in
    quarkus) assert_error_message_contains "$resp" "declared as a non null type" "$label F1: the engine explains the null" ;;
    python) assert_error_message_at "$resp" '["cargo","itinerary","legs",1,"unloadLocation"]' "Internal server error." "$label F1: the null is masked like every unexpected error" ;;
  esac
  assert_body_not_contains "$resp" "XXBAD" "$label F1: the code is not in the response"
}

# check_f2 <stack> <url> <label> - F2 on one instance: masked, with its trace id.
check_f2() {
  local stack="$1" url="$2" label="$3" resp
  resp="$(gql "$url" "$F2" '{"id":"JKL012"}' DeliveryOfJkl)"
  assert_null_at "$resp" '.data.cargo' "$label F2: delivery is non-null, so cargo became null"
  assert_error_count "$resp" 1 "$label F2: one error"
  assert_error_path "$resp" '["cargo","delivery"]' "$label F2: the path names delivery"
  assert_error_message_at "$resp" '["cargo","delivery"]' "Internal server error." "$label F2: the message is masked"
}

# run_stack_check <stack> <url> <dev-url>
run_stack_check() {
  local stack="$1" url="$2" dev_url="$3"
  local service="ch24-debugging-$stack"
  local base category logger_read logger_write
  local resp calls trace_id tp trace http_re op total fan_spans f2_spans f1_spans exc_type exc_text
  local lines t0 t1 t2 t3 level

  echo
  echo "=== verifying stack '$stack' at $url (development instance at $dev_url) ==="

  http_re='^POST /graphql$'
  base="$(graphql_base "$url")"
  case "$stack" in
    quarkus)
      op_re() { echo "^query $1\$"; }
      res_re() { echo "^$1\$"; }
      total=8; fan_spans=35; f2_spans=7; f1_spans=9
      exc_type='.*NoSuchElementException.*'
      category="com.patterncatalyst.shipping.tracking.resolve"
      logger_read="$base/q/logging-manager"
      logger_write="$base/q/logging-manager"
      ;;
    python)
      op_re() { echo "^GraphQL Query: $1\$"; }
      res_re() { echo "^GraphQL Resolving: $1\$"; }
      total=6; fan_spans=38; f2_spans=12; f1_spans=14
      exc_type='KeyError'
      category="app.resolve"
      logger_read="$base/debug/loggers"
      logger_write="$base/debug/loggers"
      ;;
  esac

  wait_for_graphql "$url"
  wait_for_graphql "$dev_url" 240

  # 1. Unchanged behaviour: Chapter 19's answers, and no extension on a success.
  resp="$(gql "$url" "$HEALTHY" '{"id":"ABC123"}' TrackCargo)"
  assert_no_errors "$resp" "$stack TrackCargo"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "TrackCargo transportStatus"
  assert_absent "$resp" '.extensions' "$stack: a successful response carries no extensions"
  resp="$(gql "$url" "$COUNT" '{}' Count)"
  expect "7" '.data.cargos.totalCount' "the booking index holds seven cargos"
  source_calls_reset "$url"
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(traced "$tp" gql "$url" "$Q_FAN" '{}' FanOut)"
  assert_no_errors "$resp" "$stack FanOut"
  assert_json_eq '[["VWX901",[["V300A","SGSIN","CNSHA"]]],["XYZ789",null],["STU678",[["V300A","SGSIN","CNSHA"]]],["DEF456",[["V100S","USNYC","DEHAM"],["V200E","DEHAM","NLRTM"]]]]' \
    "$(fan_shape)" "$stack FanOut returns Chapter 13's data"
  calls="$(source_calls "$url")"
  assert_source_call_count "$calls" '*' '*' "$total" "$stack FanOut: $total source calls, as in Chapter 13"

  # 8. Fan-out read from the trace: the number of getLocations source.call spans
  #    equals the number of location calls in the log, and they serve every
  #    location resolver span.
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$fan_spans")"
  op="$(op_re FanOut)"
  assert_span "$trace" "$op" 1 1 "$stack FanOut: one operation span"
  assert_span_count "$trace" "$total" "$stack FanOut: one source.call span per source call" '^source\.call$'
  case "$stack" in
    quarkus)
      assert_source_call_count "$calls" location getLocations 2 "$stack FanOut: two location calls in the log"
      assert_span_count "$trace" 2 "$stack FanOut: two getLocations spans, one per location field" '^source\.call$' source.operation getLocations
      ;;
    python)
      assert_source_call_count "$calls" location getLocations 1 "$stack FanOut: one location call in the log"
      assert_span_count "$trace" 1 "$stack FanOut: one getLocations span" '^source\.call$' source.operation getLocations
      ;;
  esac
  assert_span_count "$trace" 8 "$stack FanOut: eight location resolver spans share those calls" "$(res_re '(loadLocation|unloadLocation)')"

  # 2. F1 read from the response (production instance).
  source_calls_reset "$url"
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(traced "$tp" gql "$url" "$F1" '{"id":"JKL012"}' LegsOfJkl)"
  assert_eq "JKL012" "$(json_field '.data.cargo.trackingId' <<<"$resp")" "$stack F1: the cargo still answers"
  assert_null_at "$resp" '.data.cargo.itinerary' "$stack F1: itinerary is the nullable ancestor that became null"
  assert_error_count "$resp" 1 "$stack F1: one error"
  assert_error_path "$resp" '["cargo","itinerary","legs",1,"unloadLocation"]' "$stack F1: the path names the second leg's unloadLocation"
  assert_error_extension "$resp" '["cargo","itinerary","legs",1,"unloadLocation"]' traceId "\"$trace_id\"" "$stack F1: the error carries the trace id the client sent"
  case "$stack" in
    quarkus) assert_error_message_contains "$resp" "declared as a non null type" "$stack F1: the engine explains the null" ;;
    python) assert_error_message_at "$resp" '["cargo","itinerary","legs",1,"unloadLocation"]' "Internal server error." "$stack F1: the null is masked like every unexpected error" ;;
  esac
  assert_body_not_contains "$resp" "XXBAD" "$stack F1: the code is not in the response"
  calls="$(source_calls "$url")"
  assert_source_calls_exactly "$calls" "booking.getCargo:JKL012,routing.getItineraries:JKL012,location.getLocations:DEHAM+XXBAD" \
    "$stack F1: the source-call log holds the location call whose key includes XXBAD"
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$f1_spans")"
  assert_span "$trace" "$(op_re LegsOfJkl)" 1 1 "$stack F1: the operation span is in the trace"
  assert_span "$trace" "$(res_re unloadLocation)" 2 2 "$stack F1: one unloadLocation span per leg"

  # 3. F2 through the diagnosis path (production instance).
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(traced "$tp" gql "$url" "$F2" '{"id":"JKL012"}' DeliveryOfJkl)"
  assert_null_at "$resp" '.data.cargo' "$stack F2: delivery is non-null, so cargo became null"
  assert_error_count "$resp" 1 "$stack F2: one error"
  assert_error_shape "$resp" execution "$stack F2: execution error shape"
  assert_error_path "$resp" '["cargo","delivery"]' "$stack F2: the path names delivery"
  assert_error_message_at "$resp" '["cargo","delivery"]' "Internal server error." "$stack F2: the message is masked"
  assert_error_extension "$resp" '["cargo","delivery"]' traceId "\"$trace_id\"" "$stack F2: extensions.traceId equals the trace id the client sent"
  case "$stack" in
    quarkus)
      assert_error_extension "$resp" '["cargo","delivery"]' code null "$stack F2: the masked error has no code"
      assert_eq "code,traceId" "$(json_keys '.errors.0.extensions' <<<"$resp")" "$stack F2: code and traceId are the only extensions"
      ;;
    python)
      assert_error_extension_absent "$resp" '["cargo","delivery"]' code "$stack F2: the masked error has no code"
      assert_eq "traceId" "$(json_keys '.errors.0.extensions' <<<"$resp")" "$stack F2: traceId is the only extension"
      ;;
  esac
  assert_body_not_contains "$resp" "XXBAD" "$stack F2: the unknown code stays server-side"
  assert_body_not_contains "$resp" "NoSuchElement" "$stack F2: the exception type stays server-side"
  assert_body_not_contains "$resp" "KeyError" "$stack F2: the exception type stays server-side (Python)"
  assert_body_not_contains "$resp" "Traceback" "$stack F2: no stack trace reaches the client"
  assert_body_not_contains "$resp" "at com.patterncatalyst" "$stack F2: no stack frame reaches the client"
  # The trace by that id: the operation span and an ERROR span below it.
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$f2_spans")"
  op="$(op_re DeliveryOfJkl)"
  assert_span "$trace" "$op" 1 1 "$stack F2: one operation span, named for the operation"
  assert_span_descends "$trace" "$(res_re delivery)" "$op" "$stack F2: the delivery resolver span descends from the operation span"
  assert_span_status "$trace" "$(res_re delivery)" ERROR "$stack F2: the delivery resolver span ends in ERROR"
  # The log record by the same id: the exception, and the data behind it.
  # trace_id, exception_type and exception_message are structured metadata on the record.
  loki_wait "$LOKI" "{service_name=\"$service\"} | trace_id=\"$trace_id\" | exception_type=~\"$exc_type\" | exception_message=~\".*XXBAD.*\"" 90 1 >/dev/null

  # 3a. A request error has no path and carries no traceId.
  resp="$(gql_any "$url" '{ cargo(trackingId: "ABC123") { trackingId ')"
  assert_status_in "200 400" "$(status_of "$resp")" "$stack parse error: request error status"
  python3 -I -c '
import json, sys
errors = json.loads(sys.stdin.read())["errors"]
assert errors and all("traceId" not in (e.get("extensions") or {}) for e in errors), errors
' <<<"$(body_of "$resp")" || { echo "FAIL - $stack: a request error carries a traceId" >&2; return 1; }
  echo "lib.sh: ok — $stack: a request error carries no traceId" >&2

  # 3b. An exposed error carries the trace id too.
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(traced "$tp" gql "$url" "$UNAVAILABLE" '{"id":"GHI345"}' CargoOf)"
  assert_error_extension "$resp" '["cargo"]' code '"SERVICE_UNAVAILABLE"' "$stack GHI345: the exposed error keeps its code"
  assert_error_extension "$resp" '["cargo"]' traceId "\"$trace_id\"" "$stack GHI345: and carries the trace id"

  # 4. A trace id without a caller trace: the server's own.
  resp="$(gql "$url" "$F2" '{"id":"JKL012"}' DeliveryOfJkl)"
  trace_id="$(json_field '.errors.0.extensions.traceId' <<<"$resp")"
  if [[ ! "$trace_id" =~ ^[0-9a-f]{32}$ ]]; then
    echo "FAIL - $stack: extensions.traceId is not 32 lowercase hex characters: $trace_id" >&2
    return 1
  fi
  echo "lib.sh: ok — $stack: the server-chosen trace id is 32 lowercase hex characters" >&2
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$f2_spans")"
  assert_span "$trace" "$(op_re DeliveryOfJkl)" 1 1 "$stack: the trace the server chose is findable by the id the response carried"

  # 5. The application's debug category, switched at run time.
  #    5a: at INFO, F1 writes no resolve line.
  level="$(http_any GET "$logger_read?loggerName=$category" | tail -n +2)"
  assert_eq "INFO" "$(json_field '.effectiveLevel' <<<"$level")" "$stack: the debug category is at INFO"
  t0="$(new_trace_id)"
  traced "$(traceparent_for "$t0")" gql "$url" "$F1" '{"id":"JKL012"}' LegsOfJkl >/dev/null
  #    5b: switched to DEBUG on the running instance, read back.
  resp="$(http_any POST "$logger_write" -d "loggerName=$category" -d loggerLevel=DEBUG)"
  assert_status_in "200 201" "$(status_of "$resp")" "$stack: the level switch answers"
  level="$(http_any GET "$logger_read?loggerName=$category" | tail -n +2)"
  assert_eq "DEBUG" "$(json_field '.effectiveLevel' <<<"$level")" "$stack: the debug category reads back DEBUG"
  t1="$(new_trace_id)"
  traced "$(traceparent_for "$t1")" gql "$url" "$F1" '{"id":"JKL012"}' LegsOfJkl >/dev/null
  # The debug lines of that request, found by its trace id: one per distinct key.
  lines="$(loki_wait "$LOKI" "{service_name=\"$service\"} | trace_id=\"$t1\" |= \"resolve Leg.unloadLocation\"" 90 2)"
  assert_eq "1" "$(loki_count "$lines" 'resolve Leg.unloadLocation key=XXBAD outcome=missing')" "$stack: one debug line names XXBAD as missing"
  assert_eq "1" "$(loki_count "$lines" 'resolve Leg.unloadLocation key=DEHAM outcome=found')" "$stack: one debug line names DEHAM as found"
  #    The console holds the same two lines, and none from the request at INFO.
  assert_eq "2" "$(log_count "$stack" 'resolve Leg.unloadLocation')" "$stack: the log holds two resolve lines, both from the DEBUG request"
  assert_eq "1" "$(log_count "$stack" 'key=XXBAD outcome=missing')" "$stack: exactly one line for XXBAD"
  if [[ "$stack" == quarkus ]]; then
    assert_eq "1" "$([[ "$(log_count quarkus "traceId=$t1")" -ge 2 ]] && echo 1 || echo 0)" "$stack: the console lines of the request carry its trace id"
  fi
  assert_body_not_contains "$lines" "ABC123" "$stack: the debug lines carry reference keys, not tracking ids"
  #    5c: switched back to INFO, read back, and F1 writes nothing more.
  resp="$(http_any POST "$logger_write" -d "loggerName=$category" -d loggerLevel=INFO)"
  assert_status_in "200 201" "$(status_of "$resp")" "$stack: the level switch answers"
  level="$(http_any GET "$logger_read?loggerName=$category" | tail -n +2)"
  assert_eq "INFO" "$(json_field '.effectiveLevel' <<<"$level")" "$stack: the debug category reads back INFO"
  t2="$(new_trace_id)"
  traced "$(traceparent_for "$t2")" gql "$url" "$F1" '{"id":"JKL012"}' LegsOfJkl >/dev/null
  # F2 after it: its exception record reaches Loki after anything F1 wrote.
  t3="$(new_trace_id)"
  traced "$(traceparent_for "$t3")" gql "$url" "$F2" '{"id":"JKL012"}' DeliveryOfJkl >/dev/null
  loki_wait "$LOKI" "{service_name=\"$service\"} | trace_id=\"$t3\" | exception_type=~\"$exc_type\"" 90 1 >/dev/null
  assert_eq "2" "$(log_count "$stack" 'resolve Leg.unloadLocation')" "$stack: back at INFO, the same two lines are all the log holds"

  # 6. Development surfaces: present on the development instance, absent on production.
  local dev_base dev_service payloads
  dev_base="$(graphql_base "$dev_url")"
  case "$stack" in
    quarkus)
      dev_service="quarkus-dev"
      resp="$(http_any GET "$dev_base/q/graphql-ui/" -H 'Accept: text/html')"
      assert_eq "200" "$(status_of "$resp")" "$stack dev: the GraphQL UI answers"
      assert_contains "graphiql" "$(tr '[:upper:]' '[:lower:]' <<<"$(body_of "$resp")")" "$stack dev: the GraphQL UI page is GraphiQL"
      resp="$(http_any GET "$dev_base/q/dev-ui/" -H 'Accept: text/html')"
      assert_eq "200" "$(status_of "$resp")" "$stack dev: the Dev UI answers"
      resp="$(http_any GET "$base/q/graphql-ui/" -H 'Accept: text/html')"
      assert_eq "404" "$(status_of "$resp")" "$stack production: no GraphQL UI"
      resp="$(http_any GET "$base/q/dev-ui/" -H 'Accept: text/html')"
      assert_eq "404" "$(status_of "$resp")" "$stack production: no Dev UI"
      ;;
    python)
      dev_service="python-dev"
      resp="$(http_any GET "$dev_url" -H 'Accept: text/html')"
      assert_eq "200" "$(status_of "$resp")" "$stack dev: GraphiQL answers on the GraphQL path"
      assert_contains "graphiql" "$(tr '[:upper:]' '[:lower:]' <<<"$(body_of "$resp")")" "$stack dev: the page is GraphiQL"
      resp="$(http_any GET "$url" -H 'Accept: text/html')"
      assert_eq "404" "$(status_of "$resp")" "$stack production: no GraphiQL on the GraphQL path"
      ;;
  esac

  # 7. Reproduce in the development instance: the same document, the same error.
  check_f1 "$stack" "$dev_url" "$stack dev"
  check_f2 "$stack" "$dev_url" "$stack dev"
  if [[ "$stack" == quarkus ]]; then
    # Payload logging is a development setting: the document is in the dev log, and not in production's.
    payloads="$(log_count "$dev_service" 'Payload In [query LegsOfJkl')"
    assert_eq "1" "$payloads" "$stack dev: the log holds the payload of the LegsOfJkl request"
    assert_eq "0" "$(log_count quarkus 'Payload In')" "$stack production: the log holds no request payload"
  fi

  # 9. The deprecation of Chapter 11, the custom scalars, and the live schema: the seed adds data only.
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

  routes_off "$stack"

  echo "=== $stack: debugging check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8340/graphql" "http://localhost:8342/graphql"
run_stack_check "python" "http://localhost:8341/graphql" "http://localhost:8343/graphql"

echo
echo "PASS - Ch24 Debugging: on Quarkus and Python, the failing field is read from the error path, a masked" \
     "error carries extensions.traceId equal to the caller's trace id, that id finds the ERROR span in Tempo" \
     "and the exception record in Loki, the application's debug category switches INFO, DEBUG, INFO at run" \
     "time, the GraphQL UI and the Dev UI answer on the development instances and return 404 on production," \
     "the same document reproduces the error in development, and the schema is unchanged."
