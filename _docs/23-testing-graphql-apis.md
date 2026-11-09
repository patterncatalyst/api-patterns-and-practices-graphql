---
title: "Testing GraphQL APIs"
order: 23
part: "Testing & Debugging"
description: "Where each GraphQL assertion belongs: schema, resolver with a stubbed source, operation over HTTP, exported SDL against the contract, client documents, and a k6 run that asserts counts instead of latency."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Place each assertion at the cheapest layer that can see it: schema, resolver unit, operation integration, contract, client document, or load.
- Stub a source with `@InjectMock` or a fake `BookingSource` to assert the `path`, `message`, and `extensions.code` a resolver's error carries.
- Diff an exported `schema.graphql` against the canonical SDL in both directions with `assert_sdl_conforms`.
- Validate client documents with `graphql-inspector validate` and measure per-field usage with `coverage`.
- Write k6 `checks` and `thresholds` that assert request counts and per-request call invariants under concurrency, without asserting latency.

## Why this matters

A script that brings the stack up, sends operations and compares the answers proves the system once, from outside, with Docker and Node on the machine. A team also needs checks that run on every build in seconds inside each service's project, and one check that runs the client documents at volume and still holds.

The code is in `examples/23-testing/`: both servers serve the tracking view with batching and a cost budget of 1,000, with a test image per stack, a `documents/` directory shared by every layer, and a k6 image. `verify.sh` runs all of it.

## What a GraphQL test asserts

GraphQL answers `200` for almost everything: an execution failure, partial data beside `errors`, and a cost refusal with no `data` at all. A test that checks the status line passes for all of them. A GraphQL test reads the body: `data` beside `errors`, the error's `path` and `extensions.code`, and which nullable ancestor became null.

Some behavior is not in the body. DataLoader batching makes the count of source calls a property of the design, and no response says how many calls produced it. The suites read the source-call log and treat the count as an output.

The layers trade fidelity for speed. A resolver that returns the wrong field is visible to a unit. A mistyped argument is visible to the schema. A routing or serialization failure appears only across the HTTP layer, and a property that depends on requests overlapping appears only under load. Report each failure at the cheapest layer that sees it: a failed load check says something differs, and a failed unit says which rule. The first three run inside each stack's test image with no other service; the last three need the live stacks and the pinned `graphql-inspector` and `k6`, so `verify.sh` runs them.

{% include excalidraw.html file="23-test-layers" alt="A table of six layers with four columns: the layer, what it runs against, what it asserts, and where it runs. Three amber rows sit in a band labelled run inside each stack's test image. Schema runs against the built schema and asserts that types and scalars exist and the SDL is written out. Resolver unit runs against a function or a resolver with the booking source stubbed and asserts values, paths and codes. Operation runs against the app over its HTTP layer and asserts data beside errors, eight or six calls, and a refusal priced at 7,651. A second band is labelled run from verify.sh against the live stacks. Contract runs against both the exported and the live schema and asserts no breaking change either way. Client document runs against documents validated against the contract and asserts that valid documents pass and Cargo.weight is refused. Load runs k6 virtual users with an exact number of iterations and asserts that every check is true, the calls per request are the same, and forty retries write once. A footer says a test that disappears fails the build, because verify.sh counts 22 Quarkus and 18 Python tests." caption="Figure 23.1: Six test layers. The first three run in each stack's test image; the last three run from verify.sh against the live stacks." %}

## Schema tests

A schema test checks that the contract's types, scalars and inputs exist, and writes the SDL it fetched to a report directory so `verify.sh` can diff it against the canonical SDL.

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

`@QuarkusTest` boots the application once for the class on a free port (`quarkus.http.test-port=0`), and RestAssured aims at it with no address. The export lists custom scalars because `quarkus.smallrye-graphql.schema-include-scalars=true` is set. The Python test needs no server: the schema is a plain object and `as_str()` prints it.

These tests catch a type, scalar or input that disappears, in about a second. They compare substrings, so a changed nullability or argument type needs the contract diff.

## Resolver unit tests

The cheapest tests run no server. `DeliveryDerivation` takes a cargo, an itinerary and the handling events and returns the derived delivery state, so a plain JUnit class and a plain pytest function exercise it.

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

