#!/usr/bin/env bash
# examples/12-pagination/verify.sh
#
# Ch12 Connections and pagination: Relay cursor connections with opaque keyset
# cursors, forward and backward paging, filters, stability under inserts, bad
# arguments as BAD_USER_INPUT, one failing node nulling one edge, and the N+1
# that hydrating a page causes, on both stacks.
#
# The cases run in a fixed order and handling state carries forward: case 8
# registers evt_10 for DEF456, case 8b evt_11 for ABC123 (and case 9 three more DEF456), so later cases see them.
#
# The cursor is the one thing both stacks must agree on byte for byte: the
# first cargo cursor is computed here from its documented plaintext and
# compared with what each stack returns.
#
# The N+1 baseline of case 11, derived from the seed. Q_FAN pages four cargos
# (VWX901, XYZ789, STU678, DEF456) and asks each for its itinerary legs, with a
# voyage and two locations per leg, and its delivery:
#   booking.listCargos   1                         the page
#   booking.getCargo     4                         CargoEdge.node, once per edge
#   routing.getItinerary 8   = 4 cargos x 2        itinerary and delivery each read it
#   handling.listEvents  4                         delivery, once per cargo
#   voyage.getVoyage     4   = legs 1+0+1+2        V300A, V300A, V100S, V200E
#   location.getLocation 8   = 4 legs x 2          loadLocation and unloadLocation
#   total               29
# Chapter 13 reduces this number; here it is only measured.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch12-pagination"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# base64url without padding of a cursor's plaintext, computed independently of
# both stacks. python3 -I: stdlib only.
cursor_of() {
  python3 -I -c 'import base64, sys; print(base64.urlsafe_b64encode(sys.argv[1].encode()).rstrip(b"=").decode())' "$1"
}
CURSOR_VWX901="$(cursor_of 'cargo|v1|2026-09-29T09:00:00Z|VWX901')"
CURSOR_ABC123="$(cursor_of 'cargo|v1|2026-09-25T09:00:00Z|ABC123')"
CURSOR_V2="$(cursor_of 'cargo|v2|2026-09-29T09:00:00Z|VWX901')"
CURSOR_BAD_TIME="$(cursor_of 'cargo|v1|2026-09-29T09:00:00.5Z|VWX901')"
CURSOR_EXTRA_FIELD="$(cursor_of 'cargo|v1|2026-09-29T09:00:00Z|VWX901|x')"
CURSOR_NOPE="$(cursor_of 'nope')"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
Q_CARGOS='query($f: Int, $a: String, $l: Int, $b: String, $s: RoutingStatus) { cargos(first: $f, after: $a, last: $l, before: $b, routingStatus: $s) { edges { cursor node { trackingId } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } }'
# shellcheck disable=SC2016
Q_HISTORY='query($t: TrackingId!, $f: Int, $a: String, $l: Int, $b: String) { cargo(trackingId: $t) { handlingHistory(first: $f, after: $a, last: $l, before: $b) { edges { cursor node { id } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } } }'
Q_FAN='{ cargos(first: 4) { edges { node { trackingId itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } } delivery { transportStatus } } } } }'
# shellcheck disable=SC2016
REGISTER='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } userErrors { code } } }'

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# expect_json <expected-json> <json-path> <context> — assert a list, an object
# or a null of $resp by parsed equality.
expect_json() {
  assert_json_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# column <edges-path> <field> — a JSON list from $resp: <field> of each edge's
# node (null for an edge whose node is null), or "cursor" for the cursors.
column() {
  python3 -I -c '
import json, sys
value = json.load(sys.stdin)
for part in sys.argv[1].strip(".").split("."):
    value = value[int(part)] if part.isdigit() else value[part]
field = sys.argv[2]

def pick(edge):
    if field == "cursor":
        return edge["cursor"]
    return edge["node"][field] if edge["node"] is not None else None

print(json.dumps([pick(edge) for edge in value]))
' "$1" "$2" <<<"$resp"
}

# expect_column <expected-json> <edges-path> <field> <context>
expect_column() {
  assert_json_eq "$1" "$(column "$2" "$3")" "$stack $4"
}

# expect_page <hasNext> <hasPrevious> <pageInfo-path> <context> — the two flags of a pageInfo.
expect_page() {
  assert_json_eq "[$1,$2]" "$(python3 -I -c '
import json, sys
value = json.load(sys.stdin)
for part in sys.argv[1].strip(".").split("."):
    value = value[part]
print(json.dumps([value["hasNextPage"], value["hasPreviousPage"]]))
' "$3" <<<"$resp")" "$stack $4: hasNextPage, hasPreviousPage"
}

# expect_bad_input <context> <path-json> <message> <data-null-path> <query> [variables]
# A bad argument is an exposed execution error: the code, the exact message and
# the path, with the null where the non-null chain stops.
expect_bad_input() {
  local context="$1" path="$2" message="$3" null_at="$4" query="$5" variables="${6:-}" bad
  bad="$(gql "$url" "$query" "$variables")"
  assert_error_count "$bad" 1 "$stack $context: one error"
  assert_error_path "$bad" "$path" "$stack $context: path"
  assert_error_message_at "$bad" "$path" "$message" "$stack $context: message"
  assert_error_extension "$bad" "$path" code '"BAD_USER_INPUT"' "$stack $context: code"
  assert_error_shape "$bad" execution "$stack $context: execution error shape"
  assert_null_at "$bad" "$null_at" "$stack $context: the null stops here"
}

# run_stack_check <stack> <url>
run_stack_check() {
  local stack="$1" url="$2" resp calls cursor page1_end page2_end c1 evt_cursor

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. Chapter 1's query, delivered: the two events of ABC123, newest first.
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { handlingHistory(first: 2) { edges { node { id } } pageInfo { hasNextPage } } } }')"
  assert_no_errors "$resp" "$stack handlingHistory(first: 2)"
  assert_json_eq '["evt_2","evt_1"]' "$(column .data.cargo.handlingHistory.edges id)" "$stack ABC123 history is newest first"
  assert_json_eq 'false' "$(json_field '.data.cargo.handlingHistory.pageInfo.hasNextPage' <<<"$resp")" "$stack ABC123 history has no next page"

  # 2. Forward paging through the booking index, two cargos at a time, handing
  #    each endCursor to the next after:.
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_CARGOS" '{"f":2}')"
  assert_no_errors "$resp" "$stack page 1"
  expect_column '["VWX901","XYZ789"]' .data.cargos.edges trackingId "page 1"
  expect_page true false .data.cargos.pageInfo "page 1"
  expect "6" '.data.cargos.totalCount' "page 1 totalCount"
  c1="$(json_field '.data.cargos.edges.0.cursor' <<<"$resp")"
  assert_eq "$CURSOR_VWX901" "$c1" "$stack first cursor is the documented encoding, byte for byte"
  assert_eq "$c1" "$(json_field '.data.cargos.pageInfo.startCursor' <<<"$resp")" "$stack startCursor is edges[0].cursor"
  assert_eq "$(json_field '.data.cargos.edges.1.cursor' <<<"$resp")" "$(json_field '.data.cargos.pageInfo.endCursor' <<<"$resp")" "$stack endCursor is edges[1].cursor"
  # Opaque: no cursor shows a tracking id, a time or its own separators.
  assert_body_not_contains "$(column .data.cargos.edges cursor)" "VWX901" "$stack cursors do not show the tracking id"
  assert_body_not_contains "$(column .data.cargos.edges cursor)" "2026" "$stack cursors do not show the time"
  assert_body_not_contains "$(column .data.cargos.edges cursor)" "=" "$stack cursors carry no padding"
  assert_source_call_keys "$(source_calls "$url")" booking listCargos '*' "$stack page 1 asks the index once, unfiltered"
  page1_end="$(json_field '.data.cargos.pageInfo.endCursor' <<<"$resp")"

  resp="$(gql "$url" "$Q_CARGOS" "{\"f\":2,\"a\":\"$page1_end\"}")"
  assert_no_errors "$resp" "$stack page 2"
  expect_column '["STU678","DEF456"]' .data.cargos.edges trackingId "page 2"
  expect_page true true .data.cargos.pageInfo "page 2"
  page2_end="$(json_field '.data.cargos.pageInfo.endCursor' <<<"$resp")"

  resp="$(gql "$url" "$Q_CARGOS" "{\"f\":2,\"a\":\"$page2_end\"}")"
  # Page 3 is [ABC123, GHI345]; GHI345's node fails (case 6 reads the error).
  expect_column '["ABC123",null]' .data.cargos.edges trackingId "page 3"
  expect_page false true .data.cargos.pageInfo "page 3"
  assert_eq "$CURSOR_ABC123" "$(json_field '.data.cargos.edges.0.cursor' <<<"$resp")" "$stack ABC123's cursor is the documented encoding"

  # 6. The edge fuse, read on this page: one error at the node of edge 1, the
  #    edge keeps its cursor, pageInfo and the sibling edge are intact.
  assert_error_count "$resp" 1 "$stack fuse: one error"
  assert_error_path "$resp" '["cargos","edges",1,"node"]' "$stack fuse: path"
  assert_error_message_at "$resp" '["cargos","edges",1,"node"]' "booking service unavailable" "$stack fuse: message"
  assert_error_extension "$resp" '["cargos","edges",1,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack fuse: code"
  assert_error_shape "$resp" execution "$stack fuse: execution error shape"
  assert_null_at "$resp" '.data.cargos.edges.1.node' "$stack fuse: the node is the null"
  assert_eq "$(cursor_of 'cargo|v1|2026-09-24T09:00:00Z|GHI345')" "$(json_field '.data.cargos.edges.1.cursor' <<<"$resp")" "$stack fuse: the failed edge keeps its cursor"
  expect "ABC123" '.data.cargos.edges.0.node.trackingId' "fuse: the sibling edge resolved"
  expect "6" '.data.cargos.totalCount' "fuse: totalCount intact"

  # 3. Backward paging. last:2 before ABC123 is the page just before it, in
  #    connection order; last:2 alone is the end of the index (with the failing
  #    edge, so one error).
  resp="$(gql "$url" "$Q_CARGOS" "{\"l\":2,\"b\":\"$CURSOR_ABC123\"}")"
  assert_no_errors "$resp" "$stack last:2 before ABC123"
  expect_column '["STU678","DEF456"]' .data.cargos.edges trackingId "last:2 before ABC123 keeps connection order"
  expect_page true true .data.cargos.pageInfo "last:2 before ABC123"
  resp="$(gql "$url" "$Q_CARGOS" '{"l":2}')"
  expect_column '["ABC123",null]' .data.cargos.edges trackingId "last:2"
  expect_page false true .data.cargos.pageInfo "last:2"
  assert_error_count "$resp" 1 "$stack last:2: the GHI345 edge fails alone"
  assert_error_path "$resp" '["cargos","edges",1,"node"]' "$stack last:2: path"
  assert_null_at "$resp" '.data.cargos.edges.1.node' "$stack last:2: null node"

  # 4. A filter pushed down to the index, and the stored status agrees with the
  #    derived one.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargos(routingStatus: MISROUTED) { edges { node { trackingId delivery { routingStatus } } } totalCount } }')"
  assert_no_errors "$resp" "$stack MISROUTED"
  expect_column '["STU678"]' .data.cargos.edges trackingId "MISROUTED cargos"
  expect "MISROUTED" '.data.cargos.edges.0.node.delivery.routingStatus' "MISROUTED stored status equals derived"
  expect "1" '.data.cargos.totalCount' "MISROUTED totalCount"
  assert_source_call_keys "$(source_calls "$url")" booking listCargos MISROUTED "$stack MISROUTED asks the index once, with the filter"
  resp="$(gql "$url" '{ cargos(routingStatus: NOT_ROUTED) { edges { node { trackingId delivery { routingStatus } } } totalCount } }')"
  expect_column '["XYZ789",null]' .data.cargos.edges trackingId "NOT_ROUTED cargos (GHI345's node fails)"
  expect "NOT_ROUTED" '.data.cargos.edges.0.node.delivery.routingStatus' "NOT_ROUTED stored status equals derived"
  expect "2" '.data.cargos.totalCount' "NOT_ROUTED totalCount"
  assert_error_path "$resp" '["cargos","edges",1,"node"]' "$stack NOT_ROUTED: the failing edge"
  resp="$(gql "$url" '{ cargos(routingStatus: ROUTED) { edges { node { trackingId delivery { routingStatus } } } totalCount } }')"
  assert_no_errors "$resp" "$stack ROUTED"
  expect_column '["VWX901","DEF456","ABC123"]' .data.cargos.edges trackingId "ROUTED cargos"
  assert_json_eq '["ROUTED","ROUTED","ROUTED"]' "$(python3 -I -c '
import json, sys
print(json.dumps([e["node"]["delivery"]["routingStatus"] for e in json.load(sys.stdin)["data"]["cargos"]["edges"]]))
' <<<"$resp")" "$stack ROUTED stored status equals derived"
  expect "3" '.data.cargos.totalCount' "ROUTED totalCount"

  # 5. An empty page is not an absent one: no edges, no cursors, more to read.
  resp="$(gql "$url" "$Q_CARGOS" '{"f":0}')"
  assert_no_errors "$resp" "$stack first:0"
  expect_json '[]' '.data.cargos.edges' "first:0 has no edges"
  expect_page true false .data.cargos.pageInfo "first:0"
  assert_null_at "$resp" '.data.cargos.pageInfo.startCursor' "$stack first:0 startCursor"
  assert_null_at "$resp" '.data.cargos.pageInfo.endCursor' "$stack first:0 endCursor"
  expect "6" '.data.cargos.totalCount' "first:0 still counts"

  # 7. Bad arguments are exposed execution errors with the code BAD_USER_INPUT.
  #    Query.cargos is non-null, so the null climbs to data; handlingHistory is
  #    non-null, so it climbs to cargo.
  expect_bad_input "first:-1" '["cargos"]' "first must be between 0 and 50" .data '{ cargos(first: -1) { totalCount } }'
  expect_bad_input "first:51" '["cargos"]' "first must be between 0 and 50" .data '{ cargos(first: 51) { totalCount } }'
  expect_bad_input "last:51" '["cargos"]' "last must be between 0 and 50" .data '{ cargos(last: 51) { totalCount } }'
  expect_bad_input "first and last" '["cargos"]' "first and last cannot be combined" .data '{ cargos(first: 1, last: 1) { totalCount } }'
  expect_bad_input "after: not a cursor" '["cargos"]' "after is not a valid cursor for this connection" .data \
    "{ cargos(after: \"$CURSOR_NOPE\") { totalCount } }"
  expect_bad_input "before: not a cursor" '["cargos"]' "before is not a valid cursor for this connection" .data \
    "{ cargos(before: \"$CURSOR_NOPE\") { totalCount } }"
  expect_bad_input "after: padded" '["cargos"]' "after is not a valid cursor for this connection" .data \
    "{ cargos(after: \"${CURSOR_VWX901}==\") { totalCount } }"
  expect_bad_input "after: unknown version" '["cargos"]' "after is not a valid cursor for this connection" .data \
    "{ cargos(after: \"$CURSOR_V2\") { totalCount } }"
  expect_bad_input "after: time with a fraction" '["cargos"]' "after is not a valid cursor for this connection" .data \
    "{ cargos(after: \"$CURSOR_BAD_TIME\") { totalCount } }"
  expect_bad_input "after: extra field" '["cargos"]' "after is not a valid cursor for this connection" .data \
    "{ cargos(after: \"$CURSOR_EXTRA_FIELD\") { totalCount } }"
  resp="$(gql "$url" "$Q_HISTORY" '{"t":"ABC123","f":1}')"
  evt_cursor="$(json_field '.data.cargo.handlingHistory.edges.0.cursor' <<<"$resp")"
  expect_bad_input "event cursor to cargos" '["cargos"]' "after is not a valid cursor for this connection" .data \
    "{ cargos(after: \"$evt_cursor\") { totalCount } }"
  expect_bad_input "cargo cursor to handlingHistory" '["cargo","handlingHistory"]' "after is not a valid cursor for this connection" .data.cargo \
    "{ cargo(trackingId: \"DEF456\") { trackingId handlingHistory(after: \"$CURSOR_VWX901\") { totalCount } } }"
  expect_bad_input "handlingHistory first:51" '["cargo","handlingHistory"]' "first must be between 0 and 50" .data.cargo \
    '{ cargo(trackingId: "DEF456") { handlingHistory(first: 51) { totalCount } } }'
  # The limits are inclusive.
  resp="$(gql "$url" '{ cargos(first: 50) { edges { cursor } } }')"
  assert_no_errors "$resp" "$stack first:50 is allowed"

  # 8. Stability under inserts. Page through DEF456's history three at a time and
  #    register a late event between the pages: it lands in the range already
  #    read, so the next page neither repeats nor skips.
  resp="$(gql "$url" "$Q_HISTORY" '{"t":"DEF456","f":3}')"
  assert_no_errors "$resp" "$stack DEF456 history page 1"
  expect_column '["evt_9","evt_8","evt_7"]' .data.cargo.handlingHistory.edges id "DEF456 history page 1"
  expect "7" '.data.cargo.handlingHistory.totalCount' "DEF456 history totalCount"
  page1_end="$(json_field '.data.cargo.handlingHistory.pageInfo.endCursor' <<<"$resp")"
  assert_eq "$(cursor_of 'evt|v1|2026-10-11T18:20:00Z|7')" "$page1_end" "$stack the event cursor is the documented encoding"
  resp="$(gql "$url" "$REGISTER" '{"i":{"trackingId":"DEF456","type":"CUSTOMS","location":"NLRTM","completionTime":"2026-10-11T20:00:00Z"}}')"
  assert_no_errors "$resp" "$stack late registration"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "the late event is evt_10"
  resp="$(gql "$url" "$Q_HISTORY" "{\"t\":\"DEF456\",\"f\":3,\"a\":\"$page1_end\"}")"
  assert_no_errors "$resp" "$stack DEF456 history page 2"
  expect_column '["evt_6","evt_5","evt_4"]' .data.cargo.handlingHistory.edges id "page 2 after the insert: no repeat of evt_7, no skip"
  expect_page true true .data.cargo.handlingHistory.pageInfo "DEF456 page 2"
  page2_end="$(json_field '.data.cargo.handlingHistory.pageInfo.endCursor' <<<"$resp")"
  resp="$(gql "$url" "$Q_HISTORY" "{\"t\":\"DEF456\",\"f\":3,\"a\":\"$page2_end\"}")"
  expect_column '["evt_3"]' .data.cargo.handlingHistory.edges id "page 3"
  expect_page false true .data.cargo.handlingHistory.pageInfo "DEF456 page 3"
  resp="$(gql "$url" "$Q_HISTORY" '{"t":"DEF456","f":3}')"
  expect_column '["evt_9","evt_8","evt_10"]' .data.cargo.handlingHistory.edges id "a fresh first page now ends at evt_10 (offset 3 would start at evt_7 again)"
  expect "8" '.data.cargo.handlingHistory.totalCount' "totalCount after the insert"
  # What an offset page would have returned: skip 3, take 3 on a fresh read.
  # evt_7 was the last item of keyset page 1, so offset repeats it.
  resp="$(gql "$url" "$Q_HISTORY" '{"t":"DEF456","f":6}')"
  assert_no_errors "$resp" "$stack DEF456 history first:6 after the insert"
  assert_json_eq '["evt_7","evt_6","evt_5"]' "$(column .data.cargo.handlingHistory.edges id | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[3:6]))')" "$stack offset 3 would return evt_7, evt_6, evt_5: evt_7 again"

  # 8b. A sub-second completionTime. The store keeps whole seconds because the
  #     cursor encodes the sort key at that precision: the event sorts first in
  #     ABC123's history, the cursor carries the whole second, and the next page
  #     skips nothing. (Registered after case 8 so evt_10 stays the DEF456 event.)
  resp="$(gql "$url" "$REGISTER" '{"i":{"trackingId":"ABC123","type":"CUSTOMS","location":"USNYC","completionTime":"2026-10-02T09:00:00.5Z"}}')"
  assert_no_errors "$resp" "$stack sub-second registration"
  expect "evt_11" '.data.registerHandlingEvent.handlingEvent.id' "the sub-second event is evt_11"
  resp="$(gql "$url" "$Q_HISTORY" '{"t":"ABC123","f":1}')"
  assert_no_errors "$resp" "$stack ABC123 history page 1 with the sub-second event"
  expect_column '["evt_11"]' .data.cargo.handlingHistory.edges id "the sub-second event sorts first"
  expect_page true false .data.cargo.handlingHistory.pageInfo "ABC123 page 1"
  evt_cursor="$(json_field '.data.cargo.handlingHistory.pageInfo.endCursor' <<<"$resp")"
  assert_eq "$(cursor_of 'evt|v1|2026-10-02T09:00:00Z|11')" "$evt_cursor" "$stack the cursor carries the whole second"
  echo "$stack sub-second event cursor: $evt_cursor"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { handlingHistory(first: 1) { edges { node { id completionTime } } } } }')"
  expect "2026-10-02T09:00:00Z" '.data.cargo.handlingHistory.edges.0.node.completionTime' "the stored completionTime is whole seconds"
  echo "$stack sub-second event completionTime: $(json_field '.data.cargo.handlingHistory.edges.0.node.completionTime' <<<"$resp")"
  resp="$(gql "$url" "$Q_HISTORY" "{\"t\":\"ABC123\",\"f\":1,\"a\":\"$evt_cursor\"}")"
  assert_no_errors "$resp" "$stack ABC123 history page 2 after the sub-second cursor"
  expect_column '["evt_2"]' .data.cargo.handlingHistory.edges id "no skip after the sub-second cursor"
  expect_page true true .data.cargo.handlingHistory.pageInfo "ABC123 page 2"

  # 9. The end of the history: last:2 is the two oldest events, in connection order.
  resp="$(gql "$url" "$Q_HISTORY" '{"t":"DEF456","l":2}')"
  assert_no_errors "$resp" "$stack DEF456 last:2"
  expect_column '["evt_4","evt_3"]' .data.cargo.handlingHistory.edges id "last:2 is the oldest two, newest of them first"
  expect_page false true .data.cargo.handlingHistory.pageInfo "DEF456 last:2"

  # The default page size is 10 when neither first nor last is given: three more
  # late events (none later than the CLAIM) make eleven.
  local minute
  for minute in 21 22 23; do
    resp="$(gql "$url" "$REGISTER" "{\"i\":{\"trackingId\":\"DEF456\",\"type\":\"CUSTOMS\",\"location\":\"NLRTM\",\"completionTime\":\"2026-10-11T${minute}:00:00Z\"}}")"
    assert_no_errors "$resp" "$stack registering the event of ${minute}:00"
  done
  resp="$(gql "$url" '{ cargo(trackingId: "DEF456") { handlingHistory { edges { node { id } } pageInfo { hasNextPage } totalCount } delivery { transportStatus } } }')"
  assert_no_errors "$resp" "$stack default page size"
  assert_eq "10" "$(json_field '.data.cargo.handlingHistory.edges' <<<"$resp" | json_len .)" "$stack the default page holds 10 edges"
  expect_json 'true' '.data.cargo.handlingHistory.pageInfo.hasNextPage' "the default page has a next page"
  expect "11" '.data.cargo.handlingHistory.totalCount' "totalCount of eleven"
  expect "CLAIMED" '.data.cargo.delivery.transportStatus' "late events do not change the derived status"

  # 10. No argument prints a default: a "= null" in the SDL would be a
  #     dangerous change nothing else catches.
  # (graphql-java's introspection guard allows __Type.fields once per request.)
  local owner field_name defaults
  for owner in "Query cargos" "Cargo handlingHistory"; do
    read -r owner field_name <<<"$owner"
    # shellcheck disable=SC2016
    resp="$(gql "$url" 'query Args($n: String!) { __type(name: $n) { fields { name args { name defaultValue } } } }' "{\"n\":\"$owner\"}")"
    assert_no_errors "$resp" "$stack $owner argument defaults"
    defaults="$(python3 -I -c '
