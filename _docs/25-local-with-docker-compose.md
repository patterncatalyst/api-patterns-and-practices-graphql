---
title: "Local with Docker Compose"
order: 25
part: "Running It & the Final Project"
description: "The tracking view as one local tier: an nginx edge with TLS 1.3 and a body limit, an internal backend network, config and secrets outside the images, health-ordered start, limits, restart and shutdown settings, and a trace followed from the edge to Tempo and Loki."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Terminate TLS 1.3 and cap request bodies at an nginx edge so a GraphQL backend never sees an oversized or downgraded request.
- Isolate backend services on an `internal: true` Compose network and reach lab endpoints only through `docker compose exec`.
- Mount configuration and secrets as files and environment variables kept outside the image, following the Twelve-Factor App's config rule.
- Order service startup with `depends_on` `condition: service_healthy`, and tell a liveness probe apart from a readiness probe.
- Follow a request's `traceparent` from the edge through to its trace in Tempo and its record in Loki.

## Why this matters

Running one technique's example is the wrong size for the question of what the service looks like as a whole. Something has to terminate TLS, something has to refuse a body that is too large, the service has to start after the things it depends on, and an operator has to read what the engine was told to do. None of that is GraphQL, and all of it decides whether the GraphQL service is reachable and diagnosable.

The code is in `examples/25-docker-compose/`. It runs the production instances with OpenTelemetry and `extensions.traceId` on every execution error, and leaves out the seeded fault, the development instances and the run-time level switch, because a tier runs the service as it ships. The schema is everything except `Subscription`. Four services surround it: an nginx edge, the two stacks and the observability backend. `verify.sh` brings them up and reads the result from the outside.

## From one example to a tier

Four services run on three networks. The two stacks publish no port. The only way to reach them from the host is the edge, which publishes `8350` for Quarkus and `8351` for Python, both over TLS. The observability backend publishes Grafana, Tempo, Prometheus and Loki on `8352` to `8355`, bound to `127.0.0.1`.

{% include excalidraw.html file="25-compose-tier-topology" alt="Three vertical bands. The public band holds the edge, an nginx container with TLS 1.3, a body limit under 64k and only slash graphql routed, numbered 3 for its start order, and below it a box for the compose config and the two secrets mounted under slash run slash secrets. The backend band, marked internal, holds quarkus and python, both numbered 2, each with its health path, its limits and no published port, and the lgtm observability service numbered 1. An arrow from the client on the left enters the edge over TLS, and arrows from the edge reach quarkus and python on port 8080. An amber arrow labelled OTLP from both runs from the stacks to lgtm. The ops band on the right holds Grafana on 8352, Tempo on 8353, Prometheus on 8354 and Loki on 8355, published on 127.0.0.1." caption="Figure 25.1: The compose project. The backend network is internal, so the stacks are reached only through the edge; the numbers are the start order that health conditions enforce." %}

| Network | Carries | Members |
|---|---|---|
| `public` | the edge's published listeners | edge |
| `ops` | the observability backend's published ports | `lgtm` |
| `backend` | everything between services; `internal: true` gives it no route to or from the host | edge, both stacks, `lgtm` |

```yaml
networks:
  public: {}
  ops: {}
  backend:
    internal: true
```

An internal network protects a service by making the wrong path impossible, which is stronger than a service that merely doesn't listen on a public address. A stack that later gains a debug route, a metrics endpoint or an administrative page doesn't become reachable from the host by accident, because it has no address there. Anything an operator needs is reached by an explicit step: an `exec` into the container, or a route added to the edge. `verify.sh` takes the first step for the lab endpoints, with `compose_exec_http`, which runs `curl` inside the container against `localhost:8080`.

Start order follows from what each service needs. The stacks export telemetry, so they wait for `lgtm`. The edge proxies to both stacks, so it waits for both. Each wait is a `depends_on` entry with `condition: service_healthy`, a statement about health and not about the container having started:

