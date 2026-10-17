#!/usr/bin/env bash
# examples/25-docker-compose/verify.sh
#
# Ch25 Local with Docker Compose: the tracking view as one local tier. An nginx
# edge (TLS 1.3, a 64k body limit, only /graphql routed) stands in front of both
# stacks, which sit alone on an internal network beside the observability
# backend. The cases below check the tier itself (start order, published ports,
# configs and secrets, limits, restart and shutdown settings) and follow one
# request from the edge to its trace and its log record.
#
# The certificates are generated into a scratch directory at run time
# (gen-certs.sh) and are never committed. LGTM_CACERT makes every harness call
# trust that CA.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch25-compose"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
TEMPO="http://localhost:8353"
LOKI="http://localhost:8355"

SCRATCH="$(mktemp -d)"
on_exit "rm -rf '$SCRATCH'"
"$SCRIPT_DIR/gen-certs.sh" "$SCRATCH/certs"
export CERT_DIR="$SCRATCH/certs"
export LGTM_CACERT="$CERT_DIR/ca.crt"

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

# compose <args...> - docker compose against this example's project.
compose() {
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" "$@"
}

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

# fan_shape - the data of Q_FAN in $resp reduced to what the cases compare.
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

# --- tier-level cases -----------------------------------------------------------

# check_tier - the services, the networks and the published ports.
check_tier() {
  local states ports svc raw
  echo
  echo "=== the tier: start order, networks, published ports ==="
  compose config --quiet || { echo "FAIL - docker compose config" >&2; return 1; }
  echo "lib.sh: ok — docker compose config is valid" >&2

  states="$(compose ps --format json | python3 -I -c '
import json, sys
rows = [json.loads(line) for line in sys.stdin if line.strip()]
print(",".join(sorted("%s=%s" % (r["Service"], r.get("Health") or r["State"]) for r in rows)))
')"
  assert_eq "edge=healthy,lgtm=healthy,python=healthy,quarkus=healthy" "$states" "every service is healthy"

  for svc in quarkus python; do
    raw="$(compose port "$svc" 8080 2>/dev/null || true)"
    [[ -z "$raw" || "$raw" == ":0" ]] || { echo "FAIL - docker compose port reports a host binding for $svc: $raw" >&2; return 1; }
    echo "lib.sh: ok — docker compose port reports no host binding for $svc" >&2
    ports="$(compose_inspect "$svc" '{{json .HostConfig.PortBindings}}')"
    [[ "$ports" == "{}" || "$ports" == "null" ]] || { echo "FAIL - $svc declares a published port: $ports" >&2; return 1; }
    echo "lib.sh: ok — $svc declares no published port" >&2
    ports="$(compose_inspect "$svc" '{{json .NetworkSettings.Ports}}')"
    python3 -I -c '
import json, sys
ports = json.loads(sys.argv[1])
assert all(v is None for v in ports.values()), ports
' "$ports" || { echo "FAIL - $svc has a host binding: $ports" >&2; return 1; }
    echo "lib.sh: ok — $svc has no host binding" >&2
    # shellcheck disable=SC2016  # a Go template, not a shell expansion
    assert_eq "backend" "$(compose_inspect "$svc" '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{end}}' | sed "s/^${PROJECT}_//")" "$svc joins only the backend network"
  done

  assert_eq "true" "$(docker network inspect "${PROJECT}_backend" -f '{{.Internal}}')" "the backend network is internal"
  assert_eq "false" "$(docker network inspect "${PROJECT}_public" -f '{{.Internal}}')" "the public network is not internal"

  ports="$(compose_inspect lgtm '{{json .HostConfig.PortBindings}}')"
  python3 -I -c '
import json, sys
bindings = json.loads(sys.argv[1])
hosts = sorted((b["HostIp"], b["HostPort"]) for v in bindings.values() for b in v)
assert hosts == [("127.0.0.1", p) for p in ("8352", "8353", "8354", "8355")], hosts
' "$ports" || { echo "FAIL - lgtm ports: $ports" >&2; return 1; }
  echo "lib.sh: ok — Grafana, Tempo, Prometheus and Loki publish on 127.0.0.1 only" >&2
  ports="$(compose_inspect edge '{{json .HostConfig.PortBindings}}')"
  python3 -I -c '
import json, sys
bindings = json.loads(sys.argv[1])
hosts = sorted((k, b["HostPort"]) for k, v in bindings.items() for b in v)
assert hosts == [("8443/tcp", "8350"), ("8444/tcp", "8351")], hosts
' "$ports" || { echo "FAIL - edge ports: $ports" >&2; return 1; }
  echo "lib.sh: ok — the edge publishes 8350 and 8351 and nothing else" >&2
}

