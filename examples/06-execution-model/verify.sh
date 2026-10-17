#!/usr/bin/env bash
# examples/06-execution-model/verify.sh
#
# Ch6 The execution model: both stacks resolve every source-backed field
# asynchronously (each source call takes 250 ms) and log every source call.
# The checks read that log from /debug/source-calls and assert ORDER and
# OVERLAP only, never a duration: the selection decides which sources are
# called, a parent is resolved before its children, and sibling fields run at
# the same time. They also prove that a request which fails before execution
# (parse, validation, variable coercion, operation selection) calls no source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch06-exec"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# no_calls <context> — nothing was called: the request never reached a source.
no_calls() {
  assert_source_calls_exactly "$(source_calls "$url")" "" "$stack $1: zero source calls"
}

# post_accepting <accept-media-type> <query> — POST with a given Accept header
# and print "<status> <content-type>". gql_any always sends application/json;
# this is how the chapter records what each stack does for the other media type.
post_accepting() {
  local headers body
  headers="$(mktemp)"
  body="$(_gql_body "$2")"
  curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" -o /dev/null -D "$headers" -X POST \
    -H 'Content-Type: application/json' -H "Accept: $1" -d "$body" "$url" || { rm -f "$headers"; return 1; }
  python3 -I -c '
import sys
lines = open(sys.argv[1]).read().splitlines()
status = lines[0].split()[1]
ctype = next((l.split(":", 1)[1].strip() for l in lines if l.lower().startswith("content-type:")), "")
print(status, ctype.split(";")[0])
' "$headers"
  rm -f "$headers"
}

