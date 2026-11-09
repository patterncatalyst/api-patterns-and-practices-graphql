---
title: "Kubernetes on minikube"
order: 26
part: "Running It & the Final Project"
description: "Both stacks as one Helm release on minikube: a values map for the two stacks, ConfigMaps, a generated TLS Secret, three probes, a NodePort edge published at cluster creation, the pod named in each trace, and a NetworkPolicy."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Render one Helm chart template over a `stacks` map so two services can't drift apart in structure.
- Roll only the pods whose configuration changed, using a `checksum/config` annotation on the pod template.
- Generate a TLS `Secret` with `genCA` and `genSignedCert`, and keep it stable across upgrades with `lookup`.
- Map startup, readiness, and liveness probes onto the health endpoints each stack already serves.
- Restrict pod-to-pod traffic with a `NetworkPolicy` per tier, and check that it holds with a labeled test pod.

## Why this matters

A Compose project is one local tier: an nginx edge in front of two stacks, an observability backend beside them, and Compose to start them in order. A cluster runs the same images. When the application code does not change, every difference between the tiers lives in configuration, and the chart that describes it is small enough to read in one sitting.

The release carries no application sources. `images.sh` builds the Compose tier's Containerfiles, `helm/` describes the release, and `up.sh`, `smoke.sh` and `down.sh` run it. There is no `verify.sh`, because a cluster is created once, kept and stopped, not built and removed inside a script. CI validates the chart without a cluster.

## What changes from Compose to Kubernetes

Every concept in `compose.yaml` has a counterpart, and the counterparts are not always one-to-one.

{% include excalidraw.html file="26-compose-to-kubernetes" alt="Two columns of nine rows joined by arrows. The left column, Compose, lists services, ports, env_file, configs, secrets, healthcheck with depends_on, deploy resources limits, restart with stop_grace_period, and the internal backend network. The right column, the Helm chart on Kubernetes, lists the matching objects: a Deployment and ClusterIP Service per stack, NodePort Services 30360 and 30361, a ConfigMap read with envFrom, a ConfigMap mounted as nginx.conf, a TLS Secret from genCA kept with lookup, three probes, resource requests and limits, the kubelet with a 30 second grace period, and a NetworkPolicy per tier. Each row names the file it lives in." caption="Figure 26.1: Compose concepts and the chart templates that carry them. The images, the environment contract and the edge configuration are the same in both tiers." %}

A Compose service becomes two objects. The Deployment keeps the desired number of pods running and rolls a new version out. The Service gives them one stable name and address. `depends_on` with `service_healthy` has no counterpart: Kubernetes starts everything at once and lets readiness decide who receives traffic, so the edge starts before a backend is ready and the Service sends it nothing until the backend says it can. The restart policy moves from the engine to the kubelet. The internal network becomes a NetworkPolicy, a rule about who may connect instead of a place a container lives.

## The cluster

minikube runs a Kubernetes cluster as one container on Docker Engine. The profile is `gql-tracking`:

```bash
minikube start -p gql-tracking \
  --driver=docker --container-runtime=containerd \
  --kubernetes-version=v1.37.1 \
  --cpus=6 --memory=12g --disk-size=40g \
  --ports=127.0.0.1:30360:30360,...,127.0.0.1:30378:30378 \
  --keep-context
```

The driver is `docker` and the runtime is `containerd`, so the node is a container and the pods run under containerd, with no second engine to install. The Kubernetes version is explicit, so a newer default never changes what a reader gets. `--keep-context` leaves the current `kubectl` context alone, and every command in the scripts names its cluster anyway: `minikube -p gql-tracking`, `kubectl --context gql-tracking`, `helm --kube-context gql-tracking`.

`--ports` is the only way the host reaches a pod. A NodePort is published on the node container at creation and bound to `127.0.0.1`, so nothing on the local network sees it. The NodePort number is also the host port: the Quarkus edge answers on `https://127.0.0.1:30360/graphql`, the Python edge on 30361, and Grafana, Tempo, Prometheus and Loki on 30362 to 30365. The list is fixed when the profile is created, and adding a port means recreating it, so `profile.sh` publishes all fifteen ports of this release and of the final project at once. It checks with `ss -ltn` that every host port is free first, and with `docker port gql-tracking` that every mapping exists afterward.

OpenShift Local and a second minikube profile compete for the same memory, so `lib.sh` fails, naming the command that stops each running profile, and never stops one itself. `profile.sh` starts a stopped profile; the published ports and the loaded images survive a stop.

## Images into the node

The Deployments name the Compose tier's images by their bare tags, `gql-ch25-quarkus:1.0` and `gql-ch25-python:1.0`, with `imagePullPolicy: Never`. No registry holds them. `images.sh` builds each Containerfile with `docker build` and copies the result into the node with `minikube -p gql-tracking image load`, together with the nginx and otel-lgtm images. A pod that starts from an image the node does not hold fails with `ErrImageNeverPull` instead of fetching another one. After a rebuild, `image load` replaces the image in the node and `kubectl rollout restart deploy/quarkus` starts pods on it.

