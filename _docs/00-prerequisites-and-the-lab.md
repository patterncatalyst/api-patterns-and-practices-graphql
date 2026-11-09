---
title: "Prerequisites and the lab"
order: 0
part: "Prerequisites & the Lab"
description: "Toolchain pins, the repository layout and a Docker Compose lab that serves one GraphQL schema from Quarkus and Python and checks both against the canonical SDL."
duration: "25 min read"
---

## Learning objectives

By the end of this chapter you can:

- Install and pin the toolchain (JDK 25, Quarkus 3.40.1, Python 3.14, `uv`, Node 24) both GraphQL stacks build from.
- Navigate the repository layout: `contracts/schema/shipping/` as the canonical SDL, one `examples/NN-*/` directory per chapter, and the shared `examples/_lib/lib.sh` harness.
- Run `bash examples/00-prerequisites/verify.sh` and read its checks against the canned `Cargo` `ABC123`.
- Explain how `assert_sdl_conforms` diffs each stack's live schema against the canonical SDL with `graphql-inspector`.
- Contrast SmallRye GraphQL's and Strawberry's opposite nullability defaults (`@NonNull` versus `| None`) on the same `Cargo` type.

## Why this matters

Every hands-on chapter gives you a running GraphQL server in two languages and a script that checks both behave the same way. The lab sets that up: the toolchain, the repository layout, the shipping domain every schema describes, and a minimal tracking view that answers one query from canned data on Quarkus and on Python. The goal is a toolchain you stop thinking about.

The code is in `examples/00-prerequisites/`. Its `verify.sh` builds both images, starts them, checks them and tears them down; its `README.md` lists the ports and expected values.

## What to install

The lab is a Linux lab. The commands below target Fedora and RHEL-family systems, and every example runs on Docker Engine with the Compose plugin. Docker Desktop and Podman are not assumed, so a command that says `docker compose` means exactly that binary.

The images build inside containers, so `verify.sh` needs only Docker, Node with npm, `curl` and a system `python3` on the host. The language toolchains matter when you step through code in an IDE or run a server outside a container. 

| Tool | Version in this repo | Why it is here |
|---|---|---|
| Docker Engine with the Compose plugin | any current release | Builds and runs every example; `docker compose` is the only orchestration command |
| JDK | 25 (LTS) | `maven.compiler.release` is 25; the images are `ubi10/openjdk-25` and `-runtime` |
| Maven | 3.9.x | Builds the Quarkus modules; the container build uses the JDK image's 3.9.9 |
| Quarkus platform | 3.40.1 (pinned in each `pom.xml`) | SmallRye GraphQL, SmallRye Health and OpenTelemetry extensions |
| Quarkus CLI | optional | A shortcut for `quarkus dev`; `mvn quarkus:dev` does the same |
| Python | 3.14 | `requires-python = ">=3.14"`; the runtime image is `ubi10/python-314-minimal` |
| uv | 0.13.1 in the Containerfile; Fedora's 0.12 also reads `uv.lock` | Creates the virtual environment from `uv.lock` |
| Node.js | 24 LTS (CI pins 24.22.0) | Runs GraphQL ESLint and GraphQL Inspector from `contracts/` |
| `curl` and `jq` | any current release | Sends queries by hand and formats responses |

On Fedora, one command installs most host-side tools:

```bash
sudo dnf install -y java-25-openjdk-devel maven nodejs24-bin nodejs24-npm-bin uv jq curl
```

On RHEL and derivatives, enable the repositories that carry `java-25-openjdk-devel` and Node 24 for your release, or install the JDK through SDKMAN and Node through a version manager. Confirm the versions that matter:

```bash
java -version      # openjdk version "25..."
node --version     # v24...
uv --version
```

Docker Engine comes from Docker's own package repository. On Fedora with `dnf5`:

```bash
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

On RHEL, whose `dnf` takes `config-manager --add-repo`, use the `rhel` repository file. Log out and back in after the `usermod`, then check the engine and the plugin:

```bash
docker run --rm hello-world
docker compose version
```

Membership in the `docker` group is equivalent to root on that machine.

The pins follow one rule: the newest stable release that every dependency supports, pinned exactly. Strawberry 0.335.0, FastAPI 0.143.2 and uvicorn 0.54.0 are fixed in `pyproject.toml` and `uv.lock`. GraphQL Inspector 7.0.1, GraphQL ESLint 4.4.2 and `graphql` 16.14.2 are fixed in `contracts/package.json`. The images use exact tags (`ubi10/openjdk-25` and `-runtime` at `1.24-16`, `ubi10/python-314-minimal:10.2-1791928506`), so a rebuild next month produces the same bits. Bumping any pin is a reviewed change, never a side effect of a rebuild. The base images are Red Hat's Universal Base Image 10, which needs no subscription to pull, and everything else is open source.

## The repository layout

```text
contracts/                     the canonical schema and its gates
  schema/shipping/*.graphql      six SDL files: scalars, location, voyage, cargo, handling, schema
  package.json                   pinned graphql-inspector, graphql-eslint (Node 24)
  scripts/breaking.sh            breaking-change gate (npm run breaking)
examples/
  _lib/lib.sh                    shared harness every verify.sh sources
  00-prerequisites/              one directory per hands-on chapter
    quarkus/                       SmallRye GraphQL module, Containerfile
    python/                        Strawberry app, pyproject.toml, uv.lock, Containerfile
    compose.yaml                   both stacks, telemetry off by default
    compose.observability.yaml     the opt-in override that adds LGTM
    verify.sh                      the check that prints PASS or fails
_docs/                         the chapters
```

`contracts/schema/shipping/` is the single source of truth for the API. It is Schema Definition Language (SDL), the textual form of a GraphQL schema, and every type and field carries a description. Two gates protect it in CI and locally. `npm run lint` applies GraphQL ESLint's schema rules, and `npm run breaking` runs GraphQL Inspector's diff against the base branch and fails a change that removes a field, changes a type or drops an enum value.

Where gRPC generates server stubs from `.proto` files, GraphQL frameworks work the other way. Quarkus SmallRye GraphQL and Strawberry both build their schema from annotated or decorated code (code-first) and expose it through introspection. The canonical SDL is therefore not compiled into either server. It is the yardstick the running schema is measured against, and the Containerfiles use each stack's own directory as build context, so no contract file is copied into an image.

Each `examples/NN-*/` directory has the same shape: `quarkus/` and `python/` hold the two implementations, `compose.yaml` starts them side by side, and `verify.sh` checks both. `examples/_lib/lib.sh` starts and tears down the Compose project, waits for the endpoint, sends operations with `curl` and provides assertions that read the response body. A `200 OK` proves nothing in GraphQL over HTTP, because a response carrying `errors` is still a `200`, so every assertion inspects `data` and `errors`.

{% include excalidraw.html file="00-lab-topology" alt="Topology of the Compose lab. On the left, verify.sh in examples/00-prerequisites sources lib.sh from examples/_lib, and lib.sh sends POST requests to both services. In the middle, a band labelled Docker Compose project gql-ch00-prereq contains three boxes stacked vertically: quarkus on host port 8080 serving /graphql and /q/health, built with SmallRye GraphQL code-first; a dashed box for otel-lgtm, added by the compose.observability.yaml file, with Grafana on port 3000 and OTLP on port 4317; and python on host port 8081 serving /graphql and /health, built with Strawberry on FastAPI code-first. Dashed arrows labelled OTLP run from both services to otel-lgtm. On the right, graphql-inspector, run by assert_sdl_conforms, introspects both services with arrows labelled introspect and points to contracts/schema/shipping/*.graphql, the canonical SDL, with an arrow labelled diff both ways." caption="Figure 0.1: The lab: verify.sh drives both stacks through lib.sh, and graphql-inspector compares each live schema with the canonical SDL." %}

## The shipping domain and the tracking view

Every example works against one domain, shared with the sibling REST and gRPC books. A shipping company books cargo for carriage between ports. The **tracking view** is a read-oriented GraphQL layer in front of the services that own the data: a customer asks where a cargo is and what happens next, and the view assembles the answer from three owners in one response.

- A **Cargo** is the goods being shipped and the root of the view. Clients find it by **TrackingId**, an opaque string such as `ABC123` compared for equality only.
- A **Location** is a port or terminal identified by its UN/LOCODE, the five-character United Nations location code: `USNYC`, `NLRTM`, `SGSIN`.
- A **RouteSpecification** records what the customer asked for: origin, destination and an arrival deadline.
- An **Itinerary** is the planned route, an ordered list of **Leg**s. Each leg loads at one location and unloads at another, normally on a named **Voyage**.
- A **HandlingEvent** records something that physically happened to the cargo: received, loaded, unloaded, cleared by customs, claimed.
- A **Delivery** is the state derived from the handling history: transport and routing status, last known location, current voyage, estimated arrival and the next expected activity, a **HandlingActivity**.

{% include excalidraw.html file="00-shipping-domain-model" alt="Domain model of the tracking view, grouped by the service that owns each type. A band labelled Cargo service (REST) holds Cargo, a Node with id, trackingId, description, origin and destination, routeSpecification, delivery, a nullable itinerary and handlingHistory with first, after, last and before arguments, plus RouteSpecification with origin, destination and arrivalDeadline. A band labelled Routing service (gRPC) holds Itinerary with legs and finalArrivalDate, and Leg with a nullable voyage, loadLocation, unloadLocation, loadTime and unloadTime. A band labelled Handling event store holds HandlingEvent, a Node with trackingId, type, location, a nullable voyage, a nullable cargo, completionTime and registrationTime; Delivery with transportStatus, routingStatus, misdirected and nullable estimatedTimeOfArrival, lastKnownLocation, currentVoyage and nextExpectedActivity; and HandlingActivity with type, location and a nullable voyage. A band labelled Shared reference types holds Location, a Node with unLocode, name and country, and Voyage, a Node with number and a schedule of CarrierMovement. Arrows run from Cargo to RouteSpecification, from Cargo to Itinerary marked nullable, from Itinerary to Leg, from Leg to Location and to Voyage marked nullable, from Cargo to HandlingEvent for the history, from Cargo to Delivery, and from Delivery to HandlingActivity." caption="Figure 0.2: The shipping domain as the SDL describes it, grouped by the service that owns each type." %}

The figure groups types by owner because the grouping explains the nullability. Nearly every nullable field sits on a boundary between services. `Cargo.itinerary` is null until the routing service assigns a route. `Leg.voyage` is null when the voyage lookup fails, so one failed lookup degrades a leg instead of the whole response. `Delivery.estimatedTimeOfArrival` is null when no estimate exists, and `HandlingEvent.cargo` is null when the cargo service is unavailable. Fields the domain guarantees, such as `Cargo.trackingId` and `Leg.loadLocation`, are non-null. This matters most when a null in a non-null position propagates to the nearest nullable parent.

The schema has one mutation, `registerHandlingEvent`, and one subscription, `cargoHandled`. The lab serves neither. It serves a slice of the read side: `Query.cargo(trackingId: TrackingId!): Cargo`, with `Cargo` limited to `id`, `trackingId`, `description`, `origin` and `destination`, plus `Location`, the `Node` interface and the two custom scalars. That is enough to show scalars, an interface, an object graph and nullability surviving code-first generation on both stacks.

## Two stacks, one SDL

**Nullability.** Java has no non-null reference type, so SmallRye GraphQL treats every object-typed field as nullable unless you add `@NonNull`. Strawberry treats every field as non-null unless its type includes `None`. The same SDL line, `origin: Location!`, comes from opposite defaults:

```java
@Type("Cargo")
@Description("A consignment of goods being shipped, tracked end to end by its tracking id.")
public record Cargo(
        String id,
        @NonNull @Description("The public tracking identifier.") TrackingId trackingId,
        @NonNull @Description("Free-text description of the goods.") String description,
        @NonNull @Description("Where the cargo was booked from.") Location origin,
        @NonNull @Description("Where the cargo is booked to.") Location destination)
        implements Node {

    @Override
    @Id
    @NonNull
    @Description("The globally unique identifier of this cargo.")
    public String getId() {
        return id;
    }
}
```

```python
@strawberry.type(
    description="A consignment of goods being shipped, tracked end to end by its tracking id."
)
class Cargo(Node):
    id: strawberry.ID = strawberry.field(
        description="The globally unique identifier of this cargo."
    )
    tracking_id: TrackingId = strawberry.field(description="The public tracking identifier.")
    description: str = strawberry.field(description="Free-text description of the goods.")
    origin: Location = strawberry.field(description="Where the cargo was booked from.")
    destination: Location = strawberry.field(description="Where the cargo is booked to.")
