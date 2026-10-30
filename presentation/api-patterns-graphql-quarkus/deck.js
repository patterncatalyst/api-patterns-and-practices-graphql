// deck.js: "API Patterns & Practices: GraphQL: Quarkus Implementation".
// How the GraphQL patterns are built with SmallRye GraphQL on Quarkus: a
// code-first schema checked against one canonical SDL, in the shipping
// tracking view. Code on the slides is copied from examples/*/quarkus/**.
//
// Build:  bash presentation/_shared/build.sh presentation/api-patterns-graphql-quarkus

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

const OUT = path.resolve(__dirname, "api-patterns-graphql-quarkus.pptx");

const pres = newDeck();
defineSectionMaster(pres);
pres.title = "API Patterns & Practices: GraphQL: Quarkus Implementation";
let pageNum = 0;

function S() { const s = pres.addSlide(); pageNum += 1; addFooter(s, pageNum); return s; }
function divider(code, title, subtitle, notes) {
  const s = pres.addSlide({ masterName: "SECTION" }); pageNum += 1;
  addSectionDivider(s, code, title, subtitle, { onMaster: true });
  addNotes(s, notes);
}

// Figure slide: the caption starts with the book's figure number.
function figure(eyebrow, title, png, caption, notes, opts) {
  if (!require("fs").existsSync(`${SHARED}/png/${png}.png`)) throw new Error(`missing figure ${png}`);
  const s = S();
  addDiagramSlide(s, eyebrow, title, png, caption, opts || { x: 1.10, y: 1.72, w: 11.13, h: 4.60 });
  addNotes(s, notes);
}

// Code slide: lines are copied verbatim from the file named in the first line.
function code(eyebrow, title, lang, lines, caption, fontSize, notes) {
  const s = S();
  addSnippetSlide(s, eyebrow, title, lang, lines, caption, { fontSize });
  addNotes(s, notes);
}

const JAVA = "java · SmallRye GraphQL";

/* ======================= 1 · COVER ======================= */
{
  const s = pres.addSlide();
  pageNum += 1;
  s.background = { color: COLOR.white };
  try { s.addImage({ path: `${ASSETS}/cover-panel.png`, x: 0, y: 0, w: W, h: 7.5 }); } catch (e) {}
  s.addText("API PATTERNS & PRACTICES · GRAPHQL · QUARKUS", { x: 6.00, y: 1.82, w: 6.90, h: 0.34,
    fontFace: FONT.title, fontSize: 13, bold: true, color: COLOR.red, charSpacing: 3, align: "left", valign: "middle" });
  s.addText([{ text: "The Quarkus", options: { breakLine: true } }, { text: "implementation." }], {
    x: 5.95, y: 2.28, w: 6.95, h: 2.00, fontFace: FONT.title, fontSize: 48, bold: true, color: COLOR.ink, align: "left", valign: "top" });
  s.addText("SmallRye GraphQL on Quarkus, code-first against one canonical SDL: Mutiny resolvers, batching, query limits, authorization, telemetry and subscriptions in the shipping tracking view.", {
    x: 6.00, y: 4.30, w: 6.80, h: 1.30, fontFace: FONT.body, fontSize: 16, italic: true, color: COLOR.caption, align: "left", valign: "top" });
  s.addText([
    { text: "Robert Sedor", options: { bold: true, color: COLOR.ink, breakLine: true } },
    { text: "Principal Chief Architect, Application Development", options: { color: COLOR.caption } },
  ], { x: 6.00, y: 5.75, w: 6.70, h: 0.80, fontFace: FONT.body, fontSize: 15, align: "left", valign: "top" });
  try { s.addImage({ path: `${ASSETS}/logo-candidate-2.png`, x: 11.10, y: 6.80, w: 1.55, h: 0.37 }); } catch (e) {}
  addNotes(s, `Welcome to the Quarkus implementation deck, the second of three in the API Patterns and Practices series on GraphQL. The concepts deck explains what each pattern is and why it exists, with no stack code. This deck shows how the same patterns are built with SmallRye GraphQL on Quarkus, using the shipping tracking view as the running example: a customer asks where a cargo is and what happens next, and one response assembles the answer from three owners. The code on the slides is copied from the runnable examples under examples, in each chapter's quarkus directory. The through-line is that the schema is code-first. Annotated Java records and one annotated API class produce the schema, and a diff against the canonical SDL in the contracts directory checks the Java against the contract. I am Robert Sedor. By the end you will have seen nullability, resolvers, mutations and errors, pagination and batching, query limits, persisted documents, caching, transport security, authorization, telemetry, federation, subscriptions, tests and the container and chart that run it.`);
}

/* ======================= 2 · AGENDA ======================= */
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
  addNotes(s, `The twelve sections follow the order of the concepts deck, so the sections map one to one with the Python deck and follow the concepts deck's chapter order. We start with the toolchain and the code-first schema, then nullability and the gate that compares the generated schema with the contract. Execution and resolvers cover Uni-returning fields and the request context. Mutations and errors cover input types, payloads that carry userErrors, idempotent retries and the allowlist that masks unexpected failures. Schema design and evolution follow, then pagination and batching. The seventh section groups three protections: cost limits, persisted documents and cache headers. Then transport security and access control, observability and federation, subscriptions and clients, and testing and debugging. The Running it section runs the same image under Compose and under Kubernetes. The appendix carries longer listings to keep open in another window. Every section names the chapter that covers the topic in full.`);
}

/* ======================= 3 · SERIES MAP ======================= */
{
  const s = S();
  addContentTitle(s, "SERIES MAP", "Where this deck sits");
  addBullets(s, [
    "The concepts deck explains what each pattern is and why, with no stack code. Start there for the reasoning.",
    "This deck builds each pattern with SmallRye GraphQL on Quarkus 3.40.1 and JDK 25, code-first.",
    "The Python deck repeats the arc with Strawberry 0.335.0 on FastAPI 0.143.2, on Python 3.14 or newer.",
    "One canonical SDL under contracts/schema/ is the contract. Each stack's exported schema is diffed against it in CI.",
    "API Patterns & Practices: REST, gRPC, this GraphQL title, and a forthcoming WebSockets title.",
  ], { fontSize: 17 });
  addCaption(s, "Same domain, same contract, same chapter order in all three decks.");
  addNotes(s, `A short orientation so the three decks compose instead of repeating each other. The concepts deck holds the patterns and the reasoning in terms that do not depend on a language. This deck takes those patterns into one stack: SmallRye GraphQL on Quarkus 3.40.1, running on JDK 25. The Python deck walks the same twelve sections with Strawberry 0.335.0 on FastAPI 0.143.2. What ties the two implementations together is a single canonical SDL in the contracts directory. Neither stack generates code from it. Each builds its schema from annotated code, exports it, and a diff tool compares the export with the contract in both directions on every verification run, locally and in CI. A client cannot tell which stack answered. Chapter 5 covers the contract loop in detail, and the appendix of this deck lists the final project's build and configuration files.`);
}

/* ======================= 01 SETUP AND THE CODE-FIRST SCHEMA ======================= */
divider("01", "Setup and the code-first schema",
  "SmallRye GraphQL builds the schema from annotated Java.",
  `The Setup and the code-first schema section sets up the lab and shows what code-first means in Quarkus. A single extension, quarkus-smallrye-graphql, discovers classes marked as GraphQL APIs at build time, reads the annotations on them and on the records they return, and serves the resulting schema at the graphql path. There is no schema file to write and no generator to run. The canonical SDL still exists, and it is the yardstick that the contract gate compares the generated schema against. Chapter 0 sets up the lab and Chapter 3 introduces the type system on both stacks.`);

