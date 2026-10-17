---
layout: plan
render_with_liquid: false
title: "r01 Wave F Plan — Ch25–Ch27 + Appendix A (Running It & the Final Project)"
---

# Wave F (S11): Ch25–Ch27 and Appendix A, Running It & the Final Project

**Status: DONE 2026-10-17 (F0–F4 with validation and one repair round each); CI green at 32f3390. APPROVED by user 2026-10-17 — §8 as recommended (Kubernetes v1.37.1, the latest stable; live minikube proof on `gql-tracking`; no live CRC run).**

This plan is written for Sonnet executors. Where it gives a value (a port, a NodePort, a path, a chart key, a release name, an image tag, a count), use exactly that value. Where it says **spike**, check the behaviour on the pinned versions before writing prose that depends on it, and record what you observe in the example README under "Code-first notes" (cluster dirs: "Notes from the run"). If a spike contradicts an expected value here, assert what you observed, rewrite the prose to match, and report it to the orchestrator. Never weaken an assertion without saying so.

**Precondition.** S10 (Wave E) is done: Ch0 and Ch3–Ch24 are `verified`, CI is green at `9002628`, the site has 79 figures and 23 example dirs. Ch25 starts from `examples/24-debugging/` (production instances only). Ch26 deploys Ch25's images. Ch27 starts from Ch25 and ports in the deltas of Ch21, Ch14, Ch18 and Ch17. Appendix A wraps Ch27's chart.

**The content rule (binding on every executor and validator).** The site is a GraphQL tutorial, not an issue tracker. Reader-facing text (chapters, READMEs, code comments, chart comments, `NOTES.txt`, script messages, test and verify messages, figure labels and alt text) states every technique positively, as the design. It never describes framework, tool or platform bugs, limitations, upstream issues, workarounds or security weaknesses, and it carries no issue numbers. Stack and platform differences are described neutrally ("on OpenShift the router terminates TLS; on minikube the chart's edge does"). This is `lgtm-professional-voice` rules 13–14. An executor who observes behaviour that looks like a defect reports it to the orchestrator in one neutral line and writes nothing about it in the repository, including `_plans/`.

**The platform rule (binding).** Application code, images, Containerfiles and `verify.sh` never depend on OpenShift, CRC, ACS or any vendor cloud. Everything OpenShift-specific (Route, BuildConfig, ImageStream, the SCC RoleBinding) lives only in `examples/99-appendix-a-openshift-crc/`. Open source only, no license keys.

---

## 0. Facts checked (2026-10-17)

Read from GitHub releases (`gh release list --exclude-pre-releases`), `registry.access.redhat.com` and `quay.io` (`skopeo list-tags`), the yannh/kubernetes-json-schema and datreeio/CRDs-catalog trees, the installed tools and a `minikube start --dry-run` on 2026-10-17. Anything marked *spike* has not been run.

**Versions (newest stable, exact pins)**

| Component | Pin | Released | Licence | Used in | Note |
|---|---|---|---|---|---|
| Kubernetes (minikube) | **v1.37.1** | 2026-09-23 | Apache-2.0 | Ch26, Ch27 cluster | the latest stable Kubernetes release (user rule: latest if possible). minikube v1.39.0 lists v1.37.0 as its newest and accepts v1.37.1 (dry-run passes; live start is spike F2-a; fallback v1.37.0) |
| Kubernetes (OpenShift Local) | 1.35.6 (OpenShift 4.22.14) | — | — | Appendix A | from crc 2.64.0; schemas `v1.35.6-standalone-strict` exist |
| minikube | v1.39.0 (floor) | 2026-09-02 | Apache-2.0 | Ch26, Ch27 | installed on the host; `--driver=docker --container-runtime=containerd` |
| kubectl | v1.37.1 | 2026-09-23 | Apache-2.0 | scripts, CI | CI already pins v1.37.1; host has v1.36.5 (one minor skew is within policy; executors use a scratch v1.37.1) |
| Helm | **v4.3.1** | 2026-10-15 | Apache-2.0 | charts, CI | CI already pins v4.3.1 via `azure/setup-helm@v5` (v5.0.1 current); host has v4.3.0; linux-amd64 sha256 `0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b` |
| kubeconform | v0.8.0 | 2026-06-04 | Apache-2.0 | CI, executors | CI pins it with sha256 `9bc2bffb…ec287883`; not on the host (executors install into scratch with the same checksum) |
| kubernetes-json-schema | `v1.37.1-standalone-strict`, `v1.35.6-standalone-strict` | tree updated 2026-10-15 | Apache-2.0 | kubeconform default location | |
| datreeio/CRDs-catalog | commit `63669a570e231d4f1f8396d229a1de512bcf0a34` (`openshift/v4.15-strict/`: `route_route.openshift.io_v1.json`, `buildconfig_build.openshift.io_v1.json`, `imagestream_image.openshift.io_v1.json`) | 2026-10-08 | MIT | Appendix A schemas | newest OpenShift set in the catalog; Route/BuildConfig/ImageStream v1 are stable APIs |
| ShellCheck | v0.11.0 | 2025-08-04 | GPL-3.0 (CLI use) | CI, executors | not on the host: run `docker.io/koalaman/shellcheck:v0.11.0` or install the release tarball in scratch |
| OpenShift Local (crc) | 2.64.0 | 2026-09-24 | Apache-2.0 | Appendix A (static) | installed; VM stopped |
| `ubi10/nginx-126` | **`10.2-1791973310`** | 2026-10-14 | — | Ch25, Ch26, Ch27, A | newest; no `nginx-128`/`127` stream on ubi10. Ch16 uses the older `10.1-1779165744` (not bumped in-wave) |
| `ubi10/openjdk-25` / `-runtime` | `1.24-16` | — | — | all | unchanged, newest |
| `ubi10/python-314-minimal` | `10.2-1791928506` | — | — | all | unchanged, newest |
| `ubi10/ubi-minimal` | `10.2-1791891203` | — | — | k6 image (Ch27), helm test pod | unchanged, newest |
| `quay.io/keycloak/keycloak` | 26.8.1 | 2026-10-13 | Apache-2.0 | Ch27, A | unchanged (Ch18), newest |
| `docker.io/grafana/otel-lgtm` | 0.37.0 | 2026-10-16 | Apache-2.0 | Ch25, Ch26, Ch27, A | unchanged, newest |
| Grafana k6 | v2.3.0 | 2026-09-21 | AGPL-3.0 (OSI, no fees, unmodified CLI) | Ch27 load run | unchanged (Ch23) |
| Quarkus / Strawberry / FastAPI / uv | 3.40.1 / 0.335.0 / 0.143.2 / 0.13.1 | — | — | all | unchanged; do not bump in-wave (fastapi 0.143.3 recorded at Wave E) |
| Gateway API (rejected alternative) | v1.6.3; Envoy Gateway v1.9.2 | 2026-10-06 / 2026-09-28 | Apache-2.0 | — | §8 decision 3 |
| ingress-nginx (rejected) | archived upstream (2026-03-23) | — | — | — | §8 decision 3 |

**The CI job as it is today** (`.github/workflows/contracts.yml`, job `k8s-manifests`): installs kubeconform v0.8.0 (checksum), Helm v4.3.1 and kubectl v1.37.1, then runs `kubectl kustomize examples/26-minikube/k8s | kubeconform -strict -summary`, the same for `examples/27-final-project/k8s`, and `helm lint` + `helm template … | kubeconform -ignore-missing-schemas -summary` for `examples/99-appendix-a-openshift-crc/helm`. Each step prints "not present yet" when its directory is absent, so the job passes today. It is in `ci-ok`'s `needs`. It expects **kustomize** for Ch26/Ch27; this plan uses Helm, so the job changes (§3, §8 decision 9).

**`scripts/validate.py`**: `CLUSTER_TIER_DIRS = ["examples/26-minikube", "examples/99-appendix-a-openshift-crc"]` fails the build if either holds a `verify.sh` anywhere below it; `bash -n` runs on every `*.sh`. Ch27 is not a cluster-tier dir, so its `verify.sh` is auto-discovered by the examples matrix. No change to `validate.py` is needed.

