#!/usr/bin/env bash
# examples/08-mutations/verify.sh
#
# Ch8 Mutations and input types: Mutation.registerHandlingEvent on both stacks.
# The handling store is in memory and carries state forward, so the steps run
# in a fixed order and every event id is asserted where it is created: a
# skipped or reordered step fails at once. Each run needs a fresh store, which
# compose_up gives (the stack is built and started here and removed on exit).
#
# Steps: coercion failures are request errors (no data, no write); domain
# failures are userErrors with a code and a field path (no write); a success
# returns the event and the cargo with its delivery re-derived; idempotent
# replay; two aliased mutation fields run in order, seen in the source-call
# log and in the first payload's state; no key means duplicates; a mutation
# over GET is refused; eight parallel requests with one key record one event.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch08-mutations"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
TMP_DIR="$(mktemp -d)"

# One mutation document for every case; the input travels as a variable.
# shellcheck disable=SC2016  # a GraphQL variable, not a shell expansion
MUTATION='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id type trackingId completionTime registrationTime location { unLocode } voyage { number } } cargo { trackingId delivery { transportStatus lastKnownLocation { unLocode } currentVoyage { number } estimatedTimeOfArrival nextExpectedActivity { type location { unLocode } voyage { number } } } } userErrors { code message field } } }'

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# expect_json <expected-json> <json-path> <context> — assert an object, a
# boolean or a null of $resp by parsed equality.
expect_json() {
  assert_json_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# input_of <json-fields> — wrap the fields of a RegisterHandlingEventInput as
# the variables of MUTATION.
input_of() {
  printf '{"i":{%s}}' "$1"
}

# appends <calls-json> — how many appendEvent calls (writes) the log holds.
appends() {
  python3 -I -c '
import json, sys
print(sum(1 for c in json.load(sys.stdin)["calls"] if c["source"] == "handling" and c["op"] == "appendEvent"))
' <<<"$1"
}

# user_errors <json> — the userErrors of the mutation as [{code, field}], and a
# failure if any message is empty.
user_errors() {
  python3 -I -c '
import json, sys
errors = json.load(sys.stdin)["data"]["registerHandlingEvent"]["userErrors"]
if any(not e["message"] for e in errors):
    sys.exit("empty userError message")
print(json.dumps([{"code": e["code"], "field": e["field"]} for e in errors]))
' <<<"$1"
}

# print_log <calls-json> — the handling calls of the log as start and end
# offsets, for the "On the wire" section.
print_log() {
  python3 -I -c '
import json, sys
calls = [c for c in json.load(sys.stdin)["calls"] if c["source"] == "handling"]
t0 = calls[0]["startMs"]
for c in calls:
    print("%-9s %-21s %-6s start +%5d  end +%5d" % (c["source"], c["op"], c["key"], c["startMs"] - t0, c["endMs"] - t0))
' <<<"$1" >&2
}

# A request that must fail before any write: errors, no data, and not one
# source call at all (the resolver never ran).
expect_coercion_failure() {
  local fields="$1" label="$2"
  source_calls_reset "$url"
  resp="$(gql "$url" "$MUTATION" "$(input_of "$fields")")"
  assert_has_errors "$resp" "$stack coercion: $label"
  assert_no_data "$resp" "$stack coercion: $label has no data"
  assert_eq "0" "$(source_calls "$url" | json_len .calls)" "$stack coercion: $label calls no source"
}

# A request that must come back as userErrors: no top-level errors, a null
# event and cargo, the exact codes and field paths, and no append.
expect_user_errors() {
  local fields="$1" expected="$2" label="$3"
  source_calls_reset "$url"
  resp="$(gql "$url" "$MUTATION" "$(input_of "$fields")")"
  assert_no_errors "$resp" "$stack userErrors: $label"
  assert_null_at "$resp" '.data.registerHandlingEvent.handlingEvent' "$stack userErrors: $label has no event"
  assert_null_at "$resp" '.data.registerHandlingEvent.cargo' "$stack userErrors: $label has no cargo"
  assert_json_eq "$expected" "$(user_errors "$resp")" "$stack userErrors: $label"
  assert_eq "0" "$(appends "$(source_calls "$url")")" "$stack userErrors: $label writes nothing"
}

# The helpers above read stack, url and resp from this function's scope.
# run_stack_check <stack> <url> <expected status of a mutation over GET>
run_stack_check() {
  local stack="$1" url="$2" get_status="$3" resp calls out i
  local abc='"trackingId":"ABC123"'

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. Coercion: the variable or literal is not a valid value of its type. The
  #    response is errors with no data, and the resolver never runs.
  expect_coercion_failure "$abc,\"location\":\"DEHAM\",\"completionTime\":\"2026-10-09T15:00:00Z\"" "type missing"
  expect_coercion_failure "$abc,\"type\":\"TELEPORT\",\"location\":\"DEHAM\",\"completionTime\":\"2026-10-09T15:00:00Z\"" "type TELEPORT"
  expect_coercion_failure "$abc,\"type\":\"RECEIVE\",\"location\":123,\"completionTime\":\"2026-10-09T15:00:00Z\"" "location 123"
  expect_coercion_failure "$abc,\"type\":\"RECEIVE\",\"location\":\"USNYC\",\"completionTime\":\"yesterday\"" "completionTime yesterday"
  expect_coercion_failure "$abc,\"type\":\"RECEIVE\",\"location\":\"USNYC\",\"completionTime\":\"2026-10-09T15:00:00Z\",\"weightKg\":1" "unknown field weightKg"

  # 2. Domain failures: the input is well formed but breaks a rule. Every
  #    applicable failure is reported, in the order trackingId, location,
  #    voyageNumber, completionTime.
  expect_user_errors "$abc,\"type\":\"LOAD\",\"location\":\"DEHAM\",\"completionTime\":\"2026-10-09T15:00:00Z\"" \
    '[{"code":"VOYAGE_REQUIRED","field":["input","voyageNumber"]}]' "LOAD without a voyage"
  expect_user_errors "$abc,\"type\":\"RECEIVE\",\"location\":\"USNYC\",\"voyageNumber\":\"V100S\",\"completionTime\":\"2026-09-30T16:00:00Z\"" \
    '[{"code":"VOYAGE_NOT_ALLOWED","field":["input","voyageNumber"]}]' "RECEIVE with a voyage"
  expect_user_errors "$abc,\"type\":\"LOAD\",\"location\":\"DEHAM\",\"voyageNumber\":\"V999X\",\"completionTime\":\"2026-10-09T15:00:00Z\"" \
    '[{"code":"UNKNOWN_VOYAGE","field":["input","voyageNumber"]}]' "unknown voyage"
  expect_user_errors "$abc,\"type\":\"CUSTOMS\",\"location\":\"NLRTM\",\"completionTime\":\"2099-01-01T00:00:00Z\"" \
    '[{"code":"INVALID_COMPLETION_TIME","field":["input","completionTime"]}]' "completion time in the future"
  expect_user_errors '"trackingId":"NOPE99","type":"CUSTOMS","location":"ZZZZZ","completionTime":"2026-10-09T15:00:00Z"' \
    '[{"code":"UNKNOWN_CARGO","field":["input","trackingId"]},{"code":"UNKNOWN_LOCATION","field":["input","location"]}]' \
    "unknown cargo and location, both reported"

  # Ten rejected requests later the store is unchanged: the first new id is
  # still free.
  resp="$(gql "$url" '{ node(id: "evt_3") { __typename } }')"
  assert_no_errors "$resp" "$stack store unchanged"
  assert_null_at "$resp" '.data.node' "$stack rejected requests recorded nothing"

  # 3. Success: UNLOAD at DEHAM on V100S. The payload carries the new event and
  #    the cargo, whose delivery is derived after the write (IN_PORT at
  #    Hamburg, the next expected handling is LOAD on V200E).
  source_calls_reset "$url"
  resp="$(gql "$url" "$MUTATION" "$(input_of "$abc,\"type\":\"UNLOAD\",\"location\":\"DEHAM\",\"voyageNumber\":\"V100S\",\"completionTime\":\"2026-10-09T15:00:00Z\",\"idempotencyKey\":\"k-001\"")")"
  assert_no_errors "$resp" "$stack register evt_3"
  expect "evt_3" '.data.registerHandlingEvent.handlingEvent.id' "new event id"
  expect "UNLOAD" '.data.registerHandlingEvent.handlingEvent.type' "event type"
  expect "ABC123" '.data.registerHandlingEvent.handlingEvent.trackingId' "event trackingId"
  expect "DEHAM" '.data.registerHandlingEvent.handlingEvent.location.unLocode' "event location"
  expect "V100S" '.data.registerHandlingEvent.handlingEvent.voyage.number' "event voyage"
  expect "2026-10-09T15:00:00Z" '.data.registerHandlingEvent.handlingEvent.completionTime' "event completionTime"
  python3 -I -c '
import re, sys
value = sys.argv[1]
sys.exit(0 if re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", value) else "registrationTime is not YYYY-MM-DDTHH:MM:SSZ: " + value)
' "$(json_field '.data.registerHandlingEvent.handlingEvent.registrationTime' <<<"$resp")" || return 1
  expect "ABC123" '.data.registerHandlingEvent.cargo.trackingId' "payload cargo"
  expect_json '{"transportStatus":"IN_PORT","lastKnownLocation":{"unLocode":"DEHAM"},"currentVoyage":null,"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"LOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V200E"}}}' \
    '.data.registerHandlingEvent.cargo.delivery' "re-derived delivery after evt_3"
  expect_json '[]' '.data.registerHandlingEvent.userErrors' "no userErrors on success"
  calls="$(source_calls "$url")"
  assert_eq "1" "$(appends "$calls")" "$stack exactly one append"
  assert_source_call_count "$calls" handling findByIdempotencyKey 1 "$stack one key lookup"
  assert_calls_ordered "$calls" handling.findByIdempotencyKey:k-001 handling.appendEvent:evt_3 "$stack lookup before append"

  # 4. Replay: the same input and key. The original event comes back, and the
  #    store is not touched.
  source_calls_reset "$url"
  resp="$(gql "$url" "$MUTATION" "$(input_of "$abc,\"type\":\"UNLOAD\",\"location\":\"DEHAM\",\"voyageNumber\":\"V100S\",\"completionTime\":\"2026-10-09T15:00:00Z\",\"idempotencyKey\":\"k-001\"")")"
  assert_no_errors "$resp" "$stack replay"
  expect "evt_3" '.data.registerHandlingEvent.handlingEvent.id' "replay returns the original"
  assert_eq "0" "$(appends "$(source_calls "$url")")" "$stack replay writes nothing"
  assert_source_call_count "$(source_calls "$url")" handling findByIdempotencyKey 1 "$stack replay looked the key up"

  # 5. The same key with a different completionTime is still a replay: the
  #    original event, with its original completionTime.
  source_calls_reset "$url"
  resp="$(gql "$url" "$MUTATION" "$(input_of "$abc,\"type\":\"UNLOAD\",\"location\":\"DEHAM\",\"voyageNumber\":\"V100S\",\"completionTime\":\"2026-10-09T16:00:00Z\",\"idempotencyKey\":\"k-001\"")")"
  assert_no_errors "$resp" "$stack replay with a different time"
  expect "evt_3" '.data.registerHandlingEvent.handlingEvent.id' "same key, same event"
  expect "2026-10-09T15:00:00Z" '.data.registerHandlingEvent.handlingEvent.completionTime' "the original completionTime wins"
  assert_eq "0" "$(appends "$(source_calls "$url")")" "$stack second replay writes nothing"

  # 6. Two aliased mutation fields in one document run in order. Two things show
  #    it: the log (a's append ended before b's lookup began) and a's payload
  #    (its delivery is derived before b's event exists).
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  local pair='mutation($a: RegisterHandlingEventInput!, $b: RegisterHandlingEventInput!) {
    a: registerHandlingEvent(input: $a) { handlingEvent { id } cargo { delivery { transportStatus currentVoyage { number } nextExpectedActivity { type location { unLocode } voyage { number } } } } userErrors { code } }
    b: registerHandlingEvent(input: $b) { handlingEvent { id } cargo { delivery { transportStatus lastKnownLocation { unLocode } currentVoyage { number } estimatedTimeOfArrival nextExpectedActivity { type location { unLocode } voyage { number } } } } userErrors { code } }
  }'
  source_calls_reset "$url"
  resp="$(gql "$url" "$pair" "{\"a\":{$abc,\"type\":\"LOAD\",\"location\":\"DEHAM\",\"voyageNumber\":\"V200E\",\"completionTime\":\"2026-10-10T06:30:00Z\",\"idempotencyKey\":\"k-002\"},\"b\":{$abc,\"type\":\"UNLOAD\",\"location\":\"NLRTM\",\"voyageNumber\":\"V200E\",\"completionTime\":\"2026-10-11T18:30:00Z\",\"idempotencyKey\":\"k-003\"}}")"
  assert_no_errors "$resp" "$stack serial pair"
  expect "evt_4" '.data.a.handlingEvent.id' "a recorded first"
  expect "evt_5" '.data.b.handlingEvent.id' "b recorded second"
  expect_json '{"transportStatus":"ONBOARD_CARRIER","currentVoyage":{"number":"V200E"},"nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"NLRTM"},"voyage":{"number":"V200E"}}}' \
    '.data.a.cargo.delivery' "a's delivery has evt_4 and not yet evt_5"
  expect_json '{"transportStatus":"IN_PORT","lastKnownLocation":{"unLocode":"NLRTM"},"currentVoyage":null,"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"CLAIM","location":{"unLocode":"NLRTM"},"voyage":null}}' \
    '.data.b.cargo.delivery' "b's delivery has both"
  assert_eq "a,b" "$(json_keys .data <<<"$resp")" "$stack response keys follow the selection"
  calls="$(source_calls "$url")"
  assert_calls_ordered "$calls" handling.appendEvent:evt_4 handling.appendEvent:evt_5 "$stack append a before append b"
  assert_calls_ordered "$calls" handling.appendEvent:evt_4 handling.findByIdempotencyKey:k-003 "$stack b did not start until a had written"
  assert_eq "2" "$(appends "$calls")" "$stack two appends"
  echo "--- $stack handling log for the serial pair ---" >&2
  print_log "$calls"

  # 7. No key, twice: two events. Without a key nothing identifies a retry.
  for i in 6 7; do
    source_calls_reset "$url"
    resp="$(gql "$url" "$MUTATION" "$(input_of "$abc,\"type\":\"CUSTOMS\",\"location\":\"NLRTM\",\"completionTime\":\"2026-10-12T09:00:00Z\"")")"
    assert_no_errors "$resp" "$stack no key #$i"
    expect "evt_$i" '.data.registerHandlingEvent.handlingEvent.id' "no-key duplicate gets its own id"
    assert_eq "1" "$(appends "$(source_calls "$url")")" "$stack no key #$i appends once"
    assert_source_call_count "$(source_calls "$url")" handling findByIdempotencyKey 0 "$stack no key means no lookup"
  done

  # 8. A mutation over GET is refused, whatever the handler would have done.
  # shellcheck disable=SC2016
  local by_get='mutation { registerHandlingEvent(input: {trackingId: "ABC123", type: CUSTOMS, location: "NLRTM", completionTime: "2026-10-12T09:00:00Z"}) { handlingEvent { id } } }'
  source_calls_reset "$url"
  out="$(gql_get "$url" "$by_get")"
  assert_status_in "$get_status" "$(status_of "$out")" "$stack mutation over GET"
  echo "--- $stack mutation over GET: status $(status_of "$out"), body: $(body_of "$out" | head -c 80) ---" >&2
  assert_eq "0" "$(source_calls "$url" | json_len .calls)" "$stack GET called no source"
  resp="$(gql "$url" '{ node(id: "evt_8") { __typename } }')"
  assert_null_at "$resp" '.data.node' "$stack GET recorded nothing"

  # 9. Node resolves an event id; the inline fragment selects through it.
  resp="$(gql "$url" '{ node(id: "evt_3") { __typename ... on HandlingEvent { type cargo { trackingId } } } }')"
  assert_no_errors "$resp" "$stack node(evt_3)"
  expect_json '{"__typename":"HandlingEvent","type":"UNLOAD","cargo":{"trackingId":"ABC123"}}' '.data.node' "node(evt_3)"

  # 10. Eight parallel requests with one key record one event. They arrive
  #     inside one source window, so their lookups run before the write lands
  #     and miss; the atomic step inside appendEvent is what keeps the others
  #     from writing.
  source_calls_reset "$url"
  for i in 1 2 3 4 5 6 7 8; do
    gql "$url" "$MUTATION" "$(input_of "$abc,\"type\":\"CLAIM\",\"location\":\"NLRTM\",\"completionTime\":\"2026-10-13T09:00:00Z\",\"idempotencyKey\":\"k-par\"")" \
      >"$TMP_DIR/par-$i.json" &
  done
  wait
  for i in 1 2 3 4 5 6 7 8; do
    resp="$(<"$TMP_DIR/par-$i.json")"
    assert_no_errors "$resp" "$stack parallel request $i"
    expect "evt_8" '.data.registerHandlingEvent.handlingEvent.id' "parallel request $i returns the one event"
  done
  calls="$(source_calls "$url")"
  assert_eq "1" "$(appends "$calls")" "$stack eight requests, one append"
  assert_source_call_count "$calls" handling findByIdempotencyKey 8 "$stack all eight looked the key up"
  # The race happened: at least two lookups finished before the one write did,
  # so at least two requests missed and reached appendEvent. Without this the
  # check would also pass if the requests had arrived one after another.
  python3 -I -c '
import json, sys
calls = [c for c in json.load(sys.stdin)["calls"] if c["source"] == "handling"]
written = next(c["endMs"] for c in calls if c["op"] == "appendEvent")
missed = sum(1 for c in calls if c["op"] == "findByIdempotencyKey" and c["endMs"] < written)
sys.exit(0 if missed >= 2 else "only %d lookup(s) ran before the write: no race" % missed)
' <<<"$calls" || return 1
  echo "--- $stack the eight requests raced: at least two lookups missed before the write ---" >&2
  resp="$(gql "$url" '{ node(id: "evt_9") { __typename } }')"
  assert_null_at "$resp" '.data.node' "$stack no ninth event exists"
  echo "--- $stack handling log for eight parallel requests ---" >&2
  python3 -I -c '
import collections, json, sys
calls = [c for c in json.load(sys.stdin)["calls"] if c["source"] == "handling"]
print("   ", dict(collections.Counter(c["op"] for c in calls)), file=sys.stderr)
' <<<"$calls"

  # 11. The input type has no default values. A plain optional field in
  #     Strawberry (`str | None = None`) would print `= null`, which the
  #     conformance diff reports as a default change but does not fail on.
  # shellcheck disable=SC2016
  resp="$(gql "$url" '{ __type(name: "RegisterHandlingEventInput") { kind inputFields { name defaultValue } } }')"
  assert_no_errors "$resp" "$stack input introspection"
  expect "INPUT_OBJECT" '.data.__type.kind' "RegisterHandlingEventInput kind"
  assert_json_eq '[{"name":"completionTime","defaultValue":null},{"name":"idempotencyKey","defaultValue":null},{"name":"location","defaultValue":null},{"name":"trackingId","defaultValue":null},{"name":"type","defaultValue":null},{"name":"voyageNumber","defaultValue":null}]' \
    "$(python3 -I -c '
import json, sys
fields = json.load(sys.stdin)["data"]["__type"]["inputFields"]
print(json.dumps(sorted(fields, key=lambda f: f["name"])))
' <<<"$resp")" "$stack input fields and defaults"

  # 12. The custom scalars are real scalars and carry the canonical
  #     @specifiedBy URL (none for TrackingId). The SDL diff covers types,
  #     fields and arguments; this loop checks specifiedByURL.
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

  # 13. The live schema conforms to the canonical SDL. The Mutation root is
  #     served now; Subscription, cargos and handlingHistory are slice removals.
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"

  echo "=== $stack: mutations check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"
# compose_up registered the EXIT trap that tears the stack down. Chain the
# removal of the scratch directory after it.
trap 'rc=$?; _lib_teardown "$rc"; rm -rf "$TMP_DIR"; exit "$rc"' EXIT

echo
echo "=== Step 2: verify both stacks ==="
# GraphQL-over-HTTP requires a 4xx for a mutation over GET and recommends 405.
# Quarkus answers 405 with no Allow header (RFC 9110 asks for one on a 405);
# Strawberry answers 400.
run_stack_check "quarkus" "http://localhost:8180/graphql" "405"
run_stack_check "python" "http://localhost:8181/graphql" "400"

echo
echo "PASS - Ch8 Mutations and input types: Quarkus (SmallRye GraphQL, @Input record) and" \
     "Python (Strawberry, strawberry.Maybe) both reject malformed input as request errors," \
     "return domain failures as userErrors with codes and field paths, re-derive the" \
     "cargo's delivery in the payload, run aliased mutation fields in order, replay an" \
     "idempotency key to the original event (also under eight parallel requests), refuse" \
     "a mutation over GET, and conform to the canonical SDL."

# Explicit teardown in addition to lib.sh's EXIT trap (belt-and-suspenders);
# compose_down is idempotent/safe to call twice.
compose_down "$COMPOSE_FILE" "$PROJECT"