figure("THE LAB", "Lab topology", "00-lab-topology",
  "Figure 0.1: verify.sh drives both stacks; graphql-inspector diffs each live schema against the canonical SDL.",
  `This figure shows the Compose lab that every chapter builds on. The verify.sh script sends requests to both services through a shared library. The Quarkus service listens on port 8080 and serves the graphql path and the health path, and the Python service sits beside it on port 8081. A dashed box marks the optional observability container, added by a second Compose file. On the right, graphql-inspector introspects each live service and compares what it finds with the canonical SDL under contracts/schema/shipping. The point is that the lab proves behaviour as well as startup: the same checks run against both stacks. The Compose project is named for the chapter and starts the services with health checks, so a check never runs against a service that is still booting. The canonical SDL sits in the repository beside the examples, which means a change to the contract and a change to either stack are reviewed in one place. Chapter 0 covers the install steps, the repository layout and the first queries by hand, and the later chapters reuse this topology unchanged.`);

code("SETUP", "Build dependencies", "xml · Maven",
  snippet("examples/00-prerequisites/quarkus/pom.xml", [[42, 61]]),
  "quarkus-smallrye-graphql turns @GraphQLApi classes into the schema and serves POST /graphql.", 11,
  `The dependencies block of the chapter 0 pom shows how little Quarkus needs for a working GraphQL service. The quarkus-smallrye-graphql extension is the whole GraphQL stack: it discovers the annotated API classes, builds the schema code-first and serves POST on the graphql path with introspection on. The quarkus-smallrye-health extension adds liveness and readiness under q/health, which the Compose health checks use later. The quarkus-opentelemetry extension is present from the first chapter so that traces appear as soon as a collector address is configured; exports are asynchronous, so the service starts and answers with no collector running. Versions come from the Quarkus platform bill of materials, pinned to 3.40.1 in the properties of the same file. Chapter 0 walks through the full example.`);

code("CODE-FIRST", "The first query", JAVA,
  snippet("examples/00-prerequisites/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/TrackingApi.java", [[14, 33]]),
  "The method name becomes the field name; @NonNull on the argument becomes the bang in the SDL.", 10,
  `This is the whole Query type of the first chapter. The GraphQLApi annotation marks the class as part of the API surface, and the Query annotation turns the method into a root field named after the method, so cargo here. The Name annotation names the argument, NonNull makes it TrackingId!, and Description text flows into the schema as documentation that tools such as GraphiQL display. The return type is nullable, because the contract says a missing cargo is null, not an error. The data is a single canned cargo, so the example proves the toolchain and the schema generation without any domain logic. The later examples grow from this shape: more fields, more arguments, resolvers that return Uni. Chapter 0 runs this query against both stacks, and Chapter 3 explains how annotations map to SDL.`);

code("TYPES", "Records as types", JAVA,
  snippet("examples/03-sdl-type-system/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/Voyage.java", [[10, 26]]),
  "A record with @Type becomes an object type; List<@NonNull ...> becomes a list of non-null items.", 11,
  `A Java record is the natural carrier for a GraphQL object type. The Type annotation names the type, Description documents it, and each component becomes a field. NonNull on the schedule component makes the list itself non-null, while NonNull inside the angle brackets makes each item non-null, so the SDL reads schedule: [CarrierMovement!]!. The record implements Node, the interface that gives every addressable object a global id. SmallRye maps an interface's fields from getter-named methods, so the record carries an explicit getId method, and the Id annotation is what turns a String into the ID scalar. The id component itself is not annotated, because the getter is the field. Chapter 3 shows the same type in the canonical SDL and in Strawberry, and compares how each stack treats scalars and enums.`);

/* ======================= 02 NULLABILITY AND THE CONTRACT GATE ======================= */
divider("02", "Nullability and the contract gate",
  "Annotations carry the bangs; a two-direction diff checks them.",
  `Nullability is the part of a schema most likely to drift between a code-first implementation and its contract, because each language has its own default. In Java a type is nullable unless it is annotated, so the failure mode is a forgotten NonNull: the field is looser than the contract. This section shows the annotations on a record and then the gate that catches a mistake in either direction. Chapter 4 covers null propagation and Chapter 5 covers the contract loop.`);

code("NULLABILITY", "Nullable by default", JAVA,
  snippet("examples/04-nullability/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/Delivery.java", [[13, 24]]),
  "No annotation means nullable; @NonNull adds the bang; a primitive boolean is Boolean! without one.", 11,
  `The Delivery record shows all three cases on one type. Components with NonNull are required, so transportStatus and routingStatus are enums with a bang. The boolean misdirected is a Java primitive, which can never be null, so it becomes Boolean! with no annotation at all. Every other component has no annotation and is therefore nullable, and the descriptions say when null is meaningful: no last known location before the first handling event, no current voyage unless the cargo is aboard a carrier, no estimated arrival when none exists. The design rule from Chapter 4 is that nullable fields sit on boundaries between services, where one lookup can fail without taking the response down. A null in a non-null position climbs to the nearest nullable parent, which is why the placement of the bangs decides how much of a response survives a failure.`);

figure("CONTRACT GATE", "Two-direction diff", "05-two-direction-diff",
  "Figure 5.2: Each seeded drift is reported by one direction; only canonical to live may ignore a slice.",
  `This figure explains why the gate diffs the schema twice. The left panel compares the live schema to the canonical one and asks whether the stack exposes more or tighter surface than the contract. An extra field fails, and a tightened output, such as an itinerary that became non-null, fails as a breaking change. The right panel reverses the direction and asks whether what the stack serves differs from the contract. A loosened output, a removed enum value and a changed description all fail as drift. A whole type the stack does not serve is allowed, because the example serves a slice of the schema in early chapters. One direction alone would pass a tightened field, which is why both run. Chapter 5 shows the gate firing on seeded changes.`);

code("CONTRACT GATE", "Exporting the schema", "properties · Quarkus",
  snippet("examples/05-contract-first/quarkus/src/main/resources/application.properties", [[3, 8], [15, 15]]),
  "GET /graphql/schema.graphql serves the SDL the stack built; the gate diffs it against the contract.", 11,
  `The gate needs the generated schema as a file, and SmallRye serves it at the graphql path followed by schema.graphql, on the same port as the endpoint. The one setting that matters here is schema-include-scalars, which makes the export declare every scalar, so that references from Cargo to TrackingId and DateTime resolve when the diff tool loads the file. The comment block above the settings notes that introspection is on by default and is what verify.sh reads to compare the live schema with contracts/schema. The export is SDL in SmallRye's own ordering and style, so a text diff against the canonical file would be noise. That is why the checks never diff text and always hand both schemas to a tool that compares schemas. Chapter 5 covers the export, the lint step and the breaking-change check against main.`);

/* ======================= 03 EXECUTION AND RESOLVERS ======================= */
divider("03", "Execution and resolvers",
  "Uni-returning resolvers let sibling fields overlap.",
  `How a request becomes work: the engine parses and validates the document, coerces variables, then walks the selection set calling a resolver per field. In Quarkus the useful idiom is that a resolver which reads a source returns Mutiny's Uni, a lazy single-value type, so the engine receives a pending result instead of a blocked thread and can start sibling fields before any of them finish. The execution model and the resolver's inputs, including the request context, sit behind this.`);

figure("EXECUTION", "Parallel sibling fields", "06-parallel-siblings",
  "Figure 6.3: Sibling resolvers overlap in time in one Quarkus run.",
  `The figure is drawn from the source-call log of one run on Quarkus. The booking lookup for the cargo runs first and takes about 250 milliseconds. The routing and delivery lookups then start together, and the two location lookups start together after those finish. The total time follows the depth of the tree, three levels of 250 milliseconds, and not the five calls. A dashed lane shows what the same calls would cost if the resolvers blocked one event loop: they would run one after another. The specification says an executor may run sibling fields in any order, normally in parallel, so overlap is a permission, not a promise. It happens here because every resolver gives control back while it waits. Chapter 6 shows the check that asserts the overlap.`);

