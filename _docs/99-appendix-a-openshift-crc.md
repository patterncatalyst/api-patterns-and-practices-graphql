---
title: "Appendix A: OpenShift Local (CRC)"
order: 99
part: "Running It & the Final Project"
appendix: true
appendix_label: "A"
description: "The final project's chart on OpenShift Local through a wrapper chart: in-cluster builds, Routes with edge TLS, restricted-v2 for every pod but one, and a teardown that returns the cluster to its starting state."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Wrap an existing Helm chart in a dependency-only chart that adds `Route`s, `BuildConfig`s, `ImageStream`s, and one `RoleBinding`, without touching the wrapped chart.
- Build an image inside the cluster with a binary-source, Docker-strategy `BuildConfig`, with no container engine on the host.
- Run every pod under `restricted-v2`, and grant `anyuid` to exactly one service account for the one image that needs a root user.
- Terminate TLS at the router with an edge `Route`, and point an identity provider's issuer at that Route's URL.
- Tear down a CRC project against a saved inventory so a script-driven run leaves no orphaned namespace, `Subscription`, or CRD.

## Why this matters

The final project's chart is neutral. It names no distribution, sets no user id, and renders nothing that only one platform understands. Running it on a different distribution, OpenShift Local, tests that claim and counts what had to be added.

Nothing is added to the application or its images, and the chart gains one value, `lgtm.dropAllCapabilities`, whose default renders the chart as before. It is one wrapper chart and four scripts. The wrapper depends on the final project's chart and adds what a platform with a router and an image registry wants: Routes, builds, image streams, and one binding for a security context constraint. OpenShift Local is a demonstration target, as minikube is the main one. On another Kubernetes distribution, read this appendix as a list of the places where a platform differs and the one place per difference where the chart accommodates it.

There is no `verify.sh`, because a cluster is something a person starts and keeps. A run of `up.sh`, `smoke.sh` and `down.sh` was recorded on 2026-10-17; the chart and scripts are also validated offline. Pins: OpenShift Local 2.64.0, which bundles OpenShift 4.22.14 and Kubernetes 1.35.6.

## Same chart, another distribution

The wrapper's `Chart.yaml` has one dependency:

```yaml
dependencies:
  # The final project's chart, as it is in examples/27-final-project/helm.
  # `helm dependency build` packages it into charts/. The `app` tag lets the
  # first install create only the build objects (see scripts/up.sh).
  - name: gql-ch27-final
    version: 1.0.0
    repository: file://../../27-final-project/helm
    alias: final
    tags:
      - app
```

`helm dependency build` packages the final project's chart into `charts/` and records its digest in `Chart.lock`. The repository is a path in the same repository, so the wrapper always renders the chart as it is today, and CI builds on every push, so the two can't drift apart without a check failing.

The wrapper has no template for a Deployment, a Service or a ConfigMap, so there is nothing to keep in step when the chart gains a probe or a stack. It holds no copy of the Containerfiles or the sources: the builds read the final project's directories. Remove the `final:` and `openshift:` blocks and the dependency's defaults, the minikube tier, remain.

{% include excalidraw.html file="A-same-chart-on-openshift" alt="Three columns. The left column, final project values on minikube, holds three boxes: NodePort Services 30370 to 30378 on 127.0.0.1, imagePullPolicy Never with images loaded into the node, and an edge that terminates TLS 1.3 with a chart-generated certificate. The middle column, final project chart unchanged, holds an amber box for gql-ch27-final 1.0.0 with edge, quarkus, python, keycloak, lgtm, network policies and the helm test, with no OpenShift kind and no UID, above a box listing the values it exposes. The right column, Appendix A wrapper chart, holds the Chart.yaml dependency with alias final and a file path, the final values for ClusterIP Services, a plain edge and IfNotPresent, and a box for six Routes, two BuildConfigs, two ImageStreams and the anyuid RoleBinding. Amber arrows labelled values, depends on and override point at the middle column. A dashed box below states that application code, Containerfiles and images are the same in every tier." caption="Figure A.1: One chart, two sets of values. The wrapper depends on the final project's chart and adds only what the platform needs." %}

The chart exposes exactly the keys the wrapper needs: whether the edge terminates TLS, the type of each Service, each image's repository and pull policy, the identity issuer, the headers Keycloak reads behind a proxy, and the observability pod's service account and seccomp profile. The wrapper sets them under `final:`:

