---
title: "Testing GraphQL APIs"
order: 23
part: "Testing & Debugging"
description: "What a GraphQL test suite asserts at each layer: the schema a framework builds, resolvers with a stubbed source, operations over the app's own HTTP layer, the exported SDL diffed against the contract, client documents validated against it, and a k6 load run whose assertions hold on any machine, with source-call counts read per request."
duration: "16 min read"
---

## Learning objectives

By the end of this chapter you can:

- Place each assertion at the cheapest layer that can see it: schema, resolver unit, operation integration, contract, client document, or load.
- Stub a source with `@InjectMock` or a fake `BookingSource` to assert the `path`, `message`, and `extensions.code` a resolver's error carries.
- Diff an exported `schema.graphql` against the canonical SDL in both directions with `assert_sdl_conforms`.
- Validate client documents with `graphql-inspector validate` and measure per-field usage with `coverage`.
- Write k6 `checks` and `thresholds` that assert request counts and per-request call invariants hold under concurrency, without asserting latency.

## Why this matters

Chapter 22 ended with three clients that send the same documents to both stacks and read what comes back. Every chapter before it checked the same thing with `verify.sh`: a script brings the stack up, sends operations and compares the answers. That proves the system once, from outside, with Docker and Node on the machine. A team also needs checks that run on every build in seconds, inside each service's own project, and one check that runs the documents at volume and still holds.

The code is in `examples/23-testing/`. It starts from the Chapter 14 example, so both servers serve the full tracking view with batching and a cost budget of 1,000, and the SDL does not change. What is new is around the servers: a test suite for each stack that runs in its own container image, a directory of client documents shared by every layer, and a k6 image that sends those documents at volume. `verify.sh` runs all of it and asserts the results.

## What a GraphQL test asserts

A GraphQL response is `200` for almost everything. Chapter 6 showed the engine answering `200` with `errors` for an execution failure, Chapter 9 showed partial data beside errors, and Chapter 14 showed a refusal that arrives as a `200` with no `data` at all. A test that checks the status line and stops there passes for all of them. A GraphQL test reads the body: `data` beside `errors`, the error's `path`, its `extensions.code`, and which nullable ancestor became null.

The behaviour that is not in the body is as important. Chapter 13 made the count of source calls a property of the design, and no response says how many calls produced it. The suites read the source-call log the example already keeps and treat the count as an output.

The layers trade fidelity for speed, and the cheapest layer that can see a failure should be the one that reports it. A resolver that returns the wrong field is visible to a unit that calls it. A mis-typed argument is visible to the schema. A routing or serialization failure appears only when a request crosses the HTTP layer. A property that depends on many requests overlapping appears only under load. Putting every assertion at the top layer makes a suite slow and its failures hard to read: a failed load check says that something differs, and a failed unit says which rule.

Figure 23.1 names the six layers and where each runs. The first three run inside each stack's test image, with no other service, no Node and no browser. The last three need the live stacks and the pinned `graphql-inspector` and `k6`, so `verify.sh` runs them.

{% include excalidraw.html file="23-test-layers" alt="A table of six layers with four columns: the layer, what it runs against, what it asserts, and where it runs. Three amber rows sit in a band labelled run inside each stack's test image. Schema runs against the built schema and asserts that types and scalars exist and the SDL is written out. Resolver unit runs against a function or a resolver with the booking source stubbed and asserts values, paths and codes. Operation runs against the app over its HTTP layer and asserts data beside errors, eight or six calls, and a refusal priced at 7,651. A second band is labelled run from verify.sh against the live stacks. Contract runs against both the exported and the live schema and asserts no breaking change either way. Client document runs against documents validated against the contract and asserts that valid documents pass and Cargo.weight is refused. Load runs k6 virtual users with an exact number of iterations and asserts that every check is true, the calls per request are the same, and forty retries write once. A footer says a test that disappears fails the build, because verify.sh counts 22 Quarkus and 18 Python tests." caption="Figure 23.1 — Six test layers. The first three run in each stack's test image; the last three run from verify.sh against the live stacks." %}

## Schema tests