import json, sys
fields = json.load(sys.stdin)["data"]["__type"]["fields"]
field = next(f for f in fields if f["name"] == sys.argv[1])
print(json.dumps({a["name"]: a["defaultValue"] for a in field["args"]}))
' "$field_name" <<<"$resp")"
    case "$field_name" in
      cargos) assert_json_eq '{"first":null,"after":null,"last":null,"before":null,"routingStatus":null}' "$defaults" "$stack Query.cargos: every defaultValue is null" ;;
      *) assert_json_eq '{"first":null,"after":null,"last":null,"before":null}' "$defaults" "$stack Cargo.handlingHistory: every defaultValue is null" ;;
    esac
  done

  # 11. The N+1 baseline Chapter 13 reduces (arithmetic in the header).
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_FAN")"
  assert_no_errors "$resp" "$stack Q_FAN"
  expect_column '["VWX901","XYZ789","STU678","DEF456"]' .data.cargos.edges trackingId "Q_FAN page"
  calls="$(source_calls "$url")"
  assert_source_call_count "$calls" '*' '*' 29 "$stack Q_FAN: 29 source calls"
  assert_source_call_count "$calls" booking listCargos 1 "$stack Q_FAN booking.listCargos"
  assert_source_call_count "$calls" booking getCargo 4 "$stack Q_FAN booking.getCargo"
  assert_source_call_count "$calls" routing getItinerary 8 "$stack Q_FAN routing.getItinerary"
  assert_source_call_count "$calls" handling listEvents 4 "$stack Q_FAN handling.listEvents"
  assert_source_call_count "$calls" voyage getVoyage 4 "$stack Q_FAN voyage.getVoyage"
  assert_source_call_count "$calls" location getLocation 8 "$stack Q_FAN location.getLocation"
  assert_source_call_keys "$calls" voyage getVoyage V300A,V300A,V100S,V200E "$stack Q_FAN: V300A is fetched twice"

  # 12. The same N+1 through nodes(ids:): one call per id.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ nodes(ids: ["cargo_ABC123", "cargo_XYZ789", "loc_DEHAM", "loc_NLRTM", "voy_V100S"]) { id } }')"
  assert_no_errors "$resp" "$stack nodes"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 5 "$stack nodes: five ids, five source calls"
  # A bare prefix and an empty key are unrecognised ids: null, no source call.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ nodes(ids: ["cargo", "evt", "cargo_"]) { id } }')"
  assert_no_errors "$resp" "$stack nodes with bare prefixes"
  expect_json '[null,null,null]' '.data.nodes' "bare prefixes and an empty key give null"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack nodes with bare prefixes calls no source"

  # 13. The deprecation of Chapter 11, carried by this slice.
  assert_deprecated "$url" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_not_deprecated "$url" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime"
  resp="$(gql "$url" '{ cargo(trackingId: "DEF456") { itinerary { finalArrivalTime finalArrivalDate } delivery { estimatedTimeOfArrival } } }')"
  assert_no_errors "$resp" "$stack finalArrival fields"
  expect "2026-10-11T18:00:00Z" '.data.cargo.itinerary.finalArrivalTime' "finalArrivalTime"
  expect "2026-10-11T18:00:00Z" '.data.cargo.itinerary.finalArrivalDate' "finalArrivalDate, deprecated but equal"
  expect "2026-10-11T18:00:00Z" '.data.cargo.delivery.estimatedTimeOfArrival' "DEF456's ETA"

  # 14. The custom scalars, and the live schema against the canonical SDL: only
  #     Subscription is left to serve.
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

  echo "=== $stack: pagination check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8220/graphql"
run_stack_check "python" "http://localhost:8221/graphql"

echo
echo "PASS - Ch12 Connections and pagination: Quarkus (SmallRye GraphQL) and Python (Strawberry)" \
     "return byte-identical opaque keyset cursors, page forward and backward with exact hasNextPage" \
     "and hasPreviousPage, push the routingStatus filter down to the booking index, keep a page stable" \
     "when a late event is registered, reject bad arguments as BAD_USER_INPUT, null one edge when its" \
     "node fails, measure the 29 source calls that hydrating four cargos takes, and conform to the" \
     "canonical SDL except for Subscription."