code("EXECUTION", "Uni-returning fields", JAVA,
  snippet("examples/06-execution-model/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/TrackingApi.java", [[91, 100], [107, 111]]),
  "A @Source method returns Uni, so the engine can start sibling fields before any of them finish.", 10,
  `Fields that hang off a parent type are written as methods with a Source parameter. The itinerary method receives the Cargo that the parent resolver produced and returns a Uni of Itinerary, and the delivery method does the same. Because both return a Uni, SmallRye hands the engine pending results, and the engine can start itinerary and delivery together. The loadLocation method shows the NonNull annotation on a resolver, which gives the field a bang in the schema. The descriptions say what null means for each field. A resolver that blocked its thread would serialize these calls on the event loop, and the parallel-sibling timeline would collapse into a staircase. Chapter 6 measures the overlap from the source-call log, and Chapter 13 replaces these one-parent methods with batch resolvers.`);

code("EXECUTION", "Request context", JAVA,
  snippet("examples/06-execution-model/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/TrackingApi.java", [[14, 26], [47, 53]]),
  "The Context gives getExecutionId(), read at method entry and passed to the source as an argument.", 10,
  `Every resolver in the Chapter 6 example takes the SmallRye Context as a parameter and reads getExecutionId on entry. The id identifies the request, and it travels to the source as an ordinary argument so that the source-call log can say which request each call belongs to. The comment above the class gives the reason for reading it at entry: a continuation of a delayed Uni resumes later and on a different thread, where request-scoped state is not guaranteed to belong to the same request. Taking the value while the resolver still runs on the request's thread removes the question. The same pattern carries the caller's identity in Chapter 18. The context is the right home for anything scoped to a request and shared across fields, such as an id, an identity or a loader. Chapter 7 returns to the request context.`);

code("RESOLVERS", "Query arguments", JAVA,
  snippet("examples/07-queries-resolvers/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/TrackingApi.java", [[50, 65]]),
  "@Name and @NonNull type the argument as a required value; a default belongs to the operation's variables.", 10,
  `Root fields take arguments through annotated method parameters. The Name annotation sets the argument name, NonNull makes it required, and Description documents it. Custom scalars such as TrackingId and UnLocode arrive as typed records, so the resolver works with a value that has already been parsed and validated by coercion. Defaults are a separate matter. A document can declare a variable with a default, for example a tracking id of ABC123, and that default belongs to the operation, not to the schema. The schema's argument stays TrackingId!, which is what the canonical SDL says. SmallRye also supports a schema-level default value on a parameter, and the example does not need one. Chapter 7 covers variables, aliases, fragments and the include and skip directives, all of which are features of the document and not of the resolver.`);

/* ======================= 04 MUTATIONS AND ERRORS ======================= */
divider("04", "Mutations and errors",
  "Domain failures are data; unexpected failures are masked.",
  `Writes and failures get one section because they share a design question: who needs to see what went wrong. A mutation is an ordinary resolver on the Mutation root, and the engine runs the top-level mutation fields of a request one after another. Domain validation failures come back as data in a userErrors list, because the client can act on them. Unexpected failures come back as execution errors with a masked message, because the client cannot fix a corrupted shard and should not learn its name. Chapters 8 and 9 cover the two halves.`);

code("MUTATIONS", "The mutation field", JAVA,
  snippet("examples/09-error-handling/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/HandlingApi.java", [[19, 20], [35, 42]]),
  "@Mutation with one input argument and a non-null payload; the engine runs top-level mutations in order.", 10,
  `The write surface of the tracking view is one field. The Mutation annotation puts registerHandlingEvent on the Mutation root, the single input argument is an input object, and the return type is a non-null payload wrapped in a Uni. The description says that domain failures are returned in userErrors, which the payload type carries. Using one input object and one payload type per mutation keeps the contract stable: a field can be added to either without breaking a client. The engine's rule that top-level mutation fields run serially matters when a request names several of them, because each can depend on the previous one's effect. Chapter 8 covers input types, coercion as the first line of defence, and why the payload re-reads the cargo so the client sees the recomputed delivery state.`);

code("MUTATIONS", "Payload with userErrors", JAVA,
  snippet("examples/09-error-handling/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/RegisterHandlingEventPayload.java", [[9, 15], [18, 27]]),
  "Domain validation failures return as data in userErrors, beside the recorded event or null.", 10,
  `The payload record has three components. The handlingEvent and cargo components are nullable and are null when userErrors is not empty. The userErrors component is a non-null list of non-null UserError objects, empty on success, and the description separates it from the response's top-level errors array. The two static factories, rejected and recorded, keep the two outcomes explicit in the code that builds the payload. A UserError carries a stable machine-readable code, a human message and an optional path to the input field it concerns. The split is the point: a client branches on userErrors for problems it can correct, such as an unknown voyage or a missing voyage number, and treats the errors array as a failure of the request itself. Chapter 8 lists the codes and Chapter 9 compares the two kinds of failure.`);

code("MUTATIONS", "Idempotent append", JAVA,
  snippet("examples/09-error-handling/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/HandlingStore.java", [[58, 72]]),
  "computeIfAbsent records the event once per idempotencyKey, so a retry becomes a read.", 10,
  `A retry is dangerous for a mutation. The client sends a request, the server records the event, the response is lost, and the client sends it again. The input carries an idempotencyKey that the client repeats on every retry of the same intent. The append method checks the key and inserts the event in one indivisible step, using ConcurrentHashMap.computeIfAbsent, which runs its function at most once per key. A flag records whether this call wrote the event. Two requests that arrive together cannot both record one, so a lookup followed by a separate insert would not be enough. A call without a key always writes. Chapter 8 proves this with eight identical concurrent requests that return the same event id and write exactly once, and notes that a production store would scope a key to the caller and expire it.`);

figure("ERRORS", "Error masking", "09-error-masking",
  "Figure 9.3: Masking is an allowlist: the client sees only what the service listed.",
  `This figure follows an exception from the source to the response. The source throws, the resolver does not catch it, and the engine builds an error that holds the path, the message and the original exception. The error then meets an allowlist. On Quarkus the allowlist is the show-runtime-exception-message setting, which names exception classes. A class on the list is exposed, so the client receives its message and its code. Anything else is masked: the client receives Internal server error with no detail and no class name. A dashed arrow shows that the full message, the stack, the time and the shard name always go to the server log. Because nothing is shown unless the service listed it, a new exception class added next year is masked by default. Chapter 9 covers the vocabulary of codes and the policy in full.`);

code("ERRORS", "A declared error", JAVA,
  snippet("examples/09-error-handling/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/SourceUnavailableException.java", [[5, 18]]),
  "@ErrorCode sets extensions.code; the class is on the allowlist, so its message reaches the client.", 10,
  `SourceUnavailableException is the one exception this service chooses to show a client. The ErrorCode annotation sets extensions.code to SERVICE_UNAVAILABLE, a value from a vocabulary the service owns, so a client can switch on the code and never on the message text. The class is listed in the application properties under the allowlist setting, which is what lets its message through the mask. A client that reads an error follows a short order. If data is absent, the request was rejected and the fix is in the client. Otherwise it walks the errors, finds the hole by path, and treats SERVICE_UNAVAILABLE as worth a bounded retry or a degraded rendering. A masked error has no code and gets a generic apology. Chapter 12 adds BAD_USER_INPUT, and Chapter 18 adds UNAUTHENTICATED and FORBIDDEN to the same vocabulary.`);

/* ======================= 05 SCHEMA DESIGN AND EVOLUTION ======================= */
divider("05", "Schema design and evolution",
  "Global ids, node dispatch and a deprecation path.",
  `A GraphQL schema has many clients and no version numbers, so design and evolution decisions are made once and kept. Design starts from demand: fields exist because a screen needs them. Identity comes from the Node interface, which gives every addressable object an opaque global id and gives the API one way to refetch any object. Evolution then relies on additive change, deprecation with a reason, and a gate that classifies each change as safe, dangerous or breaking. Chapters 10 and 11 cover the two topics.`);