Chapter 5 sketched a schema test for each stack and said Chapter 23 would build the real ones. They are the same two tests with two additions: each also checks the mutation input, and each writes the SDL it fetched to a report directory, so `verify.sh` can diff that file against the canonical SDL afterwards.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@QuarkusTest
class SchemaExportTest {

    @ConfigProperty(name = "tracking.test.export-dir")
    String exportDir;

    @Test
    void exportedSchemaDeclaresTheContractTypesAndScalars() throws IOException {
        String sdl = RestAssured.get("/graphql/schema.graphql")
                .then()
                .statusCode(200)
                .extract()
                .asString();

        assertTrue(sdl.contains("type Cargo implements Node"), "Cargo implements Node");
        assertTrue(sdl.contains("scalar TrackingId"), "the TrackingId scalar is declared");
        assertTrue(sdl.contains("input RegisterHandlingEventInput"), "the mutation input is declared");

        Path target = Path.of(exportDir);
        Files.createDirectories(target);
        Files.writeString(target.resolve("schema.graphql"), sdl, StandardCharsets.UTF_8);
    }
}
```

```python
def test_exported_schema_declares_the_contract_types_and_scalars() -> None:
    sdl = schema.as_str()

    assert "type Cargo implements Node" in sdl
    assert "scalar TrackingId" in sdl
    assert "input RegisterHandlingEventInput" in sdl

    export_dir = Path(os.environ.get("TRACKING_TEST_EXPORT_DIR", "build"))
    export_dir.mkdir(parents=True, exist_ok=True)
    (export_dir / "schema.graphql").write_text(sdl)
```

`@QuarkusTest` boots the application once for the class, on a free port (`quarkus.http.test-port=0`), and RestAssured aims at it with no address in the test. The export lists the custom scalars because `quarkus.smallrye-graphql.schema-include-scalars=true` is set. The Python test needs no server: the schema is a plain object and `as_str()` prints it.

These tests catch a type, a scalar or an input that disappears, in about a second. They cannot say whether a field's nullability or an argument's type still matches what clients were promised, because the test compares substrings. The diff against the contract says that, and it runs on the file these tests leave behind.

## Resolver unit tests

The cheapest tests run no server. `DeliveryDerivation` calls no source: it takes a cargo, an itinerary and the handling events and returns the derived state of Chapter 7. A plain JUnit class and a plain pytest function exercise it with the seed data and a handful of events.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Test
void aCargoWithNoEventsIsNotReceived() {
    Delivery delivery = derive("ABC123", List.of());

    assertEquals(TransportStatus.NOT_RECEIVED, delivery.transportStatus());
    assertNull(delivery.lastKnownLocation());
}
```

```python
def test_a_cargo_with_no_events_is_not_received() -> None:
    delivery = derivation.derive(data.CARGOS["ABC123"], data.ITINERARIES["ABC123"], [])

    assert delivery.transport_status is TransportStatus.NOT_RECEIVED
    assert delivery.last_known_location is None
```

The cost calculator of Chapter 14 is a price list, and each rule is a unit: a page multiplies its children by the size it asks for, `nodes` by the number of ids, an introspection field costs nothing, and a negative page size counts as empty. `TrackingCostCalculatorTest` hands the calculator one field at a time, as a graphql-java `FieldComplexityEnvironment` built from the field's name and arguments, and checks the six numbers.

A resolver is one step up. It needs a source, and the useful question is what the resolver does when the source fails. Chapter 9 gave the answer: the error carries the source's message and code at the field's path, and the field is null. The test replaces the booking source with one that fails and runs the real resolver.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@QuarkusTest
class BookingFailureTest {

    @InjectMock
    BookingSource booking;

