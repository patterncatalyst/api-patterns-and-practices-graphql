---
title: "Prerequisites and the lab"
order: 0
part: "Prerequisites & the Lab"
description: "Toolchain pins, the repository layout, and a Docker Compose lab that serves the same GraphQL schema from Quarkus and Python and proves both against the canonical SDL."
duration: "25 min read"
---

Every hands-on chapter in this book hands you a running GraphQL server in two languages and a script that proves both of them behave the same way. This chapter sets that up. It lists what to install and why each version is pinned, shows where things live in the repository, introduces the shipping domain that every later schema describes, and runs the first example: a minimal tracking view that answers one query from canned data on Quarkus and on Python. Nothing in it is about schema design or resolver logic yet. The point is to make the toolchain the thing you stop thinking about, so that when a later chapter fails a check, the cause is the chapter's topic and not a missing tool.

The code is in `examples/00-prerequisites/`. The `verify.sh` script there builds both images, starts them, checks them and tears them down; its `README.md` lists the ports and the expected values.

## What to install

The lab is a Linux lab. The commands below target Fedora and RHEL-family systems, and every example runs on Docker Engine with the Compose plugin. Neither Docker Desktop nor Podman is assumed anywhere in the book, so a command that says `docker compose` means exactly that binary.

The examples build their images from inside containers, so `verify.sh` itself needs little on the host: Docker, Node with npm, `curl` and a system `python3`. The language toolchains matter when you step through code in an IDE or run a server outside a container, which is how you will work from Chapter 3 onward. Install all of them now and later chapters add no further tools.

| Tool | Version in this repo | Why it is here |
|---|---|---|
| Docker Engine with the Compose plugin | any current release | Builds and runs every example; `docker compose` is the only orchestration command used |
| JDK | 25 (LTS) | `maven.compiler.release` is 25; the images are `ubi10/openjdk-25` and `-runtime` |
| Maven | 3.9.x | Builds the Quarkus modules; the container build uses the JDK image's 3.9.9 |
| Quarkus platform | 3.40.1 (pinned in each `pom.xml`) | SmallRye GraphQL, SmallRye Health and OpenTelemetry extensions |
| Quarkus CLI | optional | A shortcut for `quarkus dev`; `mvn quarkus:dev` does the same |
| Python | 3.14 | `requires-python = ">=3.14"`; the runtime image is `ubi10/python-314-minimal` |
| uv | 0.13.1 in the Containerfile; Fedora's 0.12 also reads `uv.lock` | Creates the virtual environment from `uv.lock` and installs the interpreter if needed |
| Node.js | 24 LTS (CI pins 24.22.0) | Runs GraphQL ESLint and GraphQL Inspector from `contracts/` |
| `curl` and `jq` | any current release | Sends queries by hand and formats responses |

On Fedora, one command installs most of the host-side tools:

```bash
sudo dnf install -y java-25-openjdk-devel maven nodejs24-bin nodejs24-npm-bin uv jq curl
```

On RHEL and derivatives, enable the repositories that carry `java-25-openjdk-devel` and Node 24 for your release, or install the JDK through SDKMAN and Node through a version manager of your choice. Whatever the source, confirm the three versions that matter before moving on:

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

On RHEL, whose `dnf` takes `config-manager --add-repo`, use the `rhel` repository file. Log out and back in after the `usermod` so the new group applies, then check both the engine and the plugin:

```bash
docker run --rm hello-world
docker compose version
```

Membership in the `docker` group is equivalent to root on that machine, the usual trade on a development workstation.

The Python and Node pins follow one rule: the newest stable release that every dependency in the chain supports, pinned exactly. Strawberry 0.335.0, FastAPI 0.143.2 and uvicorn 0.54.0 are fixed in `pyproject.toml` and recorded in `uv.lock`. GraphQL Inspector 7.0.1, GraphQL ESLint 4.4.2 and `graphql` 16.14.2 are fixed in `contracts/package.json`. The container images use exact tags, `ubi10/openjdk-25` and `ubi10/openjdk-25-runtime` at `1.24-16` and `ubi10/python-314-minimal:10.2-1791928506`, so a rebuild next month produces the same bits. Bumping any of these is a reviewed change with its own commit, never a side effect of a rebuild.

The base images are Red Hat's Universal Base Image 10, which needs no subscription to pull, and everything else in the stack is open source.

## The repository layout

Three directories matter, and the boundary between them is the structure of the whole book.

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

