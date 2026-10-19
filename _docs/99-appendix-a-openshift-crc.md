---
title: "Appendix A — OpenShift Local (CRC)"
order: 99
part: "Running It & the Final Project"
appendix: true
appendix_label: "A"
description: "Chapter 27's chart on OpenShift Local through a wrapper chart: Docker-strategy builds in the cluster, Routes with edge TLS at the router, restricted-v2 for every pod but one, and a teardown that returns the cluster to the state it started in; the image pruner removes the unreferenced build layers."
duration: "16 min read"
---

## Learning objectives

By the end of this chapter you can:

- Wrap an existing Helm chart in a dependency-only chart that adds `Route`s, `BuildConfig`s, `ImageStream`s, and one `RoleBinding`, without touching the wrapped chart.
- Build an image inside the cluster with a binary-source, Docker-strategy `BuildConfig`, with no container engine on the host.
- Run every pod under `restricted-v2`, and grant `anyuid` to exactly one service account for the one image that needs a root user.
- Terminate TLS at the router with an edge `Route`, and point an identity provider's issuer at that Route's URL.
- Tear down a CRC project against a saved inventory so a script-driven run leaves no orphaned namespace, `Subscription`, or CRD.

## Why this matters

Chapters 25 to 27 ran the tracking view in three places: a Compose project, a minikube profile, and a Helm chart that carries the final project. The chart is neutral. It names no distribution, sets no user id, and renders nothing that only one platform understands. This appendix tests that claim by running the same chart on a different distribution, OpenShift Local, and it counts what had to be added.

Nothing is added to the application or its images, and Chapter 27's chart gains one value, `lgtm.dropAllCapabilities`, whose default renders the chart as before. The code is in `examples/99-appendix-a-openshift-crc/`, and it is one wrapper chart and four scripts. The wrapper depends on Chapter 27's chart and adds the objects a platform with a router and an image registry wants: Routes, builds, image streams, and one binding for a security context constraint. OpenShift Local is a demonstration target here, as minikube is the main one. A reader who runs a different Kubernetes distribution reads this appendix as a list of the places where a platform differs and the one place per difference where the chart accommodates it.

The example has no `verify.sh`, like Chapter 26's, because a cluster is something a person starts and keeps. The proof is a recorded run on 2026-10-17 of `up.sh`, `smoke.sh` and `down.sh`, with the output in "On the wire"; the chart and the scripts are also validated without a cluster, offline. Pins: OpenShift Local 2.64.0, which bundles OpenShift 4.22.14 and Kubernetes 1.35.6.

## Same chart, another distribution

The wrapper's `Chart.yaml` has one dependency:

```yaml
dependencies:
  - name: gql-ch27-final
    version: 1.0.0
    repository: file://../../27-final-project/helm
    alias: final
    tags:
      - app
```

`helm dependency build` packages the directory of Chapter 27's chart into `charts/` and records its digest in `Chart.lock`. Because the repository is a path in the same repository, the wrapper always renders the chart as it is today. A change to Chapter 27's chart reaches the appendix on the next build, and CI builds on every push, so the two cannot drift apart without a check failing.

What the wrapper leaves out matters as much as what it adds. It has no template for a Deployment, a Service or a ConfigMap, so there is nothing to keep in step with the chart when the chart gains a probe or a stack. It holds no copy of the Containerfiles or the sources either: the builds read Chapter 27's directories. A reader who removes the `final:` block and the `openshift:` block has the dependency's defaults, which are the minikube tier again.

Figure A.1 shows the three parts. On the left are the values Chapter 27 uses on minikube: NodePort Services, `imagePullPolicy: Never` for images loaded into the node, and an edge that terminates TLS 1.3 with a certificate the chart generates. On the right is the wrapper. In the middle is the chart, which exposes exactly the keys the wrapper needs: whether the edge terminates TLS, the type of each Service, each image's repository and pull policy, the identity issuer, the headers Keycloak reads behind a proxy, and the observability pod's service account and seccomp profile.

