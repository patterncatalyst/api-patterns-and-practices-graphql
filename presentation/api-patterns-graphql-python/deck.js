// deck.js — "API Patterns & Practices: GraphQL — Python / Strawberry Implementation".
// The patterns of the concepts deck built in Python: Strawberry on FastAPI, managed with uv.
// Code on the slides is read from examples/*/python/** by snippet(). Figures come from the book's diagrams.
//
// Build:  bash presentation/_shared/build.sh presentation/api-patterns-graphql-python

"use strict";

const path = require("path");
const SHARED = path.resolve(__dirname, "../_shared");
process.env.DECK_ASSETS = `${SHARED}/assets`;
process.env.DECK_PNG = `${SHARED}/png`;

const H = require(`${SHARED}/deck-helpers.js`);
const {
  COLOR, FONT, W, ASSETS,
  newDeck, addFooter, addContentTitle, addBullets, addTwoColBullets,
  addCaption, addSnippetSlide, addDiagramSlide,
  addSectionDivider, defineSectionMaster, writeDeck, addNotes,
} = H;
const { snippet } = require(`${SHARED}/snippet.js`);

// Code on the slides: each entry names a source file and the line ranges taken from it.
// snippet() reads the lines at build time and inserts an elision line between ranges.
const SNIP = {
  pyproject_deps: { size: 11, snip: snippet("examples/27-final-project/python/pyproject.toml", [[5, 17]]) }, 
  main_router: { size: 11, snip: snippet("examples/27-final-project/python/app/main.py", [[60, 80]]) }, 
  types_node_location: { size: 10, snip: snippet("examples/03-sdl-type-system/python/app/model.py", [[123, 144]]) }, 
  leg_nullability: { size: 10, snip: snippet("examples/04-nullability/python/app/graph.py", [[26, 48]]) }, 
  schema_export_test: { size: 11, snip: snippet("examples/23-testing/python/tests/test_schema.py", [[2, 17]]) }, 
  leg_async: { size: 10, snip: snippet("examples/06-execution-model/python/app/model.py", [[177, 202]]) }, 
  get_context: { size: 11, snip: snippet("examples/27-final-project/python/app/deps.py", [[65, 69], [72, 78], [89, 90]]) }, 
  root_resolvers: { size: 10, snip: snippet("examples/27-final-project/python/app/schema.py", [[67, 91]]) }, 
  input_payload: { size: 11, snip: snippet("examples/27-final-project/python/app/model.py", [[509, 519], [531, 532], [539, 544]]) }, 
  register: { size: 10, snip: snippet("examples/27-final-project/python/app/registration.py", [[50, 64], [66, 68], [85, 87]]) }, 
  errors: { size: 10, snip: snippet("examples/27-final-project/python/app/errors.py", [[20, 29], [32, 35], [57, 57], [65, 65]]) }, 
  node_dispatch: { size: 11, snip: snippet("examples/27-final-project/python/app/schema.py", [[176, 189], [198, 199]]) }, 
  deprecation: { size: 11, snip: snippet("examples/27-final-project/python/app/model.py", [[215, 226]]) }, 
  connection: { size: 10, snip: snippet("examples/27-final-project/python/app/model.py", [[426, 450]]) }, 
  cursor_codec: { size: 10, snip: snippet("examples/27-final-project/python/app/pagination.py", [[74, 91], [134, 136]]) }, 
  loaders: { size: 11, snip: snippet("examples/27-final-project/python/app/loaders.py", [[42, 49], [61, 62], [76, 82]]) }, 
  limit_extensions: { size: 11, snip: snippet("examples/27-final-project/python/app/schema.py", [[292, 299]]) }, 
  cost_walker: { size: 10, snip: snippet("examples/27-final-project/python/app/limits.py", [[214, 226], [228, 231], [235, 239]]) }, 
  persisted_resolve: { size: 10, snip: snippet("examples/15-persisted-queries/python/app/persisted.py", [[84, 108]]) }, 
  cache_policy: { size: 10, snip: snippet("examples/16-caching/python/app/cache_policy.py", [[29, 53]]) }, 
  uvicorn_tls: { size: 11, snip: snippet("examples/17-transport-security/python/Containerfile", [[52, 53], [55, 55], [60, 61]]) }, 
  introspection: { size: 11, snip: snippet("examples/27-final-project/python/app/schema.py", [[300, 312]]) }, 
  auth: { size: 10, snip: snippet("examples/27-final-project/python/app/auth.py", [[42, 45], [50, 50], [60, 70], [81, 85]]) }, 
  permissions: { size: 11, snip: snippet("examples/27-final-project/python/app/permissions.py", [[26, 40]]) }, 
  telemetry: { size: 10, snip: snippet("examples/27-final-project/python/app/telemetry.py", [[40, 45], [75, 75], [78, 82], [99, 104]]) }, 
  federation_entity: { size: 10, snip: snippet("examples/20-federation/python/cargo/app/model.py", [[226, 240], [242, 245], [252, 252]]) }, 
  subscription: { size: 10, snip: snippet("examples/27-final-project/python/app/schema.py", [[239, 261]]) }, 
  sse_feed: { size: 11, snip: snippet("examples/27-final-project/python/app/events.py", [[71, 80]]) }, 
  gql_client: { size: 10, snip: snippet("examples/22-client-integration/clients/python/track.py", [[24, 34], [60, 60], [69, 77]]) }, 
  fixture: { size: 11, snip: snippet("examples/23-testing/python/tests/conftest.py", [[31, 39]]) }, 
  operation_test: { size: 11, snip: snippet("examples/23-testing/python/tests/test_operations.py", [[11, 11], [61, 73]]) }, 
  containerfile: { size: 11, snip: snippet("examples/27-final-project/python/Containerfile", [[16, 16], [26, 32], [35, 35], [39, 40], [54, 55], [62, 63]]) }, 
  settings: { size: 11, snip: snippet("examples/27-final-project/python/app/settings.py", [[15, 29]]) }, 
  helm_values: { size: 10, snip: snippet("examples/27-final-project/helm/values.yaml", [[63, 69], [74, 77], [82, 88], [94, 95]]) }, 
  app_pyproject: { size: 10, snip: snippet("examples/27-final-project/python/pyproject.toml", [[1, 24]]) }, 
  app_main: { size: 10, snip: snippet("examples/27-final-project/python/app/main.py", [[29, 30], [47, 61], [92, 97]]) }, 
  app_access: { size: 10, snip: snippet("examples/27-final-project/python/app/access.py", [[10, 19]]) }, 
};

const OUT = path.resolve(__dirname, "api-patterns-graphql-python.pptx");
const LANG = "python · Strawberry";

const pres = newDeck();
defineSectionMaster(pres);
pres.title = "API Patterns & Practices: GraphQL — Python / Strawberry Implementation";
let pageNum = 0;

function S() { const s = pres.addSlide(); pageNum += 1; addFooter(s, pageNum); return s; }
function divider(code, title, subtitle, notes) {
  const s = pres.addSlide({ masterName: "SECTION" }); pageNum += 1;
  addSectionDivider(s, code, title, subtitle, { onMaster: true }); addNotes(s, notes);
}
// A code slide: the first line of the box names the source file; the lines come from snippets.js.
function codeSlide(eyebrow, title, lang, key, caption, notes) {
  const sn = SNIP[key];
  if (!sn) throw new Error(`no snippet ${key}`);
  const s = S();
  addSnippetSlide(s, eyebrow, title, lang, sn.snip, caption, { fontSize: sn.size });
  addNotes(s, notes);
}
function figureSlide(eyebrow, title, figure, caption, notes) {
  const s = S();
  addDiagramSlide(s, eyebrow, title, figure.file, caption);
  addNotes(s, notes);
}

