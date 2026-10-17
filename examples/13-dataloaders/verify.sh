#!/usr/bin/env bash
# examples/13-dataloaders/verify.sh
#
# Ch13 The N+1 problem and DataLoaders: the 29 source calls of Chapter 12's
# four-cargo page become bulk calls, one per field per tick. SmallRye batches
# with @Source List<...> resolvers (one graphql-java DataLoader per field per
# request); Strawberry batches with DataLoaders built per request, keyed by value
# and shared across fields. The cases count the source-call log; every bulk call
# is logged once, under its sorted distinct keys joined with "+".
#
# Q_FAN pages four cargos (VWX901, XYZ789, STU678, DEF456), each with its
# itinerary legs (a voyage and two locations per leg) and its delivery:
#   Python  6 calls  = listCargos 1, getCargos 1, getItineraries 1,
#                      listEventsFor 1, getVoyages 1, getLocations 1
#   Quarkus 8 calls  = the same, plus a second getItineraries (Cargo.delivery has
#                      its own loader, apart from Cargo.itinerary) and a second
#                      getLocations (loadLocation and unloadLocation each have
#                      their own loader)
# Chapter 12 measured 29 for the same query.
#
# The cases run in a fixed order and handling state carries forward: case 10
# registers evt_10 for ABC123, so it runs last among the reads of ABC123.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch13-dataloaders"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# base64url without padding of a cursor's plaintext, computed independently of
# both stacks. python3 -I: stdlib only.
cursor_of() {
  python3 -I -c 'import base64, sys; print(base64.urlsafe_b64encode(sys.argv[1].encode()).rstrip(b"=").decode())' "$1"
}
CURSOR_VWX901="$(cursor_of 'cargo|v1|2026-09-29T09:00:00Z|VWX901')"

