---
title: "Kubernetes on minikube"
order: 26
part: "Running It & the Final Project"
description: "The two stacks of Chapter 25 as one Helm release on minikube: a values map for both stacks, ConfigMaps, a chart-generated TLS Secret, startup, readiness and liveness probes, a NodePort edge published at cluster creation, the pod named in each trace, a NetworkPolicy and helm test."
duration: "16 min read"
---

Chapter 25 ran the tracking view as one local tier: an nginx edge in front of two stacks, an observability backend beside them, and Compose to start them in order. The images it built are the ones a cluster runs. This chapter moves the same tier onto Kubernetes without touching a line of application code, so every difference between the two tiers lives in configuration, and the chart that describes it is small enough to read in one sitting.

The code is in `examples/26-minikube/`. It carries no application sources: `images.sh` builds Chapter 25's Containerfiles, `helm/` describes the release, and `up.sh`, `smoke.sh` and `down.sh` run it. The example has no `verify.sh`, because a cluster is a different kind of fixture from a compose project. A compose stack is created and removed in minutes inside a script; a cluster is created once, kept, and stopped. The chart is validated without a cluster in CI, and the scripts prove it on a live one.

## What changes from Compose to Kubernetes

Every concept in `compose.yaml` has a counterpart in Kubernetes, and the counterparts are not always one-to-one. Figure 26.1 lists them with the file each lives in.

{% include excalidraw.html file="26-compose-to-kubernetes" alt="Two columns of nine rows joined by arrows. The left column, Chapter 25 Compose, lists services, ports, env_file, configs, secrets, healthcheck with depends_on, deploy resources limits, restart with stop_grace_period, and the internal backend network. The right column, Chapter 26 Helm chart on Kubernetes, lists the matching objects: a Deployment and ClusterIP Service per stack, NodePort Services 30360 and 30361, a ConfigMap read with envFrom, a ConfigMap mounted as nginx.conf, a TLS Secret from genCA kept with lookup, three probes, resource requests and limits, the kubelet with a 30 second grace period, and a NetworkPolicy per tier. Each row names the file it lives in." caption="Figure 26.1 — Compose concepts and the chart templates that carry them. The images, the environment contract and the edge configuration are the same in both tiers." %}

A Compose service becomes two objects. The Deployment keeps the desired number of pods running and rolls a new version out; the Service gives them one stable name and address. `depends_on` with `service_healthy` has no direct counterpart, because Kubernetes starts everything at once and lets readiness decide who receives traffic: the edge starts before a backend is ready, and the Service sends it nothing until the backend says it can. The restart policy moves from the engine to the kubelet, and the internal network moves from a network flag to a NetworkPolicy, which is a rule about who may connect rather than a place a container lives.

## The cluster

minikube runs a Kubernetes cluster as one container on Docker Engine. The profile for this book is `gql-tracking`:

```bash
minikube start -p gql-tracking \
  --driver=docker --container-runtime=containerd \
  --kubernetes-version=v1.37.1 \
  --cpus=6 --memory=12g --disk-size=40g \
  --ports=127.0.0.1:30360:30360,...,127.0.0.1:30378:30378 \
  --keep-context
```

Four choices in it matter. The driver is `docker` and the runtime is `containerd`, so the node is a container and the pods inside it run under containerd, with no second engine to install. The Kubernetes version is explicit, so a newer default never changes what a reader gets. `--keep-context` leaves the current `kubectl` context alone, and every command in the scripts names its cluster anyway: `minikube -p gql-tracking`, `kubectl --context gql-tracking`, `helm --kube-context gql-tracking`.

The fourth is `--ports`. The only way the host reaches a pod is a NodePort published on the node container at creation, bound to `127.0.0.1` so that nothing on the local network sees it. The NodePort number is also the host port, which keeps the chapter's addresses to one number each: the Quarkus edge answers on `https://127.0.0.1:30360/graphql`, the Python edge on 30361, and Grafana, Tempo, Prometheus and Loki on 30362 to 30365. The list is fixed when the profile is created. Adding a port later means recreating the profile, so `profile.sh` publishes all fifteen ports of this chapter and of Chapter 27 at once. It checks with `ss -ltn` that every host port is free before it creates anything, and with `docker port gql-tracking` that every mapping exists afterward.

`profile.sh` also checks what must not be running. OpenShift Local and a second minikube profile compete for the same memory, so `lib.sh` fails, naming the command that stops each running profile, and never stops one itself. The same script starts a stopped profile; the published ports and the loaded images survive a stop.

## Images into the node

