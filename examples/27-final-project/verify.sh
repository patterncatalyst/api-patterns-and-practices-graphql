#!/usr/bin/env bash
# examples/27-final-project/verify.sh
#
# Ch27 The final project: the complete canonical schema behind one edge, with the
# defences of Chapters 14, 17, 18 and 21 running together. An nginx edge (TLS 1.3,
# a 64k body limit, /graphql and /events/ only) stands in front of the public
# instances of both stacks; Keycloak issues the tokens; each stack validates them
# and authorizes by operation, object and field, on queries, on subscriptions and
# on the event feed; the query limits refuse a document before any source is
# asked; the internal instances (introspection on, loopback only) serve the
# schema that is compared with the contract; and k6 runs two loads through the edge.
#
# Users (test fixtures, keycloak/shipping-realm.json):
#   ana  shipper ACME    owns VWX901, DEF456, ABC123
#   bo   shipper GLOBEX  owns XYZ789, STU678, GHI345 (the booking outage seed)
#   ops  operator        sees every cargo and every field
#
# The certificates are generated into a scratch directory at run time (gen-certs.sh)
# and are never committed. LGTM_CACERT makes every harness call trust that CA.
# Tokens are fetched at http://localhost:8374, the address Keycloak is published
# on: the apps pin that address as the issuer.
#
# Handling state carries forward in the public instances: the registration of the
# subscription case (REG_F1) is the first write and issues evt_10.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

# assert_sdl_equals diffs the two schemas in both directions. A deprecation reaches
# the live side as state (isDeprecated and deprecationReason) and the canonical
# file declares it as a directive, so the diff names the directive on that one
# field. The state itself is asserted below with assert_deprecated.
LGTM_SDL_IGNORE="${LGTM_SDL_IGNORE}|Directive deprecated was (removed from|added to) field Itinerary\.finalArrivalDate\$"

PROJECT="gql-ch27-final"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
REALM_URL="http://localhost:8374/realms/shipping"
TOKEN_URL="$REALM_URL/protocol/openid-connect/token"
TEMPO="http://localhost:8376"
LOKI="http://localhost:8378"
DOCS="$SCRIPT_DIR/../23-testing/documents"

SCRATCH="$(mktemp -d)"
on_exit "rm -rf '$SCRATCH'"
"$SCRIPT_DIR/gen-certs.sh" "$SCRATCH/certs"
export CERT_DIR="$SCRATCH/certs"
export LGTM_CACERT="$CERT_DIR/ca.crt"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
REGISTER='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } userErrors { code } } }'
REG_F1='{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z","idempotencyKey":"ch27-final-unload-1"}'
Q_FAN="$(<"$SCRIPT_DIR/documents/fan-out.graphql")"
Q_OVER="$(<"$SCRIPT_DIR/documents/over-budget.graphql")"
Q_LIST='query ListCargos { cargos(first: 10) { totalCount edges { node { trackingId } } } }'
# shellcheck disable=SC2016
Q_HISTORY='query History($id: TrackingId!) { cargo(trackingId: $id) { handlingHistory(first: 2) { edges { node { id registrationTime } } } } }'
# shellcheck disable=SC2016
Q_TRACK='query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }'
# Sixteen fields deep with first: 1 throughout: refused by the depth limit.
D_DEEP='{ cargos(first: 1) { edges { node { handlingHistory(first: 1) { edges { node { cargo { handlingHistory(first: 1) { edges { node { cargo { handlingHistory(first: 1) { edges { node { cargo { trackingId } } } } } } } } } } } } } } } }'
# shellcheck disable=SC2016
SUB_BODY='{"query":"subscription Watch($id: TrackingId!) { cargoHandled(trackingId: $id) { id } }","variables":{"id":"ABC123"}}'

# A 100 KB comment inside a valid query: a large body with almost no tokens.
python3 -I -c '
import json, sys
with open(sys.argv[1] + "/comment.json", "w") as f:
    json.dump({"query": "{ __typename # " + "x" * 100000 + "\n}"}, f)
' "$SCRATCH"

# --- local helpers --------------------------------------------------------------

# compose <args...> - docker compose against this example's project.
compose() {
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" "$@"
}

# expect <expected> <json-path> <context> - assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# as <token-or-empty> <gql args...> - one GraphQL request as that caller.
as() {
  local token="$1"
  shift
  LGTM_BEARER="$token" gql "$@"
}

# as_any <token-or-empty> <gql_any args...> - the same, keeping the status.
as_any() {
  local token="$1"
  shift
  LGTM_BEARER="$token" gql_any "$@"
}