```yaml
    depends_on:
      quarkus:
        condition: service_healthy
      python:
        condition: service_healthy
```

`docker compose up -d --wait` returns once every service is healthy.

Nothing in the tier is specific to this data. Replace the two images with another service that exposes a health endpoint on `8080` and the edge, networks, configs and secrets work the same way.

## One image per stack

Each stack is built once and tagged `1.0`: `gql-ch25-quarkus:1.0` and `gql-ch25-python:1.0`. The compose file sets `image:` beside `build:`, so the tag a build produces is the tag of the image the stack runs. A fixed tag lets a Kubernetes deployment take the same two images unchanged, and an image rebuilt for each environment isn't the thing that was tested.

Relative to a debugging instance, the Quarkus Containerfile loses its `dev` target, the Python entrypoint gains `--timeout-graceful-shutdown 10` (ten seconds for uvicorn to finish requests in flight after a stop signal), and each image names its service for the collector: `ch25-compose-quarkus` and `ch25-compose-python`.

## Configuration outside the image

The images carry no environment-specific value. Everything a tier supplies reaches the process through its environment or a mounted file, which is the Twelve-Factor App's rule for config and the reason one image runs on a laptop and in a cluster. Each stack has an `env_file` with the values that are part of the tier, and an `environment:` list with the ones a run may override:

| Name | Stack | Meaning |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | both | the collector, `http://lgtm:4317` |
| `QUARKUS_OTEL_SERVICE_NAME` | Quarkus | `quarkus.otel.service.name`, `ch25-compose-quarkus` |
| `OTEL_SERVICE_NAME` | Python | the service name, `ch25-compose-python` |
| `TRACKING_SOURCE_LATENCY_MS` | both | the lab delay per source call, `250` unless the shell sets it |
| `TRACKING_DEBUG_ENDPOINTS` | both | the lab source-call log; the edge does not route it |

Quarkus maps an environment name to a property by a fixed rule, so `QUARKUS_OTEL_SERVICE_NAME` sets `quarkus.otel.service.name` with no entry in `application.properties`. Python reads the `TRACKING_` names through `pydantic-settings` and the `OTEL_` names through the OpenTelemetry SDK. The same keys appear in a Kubernetes ConfigMap and nothing in the application changes. `${VAR:-default}` supplies a default a shell can replace, as in `${TRACKING_SOURCE_LATENCY_MS:-250}` and `${CERT_DIR:-./certs}`.

A file is configuration too. The edge's `nginx.conf` is a compose config, mounted read-only at the target path in place of the image's own, so a change takes effect on the next `up`:

```yaml
    configs:
      - source: edge_conf
        target: /etc/nginx/nginx.conf
```

```yaml
configs:
  edge_conf:
    file: ./edge/nginx.conf
```

## Secrets as files

The key of the edge's certificate is the only secret in the tier, and the tier treats it the way a platform would: as a file the process reads, never as a value in an environment or an image layer.

```yaml
    secrets:
      - edge_tls_crt
      - edge_tls_key
```

```yaml
secrets:
  edge_tls_crt:
    file: ${CERT_DIR:-./certs}/edge.crt
  edge_tls_key:
    file: ${CERT_DIR:-./certs}/edge.key
```

Each secret appears in the container as a read-only file under `/run/secrets/`. `gen-certs.sh` writes a throwaway certificate authority, a server certificate for `localhost`, `edge` and `127.0.0.1`, and the key, all valid for two days. `verify.sh` runs it into a scratch directory, sets `CERT_DIR` to it and `LGTM_CACERT` to the CA. Nothing it writes is committed, and `certs/` is in `.gitignore`. Compose mounts a file secret from its host path, so the file keeps its host mode; a real deployment sources the key from a secret store, with a mode its platform sets.

The claim to check is what is absent. `verify.sh` reads the edge's environment from the engine and finds neither a PEM header nor the key's body, and searches `docker inspect` of the container and `docker inspect` plus `docker history` of all three images for the same text. The key is in one place, the file.