code("SCHEMA DESIGN", "The Node interface", JAVA,
  snippet("examples/10-schema-design/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/Node.java", [[8, 23]]),
  "Interface fields come from getter-named methods, so each implementing record carries getId().", 11,
  `Node is the Relay Global Object Identification contract. Any type that implements it has a non-null id that is unique across the whole graph, so a client can store the id, refetch the object later and let a normalized cache key entries by type name and id. In SmallRye the Interface annotation marks the type, and fields are mapped from getter-named methods, which is why the interface declares getId and each record that implements it provides one. The Id annotation is what makes the field an ID instead of a String, and NonNull gives it the bang. Cargo, Location, Voyage and HandlingEvent all implement Node, and the prefix of each id says which type it belongs to. Chapter 10 covers naming, identity, inputs and payloads, and the rule that lists that grow become connections.`);

code("SCHEMA DESIGN", "Node dispatch by prefix", JAVA,
  snippet("examples/07-queries-resolvers/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/TrackingApi.java", [[76, 92]]),
  "Query.node reads the id prefix, calls the owning source and returns null for an unknown id.", 10,
  `Query.node accepts any global id and returns the object behind it. The resolver reads the prefix of the id, cargo_, loc_ or voy_, and calls the source that owns that type. The Id annotation on the argument keeps it an ID in the schema. The map call casts each result to the Node interface, and an id with an unknown prefix resolves to a null item. Returning null for an unknown id is the contract's answer, and it also means a caller cannot tell a missing object from one it may not see, a property Chapter 18 relies on. The result type is the interface, so a client writes inline fragments to select fields of the concrete type. The final project extends this dispatch with the event prefix and a bulk variant, nodes, that groups ids by type and makes one source call per type. Chapter 10 covers both.`);

code("EVOLUTION", "Deprecating a field", JAVA,
  snippet("examples/11-evolution/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/Itinerary.java", [[12, 21]]),
  "@Deprecated(reason) on the record component marks the field and names its replacement.", 11,
  `Evolution without versions means adding the replacement, deprecating the old field with a reason, watching usage, and removing it only when the usage is gone. Here finalArrivalTime is the replacement and finalArrivalDate carries the SmallRye Deprecated annotation with a reason that points clients at the new field. Both fields execute, and the old one is hidden from the default field list in tools but still answers. The reason string is part of the contract, so it names the replacement in a form a client can act on. Clients migrate on their own schedule, and the telemetry of Chapter 19 counts requests that still select the deprecated field, by client name. Chapter 11 classifies changes as safe, dangerous or breaking and shows the gate reporting the removal of a field with exit code 1 unless a sign-off rule is set.`);

figure("EVOLUTION", "Deprecation lifecycle", "11-deprecation-lifecycle",
  "Figure 11.2: Each step has a gate result, and removal is a decision, not a side effect.",
  `The figure runs left to right across four steps and three rows. The change row adds the replacement, deprecates the old field with a reason, observes usage through operation telemetry, and finally removes the field with a sign-off. The gate row shows the output for each step: the added field passes, the deprecated field passes, the observation step changes nothing in the schema, and the removal is reported as a breaking change, with exit code 1 by default and a warning with exit code 0 when the sign-off rule is set. The clients row shows existing clients unchanged, both fields executing, clients migrating on their own schedule, and finally a client that still selects the old field failing validation. Removal is a decision with a recorded sign-off. Chapter 11 covers the gate and what it cannot see.`);

/* ======================= 06 PAGINATION AND BATCHING ======================= */
divider("06", "Pagination and batching",
  "Relay connections and one batched call per level.",
  `Two problems appear as soon as a list grows. The list needs pages that stay stable while data changes, and the resolvers below the list must not call their sources once per item. The first is solved by Relay connections with opaque cursors that seek on a sort key. The second is solved by batching: a level of the response collects the keys its resolvers ask for and makes one bulk call per kind of key. Chapters 12 and 13 cover the two designs, and the same bulk source operations serve both.`);

code("PAGINATION", "Connection records", JAVA,
  snippet("examples/12-pagination/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/CargoEdge.java", [[8, 17]]),
  "An edge holds its cursor and the key of its cargo; the node field is resolved separately.", 11,
  `A connection is a type with edges and page information, and an edge pairs a cursor with a node. The CargoEdge record holds the cursor and the tracking id of the cargo it points at, and the tracking id is ignored by the schema because it is not a field. The node field is not a record component at all: a batch resolver in the API class loads the cargos for every edge on the page in one call when a query selects node. In the Chapter 12 example, each node resolves on its own, so an edge whose cargo cannot be loaded fails alone and leaves the rest of the page intact. The CargoConnection record adds edges, a non-null PageInfo and an optional totalCount, and PageInfo carries hasNextPage, hasPreviousPage and the start and end cursors. Chapter 12 covers forward and backward paging.`);

code("PAGINATION", "Cursor encoding", JAVA,
  snippet("examples/12-pagination/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/Pagination.java", [[107, 114], [129, 132]]),
  "A cursor is base64url of prefix, version and sort key fields; paging seeks on the key.", 11,
  `A cursor is opaque to the client and fully known to the server. The encode method joins a prefix, a version and the sort key fields with a separator and writes the result as base64url without padding. For cargos the key is the booking time and the tracking id, so paging seeks on the sort key and never counts rows from the start, which is why an insert cannot shift a page. The prefix names the connection, so a cursor from one connection is rejected by another, and the version lets the format change without misreading old cursors. The decode side, not shown, accepts only the canonical encoding and rejects anything else as a bad cursor with the BAD_USER_INPUT code. The same class holds the slice algorithm from the Relay Cursor Connections specification and the page size rules, a default of 10 and a maximum of 50. Chapter 12 explains each.`);

figure("BATCHING", "Loaders per field", "13-per-field-vs-per-key",
  "Figure 13.4: SmallRye keys a loader by parent per field; Strawberry keys one per kind of key.",
  `This figure compares how the two stacks batch the same fields. On SmallRye, each batch method gets its own loader keyed by the parent object. Leg.loadLocation and Leg.unloadLocation are two methods, so they have two loaders and make two getLocations calls, one for DEHAM, SGSIN and USNYC and one for CNSHA, DEHAM and NLRTM. DEHAM travels in both. On Strawberry, one loader is keyed by location code and both fields use it, so a single call carries all five codes. The difference is a constant, not a multiplier: the four-cargo query makes eight source calls on Quarkus and six on Python, and neither count grows with the page. Both counts are fixed by the shape of the query. Sharing one loader across fields on SmallRye would mean a request-scoped cache keyed by location code, which the example does not add, so it shows the two extra calls. Chapter 13 explains both designs.`);

code("BATCHING", "Batch resolvers", JAVA,
  snippet("examples/13-dataloaders/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/TrackingApi.java", [[246, 249], [270, 274]]),
  "A @Source List<...> method becomes a DataLoader and runs once per level with every parent.", 10,
  `A resolver whose Source parameter is a List is a batch resolver. SmallRye turns such a method into a graphql-java DataLoader, one per field per request, and calls it once with every parent the level collected. The method returns one value per parent, in the parents' order, so the list of itineraries lines up with the list of cargos. The trackingIds helper and the bulk source call turn a list of parents into one call to the owner. The second method does the same for legs and voyages, collecting the voyage numbers of every leg at the level. Root fields have no parents to collect and stay one source call each. The result is a call count fixed by the shape of the query, independent of the number of rows. Chapter 13 builds the contract of a DataLoader and shows the tick that triggers the batch.`);

/* ======================= 07 COST, PERSISTED DOCUMENTS, CACHING ======================= */
divider("07", "Cost, persisted documents, caching",
  "Refuse expensive work early; name documents by hash; cache by policy.",
  `Three protections act on the request before or after the resolvers. Limits refuse a document whose cost exceeds a budget before any source is called. Persisted documents let a client send a hash instead of text, which saves bytes, gives a cache a URL to key, and can serve as an allowlist. Cache headers let a shared cache keep an answer when the response is safe to share. Each protection needs information at a specific stage, so the order in which they run matters. Chapters 14, 15 and 16 cover the three in turn.`);