- `edge.tls.enabled: false` makes the edge listen on plain ports, 8080 for Quarkus and 8081 for Python, because the router terminates TLS.
- Every Service is `ClusterIP`, including the internal instances, Keycloak and the observability UI. Each has a Route.
- Every image has `pullPolicy: IfNotPresent`.
- `identity.issuer` is the `https` URL of the Keycloak Route, and `keycloak.proxyHeaders: xforwarded` lets Keycloak take that URL from the router's forwarded headers.
- `lgtm.serviceAccountName: gql-lgtm`, `lgtm.seccompProfile: ""` and `lgtm.dropAllCapabilities: false` prepare the observability pod for its binding.

The same keys are in `examples/27-final-project/helm/ci-values-appendix-a.yaml`, which the final project's CI renders on every push. That file proves the chart accepts the overrides; the wrapper's values prove the release is complete.

## Projects and restricted-v2

An OpenShift project is a namespace with an owner and a default set of rules, including the security context constraint that admits a pod. The default, `restricted-v2`, assigns each project a range of user ids, runs each pod as one id from that range with group 0, drops every capability and turns privilege escalation off. A pod that asks for a user id outside the range is not admitted.

The chart already anticipates this. It sets `runAsNonRoot`, drops all capabilities, forbids privilege escalation, selects the runtime-default seccomp profile, and never sets `runAsUser`, `runAsGroup` or `fsGroup`; its `values.schema.json` rejects those keys. The UBI images run as a numeric non-root user and accept whichever id the platform assigns, the writable paths are `emptyDir` volumes, and group 0 owns what the images write. The same release therefore runs each pod as an id from the project's range without a changed line.

The platform records the constraint that admitted a pod in an annotation:

```bash
oc --context crc-admin -n gql-appendix-a get pods \
  -o custom-columns='POD:.metadata.name,SCC:.metadata.annotations.openshift\.io/scc'
```

One image asks for something else. `grafana/otel-lgtm` runs as root and writes under its own directories. The chart has a value for the service account its pod uses, `lgtm.serviceAccountName`, empty by default. The wrapper sets it and creates the account with a binding in `templates/lgtm-anyuid-rolebinding.yaml`, which renders as:

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

That grants `anyuid` to one service account in one project. Two more settings follow from it:

- `anyuid` admits a pod that names no seccomp profile, so `final.lgtm.seccompProfile` is an empty string and the chart leaves the profile out of that pod.
- The image creates its data directories where only root with `CAP_DAC_OVERRIDE` can write, so `final.lgtm.dropAllCapabilities` is `false` and the container keeps the constraint's default capability set. Privilege escalation stays off.

`lgtm` is the only pod that runs outside `restricted-v2`. With an image that runs as a non-root user, set `openshift.anyuid.enabled` to `false`, `final.lgtm.seccompProfile` back to `RuntimeDefault` and `final.lgtm.dropAllCapabilities` back to `true`, and the pod runs under the default like the others.

## Building in the cluster

OpenShift Local has an image registry inside the cluster and a BuildConfig that builds into it, so the host needs no container engine. The wrapper creates one BuildConfig and one ImageStream for each stack and derives both from values the chart already has: the stream's name is the last segment of `final.stacks.<stack>.image.repository`, and its tag is `final.stacks.<stack>.image.tag`. Renaming an image changes one value. The values show the registry path the Deployment reads:

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

The BuildConfig uses the Docker strategy and a binary source: it holds no repository address, and the build input is whatever `oc start-build` uploads. The Containerfile is the final project's, with no change to the pom and no OpenShift profile. Both build stages run as root so Maven and uv can create their output under the build directory, and both runtime stages run as the image's non-root user.

```bash
oc --context crc-admin -n gql-appendix-a start-build gql-ch27-quarkus \
  --from-dir examples/27-final-project/quarkus --follow --wait
```

{% include excalidraw.html file="A-in-cluster-build" alt="A left-to-right flow in two bands. In the Host band, a blue box shows oc start-build gql-ch27-quarkus with from-dir pointing at the quarkus directory of 27-final-project and follow. An amber arrow labelled tar enters the project band at an amber BuildConfig box with a binary source, the Docker strategy and dockerfilePath Containerfile. Arrows continue to a build pod that runs the Containerfile with Maven and then the runtime image on ubi10 openjdk-25, to an ImageStream gql-ch27-quarkus with tag 1.0 pushed to the internal registry, and to a Deployment named quarkus whose image comes from the internal registry under gql-appendix-a. A dashed box below explains that the tag exists before the pods are created and that the pod then starts under restricted-v2 with the UID the project assigns." caption="Figure A.2: One image, built where it runs. The BuildConfig receives the uploaded directory, builds in a pod and pushes to the image stream the Deployment reads." %}

