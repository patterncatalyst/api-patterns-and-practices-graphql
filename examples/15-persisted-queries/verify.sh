#!/usr/bin/env bash
# examples/15-persisted-queries/verify.sh
#
# Ch15 Persisted queries and APQ: Apollo's three-step handshake (hash only,
# hash plus text, hash only again), persisted queries over GET, a mutation by
# hash refused over GET, and trusted documents (only the manifest runs) on both
# stacks. Quarkus implements the protocol in a Vert.x route in front of SmallRye
# GraphQL; Python in a Strawberry SchemaExtension.
#
# Four services run: 8250/8251 in APQ mode (clients register documents) and
# 8252/8253 in trusted mode (only persisted-documents.json runs). The APQ pair
# allows introspection, so the contract checks (schema, deprecation, scalars)
# run there; trusted mode refuses introspection text like any other.
#
# The cases run in a fixed order and handling state carries forward: the mutation
# by hash registers evt_10 for ABC123 on each instance.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch15-persisted"
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

Q_FAN='{ cargos(first: 4) { edges { node { trackingId itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } } delivery { transportStatus } } } } }'
H_FAN="$(sha256_hex "$Q_FAN")"

V_TRACK='{"id":"ABC123"}'
# A registration that fails validation (a voyage on a RECEIVE): userErrors, no write.
V_REG_BAD='{"i":{"trackingId":"ABC123","type":"RECEIVE","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z"}}'
V_REG='{"i":{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z","idempotencyKey":"k-apq-1"}}'

# A document with fragments, to show what the hash saves.
Q_DETAIL='query CargoDetail($id: TrackingId!) { cargo(trackingId: $id) { ...CargoCore itinerary { legs { ...LegDetail } finalArrivalTime } handlingHistory(first: 7) { totalCount edges { cursor node { ...EventDetail } } pageInfo { hasNextPage endCursor } } } } fragment CargoCore on Cargo { trackingId delivery { transportStatus } } fragment LegDetail on Leg { voyage { number } loadLocation { unLocode name } unloadLocation { unLocode name } loadTime unloadTime } fragment EventDetail on HandlingEvent { id type completionTime registrationTime location { unLocode name } voyage { number } }'
H_DETAIL="$(sha256_hex "$Q_DETAIL")"

JSON_ACCEPT=(-H 'Accept: application/json')

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# call_keys <calls-json> — the sorted source.op:key entries of the log, comma-joined.
call_keys() {
  python3 -I -c '
import json, sys
print(",".join(sorted("%s.%s:%s" % (c["source"], c["op"], c["key"]) for c in json.load(sys.stdin)["calls"])))
' <<<"$1"
}

# post_apq <url> <query-or-empty> <hash> [variables-json] — send an APQ body; sets $resp to the body, $status to the HTTP status.
post_apq() {
  local out
  out="$(gql_raw "$1" "$(apq_body "$2" "$3" "${4:-}")")"
  status="$(status_of "$out")"
  resp="$(body_of "$out")"
}

# get_apq <url> <hash> [variables-json] — the same over GET.
get_apq() {
  local out
  out="$(http_any GET "$(apq_get_url "$1" "$2" "${3:-}")" "${JSON_ACCEPT[@]}")"
  status="$(status_of "$out")"
  resp="$(body_of "$out")"
}

# refused <code> <message> <context> [status] — $resp is a request error with that code and message, no data, no source calls; the status is 200 unless given.
refused() {
  assert_status_in "${4:-200}" "$status" "$stack $3: status"
  assert_no_data "$resp" "$stack $3: no data"
  assert_error_count "$resp" 1 "$stack $3: one error"
  assert_error_message_at "$resp" 'null' "$2" "$stack $3: message"
  assert_error_extension "$resp" 'null' code "\"$1\"" "$stack $3: code"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack $3: no source call"
}

# fill_store <url> <count> — register <count> distinct documents, then report by hash alone how many still resolve (line 1) and which indices do not (line 2, comma-joined).
fill_store() {
  python3 -I -c '
import hashlib, json, sys, urllib.request
url, count = sys.argv[1], int(sys.argv[2])

def post(body):
    request = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)

def ext(text):
    return {"persistedQuery": {"version": 1, "sha256Hash": hashlib.sha256(text.encode()).hexdigest()}}

texts = ["query Bound%d { __typename }" % i for i in range(count)]
for text in texts:
    post({"query": text, "extensions": ext(text)})
