#!/usr/bin/env bash
# examples/20-federation/verify.sh
#
# Ch20 Federation and schema composition: the tracking view split into a cargo
# subgraph and a handling subgraph on each stack, composed into two supergraphs
# and served by two gateways:
#
#   gateway-a  8300  cargo on Quarkus (8302) + handling on Python  (8305)
#   gateway-b  8301  cargo on Python  (8303) + handling on Quarkus (8304)
#
# The cases run in a fixed order. The reads come first, the write next, and the
# case that stops a subgraph runs last. The query-plan numbers are read from the
# subgraphs' source-call logs, so they are the numbers of the run, not of a plan:
#
#   TrackCargo through a gateway makes three subgraph fetches:
#     cargo     the root field, its itinerary and the legs' locations (request 1)
#     handling  _entities(Cargo): delivery and handlingHistory           (request 2)
#     cargo     _entities(Location): the names of the locations handling named
#                                                                         (request 3)
#   so the cargo subgraph sees two distinct requests and handling sees one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch20-federation"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

GATEWAY_A="http://localhost:8300/graphql"
GATEWAY_B="http://localhost:8301/graphql"
CARGO_QUARKUS="http://localhost:8302/graphql"
CARGO_PYTHON="http://localhost:8303/graphql"
HANDLING_QUARKUS="http://localhost:8304/graphql"
HANDLING_PYTHON="http://localhost:8305/graphql"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
TRACK_FED='query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId description itinerary { legs { loadLocation { name } } } delivery { transportStatus lastKnownLocation { name } } handlingHistory(first: 2) { edges { node { type location { name } } } } } }'
# shellcheck disable=SC2016
TRACK_HISTORY='query($id: TrackingId!) { cargo(trackingId: $id) { handlingHistory(first: 7) { edges { node { type location { name } } } } } }'
# shellcheck disable=SC2016
REGISTER='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } cargo { trackingId description delivery { transportStatus } } userErrors { code } } }'
# shellcheck disable=SC2016
ENTITIES_CARGO='query($r: [_Any!]!) { _entities(representations: $r) { __typename ... on Cargo { description } ... on Location { name } ... on Voyage { number } } }'
# shellcheck disable=SC2016
ENTITIES_HANDLING='query($r: [_Any!]!) { _entities(representations: $r) { __typename ... on Cargo { delivery { transportStatus } } } }'
REG_A1='{"i":{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z","idempotencyKey":"ch20-reg-a1"}}'

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$label $3"
}

# expect_json <expected-json> <json-path> <context> — a list, an object or a null.
expect_json() {
  assert_json_eq "$1" "$(json_field "$2" <<<"$resp")" "$label $3"
}

# project <list-path> <field.path> — a JSON list: the dotted field of each item of
# the list at <list-path> in $resp.
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
  assert_json_eq "$1" "$(project "$2" "$3")" "$label $4"
}

# expect_project_sorted — like expect_project, with the projected list sorted.
expect_project_sorted() {
  assert_json_eq "$1" "$(project "$2" "$3" | python3 -I -c 'import json, sys; print(json.dumps(sorted(json.load(sys.stdin))))')" "$label $4"
}

# sdl_matches <sdl> <regex> <context> / sdl_lacks <sdl> <regex> <context> — a
# multi-line regex over a subgraph's SDL. The two stacks print directives with
# different spacing, so the patterns allow any whitespace around the colon.
sdl_matches() {
  python3 -I -c '
import re, sys
sys.exit(0 if re.search(sys.argv[2], sys.argv[1], re.S) else 1)
' "$1" "$2" || { echo "lib.sh: FAIL — $3: no match for /$2/" >&2; return 1; }
  echo "lib.sh: ok — $3" >&2
}

sdl_lacks() {
  if python3 -I -c '
import re, sys
sys.exit(0 if re.search(sys.argv[2], sys.argv[1], re.S) else 1)
' "$1" "$2"; then
    echo "lib.sh: FAIL — $3: /$2/ is present" >&2
    return 1
  fi
  echo "lib.sh: ok — $3" >&2
}

# reps <typename> <key> <value>... — the JSON variables for _entities: one
# representation per value.
reps() {
  python3 -I -c '
import json, sys
typename, key, *values = sys.argv[1:]
print(json.dumps({"r": [{"__typename": typename, key: value} for value in values]}))
' "$@"
}

