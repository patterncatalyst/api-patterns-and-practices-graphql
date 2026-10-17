#!/usr/bin/env bash
# shellcheck disable=SC2034  # the names below are read by the scripts that source this file
# examples/26-minikube/scripts/lib.sh - sourced by the other scripts.
#
# Names the profile, the release and the namespace, wraps kubectl and helm so
# that every call names its cluster (the current context is never read or
# changed), and holds the preflight checks. Nothing here starts or stops a
# cluster.

PROFILE="${GQL_PROFILE:-gql-tracking}"
RELEASE="gql-ch26"
NAMESPACE="gql-ch26"
K8S_VERSION="v1.37.1"
MINIKUBE_MIN="v1.39.0"
HELM_MIN="v4.3.1"

# Published NodePorts on 127.0.0.1: Chapter 26 (30360-30365), then Chapter 27
# (30370-30378). The profile is created once with all fifteen, because the list
# is fixed at creation and Chapter 27 reuses the same profile.
CH26_PORTS=(30360 30361 30362 30363 30364 30365)
CH27_PORTS=(30370 30371 30372 30373 30374 30375 30376 30377 30378)
NODE_PORTS=("${CH26_PORTS[@]}" "${CH27_PORTS[@]}")

EDGE_QUARKUS_PORT=30360
EDGE_PYTHON_PORT=30361
TEMPO_PORT=30363
LOKI_PORT=30365

step() { printf '\n==> %s\n' "$*"; }
ok() { printf '    ok - %s\n' "$*"; }
fail() {
  printf 'FAIL - %s\n' "$*" >&2
  exit 1
}

# kc <kubectl args...> - kubectl against the profile.
kc() { kubectl --context "$PROFILE" "$@"; }

# hc <helm args...> - helm against the profile.
hc() { helm --kube-context "$PROFILE" "$@"; }

# version_ge <have> <floor> - true when have >= floor (both vX.Y.Z).
version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

require_tools() {
  local tool
  for tool in docker minikube kubectl helm python3 curl ss; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on the PATH"
  done
  version_ge "$(minikube version --short)" "$MINIKUBE_MIN" \
    || fail "minikube $(minikube version --short) is older than $MINIKUBE_MIN"
  version_ge "$(helm version --short | cut -d+ -f1)" "$HELM_MIN" \
    || fail "helm $(helm version --short) is older than $HELM_MIN"
}

# require_docker_engine - minikube's docker driver follows the active docker
# context: it must be Docker Engine on its default socket.
require_docker_engine() {
  local context endpoint
  if command -v rpm >/dev/null 2>&1 && rpm -q podman-docker >/dev/null 2>&1; then
    fail "podman-docker is installed and shadows the docker CLI (sudo dnf remove podman-docker)"
  fi
  [[ -z "${DOCKER_HOST:-}" || "$DOCKER_HOST" == "unix:///var/run/docker.sock" ]] \
    || fail "DOCKER_HOST is '$DOCKER_HOST'; unset it or point it at unix:///var/run/docker.sock"
  context="$(docker context show 2>/dev/null || true)"
  [[ "$context" == "default" ]] \
    || fail "the docker context is '${context:-unknown}', expected 'default' (docker context use default)"
  endpoint="$(docker context inspect default --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  [[ "$endpoint" == "unix:///var/run/docker.sock" ]] \
    || fail "docker context 'default' points at '${endpoint:-unknown}', expected unix:///var/run/docker.sock"
  docker info >/dev/null 2>&1 || fail "the Docker daemon on /var/run/docker.sock does not answer"
  ok "Docker Engine reachable (context default)"
}

# require_no_crc - OpenShift Local and minikube do not run side by side.
require_no_crc() {
  command -v crc >/dev/null 2>&1 || return 0
  if crc status 2>/dev/null | grep -qE '^(CRC VM|OpenShift):[[:space:]]+Running'; then
    fail "OpenShift Local (crc) is running; stop it with 'crc stop' first"
  fi
  ok "OpenShift Local is not running"
}

# running_profiles - the names of the minikube profiles that are running,
# except this one.
running_profiles() {
  minikube profile list -o json 2>/dev/null | python3 -I -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    data = {}
for p in data.get("valid") or []:
    if p.get("Name") != sys.argv[1] and p.get("Status") in ("OK", "Running"):
        print(p["Name"])
' "$PROFILE" || true
}

# require_no_other_profile - the check names each running profile and the
# command that stops it; it never stops one.
require_no_other_profile() {
  local others name
  others="$(running_profiles)"
  if [[ -n "$others" ]]; then
    while IFS= read -r name; do
      printf '    running: %s - stop it with: minikube stop -p %s\n' "$name" "$name" >&2
    done <<<"$others"
    fail "another minikube profile is running"
  fi
  ok "no other minikube profile is running"
}

# profile_status - Running, Stopped or empty when the profile does not exist.
# (minikube reports a running profile as OK.)
profile_status() {
  minikube profile list -o json 2>/dev/null | python3 -I -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    data = {}
for p in data.get("valid") or []:
    if p.get("Name") == sys.argv[1]:
        status = p.get("Status", "")
        print("Running" if status in ("OK", "Running") else status)
' "$PROFILE" || true
}

# profile_field <driver|runtime> - that field of this profile's configuration.
profile_field() {
  minikube profile list -o json 2>/dev/null | python3 -I -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    data = {}
for p in data.get("valid") or []:
    if p.get("Name") == sys.argv[1]:
        cfg = p.get("Config") or {}
        print({"driver": cfg.get("Driver", ""),
               "runtime": (cfg.get("KubernetesConfig") or {}).get("ContainerRuntime", "")}[sys.argv[2]])
' "$PROFILE" "$1" || true
}

preflight() {
  require_tools
  require_docker_engine
  require_no_crc
  require_no_other_profile
}

# repo_root - the root of the repository that holds this example.
repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd
}

EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="$EXAMPLE_DIR/helm"