**Sibling templates (read-only).**
- REST: `25-local-with-docker-compose` (own example, LGTM), `26-minikube` (kustomize base + overlay, Ingress, HPA, `run-minikube.sh`, Ch25's sources and Containerfiles reused, no third copy), `27-complete-project` (compose `verify.sh`), Appendix A (Helm chart with BuildConfig, ImageStream, Route, `run-crc.sh`). Its Ingress, `minikube image build` and `minikube delete` are replaced here by the current rules (NodePorts published at creation, `docker build` + `minikube image load`, stop not delete).
- gRPC: Ch27 (compose `verify.sh` + `k8s/` kustomize + `scripts/bootstrap|run-demo|teardown.sh`), Appendix A (`helm/` with Chart.yaml at the top, `scripts/lib.sh` with `require_crc`/`wait_for`/`install_operator`, `teardown.sh` that removes release, project, operators, CRDs and namespaces, then `crc stop`). Its figure names are `27-*` and `A-*`; its appendix front matter is `order: 99`, `appendix: true`, `appendix_label: "A"`, which this site's `_layouts/tutorial.html` already supports.

**Skills (conventions that bind this wave).**
- `lgtm-minikube-stack`: host access only through NodePorts published at profile creation (`minikube start --ports=127.0.0.1:<host>:<nodePort>,…`, loopback); ports are fixed at creation (adding one means recreating the profile); `--driver=docker --container-runtime=containerd` on Docker Engine (context `default`, `/var/run/docker.sock`); images by `docker build` + `minikube -p <profile> image load`, Deployments with the bare name and `imagePullPolicy: Never`, `kubectl rollout restart` after a reload; never `minikube config set`; every call names `-p <profile>`, `--context <profile>`, `--kube-context <profile>`, never the current context; `--kubernetes-version` always explicit; preflight checks Docker Engine, `ss -ltn` for free host ports, `docker port <profile>` after start; never publish host port 9090; OTLP to the collector by env; Fedora/RHEL only.
- `lgtm-crc`: one cluster at a time (`require_crc` refuses beside a running minikube profile); the `crc-admin` context, API server must be `api.crc.testing`; never print credentials; Routes with edge TLS and HTTP redirected, verified with the ingress CA (`curl --cacert`), never insecure; restricted-v2 (never `runAsUser`, `runAsGroup`, `fsGroup`; only `runAsNonRoot`, no privilege escalation, drop ALL, `RuntimeDefault` seccomp), otel-lgtm the single documented `anyuid` exception; `oc rollout status`, not `condition=Available`; immutable selectors on `app.kubernetes.io/name` only; ConfigMap checksum annotation; generated secrets with `lookup`; teardown removes release, project, Subscriptions, CSVs, InstallPlans, owned CRDs, operator namespaces, prints leftovers, then `crc stop`; only the user starts a cluster.
- `lgtm-docker-stack`: `docker compose` v2 plugin only; healthchecks and `depends_on: condition: service_healthy`; pinned UBI images; OTLP to one collector.
- `lgtm-tutorial`: chapter depth standard, one runnable example per chapter, paired SVG + `.excalidraw` figures from specs, static validation before hand-back.

**Forward references this wave must deliver** (grep of `_docs/`, example READMEs, `_parts/`, `index.html`, `_plans/`):
- **Ch17:23**: "A reverse proxy or a service mesh can do [TLS] instead, and Chapters 25 to 27 return to that." → Ch25's nginx edge terminates TLS 1.3; Ch26 runs the same edge in the cluster; Appendix A shows the OpenShift router doing it.
- **Ch17:182**: "The production answer is a fronting proxy: `client_max_body_size` in nginx or the ingress equivalent." → Ch25's edge sets `client_max_body_size` and verify asserts `413` on both stacks for the 100 KB body Ch17 used.
- **Ch24:314**: "Chapter 25 runs the stack locally with Docker Compose, so the diagnosis path of this chapter has a full environment to work against instead of one example at a time." → Ch25 runs LGTM by default and verify follows a trace id from a request through the edge to Tempo and Loki.
- **`examples/_lib/README.md:24`**: `assert_sdl_equals` "for the complete schema in the final project." → Ch27 serves the whole canonical SDL (Subscription included) and asserts `assert_sdl_equals` on both stacks.
- **Ch14 README:15 / Ch18 README:9**: "production would run all of them together" / "production would carry both." → Ch27 runs Ch14's limits, Ch18's authorization and Ch17's introspection control together.
- **Part 12 blurb**: "Run, observe, and defend a complete GraphQL tracking system across Compose, minikube and OpenShift Local." → Ch25 (run), Ch25/Ch27 telemetry (observe), Ch27 defences and load run (defend), Ch26 + Ch27 chart (minikube), Appendix A (OpenShift Local).
- **`index.html:51–54`**: "running the service on Kubernetes … the stack runs on Docker Compose and minikube." → Ch26/Ch27 cluster tier.
- **`_plans/iteration-plan.md` S11**: "Compose verify green; minikube and CRC manifests pass kubeconform and helm."
- **Execution plan**: 27 example dirs; cluster-tier Ch26/Appendix A without `verify.sh`, kubeconform/helm validated; minikube primary, CRC mirror.

**Figures.** The site has 79. This wave adds exactly **10** (Ch25 2, Ch26 2, Ch27 3, Appendix A 3) for **89**. Architecture figures under `examples/*/architecture.*` are not counted.

---

## 1. Approach

### Sequencing (DAG)

| Step | Executor | Owns (exclusive write set) | Depends on |
|---|---|---|---|
| **F0** Harness + CI | Executor 1 | `examples/_lib/lib.sh`, `examples/_lib/README.md`, `.github/workflows/contracts.yml` | S10 |
| **F1** Ch25 Local with Docker Compose | Executor 2 | `_docs/25-*`, `examples/25-docker-compose/**`, `diagrams/25-*.py`, `diagrams/examples/25-*`, `assets/diagrams/25-*` | F0 |
| **F2** Ch26 Kubernetes on minikube | Executor 3 | `_docs/26-*`, `examples/26-minikube/**`, `diagrams/26-*.py`, `diagrams/examples/26-*`, `assets/diagrams/26-*` | F1 example checkpoint (images and env contract) |
| **F3a** Ch27 compose tier | Executor 4 | `_docs/27-*`, `examples/27-final-project/**`, `diagrams/27-*.py`, `diagrams/examples/27-*`, `assets/diagrams/27-*` | F1 example checkpoint |
| **F3b** Ch27 chart + cluster scripts | Executor 4 (same owner) | `examples/27-final-project/helm/**`, `examples/27-final-project/scripts/**` | F2 chart checkpoint, F3a images |
| **F4** Appendix A OpenShift Local | Executor 5 | `_docs/99-appendix-a-openshift-crc.md`, `examples/99-appendix-a-openshift-crc/**`, `diagrams/A-*.py`, `diagrams/examples/99-*`, `assets/diagrams/A-*` | F3b chart checkpoint (values contract); scripts and prose may start after F3a |
| **FV1–FV4** Validation (Opus), one per chapter | Opus | read-only findings; fixes routed to the owning executor | the chapter's step |
| **FW** Wrap (orchestrator) | orchestrator | `_plans/*`, `coverage-matrix.md`, `_example_pages/index.md`, `_plans/domain-glossary.md`, `_plans/iteration-plan.md`, commits, deliberate fixes | FV1–FV4 + CI green |

How to run it:
- F0 is small (five helpers and the CI job, §3). Its CI job tolerates missing directories, so it lands first and stays green.
- F1 lands its **example first** (code, compose, verify green), then prose and figures. The example checkpoint fixes the image names, the env contract and the health paths that F2 and F3a build on.
- After the F1 example checkpoint, **F2 and F3a run in parallel**. F3b starts after F2's chart checkpoint (it copies the chart) and F3a's images. F4's chart starts after F3b's chart checkpoint; F4's scripts and prose can start after F3a.
- **The live minikube windows are serialized** (one profile, one cluster): F2 live run → `down.sh` → F3b live run → `down.sh`. The orchestrator hands out the "live token"; nobody else starts a cluster while it is held. F4 never starts a cluster.
- Critical path: F0 → F1 example → F3a → F3b → F4 chart.
- **Shared files are single-owner.** Only F0 edits `lib.sh`, its README and `contracts.yml`. Only the orchestrator edits `_plans/`, the coverage matrix, `_example_pages/` and the glossary. Nobody edits `contracts/` or `scripts/`. A helper F0 did not provide is a local function in the chapter's `verify.sh` or the cluster `scripts/lib.sh`, reported in the hand-back.
- Each FVn starts as soon as its chapter's checkpoint lands. At most two repair rounds per chapter; a third failure goes back to the user.

**Executor rules (unchanged from Waves A–E, binding)**
- Write files only. No git.
- Do not touch `_plans/*`, `coverage-matrix.md`, `_example_pages/`, `scripts/`, `contracts/`, `.github/` (only F0), `examples/_lib/` (only F0), or any other chapter's files, including every verified Ch0–Ch24 file. Ch27 **reads** Ch14, Ch17, Ch18, Ch21, Ch23 and Ch25 to port from them; it never writes them. Ch26 and Ch27 scripts **read** `examples/26-minikube/scripts/profile.sh` and `examples/25-docker-compose/{quarkus,python}`; only their owners write them.
- Never delete or reinstall `contracts/node_modules`.
- Never `pkill -f`. Stop only your own compose project with `docker compose -p <project> down -v`, and only your own release or profile.
- Before handing back, every executor runs its own `verify.sh` green (compose tiers) or `up.sh` + `smoke.sh` + `down.sh` green (cluster tiers, when holding the live token); `python3 -I scripts/validate.py; echo rc=$?` (never piped); `bash scripts/wordcount.sh _docs/NN-*.md`; `npm --prefix contracts run lint`; `helm lint --strict` + `helm template | kubeconform -strict -summary` on every chart it owns; ShellCheck on every script it owns; and renders every new figure to PNG and **views** it.
- Builds and tests run only inside the pinned UBI images; nothing calls the host's `mvn`, `java`, `uv` or `pytest`. Helm, kubectl and kubeconform run from scratch installs at the pinned versions (§0), never by changing the global `~/.local/bin`.

**Orchestrator rule.** At each chapter's checkpoint commit, flip that chapter to `draft` in **both** the Topics table (T26–T28) and the Full chapter inventory (and R1–R3 in the Runtime-tier table) in the same commit, then push so CI runs `verify: 25-docker-compose`, `verify: 27-final-project`, `k8s-manifests`, the wordcount GATE and `validate.py`. A chapter is `verified` only after FVn passes **and** CI is green; for Ch26 also after the live minikube run passed; for Appendix A after the static validation passed (no live run unless §8 decision 7 says otherwise).

**Rejected alternatives (one line each)**
- *kustomize for the cluster tiers*: the user asked for Helm charts for both stacks; Helm also gives `helm test`, `values.schema.json`, `lookup` and a dependency that Appendix A can wrap.
- *An Ingress controller on minikube*: ingress-nginx is archived upstream; an Ingress also needs `minikube tunnel` or a NodePort for the controller anyway.
- *Gateway API (Envoy Gateway) on minikube*: a controller, its CRDs and another pinned component for one host route; its data plane still needs a NodePort; the chart's nginx edge already does TLS, the body limit and the WebSocket upgrade identically on compose and Kubernetes.
- *`minikube image build` / a local registry*: the skill's idiom is `docker build` + `minikube image load`.
- *Binary S2I with `quarkus-openshift` on CRC*: changes the pom; a Docker-strategy BuildConfig builds the same Containerfile unchanged.
- *A separate Ch25 that reuses Ch24's dir*: the canonical dir list names `25-docker-compose`, and the tier needs its own edge, networks and health split.
- *Everything in Ch27 (APQ, caching, federation, dev instances)*: §8 decision 4.

### Example structure

Same as Waves A–E for compose dirs: a self-contained copy, package `com.patterncatalyst.shipping.tracking`, Python package `app`. Change the artifactId, the Python project name (then **re-run `uv lock`** inside the image), `quarkus.otel.service.name` / `OTEL_SERVICE_NAME`, container names and the compose `name:`. `.gitignore` adds `python/.ruff_cache/`, `quarkus/target/`, `python/.venv/`, `python/.pytest_cache/`, `certs/`.

Cluster dirs (Ch26, Appendix A) carry **no application code**: Ch26 deploys Ch25's images, Appendix A builds Ch27's sources. Their `.gitignore` adds `helm/charts/` (dependency output) and `*.tgz`.

**Image tags.** Compose sets `image:` on each build so the tag is the one the cluster loads: `gql-ch25-quarkus:1.0`, `gql-ch25-python:1.0`, `gql-ch27-quarkus:1.0`, `gql-ch27-python:1.0`, `gql-ch27-client:1.0`, `gql-ch27-load:1.0`.

### How the schema slice grows

| Ch | Base | Served slice | Behaviour added |
|---|---|---|---|
| 25 | Ch24 production instances (Ch19 telemetry + `extensions.traceId`) without the `JKL012` seed, the dev target and the logging manager | all but `Subscription` | an nginx edge (TLS 1.3, body limit, only `/graphql` routed, `traceparent` passed through), an internal backend network, compose `configs:` and `secrets:`, FastAPI `/health/live` + `/health/ready`, resource limits, restart and graceful-shutdown settings, log rotation, LGTM on by default |
| 26 | Ch25's images | as Ch25 | a Helm chart for both stacks: ConfigMaps, a chart-generated TLS Secret, probes, NodePort edge, LGTM, NetworkPolicy, downward-API resource attributes, `helm test` |
| 27 | Ch25 + Ch21 + Ch14 + Ch18 + Ch17 | **complete** (`assert_sdl_equals`) | subscriptions through the edge (WSS, SSE), cost/depth/alias limits, Keycloak tokens with operation, object and field authorization (subscriptions included), public instances with introspection off beside internal instances, a k6 run through the edge; the same system as a Helm chart |
| A | Ch27's chart and sources | as Ch27 | a wrapper chart (Routes, BuildConfigs, ImageStreams, the otel-lgtm SCC binding) and CRC scripts |

### Canonical SDL changes

**None.** The `contracts/` diff for Wave F must be empty.

### Seed data

Ch25: Ch24's seed **without** `JKL012` (so it equals Ch19's, which is Ch13's): `cargos(first: 10)` has six edges; GHI345 fails at the booking source with `SERVICE_UNAVAILABLE` (Quarkus nulls the whole batch, Python one edge, Ch13 values).

Ch27: Ch18's ownership (`ana` ACME: VWX901, DEF456, ABC123; `bo` GLOBEX: XYZ789, STU678, GHI345; `ops` operator) over Ch13's seed. One registration:

| Name | Input | Caller | Expected |
|---|---|---|---|
| `REG_F1` | ABC123 `UNLOAD` DEHAM `V100S` `2026-10-09T15:00:00Z`, `idempotencyKey` `ch27-final-f1` | `ops` | `evt_10`, `userErrors` empty; the `ana` subscriber on ABC123 receives `evt_10`; a `TrackCargo` for ABC123 then says `IN_PORT` |

### Ports, NodePorts, project names

**Compose rule (unchanged):** chapter N owns host ports 8100+10·N … +9; Quarkus +0, Python +1, extras +2…+9. In this part the edge holds +0/+1, and everything except the edge binds to `127.0.0.1`.

**Cluster rule (new):** NodePort = host port = 30100+10·N+k, published on `127.0.0.1` at profile creation. One profile, `gql-tracking`, publishes Ch26's and Ch27's sets, so neither chapter recreates it. The ranges clear `lgtm-minikube-stack`'s map (30009, 30081, 30084, 30100, 30201, 30300, 30320, 30379, 30417, 30418, 30585) and every compose port.

| Ch | dir | Ports (host → target) | compose `name:` / release / namespace | container prefix | artifactId / Python project |
|---|---|---|---|---|---|
| 25 | `25-docker-compose` | 8350 → edge:8443 (Quarkus, HTTPS), 8351 → edge:8444 (Python, HTTPS), 127.0.0.1:8352 → lgtm:3000 (Grafana), :8353 → lgtm:3200 (Tempo), :8354 → lgtm:9090 (Prometheus), :8355 → lgtm:3100 (Loki); backends publish nothing | `gql-ch25-compose` | `ch25-compose-` | `ch25-quarkus-compose` / `shipping-python-ch25-compose` |
| 26 | `26-minikube` | NodePorts on 127.0.0.1: 30360 edge-quarkus (HTTPS), 30361 edge-python (HTTPS), 30362 Grafana, 30363 Tempo, 30364 Prometheus, 30365 Loki | release `gql-ch26`, namespace `gql-ch26`, profile `gql-tracking` | — | (Ch25 images) |
| 27 | `27-final-project` (compose) | 8370 → edge:8443 (Quarkus, HTTPS), 8371 → edge:8444 (Python, HTTPS), 127.0.0.1:8372 → quarkus-internal:8080, :8373 → python-internal:8080, :8374 → keycloak:8080, :8375 Grafana, :8376 Tempo, :8377 Prometheus, :8378 Loki | `gql-ch27-final` | `ch27-final-` | `ch27-quarkus-final` / `shipping-python-ch27-final` |
| 27 | (cluster) | NodePorts on 127.0.0.1: 30370 edge-quarkus, 30371 edge-python, 30372 quarkus-internal, 30373 python-internal, 30374 keycloak, 30375 Grafana, 30376 Tempo, 30377 Prometheus, 30378 Loki | release `gql-ch27`, namespace `gql-ch27`, profile `gql-tracking` | — | (Ch27 images) |
| A | `99-appendix-a-openshift-crc` | Routes only (`*-gql-appendix-a.apps-crc.testing`) | release `gql-appendix-a`, project `gql-appendix-a` | — | (built in-cluster from Ch27 sources) |

`gql-tracking` `--ports` (15 entries): `127.0.0.1:30360:30360,…,127.0.0.1:30365:30365,127.0.0.1:30370:30370,…,127.0.0.1:30378:30378`. Profile size: `--cpus=6 --memory=12g --disk-size=40g` (Ch27's tier is the larger; spike F3b-a measures it).

**CI.** One example per `ubuntu-latest` job; `timeout-minutes: 60`, three attempts. Estimates per cold attempt: Ch25 ~7 min (two Maven/uv builds, LGTM, nginx, cert generation); Ch27 ~13–15 min (two builds, Keycloak, LGTM, client image, k6 image, four internal/public instances). Three cold attempts of Ch27 fit in 60 min; §8 decision 9 keeps the timeout unless spike F3a-a measures more than 18 min. The `k8s-manifests` job adds about one minute.

---

## 2. Per chapter

**Common to all four** (as in Waves A–E):
- **Front matter:** `title` (Ch25 "Local with Docker Compose", Ch26 "Kubernetes on minikube", Ch27 "The final project", A "Appendix A — OpenShift Local (CRC)"), `order` (25, 26, 27, 99), `part:` exactly "Running It & the Final Project", `description`, `duration` (words/200, "NN min read"); Appendix A adds `appendix: true`, `appendix_label: "A"`.
- **Length and figures:** 2,800–3,400 prose words (`wordcount.sh`); figures via `{% include excalidraw.html file="…" alt="…full sentences…" caption="Figure N.M — …" %}` (Appendix: `Figure A.1` …), numbered by order of appearance; at least one `{% include codetabs.html langs="Quarkus|Python" %}` (Ch26 and A: the probe/env mapping per stack, or the values for each stack).
- **Last three blocks:** `## On the wire` (commands and the exact values the script asserts), the Decision callout naming Ch2's axes, `## Where this goes next`.
- **Prose rules:** no `{{`/`{%` outside includes and fences (Helm templates shown in prose go inside fences, which `validate.py` skips; Liquid is off only inside fences, so a fenced `{{ .Values… }}` is safe, and an inline one is not); books by verified chapter title only; spec and doc sections by page title; every YAML, Java, Python or shell snippet in prose exists in the example (Pitfall 27); the content and platform rules.
- **Diagram specs:** `diagrams/<name>.py`; architecture figures `diagrams/examples/<dir>-architecture.py` (not counted). Data-movement figures are drawn from a named run (docstring). Regenerate; never hand-edit SVG.
- **README sections** (compose dirs, Ch13 order): The served slice, Run it, Ports, On the wire, Code-first notes, Diagram; Ch25 adds "The tier" after The served slice; Ch27 adds "What the final project carries" and "On Kubernetes". **Cluster dirs:** What it deploys, Layout, Run it (up, smoke, down), Ports (NodePorts), Static validation, Notes from the run, Diagram.

### Ch25: Local with Docker Compose

**Files:** `_docs/25-local-with-docker-compose.md`, `examples/25-docker-compose/` (from Ch24).

**Learning goals.** By the end of the chapter the reader can:
- run the tracking view as one local tier: both stacks, an edge, an observability backend, each started in order by health (Figure 25.1);
- keep configuration and secrets out of the image: environment and `env_file`, compose `configs:` for a file, compose `secrets:` for key material read from `/run/secrets`;
- terminate TLS and cap request bodies at a fronting proxy, route only `/graphql` through it, and keep the backends off the host (Ch17's two forward references);
- map each stack's health endpoints to start order and to the probes Chapter 26 uses: SmallRye Health `started`/`ready`/`live`; FastAPI `/health/live` and `/health/ready`;
- set resource limits, a restart policy, a shutdown grace period and log rotation, and read each back from the engine;
- follow a request from the edge to its trace and log record by trace id (Figure 25.2), the full environment Chapter 24 asked for.

**H2 outline**
1. *From one example to a tier.* What changes when the stack is run as a whole instead of one chapter's feature at a time; the topology (Figure 25.1).
2. *One image per stack.* Built once, tagged `1.0`, configured from outside; the same tags Chapter 26 loads into a cluster.
3. *Configuration outside the image.* The env contract table (`QUARKUS_*`, `OTEL_*`, `TRACKING_*` per stack), `env_file`, `${VAR:-default}`; `configs:` for `nginx.conf`.
4. *Secrets as files.* `secrets:` for the edge's key; mounted read-only under `/run/secrets`; absent from `docker inspect`'s environment and from every image.
5. *The edge.* nginx on `ubi10/nginx-126`: TLS 1.3 only, `client_max_body_size 64k`, `location = /graphql` only (everything else 404), `traceparent` forwarded unchanged; one listener per stack so the chapter port rule holds.
6. *Networks.* `backend` is `internal: true`; only the edge and the observability backend join the published networks; everything but the edge binds to `127.0.0.1`.
7. *Health and start order.* SmallRye Health's three endpoints; FastAPI live and ready routes (ready after the lifespan built the store and the sources); `healthcheck`, `start_period`, `depends_on: condition: service_healthy`.
8. *Limits, restarts and shutdown.* `deploy.resources.limits`, `restart: unless-stopped`, `stop_grace_period` with `quarkus.shutdown.timeout` and uvicorn's `--timeout-graceful-shutdown`; the `local` log driver with `max-size`/`max-file`.
9. *The diagnosis path on the whole stack.* A traced request through the edge (Figure 25.2): `extensions.traceId` on GHI345's error equals the caller's trace id, Tempo holds the trace, Loki the record (Ch19, Ch24).
10. On the wire / Decision / next (Ch26: the same images on Kubernetes).

**Example design**
- **Server code:** Ch24's production instances unchanged apart from names and ports, with: the `JKL012` seed removed (booking, routing, handling, and the location source back to Ch19's set); the `dev` Containerfile target, `%dev` properties and `quarkus-logging-manager` removed (Python `/debug/loggers` and `TRACKING_PROFILE` removed; `graphql_ide=None`); `extensions.traceId` kept (both hooks); the `resolve` debug category kept at INFO.
- **Python health:** `/health` replaced by `/health/live` (process up, always 200) and `/health/ready` (200 once the lifespan set `app.state.ready = True` after building the store and the sources, 503 before); plain FastAPI routes, tagged `ops`, no third-party health package.
- **Quarkus:** SmallRye Health unchanged (`/q/health/started`, `/q/health/ready`, `/q/health/live`); `quarkus.shutdown.timeout=10s` (spike F1-c: the property name on 3.40.1).
- **Python start command:** uvicorn gains `--timeout-graceful-shutdown 10`.
- **`edge/nginx.conf`** (compose `configs: edge_conf`, target `/etc/nginx/nginx.conf`): two `server` blocks, `listen 8443 ssl` → `quarkus:8080`, `listen 8444 ssl` → `python:8080`; `ssl_protocols TLSv1.3`; certificate `/run/secrets/edge_tls_crt`, key `/run/secrets/edge_tls_key`; `client_max_body_size 64k`; `location = /graphql` with `proxy_http_version 1.1`, `proxy_set_header Host`, `X-Forwarded-For`, `X-Forwarded-Proto https`, and the `Upgrade`/`Connection` map (unused here, used by Ch27); `location /` returns 404; `access_log` to stdout (spike F1-b: the UBI image's writable paths when it runs as UID 1001).
- **Certificates:** `gen-certs.sh` (copied from Ch17, SAN `localhost`, `127.0.0.1`, `edge`); verify generates them into a scratch dir and exports `CERT_DIR`; `secrets: edge_tls_crt: file: ${CERT_DIR:-./certs}/edge.crt`, `edge_tls_key: …/edge.key` (spike F1-a: the file mode nginx's UID needs on a bind-mounted secret).
- **compose services:** `edge` (networks `public`, `backend`), `quarkus`, `python` (network `backend` only, no `ports:`), `lgtm` (networks `backend`, `ops`; its ports on `127.0.0.1`). Networks: `public` (bridge), `ops` (bridge), `backend` (`internal: true`). Each app: `deploy.resources.limits` (Quarkus `cpus: "1.0"`, `memory: 768m`; Python `cpus: "0.5"`, `memory: 384m`; edge `0.25`/`64m`), `restart: unless-stopped`, `stop_grace_period: 15s`, `logging: {driver: local, options: {max-size: "10m", max-file: "3"}}`, `env_file: ./env/<stack>.env` for the contract, `environment:` for per-run overrides; `TRACKING_DEBUG_ENDPOINTS=true` (lab; the edge does not route `/debug`), `TRACKING_SOURCE_LATENCY_MS=250`; OTLP to `http://lgtm:4317` (Quarkus) / `http://lgtm:4318` with `http/protobuf` (Python, per the skill; spike F1-e: Ch24's Python exporter setting and whether changing it alters any span asserted).
- **Healthchecks:** Quarkus `/q/health/ready`; Python `/health/ready`; edge `curl -fsS --cacert /run/secrets/edge_tls_crt https://localhost:8443/graphql` with a `{__typename}` POST (spike: curl in the nginx image); LGTM as Ch24. `edge` depends on both apps healthy; apps depend on `lgtm` healthy.

**verify.sh assertions (both stacks unless marked).** `LGTM_CACERT` = the scratch CA; URLs `https://localhost:8350/graphql` and `https://localhost:8351/graphql`.
1. **The tier is up in order:** every service `healthy` (`docker compose ps --format json`); `docker compose config --quiet` exits 0.
2. **Only the edge is reachable:** `docker compose port quarkus 8080` and `python 8080` print nothing; the `backend` network has `Internal == true`; every published LGTM port's `HostIp` is `127.0.0.1`.
3. **Through the edge:** `wait_for_graphql`; Ch19's `HEALTHY` (`TrackCargo` ABC123 → `ONBOARD_CARRIER`, no errors); `FanOut` data and the per-stack calls (8 Quarkus, 6 Python) read with `source_calls_in` (§3); `cargos(first: 10)` → 6 edges with the per-stack GHI345 errors and code `SERVICE_UNAVAILABLE`.
4. **The edge routes only `/graphql`:** `GET /debug/source-calls` through the edge → 404; `GET /q/health/ready` through the edge → 404.
5. **TLS at the edge:** `assert_transport_fails` with `--tls-max 1.2`; `LGTM_CACERT= assert_transport_fails` without the CA; plain `http://localhost:8350/graphql` → transport failure or 400 (spike F1-b: nginx answers a plain request on an `ssl` listener with 400 "The plain HTTP request was sent to HTTPS port"; assert what it does).
6. **Body limit at the edge (Ch17:182):** a 100 KB comment followed by `{ __typename }` → `413` on both stacks, and the backend's source-call log and access count unchanged (the request never reached it).
7. **Secrets as files:** the edge container's `Config.Env` contains neither `BEGIN` nor the key path's content; `/run/secrets/edge_tls_key` exists in the edge container; no image layer holds a key (`docker image inspect` env and labels).
8. **Health split (Python):** inside the network, `GET /health/live` and `/health/ready` → 200 (`compose_exec_http`, §3); Quarkus `/q/health/started`, `/ready`, `/live` → 200 with `"status":"UP"`.
9. **Limits and policies read back:** `HostConfig.Memory` = 805306368 (Quarkus), 402653184 (Python); `NanoCpus` = 1000000000 / 500000000; `RestartPolicy.Name` = `unless-stopped`; `LogConfig.Type` = `local`; `StopTimeout` = 15.
10. **Restart and graceful stop (spike F1-d):** (a) `docker compose kill -s SIGTERM python`, then the container returns to `healthy` without a `compose up` (the restart policy brings it back; if the engine treats this as a manual stop, assert the policy value only and record it); (b) a `FanOut` sent, then `docker compose stop quarkus` while it runs → the response is complete (200, no errors) and the container exited with code 0 or 143 within 15 s. A failure is a finding, never a sleep.
11. **The diagnosis path (Ch24:314):** pick `new_trace_id`, set `LGTM_TRACEPARENT`; `cargos(first: 10)` through the edge → the GHI345 error's `extensions.traceId` equals the id; `tempo_trace` (8353) by that id has the operation span `query ListCargos` (per-stack name from Ch19's table) and `source.call` spans; `loki_wait` (8355) `{service_name="ch25-compose-<stack>"} | trace_id="<id>"` returns at least one record. Proves the edge forwards `traceparent`.
12. **Contract:** `assert_sdl_conforms` on both edge URLs (introspection open in this chapter, as in Ch19), `assert_deprecated` for `finalArrivalDate`, the scalar `kind`/`specifiedByURL` loop.

**Figures (2)**
- `25-compose-tier-topology`: the host on the left (only 8350/8351 beyond loopback; 8352–8355 on 127.0.0.1), the `public`, `ops` and `backend` networks as bands, the edge with its `configs:` and `secrets:` mounts, both stacks with their health endpoints and limits, LGTM; arrows labelled with the start order (`service_healthy`).
- `25-request-through-the-edge` (data movement): a client with a `traceparent` → edge (TLS 1.3, 64k limit, `/graphql` only) → Quarkus → batched source calls → the GHI345 error with `extensions.traceId` → Tempo and Loki by that id; a second, refused request stopping at the edge with 413. Values from the run; docstring names it.

**Citations.** Docker Compose documentation ("Compose file reference": `services` (`healthcheck`, `depends_on`, `deploy.resources`, `restart`, `stop_grace_period`, `logging`), `configs`, `secrets`, `networks` (`internal`)); Docker "Restart policies" and "Configure logging drivers" (`local`); nginx documentation (`ngx_http_ssl_module`, `client_max_body_size`, `proxy_pass`, WebSocket proxying); Quarkus "SmallRye Health" and the graceful-shutdown section of "Configuring your application" (**spike** for the exact page); Uvicorn "Settings" (`--timeout-graceful-shutdown`); FastAPI "Lifespan Events"; the Twelve-Factor App "Config" and "Disposability" (by section name); Ch17, Ch19, Ch24 by chapter.

### Ch26: Kubernetes on minikube

**Files:** `_docs/26-kubernetes-on-minikube.md`, `examples/26-minikube/` (cluster tier, **no `verify.sh`**).

**Learning goals.** By the end of the chapter the reader can:
- map each Compose concept of Chapter 25 to its Kubernetes object (Figure 26.1);
- create a minikube profile on Docker Engine with containerd, an explicit Kubernetes version and the NodePorts published at creation, and load locally built images into it;
- write one Helm chart that deploys both stacks from a values map, with `values.schema.json`, ConfigMaps, a chart-generated TLS Secret, a checksum annotation, probes, resources and a security context that also fits a restricted cluster;
- map SmallRye Health and the FastAPI health routes to startup, readiness and liveness probes, and set rolling-update and termination settings to match;
- reach the edge from the host through a NodePort (Figure 26.2), and see the pod name in a trace through the downward API;
- prove a release with `helm test` and the same GraphQL assertions as Chapter 25, and validate the chart statically in CI.

**H2 outline**
1. *What changes from Compose to Kubernetes* (Figure 26.1): services → Deployment + Service; ports → NodePort; `env_file` → ConfigMap; `secrets:` → Secret volume; `healthcheck` → three probes; `depends_on` → readiness gating; `deploy.resources` → requests/limits; `restart` → the kubelet; networks → NetworkPolicy.
2. *The cluster.* Profile `gql-tracking`: `--driver=docker --container-runtime=containerd --kubernetes-version=v1.37.1`, sized 6 CPU / 12 GiB; the `--ports` list (15 loopback entries) fixed at creation, checked with `ss -ltn` before and `docker port` after.
3. *Images into the node.* `docker build` of Chapter 25's Containerfiles, `minikube -p gql-tracking image load`, `imagePullPolicy: Never`, `kubectl rollout restart` after a reload.
4. *One chart for both stacks.* `helm/` layout, the `stacks:` map, `values.schema.json`, helpers, labels (`app.kubernetes.io/*`), selectors on `app.kubernetes.io/name` only.
5. *Configuration and secrets.* A ConfigMap per stack consumed with `envFrom`; the env contract table from Chapter 25 unchanged; the TLS Secret generated by the chart (`genCA`, `genSignedCert`) and kept across upgrades with `lookup`; the `checksum/config` annotation rolls pods on a change.
6. *Probes and lifecycle* (codetabs: Quarkus `/q/health/started|ready|live`, Python `/health/live|ready`): `startupProbe` for the JVM warm-up, readiness for traffic, liveness for restarts; `terminationGracePeriodSeconds: 30` over the 10 s application timeout; `maxUnavailable: 0`.
7. *The way in* (Figure 26.2): host `127.0.0.1:30360` → the node container's published port → the edge's NodePort Service → the edge pod → ClusterIP `quarkus` → a ready pod.
8. *Telemetry by environment.* OTLP endpoints in the ConfigMap; `OTEL_RESOURCE_ATTRIBUTES` with `k8s.namespace.name`, `k8s.pod.name` from the downward API; the pod named in the trace.
9. *Isolation.* A NetworkPolicy per tier: backends accept only the edge and the test pod; LGTM accepts OTLP from the namespace (spike F2-c: enforcement by minikube's default CNI).
10. *Proving a release.* `helm test` (a pod that posts a query through the edge with the chart's CA), then `smoke.sh` through the published NodePorts; CI renders and validates the chart without a cluster.
11. *Stopping it.* `helm uninstall`, the namespace, `minikube stop -p gql-tracking`; images survive a stop.
12. On the wire / Decision / next (Ch27).

**Example layout**
```
examples/26-minikube/
├── README.md  .gitignore  architecture.svg  architecture.excalidraw
├── helm/                      # Chart.yaml at the top: what CI lints and templates
│   ├── Chart.yaml             # apiVersion v2, name gql-ch26-tracking, version 1.0.0, appVersion "1.0"
│   ├── values.yaml  values.schema.json
│   └── templates/
│       ├── _helpers.tpl  NOTES.txt
│       ├── stack-configmap.yaml  stack-deployment.yaml  stack-service.yaml     # range over .Values.stacks
│       ├── edge-configmap.yaml  edge-deployment.yaml  edge-service.yaml       # nginx.conf rendered from values
│       ├── tls-secret.yaml                                                    # genCA/genSignedCert + lookup
│       ├── lgtm-deployment.yaml  lgtm-service.yaml                            # ClusterIP OTLP + NodePort UIs
│       ├── networkpolicy.yaml  hpa.yaml                                       # hpa off by default
│       └── tests/test-graphql.yaml                                            # helm test hook
└── scripts/
    ├── lib.sh       # sourced: PROFILE=gql-tracking, NS, RELEASE, step/ok/fail, k/h wrappers with --context, preflight
    ├── profile.sh   # create/start/verify gql-tracking with all 15 published NodePorts (also used by Ch27)
    ├── images.sh    # docker build Ch25's Containerfiles -> gql-ch25-{quarkus,python}:1.0 -> minikube image load
    ├── up.sh        # profile.sh, images.sh, helm upgrade --install --wait, rollout status, helm test
    ├── smoke.sh     # the GraphQL assertions through 127.0.0.1:3036x (sources examples/_lib/lib.sh)
    └── down.sh      # helm uninstall --wait, delete the namespace, minikube stop -p gql-tracking
```

**Chart contract** (Ch27 copies and extends it; Appendix A overrides only these keys):
- `stacks.<name>` for `quarkus` and `python`: `image.repository`, `image.tag`, `image.pullPolicy` (`Never` on minikube), `containerPort: 8080`, `probes.{startup,readiness,liveness}.path`, `resources`, `env` (map → ConfigMap), `replicas` (1).
- `edge`: `image` (`registry.access.redhat.com/ubi10/nginx-126:10.2-1791973310`), `tls.enabled` (true; false renders plain listeners 8080/8081 and no Secret mount), `service.type` (`NodePort`; `ClusterIP` allowed), `service.nodePorts.{quarkus,python}` (30360, 30361), `bodyLimit` (`64k`), `tls.sans` (default `localhost`, `127.0.0.1`, the edge Service names).
- `lgtm`: `enabled` (true), `image`, `service.type`, `service.nodePorts.{grafana,tempo,prometheus,loki}` (30362–30365), `serviceAccountName` (for an SCC binding elsewhere).
- `podSecurityContext` / `containerSecurityContext`: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`; **no `runAsUser`, `runAsGroup` or `fsGroup`** (the UBI images run as numeric UIDs 185/1001 and tolerate an arbitrary UID); otel-lgtm gets no `runAsNonRoot` (spike F2-d: the image's user).
- `networkPolicy.enabled` (true), `autoscaling.enabled` (false).
- Labels `app.kubernetes.io/{name,instance,component,part-of,version}`; selector on `app.kubernetes.io/name` and `instance` only.

**Scripts**
- `lib.sh`: `require_docker_engine` (context `default`, socket, no `podman-docker`), `require_tools` (minikube ≥ v1.39.0, kubectl, helm ≥ v4.3.1), `require_no_crc` (`crc status` not Running, when `crc` exists), `require_no_other_profile` (fails, naming `minikube stop -p <name>` for each other running profile; it never stops another profile itself), `kc()`/`hc()` wrappers with `--context gql-tracking` / `--kube-context gql-tracking`.
- `profile.sh`: the skill's `setup-profile.sh` shape: creates or starts `gql-tracking`; on create, `ss -ltn` for every host port, `minikube start -p gql-tracking --driver=docker --container-runtime=containerd --kubernetes-version=v1.37.1 --cpus=6 --memory=12g --disk-size=40g --ports=<15 entries>`; afterwards `docker port gql-tracking <np>/tcp` must show `127.0.0.1:<np>` for all 15; never `minikube config set`; `--replace` deletes and recreates only on that explicit flag.
- `up.sh`: `profile.sh`; `images.sh`; `helm upgrade --install gql-ch26 examples/26-minikube/helm -n gql-ch26 --create-namespace --kube-context gql-tracking --wait --timeout 10m`; `kubectl rollout status` per Deployment; `helm test gql-ch26 -n gql-ch26 --kube-context gql-tracking --logs`.
- `smoke.sh`: sources `examples/_lib/lib.sh`, calls `session_start` (§3), writes the CA from the Secret (`kubectl get secret gql-ch26-edge-tls -o jsonpath='{.data.ca\.crt}' | base64 -d`) to scratch and exports `LGTM_CACERT`, then runs the assertions below. Exits non-zero on the first failure, prints `PASS` at the end.
- `down.sh`: `helm uninstall gql-ch26 --wait`, `kubectl delete namespace gql-ch26 --wait`, `minikube stop -p gql-tracking`. `--keep-running` skips the stop; there is no delete path (profile deletion only with the user's say-so, by hand).

**smoke.sh assertions (live, both stacks; not CI).** URLs `https://127.0.0.1:30360/graphql`, `https://127.0.0.1:30361/graphql`.
1. `docker port gql-tracking` lists all 15 loopback mappings; `helm status gql-ch26` is `deployed`; `helm test` passed (from `up.sh`); every Deployment rolled out; each pod spec's three probe paths equal the values.
2. Ch25 case 3 through the NodePorts (`HEALTHY`, `FanOut` data, `cargos(first: 10)` six edges with the per-stack GHI345 errors); per-stack call counts read with `kubectl exec deploy/quarkus -- curl -fsS localhost:8080/debug/source-calls` (a local `source_calls_kube` in `scripts/lib.sh`).
3. Ch25 cases 4–6 (edge routes only `/graphql`; TLS 1.3 floor; 413 for 100 KB).
4. **The pod in the trace:** `LGTM_TRACEPARENT` set; `cargos(first: 10)` → `extensions.traceId` equals the id; `tempo_trace http://127.0.0.1:30363` by that id; `assert_span_attr` or resource attribute `k8s.pod.name` equals one of `kubectl get pods -l app.kubernetes.io/name=<stack> -o name` (spike F2-e: resource attributes in `tempo_trace`'s normalized document; if they are not carried, read them from Tempo's raw JSON in a local helper).
5. **A configuration change rolls the pods:** `helm upgrade --reuse-values --set stacks.python.env.TRACKING_SOURCE_LATENCY_MS=100 --wait`; the Python Deployment's `checksum/config` changed and its pod name changed; `kubectl exec … env` shows `100`; then set it back to `250`.
6. **NetworkPolicy (spike F2-c):** a pod in the namespace without the edge or test label, `kubectl run` with `ubi10/ubi-minimal`, `curl` to `quarkus:8080/graphql` → refused or timed out; the `helm test` pod (allowed label) reaches it. If the CNI does not enforce policies, assert nothing about enforcement, keep the policy in the chart, and phrase the prose neutrally ("a CNI that implements NetworkPolicy enforces it"); report to the orchestrator.
7. `assert_sdl_conforms` on both NodePort URLs; `assert_deprecated` for `finalArrivalDate`.

**Static checks (executor and CI):** `helm lint --strict examples/26-minikube/helm`; `helm template gql-ch26 examples/26-minikube/helm -n gql-ch26 | kubeconform -strict -summary -kubernetes-version 1.37.1` (expected resource count recorded in the README, e.g. `Valid: N`); a second render with `--set autoscaling.enabled=true,networkPolicy.enabled=false,edge.tls.enabled=false,edge.service.type=ClusterIP` also valid; ShellCheck on `scripts/*.sh`.

**Figures (2)**
- `26-compose-to-kubernetes`: two columns, Chapter 25's Compose concepts on the left and the Kubernetes objects on the right, one row per mapping from H2 1, with the file each lives in (`compose.yaml` key / chart template).
- `26-cluster-topology` (data movement): the host's `127.0.0.1:30360` → the `gql-tracking` node container (Docker-published port) → NodePort Service `edge` → edge pod (TLS Secret volume, `nginx.conf` ConfigMap) → ClusterIP `quarkus` → a ready pod (probes, ConfigMap env, downward API) → OTLP to `lgtm`; the trace in Tempo naming the pod. Values from the live run; docstring names it.

**Citations.** Kubernetes documentation ("Deployments", "Service" (NodePort), "ConfigMaps", "Secrets", "Configure Liveness, Readiness and Startup Probes", "Expose Pod Information to Containers Through Environment Variables", "Network Policies", "Resource Management for Pods and Containers", "Pod Security Standards"); minikube "Basic controls" / `minikube start` flags (`--ports`, `--kubernetes-version`) and "Pushing images" (`image load`); Helm documentation ("Charts", "Chart Tests", "Values Files" / schema files, "Template Function List" (`genCA`, `genSignedCert`, `lookup`), "Chart Development Tips and Tricks" (automatically roll deployments)); OpenTelemetry "Resource semantic conventions: Kubernetes"; kubeconform README; Ch25 by chapter.

### Ch27: The final project

**Files:** `_docs/27-the-final-project.md`, `examples/27-final-project/` (compose `verify.sh`, auto-discovered; plus `helm/` and `scripts/` for the cluster tier).

**What the final project carries** (§8 decision 4, recommended (b)):

| From | Feature in Ch27 |
|---|---|
| Ch13 | seed, batched sources, source-call log (lab endpoint, not routed by the edge) |
| Ch21 | `Subscription.cargoHandled` over `graphql-transport-ws` (both), GraphQL over SSE (Python), the plain SSE feed `GET /events/cargos/{trackingId}` (both); the complete canonical SDL |
| Ch14 | depth, token, alias and cost limits (budget 1000) |
| Ch17 | introspection off on the public instances; internal instances of the same image with introspection on, loopback only |
| Ch18 | Keycloak 26.8.1 realm (copied), bearer validation (`quarkus-oidc`; PyJWT + `PyJWKClient`), per-operation, per-object and per-field authorization, extended to `cargoHandled` and the SSE feed |
| Ch19 / Ch24 | traces, metrics, logs by trace id; `extensions.traceId` on execution errors |
| Ch25 | the edge (TLS 1.3, body limit, now also `/events/` and the WebSocket upgrade), networks, health split, limits, configs, secrets |
| Ch23 | the k6 image and script, reduced to two runs with a bearer token |
| Ch26 | the chart shape, extended |

Left in their own chapters, with one paragraph each in Ch27: Ch15 persisted documents and Ch16 caching (per-shipper, authorized responses are not shared-cacheable; an allowlist is a deploy-time choice the reader adds from Ch15), Ch20 federation (a different topology), Ch22 clients and Ch23's suites (Ch27 runs Ch22's documents under load instead), Ch24's dev instances and seeded fault.

**Learning goals.** By the end of the chapter the reader can:
- assemble the features of the earlier chapters into one service per stack and say why each is there (Figure 27.1);
- trace the order in which a request meets each defence: TLS and body limit at the edge, token validation, document limits, operation, object and field authorization, batched sources, masking, the trace id (Figure 27.2);
- authorize subscriptions at the upgrade and on every event, and the SSE feed by the same rules (Figure 27.3);
- serve the complete schema and prove it equals the contract, with introspection only on internal instances;
- observe and load-test the assembled system with assertions that hold on any machine;
- run the same images in Compose and in the cluster from one chart, and know what Appendix A changes for OpenShift Local.

**H2 outline**
1. *The system* (Figure 27.1) and the table above: what each chapter contributes.
2. *What stays in its own chapter, and why.*
3. *A request's defences, in order* (Figure 27.2), with the response each one gives: `413`, transport failure below TLS 1.3, `401` for a bad token before GraphQL runs, the limit messages with no `data` and no source call, `UNAUTHENTICATED`/`FORBIDDEN` at the field path, a shipper's filtered list, `registrationTime` for operators only, masked unexpected errors with `extensions.traceId`.
4. *Identity on every path.* The edge passes `Authorization` unchanged; tokens are fetched from Keycloak at `localhost:8374`, the issuer each stack pins comes from configuration (`QUARKUS_OIDC_TOKEN_ISSUER`, `TRACKING_OIDC_ISSUER`), which is what lets the same image run in three tiers.
5. *Real-time through the edge* (Figure 27.3): `wss://` through nginx with the upgrade headers; the token on the upgrade request; per-event authorization; the SSE feed with the same check.
6. *The complete schema.* `assert_sdl_equals` on the internal instances; the public instances refuse introspection with Ch17's answer.
7. *Observing it.* One trace from the edge's request to the batched calls; error counts by code; the trace id in every execution error.
8. *Defending it under load.* Two k6 runs through the edge with an operator token: `fanout` (exact calls per request) and `cost` (refused with no call), Ch23's invariants.
9. *Three tiers, one image* (codetabs: the Quarkus and Python env contract): `verify.sh` on Compose; the chart on `gql-tracking`; Appendix A on OpenShift Local.
10. On the wire / Decision / next (Appendix A; the bibliography).

**Example design**
- **Base:** copy Ch25. Port each delta from its chapter onto it, in this order, running `verify.sh` after each: (1) Ch21's subscription code, publisher and SSE feed (and the `client/` subscription client, image `gql-ch27-client:1.0`); (2) Ch14's limits; (3) Ch18's OIDC, ownership and authorization, extended to `cargoHandled` and `/events/cargos/{id}`; (4) Ch17's `TRACKING_PUBLIC` introspection switch (exact variable from Ch17; **spike F3a-b**). Each port keeps the base chapter's names and comments; the code comment names the chapter it comes from. Ch17's in-process TLS is **not** ported (the edge terminates TLS).
- **Subscription authorization (spike F3a-c):** the client sends `Authorization: Bearer …` on the WebSocket upgrade request; Quarkus authenticates the upgrade with `quarkus-oidc` (an HTTP request) and the resolver reads the identity; Strawberry's `context_getter` reads the header from the WebSocket request. `cargoHandled(trackingId)` checks ownership before the first event (a shipper on another shipper's cargo gets an `error` frame with `FORBIDDEN`) and field authorization applies to every event (`registrationTime` null with `FORBIDDEN` for a shipper). Fallback if the upgrade header is not honoured on one stack: the token in the `connection_init` payload, through each framework's documented hook; record which.
- **compose services:** `edge`, `quarkus`, `python` (public, introspection off, network `backend`), `quarkus-internal`, `python-internal` (same images, introspection on, networks `backend` + `ops`, ports on 127.0.0.1), `keycloak` (`start-dev --import-realm`, networks `backend` + `ops`, 127.0.0.1:8374), `lgtm`, and the profiled `client` (`profiles: ["client"]`) and `load` (`profiles: ["load"]`). Edge listeners route `location = /graphql` and `location /events/` (with `proxy_buffering off` for SSE) to the public instances; `/graphql` carries the `Upgrade`/`Connection` map.
- **Load image** `load/`: copy of Ch23's `Containerfile` (ubi-minimal + k6 v2.3.0, sha256-verified) and a reduced `tracking.js` (runs `fanout` and `cost`; `__ENV.TOKEN`; target `https://edge:8443/graphql` or `:8444`; spike F3a-d: k6 trusting the scratch CA via `SSL_CERT_FILE`; fallback: target the public instance over the backend network and say so in the README); documents `fan-out.graphql` and `over-budget.graphql` copied from Ch23 (verify checks byte equality, read-only).
- **Telemetry:** service names `ch27-final-quarkus`, `ch27-final-python` (public); `…-internal` for the internal instances.

**verify.sh assertions (both stacks unless marked).** `LGTM_CACERT` = scratch CA; public URLs `https://localhost:8370/graphql`, `https://localhost:8371/graphql`; internal `http://localhost:8372/graphql`, `http://localhost:8373/graphql`; tokens with `oidc_token http://localhost:8374/realms/shipping/protocol/openid-connect/token tracking-cli <user> <pw>`.
1. **Tier:** all services healthy; only the edge beyond loopback (Ch25 case 2 for every service).
2. **Edge:** TLS 1.3 floor, 413 for 100 KB, `/debug/source-calls` and `/q/health/ready` → 404 through the edge.
3. **Complete contract:** `assert_sdl_equals` on both internal URLs; `assert_deprecated` for `finalArrivalDate`; scalar loop. Public: an introspection query as `ops` is refused with Ch17's per-stack message (spike F3a-b).
4. **Authentication:** anonymous `cargo(trackingId: "ABC123")` → `UNAUTHENTICATED` at `["cargo"]`; a token for `other-cli` (wrong audience) → HTTP 401 through the edge; an `ops` token → `ONBOARD_CARRIER`.
5. **Authorization (Ch18 values):** `ana` `cargos(first: 10)` → exactly VWX901, DEF456, ABC123; `bo` `cargo(trackingId: "ABC123")` → `FORBIDDEN`; `ana` `handlingEvents { registrationTime }` → null with `FORBIDDEN` at that path, `ops` → a value.
6. **Limits before identity:** anonymous `OverBudget` → `maximum query complexity exceeded 7651 > 1000`, no `data`, 0 source calls (`source_calls_in`); Ch14's depth and alias anchors with their messages and 0 calls.
7. **Batching under authorization:** `FanOut` as `ops` → the per-stack calls (8 / 6) and Ch14's key set.
8. **Mutation and subscription through the edge:** `compose_run client` subscribes as `ana` to ABC123 over `wss://edge:8443` / `:8444` (Python also over SSE), then `REG_F1` as `ops` → `evt_10`; the client's frames hold exactly one `next` with `evt_10` and `registrationTime` null with `FORBIDDEN`; a `bo` subscription to ABC123 receives an `error` frame with `FORBIDDEN` and no `next`; the plain SSE feed as `ana` from `Last-Event-ID: evt_9` yields `evt_10`, as `bo` → 403 (spike F3a-c: per-stack status); `TrackCargo` ABC123 → `IN_PORT`; the subscriber registry is empty after the client exits (Ch21's cleanup check).
9. **Observability:** with `LGTM_TRACEPARENT`, `cargos(first: 10)` as `ops` → GHI345's `extensions.traceId` equals the id; `tempo_trace` (8376) has `query ListCargos` and `source.call` spans whose `getLocations` count equals the source-call log's; `loki_wait` (8378) returns a record for that trace id.
10. **Load (k6, ops token):** `run_load` (§3) `fanout` (8 VUs, 80 iterations: `http_req_failed rate==0`, `checks rate==1`, `iterations count==80`; then 80 distinct request ids, each with the per-stack calls and Ch14's key set) and `cost` (40 `FanOut` + 40 `OverBudget`: 40 request ids with calls, refused requests none).

**Cluster tier** (`helm/`, `scripts/`; F3b):
- `helm/`: copy of Ch26's chart, renamed `gql-ch27-final` (version 1.0.0), with: `stacks` gaining `instances: {public: {introspection: false}, internal: {introspection: true, service.nodePort: 30372|30373}}`; `keycloak` (Deployment from `quay.io/keycloak/keycloak:26.8.1`, `start-dev --import-realm`, the realm JSON copied from Ch18 into `files/shipping-realm.json` and mounted from a ConfigMap, readiness/liveness `httpGet` on management port 9000 `/health/ready|live`, NodePort 30374); env `QUARKUS_OIDC_AUTH_SERVER_URL=http://keycloak:8080/realms/shipping`, issuer `http://localhost:30374/realms/shipping` (per-tier value; spike F3b-b: tokens fetched through the NodePort carry that issuer); edge locations `/graphql` (with upgrade) and `/events/`; NodePorts 30370, 30371, 30375–30378; images `gql-ch27-*:1.0`.
- `scripts/`: `lib.sh` (copy of Ch26's with `NS=gql-ch27`, `RELEASE=gql-ch27`), `images.sh` (Ch27's three images + `minikube image load`), `up.sh` (calls `examples/26-minikube/scripts/profile.sh`, then images, `helm upgrade --install … --wait`, `helm test`), `smoke.sh` (cases 2, 3, 4, 5, 7 and 9 above through NodePorts 30370–30378; the subscription case 8 as a Kubernetes Job from `gql-ch27-client:1.0`, spike F3b-c), `down.sh` (as Ch26).
- Static: `helm lint --strict`; `helm template | kubeconform -strict -kubernetes-version 1.37.1`; a render with the Appendix A overrides (`edge.tls.enabled=false`, every `service.type=ClusterIP`, images pointed at an ImageStream path) also valid.

**Figures (3)**
- `27-final-architecture`: the components and networks of the compose tier (edge; public and internal instances per stack; Keycloak; LGTM; the client and load profiles), each labelled with the chapter it comes from.
- `27-request-defences` (data movement): one request's path through the defences in order, with the answer each defence gives on refusal (`413`, TLS failure, `401`, limit message with 0 source calls, `UNAUTHENTICATED`/`FORBIDDEN` with the path, filtered list, null field) and the success path to batched sources and `extensions.traceId`. Values from the run.
- `27-subscription-path` (data movement): `ana` upgrading through the edge with a bearer token; `ops` registering `REG_F1`; the handling store → broadcast → a fresh execution per event with ownership and field checks → `next` to `ana`, `error` `FORBIDDEN` to `bo`; the SSE feed beside it. Values from the run.

**Citations.** Earlier chapters by number; the GraphQL specification "Subscription" and "Validation"; the `graphql-transport-ws` protocol document; GraphQL-over-HTTP (current draft) for status codes as recorded in Wave B; Keycloak "Server administration" / "Importing a realm" (by page title); Quarkus "OpenID Connect (OIDC) Bearer token authentication" and "SmallRye GraphQL"; Strawberry "Subscriptions" and "Authentication" (by page title); k6 "Thresholds"; *Full Stack GraphQL Applications* Ch7 "Adding authorization and authentication" and Ch9 "Advanced GraphQL considerations" (verified); a deployment chapter of that book only by verified title (**spike**).

### Appendix A: OpenShift Local (CRC)

**Files:** `_docs/99-appendix-a-openshift-crc.md`, `examples/99-appendix-a-openshift-crc/` (cluster tier, **no `verify.sh`**). Validated **statically**; the scripts are written and checked but executors never start CRC (§8 decision 7).

**Learning goals.** By the end of the appendix the reader can:
- deploy Chapter 27's chart to OpenShift Local unchanged, through a wrapper chart that adds only OpenShift objects (Figure A.1);
- build the images inside the cluster from the same Containerfiles with a Docker-strategy BuildConfig and binary input (Figure A.2);
- expose the edge through Routes with edge TLS at the router and reach it with the cluster's ingress CA (Figure A.3);
- run a chart under the `restricted-v2` SCC without fixing a UID, and grant the one documented exception;
- validate the whole release offline, and return OpenShift Local to the state it was in.

**H2 outline**
1. *Same chart, another distribution* (Figure A.1): the wrapper's `Chart.yaml` dependency on `file://../../27-final-project/helm`; the values it overrides (`edge.tls.enabled: false`, `ClusterIP` services, image references, issuer); nothing in the application or the dependency changes.
2. *Projects and `restricted-v2`.* The chart sets no UID; the UBI images run under the namespace's assigned UID with GID 0; `otel-lgtm` runs under `anyuid` through a RoleBinding the wrapper adds for its ServiceAccount.
3. *Building in the cluster* (Figure A.2): BuildConfig (Docker strategy, binary source, `dockerfilePath: Containerfile`) and ImageStream per image; `oc start-build gql-ch27-quarkus --from-dir examples/27-final-project/quarkus --follow`; Deployments reference `image-registry.openshift-image-registry.svc:5000/gql-appendix-a/gql-ch27-quarkus:1.0` with `IfNotPresent`.
4. *Routes* (Figure A.3): edge termination at the router, `insecureEdgeTerminationPolicy: Redirect`, target the edge Service's plain listener; one Route per stack, the internal instances, Keycloak and Grafana; WebSocket and SSE through the router; `curl --cacert` with `default-ingress-cert`.
5. *Identity on Routes.* Keycloak behind its Route; the issuer value is that Route's URL.
6. *What CI checks.* `helm dependency build`, `helm lint --strict`, `helm template | kubeconform -strict` against Kubernetes 1.35.6 and the pinned OpenShift schemas; `bash -n` and ShellCheck on the scripts.
7. *Running it.* The order: stop minikube, `crc start`, `eval "$(crc oc-env)"`, the inventory, `up.sh`, `smoke.sh`, `down.sh`.
8. *Leaving it clean.* The teardown order and the leftover check.
9. On the wire (the static commands and their recorded output; the live commands listed as commands, without claimed output), Decision, next.

**Example layout**
```
examples/99-appendix-a-openshift-crc/
├── README.md  .gitignore (helm/charts/)  architecture.svg  architecture.excalidraw
├── helm/
│   ├── Chart.yaml         # name gql-appendix-a, version 1.0.0; dependencies: gql-ch27-final 1.0.0, repository file://../../27-final-project/helm, alias final
│   ├── Chart.lock         # committed; `helm dependency build` restores charts/
│   ├── values.yaml        # final.* overrides + openshift.{routes,builds,anyuid}
│   └── templates/ _helpers.tpl  routes.yaml  buildconfigs.yaml  imagestreams.yaml  lgtm-anyuid-rolebinding.yaml  NOTES.txt
└── scripts/
    ├── lib.sh       # PROJECT=gql-appendix-a, RELEASE, OCP_CONTEXT=crc-admin; require_crc (api.crc.testing, no running minikube profile), wait_for, step/ok/fail
    ├── up.sh        # inventory (read-only) -> oc new-project -> helm install with builds only -> oc start-build x3 --follow -> helm upgrade with the app -> oc rollout status
    ├── smoke.sh     # ingress CA -> Routes: TLS, FanOut, auth (token via the Keycloak Route), SDL equals via the internal Route, traceId
    └── down.sh      # teardown (below), then crc stop unless --keep-running
```

**Teardown (`down.sh`), in order:** (1) `helm uninstall gql-appendix-a --wait`; (2) `oc delete project gql-appendix-a` and `wait_for` until gone (BuildConfigs, ImageStreams, builds, the RoleBinding and every pod go with it); (3) operators: the script carries `OPERATORS=()` (empty, the appendix installs none) and the skill's removal loop (Subscription → read `installedCSV` and owned CRDs → delete Subscription, CSV, InstallPlans, CRDs), so an operator added later is removed too; (4) leftover check: no namespace, Subscription, CSV or CRD labelled or named `gql-appendix-a`; the non-system namespaces and `oc get sub,csv -A` equal the inventory `up.sh` saved (scratch); anything foreign is printed and left alone; (5) `crc stop` unless `--keep-running`. It never touches another project's resources.

**Static checks (executor and CI):** `helm dependency build examples/99-appendix-a-openshift-crc/helm`; `helm lint --strict`; `helm template gql-appendix-a … -n gql-appendix-a | kubeconform -strict -summary -kubernetes-version 1.35.6 -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/63669a570e231d4f1f8396d229a1de512bcf0a34/openshift/v4.15-strict/{{ .ResourceKind }}_{{ .Group }}_{{ .ResourceAPIVersion }}.json'` (spike F4-a: the template resolves `route_route.openshift.io_v1.json`); the rendered pods contain no `runAsUser`, `runAsGroup` or `fsGroup` except the lgtm RoleBinding's subject (a `grep` in the executor's check); ShellCheck and `bash -n` on `scripts/*.sh`.

**Figures (3)**
- `A-same-chart-on-openshift`: the Ch27 chart in the middle, the minikube values on the left (NodePorts, `pullPolicy: Never`, chart TLS), the wrapper on the right (Routes, BuildConfigs, ImageStreams, the anyuid RoleBinding, `ClusterIP`, router TLS); the unchanged application images below both.
- `A-in-cluster-build` (data movement): `oc start-build --from-dir` uploading the Ch27 `quarkus/` directory → the BuildConfig's Docker build of `Containerfile` → the ImageStream tag `1.0` → the Deployment's image reference → the pod. Values from the rendered manifests (no live run); docstring says so.
- `A-route-to-edge` (data movement): client → router (edge TLS, ingress CA) → edge Service plain listener → public instances; the WebSocket upgrade and SSE passing through; the Keycloak and internal Routes.

**Citations.** OpenShift documentation (by page title: "Route configuration" / "Secured routes", "Builds using BuildConfig" (Docker strategy, binary builds), "Managing image streams", "Managing security context constraints"); Red Hat OpenShift Local "Getting started" (crc start, `crc oc-env`); Helm "Chart Dependencies"; kubeconform README (`-schema-location`); Ch26 and Ch27 by chapter. Decks get no OpenShift slides (user decision 2026-10-12).

---

## 3. Harness and CI additions (F0)

### `examples/_lib/lib.sh` (backward compatible, `bash -n` and ShellCheck clean, stdlib `python3 -I` only, documented in the README table)

| Function | Contract |
|---|---|
| `session_start` | Installs the harness EXIT trap without a compose stack, so `on_exit` hooks run for scripts that never call `compose_up` (Ch26/Ch27 `smoke.sh`). Idempotent; a later `compose_up` keeps one trap. |
| `compose_exec_http <service> <method> <path> [curl-args...]` | `docker compose -p <project> -f <file> exec -T <service> curl -sS -X <method> -w …` against `http://localhost:8080<path>` inside the container; output as `http_any` (status line, then body). For endpoints the edge does not route. |
| `source_calls_in <service>` / `source_calls_reset_in <service>` | The source-call log of a backend reached inside its container (`compose_exec_http … /debug/source-calls`); reset expects 204. Same JSON as `source_calls`. |
| `compose_inspect <service> <go-template>` | `docker inspect -f <template>` on the service's container id from `docker compose ps -q`; FAIL when the service has no container. |
| `run_load <service> <run> <expected-iterations> [-e K=V ...]` | Promoted from Ch23's local helper: `compose_run` the load service with `RUN=<run>`, parse the JSON summary from stdout, assert `metrics.iterations.values.count` and `metrics.checks.values.rate == 1`; print the summary path. |

**F0 self-test:** `bash -n`; ShellCheck; Ch0, Ch19 and Ch23 `verify.sh` green (Ch23 switched to the promoted `run_load` only if its behaviour is identical; otherwise Ch23 is not touched and the helper is new); `session_start` + `on_exit` in a throwaway script in scratch; `compose_exec_http` and `source_calls_in` against Ch19's stack started by a scratch script.

### `.github/workflows/contracts.yml`, job `k8s-manifests`

Replace the three validation steps with (each keeps the "not present yet" branch, so the job is green before the charts land):
1. **Install ShellCheck** v0.11.0 from the GitHub release tarball with a recorded sha256, like kubeconform.
2. **Ch26 chart:** `helm lint --strict examples/26-minikube/helm`; `helm template gql-ch26 examples/26-minikube/helm -n gql-ch26 | kubeconform -strict -summary -kubernetes-version 1.37.1`; the same with `-f examples/26-minikube/helm/ci-values-alt.yaml` if the executor ships one (the alternate render of §2), else the `--set` list.
3. **Ch27 chart:** the same for `examples/27-final-project/helm` (release `gql-ch27`), plus a render with the Appendix A override values.
4. **Appendix A chart:** `helm dependency build`, `helm lint --strict`, `helm template gql-appendix-a … | kubeconform -strict -summary -kubernetes-version 1.35.6 -schema-location default -schema-location '<pinned datree URL template>'`. `-ignore-missing-schemas` is dropped.
5. **Cluster scripts:** `shellcheck -x examples/26-minikube/scripts/*.sh examples/27-final-project/scripts/*.sh examples/99-appendix-a-openshift-crc/scripts/*.sh` (each glob guarded by `shopt -s nullglob`).

No change to `discover-examples`, `examples` (timeout stays 60 unless §8 decision 9 changes it), `examples-summary` or `ci-ok`.

---

## 4. Acceptance criteria

**Per chapter (Ch25, Ch26, Ch27, A)**
- `_docs/<file>.md` with valid front matter (`part:` "Running It & the Final Project", `order` 25/26/27/99; A with `appendix: true`, `appendix_label: "A"`); `bash scripts/wordcount.sh` reports 2,800–3,400.
- Figures at `assets/diagrams/<name>.{svg,excalidraw}` with a spec `diagrams/<name>.py` that regenerates byte-identically, embedded with full-sentence alt text and a `Figure N.M — …` caption, rendered to PNG and viewed by the executor and by FVn: Ch25 2, Ch26 2, Ch27 3, A 3.
- `## On the wire` matches the script that proves it (verify.sh, smoke.sh or the static checks), then the Decision callout naming Ch2's axes, then `## Where this goes next`; at least one codetabs pair.
- The example dir has README (sections per §2), `.gitignore`, `architecture.svg` + `.excalidraw`; compose dirs also `compose.yaml` (fixed `name:`, pinned images only), executable `verify.sh`, `quarkus/` and `python/` with a re-generated `uv.lock`; cluster dirs `helm/` (Chart.yaml at the top) and `scripts/`, **no `verify.sh`**.
- No planning language: `grep -rniE 'wave [a-z0-9]|\bS[0-9]{1,2}\b|\bF[0-9][ab]?\b|\br0[0-9]\b|iteration[^s]|capstone|coverage matrix|phase [0-9]|TODO|TBD|spike' _docs/2[5-7]-* _docs/99-* examples/2[5-7]-*/README.md examples/99-*/README.md examples/2[67]-*/helm examples/99-*/helm` returns nothing (k6's "iterations" is allowed; the validator reads each hit).
- Content and platform rules: FVn reads every reader-facing line, including chart comments, `NOTES.txt` and script messages, for rule-13/14 hits; 0 allowed. `lgtm-professional-voice`: 0 ban-tier findings. `lgtm-idiomatic-review` (Quarkus, FastAPI, Kubernetes/Helm): 0 unresolved substantive findings.

**Chapter-specific**
- **Ch25:** `verify.sh` prints `PASS` with every §2 case on both stacks; the backends have no published port; `413` at the edge for 100 KB; TLS 1.2 refused; the trace id sent to the edge is found in Tempo and Loki; limits, restart policy, log driver and stop timeout read back as configured.
- **Ch26:** `helm lint --strict` clean; both renders pass `kubeconform -strict` at 1.37.1; the live run (§8 decision 6) passed `up.sh` (including `helm test`) and `smoke.sh`, and `down.sh` stopped the profile; the README records the date, versions, `kubeconform` summary and the smoke output.
- **Ch27:** `verify.sh` prints `PASS`; `assert_sdl_equals` on both internal instances; every defence answers as listed; the subscription case passes on both stacks; both k6 runs meet their thresholds and per-request invariants; the chart passes both renders; the live cluster smoke passed and the profile is stopped.
- **Appendix A:** `helm dependency build` + `helm lint --strict` + `kubeconform -strict` (1.35.6 + pinned OpenShift schemas) clean; no `runAsUser`/`runAsGroup`/`fsGroup` in rendered pods; `down.sh` implements every teardown step of §2; ShellCheck clean; the prose claims no live CRC output.

**For the wave**
- `python3 -I scripts/validate.py` exits 0 (checked via `$?`); `GATE=1 bash scripts/wordcount.sh` passes; Jekyll build in the `ruby:3.3` container is clean.
- `npm --prefix contracts run lint` and `run breaking` pass; **the `contracts/` diff is empty**; the `.github/` diff is F0's `k8s-manifests` change only.
- **27 example dirs** (`ls -d examples/[0-9]*/ | wc -l` = 27); `examples/*/verify.sh` = 25 (all but `26-minikube` and `99-appendix-a-openshift-crc`).
- All compose `verify.sh` (Ch0, Ch3–Ch25, Ch27) can run concurrently on one host (port rule; Ch27 needs ~5 GB).
- On PR #1: `verify: 25-docker-compose`, `verify: 27-final-project`, `k8s-manifests` and `ci-ok` green.
- Site figure total = **89** (`ls assets/diagrams/*.svg | wc -l`), each with a spec.
- **Forward references delivered** (FVn checks each against the shipped text): Ch17:23, Ch17:182, Ch24:314, `_lib` README `assert_sdl_equals`, Ch14/Ch18 "production would run them together", the Part 12 blurb, `index.html:51–54`.
- **Deliberate fixes (FW, never as side effects).** If an FV finds a forward statement the shipped chapter does not meet, the validator drafts a one-clause fix and the orchestrator applies it in its own `fix(§N)` commit, re-verified.
- **Host state at hand-back:** `minikube profile list` shows `gql-tracking` Stopped (every other profile untouched); `crc status` Stopped; no compose project of this wave running.

---

## 5. Risks and detection

| Risk | Detection / mitigation |
|---|---|
| minikube v1.39.0 does not start v1.37.1 | Spike F2-a (dry-run already passes); fall back to v1.37.0 (minikube's newest listed) and record it. |
| Published ports collide with a host service | `profile.sh` runs `ss -ltn` for all 15 before `minikube start`; fail with the owner. |
| Another cluster running (memory pressure, CRC dedicated elsewhere) | `require_no_crc`, `require_no_other_profile` in every cluster script; §10 checklist before the live token is handed out. |
| nginx on UBI cannot write its runtime paths as UID 1001 or under `restricted-v2` | Spike F1-b; mount `emptyDir`/tmpfs for the paths it writes; the chart sets no UID. |
| Bind-mounted compose secrets unreadable by nginx's UID | Spike F1-a; generate the files 0644 in the scratch dir (lab keys); README states it. |
| Restart-policy case depends on how the engine classifies the stop | Spike F1-d; assert the policy value instead and record. |
| Graceful-stop case is timing-sensitive | `TRACKING_SOURCE_LATENCY_MS=250` makes `FanOut` take ≥ 1 s; the stop is sent after the request is in flight (poll the source-call log for the first call, no fixed sleep). |
| Chart-generated certificate changes on every `helm template` | Expected under `helm template` (CI); `lookup` keeps it across `helm upgrade` on a cluster; the checksum annotation covers only the ConfigMap, not the Secret. |
| NetworkPolicy not enforced by minikube's default CNI | Spike F2-c; keep the policy, drop the enforcement assertion, neutral prose. |
| Resource attributes not in `tempo_trace`'s normalized output | Spike F2-e; local helper reads Tempo's raw JSON. |
| Porting four deltas onto Ch25 regresses an earlier behaviour | Port in the fixed order; run `verify.sh` after each; FV3 diffs each ported file against its source chapter. |
| WebSocket authentication differs per stack | Spike F3a-c; fallback through `connection_init` with each framework's documented hook; both stacks asserted. |
| Issuer mismatch between tiers | Issuer is configuration per tier (compose `localhost:8374`, cluster `localhost:30374`, OpenShift the Route); verify and smoke assert a token is accepted. |
| k6 does not trust the scratch CA | Spike F3a-d; fallback: the backend network target, stated in the README. |
| Ch27 CI time above the 60-minute budget for three attempts | Spike F3a-a measures a cold attempt; above 18 min, §8 decision 9 (b). |
| OpenShift schema template does not resolve | Spike F4-a; fix the template; never fall back to `-ignore-missing-schemas` without the orchestrator's sign-off. |
| `file://` dependency drifts from Ch27's chart | CI runs `helm dependency build` on every push, so the appendix always renders the current Ch27 chart; `Chart.lock` digest refreshed by F4 after F3b's last chart change. |
| Prose claims a CRC result that was never produced | FV4 checks every "On the wire" line against the static outputs; live commands are listed without output. |
| A reader-facing line presents a framework or platform as at fault | Content rule; FVn line-by-line read; S12b sweep. |

---

## 6. Coverage-matrix and plan updates (orchestrator only)

1. **At each chapter checkpoint** (same commit): T26 Ch25, T27 Ch26, T28 Ch27 and R1, R2, R3 (Appendix A) to `draft` in the Topics, Runtime-tier and Full chapter inventory tables. Run `python3 -I scripts/validate.py; echo $?` and `GATE=1 bash scripts/wordcount.sh`. Push.
2. **Verified:** after FVn passes **and** CI is green (Ch26 also the live run; Appendix A the static checks).
3. Diagram budget table unchanged (25:2, 26:2, 27:3, A:3). Record the Wave F count (10; site total 89) in the RESUME POINTER.
4. `_example_pages/index.md`, rows 25, 26, 27, A:
   - **25**: The tracking view as one local tier: an nginx edge with TLS 1.3 and a body limit in front of both stacks, an internal backend network, configs and secrets as files, health-ordered start, limits and restart policies, and a trace followed from the edge to Tempo and Loki.
   - **26**: One Helm chart for both stacks on minikube (Docker Engine, containerd): ConfigMaps, a chart-generated TLS Secret, startup/readiness/liveness probes, NodePorts published at cluster creation, the pod named in each trace, `helm test`.
   - **27**: The complete schema behind one edge: subscriptions over WSS and SSE, query limits, Keycloak tokens with operation, object and field authorization on every path, introspection on internal instances only, telemetry by trace id and a k6 run; the same system as a Helm chart.
   - **A**: Chapter 27's chart on OpenShift Local through a wrapper chart: in-cluster Docker builds, Routes with edge TLS at the router, `restricted-v2`, and a teardown that returns the cluster to its prior state.
5. `_plans/domain-glossary.md`: add **Edge** (the TLS-terminating proxy in front of the stacks), **Tier** (compose, minikube, OpenShift Local), **Published NodePort**, **Wrapper chart**, **Internal instance**.
6. RESUME POINTER: S11 done with date and spike findings (K8s patch used, nginx writable paths, secret file mode, restart classification, shutdown property, NetworkPolicy enforcement, resource attributes, WebSocket auth seam per stack, k6 CA, CI minutes per attempt, kubeconform OpenShift template); `iteration-plan.md` S11 → done.
7. Commits on `r01`, one checkpoint per step: `chore(r01.x): Wave F harness and k8s-manifests job (Helm charts, OpenShift schemas, ShellCheck)` for F0; `docs(§25): …`, `docs(§26): …`, `docs(§27): …`, `docs(§A): …`; `fix(§N): …` for repair rounds; `docs(r01): Wave F verified`. Push after each and watch CI.
8. Append **§9 "Wave F findings"** at FW, engineering notes only, in the neutral form of Wave E's §9.

---

## 7. Binding pitfalls carried forward (every Wave F executor)

**From Waves A–E (still binding):** Wave A §7 items 1–10 and §9–§10 handoffs; Wave B §9 (masking allowlist and `DeclaredErrorCodeProvider`; per-field SmallRye batching and blast radius; one `__Type.fields` per request; whole-second times; `ensure_contracts_tools`; `compose_up` runs `down -v`; `validate.py` exit code checked directly); Wave C §7 and §9 (reader-facing text is a tutorial; test code shows behaviour, not recipes; `status_of` without a pipe; no `producer | head` under `pipefail`); Wave D §9 (telemetry by the caller's trace id; per-stack span names; no fixed sleeps before a "nothing changed" check; `compose_run` with `COMPOSE_PROGRESS=quiet`; docs cited by page title; frame lists exclude `ping`/`pong`; fresh DataLoaders per subscription event; an order assertion needs concurrent input); Wave E §7 E-1…E-10 and §9 (tests and builds only in UBI images; exact counts; only a concurrent run tests a lock; dev-mode flags; lab debug endpoints behind `TRACKING_DEBUG_ENDPOINTS`).

**New in Wave F (binding):**
- **F-1.** Host access to a cluster is a NodePort published at profile creation on `127.0.0.1`; scripts and prose use nothing else. A missing port means recreating the profile, which only the orchestrator approves.
- **F-2.** Every cluster command names its target: `minikube -p gql-tracking`, `kubectl --context gql-tracking`, `helm --kube-context gql-tracking`, `oc --context crc-admin`. No script reads or changes the current context; none runs `minikube config set`.
- **F-3.** One cluster at a time. A cluster script fails (it does not stop anything) when CRC or another minikube profile is running. Teardown stops; it never deletes a profile or the CRC instance.
- **F-4.** Images reach minikube by `docker build` + `minikube image load` with `imagePullPolicy: Never`; on OpenShift by BuildConfig into an ImageStream. The Containerfiles are the compose tier's, unchanged.
- **F-5.** The charts set no `runAsUser`, `runAsGroup` or `fsGroup`; selectors use `app.kubernetes.io/name` and `instance` only; config changes roll pods through a checksum annotation.
- **F-6.** Configuration is environment and files: one env contract per stack, the same keys in compose `env_file`, the chart's ConfigMap and the appendix values. No tier-specific code path in the application.
- **F-7.** OpenShift objects exist only under `examples/99-appendix-a-openshift-crc/`. The Ch26/Ch27 charts render no `route.openshift.io`, `build.openshift.io`, `image.openshift.io` or `security.openshift.io` object.
- **F-8.** Cluster dirs never contain a file named `verify.sh`, at any depth. Their proof scripts are `up.sh`, `smoke.sh`, `down.sh`.
- **F-9.** Prose reports only outputs that were produced: Ch26/Ch27 cluster outputs from the recorded live run, Appendix A from the static checks. A command not run is shown as a command.
- **F-10.** The edge routes only what the chapter names (`/graphql`; Ch27 also `/events/`); lab endpoints are asserted unreachable through it and read inside the container.
- **F-11.** CRC teardown removes only what this appendix created and compares against the pre-run inventory; anything foreign is printed and left alone.

---

## 8. Open decisions needing user input (each with a recommendation)

1. **Kubernetes version (minikube).**
   - (a) **v1.37.1**: newest patch of the newest minor; minikube v1.39.0 accepts it (dry-run passes) and lists v1.37.0 as its newest; matches the kubectl CI already pins; schemas exist. Fallback v1.37.0 if spike F2-a fails.
   - (b) v1.37.0: minikube's newest listed version, preloaded.
   - (c) v1.36.5: the lgtm-minikube-stack pin, which other workshops use because KEDA and CNPG stop at 1.36; this book installs neither.
   **Recommend (a).** Appendix A validates against 1.35.6, the version OpenShift 4.22.14 ships.
2. **Helm chart layout.**
   - (a) **One chart per cluster example, both stacks in one chart** through a `stacks:` map; Chart.yaml at the top of `helm/` in `26-minikube`, `27-final-project` and `99-appendix-a-openshift-crc`; Ch27's chart is a copy of Ch26's extended; Appendix A is a wrapper chart with a `file://` dependency on Ch27's.
   - (b) One chart per stack (four charts plus an umbrella): duplicates the edge, LGTM and Keycloak, and a release no longer matches a compose project.
   - (c) One shared chart under a top-level `charts/` used by every tier: breaks the self-contained example convention and CI's per-dir layout.
   **Recommend (a).**
3. **Ingress approach on minikube.**
   - (a) **NodePort only**, with the chart's nginx edge (the same `ubi10/nginx-126` and config as Ch25) behind a NodePort Service: no controller, the same TLS, body limit and WebSocket handling in every tier; matches the skills and the published-NodePort rule.
   - (b) Gateway API with Envoy Gateway v1.9.2 (Gateway API v1.6.3): the standard API, but a controller, CRDs and pins to maintain, and its data plane still needs a NodePort.
   - (c) The ingress addon: ingress-nginx is archived upstream, and the REST sibling's Ingress needed a Host header and the node IP.
   **Recommend (a).** Ch26 prose names Gateway API as the shape for a shared cluster in one neutral paragraph.
4. **Ch27 scope.**
   - (a) Everything: (b) plus Ch15 persisted documents, Ch16 caching and Ch24's dev instances. The authorized, per-shipper responses are not shared-cacheable, and the merge risk roughly doubles.
   - (b) **The complete schema and the defences**: Ch13 + Ch21 + Ch14 + Ch17 (introspection) + Ch18 + Ch19/Ch24 (telemetry, traceId) + Ch25 (edge, tier) + a two-run k6 load, as tabled in §2; `verify.sh` (compose, auto-discovered) **and** a cluster chart (static in CI, live by the executor).
   - (c) Lean: Ch25 + Ch21 only (complete schema, no auth or limits): misses "defend" in the Part 12 blurb and the Ch14/Ch18 forward statements.
   **Recommend (b).** Sub-decision: include the k6 run (recommended) or leave load to Ch23.
5. **Ch25's example dir.** (a) **Its own dir `25-docker-compose`** (canonical list; copy of Ch24's production instances with the edge, networks and health split; its images are the ones Ch26 deploys); (b) reuse Ch24's dir and images (Ch24 carries a seeded fault and dev instances that a tier should not). **Recommend (a).**
6. **Live minikube proof.** (a) **Yes**: the F2 and F3b executors each hold the live token in turn, run `up.sh`, `smoke.sh`, `down.sh` on profile `gql-tracking` (created once, 6 CPU / 12 GiB / 40 GB disk, Kubernetes v1.37.1, 15 loopback NodePorts) and record the output in the README; `down.sh` ends with `minikube stop -p gql-tracking`. (b) Static only, like Appendix A. **Recommend (a)**; CI stays static.
7. **CRC live run.** (a) **No (default)**: Appendix A is validated statically (helm dependency/lint/template, kubeconform with OpenShift schemas, `bash -n`, ShellCheck); the prose shows live commands without output. (b) One live run after your explicit go-ahead: minikube stopped, `crc start`, inventory, `up.sh`, `smoke.sh`, `down.sh` (removes release, project, and any Subscription/CSV/CRD it added; none planned), `crc stop`. The CRC is dedicated to datamesh, so (b) needs your approval at the time. **Recommend (a).**
8. **Example-dir count.** With `25-docker-compose`, `26-minikube`, `27-final-project` and `99-appendix-a-openshift-crc` the count is **23 + 4 = 27**, meeting the criterion; 25 of them carry `verify.sh`. **Recommend accepting as planned**; no other dir is added (Ch27's chart lives inside `27-final-project`).
9. **CI changes.**
   - (a) **Rewrite the `k8s-manifests` validation steps for Helm** (lint `--strict`, template, kubeconform `-strict` at 1.37.1 for Ch26/Ch27 including an alternate render; `helm dependency build` and kubeconform at 1.35.6 with the pinned OpenShift schemas for Appendix A, dropping `-ignore-missing-schemas`), add a pinned ShellCheck step for the cluster scripts, keep `timeout-minutes: 60`. One owner (F0).
   - (b) As (a), and raise the examples job's `timeout-minutes` to 75 if a cold Ch27 attempt measures more than 18 minutes (spike F3a-a).
   - (c) Keep kustomize and render the charts to static `k8s/` directories for the existing steps: two sources of truth.
   **Recommend (a), with (b) only if the measurement requires it.**
10. **Host ports for the cluster tier.** (a) **Host port = NodePort = 30100+10·N+k on 127.0.0.1** (Ch26 30360–30365, Ch27 30370–30378; the skill's "host port = NodePort" rule; no collision with any compose port, so a compose verify can run beside the cluster); (b) host ports in the compose block (`127.0.0.1:8360:30360`): reads like the chapter rule but Ch27's cluster and compose tiers would both want 837x. **Recommend (a).**
11. **Observability backend in the cluster.** (a) **`grafana/otel-lgtm:0.37.0` as one Deployment in each chart** (parity with Compose, already pinned, ~1.5 GB); (b) the skill's split stack (`setup-lgtm.sh`: Grafana, Loki, Tempo, Mimir charts and a collector), more pins and ~6 GB. **Recommend (a)**; Ch26 prose names the split stack as the shape for a shared cluster.
12. **Appendix A exposure.** (a) **Edge-TLS Routes at the router to the chart's edge on its plain listener** (`edge.tls.enabled=false`): the skill's Route idiom with the ingress CA, while the edge keeps the body limit, routing and the upgrade; (b) passthrough Routes to the chart's own TLS edge (identical TLS to minikube, custom CA); (c) Routes straight to the backends with the edge disabled (loses the body limit and the routing rules). **Recommend (a).**
13. **Images on OpenShift Local.** (a) **Docker-strategy BuildConfigs with binary input from the Ch27 directories** (same Containerfiles, no pom change, no host engine); (b) binary S2I with `quarkus-openshift` (the skill's Quarkus path: adds a Maven profile to the pom, Python needs a separate path); (c) push from the host's Docker Engine to the exposed internal registry (needs the registry route and a login). **Recommend (a).**
14. **Canonical SDL additions.** **Recommend none**; the `contracts/` diff stays empty.

### Critical files for implementation
- `examples/24-debugging/` (Ch25 base), `examples/21-real-time/`, `examples/14-query-cost/`, `examples/18-authn-authz/` (realm, OIDC config, ownership), `examples/17-transport-security/` (`gen-certs.sh`, the public/internal switch), `examples/23-testing/load/` and `documents/` (read-only sources for Ch25/Ch27)
- `examples/_lib/lib.sh`, `examples/_lib/README.md`, `.github/workflows/contracts.yml` (F0)
- `scripts/validate.py` (read-only: `CLUSTER_TIER_DIRS`)
- `~/.claude/skills/lgtm-minikube-stack/templates/{setup-profile,build-image}.sh.template`, `~/.claude/skills/lgtm-crc/references/{teardown,chart-patterns}.md`, `~/Dev/api-patterns-and-practices-grpc/examples/99-appendix-a-openshift-crc/scripts/{lib,teardown}.sh` (read-only templates)
- `_plans/coverage-matrix.md` (orchestrator)

---

## 9. Wave F findings

Engineering notes only. They bind later work unless noted.

- **nginx in Compose resolves backends through the network DNS** (`resolver 127.0.0.11 valid=10s` with `set $backend …; proxy_pass $backend;`), so a restarted container is found at its new address. In the cluster the edge uses stable Service names.
- **Port checks don't depend on the Compose version.** `docker compose port` prints `:0` or an empty line for an unpublished port, so accept both. Also read `HostConfig.PortBindings`: a container on an internal-only network gets no runtime binding even when it declares one.
- **`restart: unless-stopped`** restarts a process that exits on its own. A `compose stop` or `kill` is an operator request and leaves the container stopped. To demonstrate a restart, send `SIGTERM` to PID 1 from inside the container.
- **Graceful stop:** guard that the in-flight request has not finished before the stop begins. The JVM exits with 143 after its shutdown hooks run.
- **minikube:** use `--keep-context`. A running profile reports `OK`. minikube v1.39.0 runs Kubernetes v1.37.1 and prints only version-list warnings. kindnet enforces NetworkPolicy.
- **Tokens fetched through a NodePort carry the issuer of the host name used.** Fetch them at `localhost:<np>`, which matches the configured issuer.
- **OpenShift `anyuid` lists no seccomp profiles,** so a pod that names one drops to `restricted-v2`. The Ch27 chart makes `lgtm.seccompProfile` a value, and Appendix A leaves it empty for that pod only. In Helm 4.3.1, a parent's `null` does not remove a subchart default, so use a string value.
- **Keycloak behind an edge-TLS Route** reads `KC_PROXY_HEADERS=xforwarded`, so the issuer is the Route's `https` URL. The back channel stays plain HTTP inside the project.
- **The wrapper's `final:` block equals Ch27's `ci-values-appendix-a.yaml`.** Keep them identical (a candidate CI check at S14).
- **Subscriptions on Quarkus:** `SubscriberIdentity` gives each event the subscriber's identity, and `SubscriptionGate` checks admission when the stream is created. A field refused on a non-null event nulls the whole event (Ch4), so the audit selection sits under a nullable parent.
- **Plan §2 Ch27 case 5 was wrong.** `bo` on `cargo(ABC123)` gets `data.cargo` null with no error, as Ch18 verified.
- **CI:** a Maven Central "artifact absent" error failed one Quarkus image build twice this iteration (Ch14 at e5710fb, Ch25 at 32f3390), and re-running the failed jobs passed both times. If it recurs, harden the Quarkus Containerfiles, for example with a cached Maven layer or retries on dependency resolution.
- **Host:** Helm on the host must be the latest stable (4.3.1). Give the user checksum commands that compare the hash directly.
- **Kubernetes version:** always the latest stable (user rule 2026-10-17). The `lgtm-minikube-stack` pin refresh (branch `minikube-pin-refresh`, 2e9b99f) still needs its live run: KEDA and CNPG on 1.37.1.

---

## 10. Teardown and host hygiene

**Before any live step** (checked by the orchestrator before handing out the live token, and again by `lib.sh`):
- `crc status` → Stopped (it is, 2026-10-17). CRC is never started in this wave without §8 decision 7 (b).
- `minikube profile list` → every profile Stopped (capstone, cndp-k8s, datamesh, eip, helm4dev, istio, mea, minikube, mof-capstone are Stopped today). Never start, stop, modify or delete another project's profile.
- `docker context show` → `default`; `docker info` reaches `/var/run/docker.sock`. If the engine is down, the executor stops and asks the orchestrator (the user starts it).
- `df -h /` → at least 30 GB free before `gql-tracking` is created (images loaded into the node plus the node's own disk). Report the figure.
- `ss -ltn` free on 30360–30365 and 30370–30378 (`profile.sh` checks).

**During:** one live holder at a time; compose verify runs may continue (no port overlap with the cluster tier).

**After each live step** (`down.sh`): `helm uninstall <release> --wait`; `kubectl delete namespace <ns> --wait`; `minikube stop -p gql-tracking`. Then confirm `minikube profile list` shows `gql-tracking` Stopped and `docker ps --filter name=gql-tracking` is empty. Images stay in the stopped node (stop, don't delete). Profile deletion (`minikube delete -p gql-tracking`) only on the user's instruction.

**Compose:** `verify.sh` tears its project down through the harness trap (`down -v --remove-orphans`); after a manual run, `docker compose -p gql-ch25-compose down -v` / `-p gql-ch27-final down -v`. Built images (`gql-ch25-*:1.0`, `gql-ch27-*:1.0`) stay for Ch26/Ch27's `images.sh`; removing them and pruning the build cache is the user's call (the host's 2026-10-11 cleanup left a build-cache prune pending).

**Scratch tools:** Helm v4.3.1, kubectl v1.37.1, kubeconform v0.8.0 and ShellCheck v0.11.0 live in the session scratch directory, checksum-verified; nothing is installed into `~/.local/bin` or system paths.

**At wave hand-back:** no compose project of this wave running, `gql-tracking` Stopped, CRC Stopped, no new files outside the exclusive write sets.