The chart's Deployments name Chapter 25's images by their bare tags, `gql-ch25-quarkus:1.0` and `gql-ch25-python:1.0`, with `imagePullPolicy: Never`. No registry holds them. `images.sh` builds each Containerfile with `docker build` and copies the result into the node with `minikube -p gql-tracking image load`, together with the nginx and otel-lgtm images. A pod that starts from an image the node does not hold fails with `ErrImageNeverPull` instead of fetching another image, so the cluster runs only what `images.sh` loaded. After a rebuild, `image load` replaces the image in the node, and `kubectl rollout restart deploy/quarkus` starts pods on it.

## One chart for both stacks

The chart is `helm/`, with `Chart.yaml` at the top so that `helm lint` and CI run on that directory. The two stacks are two entries of one map in `values.yaml`:

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

A template ranges over the map and renders a ConfigMap, a Deployment and a Service for each entry. The two stacks cannot drift apart in structure, because one template produces both. `values.schema.json` states what a valid values file looks like, and Helm validates every install, upgrade, lint and template against it. The schema names the two allowed stacks, requires each probe to have a path that starts with a slash, limits the image pull policy to its three values, and rejects a `runAsUser`, `runAsGroup` or `fsGroup` in the security contexts. A mistyped key then fails before any object reaches the cluster.

Every object carries the `app.kubernetes.io` labels: `name`, `instance`, `component`, `part-of`, `version` and `managed-by`. Selectors use only `name` and `instance`. Labels may change in an upgrade; a Deployment's selector may not, so the pair that never changes is the only pair a selector holds.

## Configuration and secrets

Chapter 25's environment contract is one table of keys per stack. In the chart it is the `env` map of each stack, rendered into a ConfigMap and read with `envFrom`:

```yaml
    env:
      OTEL_EXPORTER_OTLP_ENDPOINT: http://lgtm:4317
      QUARKUS_OTEL_SERVICE_NAME: ch26-quarkus
      TRACKING_SOURCE_LATENCY_MS: "250"
      TRACKING_DEBUG_ENDPOINTS: "true"
```

The keys are the ones Compose passed; only the host name changed, because `lgtm` is now a Service. Application code cannot tell the tiers apart, which is the point of reading configuration from the environment.

A pod reads its environment once, at start, so a changed ConfigMap does not reach a running pod. The chart handles that with a checksum annotation. Each Deployment's pod template carries `checksum/config`, the hash of that stack's rendered ConfigMap:

{% raw %}
```yaml
      annotations:
        # A change to the stack's environment changes this hash, which rolls the pods.
        checksum/config: {{ include "gql.stackConfigMap" (dict "root" $ "name" $name "stack" $stack) | sha256sum }}
```
{% endraw %}

A changed value changes the hash, the pod template differs, and the Deployment rolls. Only the stack whose configuration changed rolls; its neighbour keeps its pod.

The edge's TLS material is a Secret the chart generates. Chapter 25 made a throwaway authority with `gen-certs.sh`; the chart does the same with Helm's template functions. `genCA` makes the authority and `genSignedCert` signs a server certificate for `localhost`, `127.0.0.1` and the edge Service's names. A generated value would change on every render, so the template asks the cluster first:

{% raw %}
```yaml
{{- $existing := lookup "v1" "Secret" .Release.Namespace $name }}
{{- if and $existing $existing.data }}
```
{% endraw %}

When the Secret exists, `lookup` returns it and the template reuses its data, so an upgrade keeps the certificate that clients already trust. `helm template` has no cluster to read and generates a fresh one on each run, which is harmless in CI. The Secret is mounted into the edge as a volume, and the keys are lab keys: the volume is mounted read-only with mode `0444` (`defaultMode: 292`), readable by whichever user the cluster assigns, since the chart sets no `fsGroup`.

## Probes and lifecycle

Compose had one healthcheck per service. Kubernetes asks three different questions, and each stack answers them with the endpoints Chapter 25 already built:

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

The startup probe holds the other two back until the process has come up, so a JVM that needs a minute is not killed for being slow: sixty failures at two seconds each give Quarkus two minutes. Readiness decides whether the Service sends traffic. Liveness decides whether the kubelet restarts the container, which is why it asks the smallest question, whether the process answers at all, and why Python's startup and liveness both use `/health/live` while readiness uses `/health/ready`, which stays unavailable until the lifespan has built the store and the sources.