`contracts/schema/shipping/` is the single source of truth for what the API looks like. It is Schema Definition Language, the textual form of a GraphQL schema, and every type and field in it carries a description. Two gates protect it in CI and on your machine. `npm run lint` applies GraphQL ESLint's schema rules, and `npm run breaking` runs GraphQL Inspector's diff against the base branch and fails a change that removes a field, changes a type or drops an enum value. Chapters 5 and 11 build on these.

The gRPC book generates server stubs from its `.proto` files. GraphQL frameworks work the other way around. Both Quarkus SmallRye GraphQL and Strawberry build their schema from annotated or decorated code, the approach called code-first, and expose it through introspection. The canonical SDL is therefore not compiled into either server. It is the yardstick the running schema is measured against, and the measuring is what `verify.sh` does. The Containerfiles use each stack's own directory as the build context, so no contract file is copied into an image.

Each `examples/NN-*/` directory has the same shape, so once you have run one you have run them all. `quarkus/` and `python/` hold the two implementations, `compose.yaml` starts them side by side, and `verify.sh` asserts the chapter's claims against both. `examples/_lib/lib.sh` is the shared harness that `verify.sh` sources. It starts and tears down the Compose project, waits for the endpoint, sends operations with `curl`, and provides assertions that read the response body. A `200 OK` proves nothing in GraphQL over HTTP, because a response carrying `errors` is still a `200` for the `application/json` media type. Every assertion therefore inspects `data` and `errors`.

{% include excalidraw.html file="00-lab-topology" alt="Topology of the Compose lab. On the left, verify.sh in examples/00-prerequisites sources lib.sh from examples/_lib, and lib.sh sends POST requests to both services. In the middle, a band labelled Docker Compose project gql-ch00-prereq contains three boxes stacked vertically: quarkus on host port 8080 serving /graphql and /q/health, built with SmallRye GraphQL code-first; a dashed box for otel-lgtm, added by the compose.observability.yaml file, with Grafana on port 3000 and OTLP on port 4317; and python on host port 8081 serving /graphql and /health, built with Strawberry on FastAPI code-first. Dashed arrows labelled OTLP run from both services to otel-lgtm. On the right, graphql-inspector, run by assert_sdl_conforms, introspects both services with arrows labelled introspect and points to contracts/schema/shipping/*.graphql, the canonical SDL, with an arrow labelled diff both ways." caption="Figure 0.1 — The lab: verify.sh drives both stacks through lib.sh, and graphql-inspector compares each live schema with the canonical SDL." %}

## The shipping domain and the tracking view

Every example in this book works against one domain, the same one the sibling REST and gRPC books use. A shipping company books cargo for carriage between ports. Chapter 1 defined the **tracking view**: a read-oriented GraphQL layer in front of the services that own the data. A customer asks where a cargo is and what happens next, and the tracking view assembles the answer from three owners in one response.

A **Cargo** is the goods being shipped and the root of the tracking view. Clients find it by **TrackingId**, an opaque string such as `ABC123`, and compare it for equality only. A **Location** is a port or terminal identified by its UN/LOCODE, the five-character United Nations location code: `USNYC` for New York, `NLRTM` for Rotterdam, `SGSIN` for Singapore. A **RouteSpecification** records what the customer asked for: origin, destination and an arrival deadline. An **Itinerary** is the planned route, an ordered list of **Leg**s. Each leg loads cargo at one location and unloads it at another, normally on a named **Voyage**, a scheduled sailing made of carrier movements. A **HandlingEvent** records something that physically happened to the cargo: received, loaded, unloaded, cleared by customs, claimed. A **Delivery** is the state derived from the handling history: transport and routing status, last known location, current voyage, estimated arrival and the next expected activity, which is a **HandlingActivity**.

