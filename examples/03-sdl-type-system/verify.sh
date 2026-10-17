#!/usr/bin/env bash
# examples/03-sdl-type-system/verify.sh
#
# Ch3 SDL and the type system: both the Quarkus (SmallRye GraphQL) and the
# Python (Strawberry) stack build the full object graph of the tracking view
# code-first from an in-memory seed and serve it as a slice of the canonical
# SDL in contracts/schema/. The checks prove the type system on the wire:
# scalars (including DateTime), enums, objects, the Node interface and its
# dispatch, validation of a selection against the types, and introspection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch03-sdl"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# Every field this chapter serves, selected from the seed cargo ABC123.
# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
CARGO_QUERY='query Cargo($t: TrackingId!) {
  cargo(trackingId: $t) {
    __typename
    id
    trackingId
    description
    origin { unLocode }
    destination { unLocode }
    routeSpecification {
      origin { unLocode }
      destination { unLocode }
      arrivalDeadline
    }
    itinerary {
      finalArrivalDate
      legs {
        voyage { id number }
        loadLocation { unLocode }
        unloadLocation { unLocode }
        loadTime
        unloadTime
      }
    }
    delivery {
      transportStatus
      routingStatus
      misdirected
      lastKnownLocation { unLocode }
      currentVoyage { number }
      estimatedTimeOfArrival
      nextExpectedActivity {
        type
        location { unLocode }
        voyage { number }
      }
    }
  }
}'

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# enum_names <type> — the enum value names of a type, sorted. SmallRye lists
# enum values alphabetically while Strawberry keeps declaration order, so the
# set is compared, not the order.
enum_names() {
  local r
  # shellcheck disable=SC2016
  r="$(gql "$url" 'query Enum($n: String!) { __type(name: $n) { kind enumValues { name } } }' "{\"n\":\"$1\"}")" || return 1
  # Called inside $(...), where set -e does not apply: return explicitly so a
  # wrong kind prints nothing and the caller's comparison fails.
  assert_eq "ENUM" "$(json_field '.data.__type.kind' <<<"$r")" "$stack $1 kind" || return 1
  python3 -I -c '
import json, sys
print(",".join(sorted(v["name"] for v in json.load(sys.stdin)["data"]["__type"]["enumValues"])))
' <<<"$r"
}

# check_node <id> <fragment-selection> <expected __typename> <expected value> <json-path>
check_node() {
  # shellcheck disable=SC2016
  resp="$(gql "$url" 'query Node($i: ID!) { node(id: $i) { __typename '"$2"' } }' "{\"i\":\"$1\"}")"
  assert_no_errors "$resp" "$stack node($1)"
  assert_eq "$3" "$(json_field '.data.node.__typename' <<<"$resp")" "$stack node($1).__typename"
  assert_eq "$4" "$(json_field "$5" <<<"$resp")" "$stack node($1) $5"
}