/* ======================= COVER ======================= */
{
  const s = pres.addSlide();
  pageNum += 1;
  s.background = { color: COLOR.white };
  try { s.addImage({ path: `${ASSETS}/cover-panel.png`, x: 0, y: 0, w: W, h: 7.5 }); } catch (e) {}
  s.addText("API PATTERNS & PRACTICES · GRAPHQL · PYTHON", { x: 6.00, y: 1.82, w: 6.90, h: 0.34,
    fontFace: FONT.title, fontSize: 13, bold: true, color: COLOR.red, charSpacing: 3, align: "left", valign: "middle" });
  s.addText([{ text: "The Python /", options: { breakLine: true } }, { text: "Strawberry build." }], {
    x: 5.95, y: 2.28, w: 6.95, h: 2.00, fontFace: FONT.title, fontSize: 48, bold: true, color: COLOR.ink, align: "left", valign: "top" });
  s.addText("Every GraphQL pattern from the concepts deck, built with Strawberry on FastAPI and managed with uv. The running example is the shipping tracking view, against one canonical SDL shared with the Quarkus stack.", {
    x: 6.00, y: 4.22, w: 6.80, h: 1.45, fontFace: FONT.body, fontSize: 16, italic: true, color: COLOR.caption, align: "left", valign: "top" });
  s.addText([
    { text: "Robert Sedor", options: { bold: true, color: COLOR.ink, breakLine: true } },
    { text: "Principal Chief Architect, Application Development", options: { color: COLOR.caption } },
  ], { x: 6.00, y: 5.75, w: 6.70, h: 0.80, fontFace: FONT.body, fontSize: 15, align: "left", valign: "top" });
  try { s.addImage({ path: `${ASSETS}/logo-candidate-2.png`, x: 11.10, y: 6.80, w: 1.55, h: 0.37 }); } catch (e) {}
  addNotes(s, "Welcome to the Python and Strawberry deck in the API Patterns and Practices series on GraphQL. The concepts deck set out the patterns and the reasons for them without tying them to a stack. The Quarkus deck builds them with SmallRye GraphQL on the JVM. This deck builds the same patterns in Python, against the same canonical schema and the same shipping tracking view. All the code on the slides comes from the runnable examples under examples, in the python directories, and each code slide names its source file in its first line. Strawberry is a code-first library: the schema is built from decorated Python classes and type annotations, and it runs on graphql-core, the Python port of the reference implementation. FastAPI supplies the HTTP layer, dependency injection and lifespan handling, and uv manages the environment. I am Robert Sedor. The deck moves through twelve sections, from the first schema to a Helm release, and an appendix holds the full listings to keep open in another window.");
}

/* ======================= AGENDA ======================= */
{
  const s = S();
  addContentTitle(s, "OVERVIEW", "Agenda");
  addTwoColBullets(s,
    [
      "Setup and the code-first schema",
      "Nullability and the contract gate",
      "Execution and resolvers",
      "Mutations and errors",
      "Schema design and evolution",
      "Pagination and batching",
    ],
    [
      "Cost, persisted documents, caching",
      "Transport security and access control",
      "Observability and federation",
      "Subscriptions and clients",
      "Testing and debugging",
      "Running it",
    ],
    { fontSize: 17 });
  addNotes(s, "The agenda follows the pattern order of the concepts deck and the Quarkus deck, so the three decks map section to section. We start with the project setup and the way Strawberry builds a schema from classes, then look at how Python type hints decide nullability and how an exported schema is held against the canonical SDL. Execution and resolvers covers async fields and the per-request context. Mutations and errors covers inputs, payloads and the error allowlist. Schema design and evolution covers global identifiers and deprecation. Pagination and batching covers cursor connections and DataLoaders. The cost section covers the admission limits, persisted documents and caching. Security covers TLS, token validation and permissions. Observability and federation cover spans, metrics and entities. Subscriptions use async generators. Testing and debugging covers the in-process test suite, and the Running it section runs the image in a Compose tier and a Helm release. The appendix holds full listings.");
}

/* ======================= SERIES MAP ======================= */
{
  const s = S();
  addContentTitle(s, "SERIES MAP", "Where this deck sits");
  addBullets(s, [
    "The concepts deck covers what GraphQL is and why each pattern exists, independent of any stack.",
    "The Quarkus deck builds each pattern with SmallRye GraphQL on Quarkus 3.40.1 and JDK 25, code-first.",
    "This deck builds them in Python: Strawberry 0.335.0 on FastAPI 0.143.2, Python 3.14 or newer, managed with uv.",
    "The examples share one canonical SDL under contracts/schema, and each stack's exported schema is diffed against it in CI.",
    "API Patterns & Practices: REST, gRPC, this GraphQL title, and a forthcoming WebSockets title.",
  ], { fontSize: 18 });
  addCaption(s, "Same domain, same contract, same chapter order in all three decks.");
  addNotes(s, "The concepts deck carries the reasoning for every pattern and does not depend on a language. The Quarkus deck and this one are the two implementations, and they are built to the same section list so that a listener can compare them one to one. The versions listed come from the final project's pyproject file: Strawberry 0.335.0, FastAPI 0.143.2, and a Python requirement of 3.14 or newer. The part that ties the two stacks together is the canonical schema. It lives in the contracts directory as SDL files, both stacks stay code-first, and a conformance check exports each stack's schema and diffs it against the canonical SDL in both directions. A change to a type, a nullability or a description in either stack fails that check until the contract and the code agree again. Chapter 5 builds that gate, and the nullability section of this deck shows how it looks on the Python side.");
}

/* ======================= 01 · SETUP AND THE CODE-FIRST SCHEMA ======================= */
divider("01", "Setup and the code-first schema",
  "One canonical SDL; the schema is built from Python classes.",
  "The setup section covers the working environment and the way Strawberry turns decorated classes into a schema. The lab runs as a Compose project with both stacks side by side, which makes the comparison with the Quarkus build direct. The Python side is a uv project with pinned dependencies, a FastAPI application and a Strawberry schema. Chapters 0 and 3 introduce the lab and the type system, and the Python form of each follows.");

figureSlide("SETUP", "The lab topology", { file: "00-lab-topology" },
  "Figure 0.1 — The lab: verify.sh drives both stacks and diffs each live schema with the canonical SDL.",
  "The figure shows the Compose lab that every example reuses. On the left, verify.sh sources a shared lib.sh and sends POST requests to both services. In the middle, the Compose project holds the Quarkus service on host port 8080 and the Python service on 8081, with an optional otel-lgtm container that receives telemetry when the observability file is added. The Python service serves the GraphQL endpoint at /graphql and a health route. On the right, graphql-inspector introspects both services and diffs each result with the canonical SDL in contracts/schema/shipping, in both directions. The point of the topology is that the two stacks answer the same requests and are held to the same contract by a script, so any difference between them is visible as a failed check. Chapter 0 builds the lab, and the later chapters add one capability at a time to the same shape.");

codeSlide("SETUP", "Pinned dependencies", "toml · uv project", "pyproject_deps",
  "Strawberry and FastAPI are pinned exactly, on Python 3.14 or newer.",
  "The listing shows the dependency block of the final project's pyproject file. The project requires Python 3.14 or newer and pins every package to an exact version: FastAPI, uvicorn with its standard extras, Strawberry, pydantic-settings for environment-based configuration, PyJWT with the crypto extra for token validation, and the OpenTelemetry API, distro, OTLP exporter and FastAPI instrumentation. Exact pins keep a build reproducible, and uv records the resolved set in uv.lock. The Containerfile later runs uv sync with the locked flag, which fails the build when the lock file and the project file disagree. Early chapters use a smaller list: Chapter 5 adds the strawberry-graphql cli extra so that the strawberry export-schema command is available, and each later chapter adds only what it needs. Chapter 0 covers the toolchain, and Chapter 27 shows the complete set.");

codeSlide("SETUP", "Router and context", LANG, "main_router",
  "GraphQLRouter mounts the schema at /graphql; context_getter builds a context for each request.",
  "The listing shows how the schema meets FastAPI. The application object is created with a lifespan function, and GraphQLRouter is included under the /graphql prefix. The router takes the schema, a context_getter that builds the per-request context, and a few options: the IDE is off, GET queries are allowed only on the internal instance, and three subscription protocols are enabled. One path therefore serves queries and mutations over POST and subscriptions over WebSocket or server-sent events. GraphQLRouter is an ordinary FastAPI router, so dependencies, middleware and lifespans work as they do for any other route in the application. The first examples use the minimal form, GraphQLRouter(schema) with a health route beside it, and the final project adds the context getter and the subscription protocols. Chapter 3 introduces the minimal form, and Chapter 27 assembles the complete application.");