The build pod resolves Maven and uv dependencies from inside the cluster, so the BuildConfig asks for 1 CPU and 2 GiB, with limits of 4 CPU and 4 GiB.

Order matters. A Deployment that references a tag that does not exist yet waits on the pull. The wrapper therefore tags the dependency `app`, and the first install sets `tags.app=false`, so Helm renders only the two BuildConfigs, the two ImageStreams and the Routes. `up.sh` builds both images, checks that each tag exists, and upgrades the same release with the application on. The first revision holds the build objects and the second adds everything else.

## Routes

The router, HAProxy running in the cluster, listens on the wildcard domain of the cluster and sends each host to a Service. The wrapper renders six Routes from a map in its values, each host `<route>-<project>.<domain>`, for example `quarkus-gql-appendix-a.apps-crc.testing`.

{% include excalidraw.html file="A-route-to-edge" alt="Inside the band OpenShift Local, project gql-appendix-a, a blue client box labelled curl with the ingress CA and HTTPS, WSS and SSE sends an amber arrow to an amber router box that terminates edge TLS with the ingress certificate, redirects HTTP, and keeps connections open for one hour on the edge Routes. Four arrows leave the router. The first reaches Routes quarkus and python, which send plain HTTP to the edge Service on ports 8080 and 8081, which reaches the nginx edge with its 64k limit and routes for graphql and events, which reaches the public instances on ClusterIP port 8080 with introspection off. The second reaches Routes quarkus-internal and python-internal with edge TLS, which reach the internal instances with introspection on. The third reaches the Route keycloak with edge TLS, which reaches Keycloak 26.8.1 whose issuer is the https URL of the Route. The fourth reaches the Route grafana with edge TLS, which reaches the lgtm pod." caption="Figure A.3: The Routes of the release. TLS ends at the router, and everything behind it speaks plain HTTP inside the project." %}

The Routes for the two stacks target the edge Service, not the backends, which keeps what the edge does in every tier: the body limit, the routing of `/graphql` and `/events/` and nothing else, and the upgrade headers a WebSocket needs. The edge Service names its ports `quarkus` and `python`, and each Route selects one by name, so no port number appears in the wrapper:

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

The router terminates TLS with the cluster's ingress certificate, forwards plain HTTP to the Service, and redirects a plain HTTP request to HTTPS:

```yaml
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

The two Routes of the edge carry one annotation more, `haproxy.router.openshift.io/timeout: 1h`, because a subscription and an event feed stay open and idle between events, and the edge sets the same hour for its own proxy timeouts. The WebSocket upgrade and server-sent events need nothing else from the router.

Clients verify the certificate with the cluster's ingress CA, in the ConfigMap `default-ingress-cert` in `openshift-config-managed`: `-o jsonpath='{.data.ca-bundle\.crt}'` gives the PEM file, and `curl --cacert` uses it, as does every GraphQL helper through `LGTM_CACERT`. No script uses `--insecure`.

The edge Routes are the only entry to the public instances: a request that reaches a stack has been through the body limit and the routing rules, and the lab endpoints under `/debug` are not routed, so the smoke script reads the source-call log inside the pod with `oc exec`. The internal instances and Grafana have Routes of their own, because a developer reaches them from the host; the smoke script compares each internal instance with the canonical SDL through `assert_sdl_equals`. The public instances have no Route; a caller reaches them only through the edge.

## Identity on Routes

Keycloak has two addresses: the back channel the stacks read signing keys from, `keycloak:8080` inside the project, and the issuer, the address a client fetched its token from. In the minikube tier the issuer is `http://localhost:30374/realms/shipping`. On OpenShift Local clients reach Keycloak through its Route, so the issuer is that Route's URL:

```yaml
  identity:
    issuer: https://keycloak-gql-appendix-a.apps-crc.testing/realms/shipping
```

The Keycloak Route terminates TLS at the router like the others, and the router passes the client's scheme and host in `X-Forwarded-Proto` and `X-Forwarded-Host`. The wrapper sets `final.keycloak.proxyHeaders: xforwarded`, which the chart hands to Keycloak as `KC_PROXY_HEADERS`, so Keycloak builds the issuer from those headers and a token fetched at the Route carries exactly this URL. A back-channel request carries no such headers, so `authServerUrl` is not overridden. The realm sets `sslRequired` to `none` in every tier, because the back channel is plain HTTP.

`up.sh` reads the domain from the cluster, `oc get ingresses.config.openshift.io cluster`, and passes `openshift.domain` and `final.identity.issuer` to Helm. The values file carries the same strings for `apps-crc.testing`, so a render without a cluster is complete. The chart writes the value into each instance's ConfigMap under the key the stack reads:

{% include codetabs.html langs="Quarkus|Python" %}

```yaml
QUARKUS_OIDC_TOKEN_ISSUER: "https://keycloak-gql-appendix-a.apps-crc.testing/realms/shipping"
```

```yaml
TRACKING_OIDC_ISSUER: "https://keycloak-gql-appendix-a.apps-crc.testing/realms/shipping"
```

Both stacks accept tokens for `ana` and `ops` fetched at the Route.

## Running it

Only the user starts a cluster, and one cluster runs at a time:

1. Stop minikube with `minikube stop -p gql-tracking`. `require_crc` in `scripts/lib.sh` refuses to continue beside a running profile and names the commands that stop it; it never stops one.
2. `crc start`, then `eval "$(crc oc-env)"`. The scripts use the `crc-admin` context that `crc start` writes and check that its API server is `api.crc.testing`, so they can't reach a different cluster by accident. No password is typed or stored.
3. Run `scripts/up.sh`. It saves a read-only inventory first (non-system namespaces, Subscriptions, ClusterServiceVersions and CRDs, under `~/.local/state/gql-appendix-a/`), creates the project with `oc new-project --skip-config-write`, installs the build objects, builds both images with `--follow`, installs the application, waits with `oc rollout status` for each of the seven Deployments, prints each pod's constraint, and runs `helm test`.
4. Run `scripts/smoke.sh`.
5. Run `scripts/down.sh`.

`up.sh` waits with `oc rollout status` because `condition=Available` can be true while an old ReplicaSet still serves.

## Leaving it clean

`down.sh` leaves the cluster as it found it, in five steps:

1. `helm uninstall --wait`.
2. Delete the project, which removes the BuildConfigs, ImageStreams, builds, the RoleBinding and every pod, and wait until the namespace is gone.
3. Remove the operators this appendix installed. It installs none, so the `OPERATORS` list is empty. The loop is there for any project that uses OperatorHub: it deletes each Subscription, reads the installed ClusterServiceVersion and its owned CRDs before deleting it, then removes the InstallPlans and the CRDs. A later operator is one new line in the list.
4. Compare namespaces, Subscriptions, ClusterServiceVersions and CRDs with the inventory `up.sh` saved. An item that is present now and was not before is printed and left alone, and the script fails after the last step. Nothing in the comparison deletes anything. The inventory stays until the next `up.sh` on a clean cluster replaces it, so a second `down.sh` compares against the same baseline.
5. `crc stop`, unless `--keep-running` was given. It stops the cluster and does not delete it.

The cluster's image pruner removes the build layers on its schedule once the image streams are gone. On a stopped cluster `down.sh` says so and exits.

> **Decision**
>
> Keep the chart neutral and put each platform difference in a wrapper: Routes, in-cluster builds and one `anyuid` binding for the one image that needs root. The router terminates TLS and the project assigns the user id, so the contract, the edge and the batched sources stay the same objects in every tier. A team that leaves the platform keeps the chart and drops the wrapper directory.

## Build, run, observe

These are the offline checks, run from the repository root with Helm v4.3.1, kubeconform v0.8.0 and ShellCheck v0.11.0. Build the dependency and lint:

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

Render and validate against the Kubernetes and OpenShift schemas. Kubernetes' own schemas know nothing about a Route, a BuildConfig or an ImageStream, so a second schema location, the `datreeio/CRDs-catalog` repository pinned to one commit, supplies the `openshift/v4.15-strict` schemas. Route, BuildConfig and ImageStream are v1 APIs and have not changed shape since. `-ignore-missing-schemas` is not used, so a kind without a schema fails the step instead of passing unchecked.

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

The 40 objects are 2 BuildConfigs, 6 ConfigMaps, 7 Deployments, 2 ImageStreams, 5 NetworkPolicies, the helm test Pod, 1 RoleBinding, 6 Routes, 1 Secret, 8 Services and 1 ServiceAccount, each checked against its schema. The first install of `up.sh` renders a subset:

```bash
helm template gql-appendix-a examples/99-appendix-a-openshift-crc/helm -n gql-appendix-a \
  --set tags.app=false | grep -E '^kind' | sort | uniq -c
```

```text
      2 kind: BuildConfig
      2 kind: ImageStream
      6 kind: Route
```

No pod names a user id. The grep prints nothing and exits `1`:

```bash
helm template gql-appendix-a examples/99-appendix-a-openshift-crc/helm -n gql-appendix-a \
  | grep -nE 'runAsUser|runAsGroup|fsGroup'
```