    @Test
    void anUnavailableBookingServiceIsAnErrorAtTheCargoFieldWithItsCode() {
        when(booking.getCargo(any(), eq("ABC123")))
                .thenReturn(Uni.createFrom().failure(new SourceUnavailableException("booking service unavailable")));

        Documents.post("{ cargo(trackingId: \"ABC123\") { trackingId } }")
                .body("data.cargo", nullValue())
                .body("errors", hasSize(1))
                .body("errors[0].path", contains("cargo"))
                .body("errors[0].message", equalTo("booking service unavailable"))
                .body("errors[0].extensions.code", equalTo("SERVICE_UNAVAILABLE"));
    }
}
```

```python
class UnavailableBooking(BookingSource):
    """A booking service that cannot answer."""

    async def get_cargo(self, tracking_id: str):
        raise SourceUnavailable("booking service unavailable")


def context_with(booking_class: type[BookingSource]):
    context = get_context(SourceCalls(0), HandlingStore())
    context.booking = booking_class(context.booking.calls, context.request_id)
    return context


async def test_an_unavailable_booking_service_is_an_error_at_the_cargo_field_with_its_code() -> None:
    result = await schema.execute(
        '{ cargo(trackingId: "ABC123") { trackingId } }',
        context_value=context_with(UnavailableBooking),
    )

    assert result.data == {"cargo": None}
    assert len(result.errors) == 1
    error = result.errors[0]
    assert error.path == ["cargo"]
    assert error.message == "booking service unavailable"
    assert error.extensions == {"code": "SERVICE_UNAVAILABLE"}
```

`@InjectMock` replaces a normal-scoped CDI bean, here the `@ApplicationScoped` `BookingSource`, with a Mockito mock for the duration of the test. The assertions are the ones the wire shows: `data.cargo` is null, one error sits at `["cargo"]`, and the code is `SERVICE_UNAVAILABLE`.

On Python the schema is a plain object, so the test calls `schema.execute` with a context it built through the same `get_context` factory the router uses, then swaps one source. No HTTP layer is involved. The AnyIO pytest plugin runs the coroutine: each async module sets `pytestmark = pytest.mark.anyio`, and a fixture named `anyio_backend` returns `"asyncio"`.

## Operation integration tests

The next layer sends a request through the application's own HTTP layer: routing, content negotiation, the JSON body, the context factory and the response writer. The documents come from `documents/`, the directory that holds Chapter 22's four operations, so the suites send what the clients send.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Test
void trackCargoReturnsTheCargoItsPlacesAndItsDelivery() {
    Documents.postDocument("track-cargo", Map.of("id", "ABC123"))
            .body("errors", nullValue())
            .body("data.cargo.trackingId", equalTo("ABC123"))
            .body("data.cargo.description", equalTo("Palletized electronics"))
            .body("data.cargo.origin.name", equalTo("New York"))
            .body("data.cargo.destination.name", equalTo("Rotterdam"))
            .body("data.cargo.delivery.transportStatus", equalTo("ONBOARD_CARRIER"))
            .body("data.cargo.delivery.routingStatus", equalTo("ROUTED"));
}
```

```python
async def test_track_cargo_returns_the_cargo_its_places_and_its_delivery(
    app_client: httpx.AsyncClient, documents: Documents
) -> None:
    body = await post(app_client, documents.read("track-cargo"), {"id": "ABC123"})

    assert "errors" not in body
    cargo = body["data"]["cargo"]
    assert cargo["trackingId"] == "ABC123"
    assert cargo["description"] == "Palletized electronics"
    assert cargo["origin"]["name"] == "New York"
    assert cargo["destination"]["name"] == "Rotterdam"
    assert cargo["delivery"] == {"transportStatus": "ONBOARD_CARRIER", "routingStatus": "ROUTED"}
```

The Python application keeps its call log and its handling store on `app.state`, created in a lifespan function. httpx's `ASGITransport` calls the application without running that lifespan, so the fixture starts it with `asgi_lifespan.LifespanManager`, as the FastAPI documentation's "Async Tests" page describes:

```python
@pytest.fixture
async def app_client() -> AsyncIterator[httpx.AsyncClient]:
    async with LifespanManager(app) as manager:
        transport = httpx.ASGITransport(app=manager.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client
```

Every test gets a fresh application state, so a mutation in one test cannot change the answer of another. On Quarkus the application is shared by every class that uses the same configuration, and the tests that write use their own idempotency keys and their own cargo. Assertions that depend on the call log reset it first and read it once, so the order in which JUnit runs the classes does not matter.