{% include excalidraw.html file="00-shipping-domain-model" alt="Domain model of the tracking view, grouped by the service that owns each type. A band labelled Cargo service (REST) holds Cargo, a Node with id, trackingId, description, origin and destination, routeSpecification, delivery, a nullable itinerary and handlingHistory with first, after, last and before arguments, plus RouteSpecification with origin, destination and arrivalDeadline. A band labelled Routing service (gRPC) holds Itinerary with legs and finalArrivalDate, and Leg with a nullable voyage, loadLocation, unloadLocation, loadTime and unloadTime. A band labelled Handling event store holds HandlingEvent, a Node with trackingId, type, location, a nullable voyage, a nullable cargo, completionTime and registrationTime; Delivery with transportStatus, routingStatus, misdirected and nullable estimatedTimeOfArrival, lastKnownLocation, currentVoyage and nextExpectedActivity; and HandlingActivity with type, location and a nullable voyage. A band labelled Shared reference types holds Location, a Node with unLocode, name and country, and Voyage, a Node with number and a schedule of CarrierMovement. Arrows run from Cargo to RouteSpecification, from Cargo to Itinerary marked nullable, from Itinerary to Leg, from Leg to Location and to Voyage marked nullable, from Cargo to HandlingEvent for the history, from Cargo to Delivery, and from Delivery to HandlingActivity." caption="Figure 0.2 — The shipping domain as the SDL describes it, grouped by the service that owns each type." %}

The figure groups the types by owner because the grouping explains the nullability. The question mark on a field marks it nullable, and nearly every nullable field sits on a boundary between services. `Cargo.itinerary` is null until the routing service assigns a route. `Leg.voyage` is null when the voyage lookup fails, so one failed lookup degrades a leg instead of the whole response. `Delivery.estimatedTimeOfArrival` is null when no estimate exists, and `HandlingEvent.cargo` is null when the cargo service is unavailable. Fields the domain guarantees, such as `Cargo.trackingId` and `Leg.loadLocation`, are non-null. Chapter 4 treats this design in depth, including how a null in a non-null position propagates to the nearest nullable parent.

Money, which the REST and gRPC books carry, is absent from this schema. The tracking view reads and records handling; pricing stays with the services that own it.

The schema also contains exactly one mutation, `registerHandlingEvent`, and one subscription, `cargoHandled`. This chapter serves none of that. It serves a slice of the read side: `Query.cargo(trackingId: TrackingId!): Cargo`, with `Cargo` limited to `id`, `trackingId`, `description`, `origin` and `destination`, the `Location` type, the `Node` interface and the two custom scalars. The slice is enough to prove that scalars, an interface, an object graph and nullability all survive code-first generation on both stacks.

## Running the lab

From the repository root:

```bash
bash examples/00-prerequisites/verify.sh
```

The first run takes several minutes because it builds two images; later runs reuse the layer cache. The script starts the project once, then checks each stack in five steps.

**Starts the project.** `compose_up` runs `docker compose up -d --build` under the fixed project name `gql-ch00-prereq` and registers an exit trap. Whatever happens afterward, the trap tears the project down with `down -v --remove-orphans`, and when a run fails it first prints the last 200 log lines of each service. Before each stack's checks, `wait_for_graphql` polls `{ __typename }` until the endpoint answers `200` with `Query` in `data`, for up to 90 seconds, which covers a JVM cold start.

**Queries the canned cargo.** A named query selects `__typename`, `id`, `trackingId`, `description`, the origin location with all four of its fields, and the destination's code and name. Eleven assertions compare each returned value with the canned one. This proves the build, the HTTP endpoint, serialization of both custom scalars, and the `Node` interface on each stack.

**Asks for an unknown id.** `cargo(trackingId: "NOPE99")` must return `data.cargo` equal to `null` with no `errors`. The canonical SDL declares `Query.cargo` nullable, so a missing cargo is an ordinary absence, not a failure.

**Sends two invalid requests.** A query that omits the required `trackingId` argument, and a query whose variable supplies the number `123` for `TrackingId`, must each return a non-empty top-level `errors` array and no `data`. The first assertion also checks that the message names `trackingId`. These are request errors: the server rejects the document or its variables before any resolver runs. The number case matters because both stacks implement `TrackingId` as a string-backed custom scalar, and a scalar that coerced `123` to `"123"` would make the two stacks disagree on bad input.

**Checks the scalars through introspection.** `__type(name: "TrackingId")` and `__type(name: "UnLocode")` must both have kind `SCALAR`, and `UnLocode` must report `specifiedByURL` equal to `https://unece.org/trade/uncefact/unlocode` while `TrackingId` reports `null`. The `@specifiedBy` directive points a custom scalar at the specification that defines its format. The schema diff in the next step covers types, fields, arguments and descriptions; this step asserts `specifiedByURL`.