# subgraph_checks <label> <url> <role> — the subgraph contract, read straight
# from one subgraph: its SDL, and the entity resolvers behind _entities.
subgraph_checks() {
  local label="$1" url="$2" role="$3" resp sdl calls

  echo
  echo "=== subgraph $label at $url ==="
  wait_for_graphql "$url"

  resp="$(gql "$url" '{ _service { sdl } }')"
  assert_no_errors "$resp" "$label _service { sdl }"
  sdl="$(json_field '.data._service.sdl' <<<"$resp")"
  sdl_matches "$sdl" 'type Cargo\b[^{]*@key\(fields\s*:\s*"trackingId"\)' "$label: Cargo is an entity keyed by trackingId"
  sdl_matches "$sdl" '@link\([^)]*specs\.apollo\.dev/federation/v2\.7' "$label: the subgraph declares Federation 2.7"
  sdl_matches "$sdl" 'type PageInfo\b[^{]*@shareable' "$label: PageInfo is shareable"
  sdl_matches "$sdl" 'scalar UnLocode\s+@specifiedBy\(url\s*:\s*"https://unece\.org/trade/uncefact/unlocode"\)' "$label: UnLocode carries its @specifiedBy URL"
  sdl_matches "$sdl" 'scalar DateTime\s+@specifiedBy\(url\s*:\s*"https://www\.rfc-editor\.org/rfc/rfc3339"\)' "$label: DateTime carries its @specifiedBy URL"
  case "$role" in
    cargo)
      sdl_matches "$sdl" 'type Location\b[^{]*@key\(fields\s*:\s*"unLocode"\)' "$label: Location is a resolvable entity"
      sdl_matches "$sdl" 'type Voyage\b[^{]*@key\(fields\s*:\s*"number"\)' "$label: Voyage is a resolvable entity"
      sdl_lacks "$sdl" 'type Location\b[^{]*resolvable\s*:\s*false' "$label: Location is resolvable here"
      sdl_lacks "$sdl" 'handlingHistory' "$label does not define handlingHistory"
      sdl_lacks "$sdl" 'registerHandlingEvent' "$label does not define the mutation"
      ;;
    handling)
      sdl_matches "$sdl" 'type Location\b[^{]*@key\(fields\s*:\s*"unLocode"\s*,\s*resolvable\s*:\s*false\)' "$label: Location is a reference (resolvable: false)"
      sdl_matches "$sdl" 'type Voyage\b[^{]*@key\(fields\s*:\s*"number"\s*,\s*resolvable\s*:\s*false\)' "$label: Voyage is a reference (resolvable: false)"
      sdl_matches "$sdl" 'handlingHistory' "$label defines handlingHistory"
      sdl_matches "$sdl" 'registerHandlingEvent' "$label defines the mutation"
      ;;
  esac

  # Entity resolution, direct. A representation is the type name and the key.
  source_calls_reset "$url"
  case "$role" in
    cargo)
      resp="$(gql "$url" "$ENTITIES_CARGO" "$(reps Cargo trackingId ABC123 ZZZ999)")"
      assert_no_errors "$resp" "$label _entities(Cargo)"
      expect_json '[{"__typename":"Cargo","description":"Palletized electronics"},null]' '.data._entities' "resolves ABC123 and returns null for an unknown key"
      assert_source_call_keys "$(source_calls "$url")" booking getCargos ABC123+ZZZ999 "$label: both representations share one booking call"

      source_calls_reset "$url"
      resp="$(gql "$url" "$ENTITIES_CARGO" "$(reps Location unLocode DEHAM NLRTM USNYC DEHAM SGSIN)")"
      assert_no_errors "$resp" "$label _entities(Location)"
      expect_json '[{"__typename":"Location","name":"Hamburg"},{"__typename":"Location","name":"Rotterdam"},{"__typename":"Location","name":"New York"},{"__typename":"Location","name":"Hamburg"},{"__typename":"Location","name":"Singapore"}]' '.data._entities' "five representations, in order"
      calls="$(source_calls "$url")"
      assert_source_calls_exactly "$calls" 'location.getLocations:DEHAM+NLRTM+SGSIN+USNYC' "$label: five Location representations make one bulk location call"
      assert_request_count "$calls" 1 "$label: one request"

      source_calls_reset "$url"
      resp="$(gql "$url" "$ENTITIES_CARGO" "$(reps Voyage number V100S V999X)")"
      assert_no_errors "$resp" "$label _entities(Voyage)"
      expect_json '[{"__typename":"Voyage","number":"V100S"},null]' '.data._entities' "resolves V100S and returns null for an unknown number"
      ;;
    handling)
      resp="$(gql "$url" "$ENTITIES_HANDLING" "$(reps Cargo trackingId ABC123 ZZZ999)")"
      assert_no_errors "$resp" "$label _entities(Cargo)"
      expect_json '[{"__typename":"Cargo","delivery":{"transportStatus":"ONBOARD_CARRIER"}},null]' '.data._entities' "ABC123 is aboard a carrier; an unknown key is null"
      ;;
  esac
}