# The helpers above read stack, url and resp from this function's scope.
run_stack_check() {
  local stack="$1" url="$2" resp

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. ABC123: every served field has its exact seed value, DateTime as Z strings
  #    and enums as their names.
  resp="$(gql "$url" "$CARGO_QUERY" '{"t":"ABC123"}')"
  assert_no_errors "$resp" "$stack cargo(ABC123)"
  expect "Cargo" '.data.cargo.__typename' "cargo.__typename"
  expect "cargo_ABC123" '.data.cargo.id' "cargo.id"
  expect "ABC123" '.data.cargo.trackingId' "cargo.trackingId"
  expect "Palletized electronics" '.data.cargo.description' "cargo.description"
  expect "USNYC" '.data.cargo.origin.unLocode' "cargo.origin"
  expect "NLRTM" '.data.cargo.destination.unLocode' "cargo.destination"
  expect "USNYC" '.data.cargo.routeSpecification.origin.unLocode' "routeSpecification.origin"
  expect "NLRTM" '.data.cargo.routeSpecification.destination.unLocode' "routeSpecification.destination"
  expect "2026-10-15T00:00:00Z" '.data.cargo.routeSpecification.arrivalDeadline' "routeSpecification.arrivalDeadline"
  assert_eq "2" "$(json_len '.data.cargo.itinerary.legs' <<<"$resp")" "$stack itinerary.legs length"
  expect "2026-10-11T18:00:00Z" '.data.cargo.itinerary.finalArrivalDate' "itinerary.finalArrivalDate"
  expect "voy_V100S" '.data.cargo.itinerary.legs.0.voyage.id' "leg 0 voyage.id"
  expect "V100S" '.data.cargo.itinerary.legs.0.voyage.number' "leg 0 voyage"
  expect "USNYC" '.data.cargo.itinerary.legs.0.loadLocation.unLocode' "leg 0 load"
  expect "DEHAM" '.data.cargo.itinerary.legs.0.unloadLocation.unLocode' "leg 0 unload"
  expect "2026-10-01T08:00:00Z" '.data.cargo.itinerary.legs.0.loadTime' "leg 0 loadTime"
  expect "2026-10-09T14:00:00Z" '.data.cargo.itinerary.legs.0.unloadTime' "leg 0 unloadTime"
  expect "V200E" '.data.cargo.itinerary.legs.1.voyage.number' "leg 1 voyage"
  expect "DEHAM" '.data.cargo.itinerary.legs.1.loadLocation.unLocode' "leg 1 load"
  expect "NLRTM" '.data.cargo.itinerary.legs.1.unloadLocation.unLocode' "leg 1 unload"
  expect "2026-10-10T06:00:00Z" '.data.cargo.itinerary.legs.1.loadTime' "leg 1 loadTime"
  expect "2026-10-11T18:00:00Z" '.data.cargo.itinerary.legs.1.unloadTime' "leg 1 unloadTime"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "delivery.transportStatus"
  expect "ROUTED" '.data.cargo.delivery.routingStatus' "delivery.routingStatus"
  # The whole object, parsed: misdirected is the JSON boolean false (not the
  # string "false"), and the enums are JSON strings.
  assert_json_eq '{"transportStatus":"ONBOARD_CARRIER","routingStatus":"ROUTED","misdirected":false,"lastKnownLocation":{"unLocode":"USNYC"},"currentVoyage":{"number":"V100S"},"estimatedTimeOfArrival":"2026-10-11T18:00:00Z","nextExpectedActivity":{"type":"UNLOAD","location":{"unLocode":"DEHAM"},"voyage":{"number":"V100S"}}}' \
    "$(json_field '.data.cargo.delivery' <<<"$resp")" "$stack delivery object"
  expect "USNYC" '.data.cargo.delivery.lastKnownLocation.unLocode' "delivery.lastKnownLocation"
  expect "V100S" '.data.cargo.delivery.currentVoyage.number' "delivery.currentVoyage"
  expect "2026-10-11T18:00:00Z" '.data.cargo.delivery.estimatedTimeOfArrival' "delivery.estimatedTimeOfArrival"
  expect "UNLOAD" '.data.cargo.delivery.nextExpectedActivity.type' "nextExpectedActivity.type"
  expect "DEHAM" '.data.cargo.delivery.nextExpectedActivity.location.unLocode' "nextExpectedActivity.location"
  expect "V100S" '.data.cargo.delivery.nextExpectedActivity.voyage.number' "nextExpectedActivity.voyage"

  # 2. XYZ789: absence is data. No itinerary, nothing derived yet, and no errors.
  resp="$(gql "$url" "$CARGO_QUERY" '{"t":"XYZ789"}')"
  assert_no_errors "$resp" "$stack cargo(XYZ789)"
  expect "XYZ789" '.data.cargo.trackingId' "cargo.trackingId"
  expect "2026-11-20T00:00:00Z" '.data.cargo.routeSpecification.arrivalDeadline' "routeSpecification.arrivalDeadline"
  assert_null_at "$resp" '.data.cargo.itinerary' "$stack itinerary is null"
  expect "NOT_RECEIVED" '.data.cargo.delivery.transportStatus' "delivery.transportStatus"
  expect "NOT_ROUTED" '.data.cargo.delivery.routingStatus' "delivery.routingStatus"
  assert_null_at "$resp" '.data.cargo.delivery.lastKnownLocation' "$stack lastKnownLocation is null"
  assert_null_at "$resp" '.data.cargo.delivery.currentVoyage' "$stack currentVoyage is null"
  assert_null_at "$resp" '.data.cargo.delivery.estimatedTimeOfArrival' "$stack estimatedTimeOfArrival is null"
  expect "RECEIVE" '.data.cargo.delivery.nextExpectedActivity.type' "nextExpectedActivity.type"
  expect "SGSIN" '.data.cargo.delivery.nextExpectedActivity.location.unLocode' "nextExpectedActivity.location"
  assert_null_at "$resp" '.data.cargo.delivery.nextExpectedActivity.voyage' "$stack nextExpectedActivity.voyage is null"

  # 3. The other root fields. A lookup that finds nothing is null, not an error.
  # shellcheck disable=SC2016
  resp="$(gql "$url" 'query Loc($c: UnLocode!) { location(unLocode: $c) { __typename id unLocode name country } }' '{"c":"DEHAM"}')"
  assert_no_errors "$resp" "$stack location(DEHAM)"
  expect "Location" '.data.location.__typename' "location.__typename"
  expect "loc_DEHAM" '.data.location.id' "location.id"
  expect "Hamburg" '.data.location.name' "location.name"
  expect "DE" '.data.location.country' "location.country"

  # shellcheck disable=SC2016
  resp="$(gql "$url" 'query Voy($n: String!) { voyage(voyageNumber: $n) { id number schedule { departureLocation { unLocode } arrivalLocation { unLocode } departureTime arrivalTime } } }' '{"n":"V100S"}')"
  assert_no_errors "$resp" "$stack voyage(V100S)"
  expect "voy_V100S" '.data.voyage.id' "voyage.id"
  expect "V100S" '.data.voyage.number' "voyage.number"
  expect "USNYC" '.data.voyage.schedule.0.departureLocation.unLocode' "schedule[0].departureLocation"
  expect "DEHAM" '.data.voyage.schedule.0.arrivalLocation.unLocode' "schedule[0].arrivalLocation"
  expect "2026-10-01T08:00:00Z" '.data.voyage.schedule.0.departureTime' "schedule[0].departureTime"
  expect "2026-10-09T14:00:00Z" '.data.voyage.schedule.0.arrivalTime' "schedule[0].arrivalTime"

  resp="$(gql "$url" '{ location(unLocode: "ZZZZZ") { id } }')"
  assert_no_errors "$resp" "$stack location(ZZZZZ)"
  assert_null_at "$resp" '.data.location' "$stack unknown location is null"
  resp="$(gql "$url" '{ voyage(voyageNumber: "V999X") { id } }')"
  assert_no_errors "$resp" "$stack voyage(V999X)"
  assert_null_at "$resp" '.data.voyage' "$stack unknown voyage is null"

  # 4. Node dispatch: one id space, three implementing types. A fragment on a
  #    type the object is not contributes nothing.
  check_node "loc_NLRTM" '... on Location { unLocode }' "Location" "NLRTM" '.data.node.unLocode'
  check_node "cargo_ABC123" '... on Cargo { trackingId }' "Cargo" "ABC123" '.data.node.trackingId'
  check_node "voy_V200E" '... on Voyage { number }' "Voyage" "V200E" '.data.node.number'
  resp="$(gql "$url" '{ node(id: "nope") { __typename } }')"
  assert_no_errors "$resp" "$stack node(nope)"
  assert_null_at "$resp" '.data.node' "$stack unknown id is null"
  resp="$(gql "$url" '{ node(id: "loc_NLRTM") { __typename ... on Cargo { trackingId } } }')"
  assert_no_errors "$resp" "$stack node(loc_NLRTM) with a non-matching fragment"
  assert_json_eq '{"__typename":"Location"}' "$(json_field '.data.node' <<<"$resp")" "$stack non-matching fragment adds nothing"

  # 5. Validation checks a selection against the types before anything runs:
  #    HTTP 200, top-level errors, no data.
  resp="$(gql "$url" '{ node(id: "loc_NLRTM") { unLocode } }')"
  assert_has_errors "$resp" "$stack field not on the interface"
  assert_no_data "$resp" "$stack field not on the interface"
  assert_error_message_contains "$resp" "unLocode" "$stack field not on the interface"

  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { origin } }')"
  assert_has_errors "$resp" "$stack object field without a subselection"
  assert_no_data "$resp" "$stack object field without a subselection"
  assert_error_message_contains "$resp" "origin" "$stack object field without a subselection"

  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { trackingId { x } } }')"
  assert_has_errors "$resp" "$stack subselection on a scalar"
  assert_no_data "$resp" "$stack subselection on a scalar"

  # 5b. Scalar input coercion: UnLocode is a string scalar, so a number is
  #     rejected, as a literal and as a variable, and no data comes back.
  resp="$(gql "$url" '{ location(unLocode: 123) { id } }')"
  assert_has_errors "$resp" "$stack UnLocode given a number literal"
  assert_no_data "$resp" "$stack UnLocode given a number literal"
  # shellcheck disable=SC2016
  resp="$(gql "$url" 'query Loc($c: UnLocode!) { location(unLocode: $c) { id } }' '{"c":123}')"
  assert_has_errors "$resp" "$stack UnLocode given a number variable"
  assert_no_data "$resp" "$stack UnLocode given a number variable"

  # 6. Introspection. The enums are closed sets of names; SmallRye lists enum
  #    values alphabetically and Strawberry in declaration order, so compare
  #    the sets. Node is an interface with three implementers. One __type per
  #    request: graphql-java's introspection guard accepts one `__type` field
  #    per request.
  assert_eq "CLAIMED,IN_PORT,NOT_RECEIVED,ONBOARD_CARRIER,UNKNOWN" "$(enum_names TransportStatus)" "$stack TransportStatus values"
  assert_eq "MISROUTED,NOT_ROUTED,ROUTED" "$(enum_names RoutingStatus)" "$stack RoutingStatus values"
  assert_eq "CLAIM,CUSTOMS,LOAD,RECEIVE,UNLOAD" "$(enum_names HandlingEventType)" "$stack HandlingEventType values"

  # shellcheck disable=SC2016
  resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind possibleTypes { name } } }' '{"n":"Node"}')"
  assert_no_errors "$resp" "$stack Node introspection"
  expect "INTERFACE" '.data.__type.kind' "Node kind"
  assert_eq "Cargo,Location,Voyage" "$(python3 -I -c '