Test names state a behaviour: `overBudgetDocumentIsRefusedBeforeAnySourceCall`, `replayingARegistrationReturnsTheSameEventAndWritesOnce`. A report that lists names like these reads as a description of the service, and a failure names the promise that no longer holds.

A client library is also a consumer of the endpoint, and the same layer can use one. `TypedClientTest` builds the SmallRye typesafe client of Chapter 22 against `@TestHTTPResource("/graphql")`, which injects the address of the application under test. The interface is the one clients would write:

```java
@GraphQLClientApi
public interface TrackingClient {

    record Cargo(TrackingId trackingId, String description) {}

    /** Only the tracking id, for a page where an edge's node may be an error. */
    record CargoSummary(TrackingId trackingId) {}

    record CargoEdge(String cursor, ErrorOr<CargoSummary> node) {}

    record CargoPage(List<CargoEdge> edges) {}

    @Query("cargo")
    Cargo cargo(@NonNull @Name("trackingId") TrackingId trackingId);

    @Query("cargos")
    CargoPage cargos(@Name("first") int first);
}
```

`ErrorOr` carries either the node or the errors reported at its path. The test pages all six cargos and checks that the failed nodes keep the server's message. The two stacks differ here for the reason Chapter 13 gave: SmallRye resolves a page's nodes in one bulk call, so the booking outage of `GHI345` reaches all six nodes, and Strawberry fails only that key. The Quarkus tests expect six errors and the Python test expects one. Strawberry's own `GraphQLTestClient`, which wraps Starlette's `TestClient`, covers the same layer on Python; `test_operations.py` uses it for one case, and Starlette's context manager runs the lifespan.

## Behaviour the schema cannot show

Three properties of this service are invisible in any response: how many calls a request made to the sources, that an over-budget document made none, and that a retried write happened once. Each is a test of its own.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Test
void fanOutMakesEightSourceCallsUnderOneRequestId() {
    calls.reset();

    Documents.postDocument("fan-out", null);

    List<SourceCall> log = calls.snapshot();
    assertEquals(8, log.size(), "FanOut calls the owners eight times");
    Set<String> requests = log.stream().map(SourceCall::request).collect(Collectors.toSet());
    assertEquals(1, requests.size(), "every call carries the request id of the one request");
}
```

```python
async def test_fan_out_makes_six_source_calls_under_one_request_id(
    app_client: httpx.AsyncClient, calls: SourceCalls, documents: Documents
) -> None:
    await post(app_client, documents.read("fan-out"))

    log = calls.snapshot()
    assert len(log) == 6
    assert len({call.request for call in log}) == 1
```

`FanOut` is Chapter 14's four-cargo page: an itinerary with legs, voyages and both locations, and the derived delivery. A second test in each suite pins the keys: one `getCargos` call for the four tracking ids, one `getItineraries`, one `listEventsFor`, and the voyage and location calls, each carrying every key at once. A resolver rewritten to fetch one cargo at a time would still return the same JSON and would fail here, which is the regression the test exists to catch. The Quarkus count is eight and the Python count six, for the per-field batching Chapter 13 described.

The cost refusal is tested the same way. `CostLimitTest` posts `OverBudget`, a page of 50 cargos with a page of 50 events each, and expects `maximum query complexity exceeded 7651 > 1000`, no `data` and an empty log. To check a price rather than a verdict, each suite builds a copy of the application whose budget is one unit under it. Quarkus does that with a test profile, which overrides configuration for the classes that name it. Python builds a second schema with a different budget.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@QuarkusTest
@TestProfile(FanOutPriceTest.BudgetOfFiftyTwo.class)
class FanOutPriceTest {

    public static class BudgetOfFiftyTwo implements QuarkusTestProfile {
        @Override
        public Map<String, String> getConfigOverrides() {
            return Map.of("tracking.query.max-cost", "52");
        }
    }

    @Test
    void fanOutIsPricedAtFiftyThree() {
        Documents.postDocument("fan-out", null)
                .body("errors[0].message", equalTo("maximum query complexity exceeded 53 > 52"));
    }
}
```

