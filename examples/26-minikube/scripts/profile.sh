#!/usr/bin/env bash
# examples/26-minikube/scripts/profile.sh [--replace]
#
# Creates, starts or verifies the minikube profile gql-tracking: Docker Engine,
# containerd, Kubernetes v1.37.1, and the NodePorts of Chapters 26 and 27
# published on 127.0.0.1. Host access to the cluster is only through those
# NodePorts. The published list is fixed when the profile is created; a missing
# port means creating the profile again, which --replace does by deleting it
# first. Without --replace the script never deletes anything.
#
# Chapter 27 runs this script too.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CPUS="${GQL_CPUS:-6}"
MEMORY="${GQL_MEMORY:-12g}"
DISK="${GQL_DISK:-40g}"

REPLACE=0
[[ "${1:-}" == "--replace" ]] && REPLACE=1

# published_ports - the --ports value: every NodePort on loopback.
published_ports() {
  local port list=""
  for port in "${NODE_PORTS[@]}"; do
    list+="${list:+,}127.0.0.1:${port}:${port}"
  done
  printf '%s' "$list"
}

# require_published_ports - the node container publishes every NodePort on
# 127.0.0.1 and nowhere else.
require_published_ports() {
  local port published
  for port in "${NODE_PORTS[@]}"; do
    published="$(docker port "$PROFILE" "${port}/tcp" 2>/dev/null || true)"
    grep -qF "127.0.0.1:${port}" <<<"$published" \
      || fail "profile $PROFILE does not publish $port on 127.0.0.1 (docker port: ${published:-none}); the list is fixed at creation, so run profile.sh --replace"
  done
  ok "all ${#NODE_PORTS[@]} NodePorts are published on 127.0.0.1 (docker port $PROFILE)"
}

# require_free_ports - every host port is free before the profile publishes it.
require_free_ports() {
  local port owner busy=0
  for port in "${NODE_PORTS[@]}"; do
    if [[ -n "$(ss -ltnH "sport = :$port" 2>/dev/null)" ]]; then
      owner="$(ss -ltnpH "sport = :$port" 2>/dev/null | awk '{print $4, $6}' | head -n1)"
      printf '    in use: 127.0.0.1:%s (%s)\n' "$port" "$owner" >&2
      busy=1
    fi
  done
  ((busy == 0)) || fail "free the host ports above, then run profile.sh again"
  ok "host ports 30360-30365 and 30370-30378 are free"
}

preflight

step "profile $PROFILE"
status="$(profile_status)"
if [[ -n "$status" ]] && ((REPLACE)); then
  step "deleting $PROFILE (--replace)"
  minikube delete -p "$PROFILE"
  status=""
fi

if [[ -z "$status" ]]; then
  require_free_ports
  step "creating $PROFILE: Kubernetes $K8S_VERSION, ${CPUS} CPUs, ${MEMORY} memory, ${DISK} disk"
  minikube start -p "$PROFILE" \
    --driver=docker \
    --container-runtime=containerd \
    --kubernetes-version="$K8S_VERSION" \
    --cpus="$CPUS" \
    --memory="$MEMORY" \
    --disk-size="$DISK" \
    --ports="$(published_ports)" \
    --keep-context
else
  # An existing profile keeps the driver and runtime it was created with.
  driver="$(profile_field driver)"
  runtime="$(profile_field runtime)"
  if [[ "$driver" != "docker" || "$runtime" != "containerd" ]]; then
    fail "profile $PROFILE uses driver '${driver:-?}' and runtime '${runtime:-?}'; this book needs docker and containerd, fixed at creation (profile.sh --replace)"
  fi
  ok "profile $PROFILE uses the docker driver and containerd"
  if [[ "$status" != "Running" ]]; then
    step "starting the stopped profile $PROFILE"
    minikube start -p "$PROFILE" --keep-context
  else
    ok "profile $PROFILE is running"
  fi
fi

require_published_ports
kc wait --for=condition=Ready node --all --timeout=3m
kc get nodes