```

The Java record needs an annotation on every field to say what the Python class says by omission, and a forgotten `@NonNull` produces `Location` where the contract says `Location!`, which the live-to-canonical diff reports as breaking. The root field shows the opposite case: `Query.cargo` is nullable in the contract, so Python writes `-> Cargo | None` and Java returns `Cargo` and leaves `@NonNull` off. Strawberry maps `tracking_id` to `trackingId` automatically; Java's record component is already camelCase.

**The `Node` interface.** The SDL's `Node` declares `id: ID!`, and `Cargo` and `Location` implement it. SmallRye derives an interface's fields from getter-named methods, so the interface declares `getId()` and each implementing record carries an explicit `getId()` annotated `@Id @NonNull`, as `Cargo` does above. In Strawberry the `id` field on the interface class, redeclared in each subclass, is the whole mechanism.

**Contract details set in code.** Two details of the SDL have no annotation: the description of the `Query` type, which SmallRye defaults to "Query root", and `@specifiedBy` on the `UnLocode` scalar. The conformance diff compares descriptions, so both must match. With `quarkus.smallrye-graphql.events.enabled=true`, SmallRye fires the graphql-java schema builder as a CDI event just before it builds the schema, and an observer transforms it:

```java
    void applyContractDetails(@Observes GraphQLSchema.Builder builder) {
        GraphQLSchema schema = SchemaTransformer.transformSchema(builder.build(), new GraphQLTypeVisitorStub() {
            @Override
            public TraversalControl visitGraphQLObjectType(
                    GraphQLObjectType node, TraverserContext<GraphQLSchemaElement> context) {
                return "Query".equals(node.getName())
                        ? changeNode(context, node.transform(type -> type.description(QUERY_DESCRIPTION)))
                        : TraversalControl.CONTINUE;
            }

            @Override
            public TraversalControl visitGraphQLScalarType(
                    GraphQLScalarType node, TraverserContext<GraphQLSchemaElement> context) {
                return "UnLocode".equals(node.getName())
                        ? changeNode(context, node.transform(scalar -> scalar.specifiedByUrl(UN_LOCODE_SPECIFIED_BY)))
                        : TraversalControl.CONTINUE;
            }
        });
        // SmallRye keeps building from the builder it fired, so write the
        // transformed types back into it rather than returning a new one.
        builder.query(schema.getQueryType())
                .clearAdditionalTypes()
                .additionalTypes(schema.getAdditionalTypes())
                .codeRegistry(schema.getCodeRegistry());
    }
