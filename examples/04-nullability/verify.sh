#!/usr/bin/env bash
# examples/04-nullability/verify.sh
#
# Ch4 Nullability and null propagation: both stacks serve the Ch3 slice, but
# Leg.voyage, Leg.loadLocation, Leg.unloadLocation and Cargo.delivery are now
# resolvers over sources, and three seeded cargos make a source fail in three
# ways (raise, return null, raise under a non-null field). The checks prove
# what each failure does to the response: which field becomes null, which
# error path is reported, and which part of the response survives.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch04-null"
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

# The selection the fault seeds are queried with: the legs of the itinerary,
# each with a nullable voyage and a non-null load location.
# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
FAULT_QUERY='query Fault($t: TrackingId!) {
  cargo(trackingId: $t) {
    trackingId
    itinerary { legs { loadLocation { unLocode } voyage { number } } }
  }
}'

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# wrapper_chain <type> <field> — the wrapper chain of one field as
# NON_NULL>LIST>NON_NULL>OBJECT(Leg). One __type per request: graphql-java's
# introspection guard accepts one `__type` field per request. Four levels of ofType
# is the depth the longest chain here needs.
wrapper_chain() {
  local r
  # shellcheck disable=SC2016
  r="$(gql "$url" 'query Fields($n: String!) { __type(name: $n) { fields { name type { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } }' "{\"n\":\"$1\"}")" || return 1
  # Called inside $(...), where set -e does not apply: a missing field prints
  # nothing and the caller's comparison fails.
  python3 -I -c '
import json, sys
field = next(f for f in json.load(sys.stdin)["data"]["__type"]["fields"] if f["name"] == sys.argv[1])
kinds, t = [], field["type"]
while t.get("ofType"):
    kinds.append(t["kind"])
    t = t["ofType"]
kinds.append("%s(%s)" % (t["kind"], t["name"]))
print(">".join(kinds))
' "$2" <<<"$r"
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

  # 3. Failure at a nullable field: JKL567's voyage source raises. Leg.voyage is
  #    nullable, so the null stays at the leg and the rest of the leg survives.
  resp="$(gql "$url" "$FAULT_QUERY" '{"t":"JKL567"}')"
  assert_error_count "$resp" 1 "$stack JKL567 error count"
  assert_error_path "$resp" '["cargo","itinerary","legs",0,"voyage"]' "$stack JKL567 error path"
  assert_null_at "$resp" '.data.cargo.itinerary.legs.0.voyage' "$stack JKL567 leg voyage is null"
  expect "USNYC" '.data.cargo.itinerary.legs.0.loadLocation.unLocode' "JKL567 leg 0 loadLocation"
  expect "JKL567" '.data.cargo.trackingId' "JKL567 trackingId"

  # 4. Failure at a non-null field: MNO901's location source returns null for
  #    XXBAD. Leg.loadLocation is Location!, Leg is in [Leg!]!, so the null
  #    climbs to Cargo.itinerary, the first nullable ancestor. The error path
  #    still names loadLocation, where the null was produced.
  resp="$(gql "$url" "$FAULT_QUERY" '{"t":"MNO901"}')"
  assert_null_at "$resp" '.data.cargo.itinerary' "$stack MNO901 itinerary is null"
  expect "MNO901" '.data.cargo.trackingId' "MNO901 trackingId"
  assert_error_count "$resp" 1 "$stack MNO901 error count"
  assert_error_path "$resp" '["cargo","itinerary","legs",0,"loadLocation"]' "$stack MNO901 error path"
  assert_error_message_contains "$resp" "loadLocation" "$stack MNO901 error message"

  # 5. Failure at a non-null field whose parent is also non-null: PQR234's
  #    delivery source raises. Cargo.delivery is Delivery!, so the null climbs
  #    to Query.cargo (nullable) and data itself stays an object.
  # shellcheck disable=SC2016
  resp="$(gql "$url" 'query Delivery($t: TrackingId!) { cargo(trackingId: $t) { trackingId delivery { transportStatus } } }' '{"t":"PQR234"}')"
  assert_null_at "$resp" '.data.cargo' "$stack PQR234 cargo is null"
  assert_error_count "$resp" 1 "$stack PQR234 error count"
  assert_error_path "$resp" '["cargo","delivery"]' "$stack PQR234 error path"
  assert_json_eq '{"cargo":null}' "$(json_field '.data' <<<"$resp")" "$stack PQR234 data is an object holding cargo: null"

  # 6. Aliases appear in paths and isolate siblings: the failure nulls only the
  #    aliased field it sits under.
  resp="$(gql "$url" '{ ok: cargo(trackingId: "ABC123") { trackingId } bad: cargo(trackingId: "PQR234") { trackingId delivery { transportStatus } } }')"
  expect "ABC123" '.data.ok.trackingId' "alias ok"
  assert_null_at "$resp" '.data.bad' "$stack alias bad is null"
  assert_error_count "$resp" 1 "$stack alias error count"
  assert_error_path "$resp" '["bad","delivery"]' "$stack alias error path"

  # 7. Not selecting the failing field means the failing source is never called.
  resp="$(gql "$url" '{ cargo(trackingId: "PQR234") { trackingId } }')"
  assert_no_errors "$resp" "$stack PQR234 without delivery"
  expect "PQR234" '.data.cargo.trackingId' "PQR234 trackingId without delivery"

  # 8. Input-side nullability. A null literal for a non-null argument and a
  #    nullable variable in a non-null position are both rejected before
  #    execution: errors, no data.
  resp="$(gql "$url" '{ cargo(trackingId: null) { trackingId } }')"
  assert_has_errors "$resp" "$stack null literal for a non-null argument"
  assert_no_data "$resp" "$stack null literal for a non-null argument"
  # shellcheck disable=SC2016
  resp="$(gql "$url" 'query($t: TrackingId) { cargo(trackingId: $t) { trackingId } }')"
  assert_has_errors "$resp" "$stack nullable variable in a non-null position"
  assert_no_data "$resp" "$stack nullable variable in a non-null position"
  # shellcheck disable=SC2016
  resp="$(gql "$url" 'query($t: TrackingId!) { cargo(trackingId: $t) { trackingId } }' '{"t":null}')"
  assert_has_errors "$resp" "$stack null value for a non-null variable"
  assert_no_data "$resp" "$stack null value for a non-null variable"

  # 8b. The experimental directive that switches propagation off for one
  #     operation. SmallRye registers it and graphql-java honors it: the null
  #     stays at loadLocation and its sibling voyage is still returned.
  #     Strawberry's schema does not define the directive, so that is a request error.
  resp="$(gql "$url" 'query @experimental_disableErrorPropagation { cargo(trackingId: "MNO901") { itinerary { legs { loadLocation { unLocode } voyage { number } } } } }')"
  if [[ "$stack" == "quarkus" ]]; then
    assert_null_at "$resp" '.data.cargo.itinerary.legs.0.loadLocation' "$stack propagation disabled: null stays at loadLocation"
    expect "V100S" '.data.cargo.itinerary.legs.0.voyage.number' "propagation disabled: sibling voyage survives"
    assert_error_path "$resp" '["cargo","itinerary","legs",0,"loadLocation"]' "$stack propagation disabled: error path"
  else
    assert_has_errors "$resp" "$stack unknown directive"
    assert_no_data "$resp" "$stack unknown directive"
  fi

  # 9. The wrapper chains the schema promises, read through introspection.
  assert_eq "NON_NULL>LIST>NON_NULL>OBJECT(Leg)" "$(wrapper_chain Itinerary legs)" "$stack Itinerary.legs"
  assert_eq "OBJECT(Voyage)" "$(wrapper_chain Leg voyage)" "$stack Leg.voyage"
  assert_eq "NON_NULL>OBJECT(Location)" "$(wrapper_chain Leg loadLocation)" "$stack Leg.loadLocation"
  assert_eq "NON_NULL>OBJECT(Delivery)" "$(wrapper_chain Cargo delivery)" "$stack Cargo.delivery"
  assert_eq "OBJECT(Itinerary)" "$(wrapper_chain Cargo itinerary)" "$stack Cargo.itinerary"

  # 10. Node dispatch still works after the resolvers: a fragment on the
  #     implementer selects its fields, not only __typename.
  check_node "cargo_ABC123" '... on Cargo { trackingId }' "Cargo" "ABC123" '.data.node.trackingId'
  check_node "loc_NLRTM" '... on Location { unLocode }' "Location" "NLRTM" '.data.node.unLocode'

  # 11. The custom scalars have kind SCALAR in the live schema and carry the
  #     canonical @specifiedBy URL (none for TrackingId). The live schema is the
  #     source for specifiedByURL, and this loop reads it from introspection.
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

  # 12. The live schema conforms to the canonical SDL (slice).
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"

  echo "=== $stack: nullability check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8140/graphql"
run_stack_check "python" "http://localhost:8141/graphql"

echo
echo "PASS - Ch4 Nullability and null propagation: Quarkus (SmallRye GraphQL) and" \
     "Python (Strawberry) both keep a failed nullable voyage at the leg, climb a null" \
     "loadLocation to Cargo.itinerary, null Query.cargo for a failed delivery, report" \
     "each error at the field that failed, and both conform to the canonical SDL."

# Explicit teardown in addition to lib.sh's EXIT trap (belt-and-suspenders);
# compose_down is idempotent/safe to call twice.
compose_down "$COMPOSE_FILE" "$PROJECT"