codeSlide("SETUP", "Types as classes", LANG, "types_node_location",
  "Fields are non-null unless the annotation says | None; snake_case names become camelCase on the wire.",
  "The listing shows the Node interface and the Location type from the Chapter 3 example. strawberry.interface declares the shared contract, and strawberry.type declares each object type. Every field is a class attribute with a Python annotation, and a description argument supplies the text that appears in the schema. The names follow Python style and are converted for the wire, so un_locode becomes unLocode. The scalar types UnLocode and TrackingId are NewType strings registered through a scalar map on the schema. Each type, field, nullability and description mirrors the canonical SDL, and the conformance script checks that against live introspection. This is the code-first approach: the Python class is the source that developers edit, and the canonical SDL is the yardstick that reviewers read. Chapter 3 covers the type system, including interfaces, enums and custom scalars.");

/* ======================= 02 · NULLABILITY AND THE CONTRACT GATE ======================= */
divider("02", "Nullability and the contract gate",
  "Python type hints decide where a null can land.",
  "A field's wrapper type is a promise to the client, and the failure of a resolver has to land somewhere when the promise cannot be kept. The section covers how Strawberry spells nullability, how a null climbs through non-null parents, and how an export of the schema is held against the canonical SDL. Chapters 4 and 5 cover the ideas, and the examples there include seeded faults so that each behavior can be asserted.");

codeSlide("NULLABILITY", "Nullable by annotation", LANG, "leg_nullability",
  "Voyage | None is a fuse: a missing load location climbs to the nearest nullable parent.",
  "The listing shows the Leg type from the Chapter 4 example. Strawberry follows Python type hints: a bare annotation is non-null, and a union with None is nullable. voyage returns Voyage | None, so it becomes the nullable field Voyage, while load_location returns Location, which becomes Location!. The source returns None for a code it does not know, and because the field is non-null, graphql-core records an execution error and moves the null to the nearest parent that can hold it. That path runs from the leg to the legs list to Itinerary, where Cargo.itinerary is nullable and the climb stops. The error path still names loadLocation, so an operator finds the failing resolver. The usual mistake on this stack is a forgotten | None, which makes a field stricter than the contract. Chapter 4 walks the null up the tree and explains where the fuses belong.");

figureSlide("CONTRACT GATE", "Two-direction diff", { file: "05-two-direction-diff" },
  "Figure 5.2 — Each seeded drift is reported by one direction of the diff.",
  "The figure sorts five seeded drifts by the direction of the diff that reports them. Each stack exports its schema as SDL, and graphql-inspector compares the export with the canonical SDL twice. Live to canonical treats the stack as the old schema, so an extra field or a tightened output shows up as a breaking change. Canonical to live treats the contract as the old schema, so a loosened type or a missing enum value shows up. A tightened output is the case that needs both directions: the tool classes it as safe for clients, but it removes the nullable fuse from Chapter 4, so only the first direction reports it. Whole types, output fields or roots may be absent from a stack that serves only a slice of the schema, and only the second direction allows that. Chapter 5 builds the gate, and Chapter 11 reuses it for evolution.");

codeSlide("CONTRACT GATE", "Schema export test", "python · pytest", "schema_export_test",
  "schema.as_str() prints the SDL Strawberry builds, with no server and no container.",
  "The listing is the schema test from the Chapter 23 suite. Strawberry builds its schema as a plain object, so schema.as_str() returns the SDL without starting a server. The test asserts that the Cargo type implements Node, that the TrackingId scalar exists and that the registration input type is present, then writes the text to a report directory. The verify script later diffs that file against the canonical SDL. The command line offers the same export for the running image: strawberry export-schema with the module path app.schema:schema. Both routes print the same text, which is what the conformance gate compares. Because the test needs no network, it runs in every build in a few milliseconds and catches a field or type that disappears. It does not replace the gate, which compares two schemas and not two strings. Chapter 5 sketches this test, and Chapter 23 builds the full suite.");

/* ======================= 03 · EXECUTION AND RESOLVERS ======================= */
divider("03", "Execution and resolvers",
  "Async fields, a context per request and typed root resolvers.",
  "The section covers how a request becomes resolver calls. The engine collects fields, runs sibling fields together when their resolvers yield control, and hands every resolver the same context object. In Strawberry the resolver idiom is an async def method that awaits a source, and the context comes from a FastAPI dependency. Chapters 6 and 7 cover the execution model and the anatomy of a resolver.");

figureSlide("EXECUTION", "Sibling resolvers", { file: "06-parallel-siblings" },
  "Figure 6.3 — Sibling resolvers overlap in time when each one waits on its source without holding a thread.",
  "The figure plots the source-call log of one request across four lanes. The booking call runs first, because the other fields need the cargo. The routing and delivery calls start together once it returns, and the two location calls start together when those finish. The total time follows the depth of the tree, three levels of 250 milliseconds, and not the number of calls. On the Python stack the chapter measures the same shape. Overlap depends on the resolvers giving control back while they wait: an async def resolver that awaits its source lets graphql-core start its siblings, while a plain def resolver that blocks would run one after the other on the event loop and hold up every other request. The specification only permits parallel execution of siblings, so the example measures it from the call log. Chapter 6 covers the measurement and the serial execution of top-level mutation fields.");

codeSlide("EXECUTION", "Async field resolvers", LANG, "leg_async",
  "Each resolver awaits a source through info.context, so sibling fields can start together.",
  "The listing shows the Leg type from the Chapter 6 example. The three keys the routing service returns are held as strawberry.Private fields, which keeps them out of the schema. The three resolvers turn those keys into the objects the contract promises. Each one is an async def method, takes the parent value as self and receives the request's context through info, annotated as Info[TrackingContext] so that editors and type checkers know what info.context holds. The method awaits a source and returns the result, and graphql-core awaits the coroutines of sibling fields together. Nullability comes from the annotation: voyage may be None, while the two locations may not. The parent value is whatever the previous resolver returned, which is why no resolver below the cargo receives a tracking id as an argument. Chapter 6 follows a request through these resolvers, and Chapter 7 covers resolver anatomy.");

codeSlide("EXECUTION", "Context per request", LANG, "get_context",
  "get_context builds one TrackingContext, and one request id, for every resolver of the request.",
  "The listing is the context getter that the router calls once per request, or once per connection on a WebSocket. FastAPI resolves the getter's own dependencies first, so the process-wide call log, the handling store and the caller's identity arrive through Depends. The function creates a uuid4 request id and binds each of the five sources to it, which means every source call of one operation carries the same id. It also builds the request's DataLoaders over those sources, and passes a factory so that a subscription can renew them for each event. Everything reaches resolvers as info.context. Because the context belongs to the request, nothing in it is shared between requests, including the loader caches. Chapter 6 uses the request id to prove which calls belong together, and Chapter 7 covers the other uses of the context.");

codeSlide("EXECUTION", "Root fields and arguments", LANG, "root_resolvers",
  "strawberry.argument names and describes an argument; the Annotated type carries the GraphQL type.",
  "The listing shows two root fields of the Query type. Each is an async def method decorated with strawberry.field and a description. Arguments are declared with typing.Annotated, which attaches a strawberry.argument to the Python type. The argument name is given explicitly, so the Python parameter un_locode is exposed as unLocode, and the description appears in the schema and in IDE tooltips. The return annotation Location | None makes the field nullable, which matches the contract: an unknown code is absence, and absence is null with no error. The resolver body is one line that awaits a source from the context. Variables, defaults, aliases, fragments and the include and skip directives are handled by the engine before the resolver runs, so the resolver sees plain Python values. Chapter 7 covers each of these in turn.");

/* ======================= 04 · MUTATIONS AND ERRORS ======================= */
divider("04", "Mutations and errors",
  "Inputs, payloads and errors a client can act on.",
  "A mutation changes state, so its failures need more structure than a query's. The section covers the input and payload types of registerHandlingEvent, the validation flow that returns domain failures as data, the idempotency key that makes retries safe, and the allowlist that decides which exceptions reach a client. Chapters 8 and 9 cover the design, and the final project uses the same files.");

codeSlide("MUTATIONS", "Input and payload", LANG, "input_payload",
  "strawberry.Maybe separates an absent field from a null one; domain failures return as userErrors.",
  "The listing shows the input type and the payload type of registerHandlingEvent. Required fields use plain annotations. Optional fields use strawberry.Maybe, which keeps three states apart: an absent field arrives as None, and a sent value arrives wrapped in Some, so the resolver can tell an omitted voyage number from an explicit null. The schema prints neither a default nor an equals-null for such a field. The payload carries the recorded event, the recomputed cargo and a list of userErrors. Domain validation failures are data in that list, with a stable code and the path of the input field, while the top-level errors array stays reserved for execution failures. A client therefore reads one place for what it can fix and another for what went wrong in the service. Chapter 8 covers mutation design, and Chapter 9 draws the line between the two kinds of error.");