Check the scripts; ShellCheck prints nothing and exits `0`:

```bash
shellcheck -x examples/99-appendix-a-openshift-crc/scripts/*.sh
```

The live run used `crc` 2.64.0 and `oc` 4.22.14 on a cluster with no operator and no project besides the system ones. `crc start` took 5 min 38 s, `up.sh` 2 min 1 s (the Quarkus build 84 s, the Python build 21 s), `smoke.sh` 15 s and `down.sh` 33 s. With OpenShift Local running and `oc` on the path:

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

`smoke.sh` stops at the first failed check and prints `PASS` at the end. The checks that carry a value:

```text
=== the release and the ingress CA ===
lib.sh: ok, quarkus runs under restricted-v2: 'restricted-v2'
lib.sh: ok, python runs under restricted-v2: 'restricted-v2'
lib.sh: ok, quarkus-internal runs under restricted-v2: 'restricted-v2'
lib.sh: ok, python-internal runs under restricted-v2: 'restricted-v2'
lib.sh: ok, edge runs under restricted-v2: 'restricted-v2'
lib.sh: ok, keycloak runs under restricted-v2: 'restricted-v2'
lib.sh: ok, lgtm runs under anyuid: 'anyuid'
lib.sh: ok, keycloak: a plain HTTP request is redirected to HTTPS: HTTP 302 (allowed: 301 302 308)
=== tokens from Keycloak at its Route, the issuer the stacks pin ===
=== verifying stack 'quarkus' through the Route at https://quarkus-gql-appendix-a.apps-crc.testing/graphql ===
lib.sh: ok, quarkus: a plain HTTP request is redirected to HTTPS: HTTP 302 (allowed: 301 302 308)
lib.sh: ok, quarkus internal schema equals the canonical SDL: live schema equals the canonical SDL
lib.sh: ok, quarkus: a 100 KB body is refused at the edge: '413'
lib.sh: ok, quarkus ana sees her three cargos: ["VWX901", "DEF456", "ABC123"]
lib.sh: ok, quarkus OverBudget: message: 'maximum query complexity exceeded 7651 > 1000'
lib.sh: ok, quarkus FanOut: 8 source calls, read inside the pod: 8 call(s) to *.*
lib.sh: ok, quarkus: Tempo holds trace 3d72e62cb68d7c6eb2bf79a6506245a1 (^query ListCargos$)
=== verifying stack 'python' through the Route at https://python-gql-appendix-a.apps-crc.testing/graphql ===
lib.sh: ok, python: a plain HTTP request is redirected to HTTPS: HTTP 302 (allowed: 301 302 308)
lib.sh: ok, python internal schema equals the canonical SDL: live schema equals the canonical SDL
lib.sh: ok, python: a 100 KB body is refused at the edge: '413'
lib.sh: ok, python ana sees her three cargos: ["VWX901", "DEF456", "ABC123"]
lib.sh: ok, python OverBudget: message: 'maximum query complexity exceeded 7651 > 1000'
lib.sh: ok, python FanOut: 6 source calls, read inside the pod: 6 call(s) to *.*
lib.sh: ok, python: Tempo holds trace db57c7b9a8154a71e8aa9aab3984881f (^GraphQL Query: ListCargos$)
```

`down.sh` printed `the cluster matches the inventory taken before the run`, and a before-and-after comparison of Subscriptions, ClusterServiceVersions, CustomResourceDefinitions, namespaces and cluster role bindings was identical.

Experiments:

- Read each pod's `openshift.io/scc` annotation: `restricted-v2` for the six application workloads and `anyuid` for `lgtm`.
- Send a plain HTTP request to the Keycloak Route or a stack's Route: it is redirected (HTTP 302).
- Send a 100 KB body through a stack's Route: `413` at the edge.
- Send an over-budget document: `maximum query complexity exceeded 7651 > 1000`, before any source call.
- Send a trace id through a Route: Tempo holds it and it names the pod.

## For deeper coverage

- *Cloud Native Design Patterns*, Appendix S, "Running Example 05 on OpenShift Local": the same restricted-v2 / pinned-CSV / edge-TLS-Route pattern, applied to a different example.
- OpenShift documentation: Route configuration and TLS termination.
- OpenShift documentation: Builds using BuildConfig (the Docker strategy and binary source this appendix's `BuildConfig`s use).
- OpenShift documentation: Managing security context constraints (`restricted-v2` and `anyuid`).
- Red Hat OpenShift Local (CRC) documentation: Getting Started (`crc start` and `crc oc-env`).