```python
def schema_with_budget(budget: int) -> strawberry.Schema:
    return strawberry.Schema(
        query=Query,
        mutation=Mutation,
        config=StrawberryConfig(scalar_map=SCALAR_MAP, batching_config=None),
        extensions=[partial(QueryCostLimiter, max_cost=budget, max_tokens=MAX_TOKENS)],
    )


async def test_fan_out_is_priced_at_fifty_three(documents: Documents) -> None:
    result = await schema_with_budget(52).execute(documents.read("fan-out"))

    assert [e.message for e in result.errors] == ["maximum query complexity exceeded 53 > 52"]
```

The refusal states the price, so the message is the assertion. The idempotency tests send the registration of `DEF456` twice with one key and count `handling.appendEvent` entries in the log: one write, and the same event id in both answers.

## Contract tests

The schema test checks substrings. The contract test checks the whole schema. Each test image writes the SDL its suite exported into a directory `verify.sh` mounted, and `assert_sdl_conforms` diffs each file against `contracts/schema/` in both directions, the check Chapter 5 built for live endpoints. The same assertion then runs on the two live URLs, so the schema a test built and the schema a server serves are both held to the contract. The two exports are not compared with each other. The claim is that each conforms.

The diff has two directions for a reason. From the live schema to the contract, a breaking line means the stack exposes something the contract lacks, or is looser than it, for example `Cargo` where the contract says `Cargo!`. From the contract to the live schema, a breaking line is something the stack does not serve. That is expected for `Subscription`, since this example is built on Chapter 14, and a failure for anything else. Descriptions count too: a changed description on a type, field or argument that both sides declare fails the check, because clients read it in their tooling.

The breaking-change gate of Chapter 11 is a different test: it compares the contract with its previous version, and it runs on the contract alone. The suites cannot see a contract change that both stacks follow, and the gate cannot see a stack that drifts from the contract. Together they cover both.

## Client documents as tests

Chapter 22's operations are the contract's first consumers, so they are tests too. `documents/` holds them one per file, with `fan-out.graphql` and `load/over-budget.graphql` beside them and the `Cargo.weight` fixture under `fixtures/`. The test images and the load image receive the directory through `build.additional_contexts`, so there is one copy, and `verify.sh` compares each file with the same-named operation in Chapter 22's `operations.graphql`, after dropping comments and whitespace. Chapter 22's files are read and never written. If one example changes a document, the other fails.

Two checks run on the documents with `graphql-inspector`. `validate` runs the specification's validation rules against the canonical SDL: every file in `documents/` passes, and the fixture that selects `Cargo.weight` fails with `Cannot query field weight on type Cargo`. `coverage` counts how many documents select each field. Over Chapter 22's four documents it reports `Query.cargo` selected twice, `Query.cargos` once and `Query.voyage` not at all, which is the information a team needs before it deprecates a field: who still asks for it, and which fields no client has ever asked for.

Both suites also execute the documents against the application, as the previous sections showed. A document that validates is not necessarily one that returns what a client expects, and a document that returns the right data has not necessarily been checked against the contract. The two checks cover different failures.

## Load tests that assert correctness

A load run answers a question the other layers cannot: do the properties still hold when many requests overlap? Batching is the one most worth asking about. Loaders are per request (Chapter 13), and a loader shared across requests would still pass every single-request test and put keys from several requests into one batch only under concurrency.

The example uses Grafana k6 v2.3.0, an open source (AGPL-3.0) load tool, used here unmodified as a command-line program, whose scripts are JavaScript. The image is `ubi10/ubi-minimal` with the static binary from the release tarball, checked against the SHA-256 pinned in the Containerfile and against the release's own checksum file. The script reads the shared documents with `open()` and defines one scenario per run:

```javascript
const shared = (vus, iterations, execName) => ({
  executor: 'shared-iterations',
  vus,
  iterations,
  maxDuration: '5m',
  exec: execName,
});
```