# The helpers above read stack, url and resp from this function's scope.
run_stack_check() {
  local stack="$1" url="$2" resp calls out

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. The selection drives execution: description comes from the booking
  #    record, so no other source is called.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { trackingId description } }')"
  assert_no_errors "$resp" "$stack cargo(ABC123) trackingId description"
  expect "Palletized electronics" '.data.cargo.description' "cargo.description"
  calls="$(source_calls "$url")"
  assert_source_calls_exactly "$calls" "booking.getCargo:ABC123" "$stack selection drives execution"
  assert_source_call_count "$calls" routing '*' 0 "$stack routing not called"
  assert_source_call_count "$calls" delivery '*' 0 "$stack delivery not called"

  # 2. Parent before child, siblings overlap. itinerary and delivery are
  #    siblings under cargo; the two legs' loadLocation fields are siblings
  #    in a list.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { itinerary { legs { loadLocation { unLocode } } } delivery { transportStatus } } }')"
  assert_no_errors "$resp" "$stack parent and siblings"
  expect "USNYC" '.data.cargo.itinerary.legs.0.loadLocation.unLocode' "leg 0 load"
  expect "DEHAM" '.data.cargo.itinerary.legs.1.loadLocation.unLocode' "leg 1 load"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "delivery.transportStatus"
  calls="$(source_calls "$url")"
  assert_source_calls_exactly "$calls" \
    "booking.getCargo:ABC123,routing.getItinerary:ABC123,delivery.getDelivery:ABC123,location.getLocation:USNYC,location.getLocation:DEHAM" \
    "$stack calls made"
  assert_calls_ordered "$calls" booking.getCargo:ABC123 routing.getItinerary:ABC123 "$stack cargo before itinerary"
  assert_calls_ordered "$calls" booking.getCargo:ABC123 delivery.getDelivery:ABC123 "$stack cargo before delivery"
  assert_calls_ordered "$calls" routing.getItinerary:ABC123 location.getLocation:USNYC "$stack itinerary before its legs' locations"
  assert_calls_overlap "$calls" routing.getItinerary:ABC123 delivery.getDelivery:ABC123 "$stack itinerary and delivery overlap"
  assert_calls_overlap "$calls" location.getLocation:USNYC location.getLocation:DEHAM "$stack the two legs overlap"
  assert_single_request "$calls" "$stack one request id for every call"
  echo "--- $stack source-call log for this query (request id shortened) ---" >&2
  python3 -I -c '
import json, sys
calls = json.load(sys.stdin)["calls"]
t0 = calls[0]["startMs"]
for c in calls:
    print("%-9s %-13s %-7s start +%4d  end +%4d" % (c["source"], c["op"], c["key"], c["startMs"] - t0, c["endMs"] - t0))
' <<<"$calls" >&2

  # 3. Top-level query fields are siblings too, and the response keeps the
  #    order of the selection, not alphabetical order.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ b: cargo(trackingId: "XYZ789") { trackingId } a: cargo(trackingId: "ABC123") { trackingId } }')"
  assert_no_errors "$resp" "$stack aliased root fields"
  expect "XYZ789" '.data.b.trackingId' "alias b"
  expect "ABC123" '.data.a.trackingId' "alias a"
  assert_eq "b,a" "$(json_keys '.data' <<<"$resp")" "$stack data keys follow the selection"
  calls="$(source_calls "$url")"
  assert_calls_overlap "$calls" booking.getCargo:XYZ789 booking.getCargo:ABC123 "$stack root fields overlap"
  assert_single_request "$calls" "$stack one request id for both root fields"
  # A second request, with no reset between, carries a different id.
  gql "$url" '{ location(unLocode: "DEHAM") { name } }' >/dev/null
  assert_distinct_requests "$(source_calls "$url")" "$stack a second request has its own id"

  # 4. A request that fails before execution calls no source.
  #    4a. Parse error: an unclosed brace. The status is recorded, not assumed.
  source_calls_reset "$url"
  out="$(gql_any "$url" '{ cargo(trackingId: "ABC123") { trackingId }')"
  assert_status_in "200 400" "$(status_of "$out")" "$stack parse error"
  resp="$(body_of "$out")"
  assert_has_errors "$resp" "$stack parse error"
  assert_no_data "$resp" "$stack parse error"
  no_calls "parse error"
  echo "--- $stack parse error: HTTP $(status_of "$out") ---" >&2

  #    4b. Validation: a field the type does not have.
  source_calls_reset "$url"
  out="$(gql_any "$url" '{ cargo(trackingId: "ABC123") { weight } }')"
  assert_status_in "200 400" "$(status_of "$out")" "$stack unknown field"
  resp="$(body_of "$out")"
  assert_has_errors "$resp" "$stack unknown field"
  assert_no_data "$resp" "$stack unknown field"
  assert_error_message_contains "$resp" "weight" "$stack unknown field"
  no_calls "unknown field"
  echo "--- $stack validation error: HTTP $(status_of "$out") ---" >&2

  #    4c. Validation: a fragment cycle.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { ...A } } fragment A on Cargo { ...B } fragment B on Cargo { ...A }')"
  assert_has_errors "$resp" "$stack fragment cycle"
  assert_no_data "$resp" "$stack fragment cycle"
  no_calls "fragment cycle"

  #    4d. Variable coercion: TrackingId is a string scalar, so 123 is rejected
  #        before any resolver runs.
  source_calls_reset "$url"
  # shellcheck disable=SC2016  # a GraphQL variable, not a shell expansion
  resp="$(gql "$url" 'query($t: TrackingId!) { cargo(trackingId: $t) { trackingId } }' '{"t":123}')"
  assert_has_errors "$resp" "$stack variable coercion"
  assert_no_data "$resp" "$stack variable coercion"
  no_calls "variable coercion"

  #    4e. The Accept header changes the media type, and a request error's
  #        status is recorded for the other type too.
  out="$(post_accepting 'application/graphql-response+json' '{ cargo(trackingId: "ABC123") { weight } }')"
  echo "--- $stack validation error with Accept: application/graphql-response+json: $out ---" >&2
  case "$stack" in
    quarkus) assert_eq "200 application/graphql-response+json" "$out" "$stack status and media type" ;;
    python) assert_eq "200 application/json" "$out" "$stack status and media type" ;;
  esac

  # 5. operationName picks one operation out of a document.
  local two_ops='query A { cargo(trackingId: "ABC123") { trackingId } } query B { cargo(trackingId: "XYZ789") { trackingId } }'
  source_calls_reset "$url"
  resp="$(gql "$url" "$two_ops")"
  case "$stack" in
    quarkus)
      # The specification: with several operations and no operationName the
      # request is rejected before execution.
      assert_has_errors "$resp" "$stack two operations, no operationName"
      assert_no_data "$resp" "$stack two operations, no operationName"
      assert_error_message_contains "$resp" "operation name" "$stack two operations, no operationName"
      no_calls "two operations, no operationName"
      ;;
    python)
      # Strawberry 0.335.0 runs the first operation when no operationName is sent.
      assert_no_errors "$resp" "$stack two operations, no operationName"
      expect "ABC123" '.data.cargo.trackingId' "the first operation ran"
      assert_source_calls_exactly "$(source_calls "$url")" "booking.getCargo:ABC123" "$stack only the first operation ran"
      ;;
  esac
  source_calls_reset "$url"
  resp="$(gql "$url" "$two_ops" '' 'B')"
  assert_no_errors "$resp" "$stack operationName B"
  expect "XYZ789" '.data.cargo.trackingId' "operationName B"
  assert_source_calls_exactly "$(source_calls "$url")" "booking.getCargo:XYZ789" "$stack only operation B ran"

  # 6. A meta field is answered by the engine, not by a source.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ __typename }')"
  assert_no_errors "$resp" "$stack __typename"
  expect "Query" '.data.__typename' "__typename"
  no_calls "__typename"

  # 7. The custom scalars are real scalars in the live schema and carry the
  #     canonical @specifiedBy URL (none for TrackingId). The SDL diff covers
  #     types, fields and arguments; this loop checks specifiedByURL, with one
  #     __type per request.
  local scalar
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016  # a GraphQL variable, not a shell expansion
    resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    expect "SCALAR" '.data.__type.kind' "$scalar kind"
    case "$scalar" in
      UnLocode) expect "https://unece.org/trade/uncefact/unlocode" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      DateTime) expect "https://www.rfc-editor.org/rfc/rfc3339" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      *) assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL" ;;
    esac
  done

  # 8. The live schema conforms to the canonical SDL (slice). The debug
  #    endpoints are plain HTTP resources, so they add nothing to it.
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"

  echo "=== $stack: execution-model check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8160/graphql"
run_stack_check "python" "http://localhost:8161/graphql"

echo
echo "PASS - Ch6 The execution model: Quarkus (SmallRye GraphQL, Mutiny Uni) and" \
     "Python (Strawberry, async def) both call only the sources a selection names," \
     "resolve a parent before its children, run sibling fields at the same time," \
     "stop a malformed or invalid request before any source is called, and both" \
     "conform to the canonical SDL."

# Explicit teardown in addition to lib.sh's EXIT trap (belt-and-suspenders);
# compose_down is idempotent/safe to call twice.
compose_down "$COMPOSE_FILE" "$PROJECT"