## One chart for both stacks

The two stacks are two entries of one map in `values.yaml`:

```yaml
stacks:
  quarkus:
    image:
      repository: gql-ch25-quarkus
      tag: "1.0"
      pullPolicy: Never
    containerPort: 8080
    replicas: 1
```

A template ranges over the map and renders a ConfigMap, a Deployment and a Service for each entry, so one template produces both and the stacks can't drift in structure. `values.schema.json` states what a valid values file looks like, and Helm validates every install, upgrade, lint and template against it. It names the two allowed stacks, requires each probe path to start with a slash, limits the pull policy to its three values, and rejects `runAsUser`, `runAsGroup` and `fsGroup`. A mistyped key fails before any object reaches the cluster.

Every object carries the `app.kubernetes.io` labels: `name`, `instance`, `component`, `part-of`, `version` and `managed-by`. Selectors use only `name` and `instance`. Labels may change in an upgrade and a Deployment's selector may not, so a selector holds only the pair that never changes.

## Configuration and secrets

The environment contract is the `env` map of each stack, rendered into a ConfigMap and read with `envFrom`:

```yaml
    env:
      OTEL_EXPORTER_OTLP_ENDPOINT: http://lgtm:4317
      QUARKUS_OTEL_SERVICE_NAME: ch26-quarkus
      TRACKING_SOURCE_LATENCY_MS: "250"
      TRACKING_DEBUG_ENDPOINTS: "true"
```

The keys are the ones Compose passed. Only the host name changed, because `lgtm` is now a Service, and application code cannot tell the tiers apart.

A pod reads its environment once, at start, so a changed ConfigMap does not reach a running pod. Each Deployment's pod template carries `checksum/config`, the hash of that stack's rendered ConfigMap:

{% raw %}
```yaml
      annotations:
        # A change to the stack's environment changes this hash, which rolls the pods.
        checksum/config: {{ include "gql.stackConfigMap" (dict "root" $ "name" $name "stack" $stack) | sha256sum }}
```
{% endraw %}

A changed value changes the hash, the pod template differs, and the Deployment rolls. Only the stack whose configuration changed rolls.

The edge's TLS material is a Secret the chart generates, as `gen-certs.sh` did for Compose. `genCA` makes the authority and `genSignedCert` signs a server certificate for `localhost`, `127.0.0.1` and the edge Service's names. A generated value would change on every render, so the template asks the cluster first:

{% raw %}
```yaml
{{- $existing := lookup "v1" "Secret" .Release.Namespace $name }}
{{- if and $existing $existing.data }}
```
{% endraw %}

When the Secret exists, `lookup` returns it and the template reuses its data, so an upgrade keeps the certificate that clients already trust. `helm template` has no cluster to read and generates a fresh pair on each run, which is harmless in CI. The Secret is mounted read-only with mode `0444`, because the chart sets no `fsGroup` and the cluster assigns the user. These are lab keys.

## Probes and lifecycle

Compose had one healthcheck per service. Kubernetes asks three questions, and each stack answers them with the endpoints the Compose tier already served:

{% include codetabs.html langs="Quarkus|Python" %}

```yaml
    probes:
      startup:
        path: /q/health/started
        periodSeconds: 2
        failureThreshold: 60
      readiness:
        path: /q/health/ready
        periodSeconds: 5
        failureThreshold: 3
      liveness:
        path: /q/health/live
        periodSeconds: 10
        failureThreshold: 3
```

```yaml
    probes:
      startup:
        path: /health/live
        periodSeconds: 2
        failureThreshold: 30
      readiness:
        path: /health/ready
        periodSeconds: 5
        failureThreshold: 3
      liveness:
        path: /health/live
        periodSeconds: 10
        failureThreshold: 3
```

The startup probe holds the other two back until the process has come up, so a JVM that needs a minute is not killed for being slow: sixty failures at two seconds each give Quarkus two minutes. Readiness decides whether the Service sends traffic. Liveness decides whether the kubelet restarts the container, so it asks the smallest question, whether the process answers at all. That is why Python's startup and liveness both use `/health/live` while readiness uses `/health/ready`, which stays unavailable until the lifespan has built the store and the sources.

Both stacks drain in-flight requests for up to ten seconds after SIGTERM. The pod's `terminationGracePeriodSeconds` is thirty, and a `preStop` sleep of five seconds runs first, so the Service has dropped the pod from its endpoints before the signal arrives. The strategy is `RollingUpdate` with `maxUnavailable: 0` and `maxSurge: 1`: a new pod must be ready before an old one leaves.