figure("QUERY COST", "Where limits fire", "14-limit-pipeline",
  "Figure 14.2: Every refusal ends before the sources are reached.",
  `The figure places each limit at the earliest stage that has the information it needs. In the SmallRye lane the HTTP layer reads one JSON object, the parser limits the operation to 5,000 tokens, validation applies the standard rules, and before execution three checks run in order: a depth limit of 15, an alias limit of 20 and a cost budget of 1000. In both lanes the resolver enforces the page cap of 0 to 50. Dashed arrows lead from every limit to a refused box that states an HTTP 200 response with errors, no data and zero source calls, and only the arrow from the resolver to the sources reaches the sources. Everything left of resolve sees only the document and the variables, which is why those limits can refuse without waiting for a resolver. Chapter 14 explains why depth and cost answer different questions.`);

code("QUERY COST", "The price list", JAVA,
  snippet("examples/14-query-cost/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/TrackingCostCalculator.java", [[33, 35], [41, 55]]),
  "A paged list multiplies its children by the page size; introspection fields cost nothing.", 10,
  `The cost of a field is one plus a multiplier times the cost of its children. This class is the example's price list, and graphql-java supplies the traversal, the variable coercion and the limit. Introspection fields cost zero. The cargos and handlingHistory fields multiply by the page size they will return, the first or last argument or else the default page. The nodes field multiplies by the number of ids. Every other field has a multiplier of 1, because an unpaginated list such as legs is bounded by the domain and not by the client. The QueryCost class chains this calculator with SmallRye's depth instrumentation through the GraphQL.Builder event. Chapter 14 prices the nested history query at 385,151 units against a budget of 1000.`);

figure("PERSISTED DOCUMENTS", "Resolving a hash", "15-persisted-document-seam",
  "Figure 15.3: A route ahead of SmallRye on Quarkus; an extension inside Strawberry on Python.",
  `The figure follows a hash-only request through each stack. In the Quarkus lane, a Vert.x route registered ahead of SmallRye's own route reads extensions.persistedQuery.sha256Hash, resolves the hash from the manifest and then from the quarkus-cache store, checks that a GET selects a query, and reroutes to the graphql path with the text as a query parameter. SmallRye then sees ordinary text, which it parses, validates and executes, reusing its cache of parsed documents. In the Python lane the router view accepts a null query and an extension sets the query from the hash. The highlighted steps implement Apollo's persisted-query protocol. The design point is that persisted documents are a seam in front of execution: the engine does not know whether the text came from the wire or from a hash. Chapter 15 covers APQ, trusted documents and the allowlist trade-off.`);

code("PERSISTED DOCUMENTS", "The hash route", JAVA,
  snippet("examples/15-persisted-queries/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/PersistedDocumentRoute.java", [[60, 61], [80, 85], [246, 258]]),
  "A router route ahead of the GraphQL endpoint reads sha256Hash and hands the document on.", 10,
  `The persisted-document handler is a CDI bean that registers routes on the Quarkus router when the router is created. The order values place its routes ahead of SmallRye's, so a request is resolved before the GraphQL handler sees it. The hashOf method reads the hash from extensions.persistedQuery.sha256Hash, either in the JSON body or in the extensions URL parameter, and treats malformed extensions as absent. In the automatic mode the first request that carries both a hash and text registers the document, and later requests may send the hash alone. In the trusted mode the manifest, built with the client release, is the only source of documents. The design is a router route in front of the GraphQL endpoint that resolves the hash and hands the checked text on, as the persisted-document figure draws it. Chapter 15 covers the handshake, GET for caching and the difference between APQ and an allowlist.`);

code("CACHING", "Cache-Control policy", JAVA,
  snippet("examples/16-caching/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/CachePolicy.java", [[44, 46], [59, 60], [67, 74]]),
  "A response is public only for an anonymous, error-free GET of reference data.", 11,
  `The cache policy decides the Cache-Control header from what the response is. The policyFor method answers public with a max-age of 300 seconds only when four things hold: the request is a GET, because a shared cache stores only what a cacheable method produced; the request carries no Authorization header, because what a caller may read can depend on who the caller is; the result has no errors; and every root field is reference data, here location, voyage or the typename meta field. Anything else gets no-store. The observer runs after execution, once the result is known and before the response is written, and a public response also carries Vary: Accept so a shared cache keeps one entry per Accept value. Identity belongs in the cache key or the answer stays out of the cache. Chapter 16 covers the four places to keep an answer: client, edge, server and sources.`);

/* ======================= 08 TRANSPORT SECURITY AND ACCESS CONTROL ======================= */
divider("08", "Transport security and access control",
  "TLS, introspection per instance, bearer tokens and role rules.",
  `What protects the endpoint and what each caller may do: the transport has to be encrypted, size-limited and open only to the browser origin that needs it. The schema map that introspection exposes is turned off on instances that anonymous callers reach, and left on for the instances that developers and CI use. Identity comes from a bearer token validated by the framework, and authorization is stated in three layers: operation, object and field. Transport security and authorization cover the two halves.`);

code("TRANSPORT", "TLS, CORS and size", "properties · Quarkus",
  snippet("examples/17-transport-security/quarkus/src/main/resources/application.properties", [[15, 19], [22, 25], [31, 31]]),
  "A PEM key pair, HTTPS only, one CORS origin and a 64K body ceiling.", 11,
  `These settings are the transport policy of the chapter 17 service. The TLS registry reads a PEM certificate and key, the HTTPS port is 8443, and insecure-requests set to disabled closes the plain-HTTP port, so a client that forgets the s gets a dropped connection instead of a readable response. The Strict-Transport-Security header tells a browser to use HTTPS for a year. CORS is enabled for the one browser origin that may call the API and for POST only, with the content-type and authorization headers allowed. The body limit of 64K refuses larger requests with 413 before they are parsed. Query by GET is off by default in SmallRye, so a query cannot travel in a URL unless a chapter turns it on. In the final project an edge container terminates TLS in front of the same image. Chapter 17 covers certificates for a lab, CSRF for JSON APIs and size limits.`);

code("INTROSPECTION", "Introspection switch", JAVA,
  snippet("examples/17-transport-security/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/IntrospectionSwitch.java", [[9, 29]]),
  "One image, two instances: the public one sets tracking.introspection.enabled to false.", 10,
  `Introspection is a map of the schema, and an anonymous caller has no business reading it, while CI and developers need it. The decision is made per instance, using one image deployed twice. This class turns introspection off for the whole JVM at startup when the tracking.introspection.enabled property is false, using graphql-java's documented switch. Both root fields, __schema and __type, are then refused, so a known type name and an unknown one are answered identically. The flag applies per instance because each instance runs in its own JVM: the public instance sets the environment variable TRACKING_INTROSPECTION_ENABLED to false, and the internal one keeps the default. The schema document served at the graphql path is a second introspection path, which the properties turn off at build time. Chapter 17 also covers field suggestions and checking the contract without public introspection, using an SDL export at build time.`);

code("AUTHENTICATION", "Bearer tokens with OIDC", "properties · Quarkus",
  snippet("examples/27-final-project/quarkus/src/main/resources/application.properties", [[87, 93]]),
  "Quarkus OIDC in service mode validates issuer, audience and expiry before GraphQL runs.", 11,
  `Authentication is configuration, not code. The quarkus-oidc extension runs in service mode, which means it validates bearer tokens: the signature against the identity provider's key set, the issuer, the audience and the expiry. The application reads the signing keys over the back channel with discovery off, while the issuer is pinned to the address clients use, so the same image runs in every tier and only these values change. The roles claim path maps the realm roles in the token to Quarkus roles. A token for the wrong audience, with the wrong issuer, expired or tampered with is answered with 401 and a WWW-Authenticate challenge before GraphQL runs. There is no path permission for the graphql endpoint, so a request with no token is anonymous and the public fields still work. Chapter 18 covers tokens from an identity provider and what the context holds.`);