# check_secrets - the key is a file in the edge, in no environment and in no image.
check_secrets() {
  local env_json inspect_json body_line image
  echo
  echo "=== configs and secrets ==="
  compose exec -T edge test -r /run/secrets/edge_tls_key || { echo "FAIL - the edge cannot read its key" >&2; return 1; }
  echo "lib.sh: ok — /run/secrets/edge_tls_key is a readable file in the edge" >&2
  compose exec -T edge test -r /etc/nginx/nginx.conf || { echo "FAIL - the edge config is missing" >&2; return 1; }
  echo "lib.sh: ok — /etc/nginx/nginx.conf is the compose config" >&2

  body_line="$(sed -n 2p "$CERT_DIR/edge.key")"
  env_json="$(compose_inspect edge '{{json .Config.Env}}')"
  assert_body_not_contains "$env_json" "BEGIN" "the edge environment holds no PEM block"
  assert_body_not_contains "$env_json" "$body_line" "the edge environment holds no key material"
  inspect_json="$(docker inspect "ch25-compose-edge")"
  assert_body_not_contains "$inspect_json" "$body_line" "docker inspect of the edge holds no key material"
  for image in gql-ch25-quarkus:1.0 gql-ch25-python:1.0 registry.access.redhat.com/ubi10/nginx-126:10.2-1791973310; do
    inspect_json="$(docker image inspect "$image")"
    assert_body_not_contains "$inspect_json" "BEGIN" "$image holds no PEM block in its metadata"
    assert_body_not_contains "$inspect_json" "$body_line" "$image holds no key material in its metadata"
    assert_body_not_contains "$(docker history --no-trunc "$image")" "edge.key" "$image has no layer that touches the key"
  done
}

# check_limits - limits, restart policy, log driver and stop timeout, read back.
check_limits() {
  echo
  echo "=== limits, restart policy, logging, stop timeout ==="
  local svc mem cpus
  for svc in quarkus python edge; do
    case "$svc" in
      quarkus) mem=805306368; cpus=1000000000 ;;
      python) mem=402653184; cpus=500000000 ;;
      edge) mem=67108864; cpus=250000000 ;;
    esac
    assert_eq "$mem" "$(compose_inspect "$svc" '{{.HostConfig.Memory}}')" "$svc memory limit"
    assert_eq "$cpus" "$(compose_inspect "$svc" '{{.HostConfig.NanoCpus}}')" "$svc cpu limit"
    assert_eq "unless-stopped" "$(compose_inspect "$svc" '{{.HostConfig.RestartPolicy.Name}}')" "$svc restart policy"
    assert_eq "local" "$(compose_inspect "$svc" '{{.HostConfig.LogConfig.Type}}')" "$svc log driver"
    assert_eq "10m/3" "$(compose_inspect "$svc" '{{index .HostConfig.LogConfig.Config "max-size"}}/{{index .HostConfig.LogConfig.Config "max-file"}}')" "$svc log rotation"
    assert_eq "15" "$(compose_inspect "$svc" '{{.Config.StopTimeout}}')" "$svc stop timeout"
  done
}

# --- per-stack cases ------------------------------------------------------------