The lifecycle settings follow from the application's own shutdown. Both stacks drain in-flight requests for up to ten seconds after SIGTERM. The pod's `terminationGracePeriodSeconds` is thirty, three times that, and a `preStop` sleep of five seconds runs first, so the Service has dropped the pod from its endpoints before the signal arrives. The strategy is `RollingUpdate` with `maxUnavailable: 0` and `maxSurge: 1`: a new pod must be ready before an old one leaves. Resources are requests and limits, taken from Chapter 25's Compose limits, and the security contexts are the restricted profile: `runAsNonRoot`, no privilege escalation, every capability dropped, the runtime's default seccomp profile. The stacks, the edge and the test pod run under it. The otel-lgtm image runs as root, so its container keeps the same settings without `runAsNonRoot`; OpenShift admits it through the binding to the `anyuid` constraint that Appendix A creates. No user or group ID is set. The UBI images run as numeric non-root users and accept the one the cluster assigns, so the same chart fits a cluster that assigns its own.

## The way in

The edge is the same nginx on the same `ubi10/nginx-126` image, with the same rules: TLS 1.3 only, a 64k body limit, only `/graphql` routed, the `traceparent` header passed through. Its configuration is rendered into a ConfigMap from the chart's values and mounted over `/etc/nginx/nginx.conf`. The pid file and temporary paths are under `/tmp`, an `emptyDir`, because the image runs as an unprivileged user. The chart's nginx names its backends as the ClusterIP Services `quarkus` and `python`. nginx resolves a name once, at start, and a Service keeps its address for as long as it exists, so a backend pod that restarts or moves is reached at the same address through the node's proxy rules.

Figure 26.2 follows one request from the host to a pod.

{% include excalidraw.html file="26-cluster-topology" alt="A host box sends curl with a CA file to 127.0.0.1 port 30360. An arrow leads into a large band for the node container gql-tracking, running containerd and Kubernetes v1.37.1 in namespace gql-ch26. Inside, arrows lead from the Service edge, a NodePort 8443 to 30360 published by Docker, to the edge pod running nginx with TLS 1.3 and a 64k limit, which mounts the Secret gql-ch26-edge-tls and the ConfigMap edge-config. From the edge pod an arrow leads to the ClusterIP Service quarkus and then to the quarkus pod named quarkus-588766b5bf-dxv9z, which has three probes, a ConfigMap and the downward API. An arrow labelled OTLP leads from the quarkus pod down to the lgtm pod. A second host box requests the trace by id on port 30363, through the Service lgtm-ui, to the lgtm pod. A dark box at the bottom shows trace 14d6ffd0 with 11 spans whose resource attribute k8s.pod.name is the quarkus pod." caption="Figure 26.2 — A request from the host to a pod and the trace back to its name. Docker publishes the port, the NodePort Service carries it to the edge, and a ClusterIP Service picks a ready pod." %}

The chain has four hops, and each is a different mechanism. Docker publishes `127.0.0.1:30360` on the node container. Inside the node, the NodePort Service `edge` maps that port to the edge pod's TLS listener on 8443. The edge proxies to the ClusterIP Service `quarkus`, and the Service picks one of its ready pods. A pod that fails readiness drops out of that last hop without any change to the first three.

The Service type is a value. `edge.service.type` takes `NodePort` or `ClusterIP`, and `edge.tls.enabled=false` turns the listeners into plain ones on 8080 and 8081. A platform that terminates TLS in front of the cluster, or one that publishes ports some other way, sets those two values and keeps the rest of the chart. CI renders that variant too. A shared cluster would also put an ingress layer in front, and Gateway API is the standard shape for it: the same edge rules written as routes on a gateway that a platform team runs. This chapter keeps its own edge because it is the one component whose behavior is already specified, tested and identical in every tier.

## Telemetry by environment

The stacks export OTLP to `http://lgtm:4317`, and `lgtm` is a ClusterIP Service in front of the otel-lgtm pod, which runs the same image as in Chapter 25: collector, Tempo, Prometheus, Loki and Grafana. A second Service, `lgtm-ui`, publishes the four interfaces on the NodePorts 30362 to 30365.

What a cluster adds is identity. Telemetry from a pod that might be replaced at any moment is only useful if it says which pod produced it. The downward API passes the pod's own metadata into its environment, and `OTEL_RESOURCE_ATTRIBUTES` turns those values into OpenTelemetry resource attributes, following the Kubernetes resource conventions:

```yaml
            - name: K8S_POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "k8s.pod.name=$(K8S_POD_NAME),k8s.namespace.name=$(K8S_NAMESPACE_NAME),k8s.node.name=$(K8S_NODE_NAME)"
```

Kubernetes expands `$(K8S_POD_NAME)` from the entries defined above it, and both SDKs read the variable at start. Every span, metric and log record of the pod then carries `k8s.pod.name`. In the run behind Figure 26.2, the trace for one `ListCargos` request had eleven spans on the Quarkus stack, and their resource named `quarkus-588766b5bf-dxv9z`. After a rollout, the new pod's name appears in new traces, and the old name stays on the traces it produced.