## The edge

The edge is nginx on `ubi10/nginx-126`, pinned to `10.2-1791973310`. A reverse proxy can terminate TLS, and the production answer to a large body is `client_max_body_size` at the proxy.

```nginx
    ssl_protocols       TLSv1.3;
    ssl_certificate     /run/secrets/edge_tls_crt;
    ssl_certificate_key /run/secrets/edge_tls_key;

    client_max_body_size 64k;
```

TLS 1.3 is the only protocol the listeners accept, so a client that offers 1.2 fails the handshake before any HTTP happens. The body limit is checked against the request's `Content-Length`, so a body over `64k` gets `413` before nginx reads it and before a backend is involved.

Only one path is routed. The edge answers everything else:

```nginx
    server {
        listen 8443 ssl;
        server_name localhost;

        location = /graphql {
            set $backend http://quarkus:8080;
            proxy_pass $backend;
        }
        location / {
            return 404;
        }
    }
```

`location = /graphql` matches that path exactly. The lab source-call log, the health endpoints and the site root answer `404` at the edge. They exist inside the network for the platform and for `verify.sh`, and an outside caller never reaches them. A second `server` block listens on `8444` for Python, so each stack has its own listener.

The upstream is resolved through the network's DNS so a restarted container is found at its new address. A `resolver` directive names Docker's embedded DNS server and how long an answer lives, and a variable in `proxy_pass` makes nginx resolve the name per request instead of once at start-up:

```nginx
    resolver 127.0.0.11 valid=10s;
```

```nginx
            set $backend http://quarkus:8080;
            proxy_pass $backend;
```

The proxy settings above the `server` blocks forward what a GraphQL service needs. `Host` and `X-Forwarded-For` pass through, `X-Forwarded-Proto` says `https`, and a `map` turns an `Upgrade` header into `Connection: upgrade`, which a WebSocket handshake for subscriptions needs. The trace headers need no line: nginx passes request headers unchanged, so `traceparent` and `tracestate` reach the backend as the client sent them. The access log records `traceparent`, so an edge log line and a trace can be matched.

The image runs as UID 1001, which can't write `/var/log/nginx` or `/run`, so the configuration moves the pid file and every temporary path under `/tmp` and writes both logs to the standard streams, where a log driver reads them. `docker compose logs edge` prints one line per request with the status, the chosen upstream and the `traceparent`. Grafana on `http://localhost:8352` opens with Tempo, Prometheus and Loki already configured, and a trace id copied from an edge log line pastes straight into Tempo's search.

## Health and start order

A health check turns "the process started" into "the process can serve". Quarkus uses SmallRye Health, which exposes `started`, `ready` and `live` under `/q/health`, and the compose healthcheck calls `ready`. Python gets the same split from two plain FastAPI routes:

```python
@app.get("/health/live", tags=["ops"])
def live() -> dict[str, str]:
    return {"status": "UP"}


@app.get("/health/ready", tags=["ops"])
def ready(request: Request, response: Response) -> dict[str, str]:
    if not request.app.state.ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "DOWN"}
    return {"status": "UP"}
```

`live` answers `200` for as long as the process answers at all. `ready` answers `503` until the lifespan has built the handling store and the sources and set `app.state.ready`. On a stop signal uvicorn closes its listening socket first, so new requests, health checks included, are refused while the ones in flight finish.

The two answers mean different things to an orchestrator:

| Probe | A failure means | On Kubernetes |
|---|---|---|
| liveness | the process is stuck and a restart may help | liveness probe (`live`) |
| readiness | the process is working and should receive no traffic yet | readiness probe (`ready`) |
| started (Quarkus) | the application hasn't finished booting | startup probe (`started`) |

```yaml
    healthcheck:
      test: ["CMD", "curl", "-fsS", "-o", "/dev/null", "http://localhost:8080/health/ready"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 10s
```

