#!/usr/bin/env bash
# examples/16-caching/verify.sh
#
# Ch16 Caching: four places to keep an answer, and the three this example builds.
#
#   edge (nginx proxy_cache, 8262/8263)  honours the server's Cache-Control; a persisted GET
#                                        of reference data is a HIT with no source call,
#                                        a request with Authorization is a BYPASS
#   server policy (CachePolicy)          Cache-Control per response: public, max-age=300 for
#                                        an error-free anonymous GET of reference data,
#                                        no-store for everything else
#   field-level source caches            voyages and locations for 300 s, a cargo's handling
#                                        events for 20 s here (60 s by default), evicted when
#                                        registerHandlingEvent appends
#
# Direct ports (8260/8261) carry the server-cache cases and the source-call log; the edge
# ports (8262/8263) carry the HTTP cases. A cache hit is not a source call: only calls to the
# owners are logged, so "0 calls" below means "answered from a cache".
#
# The cases run in a fixed order because cache state carries forward, and the order is
# part of the design: the first cases warm exactly the keys the later counts expect.
# Every TTL case uses whole seconds (20 s TTL, sleep 21).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch16-caching"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
MANIFEST="$SCRIPT_DIR/persisted-documents.json"

# manifest_field <operation-name> <id|body> — one field of the manifest, read independently of both stacks.
manifest_field() {
  python3 -I -c '
import json, sys
operations = json.load(open(sys.argv[1]))["operations"]
print(next(op[sys.argv[3]] for op in operations if op["name"] == sys.argv[2]))
' "$MANIFEST" "$1" "$2"
}

Q_TRACK="$(manifest_field TrackCargo body)"
Q_PORT="$(manifest_field PortName body)"
Q_REG="$(manifest_field RegisterHandling body)"
H_TRACK="$(sha256_hex "$Q_TRACK")"
H_PORT="$(sha256_hex "$Q_PORT")"
H_REG="$(sha256_hex "$Q_REG")"

# Chapter 13's fan-out: four cargos with itineraries, legs and deliveries.
Q_FAN='{ cargos(first: 4) { edges { node { trackingId itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } } delivery { transportStatus } } } } }'
# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
Q_STATUS='query($id: TrackingId!) { cargo(trackingId: $id) { delivery { transportStatus } } }'
Q_VOYAGE='{ voyage(voyageNumber: "V200E") { number } }'
Q_VOYAGE_BULK_WARMED='{ voyage(voyageNumber: "V100S") { number } }'
# A selection no type has: a validation error, so an error-carrying GET.
Q_BAD='{ location(unLocode: "NLRTM") { weight } }'

V_PORT_NLRTM='{"code":"NLRTM"}'
V_PORT_USNYC='{"code":"USNYC"}'
V_PORT_SGSIN='{"code":"SGSIN"}'
V_PORT_CNSHA='{"code":"CNSHA"}'
V_TRACK='{"id":"ABC123"}'
V_REG='{"i":{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z","idempotencyKey":"k-cache-1"}}'

# Hash-only GETs need Accept: application/json: Strawberry serves its IDE page when Accept
# includes text/html or */*, and nginx forwards the header as sent.
JSON_ACCEPT=(-H 'Accept: application/json')

BEARER=(-H 'Authorization: Bearer x')