## Isolation

Compose put the backends on an internal network. The Kubernetes counterpart is a NetworkPolicy, and the chart ships one per tier. Backends accept port 8080 from pods labelled `edge` or `test` in the release and from nobody else. The edge accepts its own ports from any source, because it is the way in from outside the cluster. The observability pod accepts OTLP from the release's pods and its four interfaces from any source. Probes come from the kubelet on the node and are not subject to these rules.

A NetworkPolicy takes effect only when the cluster's network plugin implements it. minikube's default plugin on this profile does, which `smoke.sh` shows with two one-shot pods: one without the edge or test label times out against `quarkus:8080`, and one labelled as the test pod gets an answer. The network plugin, not the API server, enforces the policies, so the plugin is part of the security design.

## A release over time

A Helm release is a history. `helm upgrade` renders the chart again, compares the result with the live objects and applies the difference, and each upgrade is a numbered revision that `helm history gql-ch26` lists and `helm rollback` can return to. Three behaviours of this chart show across revisions.

Pods roll only when their template changes. An upgrade that changes the Python latency setting changes Python's `checksum/config` and nothing in Quarkus's template, so the Quarkus pod keeps running. With `maxUnavailable: 0` the new Python pod must pass readiness before the old one is removed, so the Service keeps routing to the old pod until the new one is ready, and the `preStop` sleep keeps the old pod answering while it leaves the endpoints.

The certificate does not change. Because the Secret template reads the existing object with `lookup`, revision two has the same CA as revision one, and a client that already trusts the CA keeps working. Delete the Secret by hand and the next upgrade generates a new pair, and the edge, which reads its files at start, needs a restart to pick it up.

Values are layered. `--reuse-values` keeps what the release already has and applies only the overrides on the command line, which is how `smoke.sh` changes one environment value and puts it back. A values file such as `ci-values-alt.yaml` replaces a group of settings at once, and the schema checks the merged result either way.

## What the profile costs

The profile is sized for the largest release in the book, which is Chapter 27's: six CPUs, twelve gigabytes of memory and forty gigabytes of disk. This chapter's release needs far less. The Quarkus pod requests 512 MiB with a 768 MiB limit, the Python pod 256 MiB with a 384 MiB limit, the edge 32 MiB, and otel-lgtm one gibibyte, so the whole release asks for about two gibibytes and under one CPU of requests. The profile is a fixed budget, not a per-chapter one, and creating it once is what lets Chapter 27 reuse its ports.

The disk holds the node's images, about 1.4 GB after the four are loaded, and the Kubernetes components. That is why `down.sh` stops the profile instead of deleting it: a stop returns the memory and the CPU and keeps the disk, and the next start reuses the node and its images where a fresh creation downloads and loads everything again.

## Proving a release

`up.sh` runs `profile.sh`, then `images.sh`, then installs the chart:

```bash
helm upgrade --install gql-ch26 examples/26-minikube/helm \
  --namespace gql-ch26 --create-namespace \
  --kube-context gql-tracking --wait --timeout 10m
```

`--wait` returns when the Deployments are available, and `kubectl rollout status` confirms each one. Then `helm test` runs the pod defined in `templates/tests/test-graphql.yaml`. It carries the `test` label, mounts the chart's CA, and posts a `{ __typename }` query and a `TrackCargo` query to each stack through the edge's Service name over TLS 1.3. A release that deploys but cannot answer a GraphQL query fails here, before any script from the host runs.

`smoke.sh` then repeats Chapter 25's checks from the host through the published ports, with `LGTM_CACERT` pointing at the CA the chart generated. It adds the cluster cases: the pod named in a trace, a configuration change that rolls only the pods that read it, and the NetworkPolicy pair. Both scripts stop at the first failure and `smoke.sh` ends with `PASS`.

The chart is also validated with no cluster. CI runs `helm lint --strict` and renders the chart twice, with the defaults and with an alternate values file that switches TLS off, uses ClusterIP Services, drops the NetworkPolicy and adds a HorizontalPodAutoscaler per stack. Each render goes through `kubeconform -strict` against the Kubernetes 1.37.1 schemas, which fails on an unknown field and on a wrong type. ShellCheck covers the scripts. None of that needs a cluster, which is why it runs on every push.

## Stopping it