The query-cost calculator is a price list, and each rule is a unit: a page multiplies its children by the size it asks for, `nodes` by the number of ids, an introspection field costs nothing, and a negative page size counts as empty. `TrackingCostCalculatorTest` hands the calculator one field at a time, as a graphql-java `FieldComplexityEnvironment` built from the field's name and arguments.

A resolver needs a source, and the question worth testing is what it does when the source fails. By the error-handling convention the error carries the source's message and code at the field's path, and the field is null. Replace the booking source with one that fails and run the real resolver.

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

`@InjectMock` replaces a normal-scoped CDI bean, here the `@ApplicationScoped` `BookingSource`, with a Mockito mock for one test. On Python the schema is a plain object, so the test calls `schema.execute` with a context built by the same `get_context` factory the router uses, then swaps one source. No HTTP layer is involved. The AnyIO pytest plugin runs the coroutine: each async module sets `pytestmark = pytest.mark.anyio`, and a fixture named `anyio_backend` returns `"asyncio"`.

## Operation integration tests

This layer sends a request through the application's own HTTP layer: routing, content negotiation, the JSON body, the context factory and the response writer. The documents come from `documents/`, which holds the four operations the clients send, so the suites send what the clients send.

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

The Python application keeps its call log and handling store on `app.state`, created in a lifespan function. httpx's `ASGITransport` calls the application without running the lifespan, so the fixture starts it with `asgi_lifespan.LifespanManager`, as the FastAPI "Async Tests" page describes:

```python
@pytest.fixture
async def app_client() -> AsyncIterator[httpx.AsyncClient]:
    async with LifespanManager(app) as manager:
        transport = httpx.ASGITransport(app=manager.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client
```

Every Python test gets a fresh application state. On Quarkus the application is shared by every class with the same configuration, so tests that write use their own idempotency keys and cargo, and assertions on the call log reset it first and read it once. Test order then doesn't matter.

A client library is also a consumer, and the same layer can use one. On Quarkus, the typesafe client built against `@TestHTTPResource("/graphql")` (which injects the address of the application under test) exercises the endpoint with the interface a client would write:

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

`ErrorOr` carries either the node or the errors reported at its path. Paging all six cargos shows the stacks differing for the reason DataLoader batching explains: SmallRye resolves a page's nodes in one bulk call, so the booking outage of `GHI345` reaches all six nodes and the Quarkus tests expect six errors. Strawberry fails only that key, and the Python test expects one. On Python, Strawberry's `GraphQLTestClient` wraps Starlette's `TestClient` and covers the same layer; Starlette's context manager runs the lifespan.

## Behavior the schema cannot show

Three properties are invisible in any response: how many calls a request made to the sources, that an over-budget document made none, and that a retried write happened once.

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

`FanOut` is the four-cargo page with an itinerary, legs, voyages, both locations and the derived delivery. A second check pins the keys: one `getCargos` call for the four tracking ids, one `getItineraries`, one `listEventsFor`, and the voyage and location calls, each carrying every key at once. A resolver rewritten to fetch one cargo at a time returns the same JSON and fails here, which is the regression this test exists to catch. The count is eight on Quarkus and six on Python, because each stack batches per field.

A cost refusal is tested the same way. Posting `OverBudget`, a page of 50 cargos with a page of 50 events each, must return `maximum query complexity exceeded 7651 > 1000`, no `data` and an empty log. To check a price rather than a verdict, each suite builds a copy of the application whose budget is one unit under it. Quarkus uses a test profile, which overrides configuration for the classes that name it. Python builds a second schema with a different budget.

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

The refusal states the price, so the message is the assertion. The idempotency test sends the registration of `DEF456` twice with one key and counts `handling.appendEvent` entries in the log: one write, and the same event id in both answers.

## Contract tests

Each test image writes the SDL its suite exported into a directory `verify.sh` mounted, and `assert_sdl_conforms` diffs each file against `contracts/schema/` in both directions. The same assertion then runs on the two live URLs, so the schema a test built and the schema a server serves are both held to the contract. The two exports aren't compared with each other; each must conform.