codeSlide("MUTATIONS", "The register resolver", LANG, "register",
  "Validation collects every failure before a write; the excerpt shows the replay lookup, not the first write.",
  "The listing is the resolver behind registerHandlingEvent, in excerpt. It first unwraps the Maybe fields, then loads the cargo, the location and the voyage together with asyncio.gather, because the three lookups are independent. A validation function collects every domain failure, in a fixed order, and returns them in the payload with no write. When the input is valid and carries an idempotency key, the resolver looks the key up before appending, so a repeated request returns the event the first request recorded. The store makes that check and the append one step under an asyncio lock, which means two requests with the same key cannot both write. The mutation field is declared in the schema with permission classes for authentication and the operator role. Top-level mutation fields run one after another, in the order written, which Chapter 6 introduces and Chapter 8 asserts from the call log.");

codeSlide("ERRORS", "Exposed errors", LANG, "errors",
  "Only an ExposedError reaches a client with its message and a stable code; MaskErrors hides the rest.",
  "The listing is the error contract of the service. ExposedError is a base exception whose subclasses carry a stable code in extensions: SourceUnavailable uses SERVICE_UNAVAILABLE, and the same file defines BAD_USER_INPUT, UNAUTHENTICATED and FORBIDDEN. The should_mask function is the predicate handed to Strawberry's MaskErrors extension. An error with no original exception came from the engine itself, such as a parse or validation failure, and keeps its message. An error whose original exception is not an ExposedError is an unexpected failure, and the client receives only a generic message. The result is an allowlist: a resolver that wants a client to read its failure raises an ExposedError subclass, and everything else is masked while the full detail goes to the log. Chapter 9 builds the taxonomy and explains why codes, not messages, are the contract.");

figureSlide("ERRORS", "Error masking", { file: "09-error-masking" },
  "Figure 9.3 — Masking is an allowlist: the client sees what the service listed, and the log sees everything.",
  "The figure follows one failure from a source to the client. A source raises an exception, the resolver does not catch it, and the engine builds an error that holds the path, the message and the original exception. The error then meets the allowlist. On Python that is the should_mask predicate passed to the MaskErrors extension. An exception on the list reaches the client with its message and a code such as SERVICE_UNAVAILABLE. Anything else reaches the client as Internal server error, with no detail and no class name. A dashed arrow shows that the engine always logs the full error, with the stack and the time, so an operator keeps the detail the client does not receive. Chapter 24 adds a trace id to every execution error so that a client can quote it and an operator can find the log line. Chapter 9 covers the design in detail.");

/* ======================= 05 · SCHEMA DESIGN AND EVOLUTION ======================= */
divider("05", "Schema design and evolution",
  "Global identifiers, and changes made without version numbers.",
  "A GraphQL schema is shared by every client, so its shape has to stay readable and its changes have to be safe. The section covers the Node interface and the node root field, which give every object a global identifier, and the deprecation path that retires a field without a version number. Chapters 10 and 11 cover the design patterns and the evolution rules, and both rely on the contract gate.");

codeSlide("SCHEMA DESIGN", "Node dispatch", LANG, "node_dispatch",
  "A global id carries its type prefix, so one root field can fetch any object.",
  "The listing is the dispatch behind Query.node. A global identifier is a prefix, an underscore and a key: cargo_ABC123, loc_NLRTM, voy_V100S, evt_3. The function splits the id and matches on the prefix, then calls the source that owns that kind of object. An unknown prefix, a bare prefix or an empty key returns None, which is a null with no error. Each lookup is one source call, and the nodes field next to it takes a list of ids and runs the lookups together through the request's loaders, so ids of one type collapse into one bulk call. The match statement is the Python 3.10 idiom for this kind of dispatch. The Node interface from the setup section is what makes the return type Node | None valid. Chapter 10 covers global identification and the demand-oriented design that goes with it.");

codeSlide("EVOLUTION", "Deprecating a field", LANG, "deprecation",
  "deprecation_reason marks the old field; its replacement ships beside it.",
  "The listing shows the Itinerary type after a rename. The replacement, finalArrivalTime, is added first. The old field, finalArrivalDate, stays in the schema with a deprecation_reason that names its replacement. A deprecated field still executes, so existing clients keep working, while tools that read the schema flag it and hide it from default introspection. Removing the field is a separate step that waits for evidence. The service counts requests that select a deprecated field, by field coordinate and client name, and a count that stays at zero for a release cycle says the field can go. The breaking-change gate then agrees to the removal. Nothing in this cycle needs a version number, because clients state exactly which fields they read. Chapter 11 covers safe, dangerous and breaking changes, and Chapter 19 covers the usage counter.");

figureSlide("EVOLUTION", "Deprecation lifecycle", { file: "11-deprecation-lifecycle" },
  "Figure 11.2 — Add the replacement, deprecate, observe usage, then remove with a recorded sign-off.",
  "The figure shows the four steps of retiring a field. First the replacement is added. Second the old field is deprecated with a reason. Third the service observes usage through operation telemetry, and the schema does not change. Fourth the field is removed, which the gate reports as a breaking change: it exits with failure by default, and with a warning when the sign-off rule is set, so the removal is a recorded decision and not a side effect. The clients row below shows what each step costs the people who depend on the schema. Existing clients are unchanged in the first step, both fields execute in the second, clients migrate on their own schedule in the third, and only a client that still selects the old field fails validation in the last. Chapter 11 runs each step against the gate and prints its output.");

/* ======================= 06 · PAGINATION AND BATCHING ======================= */
divider("06", "Pagination and batching",
  "Cursor connections and one bulk call per level.",
  "The section covers two patterns that decide how a list scales. Connections page a list with opaque cursors and carry their own failure boundary, and DataLoaders collapse the per-item reads under a list into one bulk call per level. Chapters 12 and 13 cover the patterns, and the Python examples use Strawberry's own DataLoader class and the asyncio event loop for the tick.");

codeSlide("PAGINATION", "Connection types", LANG, "connection",
  "CargoEdge.node is nullable, so one failed item nulls its edge and not the whole page.",
  "The listing shows the edge and connection types of the cargos field. An edge holds the tracking id as a private field and a cursor. Its node resolver loads the cargo through the request's loader when a query selects it, so an edge whose cargo cannot be loaded fails alone. The node field is nullable, because a strict non-null node would pass a single failure up through the edge, the list and the connection to the root, and a page of fifty cargos would be lost to one error. This is the fourth nullable fuse of the tracking schema. The connection itself carries the edges, the page info and a total count that may be null when counting is too expensive. A client that reads the page has to check node for null on every edge, which is the price of a page that survives. Chapter 4 introduced the fuse, and Chapter 12 builds the connection.");

codeSlide("PAGINATION", "Cursor codec", LANG, "cursor_codec",
  "Cursors are opaque base64url strings the server decodes strictly, and paging seeks on the sort key.",
  "The listing shows the argument rules and the cursor encoder. parse_page validates in a fixed order: the range of each size, then the combination of first and last, then each cursor. A size outside zero to fifty, a combination of first and last, or a cursor the codec did not issue raises BadUserInput, which reaches the client with the code BAD_USER_INPUT. With neither size the page is the first ten. The encoder joins a prefix, a version and the sort-key fields, then encodes the result as base64url without padding. The prefix names the connection, so a cursor from one connection is rejected by another, and the version lets the format change without misreading old cursors. A cursor is opaque to the client and fully known to the server. Paging seeks on the sort key and never counts rows from the start, so an insert cannot shift a page. Chapter 12 covers cursors and the offset comparison.");

codeSlide("BATCHING", "Per-request DataLoaders", LANG, "loaders",
  "One DataLoader per kind of key, built for each request, turns a level of loads into one bulk call.",
  "The listing shows the loaders of the final project. Each loader is built from a function that receives a list of keys and returns a list of values in the same order, by calling one bulk operation on the owning source. Five loaders cover the five kinds of key: cargo, itinerary, events, voyage and location. Resolvers that need the same thing share a loader, so loadLocation and unloadLocation both use the location loader. The loaders are created in the context getter for each request, and the cache that makes a repeated key free lives inside each loader, so it lives and dies with the request. A cache that outlived a request would serve stale data to the next one, since the handling store changes between requests. Strawberry's DataLoader collects the keys of every load call made before the event loop's next turn. Chapter 13 covers the contract and the tick.");