code("AUTHORIZATION", "Operation and field rules", JAVA,
  snippet("examples/18-authn-authz/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/HandlingApi.java", [[52, 67]]),
  "@RolesAllowed(operator) guards the mutation and the registrationTime field.", 10,
  `Authorization is stated in three layers, and the excerpt shows two of them. The standard RolesAllowed annotation on the mutation is the operation rule: only an operator may register a handling event, and the check runs in a Quarkus interceptor before the method body, so a refused call reaches no source and no idempotency check. The same annotation on the registrationTime method is the field rule: any signed-in caller may read the event, and only operators may read when it was registered. The field is declared where the rule is stated, and the record component is ignored. A refused field is an error with a code at the field's own path, because the field is visible in the schema and a null would be ambiguous. The object rule lives in the booking source, the one place ownership is checked. Chapter 18 compares errors and nulls across the three layers.`);

code("AUTHORIZATION", "Security error codes", JAVA,
  snippet("examples/18-authn-authz/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/SecurityErrorTranslator.java", [[26, 49]]),
  "An interceptor gives the framework's refusals the contract's codes and fixed messages.", 10,
  `Quarkus signals a refused call with UnauthorizedException or ForbiddenException. The translator is a small interceptor that runs outside Quarkus's own security interceptor and swaps the two exceptions for AuthenticationRequiredException and OperatorRoleRequiredException. Those are ErrorCode exceptions on the same allowlist as the outage of Chapter 9, so they pass the mask with their messages. The result is two codes a client can act on, UNAUTHENTICATED with the message authentication required and FORBIDDEN with the message operator role required. UNAUTHENTICATED means send the user to sign in or refresh the token, and FORBIDDEN means signing in again will not help. The translator handles both a resolver that throws and a resolver that returns a Uni, which fails inside the Uni. The check itself stays the framework's. Chapter 18 shows both codes on the wire.`);

/* ======================= 09 OBSERVABILITY AND FEDERATION ======================= */
divider("09", "Observability and federation",
  "One trace per request; subgraphs owned by teams.",
  `A GraphQL service has one endpoint, so the URL says nothing about the operation. Observability has to come from the engine: a trace per request, a span per resolver that does work, metrics keyed by operation name and error code, and logs that carry the trace id. Federation answers a different problem, which is many teams owning one graph. Each team publishes a subgraph, entities carry keys, and a gateway composes the subgraphs and plans each query. Chapters 19 and 20 cover the two topics.`);

figure("OBSERVABILITY", "Telemetry pipeline", "19-telemetry-pipeline",
  "Figure 19.2: Traces, metrics and logs leave over OTLP to one collector.",
  `The figure shows the three signals leaving over one protocol. On the left are the two stacks. The Quarkus service uses quarkus-opentelemetry, the graphql-java instrumentation and a Telemetry observer; the Python service uses its own auto-instrumentation and extension. Amber arrows labelled OTLP lead into one OpenTelemetry Collector, which is not published to the host. From the collector, traces go to Tempo, metrics to Prometheus and logs to Loki, and a dashed arrow from Tempo to Prometheus carries span metrics. Grafana reads all three stores. A dashed box shows that a caller's traceparent header puts the request in the caller's trace, so the trace id links spans, span metrics and log records. Chapter 19 covers reading a trace, errors in a trace, and what to record and what to leave out.`);

code("OBSERVABILITY", "Spans per resolver", JAVA,
  snippet("examples/19-observability/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/Telemetry.java", [[56, 59], [78, 87]]),
  "The OpenTelemetry graphql-java instrumentation is chained into the engine through GraphQL.Builder.", 10,
  `The instrument method observes the GraphQL.Builder event that SmallRye fires before it builds the engine. It reads the current instrumentation chain from a throwaway build, creates the OpenTelemetry project's graphql-java instrumentation with data-fetcher spans, query sanitization and the operation name in the span name, and installs a chain of SmallRye's instrumentation, the spans and the example's own tracking instrumentation. The attribute keys above it are the names the metrics use: operation name, error code, field coordinate and client name. The tracking instrumentation records two metrics that a span cannot give, errors by extensions.code and requests that select a deprecated field, by coordinate, operation and client. Sanitization replaces literal values in the recorded query text. SmallRye's own operation span is off, so each request has exactly one. Chapter 19 reads a trace for fan-out.`);

code("FEDERATION", "Entity keys", JAVA,
  snippet("examples/20-federation/quarkus/cargo/src/main/java/com/patterncatalyst/shipping/tracking/Cargo.java", [[8, 9], [19, 38]]),
  "@Key on the record declares Cargo as an entity that other subgraphs can reference by trackingId.", 11,
  `In federation, an entity is a type that more than one subgraph contributes fields to, identified by a key. The Key annotation with a FieldSet names the key fields, here trackingId. The cargo subgraph owns the cargo and its route specification. The itinerary comes from the routing source, and the delivery and handling history belong to the handling subgraph, which extends the same Cargo entity by its trackingId key. The record in this subgraph therefore has no delivery component. Each team ships its own subgraph, and the gateway composes them into one supergraph. The properties of both subgraphs set quarkus.smallrye-graphql.federation.enabled, which adds the service SDL field and the entities field to the schema because key annotations are present. Chapter 20 explains why ownership, not size, is the reason to split a graph, and how composition acts as a gate.`);

code("FEDERATION", "Batch entity resolvers", JAVA,
  snippet("examples/20-federation/quarkus/cargo/src/main/java/com/patterncatalyst/shipping/tracking/TrackingApi.java", [[42, 42], [60, 70]]),
  "A @Resolver takes every key of the request in one call and returns one entity per key, in order.", 10,
  `The gateway sends the entities field a list of representations, and each has to become an object. Answering them one at a time is the N+1 problem of Chapter 13 across a network, so the entity resolvers are batch resolvers. The Resolver annotation marks a method as an entity resolver without creating a query field. With federation.batch-resolving-enabled, each method takes the keys of every representation of its type in the request and returns one entity per key, in the same order. Each calls the bulk source operation introduced for batching, so five Location representations with DEHAM twice make one getLocations call. An unknown key is null at its position, which is how a gateway learns that an entity does not exist. Chapter 20 shows a query plan, a mutation across subgraphs and what a gateway returns when one subgraph is down.`);

figure("FEDERATION", "Cross-stack subgraphs", "20-cross-stack-topology",
  "Figure 20.5: Either stack can own either subgraph; the supergraph does not know which.",
  `The figure wires two gateways across the two stacks. The client sends requests to gateway-a on host 8300 and gateway-b on host 8301, each composed from its own supergraph. Four subgraph containers sit at the bottom: cargo on Quarkus and cargo on Python, then handling on Quarkus and handling on Python. Quarkus boxes are white and Python boxes amber. Gateway-a leads to the Quarkus cargo subgraph and the Python handling subgraph, and gateway-b leads to the Python cargo subgraph and the Quarkus handling subgraph. The arrows cross. Because both stacks serve the same subgraph contract, the supergraph does not know which stack is behind a subgraph, and a team can swap implementations without touching the gateway. Chapter 20 covers composition as a gate and operating a supergraph.`);

/* ======================= 10 SUBSCRIPTIONS AND CLIENTS ======================= */
divider("10", "Subscriptions and clients",
  "Multi for push; SSE with resume; a typed client for Java callers.",
  `A query asks once and hears once. Real-time needs a way for the server to push, and GraphQL offers subscriptions: the client sends a document over a long-lived transport, and the server runs the selection set once for each event. In Quarkus a subscription is a method that returns Mutiny's Multi, a stream of items. A plain server-sent event feed covers browsers that need automatic resume, and a Java client can consume the API through a typed interface. Chapters 21 and 22 cover the server and the client sides.`);