# refresh_tokens - fresh tokens for every user (they live for ten minutes).
refresh_tokens() {
  ANA="$(oidc_token "$TOKEN_URL" tracking-cli ana ana-fixture-pw)"
  BO="$(oidc_token "$TOKEN_URL" tracking-cli bo bo-fixture-pw)"
  OPS="$(oidc_token "$TOKEN_URL" tracking-cli ops ops-fixture-pw)"
  OTHER="$(oidc_token "$TOKEN_URL" other-cli ana ana-fixture-pw)"
}

# project <list-path> <field.path> - the dotted field of each item of the list at <list-path> in $resp.
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

# gen_alias_bomb - 150 aliases of one cargo lookup.
gen_alias_bomb() {
  python3 -I -c '
print("{ " + " ".join(
    f"a{k}: cargo(trackingId: \"ABC123\") {{ delivery {{ transportStatus }} itinerary {{ legs {{ voyage {{ number }} }} }} }}"
    for k in range(150)) + " }")'
}

# subscribers <service> <channel> <tracking-id> - the live subscription count, read inside the container.
subscribers() {
  python3 -I -c '
import json, sys
print(json.load(sys.stdin).get(sys.argv[1], {}).get(sys.argv[2], 0))
' "$2" "$3" < <(body_of "$(compose_exec_http "$1" GET /debug/subscribers)")
}

# wait_subscribers <service> <channel> <tracking-id> <n> [timeout] - until the count is n.
wait_subscribers() {
  local service="$1" channel="$2" id="$3" want="$4" timeout="${5:-60}" waited=0 have=-1
  while ((waited < timeout)); do
    have="$(subscribers "$service" "$channel" "$id")"
    if [[ "$have" == "$want" ]]; then return 0; fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "verify: FAIL - $service had $have $channel subscribers for $id after ${timeout}s, wanted $want" >&2
  return 1
}

# wait_for_lines <file> <n> [timeout] - until the file holds n lines.
wait_for_lines() {
  local file="$1" want="$2" timeout="${3:-60}" waited=0 have=0
  while ((waited < timeout)); do
    have="$(wc -l <"$file")"
    if ((have >= want)); then return 0; fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "verify: FAIL - $file held $have lines after ${timeout}s, wanted $want" >&2
  return 1
}

# frame_types <stderr-file> - the frames the client logged, as "<dir> <type>" in a JSON list (ping and pong left out).
frame_types() {
  python3 -I -c '
import json, sys
out = []
for line in open(sys.argv[1]):
    direction, _, body = line.partition(" ")
    if direction in (">>>", "<<<") and json.loads(body)["type"] not in ("ping", "pong"):
        out.append("%s %s" % (direction, json.loads(body)["type"]))
print(json.dumps(out))
' "$1"
}

# first_line <file> - the first line of a file.
first_line() {
  sed -n 1p "$1"
}

# history_view <file> - what an Audit event carries, as JSON: the event id, the codes of
# the errors that have one (with the last path segment), and the history nodes.
history_view() {
  python3 -I -c '
import json, sys
message = json.loads(open(sys.argv[1]).readline())
errors = [(e["extensions"]["code"], e["path"][-1]) for e in (message["errors"] or []) if e.get("extensions", {}).get("code")]
edges = message["data"]["cargoHandled"]["cargo"]["handlingHistory"]["edges"]
print(json.dumps({
    "event": message["data"]["cargoHandled"]["id"],
    "coded_errors": errors,
    "nodes": [None if e["node"] is None else {"id": e["node"]["id"], "has_time": bool(e["node"]["registrationTime"])} for e in edges],
}))
' "$1"
}

# span_count <trace> <name-regex> [<attr> <value>] - spans whose name matches and, when given, whose attribute equals the value.
span_count() {
  python3 -I -c '
import json, re, sys
spans = json.load(sys.stdin)["spans"]
name, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
def has(span):
    return not key or str(span["attributes"].get(key)) == value
print(sum(1 for s in spans if re.search(name, s["name"]) and has(s)))
' "$2" "${3:-}" "${4:-}" <<<"$1"
}

# log_count <calls-json> <source> <op> - the calls of the log made to that source operation.
log_count() {
  python3 -I -c '
import json, sys
print(sum(1 for c in json.load(sys.stdin)["calls"] if c["source"] == sys.argv[1] and c["op"] == sys.argv[2]))
' "$2" "$3" <<<"$1"
}

# --- tier-level cases -----------------------------------------------------------

