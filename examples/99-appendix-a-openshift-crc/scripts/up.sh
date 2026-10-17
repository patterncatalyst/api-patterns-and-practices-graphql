#!/usr/bin/env bash
# examples/99-appendix-a-openshift-crc/scripts/up.sh
#
# 1. Inventory (read-only): what the cluster holds before this run.
# 2. The project, then the release with the build objects only.
# 3. One in-cluster build per stack, from the Containerfile in Chapter 27's directory.
# 4. The release again, with the application, and a rollout check per Deployment.
# 5. helm test.
# Run it after `crc start` and `eval "$(crc oc-env)"`.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_crc

step "inventory before this run (read-only)"
mkdir -p "$STATE_DIR"
if [[ ! -f "$INVENTORY" ]] || ! ocx get project "$PROJECT" >/dev/null 2>&1; then
  {
    echo "## namespaces"
    namespaces_now
    echo "## operators"
    operators_now
    echo "## crds"
    crds_now
  } >"$INVENTORY"
  ok "saved $INVENTORY"
else
  ok "the project exists; keeping the inventory taken before its first run"
fi
foreign="$(awk '/^## namespaces/{n=1;next} /^##/{n=0} n && $0 != "'"$PROJECT"'"' "$INVENTORY")"
if [[ -n "$foreign" ]]; then
  warn "namespaces other than this appendix's are present and stay untouched:"
  while IFS= read -r ns; do printf '      %s\n' "$ns" >&2; done <<<"$foreign"
fi
while IFS= read -r line; do
  [[ -z "$line" || "$line" == "ClusterServiceVersion openshift-operator-lifecycle-manager packageserver" ]] || warn "operator object present and left untouched: $line"
done < <(awk '/^## operators/{n=1;next} /^##/{n=0} n' "$INVENTORY" | tr -s ' ')

DOMAIN="$(ingress_domain)"
[[ -n "$DOMAIN" ]] || fail "the cluster reports no ingress domain"
ISSUER="https://keycloak-$PROJECT.$DOMAIN/realms/shipping"

# deploy <helm args...> - the release, with the values that depend on this cluster.
deploy() {
  hc upgrade --install "$RELEASE" "$CHART_DIR" --namespace "$PROJECT" \
    --set "openshift.domain=$DOMAIN" \
    --set "final.identity.issuer=$ISSUER" \
    --timeout 10m "$@"
}

step "helm dependency build"
hc dependency build "$CHART_DIR" >/dev/null
ok "charts/ holds the Chapter 27 chart"

step "project $PROJECT"
if ocx get project "$PROJECT" >/dev/null 2>&1; then
  ok "project $PROJECT exists"
else
  # --skip-config-write leaves the kubeconfig's current namespace alone.
  ocx new-project "$PROJECT" --skip-config-write >/dev/null
  ok "project $PROJECT created"
fi

step "helm upgrade --install $RELEASE (build objects and Routes)"
deploy --set tags.app=false
ok "BuildConfigs and ImageStreams exist"

step "in-cluster builds"
# The Containerfiles are Chapter 27's, uploaded as they are.
for stack in "${STACKS[@]}"; do
  ocn start-build "$(image_name "$stack")" --from-dir "$CH27_DIR/$stack" --follow --wait
  ocn get imagestreamtag "$(image_name "$stack"):$IMAGE_TAG" >/dev/null
  ok "$(image_name "$stack"):$IMAGE_TAG is in the image stream"
done

step "helm upgrade --install $RELEASE (the application)"
deploy --wait
for deployment in lgtm keycloak quarkus python quarkus-internal python-internal edge; do
  ocn rollout status "deploy/$deployment" --timeout=5m
done

step "scc of each pod"
ocn get pods -o custom-columns='POD:.metadata.name,SCC:.metadata.annotations.openshift\.io/scc'

step "helm test $RELEASE"
hc test "$RELEASE" --namespace "$PROJECT" --logs --timeout 5m

step "up: $RELEASE is deployed and tested; run scripts/smoke.sh"