| Direction | A breaking line means | Expected |
|---|---|---|
| Live schema to contract | The stack exposes something the contract lacks, or is looser than it (`Cargo` where the contract says `Cargo!`) | Never |
| Contract to live schema | The stack doesn't serve something the contract declares | Only `Subscription`, which isn't served here |

A changed description on a type, field or argument that both sides declare also fails the check, because clients read descriptions in their tooling.

The breaking-change gate from schema evolution is a different check: it compares the contract with its previous version and runs on the contract alone. The suites can't see a contract change that both stacks follow, and the gate can't see a stack that drifts from the contract. Together they cover both.

## Client documents as tests

The client operations are the contract's first consumers, so they are tests too. `documents/` holds them one per file, with `fan-out.graphql` and `load/over-budget.graphql` beside them and the `Cargo.weight` fixture under `fixtures/`. The test and load images receive the directory through `build.additional_contexts`, so there is one copy, and `verify.sh` compares each file with the same-named operation in the client example's `operations.graphql`, after dropping comments and whitespace. If one example changes a document, the other fails.

Two checks run on the documents with `graphql-inspector`:

- `validate` applies the specification's validation rules against the canonical SDL. Every file in `documents/` passes, and the fixture that selects `Cargo.weight` fails with `Cannot query field weight on type Cargo`.
- `coverage` counts how many documents select each field. Over the four client documents it reports `Query.cargo` selected twice, `Query.cargos` once and `Query.voyage` not at all, which is what a team needs before it deprecates a field: who still asks for it, and which fields no client ever has.

Validation and execution catch different failures: a valid document can still return the wrong data, and a correct answer hasn't been checked against the contract.

## Load tests that assert correctness

A load run answers a question the other layers can't: do the properties hold when requests overlap? Loaders are per request, and a loader shared across requests passes every single-request test and puts keys from several requests into one batch only under concurrency.

Grafana k6 is an open source (AGPL-3.0) load tool, run unmodified as a command-line program, with JavaScript scripts. The image is `ubi10/ubi-minimal` with the static binary from the release tarball, checked against the SHA-256 pinned in the Containerfile and against the release's checksum file. The script reads the shared documents with `open()`, and each run defines one scenario:

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

A rate-based executor models traffic more closely but makes the request count depend on machine speed. These runs check invariants and don't measure capacity, so the exact executor fits. `handleSummary` writes the summary as one JSON line for `verify.sh`, and the image build runs `k6 inspect` so a syntax error fails the build and not the first run.

No threshold mentions time. Latency on a shared CI runner differs from job to job, so a latency assertion fails for reasons that aren't in the code. The summary prints the median and 95th percentile for the reader and nothing asserts them. Counts and invariants hold on any machine.

Four runs per stack, in this order, each starting from an empty source-call log:

| Run | Work | Checks and thresholds | Then `verify.sh` reads the log |
|---|---|---|---|
| `fanout` | 160 `FanOut` from 8 users | no `errors`, four edges, a transport status on each | 160 request ids; every request made 8 calls (Quarkus) or 6 (Python), exactly the expected keys |
| `cost` | 80 `FanOut` and 80 `OverBudget` at the same time, 4 users each | `OverBudget` has no `data` and one error with the stated price | 80 request ids: a refused request made no call; the other 80 made their own calls |
| `retry` | 40 registrations of one event, one idempotency key, 8 users | the same event id in every answer, no user errors | one `handling.appendEvent`; `ABC123` then reads `IN_PORT` |
| `mix` | 120 requests cycling `TrackCargo`, `TrackCargoBrief` and `ListCargos` | no errors; six edges and the per-stack outage on the list | 120 request ids in two shapes: 80 cargo reads and 40 pages |

The `cost` run starts two scenarios together. Accepted requests become bulk source calls under their own request ids, and refused ones stop at the cost check and add nothing to the log.