`down.sh` runs `helm uninstall --wait`, deletes the namespace and stops the profile with `minikube stop -p gql-tracking`. It stops and does not delete. The loaded images, the published ports and the node's disk stay, so the next `up.sh` skips creation and starts in a fraction of the time. Deleting the profile is a command a reader types by hand; the one script path that deletes it is `profile.sh --replace`, which recreates the profile when the published port list changes.

## On the wire

The commands and the values `smoke.sh` asserts, from the run recorded in the example's README:

```bash
examples/26-minikube/scripts/up.sh      # profile, images, helm upgrade --install, rollout, helm test
examples/26-minikube/scripts/smoke.sh   # the assertions below, through 127.0.0.1:30360-30365
examples/26-minikube/scripts/down.sh    # uninstall, delete the namespace, minikube stop
```

| Case | Quarkus (30360) | Python (30361) |
|---|---|---|
| published ports | `docker port gql-tracking` shows 127.0.0.1 for all fifteen NodePorts | the same |
| release | `helm status` is `deployed`; the test pod `Succeeded`; four Deployments rolled out | the same |
| probe paths | `/q/health/started`, `/ready`, `/live` equal the values | `/health/live`, `/health/ready`, `/health/live` |
| `TrackCargo` ABC123 | `ONBOARD_CARRIER` | the same |
| `FanOut` | Chapter 13's data; 8 source calls read inside the pod | the same data; 6 calls |
| `ListCargos` | six edges; GHI345 `SERVICE_UNAVAILABLE`, 6 errors | six edges; the same code, 1 error |
| edge routes | `/debug/source-calls`, `/q/health/ready`, `/health/ready`, `/` answer 404 | the same |
| TLS | no CA fails, TLS 1.2 refused, TLS 1.3 served | the same |
| 100 KB body | 413 at the edge; 0 calls reach the pod | the same |
| trace | `extensions.traceId` equals the id sent; the trace in Tempo with at least 8 spans (11 in the recorded run); `k8s.pod.name` is a Quarkus pod; Loki holds the record | at least 6 spans (16 recorded); a Python pod |
| NetworkPolicy | a pod with no edge or test label times out (curl exit 28); a test-labelled pod gets 200 | the same policy |
| config change | `TRACKING_SOURCE_LATENCY_MS` 250 to 100: Python's `checksum/config` changes and its pod is replaced; Quarkus keeps its hash and its pod; the CA hash is unchanged | then back to 250 |
| contract | `assert_sdl_conforms` passes; `finalArrivalDate` is deprecated | the same |

## Decision

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Kubernetes is where the <em>operational and security cost</em> axis of Chapter 2 becomes a set of objects instead of a set of habits. The chart states each of them once: probes the stack's own health endpoints answer, a security context a restricted cluster accepts for the stacks and the edge, a NetworkPolicy per tier, a certificate the chart generates and keeps. The <em>aggregation across sources</em> axis is unchanged, because the sources are still inside the stacks and the edge still routes one path. The <em>client diversity and shape variance</em> axis is served by the same edge in every tier, so a client written against Compose runs against the cluster by changing a port and a CA file. The <em>contract and evolution style</em> axis is untouched: the schema is the canonical SDL, and <code>assert_sdl_conforms</code> passes through the NodePorts. The tracking view therefore runs on Kubernetes as one Helm release for both stacks, reached through NodePorts published at cluster creation, with the pod named in every trace.</p></div>

## Where this goes next

This chapter put Chapter 25's tier on a cluster: one chart for both stacks, configuration in ConfigMaps with a checksum that rolls pods, a generated TLS Secret that survives upgrades, three probes per stack, a NodePort edge, a downward-API pod name in each trace, a NetworkPolicy and a chart test, all on a profile whose ports were fixed when it was created.

Chapter 27 builds the final project on the same profile. It serves the complete schema, subscriptions included, with Chapter 14's query limits, Chapter 18's authorization and Chapter 17's introspection control together, and its chart extends this one. For the references, read the Kubernetes documentation pages "Deployments", "Service", "ConfigMaps", "Secrets", "Configure Liveness, Readiness and Startup Probes", "Expose Pod Information to Containers Through Environment Variables", "Network Policies", "Resource Management for Pods and Containers" and "Pod Security Standards". The minikube documentation covers `minikube start` flags such as `--ports` and `--kubernetes-version` under "Basic controls" and image loading under "Pushing images". The Helm documentation has "Charts", "Chart Tests", "Values Files", the "Template Function List" for `genCA`, `genSignedCert` and `lookup`, and "Chart Development Tips and Tricks" for rolling deployments automatically. OpenTelemetry's "Resource semantic conventions: Kubernetes" defines the attribute names, and the kubeconform README explains its strict mode.
