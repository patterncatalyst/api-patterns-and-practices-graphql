#!/usr/bin/env bash
# examples/26-minikube/scripts/smoke.sh
#
# The GraphQL assertions of Chapter 25, run against the release on the cluster
# through the NodePorts the profile publishes on 127.0.0.1, plus what is new
# on Kubernetes: the pod named in the trace, a configuration change that rolls
# the pods, and a NetworkPolicy that keeps a stranger out. Run it after up.sh.
# It stops at the first failed check and prints PASS at the end.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../../_lib/lib.sh
source "$SCRIPTS/../../_lib/lib.sh"
# shellcheck source=SCRIPTDIR/lib.sh
source "$SCRIPTS/lib.sh"

session_start
SCRATCH="$(mktemp -d)"
on_exit "rm -rf '$SCRATCH'"

QUARKUS_URL="https://127.0.0.1:$EDGE_QUARKUS_PORT/graphql"
PYTHON_URL="https://127.0.0.1:$EDGE_PYTHON_PORT/graphql"
TEMPO="http://127.0.0.1:$TEMPO_PORT"
LOKI="http://127.0.0.1:$LOKI_PORT"
EDGE_IMAGE="registry.access.redhat.com/ubi10/nginx-126:10.2-1791973310"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
HEALTHY='query TrackCargo($id: TrackingId!) { cargo(trackingId: $id) { trackingId delivery { transportStatus } } }'
Q_FAN='query FanOut { cargos(first: 4) { edges { node { trackingId itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } } delivery { transportStatus } } } } }'
Q_LIST='query ListCargos { cargos(first: 10) { totalCount edges { node { trackingId } } } }'

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

# json_post <url> <body> [curl-args...] - POST a JSON body; output as gql_any.
json_post() {
  local url="$1" body="$2"
  shift 2
  http_any POST "$url" -H 'Content-Type: application/json' -d "$body" "$@"
}

# fan_shape - the data of $resp reduced to what the cases compare.
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

# source_calls_kube <stack> / source_calls_reset_kube <stack> - the source-call
# log of a backend, read inside its pod (the edge does not route /debug).
source_calls_kube() {
  kn exec "deploy/$1" -- curl -fsS http://localhost:8080/debug/source-calls
}
source_calls_reset_kube() {
  assert_eq "204" "$(kn exec "deploy/$1" -- curl -sS -o /dev/null -w '%{http_code}' -X DELETE http://localhost:8080/debug/source-calls)" "$1 source-call log reset"
}

# pod_names <stack> - the live pods of a Deployment (a pod that is shutting
# down is left out), one name per line.
pod_names() {
  kn get pods -l "app.kubernetes.io/name=$1" -o json | python3 -I -c '
import json, sys
items = json.load(sys.stdin)["items"]
print("\n".join(sorted(i["metadata"]["name"] for i in items if not i["metadata"].get("deletionTimestamp"))))
'
}

# trace_pods <trace-id> - the k8s.pod.name resource attributes of a trace, one
# per line, from Tempo's own JSON (the span helpers read span attributes only).
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

# probe_pod <name> <labels> - a one-shot pod posts a query to quarkus:8080 and
# prints "<http status> rc=<curl exit code>".
probe_pod() {
  local name="$1" labels="$2" overrides
  overrides="$(python3 -I -c '
import json, sys
print(json.dumps({"spec": {"containers": [{
    "name": "probe", "image": sys.argv[1], "imagePullPolicy": "Never",
    "command": ["sh", "-c", "curl -sS -m 5 -o /dev/null -w %{http_code} http://quarkus:8080/graphql -H content-type:application/json -d {\"query\":\"{__typename}\"}; echo \" rc=$?\""],
    "securityContext": {"allowPrivilegeEscalation": False, "capabilities": {"drop": ["ALL"]},
                        "runAsNonRoot": True, "seccompProfile": {"type": "RuntimeDefault"}}}]}}))
' "$EDGE_IMAGE")"
  kn run "$name" --restart=Never --image="$EDGE_IMAGE" --labels="$labels" --overrides="$overrides" \
    --attach --rm -q 2>/dev/null | tail -n1
}

# --- 1. the release ---------------------------------------------------------------

check_release() {
  local port published status values
  echo
  echo "=== the release: published ports, rollout, probes ==="
  for port in "${NODE_PORTS[@]}"; do
    published="$(docker port "$PROFILE" "${port}/tcp")"
    assert_contains "127.0.0.1:${port}" "$published" "docker port $PROFILE publishes $port on loopback"
  done
  status="$(hc status "$RELEASE" -n "$NAMESPACE" -o json | json_field .info.status)"
  assert_eq "deployed" "$status" "helm status $RELEASE"
  assert_eq "Succeeded" "$(kn get pod "$RELEASE-graphql-test" -o jsonpath='{.status.phase}')" "the helm test pod"
  for stack in lgtm quarkus python edge; do
    kn rollout status "deploy/$stack" --timeout=60s >/dev/null
    echo "lib.sh: ok — deploy/$stack is rolled out" >&2
  done
  values="$(hc get values "$RELEASE" -n "$NAMESPACE" -a -o json)"
  for stack in quarkus python; do
    for probe in startup readiness liveness; do
      assert_eq "$(json_field ".stacks.$stack.probes.$probe.path" <<<"$values")" \
        "$(kn get "deploy/$stack" -o "jsonpath={.spec.template.spec.containers[0].${probe}Probe.httpGet.path}")" \
        "$stack ${probe}Probe path equals the value"
    done
  done
  for stack in quarkus python edge; do
    assert_eq "1" "$(pod_names "$stack" | grep -c .)" "$stack runs one pod"
  done
}

