#!/usr/bin/env bash
# examples/99-appendix-a-openshift-crc/scripts/smoke.sh
#
# The final project's checks, run against the release through its Routes: edge TLS
# at the router verified with the cluster's ingress CA, Keycloak tokens fetched at
# the Keycloak Route, an authorized and a refused query, the edge's body limit,
# the internal instances equal to the canonical SDL, one FanOut with its source
# calls counted inside the pod, and a trace found by the id the client sent. Run
# it after up.sh. It stops at the first failed check and prints PASS at the end.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../../_lib/lib.sh
source "$SCRIPTS/../../_lib/lib.sh"
# shellcheck source=SCRIPTDIR/lib.sh
source "$SCRIPTS/lib.sh"

# The canonical file declares a deprecation as a directive and the live schema
# reports it as state; assert_deprecated checks the state.
LGTM_SDL_IGNORE="${LGTM_SDL_IGNORE}|Directive deprecated was (removed from|added to) field Itinerary\.finalArrivalDate\$"

session_start
SCRATCH="$(mktemp -d)"
on_exit "rm -rf '$SCRATCH'"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
Q_LIST='query ListCargos { cargos(first: 10) { totalCount edges { node { trackingId } } } }'
Q_FAN="$(<"$SCRIPTS/../../27-final-project/documents/fan-out.graphql")"
Q_OVER="$(<"$SCRIPTS/../../27-final-project/documents/over-budget.graphql")"

# A 100 KB comment inside a valid query: a large body with almost no tokens.
python3 -I -c '
import json, sys
with open(sys.argv[1] + "/comment.json", "w") as f:
    json.dump({"query": "{ __typename # " + "x" * 100000 + "\n}"}, f)
' "$SCRATCH"

# as <token-or-empty> <gql args...> - one GraphQL request as that caller.
as() {
  local token="$1"
  shift
  LGTM_BEARER="$token" gql "$@"
}

# tracking_ids - the tracking ids of data.cargos.edges on stdin, as a JSON list.
tracking_ids() {
  python3 -I -c '
import json, sys
edges = json.load(sys.stdin)["data"]["cargos"]["edges"]
print(json.dumps([e["node"]["trackingId"] for e in edges]))
'
}

# source_calls_pod / source_calls_reset_pod <deployment> - the source-call log of
# an instance, read inside its pod (the edge does not route /debug).
source_calls_pod() {
  ocn exec "deploy/$1" -- curl -fsS http://localhost:8080/debug/source-calls
}
source_calls_reset_pod() {
  assert_eq "204" "$(ocn exec "deploy/$1" -- curl -sS -o /dev/null -w '%{http_code}' -X DELETE http://localhost:8080/debug/source-calls)" "$1 source-call log reset"
}

# trace_in_tempo <trace-id> - poll the observability pod's Tempo until it holds the trace.
trace_in_tempo() {
  local id="$1" waited=0
  while ((waited < 90)); do
    if ocn exec deploy/lgtm -- curl -fsS "http://localhost:3200/api/traces/$id" >"$SCRATCH/trace.json" 2>/dev/null; then
      return 0
    fi
    sleep 3
    waited=$((waited + 3))
  done
  return 1
}

# trace_pod_names - the k8s.pod.name resource attributes of the fetched trace.
trace_pod_names() {
  python3 -I -c '
import json, sys
seen = set()
for batch in json.load(open(sys.argv[1])).get("batches", []):
    for kv in batch.get("resource", {}).get("attributes", []):
        if kv["key"] == "k8s.pod.name":
            seen.add(kv["value"]["stringValue"])
print("\n".join(sorted(seen)))
' "$SCRATCH/trace.json"
}

# --- run ---------------------------------------------------------------------------

require_crc

echo
echo "=== the release and the ingress CA ==="
assert_eq "deployed" "$(hc status "$RELEASE" -n "$PROJECT" -o json | json_field .info.status)" "helm status $RELEASE"
for deployment in lgtm keycloak quarkus python quarkus-internal python-internal edge; do
  ocn rollout status "deploy/$deployment" --timeout=60s >/dev/null
  echo "lib.sh: ok — deploy/$deployment is rolled out" >&2
done
# The router terminates TLS with the ingress certificate; its CA is a ConfigMap.
ocx -n openshift-config-managed get configmap default-ingress-cert -o jsonpath='{.data.ca-bundle\.crt}' >"$SCRATCH/ingress-ca.crt"
export LGTM_CACERT="$SCRATCH/ingress-ca.crt"

# The restricted-v2 SCC admits every pod except the observability pod, which is admitted by anyuid.
for deployment in quarkus python quarkus-internal python-internal edge keycloak; do
  scc="$(ocn get pods -l "app.kubernetes.io/name=$deployment" -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}')"
  assert_eq "restricted-v2" "$scc" "$deployment runs under restricted-v2"
done
scc="$(ocn get pods -l app.kubernetes.io/name=lgtm -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}')"
assert_eq "anyuid" "$scc" "lgtm runs under anyuid"

QUARKUS_URL="$(route_url quarkus https)/graphql"
PYTHON_URL="$(route_url python https)/graphql"
QUARKUS_INTERNAL="$(route_url quarkus-internal https)/graphql"
PYTHON_INTERNAL="$(route_url python-internal https)/graphql"
KEYCLOAK_URL="$(route_url keycloak https)"
out="$(http_any GET "http://${KEYCLOAK_URL#https://}/realms/shipping" --max-redirs 0)"
assert_status_in "301 302 308" "$(status_of "$out")" "keycloak: a plain HTTP request is redirected to HTTPS"