import json, sys
print(",".join(sorted(t["name"] for t in json.load(sys.stdin)["data"]["__type"]["possibleTypes"])))
' <<<"$resp")" "$stack Node possibleTypes"

  # The custom scalars have kind SCALAR in the live schema and carry the
  # canonical @specifiedBy URL (none for TrackingId). The live schema is the
  # source for specifiedByURL, and this loop reads it from introspection.
  local scalar specified_by
  for scalar in TrackingId UnLocode DateTime; do
    case "$scalar" in
      UnLocode) specified_by="https://unece.org/trade/uncefact/unlocode" ;;
      DateTime) specified_by="https://www.rfc-editor.org/rfc/rfc3339" ;;
      *) specified_by="null" ;;
    esac
    # shellcheck disable=SC2016
    resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    expect "SCALAR" '.data.__type.kind' "$scalar kind"
    if [[ "$specified_by" == "null" ]]; then
      assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL"
    else
      expect "$specified_by" '.data.__type.specifiedByURL' "$scalar specifiedByURL"
    fi
  done

  # 7. The live schema conforms to the canonical SDL (slice).
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"

  echo "=== $stack: type-system check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8130/graphql"
run_stack_check "python" "http://localhost:8131/graphql"

echo
echo "PASS - Ch3 SDL and the type system: Quarkus (SmallRye GraphQL) and Python" \
     "(Strawberry) both serve the cargo graph from the same seed with identical" \
     "values, DateTime on the wire as UTC Z strings, enums as names, Node dispatch" \
     "by id, and validation against the types, and both conform to the canonical SDL."

# Explicit teardown in addition to lib.sh's EXIT trap (belt-and-suspenders);
# compose_down is idempotent/safe to call twice.
compose_down "$COMPOSE_FILE" "$PROJECT"