**Compares the live schema with the contract.** `assert_sdl_conforms` points `graphql-inspector` at the running endpoint and diffs the schema it reads against `contracts/schema/**/*.graphql` twice. Diffing live against canonical catches anything the stack exposes that the contract lacks or loosens, such as an extra field or `Cargo` where the contract says `Cargo!`. Diffing canonical against live catches anything the stack serves differently from the contract: a nullable field the contract makes non-null, a changed type, a missing argument, or a changed description. The only differences tolerated are the parts of the schema this chapter does not serve yet and a short list of framework-injected names, which `LGTM_SDL_IGNORE` filters by regular expression. A tool failure, such as an unreachable endpoint, fails the check and never reads as conformance.

Raw output from the same tool shows why the filtering exists. Run the diff by hand against the Quarkus stack, with the stack up, and it lists forty differences:

```bash
cd contracts && npx graphql-inspector diff http://localhost:8080/graphql "schema/**/*.graphql"
```

Most of those lines are types and fields the slice does not serve yet, reported as additions, plus SmallRye's `constraint`, `defer`, `experimental_disableErrorPropagation` and `rolesAllowed` directives and its `BigDecimal` and `BigInteger` scalars, reported as removals. The harness separates "not served yet" from "served wrongly"; the raw diff reports both as differences.

A passing run ends like this:

```text
=== quarkus: toolchain check passed ===
...
=== python: toolchain check passed ===

PASS - Ch0 prerequisites skeleton: Quarkus (SmallRye GraphQL) and Python (Strawberry) both build code-first, boot under Compose, return the canned cargo ABC123 from Query.cargo with exact field values, and expose a schema that conforms to the canonical SDL - the toolchain works.
```

`PASS` appears only when the checks hold for both stacks. The chapters after this one extend the same script with their own assertions and keep the same output shape.

## Querying each stack by hand

`verify.sh` removes the stack when it finishes. To explore, start it yourself, with the same project name so a manual run and a scripted run never collide:

```bash
docker compose -f examples/00-prerequisites/compose.yaml up -d --build
```

Quarkus listens on host port 8080 and Python on 8081, both at `/graphql`. A GraphQL request over HTTP is a JSON `POST` with a `query` string. This one asks for the canned cargo and works against either port:

```bash
curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { id trackingId description origin { unLocode name country } destination { unLocode name } } }"}'
```

Both stacks return the same bytes:

```json
{"data":{"cargo":{"id":"cargo_ABC123","trackingId":"ABC123","description":"Palletized electronics","origin":{"unLocode":"USNYC","name":"New York","country":"US"},"destination":{"unLocode":"NLRTM","name":"Rotterdam"}}}}
```

The cargo is hardcoded in both implementations. Its origin is New York, its destination is Rotterdam, and the id values `cargo_ABC123` and `loc_USNYC` are the opaque global identifiers that Chapter 3 returns to when it covers `Node`. Pipe the output through `jq .` for readable formatting.

An unknown tracking id is data, not an error:

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

Quarkus answers with validation text from graphql-java and no `data` entry at all, which is what the specification prescribes when execution never started:

```json
{"errors":[{"message":"Validation error (MissingFieldArgument@[cargo]) : Missing field argument 'trackingId'","locations":[{"line":1,"column":3}],"extensions":{"classification":"ValidationError"}}]} [HTTP 200]
```

The same request against port 8081 returns a different wording and an explicit `"data":null`:

```json
{"data":null,"errors":[{"message":"Argument 'Query.cargo(trackingId:)' of type 'TrackingId!' is required, but it was not provided.","locations":[{"line":1,"column":3}]}]} [HTTP 200]
```

Those lines show two things. First, error text belongs to the framework, not the contract, so a client must branch on structure (`errors` present, `data` absent or null) and never on message wording. `verify.sh` follows that rule: it asserts only that an error exists and that its message mentions `trackingId`. Second, the status is `200` in both cases. That is the `application/json` behavior from Chapter 1, and it is why monitoring has to read the `errors` array, the convention Chapter 9 sets out.

Passing a number for the scalar shows the string-only rule working on both stacks:

```bash
curl -s localhost:8081/graphql -H 'Content-Type: application/json' \
  -d '{"query":"query($t: TrackingId!){ cargo(trackingId: $t) { trackingId } }","variables":{"t":123}}'
```

```json
{"data":null,"errors":[{"message":"Variable '$t' has invalid value: Expected value of type 'TrackingId', but encountered error 'expected a string, got int'; found: 123.","locations":[{"line":1,"column":7}]}]}
```

Each stack also exposes a health endpoint, which the Compose healthchecks use. Quarkus serves SmallRye Health under `/q/health`, with `/q/health/ready` for readiness, and the Python app serves a small FastAPI route:

```bash
curl -s localhost:8080/q/health | jq -c .
curl -s localhost:8081/health
```

```json
{"status":"UP","checks":[]}
{"status":"UP"}
```

When you finish, remove the project and its network:

```bash
docker compose -f examples/00-prerequisites/compose.yaml down -v
```

## Two stacks, one SDL

The two servers are small, and the differences between them are the ones this book keeps returning to. The three that matter now are how each stack decides nullability, how each describes the schema, and how each supplies the two details of the SDL that Quarkus sets in code.

**Nullability.** Java has no non-null reference type, so SmallRye GraphQL treats every object-typed field as nullable unless you say otherwise with `@NonNull`. Python treats every Strawberry field as non-null unless its type includes `None`. The same SDL line, `origin: Location!`, therefore comes from opposite defaults:

```java
@Type("Cargo")
public record Cargo(
        String id,
        @NonNull TrackingId trackingId,
        @NonNull String description,
        @NonNull Location origin,
        @NonNull Location destination) implements Node { /* getId() omitted */ }
```

```python
@strawberry.type
class Cargo(Node):
    id: strawberry.ID
    tracking_id: TrackingId
    description: str
    origin: Location
    destination: Location
```

Both snippets omit the `@Description` and `description=` arguments that carry the SDL descriptions. The Java record needs four annotations to say what the Python class says by omission, and a forgotten `@NonNull` produces `Location` where the contract says `Location!`. That is the difference the live-to-canonical diff reports as breaking. The root field shows the opposite case: `Query.cargo` is nullable in the contract, so Python writes `-> Cargo | None` and Java returns `Cargo` and leaves `@NonNull` off. Strawberry also maps Python's `tracking_id` to the GraphQL name `trackingId` automatically, where Java's record component is already camelCase. Chapter 4 explains how these defaults interact with null propagation.

**The `Node` interface.** In the SDL, `Node` declares one field, `id: ID!`, and `Cargo` and `Location` implement it. SmallRye derives an interface's fields from getter-named methods, so the interface declares `getId()` and each implementing record carries an explicit `getId()`, annotated `@Id @NonNull`. In Strawberry the `id` field on the interface class and the same field redeclared in each subclass is the whole mechanism.

**Contract details set in code.** Two details of the canonical SDL are set by an observer rather than by annotation: the description of the `Query` type, which SmallRye defaults to "Query root", and `@specifiedBy` on the `UnLocode` scalar. The conformance diff compares descriptions, so both must match the contract. The `ContractSchemaDetails` class sets them. With `quarkus.smallrye-graphql.events.enabled=true`, SmallRye fires the graphql-java schema builder as a CDI event just before it builds the schema, and an observer transforms it:

```java
void applyContractDetails(@Observes GraphQLSchema.Builder builder) {
    GraphQLSchema schema = SchemaTransformer.transformSchema(builder.build(), new GraphQLTypeVisitorStub() {
        // visitGraphQLObjectType: set the Query description
        // visitGraphQLScalarType: set specifiedByUrl on UnLocode
    });
    builder.query(schema.getQueryType()).clearAdditionalTypes()
           .additionalTypes(schema.getAdditionalTypes()).codeRegistry(schema.getCodeRegistry());
}
```

Strawberry accepts both as arguments instead: `description=` on the `Query` type and `specified_by_url=` on the scalar. This is the pattern for any schema detail that sits outside the annotations, and Chapter 5 returns to it when the whole contract has to match. The class is also the reason the schema-builder event is enabled in `application.properties`; nothing else in the module needs it.

The resolvers themselves are small. Quarkus declares a `@GraphQLApi` class with a `@Query` method that returns the canned cargo when `trackingId` equals `ABC123` and `null` otherwise. Strawberry decorates a method on the `Query` class with `@strawberry.field` and annotates the `tracking_id` parameter with `strawberry.argument`, which spells out the name `trackingId` that Strawberry would derive anyway and carries the description. The custom scalars differ only in mechanism. SmallRye maps a record that implements `CustomStringScalar` and carries `@CustomScalar("TrackingId")`. Strawberry maps a `NewType` to a `strawberry.scalar` definition in `StrawberryConfig.scalar_map`, with a `parse_value` function that rejects anything but a string. Chapter 3 walks through the scalar code, and Chapters 4 and 5 take on the nullability and contract-first questions this chapter only touches.