```

Strawberry takes both as arguments: `description=` on the `Query` type and `specified_by_url=` on the scalar. The observer is the pattern for any schema detail that sits outside the annotations.

The custom scalars differ only in mechanism. SmallRye maps a record that implements `CustomStringScalar` and carries `@CustomScalar("TrackingId")`. Strawberry maps a `NewType` to a `strawberry.scalar` definition in `StrawberryConfig.scalar_map`, with a `parse_value` function that rejects anything but a string.

## Querying each stack by hand

`verify.sh` removes the stack when it finishes. To explore, start it yourself under the same fixed project name, `gql-ch00-prereq`:

```bash
docker compose -f examples/00-prerequisites/compose.yaml up -d --build
```

Quarkus listens on host port 8080 and Python on 8081, both at `/graphql`. A GraphQL request over HTTP is a JSON `POST` with a `query` string. This one works against either port:

```bash
curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { id trackingId description origin { unLocode name country } destination { unLocode name } } }"}'
```

Both stacks return the same bytes:

```json
{"data":{"cargo":{"id":"cargo_ABC123","trackingId":"ABC123","description":"Palletized electronics","origin":{"unLocode":"USNYC","name":"New York","country":"US"},"destination":{"unLocode":"NLRTM","name":"Rotterdam"}}}}
```

The cargo is hardcoded in both implementations; `cargo_ABC123` and `loc_USNYC` are opaque `Node` identifiers. An unknown tracking id is data, not an error:

```bash
curl -s localhost:8081/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"NOPE99\") { trackingId } }"}'
```

```json
{"data":{"cargo":null}}
```

A request error is where the stacks first differ visibly. Omit the required argument:

```bash
curl -s -w ' [HTTP %{http_code}]' localhost:8080/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo { trackingId } }"}'
```

Quarkus answers with graphql-java's validation text and no `data` entry, which is what the specification prescribes when execution never started:

```json
{"errors":[{"message":"Validation error (MissingFieldArgument@[cargo]) : Missing field argument 'trackingId'","locations":[{"line":1,"column":3}],"extensions":{"classification":"ValidationError"}}]} [HTTP 200]
```

The same request against port 8081 returns different wording and an explicit `"data":null`:

```json
{"data":null,"errors":[{"message":"Argument 'Query.cargo(trackingId:)' of type 'TrackingId!' is required, but it was not provided.","locations":[{"line":1,"column":3}]}]} [HTTP 200]
```

Error text belongs to the framework, not the contract, so a client branches on structure (`errors` present, `data` absent or null) and never on message wording. And the status is `200` in both cases, so monitoring has to read the `errors` array rather than the HTTP status.

Passing a number for the string-backed scalar fails the same way on both stacks. Both implement `TrackingId` as a string-backed custom scalar; one that coerced `123` to `"123"` would make the stacks disagree on bad input:

```bash
curl -s localhost:8081/graphql -H 'Content-Type: application/json' \
  -d '{"query":"query($t: TrackingId!){ cargo(trackingId: $t) { trackingId } }","variables":{"t":123}}'