echo
echo "=== tokens from Keycloak at its Route, the issuer the stacks pin ==="
wait_for_http "$KEYCLOAK_URL/realms/shipping" 120
TOKEN_URL="$KEYCLOAK_URL/realms/shipping/protocol/openid-connect/token"
ANA="$(oidc_token "$TOKEN_URL" tracking-cli ana ana-fixture-pw)"
OPS="$(oidc_token "$TOKEN_URL" tracking-cli ops ops-fixture-pw)"

# run_stack_check <stack> <route-url> <internal-route-url>
run_stack_check() {
  local stack="$1" pub="$2" int="$3"
  local resp out total op trace_id tp pods
  case "$stack" in
    quarkus) total=8; op='^query ListCargos$' ;;
    python) total=6; op='^GraphQL Query: ListCargos$' ;;
  esac

  echo
  echo "=== verifying stack '$stack' through the Route at $pub ==="
  wait_for_graphql "$pub"
  wait_for_graphql "$int"

  # Edge TLS at the router: a plain HTTP request is redirected to HTTPS.
  out="$(http_any GET "http://${pub#https://}" --max-redirs 0)"
  assert_status_in "301 302 308" "$(status_of "$out")" "$stack: a plain HTTP request is redirected to HTTPS"

  # The internal instance serves the whole canonical schema; the public one refuses introspection.
  assert_sdl_equals "$int" "$stack internal schema equals the canonical SDL"
  resp="$(as "$OPS" "$pub" '{ __schema { queryType { name } } }')"
  assert_has_errors "$resp" "$stack public __schema is refused, even for an operator"
  assert_no_data "$resp" "$stack public __schema returns no data"

  # The edge behind the router: body limit, routing.
  source_calls_reset_pod "$stack"
  out="$(http_any POST "$pub" -H 'Content-Type: application/json' --http1.1 -d "@$SCRATCH/comment.json")"
  assert_eq "413" "$(status_of "$out")" "$stack: a 100 KB body is refused at the edge"
  assert_source_call_count "$(source_calls_pod "$stack")" '*' '*' 0 "$stack: the refused body never reached the pod"
  out="$(http_any GET "${pub%/graphql}/debug/source-calls")"
  assert_eq "404" "$(status_of "$out")" "$stack: /debug/source-calls is not routed"
  out="$(http_any GET "${pub%/graphql}/events/cargos/ABC123")"
  assert_eq "401" "$(status_of "$out")" "$stack: the event feed is routed and refuses an anonymous caller"

  # Identity: an anonymous query is refused, a shipper sees her own cargos.
  resp="$(gql "$pub" '{ cargo(trackingId: "ABC123") { trackingId } }')"
  assert_error_extension "$resp" '["cargo"]' code '"UNAUTHENTICATED"' "$stack anonymous cargo: code"
  resp="$(as "$ANA" "$pub" '{ cargos(first: 10) { edges { node { trackingId } } totalCount } }')"
  assert_no_errors "$resp" "$stack ana cargos"
  assert_json_eq '["VWX901","DEF456","ABC123"]' "$(tracking_ids <<<"$resp")" "$stack ana sees her three cargos"

  # An over-budget document is refused before any source is asked; FanOut makes the batched calls.
  source_calls_reset_pod "$stack"
  resp="$(gql "$pub" "$Q_OVER")"
  assert_no_data "$resp" "$stack OverBudget: no data"
  assert_eq "maximum query complexity exceeded 7651 > 1000" "$(json_field '.errors.0.message' <<<"$resp")" "$stack OverBudget: message"
  assert_source_call_count "$(source_calls_pod "$stack")" '*' '*' 0 "$stack OverBudget: refused before any source call"
  source_calls_reset_pod "$stack"
  resp="$(as "$OPS" "$pub" "$Q_FAN")"
  assert_no_errors "$resp" "$stack FanOut as ops"
  assert_source_call_count "$(source_calls_pod "$stack")" '*' '*' "$total" "$stack FanOut: $total source calls, read inside the pod"

  # The trace of a request carries the id the client chose and names the pod.
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(LGTM_BEARER="$OPS" LGTM_TRACEPARENT="$tp" gql "$pub" "$Q_LIST" '{}' ListCargos)"
  assert_error_extension "$resp" '["cargos","edges",5,"node"]' traceId "\"$trace_id\"" "$stack: extensions.traceId equals the id sent through the Route"
  trace_in_tempo "$trace_id" || fail "$stack: Tempo does not hold trace $trace_id"
  echo "lib.sh: ok — $stack: Tempo holds trace $trace_id ($op)" >&2
  pods="$(trace_pod_names)"
  assert_contains "$pods" "$(ocn get pods -l "app.kubernetes.io/name=$stack" -o jsonpath='{.items[0].metadata.name}')" "$stack: k8s.pod.name is the public instance's pod"
}

run_stack_check quarkus "$QUARKUS_URL" "$QUARKUS_INTERNAL"
run_stack_check python "$PYTHON_URL" "$PYTHON_INTERNAL"

echo
echo "PASS - Appendix A Chapter 27 on OpenShift Local: the release is deployed under restricted-v2 with the observability" \
     "pod under anyuid; Routes terminate TLS with the ingress certificate and redirect HTTP; Keycloak tokens fetched at its" \
     "Route are accepted by both stacks; the edge refuses a 100 KB body and routes only /graphql and /events/; an anonymous" \
     "query is refused and a shipper sees her cargos; the internal instances equal the canonical SDL while the public" \
     "instances refuse introspection; an over-budget document is refused before any source call; and a trace id sent through" \
     "the Route is found in the error and in Tempo, and names the pod."
