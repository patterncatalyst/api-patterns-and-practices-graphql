#!/usr/bin/env bash
# examples/99-appendix-a-openshift-crc/scripts/down.sh [--keep-running]
#
# Returns OpenShift Local to the state up.sh found it in, then stops it:
#   1. helm uninstall the release;
#   2. delete the project (BuildConfigs, ImageStreams, builds, the RoleBinding and
#      every pod go with it);
#   3. remove any operator this appendix installed: Subscription, ClusterServiceVersion,
#      InstallPlans and the CRDs it owns (the appendix installs none, so the list is empty);
#   4. compare the cluster with the inventory up.sh saved and print what differs;
#   5. crc stop, unless --keep-running.
# Anything that is not this appendix's is printed and left alone.
set -uo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KEEP=0
[[ "${1:-}" == "--keep-running" ]] && KEEP=1

# Subscription namespace and name, in removal order (the reverse of install order).
OPERATORS=()

# stop_crc - the last step; a stopped cluster has nothing to clean.
stop_crc() {
  if ((KEEP)); then
    ok "--keep-running: OpenShift Local left running"
  else
    step "crc stop"
    crc stop >/dev/null 2>&1 || fail "crc stop"
    ok "OpenShift Local stopped"
  fi
}

for tool in oc crc helm python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on the PATH (eval \"\$(crc oc-env)\" puts oc there)"
done
if ! crc_running; then
  ok "OpenShift Local is not running; there is nothing to remove"
  exit 0
fi
require_crc

step "1/5 helm uninstall $RELEASE"
if hc status "$RELEASE" --namespace "$PROJECT" >/dev/null 2>&1; then
  hc uninstall "$RELEASE" --namespace "$PROJECT" --wait >/dev/null || fail "helm uninstall"
  ok "release $RELEASE uninstalled"
else
  ok "release $RELEASE is not installed"
fi

step "2/5 project $PROJECT"
if ocx get project "$PROJECT" >/dev/null 2>&1; then
  ocx delete project "$PROJECT" --wait=false >/dev/null || fail "delete project"
  wait_for 600 "project $PROJECT deleted" gone namespace "$PROJECT"
else
  ok "no project $PROJECT"
fi

step "3/5 operators installed by this appendix"
for entry in "${OPERATORS[@]}"; do
  read -r ns sub <<<"$entry"
  csv="$(ocx get subscriptions.operators.coreos.com "$sub" -n "$ns" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
  ocx delete subscriptions.operators.coreos.com "$sub" -n "$ns" --ignore-not-found >/dev/null
  [[ -z "$csv" ]] && continue
  # The CRDs the CSV owns are read before the CSV goes.
  owned="$(ocx get csv "$csv" -n "$ns" -o jsonpath='{range .spec.customresourcedefinitions.owned[*]}{.name}{"\n"}{end}' 2>/dev/null || true)"
  ocx delete csv "$csv" -n "$ns" --wait=true >/dev/null 2>&1 || true
  for plan in $(ocx get installplan -n "$ns" -o json 2>/dev/null | python3 -I -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    if sys.argv[1] in p["spec"]["clusterServiceVersionNames"]:
        print(p["metadata"]["name"])
' "$csv"); do
    ocx delete installplan "$plan" -n "$ns" >/dev/null 2>&1 || true
  done
  # shellcheck disable=SC2086  # one argument per CRD name
  [[ -n "$owned" ]] && ocx delete crd $owned --ignore-not-found --wait=true >/dev/null 2>&1
  ok "$csv removed with its CRDs"
done
((${#OPERATORS[@]})) || ok "none were installed"

step "4/5 compare with the inventory"
leftover=0
if [[ -f "$INVENTORY" ]]; then
  section() { awk -v s="## $1" '$0 == s {n=1; next} /^##/ {n=0} n' "$INVENTORY" | sort; }
  for kind in namespaces operators crds; do
    case "$kind" in
      namespaces) now="$(namespaces_now)" ;;
      operators) now="$(operators_now)" ;;
      crds) now="$(crds_now)" ;;
    esac
    extra="$(comm -13 <(section "$kind") <(sort <<<"$now") | sed '/^$/d')"
    if [[ -n "$extra" ]]; then
      leftover=1
      printf '    present now and not in the inventory (%s):\n' "$kind" >&2
      printf '      %s\n' "$extra" >&2
    fi
  done
else
  leftover=1
  warn "no inventory at $INVENTORY; listing what is present for review"
  namespaces_now >&2
  operators_now >&2
fi
if ((leftover == 0)); then
  ok "the cluster matches the inventory taken before the run"
fi

step "5/5 stop"
stop_crc
if ((leftover)); then
  fail "objects that are not in the inventory remain; they are listed above and were left alone"
fi