# gateway_checks <label> <gateway> <cargo-url> <handling-url> <cargo-stack>
gateway_checks() {
  local label="$1" gateway="$2" cargo="$3" handling="$4" cargo_stack="$5" resp calls

  echo
  echo "=== gateway $label at $gateway (cargo on $cargo_stack) ==="
  wait_for_graphql "$gateway"

  # --- The query plan -------------------------------------------------------
  source_calls_reset "$cargo"
  source_calls_reset "$handling"
  resp="$(gql "$gateway" "$TRACK_FED" '{"id":"ABC123"}')"
  assert_no_errors "$resp" "$label TrackCargo"
  expect "ABC123" '.data.cargo.trackingId' "trackingId"
  expect "Palletized electronics" '.data.cargo.description' "description comes from the cargo subgraph"
  expect_project '["New York","Hamburg"]' .data.cargo.itinerary.legs loadLocation.name "the legs' load locations"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "delivery comes from the handling subgraph"
  expect "New York" '.data.cargo.delivery.lastKnownLocation.name' "a location named by handling is resolved by cargo"
  expect_project '["LOAD","RECEIVE"]' .data.cargo.handlingHistory.edges node.type "the two newest events"
  expect_project '["New York","New York"]' .data.cargo.handlingHistory.edges node.location.name "the events' locations"

  local cargo_calls handling_calls
  cargo_calls="$(source_calls "$cargo")"
  handling_calls="$(source_calls "$handling")"
  assert_request_count "$cargo_calls" 2 "$label the cargo subgraph saw two requests (the root fetch, then the Location entity fetch)"
  assert_request_count "$handling_calls" 1 "$label the handling subgraph saw one request (the Cargo entity fetch)"
  assert_source_calls_exactly "$cargo_calls" 'booking.getCargo:ABC123,routing.getItineraries:ABC123,location.getLocations:DEHAM+USNYC,location.getLocations:USNYC' \
    "$label cargo subgraph: the root fetch reads the cargo, its itinerary and the legs' locations; the entity fetch makes one location call"
  assert_source_calls_exactly "$handling_calls" 'booking.getCargos:ABC123,handling.pageEvents:ABC123,routing.getItineraries:ABC123,handling.listEventsFor:ABC123' \
    "$label handling subgraph: one request reads the cargo, the page, the itinerary and the events"

  # A longer history names many locations; the gateway sends them to the cargo
  # subgraph as one entity fetch, and the subgraph makes one bulk call.
  source_calls_reset "$cargo"
  source_calls_reset "$handling"
  resp="$(gql "$gateway" "$TRACK_HISTORY" '{"id":"DEF456"}')"
  assert_no_errors "$resp" "$label DEF456 history"
  expect_project '["CLAIM","CUSTOMS","UNLOAD","LOAD","UNLOAD","LOAD","RECEIVE"]' .data.cargo.handlingHistory.edges node.type "DEF456's seven events"
  expect_project '["Rotterdam","Rotterdam","Rotterdam","Hamburg","Hamburg","New York","New York"]' .data.cargo.handlingHistory.edges node.location.name "seven locations, named by the cargo subgraph"
  cargo_calls="$(source_calls "$cargo")"
  assert_request_count "$cargo_calls" 2 "$label DEF456: the cargo subgraph saw two requests"
  assert_source_call_keys "$cargo_calls" location getLocations DEHAM+NLRTM+USNYC "$label DEF456: seven location references, one bulk call"
  assert_source_call_count "$cargo_calls" location getLocations 1 "$label DEF456: one location call in all"

  # --- Errors cross the gateway ----------------------------------------------
  resp="$(gql "$gateway" '{ cargos(first: 10) { edges { node { trackingId } } } }')"
  assert_error_path "$resp" '["cargos","edges",5,"node"]' "$label the error sits at the GHI345 edge"
  assert_error_message_at "$resp" '["cargos","edges",5,"node"]' "booking service unavailable" "$label message"
  assert_error_extension "$resp" '["cargos","edges",5,"node"]' code '"SERVICE_UNAVAILABLE"' "$label code survives the gateway"
  assert_error_extension "$resp" '["cargos","edges",5,"node"]' serviceName '"cargo"' "$label the gateway names the subgraph"
  case "$cargo_stack" in
    python)
      assert_error_count "$resp" 1 "$label only the failing key fails"
      expect "VWX901" '.data.cargos.edges.0.node.trackingId' "the first node resolved"
      expect "ABC123" '.data.cargos.edges.4.node.trackingId' "the fifth node resolved"
      assert_null_at "$resp" '.data.cargos.edges.5.node' "$label GHI345's node is null"
      ;;
    quarkus)
      # SmallRye resolves a batch with one result list, so the failing key fails
      # every node of the batch: one error per edge.
      assert_error_count "$resp" 6 "$label the batch fails as a whole: one error per edge"
      assert_null_at "$resp" '.data.cargos.edges.0.node' "$label the batch's first node is null"
      assert_null_at "$resp" '.data.cargos.edges.5.node' "$label GHI345's node is null"
      ;;
  esac

  # --- The write: a mutation owned by handling, a payload shared with cargo ---
  source_calls_reset "$cargo"
  source_calls_reset "$handling"
  resp="$(gql "$gateway" "$REGISTER" "$REG_A1")"
  assert_no_errors "$resp" "$label registerHandlingEvent"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "the unload is evt_10"
  expect "Palletized electronics" '.data.registerHandlingEvent.cargo.description' "the payload's cargo description comes from the cargo subgraph"
  expect "IN_PORT" '.data.registerHandlingEvent.cargo.delivery.transportStatus' "the payload's delivery sees the unload: handling owns both the write and the read"
  expect_json '[]' '.data.registerHandlingEvent.userErrors' "no user errors"
  assert_source_call_keys "$(source_calls "$handling")" handling appendEvent evt_10 "$label the handling subgraph wrote one event"
  assert_source_call_keys "$(source_calls "$cargo")" booking getCargos ABC123 "$label the cargo subgraph served the payload's cargo as an entity"

  source_calls_reset "$handling"
  resp="$(gql "$gateway" "$REGISTER" "$REG_A1")"
  assert_no_errors "$resp" "$label the same idempotency key again"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "a repeat returns the original event"
  assert_source_call_count "$(source_calls "$handling")" handling appendEvent 0 "$label the repeat writes nothing"

  # --- The contract still holds ---------------------------------------------
  assert_sdl_conforms "$gateway" "$label gateway schema vs contracts/schema"
  local sdl_rev sdl_removed
  sdl_rev="$(_sdl_diff "$CANONICAL_SDL_GLOB" "$gateway")"
  sdl_removed="$(grep '✖' <<<"$sdl_rev" | grep -vE "$LGTM_SDL_IGNORE" | sed -E 's/^.*✖ +//' | LC_ALL=C sort || true)"
  assert_eq "Field node was removed from object type Query
