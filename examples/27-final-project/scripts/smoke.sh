#!/usr/bin/env bash
# examples/27-final-project/scripts/smoke.sh
#
# The defences of the final project, run against the release on the cluster
# through the NodePorts the profile publishes on 127.0.0.1: the edge over TLS 1.3,
# Keycloak tokens for three users, an authorized and a refused query,
# introspection refused on the public instances and answered on the internal
# ones, an over-budget refusal before any source call, one subscription event
# delivered to a client running in the cluster, one k6 run through the edge, and
# a trace found by the id the client sent. Run it after up.sh. It stops at the
# first failed check and prints PASS at the end.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../../_lib/lib.sh
source "$SCRIPTS/../../_lib/lib.sh"
# shellcheck source=SCRIPTDIR/lib.sh
source "$SCRIPTS/lib.sh"

# assert_sdl_equals diffs the two schemas in both directions. A deprecation reaches
# the live side as state and the canonical file declares it as a directive, so the
# diff names the directive on that one field; the state is asserted separately.
LGTM_SDL_IGNORE="${LGTM_SDL_IGNORE}|Directive deprecated was (removed from|added to) field Itinerary\.finalArrivalDate\$"

session_start
SCRATCH="$(mktemp -d)"
on_exit "rm -rf '$SCRATCH'"

# Tokens are fetched at localhost, the host name of the issuer the stacks pin
# (identity.issuer): a token carries the address its client used.
TOKEN_URL="http://localhost:$KEYCLOAK_PORT/realms/shipping/protocol/openid-connect/token"
TEMPO="http://127.0.0.1:$TEMPO_PORT"
LOKI="http://127.0.0.1:$LOKI_PORT"
CLIENT_IMAGE="gql-ch27-client:1.0"
LOAD_IMAGE="gql-ch27-load:1.0"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
REGISTER='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } userErrors { code } } }'
REG_F1='{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z","idempotencyKey":"ch27-final-unload-1"}'
Q_FAN="$(<"$SCRIPTS/../documents/fan-out.graphql")"
Q_OVER="$(<"$SCRIPTS/../documents/over-budget.graphql")"
Q_LIST='query ListCargos { cargos(first: 10) { totalCount edges { node { trackingId } } } }'
# shellcheck disable=SC2016
Q_HISTORY='query History($id: TrackingId!) { cargo(trackingId: $id) { handlingHistory(first: 2) { edges { node { id registrationTime } } } } }'

# A 100 KB comment inside a valid query: a large body with almost no tokens.
python3 -I -c '
import json, sys
with open(sys.argv[1] + "/comment.json", "w") as f:
    json.dump({"query": "{ __typename # " + "x" * 100000 + "\n}"}, f)
' "$SCRATCH"

# --- local helpers --------------------------------------------------------------

# kn <kubectl args...> - kubectl in the release namespace.
kn() { kc -n "$NAMESPACE" "$@"; }

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

# source_calls_kube <deployment> / source_calls_reset_kube <deployment> - the
# source-call log of an instance, read inside its pod (the edge does not route /debug).
source_calls_kube() {
  kn exec "deploy/$1" -- curl -fsS http://localhost:8080/debug/source-calls
}
source_calls_reset_kube() {
  assert_eq "204" "$(kn exec "deploy/$1" -- curl -sS -o /dev/null -w '%{http_code}' -X DELETE http://localhost:8080/debug/source-calls)" "$1 source-call log reset"
}

# subscribers <deployment> <channel> <tracking-id> - the live subscription count.
subscribers() {
  python3 -I -c '
import json, sys
print(json.load(sys.stdin).get(sys.argv[1], {}).get(sys.argv[2], 0))
' "$2" "$3" < <(kn exec "deploy/$1" -- curl -fsS http://localhost:8080/debug/subscribers)
}

# wait_subscribers <deployment> <channel> <tracking-id> <n> [timeout]
wait_subscribers() {
  local deployment="$1" channel="$2" id="$3" want="$4" timeout="${5:-90}" waited=0 have=-1
  while ((waited < timeout)); do
    have="$(subscribers "$deployment" "$channel" "$id")"
    if [[ "$have" == "$want" ]]; then return 0; fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "FAIL - $deployment had $have $channel subscribers for $id after ${timeout}s, wanted $want" >&2
  return 1
}

# pod_names <deployment> - the live pods of a Deployment, one name per line.
pod_names() {
  kn get pods -l "app.kubernetes.io/name=$1" -o json | python3 -I -c '
import json, sys
items = json.load(sys.stdin)["items"]
print("\n".join(sorted(i["metadata"]["name"] for i in items if not i["metadata"].get("deletionTimestamp"))))
'
}