code("SUBSCRIPTIONS", "Subscription field", JAVA,
  snippet("examples/21-real-time/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/HandlingApi.java", [[59, 65]]),
  "A @Subscription method returns a Multi; the engine runs the selection set once per emitted event.", 10,
  `The Subscription annotation puts cargoHandled on the Subscription root. The method returns a Multi of HandlingEvent, and the engine subscribes to it and executes the client's selection set once for each item the Multi emits. The store supplies the stream, filtered to one tracking id and tagged with the GraphQL channel, so the subscriber count can be read separately from the SSE feed. SmallRye serves the subscription over WebSocket on the same graphql path, speaking graphql-transport-ws and the older graphql-ws by default, so the application contains no protocol code. A document that fails validation never subscribes and gets an error frame that names the field. The cost of a subscription is a held connection and a held stream per client, which Chapter 21 prices against plain SSE, GraphQL over SSE and raw WebSockets in its choosing section.`);

code("SUBSCRIPTIONS", "Plain SSE feed", JAVA,
  snippet("examples/21-real-time/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/EventsResource.java", [[31, 31], [43, 62]]),
  "A Multi of OutboundSseEvent with Last-Event-ID resume, as a REST resource beside the GraphQL endpoint.", 10,
  `The plain feed is a REST resource, not a GraphQL operation, so its payload is fixed and there is no selection. Quarkus REST writes the stream: a Multi of OutboundSseEvent, produced as text/event-stream and built with the injected Sse object. Each event carries an id, the name handled and a JSON data field. A browser EventSource that loses its connection reconnects by itself and sends the last id it saw in the Last-Event-ID header. The feed answers by replaying the cargo's events registered after that id and then continuing live, using the same store as the subscription. This is the reason to offer a plain feed beside the subscription: resume is built into the protocol. Chapter 21 compares the four ways to push, covers ordering and delivery, and prices the cost of a long-lived stream.`);

code("CLIENTS", "Typesafe client", JAVA,
  snippet("examples/22-client-integration/clients/java/src/main/java/com/patterncatalyst/shipping/client/TrackingClient.java", [[15, 32]]),
  "Each method is an operation and each return type is its selection set.", 10,
  `The SmallRye typesafe client inverts the document-first approach. There is no document file. An interface annotated with GraphQLClientApi describes the operations, and the return types describe the selection: the Cargo record in Models.java has a tracking id, a description and a delivery, so the generated document selects those three fields and nothing else. The Query annotation names the root field, and the same Name and NonNull annotations as on the server type the arguments. The ErrorOr wrapper on the node of Models.CargoEdge is the client's answer to partial results. When one node failed, the edge arrives with an error that carries the message and path, and the rest of the page is kept. Without ErrorOr the client raises an exception for the whole call. The endpoint and the client-name header come from the tracking configuration key. Chapter 22 covers the normalized cache, generated types and the dynamic client.`);

/* ======================= 11 TESTING AND DEBUGGING ======================= */
divider("11", "Testing and debugging",
  "Six test layers; development surfaces stay on development instances.",
  `A GraphQL test asserts different things at different layers. A schema test checks that types and scalars exist and the SDL is written out. A resolver test checks values, paths and codes with the source stubbed. An operation test posts a document to the application and reads data beside errors. Contract, client-document and load tests run against the live stacks. Debugging starts from the response and ends at a cause, with the trace id as the thread between the client and the log. Chapters 23 and 24 cover testing and debugging.`);

figure("TESTING", "Six test layers", "23-test-layers",
  "Figure 23.1: Three layers run in each stack's test image; three run against the live stacks.",
  `The figure is a table of six layers with what each runs against, what it asserts and where it runs. The schema, resolver unit and operation layers run inside each stack's test image. The schema layer asserts that types and scalars exist and that the SDL is written out. The resolver unit layer stubs the booking source and asserts values, paths and codes. The operation layer runs against the application over its HTTP layer and asserts data beside errors, the number of source calls, and a refusal priced at 7,651. The contract, client document and load layers run from verify.sh against the live stacks. A footer notes that a test that disappears fails the build, because verify.sh counts 22 Quarkus tests and 18 Python tests. Chapter 23 builds each layer.`);

code("TESTING", "Operation tests", JAVA,
  snippet("examples/23-testing/quarkus/src/test/java/com/patterncatalyst/shipping/tracking/TrackCargoTest.java", [[21, 34]]),
  "@QuarkusTest posts a document and asserts data beside errors, not the status line alone.", 11,
  `An operation test posts a document to the application in process and reads the response the way a client reads it. The QuarkusTest annotation starts the application once for the class. The first test posts the track-cargo document with a cargo id and checks that errors is null, then walks the data: the tracking id, the description, the names of the origin and destination, and the delivery's transport and routing status. A GraphQL response can carry data and errors together, so asserting only the HTTP status would pass a response with holes. The documents are the same ones the clients of Chapter 22 send, so a change to a client document that the schema no longer supports fails in the test image. The same class asserts that a registration returns no userErrors and that a page reports a failing node at the node's path. Chapter 23 explains how the layers divide the work.`);

figure("DEBUGGING", "Development surfaces", "24-dev-vs-prod-surfaces",
  "Figure 24.2: The IDE and Dev UI stay on development instances; masking and trace ids do not change.",
  `The figure sets a development instance beside a production instance, one pair per stack. Three rows have amber boxes on the development side and dashed boxes on the production side. The GraphQL IDE, which is under q/graphql-ui on Quarkus and GraphiQL on Python, answers 404 in production. The Dev UI answers 404 in production. Payload logging writes each document in the development log and is off in production. Four rows have white boxes on both sides: the lab level switch, masked errors, extensions.traceId on every execution error, and traces and logs exported over OTLP. The consequence for debugging is that a problem reproduced in a development instance sees the same masking and the same trace id as production. The trace id is not a secret; reading the trace takes access to the observability backend. Chapter 24 gives a checklist from response to cause.`);

/* ======================= 12 RUNNING IT ======================= */
divider("12", "Running it",
  "One image per stack, from Compose to Kubernetes.",
  `The Running it section runs the tracking view as a system. The image is built once per stack and does not change between tiers. Docker Compose adds an edge that terminates TLS, an identity provider, an observability backend and a start order enforced by health checks. A Helm chart then renders the same images as Deployments and Services on Kubernetes, with probes, resources and a release that can be proven over time. The appendix of the book runs the same chart on an on-premises distribution, and the application code and images stay as they are. Chapters 25, 26 and 27 cover the tiers and the final project.`);

code("CONTAINER IMAGE", "Multi-stage image", "dockerfile · UBI 10",
  snippet("examples/27-final-project/quarkus/Containerfile", [[16, 16], [21, 22], [26, 30], [33, 33], [37, 48]]),
  "A Maven build stage, then the openjdk-25-runtime image running the fast-jar as user 185.", 10,
  `The Containerfile has two stages. The build stage starts from the UBI 10 OpenJDK 25 image, copies the pom first and runs dependency:go-offline in its own layer, so a source-only change reuses the dependency layer, and then copies the sources and packages the application. The runtime stage starts from the smaller openjdk-25-runtime image and copies the fast-jar layout, lib, the runner jar, app and quarkus, owned by user 185, which is also the user the process runs as. The image listens on 8080, binds the HTTP host to all interfaces through a system property, and uses the JBoss log manager. The entrypoint is the base image's run script, which reads JAVA_APP_JAR. The schema is built code-first from the annotated classes, so no contract file is copied into the image. Chapter 25 covers one image per stack and configuration outside the image.`);

figure("COMPOSE", "Compose tier", "25-compose-tier-topology",
  "Figure 25.1: The backend network is internal; the stacks are reached only through the edge.",
  `The figure shows three vertical bands. The public band holds the edge, an nginx container with TLS 1.3, a body limit under 64k and only the graphql path routed, plus the configuration and the two secrets mounted as files. The backend band, marked internal, holds the two stacks and the observability service, with start order numbers: observability first, the stacks second, the edge last, each enforced by a health condition. Neither stack publishes a port. An arrow from the client enters the edge over TLS, and the edge reaches both stacks on port 8080. The ops band on the right holds Grafana, Tempo, Prometheus and Loki, published on the loopback address only. The design is that the cheapest refusal is the one made before the application is involved. Chapter 25 covers secrets as files, limits, restarts and shutdown.`);