{% include excalidraw.html file="A-same-chart-on-openshift" alt="Three columns. The left column, Chapter 27 values on minikube, holds three boxes: NodePort Services 30370 to 30378 on 127.0.0.1, imagePullPolicy Never with images loaded into the node, and an edge that terminates TLS 1.3 with a chart-generated certificate. The middle column, Chapter 27 chart unchanged, holds an amber box for gql-ch27-final 1.0.0 with edge, quarkus, python, keycloak, lgtm, network policies and the helm test, with no OpenShift kind and no UID, above a box listing the values it exposes. The right column, Appendix A wrapper chart, holds the Chart.yaml dependency with alias final and a file path, the final values for ClusterIP Services, a plain edge and IfNotPresent, and a box for six Routes, two BuildConfigs, two ImageStreams and the anyuid RoleBinding. Amber arrows labelled values, depends on and override point at the middle column. A dashed box below states that application code, Containerfiles and images are the same in every tier." caption="Figure A.1 — One chart, two sets of values. The wrapper depends on Chapter 27's chart and adds only what the platform needs." %}

The overrides are a handful of keys, written as `final:` in the wrapper's `values.yaml`:

- `edge.tls.enabled: false` makes the edge listen on plain ports, 8080 for Quarkus and 8081 for Python, because the router terminates TLS.
- Every Service is `ClusterIP`, including the internal instances, Keycloak and the observability UI. The router is the way in, and each Service has a Route.
- Every image has `pullPolicy: IfNotPresent`. The stack images come from the project's registry and the others from their own registries.
- `identity.issuer` is the `https` URL of the Keycloak Route, and `keycloak.proxyHeaders: xforwarded` lets Keycloak take that URL from the router's forwarded headers.
- `lgtm.serviceAccountName: gql-lgtm`, `lgtm.seccompProfile: ""` and `lgtm.dropAllCapabilities: false` prepare the observability pod for its binding, in the next section.

The same keys and values are in `examples/27-final-project/helm/ci-values-appendix-a.yaml`, which Chapter 27's CI step renders on every push. That file proves that the chart accepts the overrides. The wrapper's values prove that the release is complete.

## Projects and restricted-v2

An OpenShift project is a namespace with an owner and a default set of rules. One of the rules is the security context constraint that admits a pod. The default, `restricted-v2`, assigns each project a range of user ids and runs each pod as one id from that range, with group 0, with every capability dropped and privilege escalation off. A pod that asks for a particular user id outside the range is not admitted.

Chapter 26 anticipated this. The chart sets `runAsNonRoot`, drops all capabilities, forbids privilege escalation and selects the runtime-default seccomp profile, and it never sets `runAsUser`, `runAsGroup` or `fsGroup`. Its `values.schema.json` rejects those keys. The images hold up their end: the UBI images run as a numeric non-root user and accept whichever id the platform assigns, the writable paths are `emptyDir` volumes (nginx's `/tmp`, Keycloak's data directory), and group 0 owns what the images write. On OpenShift the same release therefore runs each pod as an id from the project's range, without a line changed.

Any pod's constraint is one command away, because the platform records the constraint that admitted a pod in an annotation:

```bash
oc --context crc-admin -n gql-appendix-a get pods \
  -o custom-columns='POD:.metadata.name,SCC:.metadata.annotations.openshift\.io/scc'
```

One image asks for something else. `grafana/otel-lgtm` runs as root and writes under its own directories. The chart already has a value for the service account its pod uses, `lgtm.serviceAccountName`, empty by default. The wrapper sets it and creates the account with a binding, which renders as:

```yaml
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:openshift:scc:anyuid
subjects:
  - kind: ServiceAccount
    name: gql-lgtm
    namespace: gql-appendix-a
```