# run_stack_check <stack> <url>
run_stack_check() {
  local stack="$1" url="$2"
  local service="ch25-compose-$stack" port out resp calls trace_id tp trace op total
  local ghi_edges ghi_errors

  echo
  echo "=== verifying stack '$stack' through the edge at $url ==="

  case "$stack" in
    quarkus)
      op="^query ListCargos\$"; total=8; port=8350
      ;;
    python)
      op="^GraphQL Query: ListCargos\$"; total=6; port=8351
      ;;
  esac

  wait_for_graphql "$url"

  # 1. Chapter 19's answers, through the edge.
  resp="$(gql "$url" "$HEALTHY" '{"id":"ABC123"}' TrackCargo)"
  assert_no_errors "$resp" "$stack TrackCargo"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "TrackCargo transportStatus"
  source_calls_reset_in "$stack"
  resp="$(gql "$url" "$Q_FAN" '{}' FanOut)"
  assert_no_errors "$resp" "$stack FanOut"
  assert_json_eq '[["VWX901",[["V300A","SGSIN","CNSHA"]]],["XYZ789",null],["STU678",[["V300A","SGSIN","CNSHA"]]],["DEF456",[["V100S","USNYC","DEHAM"],["V200E","DEHAM","NLRTM"]]]]' \
    "$(fan_shape)" "$stack FanOut returns Chapter 13's data"
  calls="$(source_calls_in "$stack")"
  assert_source_call_count "$calls" '*' '*' "$total" "$stack FanOut: $total source calls, read inside the container"

  resp="$(gql "$url" "$Q_LIST" '{}' ListCargos)"
  expect "6" '.data.cargos.totalCount' "the booking index holds six cargos"
  assert_eq "6" "$(json_len '.data.cargos.edges' <<<"$resp")" "$stack ListCargos: six edges"
  assert_error_extension "$resp" '["cargos","edges",5,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack ListCargos: GHI345's edge carries SERVICE_UNAVAILABLE"
  assert_error_message_at "$resp" '["cargos","edges",5,"node"]' "booking service unavailable" "$stack ListCargos: the exposed message"
  case "$stack" in
    quarkus) ghi_errors=6; ghi_edges="the whole batch" ;;
    python) ghi_errors=1; ghi_edges="one edge" ;;
  esac
  assert_error_count "$resp" "$ghi_errors" "$stack ListCargos: $ghi_errors errors ($ghi_edges)"

  # 2. The edge routes only /graphql.
  resp="$(http_any GET "https://localhost:$port/debug/source-calls")"
  assert_eq "404" "$(status_of "$resp")" "$stack: /debug/source-calls is not routed"
  resp="$(http_any GET "https://localhost:$port/q/health/ready")"
  assert_eq "404" "$(status_of "$resp")" "$stack: /q/health/ready is not routed"
  resp="$(http_any GET "https://localhost:$port/health/ready")"
  assert_eq "404" "$(status_of "$resp")" "$stack: /health/ready is not routed"
  resp="$(http_any GET "https://localhost:$port/")"
  assert_eq "404" "$(status_of "$resp")" "$stack: / is not routed"

  # 3. TLS at the edge.
  LGTM_CACERT='' assert_transport_fails "$stack: without the CA the certificate is untrusted" \
    -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "https://localhost:$port/graphql"
  assert_transport_fails "$stack: a TLS 1.2 client is refused" --tlsv1.2 --tls-max 1.2 \
    -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "https://localhost:$port/graphql"
  out="$(json_post "https://localhost:$port/graphql" '{"query":"{ __typename }"}' --tlsv1.3)"
  assert_eq "200" "$(status_of "$out")" "$stack: a TLS 1.3 client is served"
  out="$(json_post "http://localhost:$port/graphql" '{"query":"{ __typename }"}')"
  assert_eq "400" "$(status_of "$out")" "$stack: plain HTTP on the TLS listener is answered 400"

  # 4. The body limit, ahead of the backend (Chapter 17's fronting proxy).
  source_calls_reset_in "$stack"
  out="$(http_any POST "$url" -H 'Content-Type: application/json' --http1.1 -d "@$SCRATCH/comment.json")"
  assert_eq "413" "$(status_of "$out")" "$stack: a 100 KB body is refused at the edge"
  assert_source_call_count "$(source_calls_in "$stack")" '*' '*' 0 "$stack: the refused body never reached the backend"

  # 5. The health split, inside the network.
  case "$stack" in
    quarkus)
      for path in started ready live; do
        out="$(compose_exec_http quarkus GET "/q/health/$path")"
        assert_eq "200" "$(status_of "$out")" "$stack /q/health/$path"
        assert_contains '"status": "UP"' "$(body_of "$out")" "$stack /q/health/$path is UP"
      done
      ;;
    python)
      for path in live ready; do
        out="$(compose_exec_http python GET "/health/$path")"
        assert_eq "200" "$(status_of "$out")" "$stack /health/$path"
        assert_contains '"status":"UP"' "$(body_of "$out")" "$stack /health/$path is UP"
      done
      ;;
  esac

  # 6. The diagnosis path: the caller's trace id through the edge, to Tempo and Loki.
  trace_id="$(new_trace_id)"
  tp="$(traceparent_for "$trace_id")"
  resp="$(LGTM_TRACEPARENT="$tp" gql "$url" "$Q_LIST" '{}' ListCargos)"
  assert_error_extension "$resp" '["cargos","edges",5,"node"]' traceId "\"$trace_id\"" "$stack ListCargos: extensions.traceId equals the id the client sent through the edge"
  trace="$(tempo_trace "$TEMPO" "$trace_id" 90 "$total")"
  assert_span "$trace" "$op" 1 1 "$stack ListCargos: Tempo holds the operation span for that id"
  assert_span "$trace" '^source\.call$' 1 "" "$stack ListCargos: and the source.call spans"
  loki_wait "$LOKI" "{service_name=\"$service\"} | trace_id=\"$trace_id\"" 90 1 >/dev/null
  echo "lib.sh: ok — $stack: Loki holds a record for trace $trace_id" >&2

  # 7. The contract, as in Chapter 19.
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

  echo "=== $stack: tier check passed ==="
}