Field nodes was removed from object type Query
Schema subscription type Subscription was removed.
Type Subscription was removed" "$sdl_removed" "$label only Query.node, Query.nodes and Subscription are unserved"
  assert_deprecated "$gateway" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$label Itinerary.finalArrivalDate"
  assert_not_deprecated "$gateway" Itinerary finalArrivalTime "$label Itinerary.finalArrivalTime"
  local scalar
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016
    resp="$(gql "$gateway" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$label $scalar introspection"
    expect "SCALAR" '.data.__type.kind' "$scalar kind"
    case "$scalar" in
      UnLocode) expect "https://unece.org/trade/uncefact/unlocode" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      DateTime) expect "https://www.rfc-editor.org/rfc/rfc3339" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      *) assert_null_at "$resp" '.data.__type.specifiedByURL' "$label $scalar has no specifiedByURL" ;;
    esac
  done

  # Node is declared in both subgraphs with its implementers split between them;
  # the gateway's schema lists all four.
  resp="$(gql "$gateway" '{ __type(name: "Node") { possibleTypes { name } } }')"
  assert_no_errors "$resp" "$label Node"
  expect_project_sorted '["Cargo","HandlingEvent","Location","Voyage"]' .data.__type.possibleTypes name "Node has four implementers"

  # Federation directives and fields never reach a client.
  resp="$(gql "$gateway" '{ __schema { directives { name } } query: __type(name: "Query") { fields { name } } }')"
  assert_no_errors "$resp" "$label directives"
  expect_project_sorted '["deprecated","include","oneOf","skip","specifiedBy"]' .data.__schema.directives name "only the built-in directives are published"
  expect_project_sorted '["cargo","cargos","location","voyage"]' .data.query.fields name "Query has no _service or _entities"
}