The binding is in `templates/lgtm-anyuid-rolebinding.yaml`, and it grants the `anyuid` constraint to one service account in one project. The `anyuid` constraint admits a pod that names no seccomp profile, so the wrapper also sets `final.lgtm.seccompProfile` to an empty string, and the chart leaves the profile out of that one pod. The image creates its data directories in a root directory that only root with `CAP_DAC_OVERRIDE` can write, so the wrapper also sets `final.lgtm.dropAllCapabilities` to `false` and the container keeps the constraint's default capability set; privilege escalation stays off. The image needs its own root user, so `lgtm` is the only pod of the release that runs outside `restricted-v2`: the smoke script reads the `openshift.io/scc` annotation of each pod and expects `restricted-v2` for the six application workloads and `anyuid` for `lgtm`. A reader who replaces the image with one that runs as a non-root user sets `openshift.anyuid.enabled` to `false`, `final.lgtm.seccompProfile` back to `RuntimeDefault` and `final.lgtm.dropAllCapabilities` back to `true`, and the pod then runs under the default like the others.

## Building in the cluster

Chapter 26 built the images with `docker build` and loaded them into the node. OpenShift Local has an image registry inside the cluster, and a BuildConfig that builds into it, so the host needs no container engine. The wrapper creates one BuildConfig and one ImageStream for each stack, and it derives both from the values the chart already has. The image stream's name is the last segment of `final.stacks.<stack>.image.repository`, and its tag is `final.stacks.<stack>.image.tag`. A reader who renames an image changes one value.

The values for each stack show the registry path the Deployment reads:

{% include codetabs.html langs="Quarkus|Python" %}

```yaml
    quarkus:
      image:
        repository: image-registry.openshift-image-registry.svc:5000/gql-appendix-a/gql-ch27-quarkus
        tag: "1.0"
        pullPolicy: IfNotPresent
```

```yaml
    python:
      image:
        repository: image-registry.openshift-image-registry.svc:5000/gql-appendix-a/gql-ch27-python
        tag: "1.0"
        pullPolicy: IfNotPresent
```

The BuildConfig uses the Docker strategy and a binary source: it holds no repository address, and the build input is whatever `oc start-build` uploads. The Containerfile is Chapter 27's, with no change to the pom and no OpenShift profile, and its path inside the uploaded directory is `Containerfile`. Both build stages run as root, so Maven and uv can create their output under the build directory, and both runtime stages run as the image's non-root user; `up.sh` uploads each directory as it is:

```bash
oc --context crc-admin -n gql-appendix-a start-build gql-ch27-quarkus \
  --from-dir examples/27-final-project/quarkus --follow --wait
```

Figure A.2 follows one image. The command uploads the directory as an archive, the BuildConfig starts a build pod that runs the Containerfile's two stages, Maven on `ubi10/openjdk-25` and then the runtime image, and the build pushes the result to the stream's `1.0` tag. The Deployment's image reference then names that tag in the internal registry. The build pod resolves Maven and uv dependencies from inside the cluster, so the BuildConfig asks for 1 CPU and 2 GiB, with limits of 4 CPU and 4 GiB.

{% include excalidraw.html file="A-in-cluster-build" alt="A left-to-right flow in two bands. In the Host band, a blue box shows oc start-build gql-ch27-quarkus with from-dir pointing at the quarkus directory of 27-final-project and follow. An amber arrow labelled tar enters the project band at an amber BuildConfig box with a binary source, the Docker strategy and dockerfilePath Containerfile. Arrows continue to a build pod that runs the Containerfile with Maven and then the runtime image on ubi10 openjdk-25, to an ImageStream gql-ch27-quarkus with tag 1.0 pushed to the internal registry, and to a Deployment named quarkus whose image comes from the internal registry under gql-appendix-a. A dashed box below explains that the tag exists before the pods are created and that the pod then starts under restricted-v2 with the UID the project assigns." caption="Figure A.2 — One image, built where it runs. The values come from the rendered manifests; the figure shows no cluster output." %}

The order matters, and `up.sh` makes it explicit. A Deployment that references a tag that does not exist yet would wait on the pull. The wrapper therefore tags the dependency with `app`, and the first install sets `tags.app=false`: Helm then renders only the wrapper's own objects, the two BuildConfigs, the two ImageStreams and the Routes. The script builds both images, checks that each tag exists, and upgrades the same release with the application on. The first release revision holds the build objects and the second adds everything else.