`shared-iterations` splits an exact number of iterations among a fixed number of virtual users, so a run sends exactly 160 requests whatever the machine's speed. `checks` read the GraphQL body of every response, and `thresholds` make k6 exit non-zero when a rule fails:

```javascript
export const options = {
  scenarios: RUNS[RUN].scenarios,
  thresholds: {
    http_req_failed: ['rate==0'],
    checks: ['rate==1'],
    iterations: [`count==${RUNS[RUN].iterations}`],
  },
};
```

A rate-based executor, which starts a fixed number of iterations per second whether or not the last ones finished, models traffic more closely. It also makes the number of requests depend on the machine's speed, so a count assertion would need a tolerance. This chapter's runs are regression checks on invariants, not capacity tests, and the exact executor fits them. The script also ends with a `handleSummary` function, so k6 writes the summary as one JSON line that `verify.sh` parses, and the image build runs `k6 inspect` on the script so a syntax error fails the build and not the first run.

No threshold mentions time. Latency on a shared CI runner differs from one job to the next, so a latency assertion would fail for reasons that are not in the code. The summary prints the median and the 95th percentile for the reader, and nothing asserts them. The assertions are counts and invariants, which hold on any machine.

Four runs on each stack, in this order, each starting from an empty source-call log:

| Run | Work | Checks and thresholds | Then `verify.sh` reads the log |
|---|---|---|---|
| `fanout` | 160 `FanOut` from 8 users | no `errors`, four edges, a transport status on each | 160 request ids; every request made 8 calls (Quarkus) or 6 (Python), exactly Chapter 14's keys |
| `cost` | 80 `FanOut` and 80 `OverBudget` at the same time, 4 users each | `OverBudget` has no `data` and one error with the stated price | 80 request ids: a refused request made no call; the other 80 made their own calls |
| `retry` | 40 registrations of one event, one idempotency key, 8 users | the same event id in every answer, no user errors | one `handling.appendEvent`; `ABC123` then reads `IN_PORT` |
| `mix` | 120 requests cycling `TrackCargo`, `TrackCargoBrief` and `ListCargos` | no errors; six edges and the per-stack outage on the list | 120 request ids in two shapes: 80 cargo reads and 40 pages |

Figure 23.2 follows the `cost` run. Two scenarios start together; the accepted requests become bulk source calls under their own request ids, and the refused ones stop at the cost check and add nothing to the log.

{% include excalidraw.html file="23-load-run" alt="Left, two blue boxes: four virtual users sending 80 FanOut requests, and four virtual users sending 80 OverBudget requests. Inside a band labelled server, quarkus or python, the FanOut arrow enters a cost check box reading cost 53, budget 1,000, then an amber arrow labelled runs leads to an execution box with batched resolvers, then down to a box of bulk source calls, booking getCargos and routing getItineraries, eight per request and six on Python. An amber arrow labelled logged leads to a dark box on the right, the source-call log grouped by request id, with 80 request ids, 8 or 6 calls each, and none from OverBudget. The OverBudget arrow enters a second cost check box reading cost 7,651, budget 1,000, then leads to a dark box labelled refused, error and no data. A dashed arrow from the refused box to the log is labelled no call. A footer says 160 requests went in, 80 request ids are in the log, and latency is printed and not asserted." caption="Figure 23.2 — One load run. Accepted requests fan out into bulk source calls under their own request ids; refused requests stop at the cost check, and the log counts none of them." %}

The log is read once, at the end of a run, and grouped by request id, which is what makes concurrency checkable. `assert_calls_per_request` fails if any request made a different number of calls, and `assert_calls_same_per_request` fails if any request's set of `source.op:key` entries differs from the single-request set, which would show keys from one request landing in another's batch. Both stacks pass: the loaders are per request, so concurrency changes the order of calls and not their content. The suites replay a registration one request after another; only concurrent retries reach the check the store makes under its lock, so the `retry` run is the test of that lock. The `retry` run is the only write, so it comes before the `mix` run that reads its result.

## Where the tests run