## Observability on request

Both services are wired for OpenTelemetry. Quarkus includes the `quarkus-opentelemetry` extension, and the Python container starts through `opentelemetry-instrument`, which instruments FastAPI without code changes. Telemetry is off by default: `compose.yaml` sets `QUARKUS_OTEL_SDK_DISABLED=true` for Quarkus and `OTEL_SDK_DISABLED=true` for Python, so a plain `docker compose up` starts the two services and nothing else.

To send telemetry to LGTM, add the observability file. `grafana/otel-lgtm` is an all-in-one image that bundles an OpenTelemetry Collector with Loki for logs, Tempo for traces, Prometheus for metrics and Grafana for dashboards. `compose.observability.yaml` adds it as the `lgtm` service, switches both SDKs on, points `OTEL_EXPORTER_OTLP_ENDPOINT` at it and makes the services wait for its healthcheck:

```bash
cd examples/00-prerequisites
docker compose -f compose.yaml -f compose.observability.yaml up -d --build
```

Grafana is then at `http://localhost:3000`. The override enables anonymous access with the Admin role and hides the login form, which is acceptable for a local lab and wrong anywhere else. Other published ports are 4317 (OTLP over gRPC), 4318 (OTLP over HTTP), 9090 (Prometheus-compatible query), 3100 (Loki) and 3200 (Tempo). Send a few queries with `curl`, then open Explore in Grafana and choose the Tempo data source to find the traces.

Every example from Chapter 3 to Chapter 18 carries the same pair of files, so the command above works in each of them. Chapter 19 is the one that makes LGTM a default service, because operation-level metrics and resolver traces are its subject.

## Troubleshooting

**A port is already in use.** The lab publishes 8080 and 8081, and the observability file adds 3000 and the collector ports. A second example, a local `mvn quarkus:dev` and a leftover container all compete for the same numbers. Find the owner before changing anything:

{% raw %}
```bash
ss -ltnp | grep -E ':(8080|8081|3000)\b'
docker ps --format '{{.Names}}\t{{.Ports}}'
```
{% endraw %}

Chapters after this one use `8100 + 10*NN` for Quarkus and the next port for Python, where `NN` is the chapter number, so examples do not collide with each other or with this one. A stale lab from an interrupted run is removed with `docker compose -f examples/00-prerequisites/compose.yaml down -v`.

**`permission denied` on the Docker socket.** The message `permission denied while trying to connect to the Docker daemon socket` means your user is not in the `docker` group, or the group change has not reached your shell. Run `sudo usermod -aG docker "$USER"`, then log out and back in, or start a shell with `newgrp docker`.

**A wait times out on the first run.** `wait_for_graphql` allows 90 seconds. A cold machine building two images and starting a JVM can need longer on the first run, and `verify.sh` then prints the service logs. Run it again: the second run reuses the image layers and the dependency cache. If a service exits instead of starting, the printed log tail names the cause.

**The wrong Node version.** `contracts/package.json` declares `engines.node >= 24`, and CI pins 24.22.0. An older Node can still install and run the checks, but `npm ci` prints an `EBADENGINE` warning, and a toolchain that differs from CI is the first suspect when a lint or diff result differs locally. Install Node 24 LTS and confirm with `node --version`. If `graphql-inspector` is missing, `verify.sh` runs `npm ci --prefix contracts` itself, so a first run needs network access for npm as well as for the images.

**Running outside containers.** To work on one stack with live reload instead of rebuilding an image, run it directly. Quarkus, from `examples/00-prerequisites/quarkus`, serves on 8080:

```bash
mvn quarkus:dev
```

Python, from `examples/00-prerequisites/python`, serves on the port you give it:

```bash
uv sync
uv run uvicorn app.main:app --port 8081
```

Stop the Compose project first, or the ports will conflict. Both commands answer the same `curl` queries shown above.

## Where this goes next

The lab is running, both stacks answer the same query, and a script proves they agree with one canonical contract. Chapter 3 starts the schema work by building up the SDL and its type system on top of this skeleton: scalars, enums, interfaces, unions and input types, written first in code on both stacks and checked against `contracts/schema/` by the same harness. Chapter 4 follows with the nullability decisions that Figure 0.2 hinted at, and Chapter 5 covers what it takes to keep two code-first servers aligned with one contract over time.

The loop to carry forward: change the code, run `verify.sh`, and read the diff against the canonical SDL when it fails.