## Routes

A Route is the platform's way in. The router, HAProxy running in the cluster, listens on the wildcard domain of the cluster and sends each host to a Service. The wrapper renders six Routes from a map in its values, and each host is `<route>-<project>.<domain>`: `quarkus-gql-appendix-a.apps-crc.testing`, for example. Figure A.3 shows where each goes.

{% include excalidraw.html file="A-route-to-edge" alt="Inside the band OpenShift Local, project gql-appendix-a, a blue client box labelled curl with the ingress CA and HTTPS, WSS and SSE sends an amber arrow to an amber router box that terminates edge TLS with the ingress certificate, redirects HTTP, and keeps connections open for one hour on the edge Routes. Four arrows leave the router. The first reaches Routes quarkus and python, which send plain HTTP to the edge Service on ports 8080 and 8081, which reaches the nginx edge with its 64k limit and routes for graphql and events, which reaches the public instances on ClusterIP port 8080 with introspection off. The second reaches Routes quarkus-internal and python-internal with edge TLS, which reach the internal instances with introspection on. The third reaches the Route keycloak with edge TLS, which reaches Keycloak 26.8.1 whose issuer is the https URL of the Route. The fourth reaches the Route grafana with edge TLS, which reaches the lgtm pod." caption="Figure A.3 — The Routes of the release. TLS ends at the router, and everything behind it speaks plain HTTP inside the project." %}

The Routes for the two stacks target the edge Service, not the backends. This keeps what the edge does for the compose tier and the minikube tier: the body limit, the routing of `/graphql` and `/events/` and nothing else, and the upgrade headers that a WebSocket needs. The edge Service names its ports `quarkus` and `python`, and each Route selects one by name, so the Route for Quarkus reaches 8080 and the Route for Python reaches 8081 without a number in the wrapper:

{% raw %}
```yaml
  to:
    kind: Service
    name: {{ $route.service }}
    weight: 100
  port:
    targetPort: {{ $route.port }}
```
{% endraw %}

The TLS stanza is the one the platform documents for a secured Route. The router terminates TLS with the cluster's ingress certificate, forwards plain HTTP to the Service, and redirects a plain HTTP request to HTTPS:

```yaml
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

The two Routes of the edge carry one annotation more, `haproxy.router.openshift.io/timeout: 1h`. A subscription and an event feed stay open and idle between events, and Chapter 27's edge sets the same hour for its own proxy timeouts. The WebSocket upgrade and the server-sent events need nothing else from the router.

Clients verify the certificate with the cluster's ingress CA, which lives in a ConfigMap in `openshift-config-managed`: `oc get configmap default-ingress-cert` and `-o jsonpath='{.data.ca-bundle\.crt}'` give the PEM file, and `curl --cacert` uses it. No script uses `--insecure`, and the smoke script passes the file to the harness as `LGTM_CACERT`, so every GraphQL helper verifies the same chain.

The edge Routes are the only entry to the public instances, which is the property Chapter 25 built the edge for: a request that reaches a stack has been through the body limit and the routing rules first, and the lab endpoints under `/debug` are not routed, so the smoke script reads the source-call log inside the pod with `oc exec`, as Chapter 27's script does.

The internal instances and Grafana have Routes of their own, because a developer reaches them from the host as before: the internal instances answer introspection, and the smoke script compares each with the canonical SDL through `assert_sdl_equals`. The public instances have no Route at all. A caller reaches them through the edge.

## Identity on Routes

Chapter 27 explained the two addresses that Keycloak has: the back channel that the stacks read signing keys from, `keycloak:8080` inside the project, and the issuer, which is the address a client fetched its token from. A token carries the address its client used, and the stacks compare it with a pinned string. In the minikube tier the string is `http://localhost:30374/realms/shipping`. On OpenShift Local clients reach Keycloak through its Route, so the issuer is that Route's URL:

```yaml
  identity:
    issuer: https://keycloak-gql-appendix-a.apps-crc.testing/realms/shipping
```

The Keycloak Route terminates TLS at the router like the others, and the router passes the client's scheme and host on in `X-Forwarded-Proto` and `X-Forwarded-Host`. The wrapper sets `final.keycloak.proxyHeaders: xforwarded`, which the chart hands to Keycloak as `KC_PROXY_HEADERS`, so Keycloak builds the issuer from those headers and a token fetched at the Route carries exactly this URL. A request on the back channel carries no such headers, so `authServerUrl` is not overridden. The realm of Chapter 18 sets `sslRequired` to `none`, as it does in every tier, because the back channel inside the project is plain HTTP.

`up.sh` does not assume the domain. It reads it from the cluster, `oc get ingresses.config.openshift.io cluster`, and passes `openshift.domain` and `final.identity.issuer` to Helm. The values file carries the same strings for `apps-crc.testing`, so a render without a cluster is complete. The chart writes the value into each instance's ConfigMap under the key the stack reads, as the rendered release shows, and no code reads a tier:

{% include codetabs.html langs="Quarkus|Python" %}

```yaml
QUARKUS_OIDC_TOKEN_ISSUER: "https://keycloak-gql-appendix-a.apps-crc.testing/realms/shipping"
```

```yaml
TRACKING_OIDC_ISSUER: "https://keycloak-gql-appendix-a.apps-crc.testing/realms/shipping"
```

The smoke script fetches tokens at the Route for `ana` and `ops`, and a query with each of them proves that both stacks accept an issuer that is a Route's URL.

## What CI checks

The appendix has no cluster in CI, so it checks what can be checked offline, in the `k8s-manifests` job, with the same commands a reader runs. First, `helm dependency build` restores `charts/` from `Chart.lock`. `helm lint --strict` then checks the wrapper, and its dependency, against the dependency's `values.schema.json`, which accepts the service account name and rejects any key that sets a user id.

Then the release is rendered and validated with `kubeconform -strict` against the Kubernetes 1.35.6 schemas, the version OpenShift 4.22.14 ships. Kubernetes' own schemas know nothing about a Route, a BuildConfig or an ImageStream, so the command adds a second schema location, the `datreeio/CRDs-catalog` repository pinned to one commit, which holds the `openshift/v4.15-strict` schemas for the three kinds. Route, BuildConfig and ImageStream are v1 APIs and have not changed shape since. `-ignore-missing-schemas` is not used: a kind without a schema fails the step instead of passing unchecked. The location is a template over the kind, the group and the API version, and for a Route it resolves to `route_route.openshift.io_v1.json`; its two siblings resolve the same way. The full command is in "On the wire".

Last, ShellCheck v0.11.0 checks the scripts and `bash -n` parses them. A grep of the render for `runAsUser`, `runAsGroup` and `fsGroup` finds nothing: no pod names a user id, so each pod under `restricted-v2` takes an id from the project's range, and the `lgtm` pod under `anyuid` runs as its image's own user.

## Running it

Only the user starts a cluster, and one cluster runs at a time. The order is fixed:

1. Stop minikube with `minikube stop -p gql-tracking`. `require_crc` in `scripts/lib.sh` refuses to continue beside a running profile and names the commands that stop it; it never stops one.
2. `crc start`, then `eval "$(crc oc-env)"` to put `oc` on the path. The scripts use the `crc-admin` context that `crc start` writes, and they check that its API server is `api.crc.testing`, so they cannot reach a different cluster by accident. No password is typed or stored.
3. Run `scripts/up.sh`. It takes the inventory first, which is read-only: the non-system namespaces, the Subscriptions and ClusterServiceVersions, and the CRDs, saved under `~/.local/state/gql-appendix-a/`. Then it creates the project with `oc new-project --skip-config-write`, which leaves the kubeconfig alone, installs the build objects, builds both images with `--follow`, installs the application, waits with `oc rollout status` for each of the seven Deployments, prints each pod's constraint, and runs `helm test`.
4. Run `scripts/smoke.sh`.
5. Run `scripts/down.sh`.