# check_restart - a process that exits is started again by the restart policy.
check_restart() {
  local before state
  echo
  echo "=== restart policy: python exits and comes back without a compose up ==="
  before="$(compose_inspect python '{{.RestartCount}}')"
  compose exec -T python sh -c 'kill -TERM 1'
  for _ in $(seq 1 45); do
    state="$(compose_inspect python '{{.RestartCount}} {{.State.Health.Status}}' 2>/dev/null || true)"
    if [[ "$state" == "$((before + 1)) healthy" ]]; then
      break
    fi
    sleep 2
  done
  assert_eq "$((before + 1)) healthy" "$state" "python was restarted by the engine and is healthy again"
  wait_for_graphql "https://localhost:8351/graphql"
  echo "lib.sh: ok — python answers through the edge after the restart" >&2
}

# check_graceful_stop - a request in flight when quarkus is stopped completes.
check_graceful_stop() {
  local url="https://localhost:8350/graphql" pid count code started finished resp
  echo
  echo "=== graceful stop: a FanOut in flight completes while quarkus stops ==="
  source_calls_reset_in quarkus
  ( set +e; gql "$url" "$Q_FAN" '{}' FanOut >"$SCRATCH/fan.json" 2>"$SCRATCH/fan.err"; echo "$?" >"$SCRATCH/fan.rc" ) &
  pid=$!
  for _ in $(seq 1 100); do
    count="$(source_calls_in quarkus | json_len '.calls')"
    [[ "$count" -ge 1 ]] && break
    sleep 0.1
  done
  [[ "$count" -ge 1 ]] || { echo "FAIL - the FanOut never reached quarkus" >&2; return 1; }
  [[ ! -e "$SCRATCH/fan.rc" ]] || { echo "FAIL - the FanOut finished before the stop began" >&2; return 1; }
  started="$(date +%s)"
  compose stop quarkus >/dev/null 2>&1
  finished="$(date +%s)"
  wait "$pid" || true
  assert_eq "0" "$(cat "$SCRATCH/fan.rc")" "the request in flight when the stop began completed"
  resp="$(cat "$SCRATCH/fan.json")"
  assert_no_errors "$resp" "quarkus FanOut in flight during the stop"
  assert_contains "Waiting for HTTP requests to complete" "$(docker logs ch25-compose-quarkus 2>&1)" "quarkus waited for the request in flight before it exited"
  assert_eq "4" "$(json_len '.data.cargos.edges' <<<"$resp")" "the in-flight FanOut returned all four cargos"
  code="$(docker inspect -f '{{.State.ExitCode}}' ch25-compose-quarkus)"
  if [[ "$code" != "0" && "$code" != "143" ]]; then
    echo "FAIL - quarkus exited with code $code" >&2
    return 1
  fi
  echo "lib.sh: ok — quarkus exited with code $code" >&2
  if (( finished - started > 15 )); then
    echo "FAIL - the stop took $((finished - started)) s, over the 15 s grace period" >&2
    return 1
  fi
  echo "lib.sh: ok — the stop took $((finished - started)) s, inside the 15 s grace period" >&2
  compose up -d --wait quarkus >/dev/null 2>&1
  wait_for_graphql "$url"
}

# check_edge_log - the refused bodies are in the edge log with no upstream.
check_edge_log() {
  local logs
  logs="$(compose_logs edge)"
  assert_eq "2" "$(grep -c '" 413 .* upstream=-' <<<"$logs" || true)" "the edge log records both refused bodies with no upstream"
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"
# `up -d` returns once the edge has started; --wait returns once every service is healthy.
compose up -d --wait

check_tier
check_secrets
check_limits

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "https://localhost:8350/graphql"
run_stack_check "python" "https://localhost:8351/graphql"
check_edge_log
check_restart
check_graceful_stop

echo
echo "PASS - Ch25 Local with Docker Compose: both stacks start by health behind an nginx edge that terminates" \
     "TLS 1.3, refuses a 100 KB body with 413 and routes only /graphql; the backends publish nothing and sit on" \
     "an internal network; the key is a mounted secret and the config a mounted config; limits, restart policy," \
     "log rotation and stop timeout read back as configured; a restarted process returns, a request in flight" \
     "survives a stop, and a trace id sent through the edge is found in the error, in Tempo and in Loki."
