#!/usr/bin/env bash
# examples/27-final-project/scripts/profile.sh [--replace]
#
# The profile is Chapter 26's: gql-tracking, Docker Engine, containerd,
# Kubernetes v1.37.1, with the NodePorts of both chapters (30360-30365 and
# 30370-30378) published on 127.0.0.1 when it is created. This script runs
# Chapter 26's profile.sh, which creates, starts or verifies it, and checks
# with docker port that every NodePort of this chapter is published.
set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/../../26-minikube/scripts/profile.sh" "$@"