SCRATCH="$(mktemp -d)"
on_exit 'rm -rf "$SCRATCH"'

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# urlenc <text> — URL-encode, for a query string.
urlenc() {
  python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

# post_apq <url> <query-or-empty> <hash> [variables-json] — an APQ POST; sets $resp.
post_apq() {
  resp="$(body_of "$(gql_raw "$1" "$(apq_body "$2" "$3" "${4:-}")")")"
}

# request_full <method> <url> [curl-args] — a request with Accept: application/json; sets
# $status, $resp and $hdrs (the response headers, one "Name: value" per line).
request_full() {
  local method="$1" url="$2" out
  shift 2
  out="$(http_any "$method" "$url" "${JSON_ACCEPT[@]}" "$@" -D "$SCRATCH/headers")"
  status="$(status_of "$out")"
  resp="$(body_of "$out")"
  hdrs="$(tr -d '\r' <"$SCRATCH/headers")"
}

# get_full <url> [curl-args] — request_full for a GET.
get_full() {
  local url="$1"
  shift
  request_full GET "$url" "$@"
}

# call_keys <calls-json> — the sorted source.op:key entries of the log, comma-joined.
call_keys() {
  python3 -I -c '
import json, sys
print(",".join(sorted("%s.%s:%s" % (c["source"], c["op"], c["key"]) for c in json.load(sys.stdin)["calls"])))
' <<<"$1"
}

# get_variant <n> <document> — the query-string value for variant <n> of a mutation document.
get_variant() {
  python3 -I -c '
import sys, urllib.parse
n, text = int(sys.argv[1]), sys.argv[2]
word, _, rest = text.partition(" ")
value = "%{:02x}".format(ord(word[0])) + word[1:]
for _ in range(n - 1):
    value = urllib.parse.quote(value, safe="")
print(value + urllib.parse.quote(" " + rest, safe=""))
' "$1" "$2"
}

# ws_upgrade_status <port> <header-line>... — the HTTP status the endpoint answers to a WebSocket upgrade
# (graphql-transport-ws) carrying the given header lines. If the upgrade is accepted, a mutation is sent
# over the socket, so a registration that got through shows in the source-call log.
ws_upgrade_status() {
  python3 -I -c '
import base64, json, os, socket, struct, sys
port = int(sys.argv[1])
lines = "".join(line + "\r\n" for line in sys.argv[2:])
mutation = ("mutation { registerHandlingEvent(input: {trackingId: \"ABC123\", type: UNLOAD, location: \"DEHAM\", "
            "voyageNumber: \"V100S\", completionTime: \"2026-10-09T15:00:00Z\", idempotencyKey: \"ws-%s\"}) { handlingEvent { id } } }" % os.urandom(3).hex())
with socket.create_connection(("localhost", port), timeout=10) as s:
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(("GET /graphql HTTP/1.1\r\nHost: localhost:%d\r\n%sConnection: Upgrade\r\n"
               "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: graphql-transport-ws\r\n\r\n" % (port, lines, key)).encode())
    reader = s.makefile("rb")
    status = reader.readline().decode().split()[1]
    print(status)
    if status == "101":
        while reader.readline() not in (b"\r\n", b""):
            pass
        def send(message):
            data = json.dumps(message).encode(); mask = os.urandom(4); n = len(data)
            head = bytes([0x81]) + (bytes([0x80 | n]) if n < 126 else bytes([0xFE]) + struct.pack(">H", n))
            s.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
        send({"type": "connection_init"})
        reader.read(2)
        send({"id": "1", "type": "subscribe", "payload": {"query": mutation}})
        reader.read(2)
' "$@"
}

# unmatched_operation_name <graphql-url> <calls-url> <context> — a single-operation mutation sent over GET, by
# text and by hash, with an operationName that names no operation and with an empty one. Each is refused with
# no data, and nothing is written.
unmatched_operation_name() {
  local target="$1" calls_url="$2" context="$3" name form qs out want ext body
  ext="$(urlenc "{\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"$H_REG\"}}")"
  for name in Nope ''; do
    for form in text hash; do
      if [[ "$form" == text ]]; then qs="query=$(urlenc "$Q_REG")"; else qs="extensions=$ext"; fi
      case "$stack:$name" in
        quarkus:) want=405 ;;
        *) want=400 ;;
      esac
      source_calls_reset "$calls_url"
      out="$(http_any GET "$target?$qs&variables=$(urlenc "$V_REG")&operationName=$name" "${JSON_ACCEPT[@]}")"
      body="$(body_of "$out")"
      assert_status_in "$want" "$(status_of "$out")" "$stack $context GET mutation by $form, operationName='$name': status"
      assert_body_not_contains "$body" '"data"' "$stack $context GET mutation by $form, operationName='$name'"
      if [[ "$stack:$name" == quarkus:Nope ]]; then
        assert_error_extension "$body" 'null' code '"BAD_USER_INPUT"' "$stack $context GET mutation by $form, operationName='$name': code"
        assert_error_message_at "$body" 'null' "operationName does not match an operation in the document" "$stack $context GET mutation by $form, operationName='$name': message"
      fi
      assert_source_call_count "$(source_calls "$calls_url")" handling appendEvent 0 "$stack $context GET mutation by $form, operationName='$name': nothing was written"
    done
  done
}