# trace_pods <trace-id> - the k8s.pod.name resource attributes of a trace, one per line.
trace_pods() {
  curl -fsS --max-time 20 "$TEMPO/api/traces/$1" | python3 -I -c '
import json, sys
seen = set()
for batch in json.load(sys.stdin).get("batches", []):
    for kv in batch.get("resource", {}).get("attributes", []):
        if kv["key"] == "k8s.pod.name":
            seen.add(kv["value"]["stringValue"])
print("\n".join(sorted(seen)))
'
}

# start_pod <name> <image> <component> <env-json> <args-json> - a pod in the
# release namespace that runs one of this chapter's images to completion, with
# the chart's CA mounted at /certs/ca.crt and the restricted security context.
start_pod() {
  local name="$1" image="$2" component="$3" env_json="$4" args_json="$5" overrides
  overrides="$(python3 -I -c '
import json, sys
name, image, secret = sys.argv[1], sys.argv[2], sys.argv[5]
env, args = json.loads(sys.argv[3]), json.loads(sys.argv[4])
env = dict(env, SSL_CERT_FILE="/certs/ca.crt")
print(json.dumps({"spec": {
    "securityContext": {"runAsNonRoot": True, "seccompProfile": {"type": "RuntimeDefault"}},
    "containers": [{
        "name": name, "image": image, "imagePullPolicy": "Never", "args": args,
        "env": [{"name": k, "value": v} for k, v in env.items()],
        "resources": {"requests": {"cpu": "100m", "memory": "128Mi"}, "limits": {"memory": "512Mi"}},
        "securityContext": {"allowPrivilegeEscalation": False, "capabilities": {"drop": ["ALL"]},
                            "seccompProfile": {"type": "RuntimeDefault"}},
        "volumeMounts": [{"name": "ca", "mountPath": "/certs", "readOnly": True}]}],
    "volumes": [{"name": "ca", "secret": {"secretName": secret, "items": [{"key": "ca.crt", "path": "ca.crt"}]}}]}}))
' "$name" "$image" "$env_json" "$args_json" "$RELEASE-edge-tls")"
  kn delete pod "$name" --ignore-not-found --wait >/dev/null
  kn run "$name" --restart=Never --image="$image" \
    --labels="app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/component=$component" \
    --overrides="$overrides" >/dev/null
}

# wait_pod <name> [timeout] - until the pod has finished; fails unless it Succeeded.
wait_pod() {
  local name="$1" timeout="${2:-240}" waited=0 phase
  while ((waited < timeout)); do
    phase="$(kn get pod "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in
      Succeeded) return 0 ;;
      Failed)
        echo "FAIL - pod $name failed:" >&2
        kn logs "$name" --tail=20 >&2 || true
        return 1
        ;;
    esac
    sleep 2
    waited=$((waited + 2))
  done
  echo "FAIL - pod $name did not finish within ${timeout}s" >&2
  return 1
}

# --- the release ------------------------------------------------------------------

check_release() {
  local port published status deployment
  echo
  echo "=== the release: published ports, rollout ==="
  for port in "${NODE_PORTS[@]}"; do
    published="$(docker port "$PROFILE" "${port}/tcp")"
    assert_contains "127.0.0.1:${port}" "$published" "docker port $PROFILE publishes $port on loopback"
  done
  status="$(hc status "$RELEASE" -n "$NAMESPACE" -o json | json_field .info.status)"
  assert_eq "deployed" "$status" "helm status $RELEASE"
  assert_eq "Succeeded" "$(kn get pod "$RELEASE-graphql-test" -o jsonpath='{.status.phase}')" "the helm test pod"
  for deployment in lgtm keycloak quarkus python quarkus-internal python-internal edge; do
    kn rollout status "deploy/$deployment" --timeout=60s >/dev/null
    echo "lib.sh: ok — deploy/$deployment is rolled out" >&2
  done
}

# --- per stack --------------------------------------------------------------------