# --- 2-3. Chapter 25's cases, through the NodePorts ---------------------------------

run_stack_check() {
  local stack="$1" url="$2" port="$3"
  local resp out calls total ghi_errors
  case "$stack" in
    quarkus) total=8; ghi_errors=6 ;;
    python) total=6; ghi_errors=1 ;;
  esac

  echo
  echo "=== verifying stack '$stack' through the edge at $url ==="
  wait_for_graphql "$url"

  resp="$(gql "$url" "$HEALTHY" '{"id":"ABC123"}' TrackCargo)"
  assert_no_errors "$resp" "$stack TrackCargo"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "TrackCargo transportStatus"

  source_calls_reset_kube "$stack"
  resp="$(gql "$url" "$Q_FAN" '{}' FanOut)"
  assert_no_errors "$resp" "$stack FanOut"
  assert_json_eq '[["VWX901",[["V300A","SGSIN","CNSHA"]]],["XYZ789",null],["STU678",[["V300A","SGSIN","CNSHA"]]],["DEF456",[["V100S","USNYC","DEHAM"],["V200E","DEHAM","NLRTM"]]]]' \
    "$(fan_shape)" "$stack FanOut returns Chapter 13's data"
  calls="$(source_calls_kube "$stack")"
  assert_source_call_count "$calls" '*' '*' "$total" "$stack FanOut: $total source calls, read inside the pod"

  resp="$(gql "$url" "$Q_LIST" '{}' ListCargos)"
  expect "6" '.data.cargos.totalCount' "the booking index holds six cargos"
  assert_eq "6" "$(json_len '.data.cargos.edges' <<<"$resp")" "$stack ListCargos: six edges"
  assert_error_extension "$resp" '["cargos","edges",5,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack ListCargos: GHI345's edge carries SERVICE_UNAVAILABLE"
  assert_error_message_at "$resp" '["cargos","edges",5,"node"]' "booking service unavailable" "$stack ListCargos: the exposed message"
  assert_error_count "$resp" "$ghi_errors" "$stack ListCargos: $ghi_errors errors"

  # The edge routes only /graphql.
  for path in /debug/source-calls /q/health/ready /health/ready /; do
    resp="$(http_any GET "https://127.0.0.1:$port$path")"
    assert_eq "404" "$(status_of "$resp")" "$stack: $path is not routed"
  done

  # TLS 1.3 at the edge, verified with the chart's CA.
  LGTM_CACERT='' assert_transport_fails "$stack: without the CA the certificate is untrusted" \
    -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "$url"
  assert_transport_fails "$stack: a TLS 1.2 client is refused" --tlsv1.2 --tls-max 1.2 \
    -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "$url"
  out="$(json_post "$url" '{"query":"{ __typename }"}' --tlsv1.3)"
  assert_eq "200" "$(status_of "$out")" "$stack: a TLS 1.3 client is served"

  # The body limit, ahead of the backend.
  source_calls_reset_kube "$stack"
  out="$(http_any POST "$url" -H 'Content-Type: application/json' --http1.1 -d "@$SCRATCH/comment.json")"
  assert_eq "413" "$(status_of "$out")" "$stack: a 100 KB body is refused at the edge"
  assert_source_call_count "$(source_calls_kube "$stack")" '*' '*' 0 "$stack: the refused body never reached the pod"

  # The contract, as in Chapter 19.
  assert_deprecated "$url" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"
}

# --- 4. the pod in the trace -------------------------------------------------------

check_trace() {
  local stack="$1" url="$2" op="$3" min="$4"
  local trace_id tp resp trace pods pod
  echo
  echo "=== $stack: the pod is named in the trace ==="
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(LGTM_TRACEPARENT="$tp" gql "$url" "$Q_LIST" '{}' ListCargos)"
  assert_error_extension "$resp" '["cargos","edges",5,"node"]' traceId "\"$trace_id\"" "$stack: extensions.traceId equals the id sent through the edge"
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$min")"
  assert_span "$trace" "$op" 1 1 "$stack: Tempo holds the operation span for that id"
  pods="$(trace_pods "$trace_id")"
  assert_eq "1" "$(grep -c . <<<"$pods")" "$stack: the trace carries one k8s.pod.name"
  pod="$pods"
  assert_contains "$pod" "$(pod_names "$stack")" "$stack: k8s.pod.name is a pod of the Deployment"
  loki_wait "$LOKI" "{service_name=\"ch26-$stack\"} | trace_id=\"$trace_id\"" 90 1 >/dev/null
  echo "lib.sh: ok — $stack: Loki holds a record for trace $trace_id" >&2
}