figureSlide("BATCHING", "The DataLoader tick", { file: "13-dataloader-tick" },
  "Figure 13.3 — Loads queue during a tick, one bulk call follows, and the next level starts when it returns.",
  "The figure is drawn from the source-call log of one request for four cargos on the Python stack. The thin ticks are load calls queued before each dispatch. The bars are the bulk calls, and each one starts as the call that supplies its keys ends. The page is one list call, the four cargos load in one call, the itineraries and events load together in the next level, and the voyages and locations load together in the last. Without batching the same query makes twenty-nine source calls, and with it the count follows the number of fields in the selection and not the number of cargos. On Strawberry the tick is the next turn of the event loop: the first load of a new batch schedules the dispatch, and every resolver that runs before that turn adds its key to the same batch. Chapter 13 covers the tick and the per-field comparison.");

/* ======================= 07 · COST, PERSISTED DOCUMENTS, CACHING ======================= */
divider("07", "Cost, persisted documents, caching",
  "Admission control, hashed documents and Cache-Control.",
  "Three patterns decide how much work a request may cause and how often it is repeated. Limits refuse a request before a resolver runs, persisted documents replace query text with a hash, and caching keeps an answer at the layer where it is cheapest to keep. On Python all three are Strawberry schema extensions or small pieces of FastAPI. Chapters 14, 15 and 16 cover the patterns.");

figureSlide("QUERY COST", "Limit pipeline", { file: "14-limit-pipeline" },
  "Figure 14.2 — Each limit fires at the earliest stage that has the information it needs.",
  "The figure places each limit at a stage of a request: the HTTP body, parse, validate, before execute, resolve and the sources. The Strawberry lane is the second one. A batch array is refused with a 400 because batching is not configured. The token limiter works at parse time with a limit of 5,000 tokens. The depth rule and the alias rule are validation rules, with limits of 14 and 20. The cost budget of 1,000 applies before execution, because it needs the variable values. The page cap of zero to fifty is enforced in the resolver, and it still fires before the first source call. Every refusal ends before the sources are reached, and the two lanes refuse the same documents, so a client cannot tell the stacks apart by what is accepted. The depth numbers differ because the engines count a root field differently. Chapter 14 explains the counts.");

codeSlide("QUERY COST", "Extension order", LANG, "limit_extensions",
  "Strawberry builds each extension per request; the list order follows the stages a request meets.",
  "The listing is the extension list of the final schema, without the telemetry entries. TraceIdExtension comes first so that its exit runs last, after MaskErrors has rebuilt the masked errors, and every error then carries a trace id. MaskErrors applies the error allowlist. MaxTokensLimiter bounds the size of the document at parse time. The depth and alias limiters are validation rules wrapped in AddValidationRules. QueryCostLimiter runs in on_execute, after validation and before the first resolver. Each entry is a class or a functools.partial factory, because Strawberry builds one extension per request, so no state is shared between requests. Batching of operations stays off by default, which means an array body is refused with a 400. The numbers 14, 20 and 1,000 are the example's choices and come from settings and constants. Chapter 14 explains each limit and the reason for its position.");

codeSlide("QUERY COST", "Cost model", LANG, "cost_walker",
  "cost(field) = 1 + m × the cost of its children, where m is the page size on a paged field.",
  "The listing is the walker that prices a selection. The rule is applied bottom-up: a meta field such as __typename costs nothing, and any other field costs one plus a multiplier times the sum of its children. The multiplier is the page size on cargos and handlingHistory, taken from first, else last, else the default of ten. On nodes it is the number of ids, which the excerpt omits, and on everything else it is one. A negative page size counts as zero, so a value the resolver will refuse cannot lower the price of its neighbor. The price is capped per field, and both stacks cap it the same way, so they report the same total for a large document. The check runs in on_execute because a validation rule never sees variables, and first: $n could not be priced there. Chapter 1's query costs 385,151 units against a budget of 1,000, and the four-cargo page costs 53.");

figureSlide("PERSISTED DOCUMENTS", "Persisted document seam", { file: "15-persisted-document-seam" },
  "Figure 15.3 — The seam where a hash becomes document text, drawn for both stacks.",
  "The figure shows the path of a hash-only request through each stack. The Quarkus lane resolves the hash in a router route ahead of the GraphQL endpoint. The Python lane, which this deck follows, resolves it inside the engine. Strawberry's HTTP layer accepts a request whose query is null and passes the extensions on, and a SchemaExtension runs its on_operation hook before Strawberry looks for the query text. The extension sets the text from the hash, and the rest of the request proceeds as if the client had sent it. The parse and validation caches then reuse the work done for text the server has seen before. Highlighted steps mark the pieces that implement Apollo's protocol. The design is the same on both stacks: a hash is resolved to text at one seam in front of the engine, and only the seam differs. Chapter 15 covers the handshake and the two modes.");

codeSlide("PERSISTED DOCUMENTS", "Resolving a hash", LANG, "persisted_resolve",
  "The server recomputes the hash of any text it receives and refuses a mismatch.",
  "The listing is the resolver for every persisted-query case. With no hash, the query text passes through, and in trusted mode it must already be in the manifest. With a hash and no text, the server looks in the manifest and then in the run-time store, and answers PersistedQueryNotFound when neither has it, which starts the handshake. With a hash and text, the server recomputes the SHA-256 of the text and refuses a mismatch with BAD_USER_INPUT. A match is stored in automatic mode and checked against the manifest in trusted mode. The store is a cachetools LRUCache of at most 1,000 documents, so an evicted hash repeats the handshake. The two modes answer different questions: automatic persisted queries save bytes and give a GET a URL a cache can key, while trusted documents are an allowlist built at release time. Chapter 15 covers both, and the extension class that calls this resolver.");

codeSlide("CACHING", "Cache-Control policy", LANG, "cache_policy",
  "A response is public only for a GET of reference data with no errors and no Authorization header.",
  "The listing is the extension that sets Cache-Control on every GraphQL response. It sets no-store first, so that a request refused before execution still carries a policy. After execution it replaces the header with public and a max-age of 300 seconds, plus a Vary header on Accept, only when four tests pass: the request is a GET, it carries no Authorization header, the result has no errors, and every root field is reference data. The reference fields are location, voyage and __typename. A cargo's delivery status changes with every handling event, so cargo is never public. A cache keys on method and URL, so persisted GET requests from Chapter 15 are what make an edge cache possible. Inside the server, cachetools TTL caches sit under the loaders, and a write evicts the entry it changes. Chapter 16 covers the four places to keep an answer and the invalidation order.");

/* ======================= 08 · TRANSPORT SECURITY AND ACCESS CONTROL ======================= */
divider("08", "Transport security and access control",
  "TLS, public and internal instances, tokens and roles.",
  "The section covers who can reach the service and what each caller may do. The transport is TLS, terminated by uvicorn in the early examples and by an edge proxy in the Compose tier. The public instance describes less of itself than the internal one. Callers present a bearer token that PyJWT validates, and Strawberry permission classes decide access to operations, objects and fields. Chapters 17 and 18 cover these controls.");

codeSlide("TRANSPORT", "TLS in uvicorn", "dockerfile · UBI 10", "uvicorn_tls",
  "Uvicorn takes the certificate and key as options, and the image serves HTTPS on its one port.",
  "The listing is the entrypoint of the transport-security example. Uvicorn terminates TLS itself: the certificate and key are mounted at /certs by Compose, and the two ssl options point at them. The opentelemetry-instrument wrapper is the zero-code auto-instrumentation entry from the observability section. The container listens on 8443, and a request made over plain HTTP is not understood on that port. Certificates for the lab come from a script that generates a short-lived authority and a server certificate signed by it, and nothing secret is committed. Uvicorn hands the files to Python's ssl module, whose default minimum protocol is TLS 1.2, and both stacks accept TLS 1.3. HSTS is added by a small middleware function. Production would replace the lab authority with a certificate from a public or internal CA, or move termination to an edge proxy as the Compose tier does. Chapter 17 covers the transport guarantees.");