```

```json
{"data":null,"errors":[{"message":"Variable '$t' has invalid value: Expected value of type 'TrackingId', but encountered error 'expected a string, got int'; found: 123.","locations":[{"line":1,"column":7}]}]}
```

Each stack also exposes a health endpoint for the Compose healthchecks: SmallRye Health under `/q/health` (with `/q/health/ready`), and a small FastAPI route on the Python side.

```bash
curl -s localhost:8080/q/health | jq -c .
curl -s localhost:8081/health
```

```json
{"status":"UP","checks":[]}
{"status":"UP"}
```

## Observability on request

Both services are wired for OpenTelemetry: Quarkus includes `quarkus-opentelemetry`, and the Python container starts through `opentelemetry-instrument`, which instruments FastAPI without code changes. Telemetry is off by default: `compose.yaml` sets `QUARKUS_OTEL_SDK_DISABLED=true` and `OTEL_SDK_DISABLED=true`.

`grafana/otel-lgtm` is an all-in-one image that bundles an OpenTelemetry Collector with Loki for logs, Tempo for traces, Prometheus for metrics and Grafana for dashboards. `compose.observability.yaml` adds it as the `lgtm` service, switches both SDKs on, points `OTEL_EXPORTER_OTLP_ENDPOINT` at it and makes the services wait for its healthcheck:

```bash
cd examples/00-prerequisites
docker compose -f compose.yaml -f compose.observability.yaml up -d --build
```

Grafana is at `http://localhost:3000`. The override enables anonymous Admin access and hides the login form, which is acceptable for a local lab and wrong anywhere else. The other published ports are 4317 (OTLP over gRPC), 4318 (OTLP over HTTP), 9090 (Prometheus-compatible query), 3100 (Loki) and 3200 (Tempo). Send a few queries, then open Explore in Grafana and choose the Tempo data source to find the traces. Every example through error handling carries both Compose files.

## Troubleshooting

**A port is already in use.** The lab publishes 8080 and 8081, and the observability file adds 3000 and the collector ports. Find the owner before changing anything:

{% raw %}
```bash
ss -ltnp | grep -E ':(8080|8081|3000)\b'
docker ps --format '{{.Names}}\t{{.Ports}}'
```
{% endraw %}

Later examples use `8100 + 10*NN` for Quarkus and the next port for Python, where `NN` is the two-digit directory number, so ports do not collide. Remove a stale lab from an interrupted run with `docker compose -f examples/00-prerequisites/compose.yaml down -v`.