# --- 5. NetworkPolicy --------------------------------------------------------------

check_network_policy() {
  local out
  echo
  echo "=== NetworkPolicy: the stacks accept the edge and the test pod ==="
  out="$(probe_pod probe-stranger "app.kubernetes.io/name=probe")"
  assert_contains "rc=28" "$out" "a pod without the edge or test label times out against quarkus:8080"
  out="$(probe_pod probe-test "app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/component=test")"
  assert_contains "200 rc=0" "$out" "a pod labelled as the test pod reaches quarkus:8080"
}

# --- 6. a configuration change rolls the pods -------------------------------------

check_config_roll() {
  local before_sum before_pod quarkus_sum quarkus_pod after_sum after_pod ca_before ca_after
  echo
  echo "=== a configuration change rolls only the pods that read it ==="
  before_sum="$(kn get deploy/python -o 'jsonpath={.spec.template.metadata.annotations.checksum/config}')"
  before_pod="$(pod_names python)"
  quarkus_sum="$(kn get deploy/quarkus -o 'jsonpath={.spec.template.metadata.annotations.checksum/config}')"
  quarkus_pod="$(pod_names quarkus)"
  ca_before="$(sha256_hex "$(kn get secret "$RELEASE-edge-tls" -o jsonpath='{.data.ca\.crt}')")"

  hc upgrade "$RELEASE" "$CHART_DIR" -n "$NAMESPACE" --reuse-values \
    --set stacks.python.env.TRACKING_SOURCE_LATENCY_MS=100 --wait --timeout 5m >/dev/null
  kn rollout status deploy/python --timeout=3m >/dev/null
  after_sum="$(kn get deploy/python -o 'jsonpath={.spec.template.metadata.annotations.checksum/config}')"
  after_pod="$(pod_names python)"
  [[ "$after_sum" != "$before_sum" ]] || { echo "FAIL - the python checksum/config did not change" >&2; return 1; }
  echo "lib.sh: ok — python checksum/config changed" >&2
  [[ "$after_pod" != "$before_pod" ]] || { echo "FAIL - the python pod was not replaced" >&2; return 1; }
  echo "lib.sh: ok — the python pod was replaced ($before_pod -> $after_pod)" >&2
  assert_eq "100" "$(kn exec deploy/python -- printenv TRACKING_SOURCE_LATENCY_MS)" "the new pod runs with TRACKING_SOURCE_LATENCY_MS=100"
  assert_eq "$quarkus_sum" "$(kn get deploy/quarkus -o 'jsonpath={.spec.template.metadata.annotations.checksum/config}')" "quarkus checksum/config is unchanged"
  assert_eq "$quarkus_pod" "$(pod_names quarkus)" "the quarkus pod was not replaced"
  ca_after="$(sha256_hex "$(kn get secret "$RELEASE-edge-tls" -o jsonpath='{.data.ca\.crt}')")"
  assert_eq "$ca_before" "$ca_after" "the upgrade kept the edge certificate (lookup)"
  wait_for_graphql "$PYTHON_URL"

  hc upgrade "$RELEASE" "$CHART_DIR" -n "$NAMESPACE" --reuse-values \
    --set stacks.python.env.TRACKING_SOURCE_LATENCY_MS=250 --wait --timeout 5m >/dev/null
  kn rollout status deploy/python --timeout=3m >/dev/null
  assert_eq "250" "$(kn exec deploy/python -- printenv TRACKING_SOURCE_LATENCY_MS)" "the value is back to 250"
  wait_for_graphql "$PYTHON_URL"
}

# --- run ---------------------------------------------------------------------------

require_tools
[[ "$(profile_status)" == "Running" ]] || fail "profile $PROFILE is not running; run scripts/up.sh first"

# The chart generated the edge CA; every harness call trusts it.
kn get secret "$RELEASE-edge-tls" -o jsonpath='{.data.ca\.crt}' | base64 -d >"$SCRATCH/ca.crt"
export LGTM_CACERT="$SCRATCH/ca.crt"

check_release
run_stack_check quarkus "$QUARKUS_URL" "$EDGE_QUARKUS_PORT"
run_stack_check python "$PYTHON_URL" "$EDGE_PYTHON_PORT"
check_trace quarkus "$QUARKUS_URL" '^query ListCargos$' 8
check_trace python "$PYTHON_URL" '^GraphQL Query: ListCargos$' 6
check_network_policy
check_config_roll

echo
echo "PASS - Ch26 Kubernetes on minikube: the release is deployed and tested; both stacks answer through the" \
     "edge NodePorts with Chapter 25's results; the edge refuses a 100 KB body with 413, serves TLS 1.3 only" \
     "and routes only /graphql; a trace id sent through the edge is found in the error, in Tempo and in Loki," \
     "and the trace names the pod; a stranger pod is refused by the NetworkPolicy; a configuration change" \
     "rolls only the pods that read it."