`oc rollout status` waits for the new ReplicaSet to be ready. `condition=Available` can be true while an old ReplicaSet still serves, which is why the script uses the rollout form.

## Leaving it clean

OpenShift Local is cleaned after each use, because the machine belongs to one piece of work at a time. `down.sh` has five steps, in this order. It runs `helm uninstall` with `--wait`. It deletes the project, which removes BuildConfigs, ImageStreams, builds, the RoleBinding and every pod with it, and waits until the namespace is gone. It removes the operators this appendix installed. The appendix installs none, so the `OPERATORS` list is empty, and the loop is there for the same reason a teardown has one in any project that uses OperatorHub: it deletes each Subscription, reads the installed ClusterServiceVersion and its owned CRDs before deleting it, then removes the InstallPlans and the CRDs. An operator added later is removed by one new line in the list.

The fourth step is the check. `down.sh` lists the namespaces, the Subscriptions and ClusterServiceVersions and the CRDs again and compares them with the inventory `up.sh` saved. An item that is present now and was not before is printed, left alone, and makes the script finish with a failure after the last step. Nothing in the comparison deletes anything: the script removes what the appendix created and reports the rest. The inventory stays until the next `up.sh` on a cluster without the project replaces it, so a second `down.sh` compares against the same baseline. The layers the builds pushed are unreferenced once the image streams are gone; the cluster's image pruner removes unreferenced images on its schedule. The fifth step is `crc stop`, unless `--keep-running` was given, and it stops the cluster; it does not delete it.

If OpenShift Local is not running, `down.sh` says so and exits: there is nothing to remove from a stopped cluster.

## On the wire

These are the static commands, run from the repository root with Helm v4.3.1, kubeconform v0.8.0 and ShellCheck v0.11.0, and their recorded output. Build the dependency and lint:

```bash
helm dependency build examples/99-appendix-a-openshift-crc/helm
helm lint --strict examples/99-appendix-a-openshift-crc/helm
```

```text
Saving 1 charts
Deleting outdated charts
==> Linting examples/99-appendix-a-openshift-crc/helm
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

Render and validate against the Kubernetes and OpenShift schemas:

{% raw %}
```bash
helm template gql-appendix-a examples/99-appendix-a-openshift-crc/helm -n gql-appendix-a \
  | kubeconform -strict -summary -kubernetes-version 1.35.6 \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/63669a570e231d4f1f8396d229a1de512bcf0a34/openshift/v4.15-strict/{{ .ResourceKind }}_{{ .Group }}_{{ .ResourceAPIVersion }}.json'
```
{% endraw %}

```text
Summary: 40 resources found parsing stdin - Valid: 40, Invalid: 0, Errors: 0, Skipped: 0
```

The 40 objects are 2 BuildConfigs, 6 ConfigMaps, 7 Deployments, 2 ImageStreams, 5 NetworkPolicies, the helm test Pod, 1 RoleBinding, 6 Routes, 1 Secret, 8 Services and 1 ServiceAccount. Nothing is skipped, so each Route, BuildConfig and ImageStream was checked against its schema. The first install of `up.sh` renders a subset, which the same command shows with `--set tags.app=false`:

```bash
helm template gql-appendix-a examples/99-appendix-a-openshift-crc/helm -n gql-appendix-a \
  --set tags.app=false | grep -E '^kind' | sort | uniq -c
```

```text
      2 kind: BuildConfig
      2 kind: ImageStream
      6 kind: Route
```

The pods ask for no user id:

```bash
helm template gql-appendix-a examples/99-appendix-a-openshift-crc/helm -n gql-appendix-a \
  | grep -nE 'runAsUser|runAsGroup|fsGroup'