code("KUBERNETES", "One chart, both stacks", "yaml · Helm values",
  snippet("examples/27-final-project/helm/values.yaml", [[11, 17], [31, 34], [63, 68], [82, 85]]),
  "Each stack is an entry of stacks with its image and resources; one template renders both.", 10,
  `The chart keeps both stacks as two entries of one map. A template ranges over the map and renders a ConfigMap, a Deployment and a Service for each entry, so the two stacks cannot drift apart in structure. The excerpt shows the image of each stack, loaded into the node, so the pull policy is Never, and the resource requests, which are set per stack. The full file also declares startup, readiness and liveness probes for each stack. Every stack has a public and an internal instance from the same image, with introspection off on the first and on for the second. A values schema validates every install, upgrade, lint and template, so a mistyped key fails before an object reaches the cluster. Chapter 26 covers configuration, probes, isolation and proving a release.`);

/* ======================= CLOSING ======================= */
{
  const s = S();
  addContentTitle(s, "WRAP-UP", "What to take away");
  addBullets(s, [
    "The schema is code-first: annotated records and one API class, checked against the canonical SDL in both directions.",
    "Resolvers return Uni and batch with @Source lists, so call counts follow the query's shape.",
    "Failures have two homes: userErrors for domain input, a masked errors array for the rest.",
    "Limits, authorization, telemetry and the container image are configuration and small classes on the same engine.",
  ], { fontSize: 17 });
  addCaption(s, "Every pattern in the concepts deck has a counterpart in the Python deck.");
  addNotes(s, `The deck followed one request path through twelve sections. The schema is built from annotated Java records and one API class, and a diff in both directions against the canonical SDL keeps it equal to the contract. Resolvers that read sources return Uni, so sibling fields overlap, and batch resolvers with a Source list make the number of source calls depend on the shape of the query instead of the number of rows. Failures have two homes: domain validation comes back as userErrors data, and everything unexpected comes back as a masked error with a code from the service's vocabulary. Query limits, the cache policy, the introspection switch, bearer-token validation and the role rules are configuration and small classes attached to the engine through standard extension points. The same image runs under Compose and Kubernetes, with the chart and the Containerfile shown in the Running it section. Each takeaway names a chapter in the concepts deck for the reasoning behind it. The Python deck follows the same twelve sections, so the two can be read side by side.`);
}

{
  const s = S();
  addContentTitle(s, "THANK YOU", "Q&A");
  addBullets(s, [
    "The concepts deck covers what each pattern is and why, with no stack code.",
    "The Python deck builds the same twelve sections with Strawberry on FastAPI.",
    "The appendix lists the final project's build, configuration and one resolver class.",
  ], { fontSize: 17 });
  addCaption(s, "Red Hat is the world's leading provider of enterprise open source software solutions.");
  addNotes(s, `Thank you. This deck built the GraphQL patterns of the concepts deck with SmallRye GraphQL on Quarkus, from a code-first schema through limits, authorization, telemetry, federation and subscriptions to a container image that runs under Compose and Kubernetes. The Python deck follows the same twelve sections with Strawberry, and the concepts deck holds the reasoning behind each pattern. The appendix carries the final project's build file, configuration and one resolver class as excerpts of the real examples. I am happy to take questions on any of it. Red Hat is the world's leading provider of enterprise open source software solutions, trusted for support, training and consulting services.`);
}

/* ======================= APPENDIX ======================= */
divider("A", "Appendix",
  "Longer listings for the excerpts in this deck. Keep this section open in another window.",
  `This appendix collects the final project's build file, configuration and one resolver class, plus a figure on building the image inside an on-premises cluster, shown as excerpts of the files in the examples. They are reference material for reading alongside the body of the deck and are not meant to be presented in order. Each listing names its source file in the first line and marks any omitted run with an elision line. The final project combines the work of the earlier chapters in one image: telemetry, query limits, bearer-token authorization, the introspection switch and the subscription.`);

code("APPX · BUILD FILES", "Final project build", "xml · Maven",
  snippet("examples/27-final-project/quarkus/pom.xml", [[48, 48], [51, 54], [63, 66], [71, 74], [86, 90]]),
  "The final project adds health, OIDC and the graphql-java instrumentation.", 10,
  `The final project's dependencies block, shown as an excerpt. The quarkus-smallrye-graphql extension is the GraphQL stack from the first chapter. The quarkus-smallrye-health extension serves liveness and readiness under q/health. The quarkus-oidc extension validates bearer tokens: signature from the identity provider's key set, issuer, audience and expiry, and maps roles to the security identity. The last entry is the OpenTelemetry project's graphql-java instrumentation, whose version is managed by the Quarkus platform bill of materials. Two more dependencies, quarkus-rest-jackson for the lab-only debug resource and quarkus-opentelemetry for the SDK and exporter, sit between the entries shown. The platform version, 3.40.1, is set once in the properties of the same file.`);

code("APPX · CONFIGURATION", "Final project properties", "properties · Quarkus",
  snippet("examples/27-final-project/quarkus/src/main/resources/application.properties", [[10, 12], [29, 33], [47, 48], [73, 76], [87, 93]]),
  "Endpoint, telemetry export, masked-error message, request limits and OIDC settings.", 10,
  `An excerpt of the final project's application properties. The first lines fix the HTTP host and port and the graphql root path. The OpenTelemetry lines point the exporter at the collector address from the environment and set the service name and the metrics and logs switches. The error-handling lines give the message shown for a masked error and name the extension fields, code and traceId, that reach the response. The limits section sets the depth limit of 15 as SmallRye's own setting, and the cost, token and alias limits as the example's own properties, with the same alias limit as the Python stack. The last block configures Quarkus OIDC in service mode with the issuer pinned to the address clients use and the roles claim path set to the realm roles.`);

code("APPX · RESOLVER CLASS", "Mutation and subscription", JAVA,
  snippet("examples/27-final-project/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/HandlingApi.java", [[33, 35], [62, 70], [79, 89]]),
  "The mutation and the subscription of the final project, with the operator role check.", 10,
  `An excerpt of the final project's HandlingApi. The class is marked as a GraphQL API and bound to the security error translator, so refusals carry the contract's codes. The mutation requires the operator role, the check running before the method body, and passes the caller's viewer to the registration so that ownership rules apply. The subscription returns a Multi of HandlingEvent from the store's GraphQL channel. The comment inside it records the division of labour: a gate admits the caller once, before the first event, applying the operation and object rules of Chapter 18, and a subscriber identity applies field authorization, such as registrationTime, to every event as the subscriber. The full class also holds batch resolvers for the cargo, location and voyage fields of an event.`);

figure("APPX · OPENSHIFT LOCAL", "In-cluster image build", "A-in-cluster-build",
  "Figure A.2: One image, built where it runs.",
  `The appendix of the book runs the same chart on OpenShift Local, an on-premises Kubernetes distribution. This figure shows the one step that differs: the image is built inside the cluster instead of loaded from the host. A build command on the host sends the Quarkus directory of the final project as a tar archive to a build configuration with a binary source and a Docker strategy that uses the same Containerfile. A build pod runs Maven and then the runtime image on UBI 10 and OpenJDK 25, and pushes the result to an image stream in the cluster registry. The deployment takes its image from that registry,. The application code and the image are the same as in the earlier tiers. Appendix A covers routes and identity on routes.`);


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

  addNotes(s, "This is the Quarkus/SmallRye GraphQL implementation deck, so the left code takes you to the runnable Quarkus example and schema, the right to the whole series. On the left, the site: the chapters, the GraphQL schema and contracts, and the runnable both-stack examples, all public. On the right, the Workshops and Tutorials hub: every workshop, tutorial, and deck in the series in one place, including the REST, gRPC, and WebSockets siblings. Scan whichever is useful; both are on the Pattern Catalyst GitHub organization.");
}


writeDeck(pres, OUT).catch((e) => { console.error(e); process.exit(1); });