# partial_failure <label> <gateway> <stopped-service> — the handling subgraph is
# down: the fields it owns fail, and Ch4's nullability decides how far. Run last.
partial_failure() {
  local label="$1" gateway="$2" service="$3" resp

  echo
  echo "=== $label: stopping $service ==="
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" stop "$service" >/dev/null

  resp="$(gql "$gateway" "$TRACK_FED" '{"id":"ABC123"}')"
  assert_has_errors "$resp" "$label TrackCargo with $service stopped"
  assert_null_at "$resp" '.data.cargo' "$label delivery is Delivery!, so a failed fetch nulls the cargo"
  assert_error_path "$resp" '["cargo","delivery"]' "$label the error names the field handling owns"
  assert_error_extension "$resp" '["cargo","delivery"]' code '"INTERNAL_SERVER_ERROR"' "$label the gateway reports the failed fetch"

  # Everything the cargo subgraph owns still answers.
  resp="$(gql "$gateway" '{ location(unLocode: "NLRTM") { name } }')"
  assert_no_errors "$resp" "$label location still resolves"
  expect "Rotterdam" '.data.location.name' "location(NLRTM)"
  resp="$(gql "$gateway" '{ cargo(trackingId: "ABC123") { trackingId description itinerary { legs { loadLocation { name } } } } }')"
  assert_no_errors "$resp" "$label the cargo's own fields still resolve"
  expect "Palletized electronics" '.data.cargo.description' "description"
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: the subgraphs ==="
subgraph_checks "cargo-quarkus" "$CARGO_QUARKUS" cargo
subgraph_checks "cargo-python" "$CARGO_PYTHON" cargo
subgraph_checks "handling-quarkus" "$HANDLING_QUARKUS" handling
subgraph_checks "handling-python" "$HANDLING_PYTHON" handling

echo
echo "=== Step 3: composition is a gate ==="
for composer in composer-a composer-b; do
  code="$(docker inspect -f '{{.State.ExitCode}}' "ch20-federation-$composer")"
  assert_eq "0" "$code" "$composer composed its pair and exited 0"
done

# Each fixture is composed against the committed cargo subgraph. Composition
# fails, names the rule and exits 1; nothing is written for a gateway to load.
compose_fixture() {
  local fixture="$1" code="$2" out status=0
  out="$(compose_run composer-a --out /tmp/rejected.graphql --file cargo=/fixtures/cargo.graphql --file "handling=/fixtures/$fixture.graphql" 2>&1)" || status=$?
  assert_eq "1" "$status" "composing $fixture fails with exit 1"
  assert_contains "$code" "$out" "composing $fixture reports $code"
  # Every error line the composer printed (CODE: message) is of this one rule: a
  # fixture that drifts and picks up another error fails here.
  local extra
  extra="$(grep -E '^[A-Z][A-Z_]+: ' <<<"$out" | grep -v "^$code: " || true)"
  assert_eq "" "$extra" "composing $fixture prints only $code errors"
}
compose_fixture handling-key-type-conflict FIELD_TYPE_MISMATCH
compose_fixture handling-unshared-pageinfo INVALID_FIELD_SHARING

# The same command with the live subgraphs succeeds.
out="$(compose_run composer-a --out /tmp/again.graphql --subgraph cargo=http://cargo-quarkus:8080/graphql --subgraph handling=http://handling-python:8080/graphql 2>&1)"
assert_contains "composed cargo + handling" "$out" "composing the live subgraphs again succeeds"

echo
echo "=== Step 4: the gateways ==="
gateway_checks "gateway-a" "$GATEWAY_A" "$CARGO_QUARKUS" "$HANDLING_PYTHON" quarkus
gateway_checks "gateway-b" "$GATEWAY_B" "$CARGO_PYTHON" "$HANDLING_QUARKUS" python

echo
echo "=== Step 5: a subgraph down ==="
partial_failure "gateway-a" "$GATEWAY_A" handling-python
partial_failure "gateway-b" "$GATEWAY_B" handling-quarkus

echo
echo "PASS - Ch20 Federation and schema composition: cargo and handling subgraphs on Quarkus (SmallRye" \
     "GraphQL) and Python (Strawberry) expose the same entities and batch their entity resolvers; the" \
     "composer turns each pair into a supergraph and rejects two broken fixtures with FIELD_TYPE_MISMATCH" \
     "and INVALID_FIELD_SHARING; two cross-wired Hive gateways answer TrackCargo in three subgraph fetches" \
     "(cargo twice, handling once), carry a mutation and its payload across subgraphs, keep error codes," \
     "conform to the canonical SDL except for Query.node, Query.nodes and Subscription, and null the cargo" \
     "when the handling subgraph is down."
