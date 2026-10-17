#!/usr/bin/env bash
# shellcheck disable=SC2034  # the names below are read by the scripts that source this file
# examples/99-appendix-a-openshift-crc/scripts/lib.sh - sourced by the other scripts.
#
# Names the project, the release and the cluster context, wraps oc and helm so
# that every call names its cluster (the current context is never read or
# changed), and holds the preflight check. Nothing here starts a cluster: the
# user runs `crc start`. The kubeconfig context `crc-admin` is written by
# `crc start`; no password is typed, read or printed.

PROJECT="gql-appendix-a"
RELEASE="gql-appendix-a"
OCP_CONTEXT="${OCP_CONTEXT:-crc-admin}"

EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="$EXAMPLE_DIR/helm"
CH27_DIR="$(cd "$EXAMPLE_DIR/../27-final-project" && pwd)"

# The stacks built in the cluster: directory under Chapter 27, image stream, tag.
STACKS=(quarkus python)
IMAGE_TAG="1.0"
image_name() { printf 'gql-ch27-%s' "$1"; }

# What up.sh saw before it created anything, so down.sh can compare.
STATE_DIR="${GQL_APPENDIX_A_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/gql-appendix-a}"
INVENTORY="$STATE_DIR/inventory.txt"

step() { printf '\n==> %s\n' "$*"; }
ok() { printf '    ok - %s\n' "$*"; }
warn() { printf '    note - %s\n' "$*" >&2; }
fail() {
  printf 'FAIL - %s\n' "$*" >&2
  exit 1
}

# ocx <oc args...> - oc against OpenShift Local.
ocx() { oc --context "$OCP_CONTEXT" "$@"; }

# ocn <oc args...> - oc in the project.
ocn() { ocx -n "$PROJECT" "$@"; }

# hc <helm args...> - helm against OpenShift Local.
hc() { helm --kube-context "$OCP_CONTEXT" "$@"; }

# wait_for <seconds> <description> <command...> - poll every 5 s until the command succeeds.
wait_for() {
  local timeout="$1" what="$2" waited=0
  shift 2
  until "$@" >/dev/null 2>&1; do
    ((waited >= timeout)) && fail "timed out after ${timeout}s waiting for $what"
    sleep 5
    waited=$((waited + 5))
  done
  ok "$what"
}

# gone <oc get args...> - true once the object no longer exists.
gone() { ! ocx get "$@" >/dev/null 2>&1; }

# require_no_minikube - OpenShift Local and a running minikube profile do not
# share the host; the check names each running profile and never stops one.
require_no_minikube() {
  command -v minikube >/dev/null 2>&1 || return 0
  local running
  running="$(minikube profile list -o json 2>/dev/null | python3 -I -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    data = {}
for p in data.get("valid") or []:
    if p.get("Status") in ("OK", "Running"):
        print(p["Name"])
' || true)"
  if [[ -n "$running" ]]; then
    while IFS= read -r name; do
      printf '    running: %s - stop it with: minikube stop -p %s\n' "$name" "$name" >&2
    done <<<"$running"
    fail "a minikube profile is running; run one cluster at a time"
  fi
  ok "no minikube profile is running"
}

# crc_running - true when the OpenShift Local VM and cluster are up.
crc_running() {
  crc status 2>/dev/null | grep -qE '^OpenShift:[[:space:]]+Running'
}

# require_crc - the tools are on the PATH, OpenShift Local is running, and the
# crc-admin context points at its API server.
require_crc() {
  local tool api
  for tool in oc crc helm python3 curl; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on the PATH (eval \"\$(crc oc-env)\" puts oc there)"
  done
  require_no_minikube
  crc_running || fail "OpenShift Local is not running; start it with: crc start"
  api="$(ocx whoami --show-server 2>/dev/null)" || fail "cannot reach the API server through context $OCP_CONTEXT"
  ocx get --raw /readyz >/dev/null 2>&1 || fail "the API server behind context $OCP_CONTEXT does not answer"
  [[ "$api" == *api.crc.testing* ]] || fail "context $OCP_CONTEXT points at $api, not at OpenShift Local"
  ok "OpenShift Local is running; context $OCP_CONTEXT"
}

# ingress_domain - the wildcard domain of the cluster's router.
ingress_domain() {
  ocx get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'
}

# route_url <route> <scheme> - the URL a Route is served at.
route_url() {
  printf '%s://%s' "$2" "$(ocn get route "$1" -o jsonpath='{.spec.host}')"
}

# namespaces_now - the non-system namespaces, sorted.
namespaces_now() {
  ocx get namespaces -o name | sed 's|^namespace/||' \
    | grep -vE '^(openshift($|-)|kube-|default$|hostpath-provisioner$)' | sort || true
}

# operators_now - every Subscription and ClusterServiceVersion, sorted.
operators_now() {
  {
    ocx get subscriptions.operators.coreos.com -A --no-headers -o custom-columns='K:.kind,NS:.metadata.namespace,NAME:.metadata.name' 2>/dev/null
    ocx get clusterserviceversions.operators.coreos.com -A --no-headers -o custom-columns='K:.kind,NS:.metadata.namespace,NAME:.metadata.name' 2>/dev/null
  } | sort || true
}

# crds_now - the CustomResourceDefinitions, sorted.
crds_now() {
  ocx get crd -o name | sed 's|^customresourcedefinition.apiextensions.k8s.io/||' | sort || true
}