# run_stack_check <stack> <edge-url> <internal-url>
run_stack_check() {
  local stack="$1" pub="$2" int="$3"
  local resp out denial total op trace_id tp trace pods
  case "$stack" in
    quarkus) total=8; denial="Introspection has been disabled for this request"; op='^query ListCargos$' ;;
    python) total=6; denial="introspection has been disabled"; op='^GraphQL Query: ListCargos$' ;;
  esac

  echo
  echo "=== verifying stack '$stack' through the edge at $pub ==="
  wait_for_graphql "$pub"
  wait_for_graphql "$int"

  # The internal instance serves the whole canonical schema; the public one
  # refuses introspection, even for an operator.
  assert_sdl_equals "$int" "$stack internal schema equals the canonical SDL"
  assert_deprecated "$int" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  resp="$(as "$OPS" "$pub" '{ __schema { queryType { name } } }')"
  assert_has_errors "$resp" "$stack public __schema is refused, even for an operator"
  assert_no_data "$resp" "$stack public __schema returns no data"
  assert_error_message_contains "$resp" "$denial" "$stack public __schema message"

  # The edge: TLS 1.3 only, a body limit, lab endpoints not routed.
  assert_transport_fails "$stack: a TLS 1.2 client is refused" --tlsv1.2 --tls-max 1.2 \
    -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "$pub"
  source_calls_reset_kube "$stack"
  out="$(http_any POST "$pub" -H 'Content-Type: application/json' --http1.1 -d "@$SCRATCH/comment.json")"
  assert_eq "413" "$(status_of "$out")" "$stack: a 100 KB body is refused at the edge"
  assert_source_call_count "$(source_calls_kube "$stack")" '*' '*' 0 "$stack: the refused body never reached the pod"
  out="$(http_any GET "${pub%/graphql}/debug/source-calls")"
  assert_eq "404" "$(status_of "$out")" "$stack: /debug/source-calls is not routed"

  # One refused query and one authorized query.
  resp="$(gql "$pub" '{ cargo(trackingId: "ABC123") { trackingId } }')"
  assert_error_extension "$resp" '["cargo"]' code '"UNAUTHENTICATED"' "$stack anonymous cargo: code"
  out="$(LGTM_BEARER="$OTHER" gql_any "$pub" '{ location(unLocode: "NLRTM") { name } }')"
  assert_eq "401" "$(status_of "$out")" "$stack a token for another audience is HTTP 401 through the edge"
  resp="$(as "$ANA" "$pub" '{ cargos(first: 10) { edges { node { trackingId } } totalCount } }')"
  assert_no_errors "$resp" "$stack ana cargos"
  assert_json_eq '["VWX901","DEF456","ABC123"]' "$(project .data.cargos.edges node.trackingId)" "$stack ana sees her three cargos"
  # shellcheck disable=SC2016
  resp="$(as "$ANA" "$pub" "$Q_HISTORY" '{"id":"ABC123"}')"
  assert_error_extension "$resp" '["cargo","handlingHistory","edges",0,"node","registrationTime"]' code '"FORBIDDEN"' "$stack ana registrationTime: code"

  # An over-budget document is refused before any source is asked.
  source_calls_reset_kube "$stack"
  resp="$(gql "$pub" "$Q_OVER")"
  assert_no_data "$resp" "$stack OverBudget: no data"
  assert_eq "maximum query complexity exceeded 7651 > 1000" "$(json_field '.errors.0.message' <<<"$resp")" "$stack OverBudget: message"
  assert_source_call_count "$(source_calls_kube "$stack")" '*' '*' 0 "$stack OverBudget: refused before any source call"
  source_calls_reset_kube "$stack"
  resp="$(as "$OPS" "$pub" "$Q_FAN")"
  assert_no_errors "$resp" "$stack FanOut as ops"
  assert_source_call_count "$(source_calls_kube "$stack")" '*' '*' "$total" "$stack FanOut: $total source calls, read inside the pod"

  check_subscription "$stack" "$pub"
  check_load "$stack"

  # The trace of a request carries the id the client chose, and names the pod.
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(LGTM_BEARER="$OPS" LGTM_TRACEPARENT="$tp" gql "$pub" "$Q_LIST" '{}' ListCargos)"
  assert_error_extension "$resp" '["cargos","edges",5,"node"]' traceId "\"$trace_id\"" "$stack: extensions.traceId equals the id sent through the edge"
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$total")"
  assert_span "$trace" "$op" 1 1 "$stack: Tempo holds the operation span for that id"
  pods="$(trace_pods "$trace_id")"
  assert_eq "1" "$(grep -c . <<<"$pods")" "$stack: the trace carries one k8s.pod.name"
  assert_contains "$pods" "$(pod_names "$stack")" "$stack: k8s.pod.name is the public instance's pod"
  loki_wait "$LOKI" "{service_name=\"ch27-final-$stack\"} | trace_id=\"$trace_id\"" 90 1 >/dev/null
  echo "lib.sh: ok — $stack: Loki holds a record for trace $trace_id" >&2
}