The in-process suites run in a `test` stage of each Containerfile, placed before the runtime stage, which stays the default target and does not depend on it, so a normal image build neither compiles the tests nor installs the test tools. The Quarkus stage adds the test sources and the documents, resolves the deployment artifacts of the test extensions with `quarkus:go-offline`, and runs `mvn verify`:

```dockerfile
FROM build AS test
# quarkus:go-offline resolves the deployment artifacts of the test-scope
# extensions, which the production build never needs, so the test JVM finds
# every Quarkus artifact in the local repository when it starts.
RUN mvn -B $MAVEN_RETRY_OPTS quarkus:go-offline
COPY src/test ./src/test
COPY --from=documents . src/test/resources/documents/
# umask 0 leaves the reports deletable by the user who mounted /out.
CMD umask 0 && exec mvn -B -o verify -Dmaven.javadoc.skip=true -Dsurefire.reports-dir=/out/surefire-reports -Dtracking.test.export-dir=/out
```

The Python stage installs the development group, which holds `pytest`, `anyio`, `httpx`, `httpx2` and `asgi-lifespan` and is left out of the production image with `--no-dev`:

```dockerfile
FROM build AS test
RUN uv sync --locked
COPY tests ./tests
COPY --from=documents . tests/documents/
ENV TRACKING_TEST_EXPORT_DIR=/out
# umask 0 leaves the reports deletable by the user who mounted /out.
CMD umask 0 && exec uv run --locked pytest -q --junitxml=/out/junit.xml
```

Both services sit behind a compose profile and run with `docker compose run`, with a scratch directory mounted at `/out`. Maven Surefire writes one XML report per class and pytest writes one `junit.xml`. `verify.sh` reads the totals from the XML and asserts the exact count, 22 and 18, with no failures, errors or skips, so a test that is deleted or skipped cannot pass unnoticed. The exit code alone could not show that.

Each report directory belongs to the user who mounts it. The containers run as UID 185, 1001 and root, so the images set `umask 0` before the test command and the files they write can be deleted by the user who created the directory. `verify.sh` creates its scratch directory with `mktemp`, mounts it with the `:z` label that SELinux hosts need, and removes it on exit.

Tests and builds run only in the pinned UBI images, never with the host's JDK, Maven, Python or uv, so a developer's machine and the CI runner execute the same thing. Quarkus Dev Services start backing services for `@QuarkusTest` when an extension needs one, such as a database or a broker. This example has none, because every source is in memory, so no container runtime is needed inside a test container.

## On the wire

Start the servers, create a report directory and run the Quarkus suite. The suite's exit code is Maven's, and the report directory receives the XML and the exported schema.

```bash
cd examples/23-testing
docker compose up -d --build
mkdir -m 0777 /tmp/ch23-quarkus /tmp/ch23-python
docker compose run --rm -T --build -v /tmp/ch23-quarkus:/out:z quarkus-test | grep -E "Tests run: 22|BUILD"
```

```text
[INFO] Tests run: 22, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

The Python suite, then one load run against Quarkus. k6's end-of-test summary is one JSON line. The timings differ on every machine and the counts do not.

```bash
docker compose run --rm -T --build -v /tmp/ch23-python:/out:z python-test | tail -1
docker compose run --rm -T --build -e TARGET=http://quarkus:8080/graphql -e RUN=fanout -e STACK=quarkus \
  load run --quiet /scripts/tracking.js