# check_tier - the services, the networks and the published ports.
check_tier() {
  local states svc raw bindings
  echo
  echo "=== the tier: start order, networks, published ports ==="
  compose config --quiet || { echo "FAIL - docker compose config" >&2; return 1; }
  echo "lib.sh: ok — docker compose config is valid" >&2

  states="$(compose ps --format json | python3 -I -c '
import json, sys
rows = [json.loads(line) for line in sys.stdin if line.strip()]
print(",".join(sorted("%s=%s" % (r["Service"], r.get("Health") or r["State"]) for r in rows)))
')"
  assert_eq "edge=healthy,keycloak=healthy,lgtm=healthy,python-internal=healthy,python=healthy,quarkus-internal=healthy,quarkus=healthy" "$states" "every service is healthy"

  # The public instances publish nothing: no host binding is reported, and the
  # container has no runtime port binding (a container on an internal network gets none).
  for svc in quarkus python; do
    raw="$(compose port "$svc" 8080 2>/dev/null || true)"
    # No published port reads back as "no binding": empty, ":0", or a port-0 form
    # some engine builds print ("0.0.0.0:0", "invalid IP:0"). A real binding never
    # ends in ":0"; the PortBindings/Ports checks below are the authoritative backstop.
    case "$raw" in
      "" | *:0) echo "lib.sh: ok — docker compose port reports no host binding for $svc" >&2 ;;
      *) echo "FAIL - $svc reports a host binding: $raw" >&2; return 1 ;;
    esac
    bindings="$(compose_inspect "$svc" '{{json .HostConfig.PortBindings}}')"
    case "$bindings" in
      "{}" | "null") echo "lib.sh: ok — $svc has no runtime port binding" >&2 ;;
      *) echo "FAIL - $svc has port bindings: $bindings" >&2; return 1 ;;
    esac
    # shellcheck disable=SC2016  # a Go template, not a shell expansion
    assert_eq "backend" "$(compose_inspect "$svc" '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{end}}' | sed "s/^${PROJECT}_//")" "$svc joins only the backend network"
  done
  assert_eq "true" "$(docker network inspect "${PROJECT}_backend" -f '{{.Internal}}')" "the backend network is internal"

  # Everything but the edge binds to 127.0.0.1.
  for svc in quarkus-internal python-internal keycloak lgtm; do
    bindings="$(compose_inspect "$svc" '{{json .HostConfig.PortBindings}}')"
    python3 -I -c '
import json, sys
bindings = json.loads(sys.argv[2])
hosts = [b["HostIp"] for v in bindings.values() for b in v]
assert hosts and all(h == "127.0.0.1" for h in hosts), (sys.argv[1], hosts)
' "$svc" "$bindings" || { echo "FAIL - $svc publishes beyond loopback: $bindings" >&2; return 1; }
    echo "lib.sh: ok — $svc publishes on 127.0.0.1 only" >&2
  done
  bindings="$(compose_inspect edge '{{json .HostConfig.PortBindings}}')"
  python3 -I -c '
import json, sys
bindings = json.loads(sys.argv[1])
hosts = sorted((k, b["HostPort"]) for k, v in bindings.items() for b in v)
assert hosts == [("8443/tcp", "8370"), ("8444/tcp", "8371")], hosts
' "$bindings" || { echo "FAIL - edge ports: $bindings" >&2; return 1; }
  echo "lib.sh: ok — the edge publishes 8370 and 8371 and nothing else" >&2
}

# --- per-stack cases ------------------------------------------------------------

