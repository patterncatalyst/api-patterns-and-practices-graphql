# Ch25 - Local with Docker Compose

The tracking view as one local tier. An nginx edge terminates TLS 1.3, refuses bodies over 64k and routes
only `/graphql`; both stacks sit on an internal network with no published port; the edge's configuration
and key are a compose config and compose secrets; start order follows health; limits, restart policy, log
rotation and stop timeout are read back from the engine; and a trace id sent through the edge is found in
the error, in Tempo and in Loki. The images, `gql-ch25-quarkus:1.0` and `gql-ch25-python:1.0`, are the ones
Chapter 26 deploys.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything in it except
`Subscription`, which Chapter 21 builds. The schema, the sources and the telemetry are Chapter 24's
production instances: Chapter 19's spans and metrics, and `extensions.traceId` on every execution error.
The seed is Chapter 19's six cargos. `GHI345` fails at the booking source with `SERVICE_UNAVAILABLE`.

## The tier

| Service | Image | Networks | Published |
|---|---|---|---|
| `edge` | `registry.access.redhat.com/ubi10/nginx-126:10.2-1791973310` | `public`, `backend` | `8350` -> 8443, `8351` -> 8444 |
| `quarkus` | `gql-ch25-quarkus:1.0` (`ubi10/openjdk-25-runtime:1.24-16`) | `backend` | none |
| `python` | `gql-ch25-python:1.0` (`ubi10/python-314-minimal:10.2-1791928506`) | `backend` | none |
| `lgtm` | `docker.io/grafana/otel-lgtm:0.37.0` | `backend`, `ops` | `127.0.0.1` 8352 to 8355 |

`backend` is `internal: true`. Start order: `lgtm`, then `quarkus` and `python`, then `edge`, each by
`depends_on` with `condition: service_healthy`.

| Setting | quarkus | python | edge |
|---|---|---|---|
| CPU / memory | `1.0` / `768m` | `0.5` / `384m` | `0.25` / `64m` |
| restart | `unless-stopped` | `unless-stopped` | `unless-stopped` |
| stop grace period | `15s` | `15s` | `15s` |
| logging | `local`, `10m` x 3 | the same | the same |
| health | `/q/health/ready` | `/health/ready` | a TLS POST of `{ __typename }` |
| shutdown | `quarkus.shutdown.timeout=10s` | `--timeout-graceful-shutdown 10` | nginx default |

### Environment contract

| Name | Stack | Where |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | both | `env/quarkus.env`, `env/python.env` |
| `QUARKUS_OTEL_SERVICE_NAME` | Quarkus | `env/quarkus.env` |
| `OTEL_SERVICE_NAME` | Python | `env/python.env` |
| `TRACKING_SOURCE_LATENCY_MS` | both | `environment:`, default `250` |
| `TRACKING_DEBUG_ENDPOINTS` | both | `environment:`, `true` (lab; the edge does not route `/debug`) |

### Edge

`edge/nginx.conf` is the compose config `edge_conf`, mounted at `/etc/nginx/nginx.conf`. `ssl_protocols
TLSv1.3`; certificate and key from `/run/secrets/edge_tls_crt` and `edge_tls_key`; `client_max_body_size
64k`; `location = /graphql` proxied, every other path `404`; each upstream resolved per request through Docker's DNS (`resolver 127.0.0.11 valid=10s`), so a restarted container is found at its new address; `traceparent` forwarded unchanged and written
to the access log. `gen-certs.sh <dir>` writes a CA, `edge.crt` and `edge.key` (two days, SANs `localhost`,
`edge`, `127.0.0.1`); compose reads them from `${CERT_DIR:-./certs}`.

## Run it

```bash
bash examples/25-docker-compose/verify.sh
```