```

```text
18 passed in 0.17s
{"run":"fanout","stack":"quarkus","iterations":160,"requests":160,"checks":{"rate":1,"passes":640,"fails":0},"http_req_failed":0,"latency_ms":{"med":214,"p95":234}}
```

Each suite's exported schema is `schema.graphql` in its directory, and Surefire's reports are in `/tmp/ch23-quarkus/surefire-reports/`. Each row below is asserted by `verify.sh`.

| Check | Quarkus | Python |
|---|---|---|
| in-process suite | 22 tests, no failures, errors or skips | 18 tests, the same |
| exported schema | conforms to `contracts/schema/` | the same |
| `documents/` against Chapter 22 | the four operations, text for text | the same |
| `documents/*.graphql` validated | passes | the same |
| `fixtures/cargo-weight.graphql` validated | fails: `Cannot query field weight on type Cargo` | the same |
| coverage over the four documents | `Query.cargo` 2, `Query.cargos` 1, `Query.voyage` 0 | the same |
| `FanOut` | `VWX901`, `XYZ789`, `STU678`, `DEF456`; 8 calls | the same data; 6 calls |
| `OverBudget` | `maximum query complexity exceeded 7651 > 1000`, no `data`, 0 calls | the same, `data` null |
| `first: 51` | `BAD_USER_INPUT` | the same |
| `fanout` run | 160 request ids, 8 calls each, Chapter 14's keys | 160 request ids, 6 calls each |
| `cost` run | 80 request ids, 8 calls each | 80 request ids, 6 calls each |
| `retry` run | one `appendEvent` (`evt_10`); `ABC123` is `IN_PORT` | the same |
| `mix` run | 120 request ids: 80 cargo reads, 40 pages | the same |
| every run | 0 failed checks, 0 transport failures, the exact number of iterations | the same |
| live schema | conforms; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

Stop the stack when done:

```bash
docker compose down -v
```

`bash examples/23-testing/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>A test strategy is where the <em>contract and evolution style</em> axis of Chapter 2 becomes a gate: the schema each stack exports and the schema each serves are held to the canonical SDL, and Chapter 22's documents are held to it too, so a field that clients use cannot vanish unnoticed. The <em>aggregation across sources</em> axis makes the number of calls to the owners a tested output, because a resolver that fetches one cargo at a time returns the same JSON at a larger bill. The <em>client diversity and shape variance</em> axis puts the clients' own documents in the suite and in the load run, not documents the server's authors would have written. The <em>operational and security cost</em> axis decides how the load run is judged: by counts that hold on any runner, never by latency. The tracking view therefore tests six layers, runs the first three in each stack's test image with the exact test count asserted, runs the contract, the documents and a k6 load run from <code>verify.sh</code>, and asserts per request that batching, cost refusals and idempotency hold under concurrency.</p></div>

## Where this goes next

This chapter tested the tracking view at six layers: the schema each stack builds, resolvers with a stubbed source, operations over the application's own HTTP layer, the exported and live SDL against the contract, Chapter 22's documents against the contract, and a k6 load run that asserts counts per request and not latency.

Chapter 24 starts where a test did not catch the problem: a request fails in a running service, and the diagnosis runs from the response to the trace, the log record and the data. The test it ends with is the kind this chapter builds, one that fails without the fix.

For the tools, read the Quarkus guide "Testing your application" for `@QuarkusTest`, `@TestHTTPResource`, `@InjectMock` and test profiles, and the Quarkus "SmallRye GraphQL Client" guide for the typesafe client and `ErrorOr`. The REST Assured documentation covers the request and body matchers. Strawberry's "Testing" page covers `schema.execute` and the test client, FastAPI's "Testing" and "Async Tests" pages describe the `ASGITransport` and lifespan pattern, the pytest documentation covers fixtures and `--junitxml`, and AnyIO's "Testing with AnyIO" page covers the plugin. GraphQL Inspector's documentation has the "Validate", "Coverage" and "Diff" commands. The k6 documentation covers "Scenarios", "Shared iterations", "Checks", "Thresholds" and "End-of-test summary", and the GraphQL specification's "Validation" section lists the rules `graphql-inspector validate` applies.

## For deeper coverage

- *Cloud Native Design Patterns*, Appendix O — "API Testing with Newman": a parallel automated API test gate built on Postman/Newman collections, worth comparing against this chapter's layered GraphQL suites.
- [Quarkus — Testing your application](https://quarkus.io/guides/getting-started-testing) — `@QuarkusTest`, `@TestHTTPResource`, `@InjectMock`, and test profiles.
- Strawberry — Testing guide — `schema.execute` and the test client.
- [GraphQL Inspector](https://the-guild.dev/graphql/inspector) — the `validate`, `coverage`, and `diff` commands.
- [Grafana k6 — Using k6](https://k6.io/docs/using-k6/) — scenarios, checks, and thresholds.
