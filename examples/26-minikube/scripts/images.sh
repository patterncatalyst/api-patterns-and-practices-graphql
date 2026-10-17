#!/usr/bin/env bash
# examples/26-minikube/scripts/images.sh
#
# Builds Chapter 25's two images with docker build and loads them, with the
# edge and observability images, into the node with minikube image load. The
# chart's Deployments use the bare image names with imagePullPolicy Never, so
# an image the node does not hold fails loudly instead of being pulled.
#
# After a reload, `kubectl rollout restart deploy/<name>` starts pods on the new image.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(repo_root)"
CH25="$ROOT/examples/25-docker-compose"
EDGE_IMAGE="registry.access.redhat.com/ubi10/nginx-126:10.2-1791973310"
LGTM_IMAGE="docker.io/grafana/otel-lgtm:0.37.0"

preflight
[[ "$(profile_status)" == "Running" ]] || fail "profile $PROFILE is not running; run profile.sh first"

step "docker build: Chapter 25's images"
docker build -q -f "$CH25/quarkus/Containerfile" -t gql-ch25-quarkus:1.0 "$CH25/quarkus"
docker build -q -f "$CH25/python/Containerfile" -t gql-ch25-python:1.0 "$CH25/python"

step "images the cluster runs besides the stacks"
for image in "$EDGE_IMAGE" "$LGTM_IMAGE"; do
  docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image"
done

step "minikube image load into $PROFILE"
for image in gql-ch25-quarkus:1.0 gql-ch25-python:1.0 "$EDGE_IMAGE" "$LGTM_IMAGE"; do
  minikube -p "$PROFILE" image load "$image"
  ok "$image"
done
minikube -p "$PROFILE" image ls --format table | grep -E 'gql-ch25|nginx-126|otel-lgtm' || true