**`permission denied` on the Docker socket.** Your user is not in the `docker` group, or the change has not reached your shell. Run `sudo usermod -aG docker "$USER"`, then log out and back in, or start a shell with `newgrp docker`.

**A wait times out on the first run.** `wait_for_graphql` allows 90 seconds. A cold machine building two images and starting a JVM can need longer, and `verify.sh` then prints the service logs. Run it again: the second run reuses the layer cache. If a service exits instead of starting, the log tail names the cause.

**The wrong Node version.** `contracts/package.json` declares `engines.node >= 24`. An older Node can still run the checks, but `npm ci` prints an `EBADENGINE` warning, and a toolchain that differs from CI is the first suspect when a lint or diff result differs locally. If `graphql-inspector` is missing, `verify.sh` runs `npm ci --prefix contracts` itself, so a first run needs network access for npm as well as for the images.

**Running outside containers.** For live reload, run one stack directly. Quarkus, from `examples/00-prerequisites/quarkus`, serves on 8080:

```bash
mvn quarkus:dev
```

Python, from `examples/00-prerequisites/python`, serves on the port you give it:

```bash
uv sync
uv run uvicorn app.main:app --port 8081
```

Stop the Compose project first, or the ports conflict. Both answer the same `curl` queries.

## Build, run, observe

From the repository root:

```bash
bash examples/00-prerequisites/verify.sh
```

The first run takes several minutes. The script starts the Compose project once and tears it down on exit with `down -v --remove-orphans`, printing the last 200 log lines of each service first when a run fails. Per stack it waits up to 90 seconds for `{ __typename }` to answer, then checks:

- the canned cargo `ABC123`, with every returned field value, both custom scalars and the `Node` interface;
- an unknown id returns `data.cargo` equal to `null` with no `errors`, because the contract declares `Query.cargo` nullable;
- a query that omits `trackingId`, and a variable that supplies the number `123` for `TrackingId`, each return a non-empty `errors` array and no `data`, because the server rejects the request before any resolver runs;
- `__type` reports `TrackingId` and `UnLocode` as `SCALAR`, with `specifiedByURL` set to `https://unece.org/trade/uncefact/unlocode` on `UnLocode` and `null` on `TrackingId`;
- `assert_sdl_conforms` points `graphql-inspector` at the live endpoint and diffs it against `contracts/schema/**/*.graphql` in both directions.

Diffing live against canonical catches anything the stack exposes that the contract lacks or loosens, such as an extra field or `Cargo` where the contract says `Cargo!`. Diffing canonical against live catches anything the stack serves differently: a nullable field the contract makes non-null, a changed type, a missing argument or a changed description. `LGTM_SDL_IGNORE` filters, by regular expression, the parts of the schema the lab does not serve yet and a short list of framework-injected names. A tool failure, such as an unreachable endpoint, fails the check and never reads as conformance.

The filter exists because the raw diff is noisy. Run by hand against the Quarkus stack, it lists forty differences, mostly types the slice does not serve yet plus SmallRye's `constraint`, `defer`, `experimental_disableErrorPropagation` and `rolesAllowed` directives and its `BigDecimal` and `BigInteger` scalars:

```bash
cd contracts && npx graphql-inspector diff http://localhost:8080/graphql "schema/**/*.graphql"
```

The run prints a `PASS` line only when the checks hold for both stacks. Later chapters extend the same script and keep the same output shape. The loop: change the code, run `verify.sh`, read the diff when it fails.

- Drop `@NonNull` from a field of the Java `Cargo` record and rerun: the live-to-canonical diff reports the field as nullable where the contract says non-null.

## For deeper coverage

- Samer Buna, *GraphQL in Action* (Manning, 2021): schema and resolver fundamentals on top of a running server.
- [GraphQL: Learn](https://graphql.org/learn/): the specification's own introduction to the type system and execution.
- [Quarkus: SmallRye GraphQL](https://quarkus.io/guides/smallrye-graphql): the extension that builds the Quarkus stack's schema code-first.
- [Strawberry GraphQL documentation](https://strawberry.rocks/docs): the decorator-based code-first approach the Python stack uses.