# run_stack_check <stack>
run_stack_check() {
  local stack="$1"
  local pub int base eport total fan_keys op out resp calls trace_id tp trace scalar
  local denial want_header want_body headers tokens_message
  case "$stack" in
    quarkus)
      pub="https://localhost:8370/graphql"; int="http://localhost:8372/graphql"; eport=8443
      total=8; op='^query ListCargos$'; denial="Introspection has been disabled for this request"
      fan_keys='booking.listCargos:*,booking.getCargos:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,handling.listEventsFor:DEF456+STU678+VWX901+XYZ789,location.getLocations:DEHAM+SGSIN+USNYC,voyage.getVoyages:V100S+V200E+V300A,location.getLocations:CNSHA+DEHAM+NLRTM'
      want_header='Bearer'; want_body=''; tokens_message="Unparseable input document"
      ;;
    python)
      pub="https://localhost:8371/graphql"; int="http://localhost:8373/graphql"; eport=8444
      total=6; op='^GraphQL Query: ListCargos$'; denial="introspection has been disabled"
      fan_keys='booking.listCargos:*,booking.getCargos:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,handling.listEventsFor:DEF456+STU678+VWX901+XYZ789,location.getLocations:CNSHA+DEHAM+NLRTM+SGSIN+USNYC,voyage.getVoyages:V100S+V200E+V300A'
      want_header='Bearer error="invalid_token"'; want_body='{"detail":"invalid token"}'; tokens_message="Document contains more than 5000 tokens"
      ;;
  esac
  base="${pub%/graphql}"

  echo
  echo "=== verifying stack '$stack' through the edge at $pub ==="
  wait_for_graphql "$pub"
  wait_for_graphql "$int"
  refresh_tokens

  # 1. The complete contract, on the internal instance (introspection on): the
  #    whole canonical SDL, Subscription included. The public instance refuses
  #    introspection with the stack's own answer, even for an operator.
  assert_sdl_equals "$int" "$stack internal schema equals the canonical SDL"
  resp="$(gql "$int" '{ __schema { subscriptionType { name } } }')"
  expect "Subscription" '.data.__schema.subscriptionType.name' "internal subscription root type"
  assert_deprecated "$int" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_not_deprecated "$int" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime"
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016
    resp="$(gql "$int" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    expect "SCALAR" '.data.__type.kind' "$scalar kind"
    case "$scalar" in
      UnLocode) expect "https://unece.org/trade/uncefact/unlocode" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      DateTime) expect "https://www.rfc-editor.org/rfc/rfc3339" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      *) assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL" ;;
    esac
  done
  resp="$(as "$OPS" "$pub" '{ __schema { queryType { name } } }')"
  assert_has_errors "$resp" "$stack public __schema is refused, even for an operator"
  assert_no_data "$resp" "$stack public __schema returns no data"
  assert_error_message_contains "$resp" "$denial" "$stack public __schema message"

  # 2. The edge: TLS 1.3 only, a body limit, and only /graphql and /events/ routed.
  LGTM_CACERT='' assert_transport_fails "$stack: without the CA the certificate is untrusted" \
    -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "$pub"
  assert_transport_fails "$stack: a TLS 1.2 client is refused" --tlsv1.2 --tls-max 1.2 \
    -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "$pub"
  source_calls_reset_in "$stack"
  out="$(http_any POST "$pub" -H 'Content-Type: application/json' --http1.1 -d "@$SCRATCH/comment.json")"
  assert_eq "413" "$(status_of "$out")" "$stack: a 100 KB body is refused at the edge"
  assert_source_call_count "$(source_calls_in "$stack")" '*' '*' 0 "$stack: the refused body never reached the backend"
  out="$(http_any GET "$base/debug/source-calls")"
  assert_eq "404" "$(status_of "$out")" "$stack: /debug/source-calls is not routed"
  out="$(http_any GET "$base/debug/subscribers")"
  assert_eq "404" "$(status_of "$out")" "$stack: /debug/subscribers is not routed"
  out="$(http_any GET "$base/q/health/ready")"
  assert_eq "404" "$(status_of "$out")" "$stack: /q/health/ready is not routed"
  out="$(http_any GET "$base/health/ready")"
  assert_eq "404" "$(status_of "$out")" "$stack: /health/ready is not routed"

  # 3. Authentication. No token is an anonymous caller; a token that does not
  #    validate is HTTP 401 with a Bearer challenge before GraphQL runs.
  source_calls_reset_in "$stack"
  resp="$(gql "$pub" '{ cargo(trackingId: "ABC123") { trackingId } }')"
  assert_null_at "$resp" '.data.cargo' "$stack anonymous cargo is null"
  assert_error_path "$resp" '["cargo"]' "$stack anonymous cargo: error path"
  assert_error_extension "$resp" '["cargo"]' code '"UNAUTHENTICATED"' "$stack anonymous cargo: code"
  assert_error_message_at "$resp" '["cargo"]' "authentication required" "$stack anonymous cargo: message"
  assert_source_call_count "$(source_calls_in "$stack")" '*' '*' 0 "$stack the refused operation makes no source call"
  out="$(as_any "$OTHER" "$pub" '{ location(unLocode: "NLRTM") { name } }')"
  assert_eq "401" "$(status_of "$out")" "$stack a token for another audience is HTTP 401 through the edge"
  assert_body_not_contains "$(body_of "$out")" '"data"' "$stack the refused token gets no GraphQL body"
  assert_eq "$want_body" "$(body_of "$out")" "$stack exact 401 body"
  headers="$(LGTM_BEARER="$OTHER" http_headers POST "$pub" -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}')"
  assert_eq "$want_header" "$(header_value "$headers" www-authenticate)" "$stack exact WWW-Authenticate"
  resp="$(as "$OPS" "$pub" "$Q_TRACK" '{"id":"ABC123"}')"
  assert_no_errors "$resp" "$stack ops TrackCargo"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "ops reads ABC123"

  # 4. Authorization by object and by field, with Chapter 18's values.
  resp="$(as "$ANA" "$pub" '{ cargos(first: 10) { edges { node { trackingId } } totalCount } }')"
  assert_no_errors "$resp" "$stack ana cargos"
  assert_json_eq '["VWX901","DEF456","ABC123"]' "$(project .data.cargos.edges node.trackingId)" "$stack ana sees her three cargos, newest first"
  expect "3" '.data.cargos.totalCount' "ana's totalCount counts only her cargos"
  resp="$(as "$BO" "$pub" '{ cargo(trackingId: "ABC123") { trackingId } }')"
  assert_no_errors "$resp" "$stack bo asks for an ACME cargo"
  assert_null_at "$resp" '.data.cargo' "$stack a cargo owned by another shipper is null, like an unknown one"
  resp="$(as "$ANA" "$pub" "$Q_HISTORY" '{"id":"ABC123"}')"
  assert_error_count "$resp" 2 "$stack ana registrationTime: one error per event"
  assert_error_extension "$resp" '["cargo","handlingHistory","edges",0,"node","registrationTime"]' code '"FORBIDDEN"' "$stack ana registrationTime: code"
  assert_error_message_at "$resp" '["cargo","handlingHistory","edges",0,"node","registrationTime"]' "operator role required" "$stack ana registrationTime: message"
  assert_null_at "$resp" '.data.cargo.handlingHistory.edges.0.node' "$stack ana: the refused field nulls the edge's node"
  resp="$(as "$OPS" "$pub" "$Q_HISTORY" '{"id":"ABC123"}')"
  assert_no_errors "$resp" "$stack ops registrationTime"
  assert_json_eq '["evt_2","evt_1"]' "$(project .data.cargo.handlingHistory.edges node.id)" "$stack ops: history ids"

  # 5. Limits run before identity: a refused document makes no source call, for
  #    an anonymous caller too.
  source_calls_reset_in "$stack"
  resp="$(gql "$pub" "$Q_OVER")"
  assert_has_errors "$resp" "$stack OverBudget"
  assert_no_data "$resp" "$stack OverBudget: no data"
  expect "maximum query complexity exceeded 7651 > 1000" '.errors.0.message' "OverBudget: message"
  resp="$(gql "$pub" "$D_DEEP")"
  assert_has_errors "$resp" "$stack D_DEEP"
  case "$stack" in
    quarkus) assert_error_message_contains "$resp" "maximum query depth exceeded 16 > 15" "$stack D_DEEP: message" ;;
    python) assert_error_message_contains "$resp" "exceeds maximum operation depth of 14" "$stack D_DEEP: message" ;;
  esac
  resp="$(gql "$pub" "$(gen_alias_bomb)")"
  assert_has_errors "$resp" "$stack A_BOMB"
  expect "150 aliases found. Allowed: 20" '.errors.0.message' "A_BOMB: message"
  # The token limit: a document of 5500 tokens, about 60 KB, under the edge's 64k body limit.
  out="$(gql_any "$pub" "{ $(python3 -I -c 'print("__typename " * 5500, end="")')}")"
  assert_has_errors "$(body_of "$out")" "$stack a 5500-token document is refused"
  assert_no_data "$(body_of "$out")" "$stack the token limit returns no data"
  assert_error_message_contains "$(body_of "$out")" "$tokens_message" "$stack token limit message"
  assert_source_call_count "$(source_calls_in "$stack")" '*' '*' 0 "$stack the refused documents made no source call"

  # 6. Batching under authorization: Chapter 14's calls, as an operator.
  source_calls_reset_in "$stack"
  resp="$(as "$OPS" "$pub" "$Q_FAN")"
  assert_no_errors "$resp" "$stack FanOut"
  assert_json_eq '["VWX901","XYZ789","STU678","DEF456"]' "$(project .data.cargos.edges node.trackingId)" "$stack FanOut pages the four cargos"
  assert_source_calls_exactly "$(source_calls_in "$stack")" "$fan_keys" "$stack FanOut: $total source calls"

  # 7. Real time through the edge. Five subscribers on ABC123 are up before the one
  #    registration, REG_F1, and each hears (or is refused) on its own terms.
  check_realtime "$stack" "$pub" "$base" "$eport"

  # 8. The diagnosis path: the caller's trace id through the edge, to Tempo and Loki.
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  source_calls_reset_in "$stack"
  resp="$(LGTM_BEARER="$OPS" LGTM_TRACEPARENT="$tp" gql "$pub" "$Q_LIST" '{}' ListCargos)"
  assert_error_extension "$resp" '["cargos","edges",5,"node"]' traceId "\"$trace_id\"" "$stack ListCargos: extensions.traceId equals the id the client sent through the edge"
  calls="$(source_calls_in "$stack")"
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$total")"
  assert_span "$trace" "$op" 1 1 "$stack ListCargos: Tempo holds the operation span for that id"
  assert_eq "$(log_count "$calls" location getLocations)" "$(span_count "$trace" '^source\.call$' source.operation getLocations)" "$stack: one source.call span per getLocations call in the log"
  assert_span_attr_absent "$trace" 'authorization|token' "$stack: no span carries a credential"
  loki_wait "$LOKI" "{service_name=\"ch27-final-$stack\"} | trace_id=\"$trace_id\"" 90 1 >/dev/null
  echo "lib.sh: ok — $stack: Loki holds a record for trace $trace_id" >&2

  echo "=== $stack: final-project check passed ==="
}