# check_subscription <stack> <edge-url> - ana subscribes
# from a pod in the cluster over wss through the edge; ops registers REG_F1 from
# the host; the pod's client prints exactly the event.
check_subscription() {
  local stack="$1" pub="$2" resp inport out
  inport=$([[ "$stack" == "quarkus" ]] && echo 8443 || echo 8444)
  echo "--- $stack: one subscription event, delivered to a client in the cluster"
  start_pod "sub-$stack" "$CLIENT_IMAGE" client \
    "{\"TOKEN\":\"$ANA\"}" \
    "[\"--url\",\"wss://edge:$inport/graphql\",\"--tracking-id\",\"ABC123\",\"--count\",\"1\",\"--timeout\",\"120\"]"
  wait_subscribers "$stack" graphql ABC123 1
  resp="$(as "$OPS" "$pub" "$REGISTER" "{\"i\":$REG_F1}")"
  assert_no_errors "$resp" "$stack REG_F1"
  assert_eq "evt_10" "$(json_field '.data.registerHandlingEvent.handlingEvent.id' <<<"$resp")" "$stack REG_F1 is evt_10"
  wait_pod "sub-$stack"
  out="$(kn logs "sub-$stack")"
  assert_eq "1" "$(grep -c . <<<"$out")" "$stack the client printed exactly one event"
  resp="$out"
  expect "evt_10" '.data.cargoHandled.id' "ana's event is evt_10"
  expect "IN_PORT" '.data.cargoHandled.cargo.delivery.transportStatus' "ana's event delivery, read after the unload"
  kn delete pod "sub-$stack" --wait >/dev/null
  wait_subscribers "$stack" graphql ABC123 0 30
}

# check_load <stack> - one k6 run of FanOut
# through the edge, from a pod in the cluster.
check_load() {
  local stack="$1" inport summary calls per_request
  inport=$([[ "$stack" == "quarkus" ]] && echo 8443 || echo 8444)
  per_request=$([[ "$stack" == "quarkus" ]] && echo 8 || echo 6)
  echo "--- $stack: one k6 run through the edge"
  source_calls_reset_kube "$stack"
  start_pod "k6-$stack" "$LOAD_IMAGE" load \
    "{\"RUN\":\"fanout\",\"STACK\":\"$stack\",\"TARGET\":\"https://edge:$inport/graphql\",\"TOKEN\":\"$OPS\"}" \
    '["run","--quiet","/scripts/tracking.js"]'
  wait_pod "k6-$stack" 300
  summary="$(kn logs "k6-$stack" | tail -n 1)"
  assert_eq "80" "$(json_field '.metrics.iterations.values.count' <<<"$summary")" "$stack k6 fanout: iterations"
  assert_eq "1" "$(json_field '.metrics.checks.values.rate' <<<"$summary")" "$stack k6 fanout: every check true"
  assert_eq "0" "$(json_field '.metrics.http_req_failed.values.rate' <<<"$summary")" "$stack k6 fanout: no transport failure"
  calls="$(source_calls_kube "$stack")"
  assert_request_count "$calls" 80 "$stack k6 fanout: one request id per request"
  assert_calls_per_request "$calls" "$per_request" "$stack k6 fanout: $per_request calls per request"
  kn delete pod "k6-$stack" --wait >/dev/null
}

# --- run ---------------------------------------------------------------------------

require_tools
[[ "$(profile_status)" == "Running" ]] || fail "profile $PROFILE is not running; run scripts/up.sh first"

# The chart generated the edge CA; every harness call trusts it.
kn get secret "$RELEASE-edge-tls" -o jsonpath='{.data.ca\.crt}' | base64 -d >"$SCRATCH/ca.crt"
export LGTM_CACERT="$SCRATCH/ca.crt"

check_release

echo
echo "=== tokens from Keycloak at the NodePort, the issuer the stacks pin ==="
wait_for_http "http://localhost:$KEYCLOAK_PORT/realms/shipping" 120
ANA="$(oidc_token "$TOKEN_URL" tracking-cli ana ana-fixture-pw)"
OPS="$(oidc_token "$TOKEN_URL" tracking-cli ops ops-fixture-pw)"
OTHER="$(oidc_token "$TOKEN_URL" other-cli ana ana-fixture-pw)"

run_stack_check quarkus "https://127.0.0.1:$EDGE_QUARKUS_PORT/graphql" "http://127.0.0.1:$INTERNAL_QUARKUS_PORT/graphql"
run_stack_check python "https://127.0.0.1:$EDGE_PYTHON_PORT/graphql" "http://127.0.0.1:$INTERNAL_PYTHON_PORT/graphql"

echo
echo "PASS - Ch27 The final project on Kubernetes: the release is deployed and tested; Keycloak tokens fetched at" \
     "the NodePort are accepted by both stacks; the edge serves TLS 1.3 only and refuses a 100 KB body; an" \
     "anonymous query and a token for another audience are refused, an operator's and a shipper's queries" \
     "are authorized by object and field; the public instances refuse introspection while the internal" \
     "instances equal the canonical SDL; an over-budget document is refused before any source call; a client" \
     "in the cluster receives a subscription event over wss; k6 runs 80 requests through the edge; and a" \
     "trace id sent through the edge is found in the error, in Tempo, in Loki and names the pod."
