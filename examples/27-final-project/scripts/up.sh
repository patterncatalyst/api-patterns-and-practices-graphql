#!/usr/bin/env bash
# examples/27-final-project/scripts/up.sh
#
# profile.sh, images.sh, helm upgrade --install --wait, a rollout check per
# Deployment, and helm test.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SCRIPTS="$(dirname "${BASH_SOURCE[0]}")"

"$SCRIPTS/profile.sh"
"$SCRIPTS/images.sh"

step "helm upgrade --install $RELEASE"
hc upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" --create-namespace \
  --wait --timeout 10m

step "rollout status"
for deployment in lgtm keycloak quarkus python quarkus-internal python-internal edge; do
  kc -n "$NAMESPACE" rollout status "deploy/$deployment" --timeout=5m
done

step "helm test $RELEASE"
hc test "$RELEASE" --namespace "$NAMESPACE" --logs --timeout 5m

step "up: $RELEASE is deployed and tested; run scripts/smoke.sh"