codeSlide("TRANSPORT", "Public and internal", LANG, "introspection",
  "One image, two instances: the public one refuses introspection and field suggestions.",
  "The listing is the end of the schema factory. When the public flag is set, the DisableIntrospection extension rejects __schema and __type at validation, and the schema configuration drops the did-you-mean suggestions that would otherwise name a real field. The same image runs a second time as an internal instance with the flag off, published on the loopback interface for CI and developers, who need introspection to run the conformance check. The router adds the matching options: no IDE on any instance, and no GET queries on a public one. The flag comes from a single setting, TRACKING_PUBLIC, so the difference between the two instances is configuration and not code. The remaining lines wire the OpenTelemetry extension and the metrics extension that the observability section covers. Chapter 17 describes the public and internal split, and the gates a request meets in order.");

codeSlide("ACCESS CONTROL", "Token validation", LANG, "auth",
  "PyJWT checks signature, expiry, issuer and audience; the context keeps only an Identity.",
  "The listing is the authenticator, in excerpt. It holds one PyJWKClient for the process, which fetches the identity provider's signing keys and caches them. The key lookup does blocking network I/O on a cache miss, so it runs in a thread pool to keep the event loop free. jwt.decode then checks the signature, the expiry, the issuer and the audience, and requires the exp, iss, aud and sub claims. A valid token becomes an Identity with the subject, the realm roles and the shipper organization, and the token itself is dropped. The omitted branches turn an invalid token into an HTTP 401 with a Bearer challenge before any GraphQL runs, and a missing header into an anonymous caller. Nothing here parses a token by hand. The issuer is a pinned string, while the keys are read over the backend network. Chapter 18 covers tokens and the identity in the context.");

codeSlide("ACCESS CONTROL", "Operation permissions", LANG, "permissions",
  "BasePermission classes decide; on_unauthorized raises an exposed error with a stable code.",
  "The listing shows two permission classes. Strawberry's BasePermission asks has_permission whether the current context may run a field, and on_unauthorized chooses the error. The default error would be masked by the error allowlist, so each class raises an ExposedError subclass with a stable code. A field lists its classes in order: with IsAuthenticated followed by IsOperator, an anonymous caller receives UNAUTHENTICATED and a signed-in shipper receives FORBIDDEN, so the client can act on the code. The same mechanism guards the register mutation, the cargo query and, with a third class, the cargoHandled subscription. Object-level visibility lives in one function that every path to a cargo calls, so a shipper sees its own cargos and an unknown id answers like a cargo that belongs to someone else. Chapter 18 covers operation, object and field rules and the choice between errors and nulls.");

/* ======================= 09 · OBSERVABILITY AND FEDERATION ======================= */
divider("09", "Observability and federation",
  "One trace per request, and subgraphs behind a gateway.",
  "The section covers two ways of looking at a graph that spans services. Observability records what each request did, per operation and per resolver, with three signals joined by a trace id. Federation lets several services own parts of one schema behind a gateway. On Python, the traces come from ready-made instrumentation, and the metrics and entities come from a SchemaExtension and Strawberry's federation module. Chapters 19 and 20 cover both.");

figureSlide("OBSERVABILITY", "Telemetry pipeline", { file: "19-telemetry-pipeline" },
  "Figure 19.2 — Three signals leave over one protocol, and the trace id joins spans, metrics and logs.",
  "The figure shows both stacks exporting to one collector over OTLP. On the Python side the opentelemetry-instrument wrapper instruments FastAPI and produces the HTTP server span. Strawberry's OpenTelemetryExtension adds the operation span and a span for each resolver, and a second extension adds the two counters that spans cannot give. The collector routes traces to Tempo, metrics to Prometheus and logs to Loki, and Grafana reads all three. A caller's traceparent header puts the request in the caller's trace, which both stacks honor without code. Tempo can also derive rate, error and duration series from the spans, per operation name, so a dashboard sees more than a single POST route returning 200. The operation name is the key that makes that work, which is why clients should name every operation. Chapter 19 builds the pipeline and the dashboards.");

codeSlide("OBSERVABILITY", "Operation metrics", LANG, "telemetry",
  "A SchemaExtension records each operation once and counts errors by code, with no change to resolvers.",
  "The listing shows the metrics extension, in excerpt. Spans say where time went in one request, and two counters say how often and which errors, across many. graphql.errors counts each error of an executed operation by its extensions code and the operation name. The extension reads the operation name and the client name when execution starts, yields to let the operation run, then walks the result's errors. An error with no declared code, such as a masked one, counts as unclassified, so unexpected failures are visible as their own bucket. The omitted middle of the method counts deprecated fields by walking the selected operation against the schema, which is what tells a team when a field can be removed. Both counters hang off the engine's own hook, so no resolver changes and no field can forget to count. Chapter 19 covers spans, metrics and logs.");

codeSlide("FEDERATION", "Federation entity", LANG, "federation_entity",
  "keys makes Cargo an entity, and resolve_reference answers the gateway through the cargo loader.",
  "The listing is the Cargo type of the cargo subgraph. strawberry.federation.type declares trackingId as the entity key, so a gateway can ask this subgraph for a cargo that another subgraph names. resolve_reference is the entity resolver: the parameter is named as the key is on the wire, because the representation's keys arrive as keyword arguments. It goes through the request's cargo loader, so the representations of one _entities request share one bulk booking call. The schema is a strawberry.federation.Schema, which adds the service field that a composer reads, the entities field that a gateway calls, and the federation version. The handling subgraph owns the delivery and the handling history of a cargo, and the gateway stitches the two into the single schema that clients see. The canonical SDL still holds for the composed result. Chapter 20 covers ownership, keys, composition as a gate and query plans.");

figureSlide("FEDERATION", "Cross-wired gateways", { file: "20-cross-stack-topology" },
  "Figure 20.5 — The supergraph does not know which stack is behind a subgraph.",
  "The figure shows two gateways over four subgraphs. The cargo subgraph and the handling subgraph each exist twice, once on Quarkus and once on Python. Gateway A routes cargo to the Quarkus service and handling to the Python service. Gateway B routes the other way round. Both compose the same supergraph, and a client sees the same schema from either. The arrangement proves the point of a shared contract: either stack can own either subgraph, because composition depends on the SDL and on the entity keys and not on the language behind them. Amber boxes mark the Python subgraphs. The example also checks what happens when a subgraph is down, since a gateway answers with partial data and the nullable fuses from Chapter 4 decide how much of the response survives. Chapter 20 covers composition, query plans and operating a supergraph.");

/* ======================= 10 · SUBSCRIPTIONS AND CLIENTS ======================= */
divider("10", "Subscriptions and clients",
  "Push with async generators, and clients that read the contract.",
  "Subscriptions push events to a client, and clients are the people who depend on the contract. The section covers the subscription type, which is an async generator on Strawberry, the plain server-sent-event feed beside it that resumes after a dropped connection, and the Python client that validates every document against the canonical SDL before sending it. Chapters 21 and 22 cover them.");

codeSlide("SUBSCRIPTIONS", "Async generator subscription", LANG, "subscription",
  "An async generator yields one HandlingEvent per registered event; permissions run once, before the first.",
  "The listing shows the Subscription type. The field is an async generator method: it iterates the store's watch, which yields each new handling event for one cargo as it is registered, and it yields a GraphQL object for each. The permission classes run once, before the first event, so the object-level rule is checked at subscription time and the field-level rules apply to every event. Before each event the resolver calls begin_event on the context, which gives the event new loaders with empty caches, so one event's reads never carry into the next. Each watcher owns a bounded asyncio queue, and a watcher that falls too far behind is ended, which keeps one slow consumer from growing the process's memory. The router enables three transports on one path: graphql-transport-ws, the older graphql-ws, and graphql-sse. Chapter 21 compares them.");

codeSlide("SUBSCRIPTIONS", "Plain SSE feed", "python · FastAPI", "sse_feed",
  "EventSourceResponse streams an async generator, and Last-Event-ID resumes from the last id seen.",
  "The listing is a plain server-sent-event feed, which is not a GraphQL operation: its payload is fixed, so there is no selection. FastAPI serves it with EventSourceResponse and ServerSentEvent, and the route is an async generator, so the framework writes the stream, the headers and the keep-alive comments. Each event carries an id, an event name of handled and a JSON data field. A browser EventSource that loses its connection reconnects by itself and sends the last id it saw as Last-Event-ID. The route passes that number to the store's watch, which replays the events registered after it and then continues live. A dependency checks the caller's identity and the cargo's visibility before the stream starts, with the same rule as the GraphQL subscription. Chapter 21 compares server-sent events, WebSocket and the other ways to push.");