# run_stack_check <stack> <direct-graphql-url> <edge-graphql-url>
run_stack_check() {
  local stack="$1" url="$2" edge="$3" resp status hdrs calls out

  echo
  echo "=== verifying stack '$stack' directly at $url and through the edge at $edge ==="

  wait_for_graphql "$url"
  wait_for_http "$edge?query=%7B__typename%7D"

  # 1. Register PortName for NLRTM by POST: APQ step two. This reads Rotterdam, so the
  #    location cache holds NLRTM from here on.
  post_apq "$url" "$Q_PORT" "$H_PORT" "$V_PORT_NLRTM"
  assert_no_errors "$resp" "$stack PortName registered"
  expect "Rotterdam" '.data.location.name' "PortName registered: Rotterdam"

  # 2. The edge: a persisted GET of reference data is stored by the first request and served
  #    by the second without reaching the server. USNYC is a key nothing has read yet.
  source_calls_reset "$url"
  get_full "$(apq_get_url "$edge" "$H_PORT" "$V_PORT_USNYC")"
  assert_status_in "200" "$status" "$stack edge GET 1: status"
  assert_no_errors "$resp" "$stack edge GET 1"
  expect "New York" '.data.location.name' "edge GET 1: New York"
  assert_header "$hdrs" cache-control "public, max-age=300" "$stack edge GET 1: Cache-Control"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET 1: X-Cache-Status"
  assert_source_calls_exactly "$(source_calls "$url")" "location.getLocation:USNYC" "$stack edge GET 1: one call to the location owner"
  local first_body="$resp"
  source_calls_reset "$url"
  get_full "$(apq_get_url "$edge" "$H_PORT" "$V_PORT_USNYC")"
  assert_header "$hdrs" x-cache-status HIT "$stack edge GET 2: X-Cache-Status"
  assert_header "$hdrs" cache-control "public, max-age=300" "$stack edge GET 2: Cache-Control on the HIT"
  assert_eq "$first_body" "$resp" "$stack edge GET 2: the stored body"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack edge GET 2: no source call"

  # 3. Single-key reference reads: the first V200E read calls the voyage owner, the second
  #    is answered by the voyages cache (Quarkus: @CacheResult; Python: TTLCache).
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_VOYAGE")"
  assert_no_errors "$resp" "$stack voyage V200E, first read"
  expect "V200E" '.data.voyage.number' "voyage V200E, first read"
  assert_source_calls_exactly "$(source_calls "$url")" "voyage.getVoyage:V200E" "$stack voyage V200E, first read: one owner call"
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_VOYAGE")"
  expect "V200E" '.data.voyage.number' "voyage V200E, second read"
  assert_source_call_count "$(source_calls "$url")" voyage '*' 0 "$stack voyage V200E, second read: no voyage call"

  # 3b. An unknown key. Quarkus' @CacheResult stores the null, so the second read makes no call;
  #     Python's cache holds only found values, so both reads reach the owner.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ voyage(voyageNumber: "V999X") { number } }')"
  assert_no_errors "$resp" "$stack unknown voyage, first read"
  resp="$(gql "$url" '{ voyage(voyageNumber: "V999X") { number } }')"
  assert_no_errors "$resp" "$stack unknown voyage, second read"
  case "$stack" in
    quarkus) assert_source_call_count "$(source_calls "$url")" voyage getVoyage 1 "$stack unknown voyage twice: negative caching, one owner call" ;;
    python) assert_source_call_count "$(source_calls "$url")" voyage getVoyage 2 "$stack unknown voyage twice: not cached, two owner calls" ;;
  esac

  # 4. Q_FAN twice. Run 1 still calls every owner whose keys are not cached; run 2, inside the
  #    handling TTL, calls only the booking and routing owners. The cache holds NLRTM, USNYC and
  #    V200E from the cases above, so run 1's location and voyage keys are the misses only.
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_FAN")"
  assert_no_errors "$resp" "$stack Q_FAN run 1"
  calls="$(source_calls "$url")"
  case "$stack" in
    python)
      assert_source_call_count "$calls" '*' '*' 6 "$stack Q_FAN run 1: 6 calls, as in Chapter 13"
      assert_source_call_keys "$calls" location getLocations CNSHA+DEHAM+SGSIN "$stack Q_FAN run 1: only the uncached locations"
      ;;
    quarkus)
      assert_source_call_count "$calls" '*' '*' 8 "$stack Q_FAN run 1: 8 calls, as in Chapter 13"
      assert_source_call_keys "$calls" location getLocations DEHAM+SGSIN,CNSHA+DEHAM "$stack Q_FAN run 1: only the uncached locations, one call per field"
      ;;
  esac
  assert_source_call_keys "$calls" voyage getVoyages V100S+V300A "$stack Q_FAN run 1: only the uncached voyages"
  assert_source_call_keys "$calls" handling listEventsFor DEF456+STU678+VWX901+XYZ789 "$stack Q_FAN run 1: every cargo's events"
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_FAN")"
  assert_no_errors "$resp" "$stack Q_FAN run 2"
  expect "DEF456" '.data.cargos.edges.3.node.trackingId' "Q_FAN run 2: fourth cargo"
  calls="$(source_calls "$url")"
  case "$stack" in
    python)
      assert_source_calls_exactly "$calls" "booking.listCargos:*,booking.getCargos:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789" \
        "$stack Q_FAN run 2: 3 calls, none to voyage, location or handling"
      ;;
    quarkus)
      assert_source_calls_exactly "$calls" "booking.listCargos:*,booking.getCargos:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789" \
        "$stack Q_FAN run 2: 4 calls, none to voyage, location or handling"
      ;;
  esac
  # The bulk read warmed the single-key path: V100S was never read on its own.
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_VOYAGE_BULK_WARMED")"
  expect "V100S" '.data.voyage.number' "voyage V100S after the bulk read"
  assert_source_call_count "$(source_calls "$url")" voyage '*' 0 "$stack voyage V100S: filled by the bulk read, no voyage call"

  # 5. Cache-Control per response, read at the server.
  get_full "$(apq_get_url "$url" "$H_PORT" "$V_PORT_NLRTM")"
  assert_header "$hdrs" cache-control "public, max-age=300" "$stack direct GET PortName"
  assert_no_errors "$resp" "$stack direct GET PortName"
  expect "Rotterdam" '.data.location.name' "direct GET PortName: Rotterdam"
  request_full POST "$url" -H 'Content-Type: application/json' -d "$(apq_body '' "$H_PORT" "$V_PORT_NLRTM")"
  assert_header "$hdrs" cache-control "no-store" "$stack direct POST PortName"
  assert_no_errors "$resp" "$stack direct POST PortName"
  expect "Rotterdam" '.data.location.name' "direct POST PortName: Rotterdam"
  # TrackCargo is registered first (by POST), then read by GET: it is not reference data.
  post_apq "$url" "$Q_TRACK" "$H_TRACK" "$V_TRACK"
  assert_no_errors "$resp" "$stack TrackCargo registered"
  get_full "$(apq_get_url "$url" "$H_TRACK" "$V_TRACK")"
  assert_header "$hdrs" cache-control "no-store" "$stack direct GET TrackCargo"
  assert_no_errors "$resp" "$stack direct GET TrackCargo"
  expect "ABC123" '.data.cargo.trackingId' "direct GET TrackCargo: ABC123"
  request_full GET "$url?query=$(urlenc "$Q_BAD")"
  assert_header "$hdrs" cache-control "no-store" "$stack direct GET with a validation error"
  assert_has_errors "$resp" "$stack direct GET with a validation error: body"
  assert_no_data "$resp" "$stack direct GET with a validation error: no data"
  get_full "$(apq_get_url "$url" "$H_PORT" "$V_PORT_NLRTM")" "${BEARER[@]}"
  assert_header "$hdrs" cache-control "no-store" "$stack direct GET PortName with Authorization"
  assert_no_errors "$resp" "$stack direct GET PortName with Authorization"
  expect "Rotterdam" '.data.location.name' "direct GET PortName with Authorization: Rotterdam"
  # An unregistered hash is the handshake's first step (Chapter 15). It must not be stored either.
  get_full "$(apq_get_url "$url" "$(sha256_hex 'never registered')")"
  assert_error_message_at "$resp" 'null' PersistedQueryNotFound "$stack unknown hash: message"
  assert_error_extension "$resp" 'null' code '"PERSISTED_QUERY_NOT_FOUND"' "$stack unknown hash: code"
  assert_header "$hdrs" cache-control "no-store" "$stack unknown hash: Cache-Control"

  # 5b. GET guards carried over from Chapter 15, in APQ mode. A mutation stays off GET; a document
  #     that does not parse is a client error on Quarkus; '+' and '%' in a document and in variables
  #     reach the source unchanged; and this example serves HTTP only, so an Upgrade request is refused.
  source_calls_reset "$url"
  status="$(status_of "$(http_any GET "$url?query=$(get_variant 1 "$Q_REG")&variables=$(urlenc "$V_REG")" "${JSON_ACCEPT[@]}")")"
  case "$stack" in
    python) assert_status_in "400" "$status" "$stack GET mutation variant: status" ;;
    quarkus) assert_status_in "405" "$status" "$stack GET mutation variant: status" ;;
  esac
  assert_source_call_count "$(source_calls "$url")" handling appendEvent 0 "$stack GET mutation variant: nothing was written"
  status="$(status_of "$(http_any GET "$url?query=$(get_variant 2 "$Q_REG")&variables=$(urlenc "$V_REG")" "${JSON_ACCEPT[@]}")")"
  case "$stack" in
    python) assert_status_in "200" "$status" "$stack GET unparseable document: status" ;;
    quarkus) assert_status_in "400" "$status" "$stack GET unparseable document: status" ;;
  esac
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack GET unparseable document: no source call"
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  local q_lit='query { cargo(trackingId: "A+B%41 C") { trackingId } }' q_var='query Lit($id: TrackingId!) { cargo(trackingId: $id) { trackingId } }'
  source_calls_reset "$url"
  status="$(status_of "$(http_any GET "$url?query=$(urlenc "$q_lit")" "${JSON_ACCEPT[@]}")")"
  assert_status_in "200" "$status" "$stack GET literal % and +: status"
  assert_eq "booking.getCargo:A+B%41 C" "$(call_keys "$(source_calls "$url")")" "$stack GET literal % and + in the document"
  source_calls_reset "$url"
  status="$(status_of "$(http_any GET "$url?query=$(urlenc "$q_var")&variables=$(urlenc '{"id":"D+E%42 F"}')" "${JSON_ACCEPT[@]}")")"
  assert_status_in "200" "$status" "$stack GET literal % and + in variables: status"
  assert_eq "booking.getCargo:D+E%42 F" "$(call_keys "$(source_calls "$url")")" "$stack GET literal % and + in variables"
  # The same texts by hash over POST: the source receives the registered text unchanged.
  post_apq "$url" "$q_lit" "$(sha256_hex "$q_lit")"
  source_calls_reset "$url"
  post_apq "$url" '' "$(sha256_hex "$q_lit")"
  assert_no_errors "$resp" "$stack literal document by hash over POST"
  assert_eq "booking.getCargo:A+B%41 C" "$(call_keys "$(source_calls "$url")")" "$stack POST by hash: the executed text equals the stored text"
  local q_pct='query { cargo(trackingId: "100%") { trackingId } }'
  post_apq "$url" "$q_pct" "$(sha256_hex "$q_pct")"
  source_calls_reset "$url"
  out="$(gql_raw "$url" "$(apq_body '' "$(sha256_hex "$q_pct")")")"
  assert_status_in "200" "$(status_of "$out")" "$stack POST by hash, document with a lone %: status"
  assert_eq "booking.getCargo:100%" "$(call_keys "$(source_calls "$url")")" "$stack POST by hash, document with a lone %"
  # An operationName that selects no operation is refused, an empty one is treated as absent, and a
  # GET with a body is answered like any GET.
  post_apq "$url" "$Q_REG" "$H_REG"
  unmatched_operation_name "$url" "$url" "direct"
  unmatched_operation_name "$edge" "$url" "edge"
  out="$(http_any GET "$url" "${JSON_ACCEPT[@]}" -H 'Content-Type: application/x-www-form-urlencoded' --data 'a=b')"
  assert_body_not_contains "$(status_of "$out")" "500" "$stack GET with a form body: answered"
  if [[ "$stack" == quarkus ]]; then
    local ws_form ws_out
    local -a ws_lines
    for ws_form in 'Upgrade: websocket' 'Upgrade: foo|Upgrade: websocket' 'Upgrade:|Upgrade: websocket'; do
      source_calls_reset "$url"
      IFS='|' read -r -a ws_lines <<<"$ws_form"
      ws_out="$(ws_upgrade_status "${url//[!0-9]/}" "${ws_lines[@]}")"
      assert_eq "400" "${ws_out%%$'\n'*}" "$stack WebSocket upgrade on $url ($ws_form) is refused"
      assert_source_call_count "$(source_calls "$url")" handling appendEvent 0 "$stack WebSocket upgrade ($ws_form): the mutation sent over it wrote nothing"
      assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack WebSocket upgrade ($ws_form): no source call"
    done
  fi

  # 6. The edge never stores what the server marked private or failed.
  source_calls_reset "$url"
  get_full "$(apq_get_url "$edge" "$H_TRACK" "$V_TRACK")"
  expect "ABC123" '.data.cargo.trackingId' "edge GET TrackCargo 1"
  assert_header "$hdrs" cache-control "no-store" "$stack edge GET TrackCargo 1: Cache-Control"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET TrackCargo 1"
  get_full "$(apq_get_url "$edge" "$H_TRACK" "$V_TRACK")"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET TrackCargo 2"
  assert_source_call_count "$(source_calls "$url")" booking getCargo 2 "$stack edge GET TrackCargo twice: the server was reached twice"
  get_full "$edge?query=$(urlenc "$Q_BAD")"
  assert_has_errors "$resp" "$stack edge GET with an error 1"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET with an error 1"
  get_full "$edge?query=$(urlenc "$Q_BAD")"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET with an error 2"
  get_full "$(apq_get_url "$edge" "$(sha256_hex 'never registered')")"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET unknown hash 1"
  get_full "$(apq_get_url "$edge" "$(sha256_hex 'never registered')")"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET unknown hash 2"
  assert_error_message_at "$resp" 'null' PersistedQueryNotFound "$stack edge GET unknown hash 2: still the server's answer"

  # 7. Authorization bypasses the edge. The NLRTM answer is stored first, so a BYPASS that
  #    reached the server is visible in its Cache-Control (no-store), not the stored copy's.
  get_full "$(apq_get_url "$edge" "$H_PORT" "$V_PORT_NLRTM")"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET NLRTM: stored"
  get_full "$(apq_get_url "$edge" "$H_PORT" "$V_PORT_NLRTM")"
  assert_header "$hdrs" x-cache-status HIT "$stack edge GET NLRTM: served from the edge"
  get_full "$(apq_get_url "$edge" "$H_PORT" "$V_PORT_NLRTM")" "${BEARER[@]}"
  assert_header "$hdrs" x-cache-status BYPASS "$stack edge GET NLRTM with Authorization: X-Cache-Status"
  assert_header "$hdrs" cache-control "no-store" "$stack edge GET NLRTM with Authorization: the server answered"
  expect "Rotterdam" '.data.location.name' "edge GET NLRTM with Authorization: the same data"

  # 7a. Vary: Accept. Every public response says its body depends on Accept, so the edge stores one
  #     entry per Accept value. A first request that allows several media types (Quarkus: */*;
  #     Python answers */* with its IDE page, so it sends the GraphQL-over-HTTP media type) is stored under
  #     its own Accept; a later Accept: application/json is a MISS with its own content type, then a HIT.
  local vary_url vary_first
  vary_url="$(apq_get_url "$edge" "$H_PORT" '{"code":"DEHAM"}')"
  case "$stack" in
    quarkus) vary_first='*/*' ;;
    python) vary_first='application/graphql-response+json' ;;
  esac
  out="$(http_any GET "$vary_url" -H "Accept: $vary_first" -D "$SCRATCH/headers")"
  hdrs="$(tr -d '\r' <"$SCRATCH/headers")"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET DEHAM, Accept $vary_first: X-Cache-Status"
  assert_header "$hdrs" vary Accept "$stack edge GET DEHAM, Accept $vary_first: Vary"
  assert_header "$hdrs" cache-control "public, max-age=300" "$stack edge GET DEHAM, Accept $vary_first: Cache-Control"
  get_full "$vary_url"
  assert_header "$hdrs" x-cache-status MISS "$stack edge GET DEHAM, Accept application/json: stored separately"
  assert_header "$hdrs" content-type application/json "$stack edge GET DEHAM, Accept application/json: Content-Type"
  assert_header "$hdrs" vary Accept "$stack edge GET DEHAM, Accept application/json: Vary"
  expect "Hamburg" '.data.location.name' "edge GET DEHAM, Accept application/json: Hamburg"
  get_full "$vary_url"
  assert_header "$hdrs" x-cache-status HIT "$stack edge GET DEHAM, Accept application/json: served from its own entry"
  assert_header "$hdrs" content-type application/json "$stack edge GET DEHAM, Accept application/json, HIT: Content-Type"

  # 7b. Python serves its IDE page to a hash-only GET whose Accept header includes text/html or */*;
  #     curl's default, Accept: */*, is enough. The page carries no Cache-Control, so the edge stores
  #     nothing: two requests, two MISSes.
  if [[ "$stack" == python ]]; then
    local ide_url ide_try
    ide_url="$(apq_get_url "$edge" "$H_PORT" "$V_PORT_CNSHA")"
    for ide_try in 1 2; do
      out="$(http_any GET "$ide_url" -D "$SCRATCH/headers")"
      hdrs="$(tr -d '\r' <"$SCRATCH/headers")"
      assert_contains "text/html" "$(header_value "$hdrs" content-type)" "$stack hash-only GET, curl's default Accept, try $ide_try: Content-Type"
      assert_header "$hdrs" x-cache-status MISS "$stack hash-only GET, curl's default Accept, try $ide_try: X-Cache-Status"
    done
  fi

  # 8. Expiry: the handling TTL is 20 s. XYZ789's events are read, the entry ages out, and the
  #    next read calls the handling owner again. Whole seconds only. After this case nothing
  #    cached by an earlier case is left in the handling cache.
  resp="$(gql "$url" "$Q_STATUS" '{"id":"XYZ789"}')"
  assert_no_errors "$resp" "$stack XYZ789 first read"
  sleep 21
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_STATUS" '{"id":"XYZ789"}')"
  assert_no_errors "$resp" "$stack XYZ789 read after the TTL"
  assert_source_call_keys "$(source_calls "$url")" handling listEventsFor XYZ789 "$stack XYZ789 after the TTL: the entry expired"
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_STATUS" '{"id":"XYZ789"}')"
  assert_source_call_count "$(source_calls "$url")" handling '*' 0 "$stack XYZ789 read again: cached again"

  # 9. Invalidation on write. ABC123's events are cached by the first read; the registration
  #    evicts them before the payload reads the cargo, so the payload shows the new event.
  local t0
  t0=$(date +%s)
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_STATUS" "$V_TRACK")"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "ABC123 before the write"
  assert_source_call_keys "$(source_calls "$url")" handling listEventsFor ABC123 "$stack ABC123 first read: one handling call, the entry is filled"
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_STATUS" "$V_TRACK")"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "ABC123 second read"
  assert_source_call_count "$(source_calls "$url")" handling '*' 0 "$stack ABC123 second read: events cached"
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_REG" "$V_REG")"
  assert_no_errors "$resp" "$stack registration"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "registration: evt_10"
  expect "IN_PORT" '.data.registerHandlingEvent.cargo.delivery.transportStatus' "registration: the payload is fresh, IN_PORT"
  calls="$(source_calls "$url")"
  assert_source_call_count "$calls" handling appendEvent 1 "$stack registration: one append"
  assert_source_call_keys "$calls" handling listEventsFor ABC123 "$stack registration: the evicted entry was read again by the payload"
  assert_source_call_count "$calls" voyage '*' 0 "$stack registration: V100S from the voyages cache"
  assert_source_call_count "$calls" location '*' 0 "$stack registration: DEHAM from the locations cache"
  if ! (( $(date +%s) - t0 < 20 )); then
    echo "verify.sh: FAIL - $stack invalidation ran outside the TTL; result proves nothing" >&2
    return 1
  fi
  echo "verify.sh: ok - $stack invalidation ran inside the 20 s TTL" >&2
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_STATUS" "$V_TRACK")"
  expect "IN_PORT" '.data.cargo.delivery.transportStatus' "ABC123 after the write"
  assert_source_call_count "$(source_calls "$url")" handling '*' 0 "$stack ABC123 after the write: the payload refilled the entry"

  # 10. The contract, on the instance that allows introspection: deprecation, custom scalars
  #     and the live schema.
  assert_deprecated "$url" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_not_deprecated "$url" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime"
  local scalar
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
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

  echo "=== $stack: caching check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8260/graphql" "http://localhost:8262/graphql"