The security contexts are the restricted profile: `runAsNonRoot`, no privilege escalation, every capability dropped, the runtime's default seccomp profile. The stacks, the edge and the `helm test` pod run under it. The otel-lgtm image runs as root, so its container keeps the same settings without `runAsNonRoot`. No user or group ID is set. The UBI images run as numeric non-root users and accept the one the cluster assigns, so the same chart fits a cluster that assigns its own.

## The way in

The edge is the same nginx on the same `ubi10/nginx-126` image, with the same rules: TLS 1.3 only, a 64k body limit, only `/graphql` routed, the `traceparent` header passed through. Its configuration is rendered into a ConfigMap and mounted over `/etc/nginx/nginx.conf`. The pid file and temporary paths are under `/tmp`, an `emptyDir`, because the image runs unprivileged. nginx resolves a backend name once, at start, and a Service keeps its address for as long as it exists, so the edge names the ClusterIP Services `quarkus` and `python` and reaches a restarted pod at the same address.

{% include excalidraw.html file="26-cluster-topology" alt="A host box sends curl with a CA file to 127.0.0.1 port 30360. An arrow leads into a large band for the node container gql-tracking, running containerd and Kubernetes v1.37.1 in namespace gql-ch26. Inside, arrows lead from the Service edge, a NodePort 8443 to 30360 published by Docker, to the edge pod running nginx with TLS 1.3 and a 64k limit, which mounts the Secret gql-ch26-edge-tls and the ConfigMap edge-config. From the edge pod an arrow leads to the ClusterIP Service quarkus and then to the quarkus pod named quarkus-588766b5bf-dxv9z, which has three probes, a ConfigMap and the downward API. An arrow labelled OTLP leads from the quarkus pod down to the lgtm pod. A second host box requests the trace by id on port 30363, through the Service lgtm-ui, to the lgtm pod. A dark box at the bottom shows trace 14d6ffd0 with 11 spans whose resource attribute k8s.pod.name is the quarkus pod." caption="Figure 26.2: A request from the host to a pod and the trace back to its name. Docker publishes the port, the NodePort Service carries it to the edge, and a ClusterIP Service picks a ready pod." %}

The chain has four hops, and each is a different mechanism. Docker publishes `127.0.0.1:30360` on the node container. Inside the node, the NodePort Service `edge` maps that port to the edge pod's TLS listener on 8443. The edge proxies to the ClusterIP Service `quarkus`, and the Service picks one of its ready pods. A pod that fails readiness drops out of the last hop without any change to the first three.

The Service type is a value. `edge.service.type` takes `NodePort` or `ClusterIP`, and `edge.tls.enabled=false` turns the listeners into plain ones on 8080 and 8081. A platform that terminates TLS in front of the cluster, or publishes ports some other way, sets those two values and keeps the rest of the chart. A shared cluster would put Gateway API in front instead, with the same edge rules written as routes on a gateway a platform team runs. This chart keeps its own edge because it behaves identically in every tier.

## Telemetry by environment

The stacks export OTLP to `http://lgtm:4317`, a ClusterIP Service in front of the otel-lgtm pod, which runs the same image as the Compose tier's backend: collector, Tempo, Prometheus, Loki and Grafana. A second Service, `lgtm-ui`, publishes the four interfaces on NodePorts 30362 to 30365.

What a cluster adds is identity. Telemetry from a pod that may be replaced at any moment is only useful if it says which pod produced it. The downward API passes the pod's metadata into its environment, and `OTEL_RESOURCE_ATTRIBUTES` turns it into OpenTelemetry resource attributes, following the Kubernetes resource conventions:

```yaml
          env:
            # The downward API names the pod, and OpenTelemetry resource
            # attributes carry the name into every span, metric and log record.
            - name: K8S_POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: K8S_NAMESPACE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: K8S_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "k8s.pod.name=$(K8S_POD_NAME),k8s.namespace.name=$(K8S_NAMESPACE_NAME),k8s.node.name=$(K8S_NODE_NAME)"
```

Kubernetes expands `$(K8S_POD_NAME)` from the entries defined above it, and both SDKs read the variable at start. Every span, metric and log record of the pod then carries `k8s.pod.name`. After a rollout, the new pod's name appears in new traces and the old name stays on the traces it produced.

## Isolation

The chart ships one NetworkPolicy per tier. Backends accept port 8080 from pods labeled `edge` or `test` in the release and from nobody else. The edge accepts its own ports from any source, because it is the way in from outside. The observability pod accepts OTLP from the release's pods and its four interfaces from any source. Probes come from the kubelet on the node and are not subject to these rules.

A NetworkPolicy takes effect only when the cluster's network plugin implements it. The plugin on this profile does. The plugin enforces the policies, not the API server, so it is part of the security design.

## A release over time