missing = [i for i, text in enumerate(texts) if "errors" in post({"extensions": ext(text)})]
print(count - len(missing))
print(",".join(str(i) for i in missing))
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

# urlenc <text> — URL-encode every reserved character.
urlenc() {
  python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
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

# run_stack_check <stack> <apq-url> <trusted-url>
run_stack_check() {
  local stack="$1" url="$2" trusted_url="$3" resp status out calls full_keys

  echo
  echo "=== verifying stack '$stack' at $url (APQ) and $trusted_url (trusted) ==="

  wait_for_graphql "$url"
  # The trusted instance refuses the `{ __typename }` probe wait_for_graphql sends, so wait on its health endpoint.
  case "$stack" in
    quarkus) wait_for_http "$(graphql_base "$trusted_url")/q/health/ready" ;;
    python) wait_for_http "$(graphql_base "$trusted_url")/health" ;;
  esac

  # 1. The manifest's ids are the SHA-256 of their bodies (verified once, on the first stack).
  local name
  for name in TrackCargo PortName RegisterHandling; do
    assert_eq "$(manifest_field "$name" id)" "$(sha256_hex "$(manifest_field "$name" body)")" "$stack manifest id of $name is sha256(body)"
  done

  # 2. The handshake over POST.
  source_calls_reset "$url"
  post_apq "$url" '' "$H_TRACK" "$V_TRACK"
  refused PERSISTED_QUERY_NOT_FOUND PersistedQueryNotFound "handshake 1, hash only"

  post_apq "$url" "$Q_TRACK" "$H_TRACK" "$V_TRACK"
  assert_status_in "200" "$status" "$stack handshake 2: status"
  assert_no_errors "$resp" "$stack handshake 2, hash and text"
  expect "ABC123" '.data.cargo.trackingId' "handshake 2: trackingId"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "handshake 2: transportStatus"
  full_keys="$(call_keys "$(source_calls "$url")")"

  source_calls_reset "$url"
  post_apq "$url" '' "$H_TRACK" "$V_TRACK"
  assert_status_in "200" "$status" "$stack handshake 3: status"
  assert_no_errors "$resp" "$stack handshake 3, hash only again"
  expect "ABC123" '.data.cargo.trackingId' "handshake 3: trackingId"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "handshake 3: transportStatus"
  assert_eq "$full_keys" "$(call_keys "$(source_calls "$url")")" "$stack handshake 3: the same source calls as the full request"

  # 2b. A list query by hash: Chapter 13's Q_FAN, same data and same calls.
  source_calls_reset "$url"
  post_apq "$url" "$Q_FAN" "$H_FAN"
  assert_no_errors "$resp" "$stack Q_FAN registered"
  full_keys="$(call_keys "$(source_calls "$url")")"
  source_calls_reset "$url"
  post_apq "$url" '' "$H_FAN"
  assert_no_errors "$resp" "$stack Q_FAN by hash"
  expect "VWX901" '.data.cargos.edges.0.node.trackingId' "Q_FAN by hash: first cargo"
  expect "DEF456" '.data.cargos.edges.3.node.trackingId' "Q_FAN by hash: fourth cargo"
  assert_eq "$full_keys" "$(call_keys "$(source_calls "$url")")" "$stack Q_FAN by hash: the same source calls as the full request"
  # 2c. What the hash saves: a document with fragments, 580 characters. The
  #     counts are request body bytes, computed for the bodies sent below.
  source_calls_reset "$url"
  post_apq "$url" "$Q_DETAIL" "$H_DETAIL" '{"id":"DEF456"}'
  assert_no_errors "$resp" "$stack CargoDetail registered"
  post_apq "$url" '' "$H_DETAIL" '{"id":"DEF456"}'
  assert_no_errors "$resp" "$stack CargoDetail by hash"
  expect "DEF456" '.data.cargo.trackingId' "CargoDetail by hash: trackingId"
  assert_eq "7" "$(json_len .data.cargo.handlingHistory.edges <<<"$resp")" "$stack CargoDetail by hash: seven events"
  local plain_bytes hash_bytes
  plain_bytes="$(python3 -I -c 'import json, sys; print(len(json.dumps({"query": sys.argv[1], "variables": {"id": "DEF456"}})))' "$Q_DETAIL")"
  hash_bytes="$(printf '%s' "$(apq_body '' "$H_DETAIL" '{"id":"DEF456"}')" | wc -c)"
  echo "lib.sh: info - $stack CargoDetail request body: $plain_bytes bytes with text, $hash_bytes bytes by hash" >&2
  assert_eq "624" "$plain_bytes" "$stack CargoDetail request body with text"
  assert_eq "163" "$hash_bytes" "$stack CargoDetail request body by hash"

  # 3. A hash that lies: the server recomputes it.
  source_calls_reset "$url"
  post_apq "$url" "$Q_TRACK" "$H_PORT" "$V_TRACK"
  refused BAD_USER_INPUT "provided sha does not match query" "mismatch"

  # 4. GET by hash: the document registered in case 2, variables and extensions in the URL.
  source_calls_reset "$url"
  get_apq "$url" "$H_TRACK" "$V_TRACK"
  assert_status_in "200" "$status" "$stack GET by hash: status"
  assert_no_errors "$resp" "$stack GET by hash"
  expect "ABC123" '.data.cargo.trackingId' "GET by hash: trackingId"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "GET by hash: transportStatus"
  # An operationName sent with a GET by hash works.
  out="$(http_any GET "$(apq_get_url "$url" "$H_TRACK" "$V_TRACK")&operationName=TrackCargo" "${JSON_ACCEPT[@]}")"
  assert_status_in "200" "$(status_of "$out")" "$stack GET by hash with operationName: status"
  resp="$(body_of "$out")"
  assert_no_errors "$resp" "$stack GET by hash with operationName"
  expect "ABC123" '.data.cargo.trackingId' "GET by hash with operationName: trackingId"
  # An unknown hash over GET is the same handshake step.
  source_calls_reset "$url"
  get_apq "$url" "$H_PORT" '{"code":"NLRTM"}'
  refused PERSISTED_QUERY_NOT_FOUND PersistedQueryNotFound "GET unknown hash"
  # A literal % and + in a string argument reach the source unchanged: by text, by variable and by hash.
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  local q_lit='query { cargo(trackingId: "A+B%41 C") { trackingId } }' q_var='query Lit($id: TrackingId!) { cargo(trackingId: $id) { trackingId } }'
  source_calls_reset "$url"
  out="$(http_any GET "$url?query=$(urlenc "$q_lit")" "${JSON_ACCEPT[@]}")"
  assert_status_in "200" "$(status_of "$out")" "$stack GET literal % and +: status"
  assert_eq "booking.getCargo:A+B%41 C" "$(call_keys "$(source_calls "$url")")" "$stack GET literal % and + in the document"
  source_calls_reset "$url"
  out="$(http_any GET "$url?query=$(urlenc "$q_var")&variables=$(urlenc '{"id":"D+E%42 F"}')" "${JSON_ACCEPT[@]}")"
  assert_status_in "200" "$(status_of "$out")" "$stack GET literal % and + in variables: status"
  assert_eq "booking.getCargo:D+E%42 F" "$(call_keys "$(source_calls "$url")")" "$stack GET literal % and + in variables"
  post_apq "$url" "$q_lit" "$(sha256_hex "$q_lit")"
  assert_no_errors "$resp" "$stack literal document registered"
  source_calls_reset "$url"
  get_apq "$url" "$(sha256_hex "$q_lit")"
  assert_no_errors "$resp" "$stack literal document by hash over GET"
  assert_eq "booking.getCargo:A+B%41 C" "$(call_keys "$(source_calls "$url")")" "$stack the executed text equals the stored text"
  source_calls_reset "$url"
  post_apq "$url" '' "$(sha256_hex "$q_lit")"
  assert_no_errors "$resp" "$stack literal document by hash over POST"
  assert_eq "booking.getCargo:A+B%41 C" "$(call_keys "$(source_calls "$url")")" "$stack POST by hash: the executed text equals the stored text"
  # A document that ends in a lone % reaches the source unchanged over POST and GET.
  local q_pct='query { cargo(trackingId: "100%") { trackingId } }'
  post_apq "$url" "$q_pct" "$(sha256_hex "$q_pct")"
  source_calls_reset "$url"
  post_apq "$url" '' "$(sha256_hex "$q_pct")"
  assert_status_in "200" "$status" "$stack POST by hash, document with a lone %: status"
  assert_eq "booking.getCargo:100%" "$(call_keys "$(source_calls "$url")")" "$stack POST by hash, document with a lone %"
  source_calls_reset "$url"
  get_apq "$url" "$(sha256_hex "$q_pct")"
  assert_status_in "200" "$status" "$stack GET by hash, document with a lone %: status"
  assert_eq "booking.getCargo:100%" "$(call_keys "$(source_calls "$url")")" "$stack GET by hash, document with a lone %"

  # 5. A mutation by hash over GET is refused. Register it first by POST with
  #    input that fails validation (userErrors, no write), then send it by GET.
  post_apq "$url" "$Q_REG" "$H_REG" "$V_REG_BAD"
  assert_no_errors "$resp" "$stack mutation registered with invalid input"
  assert_json_eq '[{"code":"VOYAGE_NOT_ALLOWED"}]' "$(json_field '.data.registerHandlingEvent.userErrors' <<<"$resp")" "$stack mutation registered: userErrors"
  source_calls_reset "$url"
  get_apq "$url" "$H_REG" "$V_REG"
  case "$stack" in
    python)
      assert_status_in "400" "$status" "$stack GET mutation by hash: status"
      assert_contains "mutations are not allowed when using GET" "$resp" "$stack GET mutation by hash: body"
      ;;
    quarkus)
      # The route refuses with the status the specification recommends.
      assert_status_in "405" "$status" "$stack GET mutation by hash: status"
      assert_header "$(http_headers GET "$(apq_get_url "$url" "$H_REG" "$V_REG")" "${JSON_ACCEPT[@]}")" allow POST "$stack GET mutation by hash: Allow header"
      assert_contains "mutations are not allowed when using GET" "$resp" "$stack GET mutation by hash: body"
      ;;
  esac
  assert_source_call_count "$(source_calls "$url")" handling appendEvent 0 "$stack GET mutation by hash: nothing was written"
  # The same holds for mutation text sent over GET with no hash, with input that would be accepted.
  out="$(http_any GET "$url?query=$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$Q_REG")&variables=$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$V_REG")" "${JSON_ACCEPT[@]}")"
  case "$stack" in
    python) assert_status_in "400" "$(status_of "$out")" "$stack GET mutation text: status" ;;
    quarkus) assert_status_in "405" "$(status_of "$out")" "$stack GET mutation text: status" ;;
  esac
  assert_contains "mutations are not allowed when using GET" "$(body_of "$out")" "$stack GET mutation text: body"
  assert_source_call_count "$(source_calls "$url")" handling appendEvent 0 "$stack GET mutation text: nothing was written"
  # Two more variants are refused the same way.
  out="$(http_any GET "$url?query=$(get_variant 1 "$Q_REG")&variables=$(urlenc "$V_REG")" "${JSON_ACCEPT[@]}")"
  case "$stack" in
    python) assert_status_in "400" "$(status_of "$out")" "$stack GET mutation variant: status" ;;
    quarkus) assert_status_in "405" "$(status_of "$out")" "$stack GET mutation variant: status" ;;
  esac
  assert_contains "mutations are not allowed when using GET" "$(body_of "$out")" "$stack GET mutation variant: body"
  assert_source_call_count "$(source_calls "$url")" handling appendEvent 0 "$stack GET mutation variant: nothing was written"
  out="$(http_any GET "$url?query=$(get_variant 2 "$Q_REG")&variables=$(urlenc "$V_REG")" "${JSON_ACCEPT[@]}")"
  case "$stack" in
    python) assert_status_in "200" "$(status_of "$out")" "$stack GET unparseable document: status" ;;
    quarkus) assert_status_in "400" "$(status_of "$out")" "$stack GET unparseable document: status" ;;
  esac
  assert_has_errors "$(body_of "$out")" "$stack GET unparseable document: errors"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack GET unparseable document: no source call"

  # 5b. An operationName that selects no operation is refused, whatever the document holds, and an
  #     empty one is treated as absent: the mutation still stays off GET.
  unmatched_operation_name "$url" "$url" "APQ"
  # A GET with a body is answered like any GET.
  out="$(http_any GET "$url" "${JSON_ACCEPT[@]}" -H 'Content-Type: application/x-www-form-urlencoded' --data 'a=b')"
  assert_body_not_contains "$(status_of "$out")" "500" "$stack GET with a form body: answered"

  # 6. The same mutation by hash over POST: Chapter 8's semantics hold through APQ.
  post_apq "$url" '' "$H_REG" "$V_REG"
  assert_status_in "200" "$status" "$stack mutation by hash: status"
  assert_no_errors "$resp" "$stack mutation by hash"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "mutation by hash: evt_10"
  expect "IN_PORT" '.data.registerHandlingEvent.cargo.delivery.transportStatus' "mutation by hash: IN_PORT"
  source_calls_reset "$url"
  post_apq "$url" '' "$H_REG" "$V_REG"
  assert_no_errors "$resp" "$stack the repeat by hash"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "the repeat returns evt_10"
  assert_source_call_count "$(source_calls "$url")" handling appendEvent 0 "$stack the repeat wrote nothing"

  # 7. Trusted mode: the manifest runs without registration, and nothing else does.
  source_calls_reset "$trusted_url"
  local url_apq="$url"
  url="$trusted_url"
  post_apq "$url" '' "$H_PORT" '{"code":"NLRTM"}'
  assert_status_in "200" "$status" "$stack trusted: manifest hash, never registered: status"
  assert_no_errors "$resp" "$stack trusted: manifest hash, never registered"
  expect "Rotterdam" '.data.location.name' "trusted: manifest hash gives Rotterdam"
  get_apq "$url" "$H_PORT" '{"code":"NLRTM"}'
  assert_no_errors "$resp" "$stack trusted: manifest hash over GET"
  expect "Rotterdam" '.data.location.name' "trusted: manifest hash over GET"

  source_calls_reset "$url"
  post_apq "$url" '{ __typename }' "$(sha256_hex '{ __typename }')"
  refused PERSISTED_QUERY_REQUIRED "only persisted documents are accepted" "trusted: registration attempt"
  out="$(gql_any "$url" '{ __typename }')"
  status="$(status_of "$out")"
  resp="$(body_of "$out")"
  refused PERSISTED_QUERY_REQUIRED "only persisted documents are accepted" "trusted: arbitrary text"
  out="$(gql_any "$url" '{ __schema { queryType { name } } }')"
  status="$(status_of "$out")"
  resp="$(body_of "$out")"
  refused PERSISTED_QUERY_REQUIRED "only persisted documents are accepted" "trusted: introspection"
  # A text sent as application/graphql is held to the same rule; Python does not read the type.
  out="$(gql_raw "$url" '{ __schema { queryType { name } } }' application/json application/graphql)"
  status="$(status_of "$out")"
  resp="$(body_of "$out")"
  case "$stack" in
    quarkus) refused PERSISTED_QUERY_REQUIRED "only persisted documents are accepted" "trusted: application/graphql introspection" ;;
    python)
      assert_status_in "400" "$status" "$stack trusted: application/graphql introspection: status"
      assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack trusted: application/graphql introspection: no source call"
      ;;
  esac
  # A URL query parameter does not replace the document: POST and GET.
  out="$(http_any POST "$url?query=$(urlenc '{ __typename }')" "${JSON_ACCEPT[@]}" -H 'Content-Type: application/json' --data-binary "$(_gql_body "$Q_PORT" '{"code":"NLRTM"}')")"
  status="$(status_of "$out")"
  resp="$(body_of "$out")"
  case "$stack" in
    quarkus) refused PERSISTED_QUERY_REQUIRED "only persisted documents are accepted" "trusted: ?query= on POST" ;;
    python)
      # On POST the body's document runs; the URL parameter is not read.
      expect "Rotterdam" '.data.location.name' "trusted: ?query= on POST runs the body's manifest document"
      assert_absent "$resp" '.data.__typename' "$stack trusted: ?query= on POST: the URL text did not run"
      ;;
  esac
  source_calls_reset "$url"
  out="$(http_any GET "$url?query=$(urlenc '{ __typename }')" "${JSON_ACCEPT[@]}")"
  status="$(status_of "$out")"
  resp="$(body_of "$out")"
  refused PERSISTED_QUERY_REQUIRED "only persisted documents are accepted" "trusted: ?query= on GET"
  post_apq "$url" '' "$(sha256_hex 'never registered')"
  refused PERSISTED_QUERY_NOT_FOUND PersistedQueryNotFound "trusted: unknown hash"
  # The registration attempt stored nothing: the same hash alone is still unknown.
  post_apq "$url" '' "$(sha256_hex '{ __typename }')"
  refused PERSISTED_QUERY_NOT_FOUND PersistedQueryNotFound "trusted: the refused document was not stored"
  # A hash from the APQ instance's store is not in this instance's manifest.
  post_apq "$url" '' "$H_FAN"
  refused PERSISTED_QUERY_NOT_FOUND PersistedQueryNotFound "trusted: a hash registered on the APQ instance is unknown here"

  # Full text that is in the manifest is accepted without a hash.
  resp="$(gql "$url" "$Q_PORT" '{"code":"NLRTM"}')"
  assert_no_errors "$resp" "$stack trusted: manifest text without a hash"
  expect "Rotterdam" '.data.location.name' "trusted: manifest text without a hash"
  # An application/graphql manifest document runs on Quarkus.
  if [[ "$stack" == quarkus ]]; then
    out="$(http_any POST "$url?variables=$(urlenc '{"code":"NLRTM"}')" "${JSON_ACCEPT[@]}" -H 'Content-Type: application/graphql' --data-binary "$Q_PORT")"
    assert_status_in "200" "$(status_of "$out")" "$stack trusted: application/graphql manifest document: status"
    resp="$(body_of "$out")"
    assert_no_errors "$resp" "$stack trusted: application/graphql manifest document"
    expect "Rotterdam" '.data.location.name' "trusted: application/graphql manifest document"
    # An empty application/graphql body is held to the same rule.
    source_calls_reset "$url"
    out="$(http_any POST "$url" "${JSON_ACCEPT[@]}" -H 'Content-Type: application/graphql' --data-binary '')"
    status="$(status_of "$out")"
    resp="$(body_of "$out")"
    refused PERSISTED_QUERY_REQUIRED "only persisted documents are accepted" "trusted: empty application/graphql body"
    # Any other media type is refused with a 400.
    source_calls_reset "$url"
    out="$(http_any POST "$url" "${JSON_ACCEPT[@]}" -H 'Content-Type: text/plain' --data-binary '{ __typename }')"
    status="$(status_of "$out")"
    resp="$(body_of "$out")"
    refused PERSISTED_QUERY_REQUIRED "only persisted documents are accepted" "trusted: text/plain body" 400
  fi
  # A mutation in the manifest runs by hash over POST.
  post_apq "$url" '' "$H_REG" "$V_REG"
  assert_no_errors "$resp" "$stack trusted: mutation by hash"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "trusted: mutation by hash: evt_10"
  unmatched_operation_name "$url" "$url" "trusted"
  url="$url_apq"

  # 7b. This example serves HTTP only: any request on /graphql that carries an Upgrade header is refused
  #     on both instances, whatever the header says. A mutation is sent if the upgrade succeeds.
  if [[ "$stack" == quarkus ]]; then
    local ws_url ws_form ws_out; local -a ws_lines
    for ws_url in "$url_apq" "$trusted_url"; do
      for ws_form in 'Upgrade: websocket' 'Upgrade: foo|Upgrade: websocket' 'Upgrade:|Upgrade: websocket'; do
        source_calls_reset "$ws_url"
        IFS='|' read -r -a ws_lines <<<"$ws_form"
        ws_out="$(ws_upgrade_status "${ws_url//[!0-9]/}" "${ws_lines[@]}")"
        assert_eq "400" "${ws_out%%$'\n'*}" "$stack WebSocket upgrade on $ws_url ($ws_form) is refused"
        assert_source_call_count "$(source_calls "$ws_url")" handling appendEvent 0 "$stack WebSocket upgrade on $ws_url ($ws_form): the mutation sent over it wrote nothing"
        assert_source_call_count "$(source_calls "$ws_url")" '*' '*' 0 "$stack WebSocket upgrade on $ws_url ($ws_form): no source call"
      done
    done
  fi

  # 8. The store is bounded: 1100 distinct documents leave at most 1000 resolvable.
  local resolved evicted
  out="$(fill_store "$url" 1100)"
  resolved="$(head -n1 <<<"$out")"
  evicted="$(sed -n 2p <<<"$out")"
  echo "lib.sh: info - $stack $resolved of 1100 registered documents still resolve" >&2
  assert_eq "1000" "$resolved" "$stack the store holds exactly 1000 documents"
  if [[ "$stack" == python ]]; then
    # cachetools.LRUCache drops the least recently used: the first 100 registered.
    assert_eq "$(seq -s, 0 99)" "$evicted" "$stack the evicted documents are the 100 oldest"
  fi

  # 9. The contract, on the instance that allows introspection: deprecation,
  #    custom scalars and the live schema.
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

  echo "=== $stack: persisted-document check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8250/graphql" "http://localhost:8252/graphql"
run_stack_check "python" "http://localhost:8251/graphql" "http://localhost:8253/graphql"

echo
echo "PASS - Ch15 Persisted queries and APQ: Quarkus (a Vert.x route in front of SmallRye GraphQL)" \
     "and Python (a Strawberry SchemaExtension) run Apollo's hash handshake, serve persisted queries" \
     "over GET, refuse a mutation by hash over GET (variants included), reject a hash" \
     "that does not match its text, keep the store bounded, and in trusted mode run only the manifest's" \
     "documents over every transport the example serves."