```

The command prints nothing and exits `1`. Check the scripts:

```bash
shellcheck -x examples/99-appendix-a-openshift-crc/scripts/*.sh
```

ShellCheck prints nothing and exits `0`.

The live run was recorded on 2026-10-17 with `crc` 2.64.0, OpenShift 4.22.14 (Kubernetes v1.35.6) and `oc` 4.22.14, on a cluster that held no operator and no project besides the system ones. `crc start` took 5 min 38 s. `up.sh` took 2 min 1 s on a node that already held the base images: the Quarkus build ran for 84 s and the Python build for 21 s, and the first pull of the observability image took 30 s. `smoke.sh` took 15 s, `down.sh` 33 s and `crc stop` 1 min 13 s. With OpenShift Local running and `oc` on the path:

```bash
examples/99-appendix-a-openshift-crc/scripts/up.sh
examples/99-appendix-a-openshift-crc/scripts/smoke.sh
curl --cacert ingress-ca.crt -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' \
  https://quarkus-gql-appendix-a.apps-crc.testing/graphql
examples/99-appendix-a-openshift-crc/scripts/down.sh
```

The end of `up.sh`, with the build pods left out of the table:

```text
==> scc of each pod
POD                                SCC
edge-7cc66799c5-s4ntl              restricted-v2
keycloak-6f7ffdd544-ns657          restricted-v2
lgtm-547c859f75-dpvml              anyuid
python-65bcb45946-wn2q4            restricted-v2
python-internal-5db8ddfc76-4wl99   restricted-v2
quarkus-7cdc4fdcf7-hf5nc           restricted-v2
quarkus-internal-7cf8c989d-v99s6   restricted-v2

==> helm test gql-appendix-a
Phase:          Succeeded

quarkus {"data":{"__typename":"Query"}}
quarkus {"errors":[{"message":"authentication required","locations":[{"line":1,"column":3}],"path":["cargo"],"extensions":{"code":"UNAUTHENTICATED","t
quarkus /debug/source-calls 404
python {"data":{"__typename":"Query"}}
python {"data":{"cargo":null},"errors":[{"message":"authentication required","locations":[{"line":1,"column":3}],"path":["cargo"],"extensions":{"code"
python /debug/source-calls 404
keycloak {"realm":"shipping","public_key":"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwJ85t9fzadmWuN18hiLajnRWRdj6y36uV
helm test: both stacks answer through the edge and keycloak serves the realm

==> up: gql-appendix-a is deployed and tested; run scripts/smoke.sh
```

The checks of `smoke.sh` that carry a value, in the order it prints them:

```text
=== the release and the ingress CA ===
lib.sh: ok — quarkus runs under restricted-v2: 'restricted-v2'
lib.sh: ok — python runs under restricted-v2: 'restricted-v2'
lib.sh: ok — quarkus-internal runs under restricted-v2: 'restricted-v2'
lib.sh: ok — python-internal runs under restricted-v2: 'restricted-v2'
lib.sh: ok — edge runs under restricted-v2: 'restricted-v2'
lib.sh: ok — keycloak runs under restricted-v2: 'restricted-v2'
lib.sh: ok — lgtm runs under anyuid: 'anyuid'
lib.sh: ok — keycloak: a plain HTTP request is redirected to HTTPS: HTTP 302 (allowed: 301 302 308)
=== tokens from Keycloak at its Route, the issuer the stacks pin ===
=== verifying stack 'quarkus' through the Route at https://quarkus-gql-appendix-a.apps-crc.testing/graphql ===
lib.sh: ok — quarkus: a plain HTTP request is redirected to HTTPS: HTTP 302 (allowed: 301 302 308)
lib.sh: ok — quarkus internal schema equals the canonical SDL: live schema equals the canonical SDL
lib.sh: ok — quarkus: a 100 KB body is refused at the edge: '413'
lib.sh: ok — quarkus ana sees her three cargos: ["VWX901", "DEF456", "ABC123"]
lib.sh: ok — quarkus OverBudget: message: 'maximum query complexity exceeded 7651 > 1000'
lib.sh: ok — quarkus FanOut: 8 source calls, read inside the pod: 8 call(s) to *.*
lib.sh: ok — quarkus: Tempo holds trace 3d72e62cb68d7c6eb2bf79a6506245a1 (^query ListCargos$)
=== verifying stack 'python' through the Route at https://python-gql-appendix-a.apps-crc.testing/graphql ===
lib.sh: ok — python: a plain HTTP request is redirected to HTTPS: HTTP 302 (allowed: 301 302 308)
lib.sh: ok — python internal schema equals the canonical SDL: live schema equals the canonical SDL
lib.sh: ok — python: a 100 KB body is refused at the edge: '413'
lib.sh: ok — python ana sees her three cargos: ["VWX901", "DEF456", "ABC123"]
lib.sh: ok — python OverBudget: message: 'maximum query complexity exceeded 7651 > 1000'
lib.sh: ok — python FanOut: 6 source calls, read inside the pod: 6 call(s) to *.*
lib.sh: ok — python: Tempo holds trace db57c7b9a8154a71e8aa9aab3984881f (^GraphQL Query: ListCargos$)
PASS - Appendix A Chapter 27 on OpenShift Local: the release is deployed under restricted-v2 with the observability pod under anyuid; [the remaining clauses of the line are omitted]
```

`down.sh` printed `the cluster matches the inventory taken before the run`, and a comparison of Subscriptions, ClusterServiceVersions, CustomResourceDefinitions, namespaces and cluster role bindings before and after was identical.

`smoke.sh` prints `PASS` when the release is deployed under the expected constraints, both stacks accept tokens fetched at the Keycloak Route, the edge refuses a 100 KB body with `413` and routes only `/graphql` and `/events/`, the internal instances equal the canonical SDL, an over-budget document is refused before any source call, a `FanOut` makes eight source calls on Quarkus and six on Python, and a trace id sent through the Route is found in Tempo and names the pod.

## Decision

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>The appendix settles Chapter 2's axes by what stays constant. <em>Contract and evolution style</em> is unchanged: the schema is the canonical SDL on every tier, and the smoke script compares the internal instances with it through Routes. <em>Operational and security cost</em> moves to the platform: the router terminates TLS and the project assigns the user id, so the chart carries one binding for the one image that asks for root, and nothing else. <em>Aggregation across sources</em> and <em>client diversity and shape variance</em> cost nothing more, because the edge, the batched sources and the transports are the same objects in the same chart. A team that wants to leave the platform keeps the chart and drops the wrapper, which is a directory of Routes, builds and one binding.</p></div>

## Where this goes next

This appendix ran Chapter 27's chart on OpenShift Local through a wrapper that adds Routes with edge TLS at the router, Docker-strategy builds into image streams, the `restricted-v2` constraint for every workload and `anyuid` for the one image that needs it, with an issuer that is a Route's URL and a teardown that compares the cluster with an inventory.

That completes the book's path from a schema to a system that runs in three places. The bibliography lists the specifications and books behind the whole. For this appendix, read the OpenShift documentation pages "Route configuration" and "Secured routes", "Builds using BuildConfig" for the Docker strategy and binary builds, "Managing image streams" and "Managing security context constraints"; Red Hat OpenShift Local's "Getting started" guide for `crc start` and `crc oc-env`; Helm's "Chart Dependencies"; and the kubeconform README for `-schema-location`. Chapters 26 and 27 hold the chart this appendix wraps.

## For deeper coverage

- *Cloud Native Design Patterns*, Appendix S — "Running Example 05 on OpenShift Local": the same restricted-v2 / pinned-CSV / edge-TLS-Route pattern, applied to a different example.
- [OpenShift — Route configuration](https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html)
- [OpenShift — Builds using BuildConfig](https://docs.openshift.com/container-platform/latest/cicd/builds/understanding-image-builds.html) — the Docker strategy and binary source this appendix's `BuildConfig`s use.
- [OpenShift — Managing security context constraints](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html) — `restricted-v2` and `anyuid`.
- [Red Hat OpenShift Local — Getting Started](https://crc.dev/crc/getting_started/) — `crc start` and `crc oc-env`.