{% include excalidraw.html file="23-load-run" alt="Left, two blue boxes: four virtual users sending 80 FanOut requests, and four virtual users sending 80 OverBudget requests. Inside a band labelled server, quarkus or python, the FanOut arrow enters a cost check box reading cost 53, budget 1,000, then an amber arrow labelled runs leads to an execution box with batched resolvers, then down to a box of bulk source calls, booking getCargos and routing getItineraries, eight per request and six on Python. An amber arrow labelled logged leads to a dark box on the right, the source-call log grouped by request id, with 80 request ids, 8 or 6 calls each, and none from OverBudget. The OverBudget arrow enters a second cost check box reading cost 7,651, budget 1,000, then leads to a dark box labelled refused, error and no data. A dashed arrow from the refused box to the log is labelled no call. A footer says 160 requests went in, 80 request ids are in the log, and latency is printed and not asserted." caption="Figure 23.2: One load run. Accepted requests fan out into bulk source calls under their own request ids; refused requests stop at the cost check, and the log counts none of them." %}

The log is read once at the end of a run and grouped by request id, which makes concurrency checkable. `assert_calls_per_request` fails if any request made a different number of calls, and `assert_calls_same_per_request` fails if any request's set of `source.op:key` entries differs from the single-request set, which would show keys from one request landing in another's batch. Both stacks pass: loaders are per request, so concurrency changes the order of calls and not their content. Sequential replays of a registration never reach the check the store makes under its lock; only concurrent retries do, so the `retry` run is the test of that lock. It is the only write, so it runs before the `mix` run that reads its result.

## Where the tests run

The in-process suites run in a `test` stage of each Containerfile, placed before the runtime stage, which stays the default target and doesn't depend on it, so a normal image build neither compiles the tests nor installs the test tools. The Quarkus stage adds the test sources and the documents, resolves the deployment artifacts of the test extensions with `quarkus:go-offline`, and runs `mvn verify`:

```dockerfile
FROM build AS test
# quarkus:go-offline resolves the deployment artifacts of the test-scope
# extensions, which the production build never needs, so the test JVM finds
# every Quarkus artifact in the local repository when it starts.
RUN mvn -B $MAVEN_RETRY_OPTS quarkus:go-offline
COPY src/test ./src/test
COPY --from=documents . src/test/resources/documents/
# One plain unit test at build time puts Surefire's JUnit Platform provider in the local repository, so the test run needs no network.
RUN mvn -B $MAVEN_RETRY_OPTS test -Dtest=DeliveryDerivationTest -Dmaven.javadoc.skip=true && rm -rf target/surefire-reports
# umask 0 leaves the reports deletable by the user who mounted /out.
CMD umask 0 && exec mvn -B -o verify -Dmaven.javadoc.skip=true -Dsurefire.reports-dir=/out/surefire-reports -Dtracking.test.export-dir=/out
```

The Python stage installs the development group (`pytest`, `anyio`, `httpx`, `httpx2` and `asgi-lifespan`), which the production image leaves out with `--no-dev`:

```dockerfile
FROM build AS test
RUN uv sync --locked
COPY tests ./tests
COPY --from=documents . tests/documents/
ENV TRACKING_TEST_EXPORT_DIR=/out
# umask 0 leaves the reports deletable by the user who mounted /out.
CMD umask 0 && exec uv run --locked pytest -q --junitxml=/out/junit.xml
```

Both services sit behind a compose profile and run with `docker compose run`, with a scratch directory mounted at `/out`. Surefire writes one XML report per class and pytest writes one `junit.xml`. `verify.sh` reads the totals from the XML and asserts the exact count, 22 and 18, with no failures, errors or skips, so a deleted or skipped test can't pass unnoticed.

The containers run as UID 185, 1001 and root, so the images set `umask 0` and the user who mounted `/out` can delete the reports. `verify.sh` mounts its `mktemp` scratch directory with the `:z` label SELinux hosts need and removes it on exit.

Tests and builds run only in the pinned UBI images, never with the host's JDK, Maven, Python or uv, so a developer's machine and the CI runner execute the same thing. Quarkus Dev Services would start a database or broker for `@QuarkusTest` if an extension needed one; every source here is in memory.

> **🤖 Explore with your agent**
>
> "In `examples/23-testing`, add a resolver unit test for `BookingSource` failing on `Query.cargos`: assert the error `path`, `message` and `extensions.code` on the Quarkus side (`BookingFailureTest`) and the Python side (`UnavailableBooking`), then add a source-call assertion for the page that fails if a resolver fetches one cargo at a time. Put each assertion at the cheapest layer that can see it and assert no latency."
>
> Check: `verify.sh` asserts exact test counts, so raise 22 and 18 by the tests you added, run `bash examples/23-testing/verify.sh`, and confirm that making the resolver fetch per cargo fails the source-call assertion.