# check_realtime <stack> <public-url> <base> <edge-port>
check_realtime() {
  local stack="$1" pub="$2" base="$3" eport="$4"
  local ws="wss://edge:$eport/graphql" feed="$3/events/cargos/ABC123"
  local pid_watch pid_audit pid_ops pid_sse rc out
  local want_sub=3

  echo "--- $stack: subscriptions"
  # Refusals come first and leave no subscriber behind.
  out="$SCRATCH/$stack-anon.out"
  rc=0
  compose_run client --url "$ws" --count 1 --timeout 30 >"$out" 2>/dev/null || rc=$?
  assert_eq "1" "$rc" "$stack an anonymous subscription ends with an error message"
  assert_eq "UNAUTHENTICATED" "$(python3 -I -c 'import json,sys; print(json.loads(sys.stdin.readline())["error"][0]["extensions"]["code"])' <"$out")" "$stack anonymous subscription: code"
  out="$SCRATCH/$stack-bo.out"
  rc=0
  compose_run -e "TOKEN=$BO" client --url "$ws" --count 1 --timeout 30 >"$out" 2>/dev/null || rc=$?
  assert_eq "1" "$rc" "$stack bo watching ACME's cargo ends with an error message"
  assert_eq "FORBIDDEN" "$(python3 -I -c 'import json,sys; print(json.loads(sys.stdin.readline())["error"][0]["extensions"]["code"])' <"$out")" "$stack bo's subscription: code"
  assert_eq "not permitted to watch this cargo" "$(python3 -I -c 'import json,sys; print(json.loads(sys.stdin.readline())["error"][0]["message"])' <"$out")" "$stack bo's subscription: message"
  # An unknown cargo is refused like another shipper's: the error does not say which ids exist.
  out="$SCRATCH/$stack-unknown.out"
  rc=0
  compose_run -e "TOKEN=$ANA" client --url "$ws" --tracking-id ZZZ999 --count 1 --timeout 30 >"$out" 2>/dev/null || rc=$?
  assert_eq "1" "$rc" "$stack ana watching an unknown cargo ends with an error message"
  assert_eq "FORBIDDEN" "$(python3 -I -c 'import json,sys; print(json.loads(sys.stdin.readline())["error"][0]["extensions"]["code"])' <"$out")" "$stack an unknown cargo: code"
  assert_eq "not permitted to watch this cargo" "$(python3 -I -c 'import json,sys; print(json.loads(sys.stdin.readline())["error"][0]["message"])' <"$out")" "$stack an unknown cargo: the same message as another shipper's cargo"
  out="$SCRATCH/$stack-bad.out"
  rc=0
  compose_run -e "TOKEN=not.a.jwt" client --url "$ws" --count 1 --timeout 30 >"$out" 2>/dev/null || rc=$?
  assert_eq "3" "$rc" "$stack a token that does not validate refuses the upgrade"
  assert_json_eq '{"graphql":{},"sse":{}}' "$(body_of "$(compose_exec_http "$stack" GET /debug/subscribers)")" "$stack no subscriber after the refusals"

  # The feed's refusals.
  out="$(http_any GET "$feed" -H 'Accept: text/event-stream' -m 5)"
  assert_eq "401" "$(status_of "$out")" "$stack the feed without a token is 401"
  out="$(LGTM_BEARER="$BO" http_any GET "$feed" -H 'Accept: text/event-stream' -m 5)"
  assert_eq "403" "$(status_of "$out")" "$stack the feed for another shipper's cargo is 403"

  # Three WebSocket subscribers, as ana (the contract's fields), ana (the audit document) and ops (the audit document).
  : >"$SCRATCH/$stack-watch.out"
  : >"$SCRATCH/$stack-audit.out"
  : >"$SCRATCH/$stack-opsaudit.out"
  compose_run -e "TOKEN=$ANA" client --url "$ws" --tracking-id ABC123 --count 1 --timeout 120 --frames \
    >"$SCRATCH/$stack-watch.out" 2>"$SCRATCH/$stack-watch.err" &
  pid_watch=$!
  compose_run -e "TOKEN=$ANA" client --url "$ws" --tracking-id ABC123 --count 1 --timeout 120 --query /app/documents/audit.graphql \
    >"$SCRATCH/$stack-audit.out" 2>/dev/null &
  pid_audit=$!
  compose_run -e "TOKEN=$OPS" client --url "$ws" --tracking-id ABC123 --count 1 --timeout 120 --query /app/documents/audit.graphql \
    >"$SCRATCH/$stack-opsaudit.out" 2>/dev/null &
  pid_ops=$!
  if [[ "$stack" == "python" ]]; then
    # GraphQL over SSE (graphql-sse): Strawberry serves it on the same path.
    : >"$SCRATCH/$stack-gqlsse.out"
    LGTM_BEARER="$ANA" sse_collect "$pub" 120 1 -X POST -H 'Content-Type: application/json' -H 'Accept: text/event-stream' --data "$SUB_BODY" \
      >"$SCRATCH/$stack-gqlsse.out" &
    pid_sse=$!
    want_sub=4
  fi
  wait_subscribers "$stack" graphql ABC123 "$want_sub" 120

  # REG_F1 is the first write of the run: the operator registers it through the edge.
  resp="$(as "$OPS" "$pub" "$REGISTER" "{\"i\":$REG_F1}")"
  assert_no_errors "$resp" "$stack REG_F1"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "REG_F1 is evt_10"
  assert_json_eq '[]' "$(json_field '.data.registerHandlingEvent.userErrors' <<<"$resp")" "$stack REG_F1 has no userErrors"

  rc=0
  wait "$pid_watch" || rc=$?
  assert_eq "0" "$rc" "$stack ana's client received its event"
  out="$SCRATCH/$stack-watch.out"
  assert_eq "1" "$(wc -l <"$out" | tr -d ' ')" "$stack ana's client printed exactly one event"
  resp="$(first_line "$out")"
  expect "evt_10" '.data.cargoHandled.id' "ana's event is evt_10"
  expect "Hamburg" '.data.cargoHandled.location.name' "ana's event location"
  expect "IN_PORT" '.data.cargoHandled.cargo.delivery.transportStatus' "ana's event delivery, read after the unload"
  assert_json_eq '[">>> connection_init","<<< connection_ack",">>> subscribe","<<< next",">>> complete"]' \
    "$(frame_types "$SCRATCH/$stack-watch.err")" "$stack the graphql-transport-ws frames of ana's run"

  rc=0
  wait "$pid_audit" || rc=$?
  assert_eq "0" "$rc" "$stack ana's audit client received its event"
  assert_json_eq '{"event":"evt_10","coded_errors":[["FORBIDDEN","registrationTime"],["FORBIDDEN","registrationTime"]],"nodes":[null,null]}' \
    "$(history_view "$SCRATCH/$stack-audit.out")" "$stack ana's event: registrationTime is FORBIDDEN, as in a query"
  rc=0
  wait "$pid_ops" || rc=$?
  assert_eq "0" "$rc" "$stack ops' audit client received its event"
  assert_json_eq '{"event":"evt_10","coded_errors":[],"nodes":[{"id":"evt_10","has_time":true},{"id":"evt_2","has_time":true}]}' \
    "$(history_view "$SCRATCH/$stack-opsaudit.out")" "$stack ops' event carries registrationTime"

  if [[ "$stack" == "python" ]]; then
    wait "$pid_sse"
    assert_eq "next" "$(json_field '.event' <<<"$(first_line "$SCRATCH/$stack-gqlsse.out")")" "$stack graphql-sse delivers a next event"
    assert_eq "evt_10" "$(json_field '.data' <<<"$(first_line "$SCRATCH/$stack-gqlsse.out")" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["data"]["cargoHandled"]["id"])')" "$stack graphql-sse payload id"
  fi

  # The plain feed applies the same rules: ana resumes from evt_9 and hears evt_10.
  out="$SCRATCH/$stack-feed.out"
  LGTM_BEARER="$ANA" sse_collect "$feed" 30 1 -H 'Accept: text/event-stream' -H 'Last-Event-ID: evt_9' >"$out"
  resp="$(first_line "$out")"
  expect "handled" '.event' "the feed's event name"
  expect "evt_10" '.id' "the feed resumes from evt_9 with evt_10"
  assert_json_eq '{"id":"evt_10","trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","completionTime":"2026-10-09T15:00:00Z"}' \
    "$(json_field '.data' <<<"$resp")" "$stack the feed's payload"

  resp="$(as "$OPS" "$pub" "$Q_TRACK" '{"id":"ABC123"}')"
  assert_no_errors "$resp" "$stack TrackCargo after REG_F1"
  expect "IN_PORT" '.data.cargo.delivery.transportStatus' "ABC123 is IN_PORT after the registration"

  # Every subscription ended with its client.
  wait_subscribers "$stack" graphql ABC123 0 30
  wait_subscribers "$stack" sse ABC123 0 30
}