`verify.sh` generates certificates into a scratch directory, brings the project up, runs every case on both
stacks, diffs each schema against `contracts/schema/` and tears the project down. It prints `PASS` only if
every check holds on both stacks. It needs Docker Engine with the `docker compose` plugin and Node/npm (for
the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
examples/25-docker-compose/gen-certs.sh examples/25-docker-compose/certs
docker compose -f examples/25-docker-compose/compose.yaml up -d --build --wait
open http://localhost:8352    # Grafana; Explore has Tempo, Prometheus and Loki data sources
docker compose -f examples/25-docker-compose/compose.yaml down -v
```

## Ports

| Service | Container | Host | Endpoint |
|---|---|---|---|
| edge, Quarkus | 8443 | 8350 | `https://localhost:8350/graphql` |
| edge, Python | 8444 | 8351 | `https://localhost:8351/graphql` |
| Grafana | 3000 | 127.0.0.1:8352 | UI, anonymous Admin (lab only) |
| Tempo | 3200 | 127.0.0.1:8353 | `/api/traces/<trace id>` |
| Prometheus | 9090 | 127.0.0.1:8354 | `/api/v1/query` |
| Loki | 3100 | 127.0.0.1:8355 | `/loki/api/v1/query_range` |

Compose project `gql-ch25-compose`, containers `ch25-compose-*`. The collector's OTLP ports (4317, 4318)
stay on the backend network.

## On the wire

Each value below is asserted by `verify.sh`.

| Case | Quarkus | Python |
|---|---|---|
| services | all four `healthy` | the same |
| `quarkus`, `python` ports | no host binding and none declared (`docker compose port`, `HostConfig.PortBindings`); network `backend` only | the same |
| `backend` network | `Internal` true | the same |
| `lgtm` ports | `127.0.0.1` 8352 to 8355 | the same |
| `TrackCargo` ABC123 | `ONBOARD_CARRIER`, no errors | the same |
| `FanOut` | Chapter 13's data; 8 source calls read inside the container | the same data; 6 calls |
| `cargos(first: 10)` | `totalCount` 6; 6 errors, `SERVICE_UNAVAILABLE`, message `booking service unavailable` | 6 edges; 1 error at `["cargos","edges",5,"node"]` |
| `/debug/source-calls`, `/q/health/ready`, `/health/ready`, `/` via the edge | `404` | `404` |
| TLS | TLS 1.2 client fails; no CA fails; plain HTTP answers `400` | the same |
| 100 KB body | `413`; source-call log empty | the same |
| health inside the network | `/q/health/started`, `ready`, `live` `200` and `UP` | `/health/live`, `/health/ready` `200` and `UP` |
| the key | a readable file in the edge; not in its environment, `docker inspect` or any image | the same |
| limits | `805306368` bytes, `1000000000` nano-CPUs | `402653184`, `500000000` |
| policies | `unless-stopped`, `local`, `10m` x 3, stop timeout `15` on every service | the same |
| edge limits | `67108864` bytes, `250000000` nano-CPUs | |
| restart | | one restart after the process exits; healthy without `compose up` |
| stop in flight | `FanOut` completes with four cargos; exit code `143` in under 15 s | |
| `extensions.traceId` | equals the sent id; `query ListCargos` in Tempo; a Loki record by `trace_id` | `GraphQL Query: ListCargos`; the same |
| schema | conforms; `finalArrivalDate` deprecated; scalars carry `specifiedByURL` | the same |

## Code-first notes

Pinned versions: Quarkus 3.40.1, Strawberry 0.335.0, FastAPI 0.143.2, uv 0.13.1, `ubi10/nginx-126`
`10.2-1791973310` (nginx 1.26.3), `grafana/otel-lgtm` 0.37.0. The Python project is
`shipping-python-ch25-compose` with its own `uv.lock`; the Quarkus artifact is `ch25-quarkus-compose`.

**Health.** Quarkus keeps SmallRye Health's `started`, `ready` and `live`. Python serves two plain FastAPI
routes: `/health/live` always answers `200`, and `/health/ready` answers `200` once the lifespan has built
the store and the sources and `503` before that.

**Edge paths.** The image runs as UID 1001, so `nginx.conf` puts the pid file and every temporary path under
`/tmp`, and writes the error log to stderr and the access log to stdout. `curl` ships in the image, so the
edge's healthcheck posts `{ __typename }` to its own listener and verifies the certificate against the
mounted secret.

**Secret file mode.** The certificate and key are bind-mounted, so the edge reads them with the host file's
mode. `gen-certs.sh` writes them `0644` for the lab; the key lives two days.

**Restart.** `unless-stopped` starts a container again whenever its process exits, whatever the exit code, and
leaves a container stopped when an operator stopped it through the engine (`docker compose stop` or `kill`).
The case has the process exit on its own: it sends `SIGTERM` to PID 1, uvicorn, from inside the container
(`kill -TERM 1`). Uvicorn shuts down and exits, the engine starts the container again and `RestartCount`
goes up by one.

**Graceful stop.** With `TRACKING_SOURCE_LATENCY_MS=250` a `FanOut` takes over a second. The case polls the
source-call log until the first call appears, runs `docker compose stop quarkus` and expects the response
complete. Quarkus exits with code `143` after finishing it.

**Telemetry.** Python exports over OTLP gRPC to `http://lgtm:4317`, as in Chapter 24; both stacks name their
service `ch25-compose-<stack>`, which is the `service_name` Loki and Tempo use.

**Reading the engine.** `docker compose port` reports no host binding for a service without a published port.
`verify.sh` also reads `HostConfig.PortBindings`, which is what the file declares, and `NetworkSettings.Ports`,
which is what the engine bound, and expects neither to hold a host port. A container whose only network is
internal gets no host binding even when it declares one; the declared check reads what the file asks for.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/25-docker-compose-architecture.py`) show the compose topology: a client with a
`traceparent` reaching the edge over TLS 1.3, the edge reaching both stacks on the backend network, both
stacks exporting OTLP to `lgtm`, and the schema diffed against the canonical SDL.