`start_period` is a grace window in which a failing check doesn't count against `retries`. The JVM needs longer than Python, so Quarkus has `20s` and Python `10s`. The edge's own check is a real GraphQL request, a POST of `{ __typename }` to its own listener, verified against the certificate mounted as a secret, so it is healthy only when TLS, the config and the route all work.

## Limits, restarts and shutdown

A tier on a shared machine states what each service may use and what happens when it stops. Each application service takes the same settings from a shared block:

```yaml
x-app: &app
  restart: unless-stopped
  stop_grace_period: 15s
  logging:
    driver: local
    options:
      max-size: "10m"
      max-file: "3"
  networks:
    - backend
```

`restart: unless-stopped` starts a container again when its process exits, unless a person stopped it. `stop_grace_period` is the wait between the stop signal and a kill. The `local` log driver stores each service's output on the host with rotation, `10m` in at most three files, so a chatty service can't fill the disk. Limits sit beside them under `deploy.resources.limits`:

| Service | CPU | Memory |
|---|---|---|
| quarkus | `1.0` | `768m` |
| python | `0.5` | `384m` |
| edge | `0.25` | `64m` |

Compose turns each into an engine setting, `NanoCpus` and `Memory`, and `verify.sh` reads them back from the engine instead of trusting the file: `805306368` bytes and `1000000000` nano-CPUs for Quarkus, `402653184` and `500000000` for Python. It checks the restart policy, the log driver, its rotation and the stop timeout of `15` the same way. A configuration the engine didn't apply is what a re-read catches and a code review doesn't.

The grace period only helps if the application uses it, so each stack sets a shutdown window shorter than it:

{% include codetabs.html langs="Quarkus|Python" %}

```properties
quarkus.shutdown.timeout=10s
```

```dockerfile
ENTRYPOINT ["opentelemetry-instrument", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", \
            "--timeout-graceful-shutdown", "10"]
```

On `SIGTERM` Quarkus stops accepting requests and waits up to ten seconds for the ones in flight; uvicorn's `--timeout-graceful-shutdown 10` does the same for Python. Both windows end before the engine's fifteen seconds, so the process leaves by itself and isn't killed mid-response. The JVM then exits with `143`, 128 plus the number of `SIGTERM`, after its shutdown hooks run; a kill at the end of the grace period would show `137`. This is the Twelve-Factor App's disposability: fast start, graceful stop.

Two cases exercise it. `SIGTERM` sent to the Python process from inside its container makes it exit without a stop request to the engine, and the restart policy brings it back with no `compose up`. A `docker compose stop` or `kill` is an operator's request, and `unless-stopped` leaves that container stopped. And a `FanOut`, which takes more than a second at 250 ms per source call, is sent to Quarkus; once its first source call shows in the log the service is stopped, and the response must still arrive complete.

## The diagnosis path on the whole stack

The tier runs the service behind the edge and exports to `lgtm`, so the path from a response to its cause starts where a client would start it. The client sends `ListCargos`, `cargos(first: 10)`, to the edge with a `traceparent` it chose. The edge terminates TLS, checks the body and the path, and passes the header on. The stack answers with six edges. Five nodes resolve, and the node of `GHI345` is null with an error whose code is `SERVICE_UNAVAILABLE`, because the booking source fails that key. The error carries `extensions.traceId`, the trace id of the `traceparent` the client sent.

{% include excalidraw.html file="25-request-through-the-edge" alt="Two bands. The upper band, a traced request, shows a client sending a traceparent to the edge on port 8351, which forwards to python running the ListCargos query, which calls the booking source twice, once to list and once to get six keys in a single call, where the booking of GHI345 fails. A second row shows the response with six edges, a null node at index five, the code SERVICE_UNAVAILABLE and extensions.traceId equal to the trace id the client sent. Amber arrows labelled id and same id lead from the response to Tempo, which holds the ListCargos operation span and the source call spans, and then to Loki, which holds the error record with the same trace id. The lower band, a refused request, shows a client sending a 100 KB body to the edge, which answers 413 Request Entity Too Large, with a dashed arrow labelled not reached to python, whose source-call log stays empty." caption="Figure 25.2: One traced request and one refused request, from a run of the Python stack. The trace id the client chose survives the edge and finds the trace and the log record; the oversized body stops at the edge." %}