# --- the load, through the edge -------------------------------------------------

check_load() {
  local stack per_request fan_keys eport summary calls
  echo
  echo "=== k6 through the edge, as an operator ==="
  refresh_tokens
  for stack in quarkus python; do
    case "$stack" in
      quarkus)
        eport=8443; per_request=8
        fan_keys='booking.listCargos:*,booking.getCargos:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,handling.listEventsFor:DEF456+STU678+VWX901+XYZ789,location.getLocations:DEHAM+SGSIN+USNYC,voyage.getVoyages:V100S+V200E+V300A,location.getLocations:CNSHA+DEHAM+NLRTM'
        ;;
      python)
        eport=8444; per_request=6
        fan_keys='booking.listCargos:*,booking.getCargos:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,handling.listEventsFor:DEF456+STU678+VWX901+XYZ789,location.getLocations:CNSHA+DEHAM+NLRTM+SGSIN+USNYC,voyage.getVoyages:V100S+V200E+V300A'
        ;;
    esac

    # fanout: 80 FanOut requests from 8 virtual users. Every request makes the calls of a single request.
    source_calls_reset_in "$stack"
    summary="$(run_load load fanout 80 -e "TARGET=https://edge:$eport/graphql" -e "STACK=$stack" -e "TOKEN=$OPS")"
    assert_eq "0" "$(json_field '.metrics.http_req_failed.values.rate' <<<"$summary")" "$stack load fanout: no transport failure"
    calls="$(source_calls_in "$stack")"
    assert_request_count "$calls" 80 "$stack fanout: one request id per request"
    assert_calls_per_request "$calls" "$per_request" "$stack fanout: $per_request calls per request under concurrency"
    assert_calls_same_per_request "$calls" "$fan_keys" "$stack fanout: every request made Chapter 14's calls"

    # cost: 40 FanOut and 40 OverBudget together. A refused request makes no call.
    source_calls_reset_in "$stack"
    summary="$(run_load load cost 80 -e "TARGET=https://edge:$eport/graphql" -e "STACK=$stack" -e "TOKEN=$OPS")"
    assert_eq "0" "$(json_field '.metrics.http_req_failed.values.rate' <<<"$summary")" "$stack load cost: no transport failure"
    calls="$(source_calls_in "$stack")"
    assert_request_count "$calls" 40 "$stack cost: only the accepted requests reached a source"
    assert_calls_per_request "$calls" "$per_request" "$stack cost: $per_request calls per accepted request"
    assert_calls_same_per_request "$calls" "$fan_keys" "$stack cost: the accepted requests made their own calls"
  done
}

