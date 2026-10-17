#!/usr/bin/env bash
# examples/26-minikube/scripts/down.sh [--keep-running]
#
# helm uninstall, delete the namespace, then stop the profile. The images stay
# in the stopped node. down.sh never deletes the profile: that is
# `minikube delete -p gql-tracking`, run by hand, or `profile.sh --replace` to recreate it.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KEEP=0
[[ "${1:-}" == "--keep-running" ]] && KEEP=1

if [[ "$(profile_status)" == "Running" ]]; then
  step "helm uninstall $RELEASE"
  if hc status "$RELEASE" --namespace "$NAMESPACE" >/dev/null 2>&1; then
    hc uninstall "$RELEASE" --namespace "$NAMESPACE" --wait
  else
    ok "release $RELEASE is not installed"
  fi
  step "delete namespace $NAMESPACE"
  kc delete namespace "$NAMESPACE" --ignore-not-found --wait
else
  ok "profile $PROFILE is not running; nothing to uninstall"
fi

if ((KEEP)); then
  ok "--keep-running: profile $PROFILE left running"
else
  step "minikube stop -p $PROFILE"
  minikube stop -p "$PROFILE"
fi
minikube profile list 2>/dev/null | grep -E "Profile|$PROFILE" || true
