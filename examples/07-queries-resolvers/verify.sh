#!/usr/bin/env bash
# examples/07-queries-resolvers/verify.sh
#
# Ch7 Queries and resolvers: both stacks resolve every source-backed field
# asynchronously (each source call takes 250 ms) and log every source call,
# and Cargo.delivery is DERIVED from the handling events and the itinerary
# instead of stored. The checks read the source-call log from
# /debug/source-calls and assert ORDER and OVERLAP only, never a duration:
# the resolver chain (parent value, child arguments, source keys), the derived
# Delivery against the values Chapter 3 served as constants, default
# resolvers, variables with defaults, aliases, fragments, @include and @skip,
# the per-request id, and the repeated fetch a resolver-per-field graph makes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch07-resolvers"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# expect_json <expected-json> <json-path> <context> — assert an object, a
# boolean or a null of $resp by parsed equality.
expect_json() {
  assert_json_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# print_log <calls-json> — the source-call log as start and end offsets, for
# the "On the wire" section.
print_log() {
  python3 -I -c '
import json, sys
calls = json.load(sys.stdin)["calls"]
t0 = calls[0]["startMs"]
for c in calls:
    print("%-9s %-13s %-7s start +%4d  end +%4d" % (c["source"], c["op"], c["key"], c["startMs"] - t0, c["endMs"] - t0))
' <<<"$1" >&2
}

# The helpers above read stack, url and resp from this function's scope.
run_stack_check() {
  local stack="$1" url="$2" resp calls

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. The resolver chain: the parent value feeds the child's arguments, and
  #    the child's arguments are the source keys. The cargo comes from
  #    booking, its itinerary from routing, each leg's voyage number from the
  #    itinerary, and the two voyage lookups, one per list item, run together.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { itinerary { legs { voyage { number } } } } }')"
  assert_no_errors "$resp" "$stack resolver chain"
  expect "V100S" '.data.cargo.itinerary.legs.0.voyage.number' "leg 0 voyage"
  expect "V200E" '.data.cargo.itinerary.legs.1.voyage.number' "leg 1 voyage"
  calls="$(source_calls "$url")"
  assert_source_calls_exactly "$calls" \
    "booking.getCargo:ABC123,routing.getItinerary:ABC123,voyage.getVoyage:V100S,voyage.getVoyage:V200E" \
    "$stack the chain's four calls"
  assert_calls_ordered "$calls" booking.getCargo:ABC123 routing.getItinerary:ABC123 "$stack cargo before itinerary"
  assert_calls_ordered "$calls" routing.getItinerary:ABC123 voyage.getVoyage:V100S "$stack itinerary before voyage V100S"
  assert_calls_ordered "$calls" routing.getItinerary:ABC123 voyage.getVoyage:V200E "$stack itinerary before voyage V200E"
  assert_calls_overlap "$calls" voyage.getVoyage:V100S voyage.getVoyage:V200E "$stack list items resolve together"
  # 8a. One request id on every call of the chain.
  assert_single_request "$calls" "$stack one request id for every call"
  echo "--- $stack source-call log for the resolver chain ---" >&2
  print_log "$calls"

  # 2. Delivery is derived. For ABC123 (RECEIVE then LOAD on V100S) and XYZ789
  #    (no events) the derivation yields exactly the values Chapter 3 served
  #    as stored constants, and costs a handling call and a routing call.
  local delivery='delivery { transportStatus routingStatus misdirected lastKnownLocation { unLocode } currentVoyage { number } estimatedTimeOfArrival nextExpectedActivity { type location { unLocode } voyage { number } } }'
  source_calls_reset "$url"
  resp="$(gql "$url" "{ cargo(trackingId: \"ABC123\") { $delivery } }")"
  assert_no_errors "$resp" "$stack derived delivery ABC123"
  expect_json '{"transportStatus":"ONBOARD_CARRIER","routingStatus":"ROUTED","misdirected":false,"lastKnownLocation":{"unLocode":"USNYC"},"currentVoyage":{"number":"V100S"},"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V100S"}}}' \
    '.data.cargo.delivery' "derived delivery ABC123"
  calls="$(source_calls "$url")"
  assert_source_calls_exactly "$calls" \
    "booking.getCargo:ABC123,routing.getItinerary:ABC123,handling.listEvents:ABC123" \
    "$stack delivery calls handling and routing"
  assert_calls_ordered "$calls" booking.getCargo:ABC123 handling.listEvents:ABC123 "$stack cargo before its events"
  assert_calls_overlap "$calls" routing.getItinerary:ABC123 handling.listEvents:ABC123 "$stack the derivation's inputs are fetched together"

  source_calls_reset "$url"
  resp="$(gql "$url" "{ cargo(trackingId: \"XYZ789\") { $delivery } }")"
  assert_no_errors "$resp" "$stack derived delivery XYZ789"
  expect_json '{"transportStatus":"NOT_RECEIVED","routingStatus":"NOT_ROUTED","misdirected":false,"lastKnownLocation":null,"currentVoyage":null,"estimatedTimeOfArrival":null,"nextExpectedActivity":{"type":"RECEIVE","location":{"unLocode":"SGSIN"},"voyage":null}}' \
    '.data.cargo.delivery' "derived delivery XYZ789"
  assert_source_calls_exactly "$(source_calls "$url")" \
    "booking.getCargo:XYZ789,routing.getItinerary:XYZ789,handling.listEvents:XYZ789" \
    "$stack XYZ789 delivery calls"

  # 3. A default resolver reads a property of the parent: description is in
  #    the booking record, so booking is the only source called. A cargo that
  #    does not exist is null, not an error.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { description } }')"
  assert_no_errors "$resp" "$stack default resolver"
  expect "Palletized electronics" '.data.cargo.description' "cargo.description"
  assert_source_calls_exactly "$(source_calls "$url")" "booking.getCargo:ABC123" "$stack description costs no further call"
  resp="$(gql "$url" '{ cargo(trackingId: "NOPE99") { trackingId } }')"
  assert_no_errors "$resp" "$stack unknown cargo"
  assert_null_at "$resp" '.data.cargo' "$stack unknown cargo is null"

  # 4. A variable with a default value; no variables are sent.
  # shellcheck disable=SC2016  # a GraphQL variable, not a shell expansion
  resp="$(gql "$url" 'query($t: TrackingId! = "ABC123") { cargo(trackingId: $t) { trackingId } }')"
  assert_no_errors "$resp" "$stack variable default"
  expect "ABC123" '.data.cargo.trackingId' "default applied"
  # shellcheck disable=SC2016
  resp="$(gql "$url" 'query($t: TrackingId! = "ABC123") { cargo(trackingId: $t) { trackingId } }' '{"t":"XYZ789"}')"
  expect "XYZ789" '.data.cargo.trackingId' "a supplied value wins over the default"

  # 5. Aliases: the same field with two arguments in one round trip.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ ny: location(unLocode: "USNYC") { name } rtm: location(unLocode: "NLRTM") { name } }')"
  assert_no_errors "$resp" "$stack aliases"
  expect "New York" '.data.ny.name' "alias ny"
  expect "Rotterdam" '.data.rtm.name' "alias rtm"
  calls="$(source_calls "$url")"
  assert_calls_overlap "$calls" location.getLocation:USNYC location.getLocation:NLRTM "$stack aliased root fields overlap"

  # 6. A named fragment reused on origin and destination, and an inline
  #    fragment under node(id:).
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { origin { ...Place } destination { ...Place } } } fragment Place on Location { unLocode name country }')"
  assert_no_errors "$resp" "$stack named fragment"
  expect_json '{"unLocode":"USNYC","name":"New York","country":"US"}' '.data.cargo.origin' "origin through Place"
  expect_json '{"unLocode":"NLRTM","name":"Rotterdam","country":"NL"}' '.data.cargo.destination' "destination through Place"
  resp="$(gql "$url" '{ node(id: "loc_NLRTM") { __typename ... on Location { name } } }')"
  assert_no_errors "$resp" "$stack inline fragment"
  expect_json '{"__typename":"Location","name":"Rotterdam"}' '.data.node' "inline fragment under node"

  # 7. @include and @skip prune a field before it is resolved. The only
  #    handling call comes from delivery; the only routing calls come from
  #    delivery (its input) or itinerary (the field), never both when one is pruned.
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  local pruned='query($full: Boolean!) { cargo(trackingId: "ABC123") { trackingId itinerary @include(if: $full) { legs { loadTime } } delivery @skip(if: $full) { transportStatus } } }'
  source_calls_reset "$url"
  resp="$(gql "$url" "$pruned" '{"full":false}')"
  assert_no_errors "$resp" "$stack full=false"
  assert_absent "$resp" '.data.cargo.itinerary' "$stack full=false prunes itinerary"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "full=false keeps delivery"
  calls="$(source_calls "$url")"
  assert_source_calls_exactly "$calls" \
    "booking.getCargo:ABC123,routing.getItinerary:ABC123,handling.listEvents:ABC123" \
    "$stack full=false calls"
  echo "--- $stack source-call log for full=false ---" >&2
  print_log "$calls"
  source_calls_reset "$url"
  resp="$(gql "$url" "$pruned" '{"full":true}')"
  assert_no_errors "$resp" "$stack full=true"
  assert_absent "$resp" '.data.cargo.delivery' "$stack full=true prunes delivery"
  expect "2026-10-01T08:00:00Z" '.data.cargo.itinerary.legs.0.loadTime' "full=true keeps itinerary"
  calls="$(source_calls "$url")"
  assert_source_calls_exactly "$calls" "booking.getCargo:ABC123,routing.getItinerary:ABC123" "$stack full=true calls"
  assert_source_call_count "$calls" handling '*' 0 "$stack handling not called when delivery is skipped"
  echo "--- $stack source-call log for full=true ---" >&2
  print_log "$calls"

  # 8. Request context: a second request, with no reset between, has its own id.
  gql "$url" '{ location(unLocode: "DEHAM") { name } }' >/dev/null
  assert_distinct_requests "$(source_calls "$url")" "$stack a second request has its own id"

  # 9. The repeated fetch: nothing caches within a request. Two aliases of
  #    Leg.voyage over two legs are four voyage lookups, two of them for the
  #    same key. Selecting itinerary and delivery together asks routing twice.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { itinerary { legs { a: voyage { number } b: voyage { number } } } } }')"
  assert_no_errors "$resp" "$stack repeated fetch"
  expect "V100S" '.data.cargo.itinerary.legs.0.b.number' "alias b on leg 0"
  calls="$(source_calls "$url")"
  assert_source_call_count "$calls" voyage getVoyage 4 "$stack four voyage lookups for two legs and two aliases"
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { itinerary { finalArrivalDate } delivery { transportStatus } } }')"
  assert_no_errors "$resp" "$stack itinerary and delivery together"
  assert_source_call_count "$(source_calls "$url")" routing getItinerary 2 "$stack the itinerary is fetched by both fields"

  # 10. Root fields with arguments, and a not-found that is null.
  resp="$(gql "$url" '{ voyage(voyageNumber: "V100S") { schedule { departureLocation { unLocode } arrivalTime } } }')"
  assert_no_errors "$resp" "$stack voyage"
  expect "USNYC" '.data.voyage.schedule.0.departureLocation.unLocode' "departure location"
  expect "2026-10-09T14:00:00Z" '.data.voyage.schedule.0.arrivalTime' "arrival time"
  resp="$(gql "$url" '{ voyage(voyageNumber: "V999X") { number } }')"
  assert_no_errors "$resp" "$stack unknown voyage"
  assert_null_at "$resp" '.data.voyage' "$stack unknown voyage is null"

  # 11. The custom scalars are real scalars in the live schema and carry the
  #      canonical @specifiedBy URL (none for TrackingId). The SDL diff covers
  #      types, fields and arguments; this loop checks specifiedByURL, with one
  #      __type per request.
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

  # 12. The live schema conforms to the canonical SDL (slice).
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"

  echo "=== $stack: queries-and-resolvers check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8170/graphql"
run_stack_check "python" "http://localhost:8171/graphql"

echo
echo "PASS - Ch7 Queries and resolvers: Quarkus (SmallRye GraphQL, Mutiny Uni) and" \
     "Python (Strawberry, async def) both resolve a parent before its children and" \
     "key each source call from the parent's data, derive Cargo.delivery from the" \
     "handling events and the itinerary (the values Chapter 3 stored), prune fields" \
     "with @include and @skip before any source is called, tag every call of a request" \
     "with one id, and conform to the canonical SDL."

# Explicit teardown in addition to lib.sh's EXIT trap (belt-and-suspenders);
# compose_down is idempotent/safe to call twice.
compose_down "$COMPOSE_FILE" "$PROJECT"