# --- run ------------------------------------------------------------------------

echo "=== Step 0: the load documents are Chapter 23's ==="
cmp -s "$SCRIPT_DIR/documents/fan-out.graphql" "$DOCS/fan-out.graphql" || { echo "FAIL - fan-out.graphql differs from Chapter 23's" >&2; exit 1; }
cmp -s "$SCRIPT_DIR/documents/over-budget.graphql" "$DOCS/load/over-budget.graphql" || { echo "FAIL - over-budget.graphql differs from Chapter 23's" >&2; exit 1; }
echo "lib.sh: ok — fan-out.graphql and over-budget.graphql are byte-equal to Chapter 23's" >&2

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"
# `up -d` returns once the edge has started; --wait returns once every service is healthy.
compose up -d --wait
wait_for_http "$REALM_URL" 180

check_tier

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus"
run_stack_check "python"

echo
echo "=== Step 3: load ==="
check_load

echo
echo "PASS - Ch27 The final project: both stacks serve the complete canonical schema (the internal instances equal" \
     "the contract, the public ones refuse introspection) behind an nginx edge that terminates TLS 1.3, refuses a" \
     "100 KB body and routes only /graphql and /events/; Keycloak tokens are validated and authorized by operation," \
     "object and field on queries, subscriptions and the event feed; over-budget, too-deep and aliased documents are" \
     "refused before any source call; one registration reaches the subscribers over wss (and graphql-sse and the feed)" \
     "under each subscriber's own rights; a trace id sent through the edge is found in the error, in Tempo and in Loki;" \
     "and two k6 runs through the edge hold every check and the per-request source calls."