codeSlide("CLIENTS", "The gql client", "python · gql", "gql_client",
  "gql validates each document against the contract's SDL locally before anything is sent.",
  "The listing is the Python client of the Chapter 22 example. It builds a Client from an HTTPX transport and the canonical SDL files, so every document is validated locally before a request is made. A document that selects a field the contract does not have, such as Cargo.weight, raises a GraphQL error with no request sent. The client sets an X-Client-Name header, which the server's deprecation counter reads, and a counter hook on the transport measures how many requests each step made. The document is named, TrackCargo, so the operation name appears in traces and metrics. A response with errors raises TransportQueryError, which carries the data and the errors side by side, so a client can use a partial page. gql also offers a DSL that builds documents from the schema's own types. Chapter 22 compares the client landscape, code generation and normalized caches.");

/* ======================= 11 · TESTING AND DEBUGGING ======================= */
divider("11", "Testing and debugging",
  "Layers that read the body, and surfaces that differ by profile.",
  "A GraphQL response is 200 for almost everything, so a test that checks the status line passes for failures. The section covers tests that read the body and the call log, organized in layers by cost, and the debugging surfaces that a development instance adds. On Python the suite uses pytest, httpx and asgi-lifespan, and it runs in the stack's own test image. Chapters 23 and 24 cover testing and debugging.");

figureSlide("TESTING", "Six test layers", { file: "23-test-layers" },
  "Figure 23.1 — Six layers: three run in the stack's test image, and three run from verify.sh.",
  "The figure names the six layers of the test strategy and where each runs. Schema tests assert that types and scalars exist and write the SDL out. Resolver unit tests call a resolver with the booking source stubbed and assert values, paths and codes. Operation tests send documents through the application's HTTP layer and assert data beside errors and the number of source calls. Those three run inside each stack's test image with no other service. The contract, client-document and load layers need the live stacks and the pinned tools, so verify.sh runs them. The cheapest layer that can see a failure should be the one that reports it: a failed unit says which rule broke, while a failed load check says only that something differs. The footer adds that a test which disappears fails the build, because verify.sh counts the tests. Chapter 23 builds each layer.");

codeSlide("TESTING", "In-process fixture", "python · pytest", "fixture",
  "LifespanManager runs the lifespan, then ASGITransport calls the application in process.",
  "The listing is the fixture behind the operation tests. The application creates its source-call log and its handling store in a lifespan function. httpx's ASGITransport calls the application without running that lifespan, so the fixture starts it with asgi_lifespan's LifespanManager, as the FastAPI documentation describes for async tests. The httpx client then talks to the app object directly, with no port, no process and no network. Every test gets a fresh application state, so the handling store of one test does not affect the next. The conftest module sets the environment before the app is imported, because the settings are read at import time: no source latency, the debug endpoints off and the telemetry SDK disabled. A second fixture exposes the source-call log, which lets tests treat the number of calls as an output. Chapter 23 covers the operation layer.");

codeSlide("TESTING", "Operation test", "python · pytest", "operation_test",
  "The assertions read data beside errors, the error path and extensions.code, not the status line.",
  "The listing is a test of the cargos list. The document comes from the shared documents directory, so the suite sends what the clients send. The status is always 200, so the test reads the body. One cargo cannot be loaded, and because the edge's node field is nullable, five nodes arrive and the sixth is null. The test asserts six edges, exactly one null node, exactly one error, an error path that ends at edges, index five, node, and the code SERVICE_UNAVAILABLE in the extensions. That is the nullable fuse from the nullability section, observed from the outside. The same file asserts the track-cargo document, the registration mutation with no user errors, and Strawberry's own test client, which returns data and errors apart. The pytestmark line puts every test on the anyio plugin with the asyncio backend. Chapter 23 covers operation tests and the behavior a schema cannot show.");

figureSlide("DEBUGGING", "Dev and prod surfaces", { file: "24-dev-vs-prod-surfaces" },
  "Figure 24.2 — Development surfaces live on development instances; masking and trace ids are identical.",
  "The figure sets a development instance beside a production one. The development instance offers the GraphQL IDE, which on Python is GraphiQL on the GraphQL path itself; payload logging is a Quarkus development surface with no Python counterpart. The production instance returns 404 for the IDE. Four things are the same on both: masked errors, an extensions traceId on every execution error, the lab level switch, and the OTLP export of traces and logs. A development instance must not be easier to read than production in any way a client could depend on, or a fault that reproduces in one will not reproduce in the other. The debugging path starts from the response, takes the trace id from the error, finds the trace in Tempo, and reads the log lines of the application's resolve category, which carry reference keys and never tokens or variable values. Chapter 24 covers the checklist.");

/* ======================= 12 · RUNNING IT ======================= */
divider("12", "Running it",
  "One image, a Compose tier and a Helm release.",
  "The Running it section runs the Python stack outside the development loop. One image is built from a multi-stage Containerfile on a UBI 10 Python base, a Compose project puts an edge in front of it, and one Helm chart deploys both stacks to a Kubernetes cluster. The book's last appendix runs the same chart on OpenShift Local, as a demonstration of an on-premises distribution. The application has no code path that depends on where it runs. Chapters 25, 26 and 27 cover the tiers.");

codeSlide("RUNNING IT", "Multi-stage image", "dockerfile · UBI 10", "containerfile",
  "uv syncs the locked dependencies in a build stage; the runtime stage copies only the environment and the app.",
  "The listing is the Containerfile of the final project, in excerpt. A build stage on the UBI 10 Python 3.14 minimal image installs uv and runs uv sync with the locked flag, first for dependencies in their own layer and then for the project, so a source-only change reuses the dependency layer. The runtime stage starts from the same base, copies the virtual environment and the app with ownership for UID 1001, and runs as that non-root user. The entrypoint starts uvicorn behind the opentelemetry-instrument wrapper on port 8080, with ten seconds of graceful shutdown for requests in flight. The image carries no environment-specific value: the collector address, the source latency and the identity settings arrive through the environment, which is why one image runs on a laptop and in a cluster. The base image tag is pinned exactly. Chapter 25 covers the image and the configuration contract.");

codeSlide("RUNNING IT", "Settings from the environment", "python · pydantic-settings", "settings",
  "pydantic-settings reads TRACKING_* variables, so one image takes its configuration from the environment.",
  "The listing is the settings class of the final project. pydantic-settings reads each field from an environment variable with the TRACKING_ prefix and converts it to the annotated type, so TRACKING_MAX_QUERY_COST arrives as an integer and TRACKING_PUBLIC as a boolean. The defaults are the development values. The source latency stands in for the time a call to an owning service takes, the debug endpoints are off unless a lab turns them on, the cost budget is 1,000 and the public flag selects the hardened instance. The three OIDC values say how a bearer token is validated: the issuer string a token must carry, the audience this API answers to, and the address from which the signing keys are read over the backend network. Compose and Helm set these variables and nothing else changes between tiers. The image holds no environment-specific value, which is why the image that passed the tests is the one that runs. Chapter 25 covers the configuration contract.");

figureSlide("RUNNING IT", "Compose tier", { file: "25-compose-tier-topology" },
  "Figure 25.1 — The backend network is internal, so the stacks are reached only through the edge.",
  "The figure shows the Compose project as three bands. The public band holds the edge, an nginx container with TLS 1.3, a request-body limit and only the GraphQL path routed. The backend band is an internal network that holds both stacks and the observability service, with no published ports for the stacks. The ops band publishes Grafana, Tempo, Prometheus and Loki on loopback ports. The numbers show the start order that health conditions enforce: the observability service first, the stacks second, the edge last. An internal network protects a service by making the wrong path impossible, which is stronger than a service that merely does not listen on a public address. The Python health split supports the order: a live route answers while the process runs, and a ready route answers only after the lifespan has built the store and the sources. Chapter 25 covers the edge, secrets and limits.");

codeSlide("RUNNING IT", "Helm values", "yaml · Helm values", "helm_values",
  "One chart renders both stacks from entries of a stacks map; the Python entry sets image, probes and limits.",
  "The listing is the Python entry of the chart's values file, in excerpt. The chart ranges over a map of stacks and renders a ConfigMap, a Deployment and a Service for each instance of each stack (public and internal), so the two stacks cannot drift apart in structure. The Python entry names the image gql-ch27-python at tag 1.0 with a pull policy of Never, because the image is loaded into the node. The readiness probe uses the ready route and the other probes use the live route. The resource requests and limits are small, 100 millicores and 256 mebibytes requested, with a ceiling of 500 millicores and 384 mebibytes. The introspectionOff block holds the one setting that turns a public instance into the hardened one, TRACKING_PUBLIC. A values schema rejects a mistyped key before any object reaches the cluster. Chapters 26 and 27 cover the chart and the final project that uses it.");