Q_FAN='{ cargos(first: 4) { edges { node { trackingId itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } } delivery { transportStatus } } } } }'
# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
REGISTER='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } cargo { delivery { transportStatus } } userErrors { code } } }'

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# expect_json <expected-json> <json-path> <context> — assert a list, an object
# or a null of $resp by parsed equality.
expect_json() {
  assert_json_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# fan_shape — the data of Q_FAN in $resp reduced to what the cases compare:
# each cargo's tracking id and its legs' voyage, load and unload codes.
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

# project <list-path> <field.path> — a JSON list: the dotted field of each item of
# the list at <list-path> in $resp (null where the path runs into a null).
project() {
  python3 -I -c '
import json, sys
value = json.load(sys.stdin)
for part in sys.argv[1].strip(".").split("."):
    value = value[int(part)] if part.isdigit() else value[part]
out = []
for item in value:
    for part in sys.argv[2].split("."):
        item = None if item is None else item[part]
    out.append(item)
print(json.dumps(out))
' "$1" "$2" <<<"$resp"
}

# expect_project <expected-json> <list-path> <field.path> <context>
expect_project() {
  assert_json_eq "$1" "$(project "$2" "$3")" "$stack $4"
}

# per_request_counts — the number of source calls each request id made, sorted.
per_request_counts() {
  python3 -I -c '
import collections, json, sys
counts = collections.Counter(c["request"] for c in json.load(sys.stdin)["calls"])
print(json.dumps(sorted(counts.values())))
' <<<"$1"
}

# run_stack_check <stack> <url>
run_stack_check() {
  local stack="$1" url="$2" resp calls total

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # The contract is untouched by batching: the first cargo cursor is still the
  # documented encoding, byte for byte.
  resp="$(gql "$url" '{ cargos(first: 2) { edges { cursor node { trackingId } } totalCount } }')"
  assert_no_errors "$resp" "$stack cargos(first: 2)"
  assert_eq "$CURSOR_VWX901" "$(json_field '.data.cargos.edges.0.cursor' <<<"$resp")" "$stack first cursor is the documented encoding"

  # 1. Q_FAN: the same data as Chapter 12, in 6 calls on Python and 8 on Quarkus.
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_FAN")"
  assert_no_errors "$resp" "$stack Q_FAN"
  assert_json_eq '[["VWX901",[["V300A","SGSIN","CNSHA"]]],["XYZ789",null],["STU678",[["V300A","SGSIN","CNSHA"]]],["DEF456",[["V100S","USNYC","DEHAM"],["V200E","DEHAM","NLRTM"]]]]' \
    "$(fan_shape)" "$stack Q_FAN returns the Chapter 12 data"
  calls="$(source_calls "$url")"
  case "$stack" in
    python) total=6 ;;
    quarkus) total=8 ;;
  esac
  assert_source_call_count "$calls" '*' '*' "$total" "$stack Q_FAN: $total source calls (Chapter 12: 29)"
  assert_source_call_keys "$calls" booking listCargos '*' "$stack Q_FAN booking.listCargos"
  assert_source_call_keys "$calls" booking getCargos DEF456+STU678+VWX901+XYZ789 "$stack Q_FAN booking.getCargos"
  assert_source_call_keys "$calls" handling listEventsFor DEF456+STU678+VWX901+XYZ789 "$stack Q_FAN handling.listEventsFor"
  assert_source_call_keys "$calls" voyage getVoyages V100S+V200E+V300A "$stack Q_FAN voyage.getVoyages"
  case "$stack" in
    python)
      assert_source_call_keys "$calls" routing getItineraries DEF456+STU678+VWX901+XYZ789 "$stack Q_FAN routing.getItineraries: one loader for itinerary and delivery"
      assert_source_call_keys "$calls" location getLocations CNSHA+DEHAM+NLRTM+SGSIN+USNYC "$stack Q_FAN location.getLocations: one loader keyed by code"
      ;;
    quarkus)
      assert_source_call_keys "$calls" routing getItineraries DEF456+STU678+VWX901+XYZ789,DEF456+STU678+VWX901+XYZ789 "$stack Q_FAN routing.getItineraries: one loader per field"
      assert_source_call_keys "$calls" location getLocations DEHAM+SGSIN+USNYC,CNSHA+DEHAM+NLRTM "$stack Q_FAN location.getLocations: one loader per field"
      ;;
  esac
  # No single-key fan-out is left.
  assert_source_call_count "$calls" '*' getCargo 0 "$stack Q_FAN makes no booking.getCargo call"
  assert_source_call_count "$calls" '*' getItinerary 0 "$stack Q_FAN makes no routing.getItinerary call"
  assert_source_call_count "$calls" '*' listEvents 0 "$stack Q_FAN makes no handling.listEvents call"
  assert_source_call_count "$calls" '*' getVoyage 0 "$stack Q_FAN makes no voyage.getVoyage call"
  assert_source_call_count "$calls" '*' getLocation 0 "$stack Q_FAN makes no location.getLocation call"

  # The count follows the fields of the selection, not the size of the page: two
  # cargos and five cargos cost the same number of calls as four.
  local size
  for size in 2 5; do
    source_calls_reset "$url"
    resp="$(gql "$url" "${Q_FAN/first: 4/first: $size}")"
    assert_no_errors "$resp" "$stack Q_FAN with first: $size"
    assert_source_call_count "$(source_calls "$url")" '*' '*' "$total" "$stack Q_FAN with $size cargos: still $total calls"
  done
  source_calls_reset "$url"
  gql "$url" "$Q_FAN" >/dev/null
  calls="$(source_calls "$url")"

  # 2. The tick: a level's keys are collected, then one call is made; a call starts
  #    only after the call its keys come from has returned. Only order and overlap
  #    are asserted, never durations.
  assert_calls_ordered "$calls" 'booking.listCargos:*' 'booking.getCargos:DEF456+STU678+VWX901+XYZ789' "$stack the page is read before its cargos are loaded"
  assert_calls_ordered "$calls" 'booking.getCargos:DEF456+STU678+VWX901+XYZ789' 'handling.listEventsFor:DEF456+STU678+VWX901+XYZ789' "$stack the cargos are loaded before their events"
  case "$stack" in
    quarkus)
      # graphql-java dispatches a level only after every object of the level above completed,
      # so the Leg level waits for Cargo.delivery and its events.
      assert_calls_ordered "$calls" 'handling.listEventsFor:DEF456+STU678+VWX901+XYZ789' 'voyage.getVoyages:V100S+V200E+V300A' "$stack the Leg level waits for the whole Cargo level, events included"
      ;;
    python)
      # Strawberry dispatches whatever was loaded in the tick: the voyages wait for the
      # itineraries they come from, not for the events.
      assert_calls_ordered "$calls" 'routing.getItineraries:DEF456+STU678+VWX901+XYZ789' 'voyage.getVoyages:V100S+V200E+V300A' "$stack the itineraries are read before their legs' voyages"
      assert_calls_overlap "$calls" 'routing.getItineraries:DEF456+STU678+VWX901+XYZ789' 'handling.listEventsFor:DEF456+STU678+VWX901+XYZ789' "$stack the itinerary and event batches share a tick"
      assert_calls_overlap "$calls" 'voyage.getVoyages:V100S+V200E+V300A' 'location.getLocations:CNSHA+DEHAM+NLRTM+SGSIN+USNYC' "$stack the voyage and location batches share a level"
      ;;
    quarkus)
      assert_calls_overlap "$calls" 'voyage.getVoyages:V100S+V200E+V300A' 'location.getLocations:DEHAM+SGSIN+USNYC' "$stack the voyage and load-location batches share a level"
      assert_calls_overlap "$calls" 'location.getLocations:DEHAM+SGSIN+USNYC' 'location.getLocations:CNSHA+DEHAM+NLRTM' "$stack the two location batches run together"
      ;;
  esac
  assert_single_request "$calls" "$stack Q_FAN: one request id across every batch"

  # 3. Chapter 7's alias pair: four voyage calls there, one here.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { itinerary { legs { a: voyage { number } b: voyage { number } } } } }')"
  assert_no_errors "$resp" "$stack alias pair"
  expect "V100S" '.data.cargo.itinerary.legs.0.a.number' "alias a on leg 0"
  expect "V100S" '.data.cargo.itinerary.legs.0.b.number' "alias b on leg 0"
  expect "V200E" '.data.cargo.itinerary.legs.1.a.number' "alias a on leg 1"
  expect "V200E" '.data.cargo.itinerary.legs.1.b.number' "alias b on leg 1"
  assert_source_call_keys "$(source_calls "$url")" voyage getVoyages V100S+V200E "$stack alias pair: one voyage call (Chapter 7: four)"
  assert_source_call_count "$(source_calls "$url")" voyage '*' 1 "$stack alias pair: nothing else asks the voyage service"

  # 4. Chapter 7's itinerary and delivery pair: one routing call on Python, two on
  #    Quarkus, where the two fields have separate loaders.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { itinerary { finalArrivalTime } delivery { transportStatus } } }')"
  assert_no_errors "$resp" "$stack itinerary and delivery"
  expect "2026-10-11T18:00:00Z" '.data.cargo.itinerary.finalArrivalTime' "itinerary.finalArrivalTime"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "delivery.transportStatus"
  case "$stack" in
    python) assert_source_call_keys "$(source_calls "$url")" routing getItineraries ABC123 "$stack itinerary and delivery share one routing call" ;;
    quarkus) assert_source_call_keys "$(source_calls "$url")" routing getItineraries ABC123,ABC123 "$stack itinerary and delivery each call routing" ;;
  esac

  # 5. Chapter 1's history fan-out: seven events of DEF456, each with a location
  #    and, for four of them, a voyage. Chapter 12 made 7 + 4 calls; the batches
  #    make one of each.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "DEF456") { handlingHistory(first: 7) { edges { node { id location { unLocode } voyage { number } } } } } }')"
  assert_no_errors "$resp" "$stack history fan-out"
  expect_project '["evt_9","evt_8","evt_7","evt_6","evt_5","evt_4","evt_3"]' .data.cargo.handlingHistory.edges node.id "history ids"
  expect_project '["NLRTM","NLRTM","NLRTM","DEHAM","DEHAM","USNYC","USNYC"]' .data.cargo.handlingHistory.edges node.location.unLocode "history locations"
  expect_project '[null,null,"V200E","V200E","V100S","V100S",null]' .data.cargo.handlingHistory.edges node.voyage.number "history voyages (null without one)"
  calls="$(source_calls "$url")"
  assert_source_call_keys "$calls" location getLocations DEHAM+NLRTM+USNYC "$stack history: one location call (Chapter 12: 7)"
  assert_source_call_keys "$calls" voyage getVoyages V100S+V200E "$stack history: one voyage call, only for events that have a voyage (Chapter 12: 4)"
  assert_source_calls_exactly "$calls" 'booking.getCargo:DEF456,handling.pageEvents:DEF456,location.getLocations:DEHAM+NLRTM+USNYC,voyage.getVoyages:V100S+V200E' "$stack history: the root cargo, the page, then one call per field"

  # 5b. HandlingEvent.cargo batches too: seven events of DEF456, one getCargos call
  #     (the root field's own getCargo and the page read are the other two).
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "DEF456") { handlingHistory(first: 7) { edges { node { cargo { trackingId } } } } } }')"
  assert_no_errors "$resp" "$stack history with each event's cargo"
  expect_project '["DEF456","DEF456","DEF456","DEF456","DEF456","DEF456","DEF456"]' .data.cargo.handlingHistory.edges node.cargo.trackingId "each event's cargo"
  assert_source_calls_exactly "$(source_calls "$url")" 'booking.getCargo:DEF456,handling.pageEvents:DEF456,booking.getCargos:DEF456' "$stack HandlingEvent.cargo: seven events, one getCargos call"

  # 5c. Chapter 1's twenty-four locations: a cargo's legs and its history ask for
  #     eleven locations (4 + 7 for DEF456). The count of calls is one per
  #     location field on Quarkus and one shared loader on Python.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "DEF456") { itinerary { legs { loadLocation { unLocode } unloadLocation { unLocode } } } handlingHistory(first: 7) { edges { node { location { unLocode } } } } } }')"
  assert_no_errors "$resp" "$stack legs' and history's locations"
  case "$stack" in
    python) assert_source_call_keys "$(source_calls "$url")" location getLocations DEHAM+NLRTM+USNYC "$stack Chapter 1's locations: one getLocations call" ;;
    quarkus) assert_source_call_keys "$(source_calls "$url")" location getLocations DEHAM+USNYC,DEHAM+NLRTM,DEHAM+NLRTM+USNYC "$stack Chapter 1's locations: one getLocations call per location field" ;;
  esac

  # 6. nodes: one bulk call per type (Chapter 12: five calls).
  source_calls_reset "$url"
  resp="$(gql "$url" '{ nodes(ids: ["cargo_ABC123", "cargo_XYZ789", "loc_DEHAM", "loc_NLRTM", "voy_V100S"]) { __typename id } }')"
  assert_no_errors "$resp" "$stack nodes"
  expect_project '["Cargo","Cargo","Location","Location","Voyage"]' .data.nodes __typename "nodes types, in the order asked"
  expect_project '["cargo_ABC123","cargo_XYZ789","loc_DEHAM","loc_NLRTM","voy_V100S"]' .data.nodes id "nodes ids, in the order asked"
  assert_source_calls_exactly "$(source_calls "$url")" 'booking.getCargos:ABC123+XYZ789,location.getLocations:DEHAM+NLRTM,voyage.getVoyages:V100S' "$stack nodes: three calls, one per type"

  # 6b. Chapter 10's list with a duplicate and an unknown id: the duplicate travels once.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ nodes(ids: ["cargo_ABC123", "loc_NLRTM", "nope", "voy_V200E", "cargo_ABC123"]) { id } }')"
  assert_no_errors "$resp" "$stack nodes with a duplicate"
  expect_json '[{"id":"cargo_ABC123"},{"id":"loc_NLRTM"},null,{"id":"voy_V200E"},{"id":"cargo_ABC123"}]' '.data.nodes' "duplicate and unknown ids keep their positions"
  assert_source_calls_exactly "$(source_calls "$url")" 'booking.getCargos:ABC123,location.getLocations:NLRTM,voyage.getVoyages:V200E' "$stack Chapter 10's four calls become three"

  # 7. Request scope: the same request twice shares nothing. Each makes its own
  #    calls under its own request id.
  source_calls_reset "$url"
  gql "$url" "$Q_FAN" >/dev/null
  gql "$url" "$Q_FAN" >/dev/null
  calls="$(source_calls "$url")"
  assert_distinct_requests "$calls" "$stack two requests, two request ids"
  assert_source_call_count "$calls" '*' '*' "$((total * 2))" "$stack the second request repeats every call"
  assert_json_eq "[$total,$total]" "$(per_request_counts "$calls")" "$stack each request made $total calls"

  # 8. Not found inside a batch: a null at its position, no error. The root
  #    voyage field is still the single-key call.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ voyage(voyageNumber: "V999X") { number } }')"
  assert_no_errors "$resp" "$stack voyage(V999X)"
  assert_null_at "$resp" '.data.voyage' "$stack voyage(V999X) is null"
  assert_source_calls_exactly "$(source_calls "$url")" 'voyage.getVoyage:V999X' "$stack the root voyage field makes one single-key call"
  source_calls_reset "$url"
  resp="$(gql "$url" '{ nodes(ids: ["voy_V999X", "voy_V100S"]) { __typename ... on Voyage { number } } }')"
  assert_no_errors "$resp" "$stack nodes with an unknown voyage"
  expect_json '[null,{"__typename":"Voyage","number":"V100S"}]' '.data.nodes' "an unknown key is null at its position"
  assert_source_calls_exactly "$(source_calls "$url")" 'voyage.getVoyages:V100S+V999X' "$stack nodes: the unknown key travels in the batch"

  # 9. Blast radius: GHI345 fails inside the bulk booking call that loads the
  #    last page's two nodes.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargos(last: 2) { edges { node { trackingId } } } }')"
  assert_source_calls_exactly "$(source_calls "$url")" 'booking.listCargos:*,booking.getCargos:ABC123+GHI345' "$stack blast radius: both nodes in one bulk call"
  assert_error_shape "$resp" execution "$stack blast radius: execution error shape"
  case "$stack" in
    python)
      # The exception instance sits at one position: one error, one null node.
      assert_error_count "$resp" 1 "$stack blast radius: one error"
      assert_error_path "$resp" '["cargos","edges",1,"node"]' "$stack blast radius: the failing key's path"
      assert_error_message_at "$resp" '["cargos","edges",1,"node"]' "booking service unavailable" "$stack blast radius: message"
      assert_error_extension "$resp" '["cargos","edges",1,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack blast radius: code"
      assert_null_at "$resp" '.data.cargos.edges.1.node' "$stack blast radius: GHI345's node is null"
      expect "ABC123" '.data.cargos.edges.0.node.trackingId' "blast radius: the sibling key resolved"
      ;;
    quarkus)
      # SmallRye resolves a batch method with one result list, so a failure fails
      # the whole batch: every parent in it gets the error at its own path.
      assert_error_count "$resp" 2 "$stack blast radius: one error per parent in the batch"
      assert_error_path "$resp" '["cargos","edges",0,"node"]' "$stack blast radius: the healthy key's path"
      assert_error_path "$resp" '["cargos","edges",1,"node"]' "$stack blast radius: the failing key's path"
      assert_error_extension "$resp" '["cargos","edges",0,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack blast radius: code at edge 0"
      assert_error_extension "$resp" '["cargos","edges",1,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack blast radius: code at edge 1"
      assert_null_at "$resp" '.data.cargos.edges.0.node' "$stack blast radius: the healthy node is lost"
      assert_null_at "$resp" '.data.cargos.edges.1.node' "$stack blast radius: GHI345's node is null"
      ;;
  esac

  # 10. A write still reads back: the payload and a fresh request both see the
  #     new event, because no loader outlives its request.
  resp="$(gql "$url" "$REGISTER" '{"i":{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z"}}')"
  assert_no_errors "$resp" "$stack registering the unload"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "the unload is evt_10"
  expect "IN_PORT" '.data.registerHandlingEvent.cargo.delivery.transportStatus' "the payload's delivery sees the unload"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { delivery { transportStatus } } }')"
  expect "IN_PORT" '.data.cargo.delivery.transportStatus' "a fresh request sees the unload"

  # 11. The deprecation of Chapter 11, the custom scalars, and the live schema:
  #     batch methods and loaders change no field, argument or nullability.
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
  # Only Subscription is unserved: the canonical -> live breaking lines, less the
  # framework noise, are exactly its two removals.
  local sdl_rev sdl_removed
  sdl_rev="$(_sdl_diff "$CANONICAL_SDL_GLOB" "$url")"
  sdl_removed="$(grep '✖' <<<"$sdl_rev" | grep -vE "$LGTM_SDL_IGNORE" | sed -E 's/^.*✖ +//' | sort || true)"
  assert_eq "Schema subscription type Subscription was removed.
Type Subscription was removed" "$sdl_removed" "$stack only Subscription is unserved"

  echo "=== $stack: batching check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8230/graphql"
run_stack_check "python" "http://localhost:8231/graphql"

echo
echo "PASS - Ch13 The N+1 problem and DataLoaders: Quarkus (SmallRye GraphQL @Source List batch" \
     "resolvers) and Python (Strawberry DataLoaders) turn the 29 source calls of a four-cargo page" \
     "into 8 and 6 bulk calls, collapse Chapter 7's repeated voyage and the nodes fan-out, keep" \
     "loaders inside one request, return a missing key as null, show how one failing key spreads" \
     "through a batch on each stack, and still conform to the canonical SDL except for Subscription."
