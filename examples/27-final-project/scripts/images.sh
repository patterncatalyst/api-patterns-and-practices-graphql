#!/usr/bin/env bash
# examples/27-final-project/scripts/images.sh
#
# Builds this chapter's four images with docker build (the Containerfiles of the
# compose tier, unchanged) and loads them, with the edge, Keycloak and
# observability images, into the node with minikube image load. The chart's
# Deployments use the bare image names with imagePullPolicy Never, so an image
# the node does not hold fails loudly instead of being pulled. The client and
# the load image are for the pods smoke.sh runs.
#
# After a reload, `kubectl rollout restart deploy/<name>` starts pods on the new image.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(repo_root)"
CH27="$ROOT/examples/27-final-project"
EDGE_IMAGE="registry.access.redhat.com/ubi10/nginx-126:10.2-1791973310"
KEYCLOAK_IMAGE="quay.io/keycloak/keycloak:26.8.1"
LGTM_IMAGE="docker.io/grafana/otel-lgtm:0.37.0"

preflight
[[ "$(profile_status)" == "Running" ]] || fail "profile $PROFILE is not running; run profile.sh first"

step "docker build: the images of the compose tier"
docker build -q -f "$CH27/quarkus/Containerfile" -t gql-ch27-quarkus:1.0 "$CH27/quarkus"
docker build -q -f "$CH27/python/Containerfile" -t gql-ch27-python:1.0 "$CH27/python"
docker build -q -f "$CH27/client/Containerfile" -t gql-ch27-client:1.0 "$CH27/client"
docker build -q -f "$CH27/load/Containerfile" --build-context "documents=$CH27/documents" -t gql-ch27-load:1.0 "$CH27/load"

step "images the cluster runs besides the stacks"
for image in "$EDGE_IMAGE" "$KEYCLOAK_IMAGE" "$LGTM_IMAGE"; do
  docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image"
done

step "minikube image load into $PROFILE"
for image in gql-ch27-quarkus:1.0 gql-ch27-python:1.0 gql-ch27-client:1.0 gql-ch27-load:1.0 \
  "$EDGE_IMAGE" "$KEYCLOAK_IMAGE" "$LGTM_IMAGE"; do
  minikube -p "$PROFILE" image load "$image"
  ok "$image"
done
minikube -p "$PROFILE" image ls --format table | grep -E 'gql-ch27|nginx-126|keycloak|otel-lgtm' || true