run_stack_check "python" "http://localhost:8261/graphql" "http://localhost:8263/graphql"

echo
echo "=== Step 3: the two edge listeners keep separate entries ==="
# Both stacks answer the same URL, and they share one cache zone. The key names the upstream,
# so a URL stored for one stack is a MISS for the other.
stack=edge
sg_quarkus="$(apq_get_url "http://localhost:8262/graphql" "$H_PORT" "$V_PORT_SGSIN")"
sg_python="$(apq_get_url "http://localhost:8263/graphql" "$H_PORT" "$V_PORT_SGSIN")"
get_full "$sg_quarkus"
assert_header "$hdrs" x-cache-status MISS "SGSIN on 8262, first"
expect "Singapore" '.data.location.name' "SGSIN on 8262: Singapore"
get_full "$sg_python"
assert_header "$hdrs" x-cache-status MISS "SGSIN on 8263, first: not the Quarkus entry"
expect "Singapore" '.data.location.name' "SGSIN on 8263: Singapore"
get_full "$sg_quarkus"
assert_header "$hdrs" x-cache-status HIT "SGSIN on 8262, second"
get_full "$sg_python"
assert_header "$hdrs" x-cache-status HIT "SGSIN on 8263, second"

echo
echo "PASS - Ch16 Caching: Cache-Control per response, an nginx edge that stores a persisted GET of" \
     "reference data (MISS, then HIT with no source call) and bypasses on Authorization, field-level" \
     "source caches that cut the second Q_FAN run to 3 calls on Python and 4 on Quarkus, eviction" \
     "on registerHandlingEvent, and expiry after the TTL, on Quarkus (quarkus-cache) and Python (cachetools)."