Tempo holds the trace under that id, with the operation span `GraphQL Query: ListCargos` on Python and `query ListCargos` on Quarkus, and below it the `source.call` spans of the two booking calls. Loki holds the exception record the server wrote when the failure passed through the engine, with `trace_id` as structured metadata, so `{service_name="ch25-compose-python"} | trace_id="<id>"` returns it. The stacks fail differently: Quarkus nulls the whole batch and reports six errors, one per parent, and Python reports one. At the trace id they agree.

Because nginx forwards `traceparent`, the trace begins at the caller and continues in the backend, with no new header to learn and no second id to correlate.

The refused request is the lower band. A 100 KB body gets `413` from the edge. The stack's source-call log is empty afterwards, so no resolver ran, and the access log records `upstream=-`, meaning no upstream was chosen. A refusal at the edge is cheaper than one in the application because it never costs a thread, a parse or a trace.

## Build, run, observe

Generate the throwaway certificates, start the tier and wait for every service to be healthy:

```bash
examples/25-docker-compose/gen-certs.sh examples/25-docker-compose/certs
docker compose -f examples/25-docker-compose/compose.yaml up -d --build --wait
```

Send a traced request through the edge to the Python stack, with the CA that signed the edge's certificate:

```bash
CA=examples/25-docker-compose/certs/ca.crt
TID=$(python3 -I -c 'import secrets; print(secrets.token_hex(16))')
curl -s --cacert $CA https://localhost:8351/graphql -H 'Content-Type: application/json' \
  -H "traceparent: 00-$TID-00f067aa0ba902b7-01" \
  -d '{"query":"query ListCargos { cargos(first: 10) { totalCount edges { node { trackingId } } } }"}'
```

```json
{"data":{"cargos":{"totalCount":6,"edges":[{"node":{"trackingId":"VWX901"}},{"node":{"trackingId":"XYZ789"}},{"node":{"trackingId":"STU678"}},{"node":{"trackingId":"DEF456"}},{"node":{"trackingId":"ABC123"}},{"node":null}]}},"errors":[{"message":"booking service unavailable","locations":[{"line":1,"column":59}],"path":["cargos","edges",5,"node"],"extensions":{"code":"SERVICE_UNAVAILABLE","traceId":"e317abd0a65a4ba25a30bfb67ccda8fb"}}]}
```

The `traceId` equals `$TID`. Read the trace from Tempo, and the record from Loki by the same id:

```bash
curl -s localhost:8353/api/traces/$TID
curl -sG localhost:8355/loki/api/v1/query_range \
  --data-urlencode "query={service_name=\"ch25-compose-python\"} | trace_id=\"$TID\""
```

The edge answers what it doesn't route, what it refuses and what it won't negotiate:

```bash
curl -s --cacert $CA -o /dev/null -w '%{http_code}\n' https://localhost:8350/q/health/ready
curl -s --cacert $CA --tls-max 1.2 -o /dev/null https://localhost:8350/graphql; echo curl=$?
curl -s -o /dev/null -w '%{http_code}\n' -d x http://localhost:8350/graphql
```

```text
404
curl=35
400
```

The first is the edge's `404` for a path it doesn't route, the second is the failed handshake of a TLS 1.2 client (curl exit code `35`), and the third is nginx's `400` for plain HTTP on a TLS listener. Read the limits back from the engine, and stop the tier when done:

{% raw %}
```bash
docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}} {{.HostConfig.RestartPolicy.Name}}' ch25-compose-quarkus
docker compose -f examples/25-docker-compose/compose.yaml down -v
```
{% endraw %}