/* ======================= CLOSING ======================= */
{
  const s = S();
  addContentTitle(s, "WRAP-UP", "What to take away");
  addBullets(s, [
    "Types: annotations decide nullability, and strawberry.Maybe keeps absent apart from null.",
    "Execution: async resolvers, one context per request and one DataLoader per kind of key.",
    "Admission: schema extensions bound tokens, depth, aliases and cost before the first resolver.",
    "Contract: the exported schema is diffed against the canonical SDL in both directions.",
    "Delivery: a uv-locked image, a Compose tier with an edge, and one Helm release.",
  ], { fontSize: 18 });
  addCaption(s, "Same patterns, same contract; the Quarkus deck maps to this one section by section.");
  addNotes(s, "The five lines summarize how the patterns look in Python. Types come from annotations, with Maybe for the three-state input. Execution is async def resolvers, a context built per request by a FastAPI dependency, and Strawberry DataLoaders that batch on the event loop's next turn. Admission control is a list of schema extensions that run in the order a request meets them. The contract is the canonical SDL, held against the exported schema in both directions on every verification run. Delivery is one pinned image, a Compose tier with an edge, and a Helm release that treats the two stacks alike. The Quarkus deck covers the same twelve sections with SmallRye GraphQL, and the concepts deck holds the reasoning behind each pattern. The appendix lists the project file in full, and the entry point and the object-level rule in excerpt, to keep open in another window while working through the examples. Chapter 27 assembles all of it into one running system.");
}

/* ======================= THANK YOU ======================= */
{
  const s = S();
  addContentTitle(s, "THANK YOU", "Q&A");
  addBullets(s, [
    "The concepts deck covers what each pattern is and why, with no stack code.",
    "The Quarkus deck builds the same twelve sections with SmallRye GraphQL.",
    "The canonical SDL is in contracts/schema/shipping; the chapters carry the reasoning for each pattern.",
    "The appendix holds the project file, the entry point and the object-level rule.",
  ], { fontSize: 18 });
  addCaption(s, "Red Hat is the world's leading provider of enterprise open source software solutions.");
  addNotes(s, "Thank you. This is the point for questions. The material to return to is in three places: the runnable examples in the python directories, one per chapter, each started with docker compose and each carrying a verification script that asserts the behavior shown in the deck; the canonical schema in the contracts directory, which both stacks are held against; and the chapters, which carry the reasoning for every pattern and the recorded output of each example. The appendix holds the listings to keep open while reading the code. Questions about the Quarkus build map to the same twelve sections, so the two decks can be read side by side. Chapter 27 is the place to start for the complete system, because it assembles the limits, identity, subscriptions, telemetry and the three tiers into one project. Red Hat is the world's leading provider of enterprise open source software solutions, trusted for support, training and consulting services.");
}

/* ======================= APPENDIX ======================= */
divider("A", "Appendix",
  "Reference material to keep open in another window.",
  "The appendix lists the project file in full, and the entry point and the object-level rule in excerpt. They are reference material, meant to stay open in another window while reading the sections. Each listing names its source file in the first line, and a header marked excerpt means that some lines of the file are omitted.");

codeSlide("APPX · REFERENCE", "Project file", "toml · uv project", "app_pyproject",
  "The complete pyproject.toml of the final project.",
  "The listing is the complete project file of the final project. The project block names the package, requires Python 3.14 or newer and pins ten runtime dependencies to exact versions. The build-system block uses hatchling, pinned to an exact version as well, and the wheel target packages the app directory. uv reads this file and uv.lock together: uv sync resolves from the lock, and the Containerfile passes the locked flag so that a mismatch fails the build. The strawberry-graphql package is listed without the cli extra here, because the final project does not call the export command. Every dependency comes from a maintained open source project, and no package requires a license key. Keep this file open when reading the setup section, and compare it with the Chapter 0 skeleton to see which dependencies each chapter added.");

codeSlide("APPX · REFERENCE", "Application entry point", LANG, "app_main",
  "Imports, lifespan, application object and readiness probe of the final project (excerpt).",
  "The listing is the entry point of the final project, in excerpt. The lifespan function builds the process-wide objects once: the source-call log, the handling store and the authenticator. It sets a ready flag after the build and clears it on shutdown. The application object is created with that lifespan. The omitted middle holds the router wiring shown in the setup section, the event feed router and the debug routes that only mount when the debug setting is on. At the end, the readiness route answers 200 once the lifespan has run and 503 before that and during shutdown, while the liveness route, omitted here, answers 200 while the process runs. The split lets an orchestrator keep a container alive while it warms up and keep traffic away until it can serve. Keep this listing next to the Helm values, whose probes point at these two routes, and compare it with the Chapter 3 entry point.");

codeSlide("APPX · REFERENCE", "Object-level rule", LANG, "app_access",
  "The one function that decides whether a caller may see a cargo (excerpt).",
  "The listing is the object-level rule of the access-control section, without its module docstring. The function takes the caller's identity, which is None for an anonymous caller, and the owner of the cargo, which is None for an unknown cargo. An anonymous caller sees nothing. An operator sees every cargo, and a shipper sees a cargo whose owner matches its own organization. Every path to a cargo reads through the booking source, which applies this function, so the query, the connection, the node fields and the edge nodes cannot disagree. The subscription check and the event feed call the same function when a stream starts. A cargo that is not the caller's answers like an unknown one, with null and no error, so the response does not reveal which tracking ids exist. Keep this listing open while reading the permission classes in the access-control section.");

/* ======================= WRITE ======================= */

/* --- Scan to explore (QR codes) --- */
{
  const s = S();
  addContentTitle(s, "SCAN TO EXPLORE", "Take it with you");

  // Left QR: the site
  s.addImage({ path: `${ASSETS}/qr-graphql-site.png`, x: 2.30, y: 1.78, w: 3.10, h: 3.10 });
  s.addText("The site", { x: 1.55, y: 4.98, w: 4.60, h: 0.40,
    fontFace: FONT.title, fontSize: 18, bold: true, color: COLOR.ink, align: "center", valign: "middle" });
  s.addText("Chapters, the GraphQL schema and contracts, and both-stack runnable examples", { x: 1.45, y: 5.40, w: 4.80, h: 0.72,
    fontFace: FONT.body, fontSize: 13, italic: true, color: COLOR.caption, align: "center", valign: "top" });
  s.addText("patterncatalyst.github.io/api-patterns-and-practices-graphql", { x: 1.45, y: 6.12, w: 4.80, h: 0.32,
    fontFace: FONT.mono, fontSize: 10, color: COLOR.red, align: "center", valign: "middle" });

  // Right QR: the hub
  s.addImage({ path: `${ASSETS}/qr-hub.png`, x: 7.93, y: 1.78, w: 3.10, h: 3.10 });
  s.addText("Workshops & Tutorials", { x: 7.18, y: 4.98, w: 4.60, h: 0.40,
    fontFace: FONT.title, fontSize: 18, bold: true, color: COLOR.ink, align: "center", valign: "middle" });
  s.addText("The whole series: every workshop, tutorial, and deck in one place", { x: 7.08, y: 5.40, w: 4.80, h: 0.72,
    fontFace: FONT.body, fontSize: 13, italic: true, color: COLOR.caption, align: "center", valign: "top" });
  s.addText("patterncatalyst.github.io/patterncatalyst-workshops-tutorials-list", { x: 7.08, y: 6.12, w: 4.80, h: 0.32,
    fontFace: FONT.mono, fontSize: 9, color: COLOR.red, align: "center", valign: "middle" });

  addNotes(s, "This is the Python/Strawberry implementation deck, so the left code takes you to the runnable Python example and schema, the right to the whole series. On the left, the site: the chapters, the GraphQL schema and contracts, and the runnable both-stack examples, all public. On the right, the Workshops and Tutorials hub: every workshop, tutorial, and deck in the series in one place, including the REST, gRPC, and WebSockets siblings. Scan whichever is useful; both are on the Pattern Catalyst GitHub organization.");
}


writeDeck(pres, OUT);