A Helm release is a history. `helm upgrade` renders the chart again, compares the result with the live objects and applies the difference. Each upgrade is a numbered revision that `helm history gql-ch26` lists and `helm rollback` can return to.

- **Pods roll only when their template changes.** Changing the Python latency setting changes Python's `checksum/config` and nothing in Quarkus's template. With `maxUnavailable: 0` the new Python pod must pass readiness before the old one is removed, and the `preStop` sleep keeps the old pod answering while it leaves the endpoints.
- **The certificate does not change.** Revision two has the same CA as revision one, so a client that trusts the CA keeps working. Delete the Secret by hand and the next upgrade generates a new pair; the edge reads its files at start and needs a restart to pick it up.
- **Values are layered.** `--reuse-values` keeps what the release has and applies only the command-line overrides. A values file such as `ci-values-alt.yaml` replaces a group of settings at once, and the schema checks the merged result either way.

## What the profile costs

The profile is sized for the final project's larger release: six CPUs, twelve gigabytes of memory and forty gigabytes of disk. This release requests far less: Quarkus 512 MiB (limit 768 MiB), Python 256 MiB (limit 384 MiB), the edge 32 MiB and otel-lgtm 1 GiB, about two gibibytes and under one CPU in all, and the node holds about 1.4 GB of loaded images. `down.sh` therefore stops the profile instead of deleting it: a stop returns memory and CPU and keeps the disk, and the next start reuses the node and its images.

> **Decision**
>
> Run the tracking view on Kubernetes as one Helm release for both stacks, reached through NodePorts published at cluster creation. The chart turns operational and security habits into objects stated once: probes on each stack's own health endpoints, a restricted security context, a NetworkPolicy per tier, and a certificate it generates and keeps with `lookup`. Clients written against Compose run against the cluster by changing a port and a CA file; the schema is still the canonical SDL.

## Build, run, observe

`up.sh` runs `profile.sh`, then `images.sh`, then installs the chart:

```bash
helm upgrade --install gql-ch26 examples/26-minikube/helm \
  --namespace gql-ch26 --create-namespace \
  --kube-context gql-tracking --wait --timeout 10m
```

`--wait` returns when the Deployments are available. `helm test` then runs the pod in `templates/tests/test-graphql.yaml`. It carries the `test` label, mounts the chart's CA, and posts a `{ __typename }` query and a `TrackCargo` query to each stack through the edge's Service name over TLS 1.3. A release that deploys but can't answer a GraphQL query fails here, before any script from the host runs.

```bash
examples/26-minikube/scripts/up.sh      # profile, images, helm upgrade --install, rollout, helm test
examples/26-minikube/scripts/smoke.sh   # the checks, through 127.0.0.1:30360-30365
examples/26-minikube/scripts/down.sh    # uninstall, delete the namespace, minikube stop
```

`smoke.sh` repeats the Compose tier's checks from the host through the published ports, with `LGTM_CACERT` pointing at the CA the chart generated, and adds the cluster cases. Both scripts stop at the first failure, and `smoke.sh` ends with `PASS`. `down.sh` stops the profile and does not delete it, so the next `up.sh` skips creation. The one script path that deletes it is `profile.sh --replace`, for a changed port list.

CI needs no cluster. It runs `helm lint --strict` and renders the chart twice, with the defaults and with `ci-values-alt.yaml`, which switches TLS off, uses ClusterIP Services, drops the NetworkPolicy and adds a HorizontalPodAutoscaler per stack. Each render goes through `kubeconform -strict` against the Kubernetes 1.37.1 schemas, which fails on an unknown field and on a wrong type. ShellCheck covers the scripts.

Experiments:

- Change `TRACKING_SOURCE_LATENCY_MS` from 250 to 100 with `--reuse-values`. Python's `checksum/config` changes and its pod is replaced; Quarkus keeps its hash and its pod, and the CA hash is unchanged. Set it back to 250.
- Run a one-shot pod without the `edge` or `test` label against `quarkus:8080`. It times out (curl exit 28). A pod labeled `test` gets `200`.
- Send a 100 KB body to either edge port. It gets `413` at the edge and no call reaches the pod.
- Open a TLS 1.2 connection to port 30360. It is refused; TLS 1.3 is served.
- Send a `traceparent` header and look up the trace in Tempo on 30363. `k8s.pod.name` on its resource is a Quarkus or Python pod.

## For deeper coverage

- *Cloud Native Design Patterns*, Appendix R: "Running Example 05 on minikube": the same Docker-driver/containerd-runtime minikube pattern, applied to a different example.
- [Kubernetes: Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Kubernetes: Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Helm: Template Function List](https://helm.sh/docs/chart_template_guide/function_list/): `genCA`, `genSignedCert`, and `lookup`.
- [minikube: start command reference](https://minikube.sigs.k8s.io/docs/commands/start/): `--ports`, `--kubernetes-version`, and image loading.