## Build, run, observe

Start the servers, create a report directory and run the Quarkus suite. The exit code is Maven's, and the report directory receives the XML and the exported schema.

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

Then the Python suite and one load run against Quarkus. k6's end-of-test summary is one JSON line; timings differ on every machine and the counts don't.

```bash
docker compose run --rm -T --build -v /tmp/ch23-python:/out:z python-test | tail -1
docker compose run --rm -T --build -e TARGET=http://quarkus:8080/graphql -e RUN=fanout -e STACK=quarkus \
  load run --quiet /scripts/tracking.js
```

```text
18 passed in 0.17s
{"run":"fanout","stack":"quarkus","iterations":160,"requests":160,"checks":{"rate":1,"passes":640,"fails":0},"http_req_failed":0,"latency_ms":{"med":214,"p95":234}}
```

Each suite's exported schema is `schema.graphql` in its directory, and Surefire's reports are in `/tmp/ch23-quarkus/surefire-reports/`. `verify.sh` asserts every row below.

| Check | Quarkus | Python |
|---|---|---|
| in-process suite | 22 tests, no failures, errors or skips | 18 tests, the same |
| exported schema | conforms to `contracts/schema/` | the same |
| `documents/` against the client example | the four operations, text for text | the same |
| `documents/*.graphql` validated | passes | the same |
| `fixtures/cargo-weight.graphql` validated | fails: `Cannot query field weight on type Cargo` | the same |
| coverage over the four documents | `Query.cargo` 2, `Query.cargos` 1, `Query.voyage` 0 | the same |
| `FanOut` | `VWX901`, `XYZ789`, `STU678`, `DEF456`; 8 calls | the same data; 6 calls |
| `OverBudget` | `maximum query complexity exceeded 7651 > 1000`, no `data`, 0 calls | the same, `data` null |
| `first: 51` | `BAD_USER_INPUT` | the same |
| `fanout` run | 160 request ids, 8 calls each | 160 request ids, 6 calls each |
| `cost` run | 80 request ids, 8 calls each | 80 request ids, 6 calls each |
| `retry` run | one `appendEvent` (`evt_10`); `ABC123` is `IN_PORT` | the same |
| `mix` run | 120 request ids: 80 cargo reads, 40 pages | the same |
| every run | 0 failed checks, 0 transport failures, the exact number of iterations | the same |
| live schema | conforms; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

Stop the stack when done:

```bash
docker compose down -v
```

`bash examples/23-testing/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold. Experiments:

- Select `Cargo.weight` in a document: `graphql-inspector validate` fails with `Cannot query field weight on type Cargo`.
- Rewrite a resolver to fetch one cargo at a time: the JSON is unchanged, and the source-call count assertions fail.
- Delete or skip a test: the exact 22 and 18 counts fail.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Hold the exported and the served schema, and the client documents, to the canonical SDL, so a field clients use can't vanish unnoticed. Treat the number of calls to the owners as a tested output, since a resolver that fetches one cargo at a time returns the same JSON at a larger bill. Judge a load run by counts that hold on any runner, never by latency.</p></div>

## For deeper coverage

- *Cloud Native Design Patterns*, Appendix O, "API Testing with Newman": a parallel automated API test gate built on Postman/Newman collections, worth comparing against these layered GraphQL suites.
- [Quarkus, Testing your application](https://quarkus.io/guides/getting-started-testing): `@QuarkusTest`, `@TestHTTPResource`, `@InjectMock`, and test profiles. The "SmallRye GraphQL Client" guide covers the typesafe client and `ErrorOr`.
- Strawberry's "Testing" guide covers `schema.execute` and the test client; FastAPI's "Testing" and "Async Tests" pages describe the `ASGITransport` and lifespan pattern.
- [GraphQL Inspector](https://the-guild.dev/graphql/inspector): the `validate`, `coverage`, and `diff` commands.
- [Grafana k6, Using k6](https://k6.io/docs/using-k6/): scenarios, checks, and thresholds.