```text
805306368 1000000000 unless-stopped
```

`bash examples/25-docker-compose/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when every case holds. It asserts these values:

| Check | Quarkus | Python |
|---|---|---|
| services | `edge`, `quarkus`, `python`, `lgtm` all `healthy` | the same |
| published ports | none on the stack; the edge publishes 8350 and 8351; `lgtm` on 127.0.0.1 only | the same |
| `docker compose port`, `HostConfig.PortBindings` | no host binding, none declared | the same |
| `backend` network | `Internal` is true | the same |
| `TrackCargo` for ABC123 | `ONBOARD_CARRIER`, no errors | the same |
| `FanOut` source calls, read inside the container | 8 | 6 |
| `cargos(first: 10)` | 6 edges, 6 errors with `SERVICE_UNAVAILABLE` | 6 edges, 1 error at `edges[5].node` |
| `/debug/source-calls`, `/q/health/ready`, `/health/ready`, `/` through the edge | `404` | `404` |
| TLS | a TLS 1.2 client fails; no CA fails; plain HTTP answers `400` | the same |
| 100 KB body | `413`, no source call | `413`, no source call |
| inside the network | `/q/health/started`, `ready`, `live` answer `200` `UP` | `/health/live`, `ready` answer `200` `UP` |
| the key | a file in the edge; in no environment, `inspect` output or image | the same |
| limits | `805306368` bytes, `1000000000` nano-CPUs | `402653184`, `500000000` |
| policies | `unless-stopped`, `local`, `10m` by 3, stop timeout `15` | the same |
| restart | not exercised | one restart after the process exits, healthy again |
| stop with a request in flight | the `FanOut` completes; exit code `143` within 15 s | not exercised |
| `extensions.traceId` | equals the id sent through the edge; the trace is in Tempo and the record in Loki | the same |
| schema | conforms; `finalArrivalDate` deprecated | the same |

Experiments:

- Offer TLS 1.2 (`--tls-max 1.2`): the handshake fails with curl exit `35`.
- Send a body over 64k: the edge answers `413` and the source-call log stays empty.
- Request `/q/health/ready` or `/health/ready` through the edge: `404`; the same path inside the container answers `200`.
- Stop a stack with a request in flight: the response still arrives complete, and Quarkus exits `143`.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Put the rules every caller needs in one place: the edge terminates TLS 1.3, refuses a body over 64k and routes one path, and the backends stay off the host. Forward <code>traceparent</code> unchanged so any caller can start the trace an operator reads. Ship the observability backend with the tier and start the stacks after it. Keep config and the key outside the images, let health order the start, and confirm limits and policies from the engine.</p></div>

## For deeper coverage

- [The Twelve-Factor App: Config](https://12factor.net/config) and [Disposability](https://12factor.net/disposability): the rules this tier's configuration and shutdown settings follow.
- [Docker Compose: Compose file reference](https://docs.docker.com/compose/compose-file/): `services`, `configs`, `secrets`, and `networks`. Docker's "Restart policies" and "Configure logging drivers" pages cover those settings.
- [nginx: ngx_http_ssl_module](https://nginx.org/en/docs/http/ngx_http_ssl_module.html): TLS termination and `client_max_body_size`; the nginx docs also cover `proxy_pass` and "WebSocket proxying".
- The Quarkus "SmallRye Health" and "Configuring your application" guides, Uvicorn's "Settings" and FastAPI's "Lifespan Events" cover the application side.
- *Cloud Native Design Patterns*, "Observability": the LGTM stack and OTLP wiring this tier's edge-to-trace path reuses.
- Gerald Bachlmayr, Aiden Ziegelaar, Alan Blockley & Bojan Zivic, *Cloud Native Anti-Patterns* (Packt, 2025): the coupling and operability failures a hardened edge and health-ordered start exist to avoid.
