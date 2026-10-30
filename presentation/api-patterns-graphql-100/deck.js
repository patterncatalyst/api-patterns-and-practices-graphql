// deck.js — "API Patterns & Practices: GraphQL — 100 (Concepts)".
// Stack-agnostic: the what and why of GraphQL in the shipping and cargo domain.
// Snippets are wire-level only: SDL, GraphQL documents and JSON. The Quarkus and
// Python decks (../api-patterns-graphql-quarkus, ../api-patterns-graphql-python)
// carry the implementations.
//
// Build:  bash ../_shared/build.sh .   (pinned Node 24 container)

"use strict";

const path = require("path");
const SHARED = path.resolve(__dirname, "../_shared");
process.env.DECK_ASSETS = `${SHARED}/assets`;
process.env.DECK_PNG = `${SHARED}/png`;
const { snippet } = require(`${SHARED}/snippet.js`);

const H = require(`${SHARED}/deck-helpers.js`);
const {
  COLOR, FONT, W, ASSETS,
  newDeck, addFooter, addContentTitle, addBullets, addTwoColBullets,
  addStatusTable, addCaption, addCodeSlide, addDiagramSlide,
  addSectionDivider, addNotes, defineSectionMaster, writeDeck, addSnippetSlide,
} = H;

const OUT = path.resolve(__dirname, "api-patterns-graphql-100.pptx");

const pres = newDeck();
defineSectionMaster(pres);
pres.title = "API Patterns & Practices: GraphQL — 100 (Concepts)";
let pageNum = 0;

function S() { const s = pres.addSlide(); pageNum += 1; addFooter(s, pageNum); return s; }
function divider(code, title, subtitle, notes) {
  const s = pres.addSlide({ masterName: "SECTION" }); pageNum += 1; addSectionDivider(s, code, title, subtitle, { onMaster: true }); addNotes(s, notes);
}

/* Code lines are read from the named repository file, so every line on a slide is a
   verbatim line of its source. `spec` mixes 1-based line numbers with "# ..." markers.
   The container mounts only presentation/, so the picked lines are cached in
   snippets.json by a host run and replayed from there when the source is not visible. */
function codeSlide(eyebrow, title, lang, src, ranges, caption, notes, opts = {}) {
  const { tag, trailing, fontSize, ...rest } = opts;
  const snip = snippet(src, ranges, { tag });
  if (trailing) snip.lines.push(trailing);
  const s = S();
  addSnippetSlide(s, eyebrow, title, lang, snip, caption, { fontSize: fontSize || (snip.lines.length > 21 ? 10 : 11), ...rest });
  addNotes(s, notes);
}
function fig(eyebrow, title, file, caption, notes) {
  const s = S();
  addDiagramSlide(s, eyebrow, title, file, caption, { x: 0.62, y: 1.75, w: 12.09, h: 4.70 });
  addNotes(s, notes);
}

/* ======================= COVER ======================= */
{
  const s = pres.addSlide();
  pageNum += 1;
  s.background = { color: COLOR.white };
  try { s.addImage({ path: `${ASSETS}/cover-panel.png`, x: 0, y: 0, w: W, h: 7.5 }); } catch (e) {}
  s.addText("API PATTERNS & PRACTICES · GRAPHQL · 100", { x: 6.00, y: 1.82, w: 6.90, h: 0.34,
    fontFace: FONT.title, fontSize: 13, bold: true, color: COLOR.red, charSpacing: 3, align: "left", valign: "middle" });
  s.addText([{ text: "GraphQL:", options: { breakLine: true } }, { text: "the what, the why." }], {
    x: 5.95, y: 2.28, w: 6.95, h: 1.70, fontFace: FONT.title, fontSize: 46, bold: true, color: COLOR.ink, align: "left", valign: "top" });
  s.addText("The design patterns behind a production GraphQL service: the schema, execution, errors, evolution, pagination, safety, security and operation. The domain is the shipping tracking view. Snippets are wire-level only. The Quarkus and Python decks show the implementations.", {
    x: 6.00, y: 4.15, w: 6.80, h: 1.45, fontFace: FONT.body, fontSize: 15, italic: true, color: COLOR.caption, align: "left", valign: "top" });
  s.addText([
    { text: "Robert Sedor", options: { bold: true, color: COLOR.ink, breakLine: true } },
    { text: "Principal Chief Architect, Application Development", options: { color: COLOR.caption } },
  ], { x: 6.00, y: 5.75, w: 6.70, h: 0.80, fontFace: FONT.body, fontSize: 15, align: "left", valign: "top" });
  try { s.addImage({ path: `${ASSETS}/logo-candidate-2.png`, x: 11.10, y: 6.80, w: 1.55, h: 0.37 }); } catch (e) {}
  addNotes(s, "Welcome. This is the 100-level deck in the API Patterns and Practices series on GraphQL. The series is API Patterns & Practices: REST, gRPC, this GraphQL title, and a forthcoming WebSockets title. It covers the what and the why: the patterns themselves, not any one framework's implementation of them. The domain is shipping and cargo throughout. A tracking view aggregates the cargo record, the routing itinerary and the handling history behind one schema, and clients ask it for exactly the fields they need. The series premise is one canonical schema and two implementations, Quarkus with SmallRye GraphQL and Python with Strawberry, each checked against the same contract. In this deck the snippets are wire-level only: schema definition language, GraphQL documents and JSON responses. The two companion decks show how each stack builds the same patterns. I am Robert Sedor, Principal Chief Architect in Application Development. By the end you should be able to explain where GraphQL fits next to REST and gRPC, how a request executes, how failures and nulls travel, how a schema evolves without versions, and how the whole service is limited, secured, observed and run.");
}

/* ======================= AGENDA ======================= */
{
  const s = S();
  addContentTitle(s, "OVERVIEW", "Agenda");
  addTwoColBullets(s,
    [
      "Why GraphQL, and the decision lens",
      "The schema: SDL and types",
      "Execution: resolvers, queries, mutations",
      "Errors and partial results",
      "Schema design and evolution",
      "Data fetching at scale",
    ],
    [
      "Performance and safety",
      "Security",
      "Observability and federation",
      "Real time and clients",
      "Testing and debugging",
      "Running it, and the final project",
    ],
    { fontSize: 16 });
  addCaption(s, "Every code sample is wire-level: schema definition language, GraphQL documents and JSON.");
  addNotes(s, "Here is the arc. We start with why a team would choose GraphQL next to REST and gRPC, and a seven-axis decision lens that every later section reuses. Then the schema: the type system, nullability and the contract that keeps two implementations aligned. Execution follows, covering how a request is parsed, validated and resolved, and how a mutation differs from a query. Errors and partial results come next, because GraphQL fails field by field rather than request by request. The middle of the deck is schema design and evolution, then pagination and batching, which together keep a graph affordable. Performance and safety covers cost limits, persisted documents and caching. Security covers transport, introspection and authorization. Observability and federation, real time and clients, and testing and debugging round out the practice. The section on running it, and the final project, runs the whole service in containers and on a cluster. Everything here is conceptual and stack-agnostic.");
}

/* ======================= 01 · WHY GRAPHQL ======================= */
divider("01", "Why GraphQL, and the decision lens",
  "Where GraphQL fits next to REST and gRPC, and seven axes for choosing it per interaction.",
  "Two foundations come first. The first is a precise picture of what GraphQL is: a typed graph that the server publishes and the client queries with a selection of fields, answered in one JSON response. The second is a decision framework. Seven axes turn the strengths and costs of the paradigm into a judgement that can be made per interaction, not per organization. The shipping domain has four interactions that look alike and differ sharply, and the framework gives each of them a different answer. This vocabulary comes back at the end of every later chapter in a Decision callout.");

fig("FOUNDATIONS", "Three paradigms", "01-three-paradigms",
  "Figure 1.1 — Three paradigms, one intent: REST, gRPC and GraphQL answering one tracking question.",
  "The figure shows one client intent, the state of cargo ABC123 and its remaining route, expressed three ways. A REST client treats the cargo and its related data as separate resources and issues several GET requests, one for the cargo, one for the itinerary, one for the handling events, and one for each voyage. A gRPC client calls typed methods on each service that owns a piece of the answer, which suits service-to-service traffic but needs a proxy in a browser. A GraphQL client sends one document that names the fields it wants over a graph, and the server assembles the answer. The point is where the shaping work happens. REST and gRPC fix the response shape on the server and let the client combine responses. GraphQL lets the client fix the shape and makes the server do the combining. Chapter 1 covers the comparison in full.");

fig("REQUEST PATH", "One request path", "01-request-path",
  "Figure 1.2 — One endpoint, one POST, four server stages and a fan-out to the services that own the data.",
  "Every GraphQL operation goes to one endpoint, conventionally /graphql, as a POST whose JSON body carries a query string, a variables object and an optional operationName. The server parses the text, validates it against the schema, coerces the variables and only then executes. Execution walks the selection set, and each field has a resolver that fetches from the service that owns the data. The result is one JSON map with data, an optional errors list and optional extensions. Variables travel beside the query text, which lets the server cache the parsed document and keeps user values out of the parsed string, for the same reason prepared statements exist in SQL. The GraphQL over HTTP specification also allows GET for queries and requires a mutation received over GET to be refused with a 4xx status. Chapter 1 traces the request, and Chapter 6 covers the execution algorithm precisely.");

codeSlide("FIRST QUERY", "A first tracking query", "graphql · document and response",
  "_docs/01-from-rest-and-rpc-to-graphql.md", [[54, 62], [82, 83], [91, 100]],
  "The response mirrors the selection field for field and contains nothing the query did not name.",
  "The snippet shows the tracking question as one GraphQL document and the beginning of its response, with the middle of each trimmed. The operation takes one variable typed with the schema's TrackingId scalar and marked non-null with a bang. The root field cargo resolves one Cargo, and inside it the client names only the fields it wants, here the tracking id, the origin, and two delivery fields. The response has the same shape as the selection. Three properties recur throughout the book. The response contains nothing the query did not name, so adding a field to the response means editing the query, not the server. Every value is typed by the schema, so transportStatus can only be one of five enum values. And the response is one document even though the data came from at least three owners. Chapter 1 shows the full query and response, including the itinerary and handling history.", { trailing: "...", fontSize: 10 });

{
  const s = S();
  addContentTitle(s, "TRADE-OFFS", "Where GraphQL wins and loses");
  addStatusTable(s, [
    { code: "Shape", name: "wins", purpose: "The client selects fields, and one request returns what a screen needs from several owners." },
    { code: "Round trips", name: "wins", purpose: "A screen that joins cargo, legs and events makes one request instead of five." },
    { code: "Contract", name: "wins", purpose: "One introspectable schema drives tooling, generated clients and schema diffs." },
    { code: "Evolution", name: "wins", purpose: "Adding fields plus deprecation replaces version numbers, if the schema is treated as a contract." },
    { code: "Caching", name: "costs", codeColor: COLOR.govern, purpose: "A POST to one URL is not stored by shared caches. Persisted GET requests and cache layers recover it." },
    { code: "Query cost", name: "costs", codeColor: COLOR.govern, purpose: "The client chooses the work, so depth, cost and page limits are required." },
    { code: "N+1 calls", name: "costs", codeColor: COLOR.govern, purpose: "A resolver runs once per field occurrence, so batching has to be designed in." },
    { code: "Errors", name: "costs", codeColor: COLOR.govern, purpose: "Most failures arrive as 200, so telemetry has to name the operation and the error code." },
  ], { colW: [2.30, 1.30, 8.49], rowH: 0.52 });
  addCaption(s, "Columns: concern, verdict, why. Each cost has an established answer, and each answer is work.", 6.45);
  addNotes(s, "This table sorts the strengths and costs that follow from putting shape control in the client's hands. On the winning side, a mobile screen and a web dashboard query the same schema and receive different payloads, and a screen that needs a cargo, its legs and its events makes one request instead of five. The schema is machine readable, so tools can validate documents, generate typed clients and diff two versions. Evolution works without a version number because clients name the fields they use. On the cost side, caching is harder because intermediaries key on the method and URL, and a POST to one URL gives them nothing to key on. Query cost moves to the server because the client picks the work. The N+1 pattern appears by construction, and error semantics are different because most failures arrive with a 200 status. Chapter 1 sets out each of these and the chapters that answer them.");
}

fig("DECISION LENS", "Seven decision axes", "02-decision-framework",
  "Figure 2.1 — Seven axes feed one decision per interaction; the shipping domain lands on four answers.",
  "The figure shows the framework this book applies to every topic. The seven axes are client diversity and shape variance, aggregation across sources, read and write balance, caching needs, contract and evolution style, operational and security cost, and team ownership and federation. Applied to the shipping domain they give four different answers. The customer tracking view scores toward GraphQL on nearly every axis: clients are varied and released independently, one screen needs data from three owners, and the traffic is read dominated. Booking a cargo is a command with known inputs and strong idempotency needs, so it stays REST. Internal routing is a service-to-service call with one trusted caller, so it stays gRPC. A partner's nightly bulk feed of forty thousand events fits none of the three and uses a batch channel. The axes are judgements, not measurements, and their value is that disagreements become specific. Chapter 2 develops each axis.");

fig("TOPOLOGY", "The tracking view", "02-tracking-view-topology",
  "Figure 2.2 — The tracking view fronts three sources for reads; writes and bulk feeds take their own paths.",
  "With the decisions made, the architecture follows. Clients reach the tracking view with GraphQL reads. Its resolvers call the booking service for cargo data, the routing service over gRPC for itineraries, and the handling event store for history. Writes such as booking go to the booking service over REST, and partner bulk feeds reach the handling store through their own channel. The tracking view owns no data. Two consequences follow: it can be scaled, redeployed and replaced without a migration, and it depends on the services behind it, which is why its schema marks cross-service fields nullable and why its resolvers must tolerate a missing source. Its schema is its public contract, stored in the repository as one canonical file of SDL and enforced against both implementations. No service behind it has to change to participate. Chapter 2 develops the topology.");

/* ======================= 02 · SCHEMA ======================= */
divider("02", "The schema: SDL and types",
  "The type graph, scalars, wrappers and the contract that keeps two stacks aligned.",
  "Every GraphQL service is described by a schema, and the schema is made of a small set of type kinds. This section reads the canonical SDL for the tracking view kind by kind: the scalars and enums that form the leaves, the object types and the Node interface that connect them, and the wrappers that make a field required or optional. It then shows what a null does when it cannot be returned, and how a canonical schema file keeps two code-first implementations from drifting apart. Nearly every question a client or a reviewer asks reduces to what kind a type is and how it is wrapped.");

fig("TYPE SYSTEM", "The type system map", "03-type-system-map",
  "Figure 3.1 — The tracking view's types by kind. Every leaf of a selection ends in a scalar or an enum.",
  "A schema is a set of named types connected by fields. The figure groups the tracking view's types by kind. The root operation types Query, Mutation and Subscription are the entry points, and everything else is reachable only through them. Object types such as Cargo, Leg and Delivery hold fields. Scalars and enums are the leaves: a selection can never go below them, so asking for a sub-field of a tracking id is rejected. The Node interface is implemented by the types a client can fetch by identity. Input types are the mirror of object types for arguments. The schema has no union, because its one abstract case has a shared field, the id, and an interface fits that better. The canonical SDL is split across six files by ownership, and tools load them as one document. Chapter 3 goes through each kind.");

codeSlide("OBJECT TYPES", "The Cargo object type", "graphql · SDL",
  "contracts/schema/shipping/cargo.graphql", [[4, 8], [17, 32]],
  "A Cargo implements Node. Descriptions are part of the contract; some fields are omitted for space.",
  "The snippet shows the Cargo type as the canonical SDL declares it. Read it as edges: origin and destination lead to Location, delivery leads to the derived Delivery object, and handlingHistory leads to a connection of events. Two nullability choices carry meaning. Delivery is required, because every cargo has a derived state. Itinerary is nullable, and its description says why: the field is null until the routing service has assigned a route, which is absence and not failure. The handlingHistory field takes the four Relay pagination arguments, and its connection type is the subject of the pagination section. Descriptions are part of the contract. Every type, field, argument and enum value in the canonical file has one, tools show them in documentation panels, and the conformance check fails when a served description differs from the canonical text. Chapter 3 reads the whole schema this way.");

fig("SCALARS", "Scalar coercion", "03-scalar-coercion",
  "Figure 3.2 — Three coercions around one internal value. Whatever enters, the output is one canonical string.",
  "A scalar is a leaf, and it is more than a name. GraphQL has five built-in scalars: Int, Float, String, Boolean and ID. The tracking view adds three custom ones. TrackingId and UnLocode are string-backed, and they exist so the schema says what the string is. DateTime carries an instant in UTC, and its definition uses the specifiedBy directive to point at the RFC that defines the format. Each scalar has three functions. Serialize turns an internal value into the response. Parse value turns a JSON variable into an internal value. Parse literal does the same for a value written inline in the document. The input pair exists because an inline argument is a syntax tree node while a variable arrives as already-parsed JSON. Input is where a loose scalar does damage, because a scalar that accepts too much lets two implementations disagree. The figure shows three inputs converging on one canonical output string. Chapter 3 covers coercion.");

fig("NULLABILITY", "Wrapper types", "04-wrapper-matrix",
  "Figure 4.1 — The six wrapper combinations and what each allows in a response.",
  "Two wrappers modify any type. A bang means the value is never null, and square brackets make a list. They nest, and a chain reads inside out. That gives six combinations for a field. A list of nullable items that is itself nullable is the loosest. Each bang removes one case. The legs field of an itinerary is a list of non-null legs that is itself non-null, which is the strongest promise: never null, never containing a null, though it may be empty. The position of the bang matters more than its presence. A null item in a list declared with a non-null list but nullable items leaves a hole in the list. A null item in a list declared with non-null items but a nullable list nulls the whole list. Each framework has its own default for an unannotated type, so a code-first schema can drift in either direction, which the contract check catches. Chapter 4 covers the wrappers.");

fig("NULL PROPAGATION", "Null propagation", "04-null-bubbling-walk",
  "Figure 4.2 — One null climbing from Leg.loadLocation to Cargo.itinerary, the first nullable position.",
  "A null in a non-null position cannot be returned, so it moves up. The figure follows one case. A cargo has a leg that loads at a code the location source does not know. Leg.loadLocation is required, so the leg cannot hold the missing value and the leg becomes null. The legs list holds non-null items, so the list becomes null. Itinerary.legs is required, so the itinerary object would be left without legs. The climb stops at Cargo.itinerary, which is nullable. Everything outside that boundary survives, including the tracking id selected next to the itinerary. Inside it, the voyage selected beside the location is lost even though the voyage service is healthy. The error is recorded once, at the field that failed, so its path ends at loadLocation while the null lands higher. Nullability is therefore a blast-radius setting that the schema author chooses once for every client. Chapter 4 walks through this example.");

fig("CONTRACT", "The contract loop", "05-contract-loop",
  "Figure 5.1 — Code builds the schema, the export makes it a file, and the diff compares it both ways.",
  "A service needs a schema, and it can come from an SDL file or from code. The book keeps both implementations code-first, which is the idiom of each framework, and holds them to one canonical SDL file with a drift gate. Each stack builds its schema from code and exports it as an SDL file. A diff tool compares the export with the canonical file in both directions, because the classification of a change depends on which side is old. Live to canonical catches a stack that exposes something the contract does not. Canonical to live catches a stack that serves something different. The lower lane of the figure shows two gates that apply to the canonical file itself: a linter and a breaking-change check against the main branch. Seeded drifts prove the gate fires: a tightened field, a loosened field, an extra field, a removed enum value and a changed description. Chapter 5 builds the loop.");

/* ======================= 03 · EXECUTION ======================= */
divider("03", "Execution: resolvers, queries, mutations",
  "How a request is checked, how resolvers pass values down the tree, and how a write differs.",
  "A GraphQL server does not run a query the way a database runs SQL. It parses text, checks it against the schema, converts the inputs, and then calls ordinary functions, one per field, in an order the specification mostly leaves to the engine. This section follows that order. Knowing it tells you which calls a selection costs, which of them wait for each other, and what a failed request leaves behind. It then looks at the one write in the schema, the mutation that records a handling event, and at what makes a retry safe.");

fig("EXECUTION", "Three stages before resolvers", "06-request-phases",
  "Figure 6.1 — Parse, validate and coerce run before any resolver. A failure ends the request with no data.",
  "Three stages run before any resolver does. Parsing turns the text into a document and checks only syntax. Validation checks the document against the schema without touching data: every field must exist on its parent, arguments must match their types, fragments must not form cycles, and variables must be declared and used compatibly. Coercion converts each variable to the type its declaration names. A failure in any of the three ends the request with errors, no data and no source calls, and the client can fix the document and retry safely because nothing ran. Only Execute reaches the sources. Validation and parsing need only the document and the schema, which is why later controls such as cost limits and persisted documents attach at these stages. The specification selects the operation by operationName, so a client names it whenever a document holds more than one. Chapter 6 covers each stage.");

fig("RESOLVERS", "The resolver chain", "07-resolver-chain",
  "Figure 7.2 — The parent value feeds the child resolver, the child derives a key, and the key goes to a source.",
  "A resolver is an ordinary function with four inputs and one output: the parent value, the field's arguments, a request context, and information about the field. The figure shows a chain for one query. The cargo resolver reads the cargo from the booking service. The itinerary resolver takes that cargo as its parent and derives a key for the routing service. Each leg's voyage resolver derives a voyage number from its leg and calls the voyage service. The two voyage lookups start together because they are siblings. In the lab each source call takes about a quarter of a second, so four calls in three levels cost about three source windows. The point is that a query's latency is the depth of its tree, not the number of fields. The source-call log makes that visible, listing each call with its request id and start and end time. Chapter 7 builds this chain on both stacks.");

codeSlide("OPERATIONS", "Variables, aliases, fragments", "graphql · documents",
  "_docs/07-queries-and-resolvers.md", [[137, 137], [147, 147], [157, 158], [174, 180]],
  "A variable with a default, two aliases, a fragment, and a directive that prunes fields before they run.",
  "The snippet collects four client tools from the book's queries chapter. A variable lets a document stay fixed while its inputs change, and it may carry a default that belongs to the operation, not to the schema. An alias gives a field another response key, so one document can ask for the same field twice with different arguments, and the alias also appears in an error path. A fragment names a selection set for reuse; after field collection the spread is expanded in place, so the engine sees the same fields as if they were written twice. The last document uses include and skip with a boolean variable. A field excluded by either directive is dropped before execution reaches it, so its resolver never runs and its sources are never called. That is how one document serves a light mobile view and a full desktop view, with the client, not the server, deciding what runs. Chapter 7 shows the source-call log for both runs.", { fontSize: 13 });

fig("MUTATIONS", "A mutation's path", "08-mutation-flow",
  "Figure 8.2 — Coercion belongs to the engine; validation, lookup, append and re-read run in the resolver.",
  "The schema has exactly one mutation, registerHandlingEvent, and it carries most of what a write in GraphQL needs. The input is a typed object, so the engine coerces it before the resolver runs. The resolver then validates domain rules, looks up the cargo, the location and the voyage together, appends the event, and re-reads the cargo so that the payload carries the recomputed delivery state. A refused input does not throw. It comes back as data in a userErrors list, each entry with a stable code, a message and a field path. The payload is the reason the mutation exists in the graph: a terminal app that reports an unload also wants the cargo's new status in the same round trip. An unload at Hamburg moves the cargo from on board a carrier to in port. A client that needs only an acknowledgment selects only the event id, and the delivery is never derived. Chapter 8 covers the write path.");

fig("IDEMPOTENCY", "Idempotent replay", "08-idempotent-replay",
  "Figure 8.3 — The same retry with and without a key. With one, the second request becomes a read.",
  "A mutation changes state, so a retry is dangerous. A client sends a request, the server records the event, the response is lost, and the client sends it again. The input carries an idempotency key, a string the client chooses and repeats on every retry of one intent. A repeated request with the same key returns the originally recorded event instead of recording a second one. The implementation has two steps and the second matters most. The server looks the key up, and then it inserts only if absent, in one atomic step. The lookup alone is not enough, because two requests that arrive together can both miss it. The proof is a race: eight identical requests sent at once return the same event id and produce exactly one append. Without a key, two identical registrations create two events. Top-level mutation fields also run serially, in the order written, which is how a client gets ordered writes. Chapter 8 measures both.");

/* ======================= 04 · ERRORS ======================= */
divider("04", "Errors and partial results",
  "Three kinds of failure, where each lands in the response, and what a client may rely on.",
  "In most APIs a failure is an exception, a status code and an empty body. In GraphQL a failure is usually a field that could not be filled, and the schema's nullability decides how much of the response goes with it. This section separates the kinds of failure, shows a response that is half right, and explains the allowlist that keeps internal detail out of messages while the server log keeps everything. The tracking view fails in three ways, one outage and two unexpected failures, and both stacks answer them with the same shape.");

fig("ERRORS", "Three failure kinds", "09-error-taxonomy",
  "Figure 9.1 — Three kinds of failure and the response each produces; only the first precedes a resolver.",
  "The specification separates failures by when they happen. A request error occurs before execution begins: the document does not parse, fails validation, a variable does not coerce, or the operation cannot be selected. No resolver runs and the response has no data entry. An execution error occurs while a resolver runs. Execution continues, so the response carries data with a null where the field failed, and the error carries a path to that field. A third outcome has no errors at all: a refused input comes back as userErrors, which is ordinary data in a successful response. The origin tells a client what to do next. A request error is a fault in the code that built the document, and retrying fails the same way. An execution error may be transient, as an outage often is. A domain failure was understood and refused, and the user can correct it. Chapter 9 sets out all three.");

fig("PARTIAL RESULTS", "Partial results", "09-partial-data-errors",
  "Figure 9.2 — A path names where it broke, and the null lands at the nearest nullable ancestor.",
  "The strongest argument for the execution-error model is a query that is half right. The figure shows three aliased lookups for three cargos. The first is intact. The second is a cargo whose itinerary has one leg and whose voyage is null, because the voyage service is down. The third is null as a whole, because the handling service failed under a required field and the null climbed to the nearest nullable ancestor. Two errors explain the two holes, and each carries a path to the field that failed, not to the null that resulted. A client that renders what arrived and marks the missing parts serves the user better than one that treats any entry in errors as a failed request. Each alias sits under its own nullable root field, so one failure cannot take another alias with it. The order of entries in the errors array carries no meaning, so a client finds an error by its path. Chapter 9 covers where the null lands.");

codeSlide("ON THE WIRE", "Errors on the wire", "shell · json",
  "_docs/09-error-handling.md", [[215, 215], [219, 219], [225, 225], [230, 230]],
  "An exposed outage keeps its message and gets a code; an unexpected failure is masked and gets no code.",
  "The snippet shows two recorded requests and their responses. The first asks for the itinerary of a cargo whose voyage service is down. The response carries data with the voyage null, and one error. The error has a message a developer can read, locations that point into the document, a path that ends at the failing field, and extensions.code with the value SERVICE_UNAVAILABLE. The code is the part a client acts on, by retrying within a bound or rendering a degraded view. The second request asks for the delivery state of a cargo whose handling service raised an unexpected exception. The message is the generic Internal server error, the path names the field, and no code is exposed. The detail stays in the server log. Messages are for people and may be reworded at any time, so a client branches on the code and the path. Chapter 9 sets out the code vocabulary.", { tag: "On the wire", fontSize: 11 });

fig("MASKING", "Error masking", "09-error-masking",
  "Figure 9.3 — Masking is an allowlist. The client sees only what the service listed; the log sees everything.",
  "An unexpected exception carries whatever its author put in the message: a table name, a shard, a host, a stack. Showing that to a client reveals topology and does not help the client, which cannot repair a shard. The rule has two halves. The client gets a generic message, and the operator gets everything in the server log. Both frameworks implement masking as an allowlist: nothing is shown unless the service listed it, so an exception class added next year is masked by default. A small set of exposed exception classes carries a stable code in extensions, such as SERVICE_UNAVAILABLE for an outage. Everything else becomes Internal server error. The log half deserves the same attention as the response half, because the exception, its stack and the time are what an operator uses later. A message should describe what happened to this request in domain terms and should not carry internals. Chapter 9 covers masking and its tests.");

/* ======================= 05 · DESIGN AND EVOLUTION ======================= */
divider("05", "Schema design and evolution",
  "Designing from demand, identity across the graph, and changing a schema without versions.",
  "Every type, name and nullability marker in the schema is a decision that clients will depend on for years. A field name cannot be changed quietly once a dashboard selects it, and an identity rule cannot be added after caches have been keyed on something else. The patterns that keep those decisions cheap to live with are designing from the screens that ask, giving every object a global identity, and classifying each change by what it can do to an existing client. The section ends with the deprecation lifecycle, which replaces a version number with evidence.");

fig("DESIGN", "Demand-driven design", "10-demand-oriented-schema",
  "Figure 10.1 — One screen, one query, five owners. The panels choose fields; sources answer them.",
  "A schema that mirrors the tables behind it describes the producers. A schema designed from demand describes what the clients ask. The tracking view has one primary client, a screen with three panels: a status header, a route and a timeline. The panels name the fields, and the fields name their owners. The delivery field does not exist in any service. It is derived from the itinerary and the handling events, which is the read-oriented aggregation role of the layer, and the client never learns that two services answered. Demand also decides what stays out. Nothing on the screen reads a price, so the graph has no money type, and no panel creates a booking, so booking writes stay a REST call. A field belongs in the schema when a client reads it, adding one later is safe, and removing one is not. Names follow conventions the checks enforce: PascalCase types, camelCase fields, and suffixes such as Input, Payload and Connection. Chapter 10 covers design.");

fig("IDENTITY", "Global object identity", "10-node-identity",
  "Figure 10.2 — Ids reach a client cache along any path. node and nodes turn any of them back into one object.",
  "A client that caches objects needs a key that identifies an object across the whole graph, not only within a type. The Relay Global Object Identification pattern provides it: an interface Node with an id field, a root field node that fetches any Node by id, and a plural nodes field. In the tracking view cargos, locations, voyages and handling events implement Node, and their ids carry a type prefix such as cargo_ABC123, loc_USNYC, voy_V200E and evt_1. The prefix keeps two types with overlapping keys distinct. The ids are readable, and the contract says they are opaque: a client stores, compares and sends an id back, and never takes it apart, which leaves the server free to change how a cargo is keyed. One testable rule follows, the refetch rule. For any object the graph returns, node with its id returns the same object with the same type. Chapter 10 applies the rule to each implementer.");

fig("EVOLUTION", "Three classes of change", "11-change-classes",
  "Figure 11.1 — Safe, dangerous and breaking changes, each with a fixture and the gate's verdict.",
  "A schema diff tool sorts every change into one of three classes, from the point of view of a client of the old schema. Safe changes cannot break any query that was valid before: a new field, a new optional input field or a newly deprecated field. Dangerous changes keep every old query valid and can still surprise a client at run time. A new enum value is the standard case, because a client with an exhaustive switch meets a value it has never seen. Breaking changes make some valid old query invalid: removing a field, removing an enum value, adding a required input field, or loosening an output field from non-null to nullable. Nullability cuts both ways. For an output, the server promises a value, so tightening is safe and loosening is not. For an input, the client promises a value, so the rule flips. By default the gate fails only on breaking changes and echoes dangerous ones as pull-request annotations. Chapter 11 runs the gate.");

codeSlide("DEPRECATION", "A deprecated field", "graphql · SDL",
  "contracts/schema/shipping/cargo.graphql", [[49, 56]],
  "The replacement ships first; the old field stays fully functional and names its successor.",
  "The snippet shows a correction in the canonical schema. The itinerary exposes the final arrival under finalArrivalTime. An earlier field, finalArrivalDate, holds the same instant under a name that breaks the convention that time fields end in Time. A name cannot be corrected by renaming, because every client that selects it would break. The correction is an addition followed by a deprecation, in that order. The replacement is added first so that clients can move before anything is taken away. Then the old field is marked with the deprecated directive and a reason that names the replacement. The old field keeps working and returns the same instant. A deprecated field is a signal to tools and people, not a behaviour change: introspection reports it, editors strike it through, and generated types flag it. The reason string is what a client author reads, so it should name the replacement and nothing else. Chapter 11 shows the run.", { fontSize: 14 });

fig("DEPRECATION", "The deprecation lifecycle", "11-deprecation-lifecycle",
  "Figure 11.2 — Add, deprecate, observe, then remove with a recorded sign-off.",
  "Deprecation without removal is a note nobody acts on, and removal without evidence is an outage. The lifecycle has four steps. First the replacement is added. Second the old field is marked deprecated with a reason that names the replacement; the gate reports those two steps as one safe change. Third comes the waiting. Operation-level telemetry shows which clients still select the old field, and until that count reaches zero the field stays. Fourth is removal, which fails the gate by default with a message that says what was deleted. That failure is intended, because deleting a deprecated field still breaks any client that never moved. A pull request that removes the field after the usage evidence is in can say so by setting the suppressRemovalOfDeprecatedField rule, which turns the line into a warning and lets the gate pass. The rule is a sign-off recorded in the pull request, not a default. Chapter 11 describes the full lifecycle.");

/* ======================= 06 · DATA FETCHING ======================= */
divider("06", "Data fetching at scale",
  "Pages with cursors, and batching that turns a fan-out into a few bulk calls.",
  "A graph that works on a seed of five cargos has to keep working on data the client does not control. Two problems appear first. A list that was short grows without bound, so its cost depends on data the client does not control, and a page size with a cursor puts a ceiling on it. And a resolver is called once per field occurrence, so a field under a list is called once per item, which turns one request into dozens of source calls. Connections, cursors and DataLoaders are the standard answers to both.");

fig("CONNECTIONS", "Connection anatomy", "12-connection-anatomy",
  "Figure 12.2 — A connection has edges and pageInfo. The edge's node is the one nullable link in the chain.",
  "A connection is the Relay answer to the question of how to return a page of a list. A connection has edges and pageInfo, and an edge has a node and a cursor. The cursor sits on the edge, not on the node, because it names a position in this connection. The pageInfo object answers the two questions a client has after reading a page: is there more in each direction, and where to continue from. The canonical schema adds a nullable total count, because counting is not free and a server that cannot count cheaply may return null. The node is nullable by design. Its description says the node is null when the item failed to resolve, so one bad item nulls its edge instead of the whole page. Without that fuse every non-null position up to the root would lose the page. The ceiling has to hold when the client says nothing, so a request without first or last gets a default page of ten, and none may ask for more than fifty. Chapter 12 builds the connection.");

fig("PAGINATION", "Offset versus keyset", "12-offset-vs-keyset",
  "Figure 12.1 — One insert, two designs. Offset repeats an item; the keyset cursor seeks past it.",
  "Two designs answer the request for the next page. Offset pagination counts: skip the first N rows and take the next M. Keyset pagination seeks: take the rows whose sort key comes after the last key the client saw. Offset fails silently when data changes between two requests. The example reads a history three events at a time. A late event is then registered that sorts into the part already read. A client that asks to skip three and take three now receives one event twice, because everything below the insert moved down one place. A client that sends the cursor of the last event it saw receives the next three with no repeat and no gap. The sort key has to be total, so both connections break ties. The cursor is opaque: a client holds it and hands it back, and the server encodes the key with a version so it can change the contents later. Keyset cannot jump to page forty, which feeds and timelines do not need. Chapter 12 covers both.");

codeSlide("ON THE WIRE", "A page on the wire", "shell · json",
  "_docs/12-connections-and-pagination.md", [[226, 226], [230, 230], [246, 246], [253, 253]],
  "The first page selects edges, pageInfo and totalCount; an oversized page is a coded error.",
  "The snippet shows a recorded exchange against the pagination example. The query selects edges with a cursor and a node, the four pageInfo fields, and the total count. The variables give a page size of two. The response returns two edges, each with an opaque cursor, a next-page flag that is true, a previous-page flag that is false, and a total of six. The cursors are base64 text, and a client never reads them. The second pair shows a request for a page of fifty-one. That argument passes coercion and is still unacceptable, so the server returns an exposed error with the code BAD_USER_INPUT, a message that states the allowed range, a path to the field, and data that is null because the connection is required. The code vocabulary is the same machinery that carries SERVICE_UNAVAILABLE. Chapter 12 lists the checks, including the cursor messages.", { tag: "On the wire", fontSize: 9 });

fig("N+1", "The N+1 fan-out", "13-n-plus-one-fanout",
  "Figure 13.1 — Before batching: one call per field occurrence, 29 in all. Highlighted keys are fetched twice.",
  "The name comes from databases: one query for a list, then one more for each of its rows. A GraphQL server does the same by construction, because a resolver is called once per field occurrence and each call that reads a source is a round trip. The figure counts the calls for a page of four cargos with each cargo's itinerary, legs, voyages, locations and delivery status. One call lists the cargos, four load them, eight read itineraries because both itinerary and delivery read the routing source, four read events, four read voyages, and eight read locations. The total is twenty-nine. Several of those calls ask for the same thing: one voyage is fetched twice because two cargos share a route, and every itinerary is fetched twice because two fields need it. The cost grows with the data, and the client controls the data. Chapter 12 ends on this number, and Chapter 13 takes it apart.");

fig("BATCHING", "Batched loading", "13-batched-load",
  "Figure 13.2 — The same query with one bulk call per level, without changing a field of the schema.",
  "The fix starts from what the engine already does. A field's resolver runs only after its parent has resolved, and siblings run together, so the fields that want the same owner are asked at about the same moment. Instead of one call per field, the server makes one call per owner for all the keys asked at that moment. The same query now costs one list call, one bulk cargo call, one bulk itinerary call, one bulk event call, one bulk voyage call and one bulk location call, with small variations in grouping by engine. The number of calls follows the number of fields in the selection and not the number of cargos: a page of two and a page of five give the same totals. A call waits for the call its keys come from, because those keys are in its results, and calls whose keys come from the same place run together. The schema does not change at all. Chapter 13 shows the counts.");

fig("DATALOADER", "The DataLoader tick", "13-dataloader-tick",
  "Figure 13.3 — Loads queue during a tick, one bulk call follows, and the next level starts when it returns.",
  "The tool that implements batching is the DataLoader, an idea from 2010 that was published in 2015 as a JavaScript library. Its contract is small. Keys go in and values come out in the same order. Not found is a value, so an unknown key gets null at its position with no error. A key's slot may hold a failure. Keys are deduplicated and cached within a request, and the cache lives only as long as the loader. That last point carries a safety rule: a loader belongs to one request, because a cache that outlives a request serves stale data to the next one. A loader also has to decide when to stop collecting keys and make the call. Each implementation answers with a tick, a point in execution when every field at this level has already asked. In an event-loop runtime it is the loop's next turn. In an engine that executes level by level it is the engine's dispatch of a level. The figure is drawn from a recorded source-call log. Chapter 13 explains both.");

/* ======================= 07 · PERFORMANCE AND SAFETY ======================= */
divider("07", "Performance and safety",
  "Limits on what one document may cost, documents sent by hash, and caches in four places.",
  "Three topics make an open endpoint affordable. A query of a few hundred bytes can fan out across thousands of backend calls, so the server bounds the selection with depth, alias and cost limits that refuse before any source is called. The same document is sent again and again, so a hash can replace the text, which also turns a read into a GET that shared caches can store. And answers can be kept in four places, each with its own key and its own way of losing an entry. Each topic answers the caching and the operational cost axes together.");

fig("LIMITS", "The limit pipeline", "14-limit-pipeline",
  "Figure 14.2 — Where each limit fires. Every refusal ends before the sources are reached.",
  "A request passes through the stages of the execution algorithm, with the HTTP layer in front, and each limit belongs at the earliest stage that has the information it needs, because an earlier refusal does less work. The body size is checked at the HTTP layer. The token count is checked at parse. Depth and alias counts are validation rules. The cost calculation runs just before execution. The page cap is the exception, since it needs the resolver's own argument check, and it still fires before the first source call. Everything left of resolve sees only the document and the variables, which is why those limits can refuse a request without waiting for any resolver. Depth and cost answer different questions, so both exist. Depth bounds the shape of the text and the recursion in the engine. Cost bounds the work, which depends on page sizes. The two engines count depth slightly differently, and the figure shows lanes that refuse the same documents. Chapter 14 builds the pipeline.");

fig("COST", "Cost accumulation", "14-cost-accumulation",
  "Figure 14.3 — The nested query priced bottom-up: 385,151 units. The four-cargo query of Chapter 13 is 53.",
  "The cost model has one rule, applied bottom-up. A field costs one unit plus a multiplier times the cost of its children. The multiplier is the page size on a paginated field, the number of ids on the nodes field, and one everywhere else. Introspection fields are free, and a field excluded by a skip or include directive costs nothing. Applied to the nested query from Chapter 1, with every page at the ceiling, the innermost id costs one, and each paged level multiplies everything beneath it by fifty, so the whole query is priced at 385,151 units. The four-cargo query from the batching section is 53. The budget in the example is a thousand units, and the choice is as arbitrary as a timeout: measure queries against their cost and set the budget a little under the point where the 99th percentile crosses the response time you promise. A client that hits the edge gets a message with both numbers, so it can halve its page and retry. Chapter 14 shows the boundary.");

fig("PERSISTED DOCUMENTS", "The APQ handshake", "15-apq-handshake",
  "Figure 15.1 — A miss, a registration, and a hit by GET, with request and response sizes in bytes.",
  "Automatic Persisted Queries replace a document with its hash. The protocol has one extension, persistedQuery, with a version and the hexadecimal SHA-256 of the exact query text. A client walks three cases the first time it sends a document. It sends the hash alone, and the server answers with a not-found error. It repeats the request with the hash and the text, and the server recomputes the hash, stores the text under it and executes. From then on the hash alone is enough. The server never trusts the hash it receives, so a mismatch between hash and text is refused and nothing is stored. A hash buys three things: bytes on the wire, with a 624-byte request body falling to 163 bytes for one example document; a URL that a cache can key, since the hash fits in a GET; and, in a different arrangement, an allowlist. A GET carries only queries, and the hash-only form is an Apollo convention on top of the standard parameters. Chapter 15 follows the handshake.");

fig("PERSISTED DOCUMENTS", "APQ and trusted documents", "15-apq-vs-trusted",
  "Figure 15.2 — APQ and trusted documents compare on who registers and what the server accepts.",
  "The same hash supports two different arrangements, and they answer different questions. In automatic persisted queries, any client registers a document at run time, and the server accepts anything that matches its own hash. That is a bandwidth and caching tool and not an allowlist, so the store must be bounded and cost limits remain necessary. In trusted documents, registration moves to the build. The client's build extracts its operations, computes their hashes and publishes a manifest, and the server loads the manifest at start and treats it as the whole truth: it runs what the manifest lists and refuses everything else. That works when you control the clients, and it cannot protect a public interface whose operations are not known in advance. A client that cannot register has no registration miss, so a cold cache sees the same short URL as a warm one. A manifest is a deployment artifact: it deploys before the client, hashes are never removed while a live client sends them, and every document gets an operation name. Chapter 15 compares the modes.");

fig("CACHING", "Four cache layers", "16-cache-layers",
  "Figure 16.1 — Four places to keep an answer, nearest the caller first, with the key and the eviction of each.",
  "A GraphQL service has four places where an answer can be kept. The client's normalized cache stores objects by type name and id, so a response for one query updates the objects another query shows. The edge keeps whole responses by method and URL, and persisted GET requests are what make that layer usable. The server's field caches keep what a source returned, by the source's own key, and they sit under the loaders. The sources are the owners and the system of record, and every other layer is a copy of what they said. A cache is derived data: it can be thrown away and rebuilt, and the only question is how stale a copy may be before someone is harmed. Each layer answers with a time limit, an event, or both. The server does not cache whole responses, for three reasons: the key is large, invalidation cannot see inside a stored blob, and the edge already does it for public reads. Chapter 16 covers the layers.");

fig("CACHING", "The Cache-Control decision", "16-cache-policy-decision",
  "Figure 16.3 — Four tests, and any no ends in no-store.",
  "Cache-Control is the server's statement about who may keep a response and for how long. GraphQL has no per-URL answer, because one path carries every document, so the decision looks at the operation and the result. The figure shows four tests in order. The request must be a GET. It must carry no Authorization header. The result must have no errors. And the operation must select only reference data. Only locations and voyages count as reference data, facts about the world that change on a timescale of days, and the policy for them is public with a max-age of five minutes. A cargo's delivery status changes with every handling event, so a cargo is never public. The policy is allowed to be wrong in the safe direction, since a response it calls no-store costs one more request. A TTL alone is not enough for a user who has just registered an event, so a write evicts the cargo's entry after the append and before the payload re-reads, and the TTL stays as the backstop. Chapter 16 builds the policy.");

/* ======================= 08 · SECURITY ======================= */
divider("08", "Security",
  "Transport, the schema map, and who may see which operation, object and field.",
  "A GraphQL request carries the same credentials a REST request does, to a single URL, and the endpoint accepts arbitrary documents. The controls follow here in the order a request meets them. The transport has to give confidentiality and integrity. The schema is queryable by default, so the public instance stops describing itself while internal tools keep introspection. Then identity: the server validates a token from an identity provider, keeps only the identity, and applies authorization at three layers, with different answers for fields and for objects.");

fig("TRANSPORT", "The hardened request path", "17-hardened-request-path",
  "Figure 17.1 — The gates in front of a public instance. A refused request makes no source call.",
  "The figure lays out the gates a request meets in front of a public instance, in order. TLS 1.3 gives the client the right server, keeps the exchange private and detects changes, and every other control assumes it. A content-type check accepts only JSON request bodies, because a browser can send text, form and multipart posts across origins without a preflight, and JSON is the content type that forces one. A CORS policy lists the one origin the product needs and nothing else. A body size limit and a parser token limit bound the cost of reading a request before any GraphQL rule runs. Introspection is refused on the public instance, and field suggestions are switched off so an error message does not teach the schema. Every refusal here happens before a source is called. The document-level refusals answer 200 with an errors array and no data, while the HTTP-level gates send their own status codes. Chapter 17 builds the gates.");

fig("INTROSPECTION", "Public and internal endpoints", "17-public-vs-internal-endpoints",
  "Figure 17.2 — One image, deployed twice. Only the internal instance answers a schema query.",
  "Introspection lets any client ask a schema for its types, fields and arguments. It is how editors complete a query and how a code generator reads the contract, and it is also a map of the territory for a caller with no business knowing it. The decision is made by instance. Anonymous callers get no introspection, while your own tools in CI and on developer machines need it. The figure shows one image deployed twice, with environment settings that differ. The public instance refuses the schema and type root fields, with errors and no data, and its __type answer is the same for a known and an unknown type name. The internal instance is not reachable from the internet and answers introspection, which is where the contract check points. The schema document served at a path and a browser IDE are two more doors, and each is switched off on the public instance. A schema that clients must not enumerate is still a schema the build has to read. Chapter 17 covers the switch.");

fig("AUTHORIZATION", "Authorization layers", "18-authorization-layers",
  "Figure 18.2 — Three layers. An operation or a field refuses with a coded error; an object refuses with a null.",
  "Authentication answers who the caller is, and authorization answers what that caller may do. The figure shows three layers. An operation rule decides whether a call is allowed at all: reading a cargo needs a signed-in caller, and registering a handling event needs the operator role. An object rule decides which objects a caller sees. A shipper sees only its own cargos, and the rule lives in one place, the source that every path to a cargo reads, so there is no per-resolver check to forget. A field rule decides which fields a role reads, such as the registration time of an event, which only operators read. Identity enters through a validated token. The server checks the signature against the issuer's key set, the issuer, the audience and the expiry, and keeps only the identity in the request context, never the token. Two codes tell a client what to do: UNAUTHENTICATED means sign in, and FORBIDDEN means a login will not help. Chapter 18 builds the layers.");

fig("AUTHORIZATION", "Errors versus nulls", "18-errors-vs-nulls",
  "Figure 18.3 — Fields: error. Objects: null. A refused object looks like one that does not exist.",
  "The two answers differ by design. An object that is not yours is better as a plain null, because an error would confirm that it exists. A shipper who asks for another shipper's cargo gets the same answer as for an unknown tracking id, so the response does not say which ids exist. A field is the opposite. The field is in the schema and any client can see it there, so there is nothing to hide, and a null would be ambiguous. A client that receives null for the registration time cannot tell not allowed from no value. An error with the code FORBIDDEN at the field's path gives the client something to act on. The null from a required field then lands at the nearest nullable parent, which is the edge's node, so the page and its cursors survive. A nullable field could return null instead, but that turns an access decision into data that looks like a fact about the cargo. Responses that depend on the caller must not be reused for another one, which is why shared caches hold reference data only. Chapter 18 shows both.");

/* ======================= 09 · OBSERVABILITY AND FEDERATION ======================= */
divider("09", "Observability and federation",
  "Seeing inside one endpoint, and splitting one schema across teams without splitting the graph.",
  "Two concerns grow with the system. Every request hits one route and most failures answer 200, so the URL and the status describe nothing finer than the endpoint. The telemetry has to name the operation, the field and the error code. And one team cannot own the schema forever: once several teams each want to contribute types, a single owner becomes the queue. Federation moves the queue by letting each team own a subgraph that a gateway composes into one supergraph that clients query.");

fig("OBSERVABILITY", "The one-endpoint blind spot", "19-one-endpoint-blind-spot",
  "Figure 19.1 — The same nine requests, keyed two ways. The operation name and error code separate them.",
  "An access log and a latency histogram keyed by URL and status describe a POST to the GraphQL path and nothing finer. A page of cargos and a single lookup share the route, the status and the histogram, and a response that carries SERVICE_UNAVAILABLE at one edge is a 200 like all the others. A dashboard built from those two labels cannot tell a healthy service from one that fails a field in every response. The unit that restores the distinction is the operation name. The figure splits nine named requests, first by URL and status and then by operation name and error code. The second view separates traffic that the first one merges. Operation names are not free: an anonymous operation gets the name anonymous in the metrics, and a client that omits names loses the split. Naming is a convention the server cannot enforce without rejecting documents, so it belongs in the client's code generation or lint step. Chapter 19 builds operation-level telemetry.");

fig("OBSERVABILITY", "A span per resolver", "19-span-per-resolver",
  "Figure 19.3 — Twenty-five resolver spans in four levels, and one source call per batch.",
  "One request produces one tree: an HTTP server span, an operation span below it, a span for each resolver that does work, and a span for each call into a source. The figure shows the trace of the four-cargo fan-out from the batching section. It has four levels, and each level is one tick of the batching machinery. Twenty-five resolver spans appear, and the source-call spans are one per batch, so eight location resolvers share a single getLocations span. Reading a trace starts from its root. The slowest resolver span is rarely the answer. The useful question is which level the time sits in and whether the batch below it served many resolvers or one. Here every level costs one source latency, so the query is as slow as its depth, and a shallower selection would be faster where fewer calls would not. The trace id joins the three signals: the caller's traceparent header puts the request in the caller's trace, and the same id links spans, span metrics and log records. Chapter 19 reads the trace.");

fig("FEDERATION", "Subgraph ownership", "20-subgraph-ownership",
  "Figure 20.1 — Each field has one owner. An entity is shared by its key; a reference names a place only.",
  "Federation solves a coordination problem, not a technical one. Each team owns a subgraph, a GraphQL service with its own schema, and a gateway composes the subgraphs into a supergraph. The split follows who owns the data. In the example the cargo subgraph holds cargo, location and voyage, and the handling subgraph holds handling events, the delivery state and the mutation. An entity is an object type that more than one subgraph contributes fields to, and a key directive names the fields that identify it. Cargo is an entity with the tracking id as its key: neither subgraph defines the whole type, and the supergraph merges the two definitions. The handling subgraph needs to say where an event happened without owning locations, so it declares a reference with the key only, which tells the gateway that a location's name must come from the cargo subgraph. Federation pays when the ownership is real, and it costs a composition step and a request across a boundary for every field a team does not own. Chapter 20 builds it.");

fig("FEDERATION", "The query plan", "20-query-plan",
  "Figure 20.3 — One client request, three subgraph fetches. The cargo subgraph is asked twice.",
  "The gateway turns one client query into requests to subgraphs, called a query plan. The figure shows a tracking query that asks for fields from both teams. The root field and everything the cargo subgraph owns come from one request to it. The gateway then sends the cargo's key to the handling subgraph as an entities request for the delivery and the history. Those fields name locations, and only the cargo subgraph knows a location's name, so a third fetch goes back to the cargo subgraph with the locations that handling named. The reference mechanism batches: seven events at three places produce one bulk call, because the entity resolver is a batch resolver. This is the batching idea applied across a network boundary. Composition is a build step that can fail. If the subgraphs disagree about a shared type or key, composition exits with an error and writes no file, so no gateway starts on a graph that does not compose. Chapter 20 reads the plan from the subgraphs' own logs.");

/* ======================= 10 · REAL TIME AND CLIENTS ======================= */
divider("10", "Real time and clients",
  "Four ways to push an event, and what a client library adds over a raw request.",
  "Every operation so far answered a request with a response. The tracking view also has a subscription for clients that want to be told: it emits each handling event for one cargo as it is registered. This section compares the ways to deliver it and then looks at the consumer side. A client library takes on the jobs that curl leaves to the reader: documents that stay matched to the schema, typed results, errors as data, a cache, and a transport.");

fig("PUSH", "Four ways to push", "21-three-ways-to-push",
  "Figure 21.1 — GraphQL columns keep the selection set and schema; the plain feed trades them for resume.",
  "A subscription is a document that stays open. The client sends it once and the server answers with a result for every event, and each result has the shape of the client's own selection set because each event executes that selection. The figure compares four ways to push. A GraphQL subscription over WebSocket is the default for the ecosystem, one socket can carry several subscriptions, and credentials travel in the connection init message. GraphQL over server-sent events carries the same documents over ordinary HTTP with no upgrade. A plain event feed drops GraphQL and gains everything SSE defines: event ids, reconnection in the browser, and a header that lets the server resume. A raw WebSocket needs a protocol of your own. The event path matters: the store broadcasts after the write succeeds and never for an idempotent replay, so any writer reaches a subscriber and a watcher hears each event once. Chapter 21 serves three of the four.");

{
  const s = S();
  addContentTitle(s, "REAL TIME", "Choosing a push transport");
  addStatusTable(s, [
    { code: "WS subscription", name: "GraphQL over WebSocket", purpose: "Clients want different fields per event, or one socket serves several operations. Credentials go in the init message." },
    { code: "GraphQL SSE", name: "GraphQL over HTTP stream", purpose: "The selection set is needed and every hop must pass a long-lived HTTP response. Ordinary headers carry the token." },
    { code: "Plain SSE", name: "Fixed-payload event feed", purpose: "Every client wants the same few fields, or the client must resume after a drop with a last-event id." },
    { code: "Raw WebSocket", name: "A protocol of your own", purpose: "Two-way, high-frequency traffic that is not graph shaped. The framing and acknowledgements are yours to design." },
  ], { colW: [2.60, 3.20, 6.29], rowH: 0.82 });
  addCaption(s, "Columns: transport, what it carries, when to choose it. The forthcoming WebSockets title covers raw WebSockets in depth.", 6.00);
  addNotes(s, "Three questions decide most cases. Does the client need a selection? If different clients want different fields of each event, or the payload is a graph that reaches across services, a GraphQL transport saves a second round trip per event. If every client wants the same few fields, a plain feed is simpler to write, to cache and to read in a log. Does the client need to resume? The feed does it with a header and the server's store. A GraphQL subscription does not, so a client that cannot afford to miss events pairs it with a query for the missed range, or uses the feed. And what sits between the client and the server? A WebSocket needs every hop to pass the upgrade, SSE needs every hop to pass a long-lived response without buffering, and a browser WebSocket cannot set request headers. Raw WebSockets are worth their cost for two-way, high-frequency traffic such as chat or trading. The forthcoming WebSockets book in this series covers them in depth. Chapter 21 compares the choices.");
}

fig("CLIENTS", "The normalized cache", "22-normalized-cache-update",
  "Figure 22.2 — Two requests leave the client; the second query is answered from the first one's entry.",
  "A client that stores each response whole can reuse only a response that repeats the request exactly. A normalized cache stores objects instead. Because every Node has a stable id, the cache keys any object that has an id and a type name by the pair, such as Cargo and its id. A response is flattened into those entries, and a field that holds an object becomes a reference to its entry. The figure follows three operations. The first query asks for a cargo with its locations and delivery fields. A second query asks for a subset of that on the same root field and is answered from the entry the first one wrote, with no request. A mutation payload that returns the changed cargo with its id updates the same entry, and every view that reads it updates. Two requests leave the client for three operations. Partial results are data a client keeps, and it branches on the error code. Each client also names itself with a header, which is what the deprecation telemetry counts. Chapter 22 builds this.");

/* ======================= 11 · TESTING AND DEBUGGING ======================= */
divider("11", "Testing and debugging",
  "Six test layers, and a path from a client's report to the cause.",
  "A GraphQL response is 200 for almost everything, so a test that checks the status line passes for every failure the chapters on errors and nulls described. A GraphQL test reads the body: data beside errors, the error's path, its code, and which nullable ancestor became null. The layers below give fast, readable failures, and the second half takes on the reverse problem. A problem report arrives as a response that looks fine from the transport's side, with a hole in the data and an error that says little. The diagnosis path turns that report into a cause.");

fig("TESTING", "Six test layers", "23-test-layers",
  "Figure 23.1 — Six layers: three run in each stack's test image, three against the live stacks.",
  "The layers trade fidelity for speed, and the cheapest layer that can see a failure should report it. The figure names six. Schema tests check the schema each stack builds. Resolver unit tests call a resolver with a stubbed source. Operation integration tests send documents through the application's own HTTP layer. Contract tests compare the exported and the live SDL with the canonical file. Client document tests run the clients' own documents against the contract. A load run asserts counts per request and not latency. Putting every assertion at the top layer makes a suite slow and its failures hard to read: a failed load check says that something differs, and a failed unit says which rule. The count of source calls is treated as an output, because no response says how many calls produced it, and a resolver that fetches one cargo at a time returns the same JSON at a larger bill. Under load, batching, cost refusals and idempotency are asserted per request. Chapter 23 builds the layers.");

fig("DEBUGGING", "The diagnosis path", "24-diagnosis-path",
  "Figure 24.1 — One masked error followed to the data, through the trace id, the trace and the log.",
  "A masked error says only Internal server error, which is the masking rule doing its job. The operator still has to find the exception, and the client's report has to carry something that leads to it. That something is the trace id, which every execution error carries in its extensions: it is the id the caller sent in traceparent, or a new one if none was sent. The id is not a secret, and reading the trace takes access to the observability backend. The path is a checklist. Read the response first: an error with a path is an execution error, and one without a path was rejected before execution. Read the path and the code. Take the trace id. In the trace, find the resolver span in error status and read the exception type and the source calls under it. Query the log store by the same id for the exception message and the data in it. Reproduce once in a development instance and keep a test that fails without the fix. A debugger comes last, for the one value that observation could not explain. Chapter 24 follows the path.");

/* ======================= 12 · RUNNING IT ======================= */
divider("12", "Running it, and the final project",
  "One tier in containers, the same images on a cluster, and all the controls working together.",
  "The section on running it, and the final project, moves from single techniques to the whole service. Something has to terminate TLS, something has to refuse a body that is too large, the service has to start after the things it depends on, and an operator has to be able to read what the engine was told to do. None of that is GraphQL, and all of it decides whether the GraphQL service is reachable and diagnosable. The section runs the tier in containers, moves the same images onto a cluster, and then combines every control from the other sections in a final project.");

fig("RUNNING IT", "Compose to Kubernetes", "26-compose-to-kubernetes",
  "Figure 26.1 — Compose concepts and the chart templates that carry them; images and environment match.",
  "Every concept in a compose file has a counterpart in Kubernetes, and the counterparts are not always one to one. The figure lists them with the file each lives in. A compose service becomes two objects: a Deployment that keeps the desired number of pods running and rolls out a new version, and a Service that gives them one stable name. Start order expressed as health conditions has no direct counterpart, because Kubernetes starts everything at once and lets readiness decide who receives traffic. The restart policy moves from the engine to the kubelet, and the internal network becomes a network policy. One chart serves both stacks. The images, the environment contract and the edge configuration are the same in both tiers, so every difference between the tiers lives in configuration. A service that runs the same way in a local compose project and in a cluster has put its differences where they belong, in values a platform owner can read. Chapter 26 moves the tier.");

fig("FINAL PROJECT", "The final architecture", "27-final-architecture",
  "Figure 27.1 — The final project's compose tier. Each component implements one pattern from the deck.",
  "The final project combines everything. The public instances of both stacks are reached through an edge, and they publish nothing themselves. Each stack also runs a second time from the same image as an internal instance, with introspection on, published to the loopback address only. An identity provider issues the tokens. An observability image receives the telemetry. Two more services sit behind compose profiles and start only when a script runs them: a subscription client and a load runner. Each component implements one pattern from the deck. The batched sources and the source-call log come from data fetching, the document limits from performance and safety, the introspection switch and the authorization rules from security, the spans and the trace id from observability, and the subscription and the event feed from real time. The complete schema is proven equal to the canonical SDL on both stacks. Chapter 27 wires the tier.");

fig("FINAL PROJECT", "Request defences in order", "27-request-defences",
  "Figure 27.2 — The defences in the order a request meets them, and the answer each gives.",
  "A request that reaches the tier meets a fixed sequence of decisions, and each decision has its own answer when it refuses. The first three belong to the edge and the identity layer. A client limited to an old TLS version cannot finish the handshake. A body over the size limit gets a 413 from the edge, and the source-call log stays empty because the request never arrived. A token for another audience gets a 401 before any GraphQL runs. The next three belong to the document and run before any authorization rule. An anonymous request with a document priced at 7,651 against a budget of 1,000 is refused the same way an operator's would be, with a message that states the price and no source call. The last group runs inside the operation: an anonymous caller gets UNAUTHENTICATED, a shipper asking for another shipper's cargo gets null, and a shipper asking for an operator-only field gets FORBIDDEN. The order matters. The cost check runs before authorization, so a refusal for cost needs no knowledge of who the caller is. Chapter 27 lists the values.");

{
  const s = S();
  addContentTitle(s, "DECISION", "The decision axes, applied");
  addStatusTable(s, [
    { code: "Shape variance", name: "One graph", purpose: "Clients choose the selection and the transport: queries, subscriptions or the event feed, through one edge." },
    { code: "Aggregation", name: "Batched calls", purpose: "Per request, the same keys reach the owners whatever the load, and a refused request makes no call." },
    { code: "Read and write", name: "Reads dominate", purpose: "One mutation with a role rule. Booking and bulk feeds stay with their owners." },
    { code: "Caching", name: "Reference data only", purpose: "Shared caches hold locations and voyages. An answer that depends on the caller stays private." },
    { code: "Contract", name: "One schema", purpose: "The canonical SDL equals what both stacks serve, and introspection stays on internal instances." },
    { code: "Operations", name: "Layered refusal", purpose: "The edge refuses what is cheap, document limits refuse what is expensive, identity decides the rest." },
    { code: "Ownership", name: "One owner", purpose: "One team owns the schema until review volume justifies subgraphs." },
  ], { colW: [2.60, 2.40, 7.09], rowH: 0.56 });
  addCaption(s, "The decision axes, run against the whole system.", 6.15);
  addNotes(s, "The chapter closes by running the seven decision axes against the finished system. Shape variance is settled by one graph that carries queries, a subscription and an event feed through one edge, so a client chooses the transport its environment allows. Aggregation is the batched calls under authorization: the same keys per request whatever the load. The read and write balance holds, with one mutation guarded by a role and booking left with its owner. Caching stays narrow, because a response that depends on the caller's token is private and a shared cache holds reference data only. The contract is the complete schema, proven equal to the canonical SDL on both stacks, with introspection kept for the instances that need it. Operational cost is paid in layers: the edge refuses what is cheap to refuse, the document limits refuse what is expensive, and identity decides the rest. Ownership stays with one team until review volume justifies federation. Chapter 27 states this decision.");
}

/* ======================= APPENDIX ======================= */
{
  const s = pres.addSlide({ masterName: "SECTION" });
  pageNum += 1;
  addSectionDivider(s, "A", "Appendix",
    "Reference listings and a glossary, to keep open in another window.", { onMaster: true });
  addNotes(s, "The appendix is reference material: the canonical root types, the mutation input and payload, the derived delivery type, the error code vocabulary and a glossary of terms. Keep this section open in a second window rather than reading it from start to finish.");
}

codeSlide("APPX · REFERENCE", "The Query type", "graphql · SDL",
  "contracts/schema/shipping/schema.graphql", [[10, 28], [49, 49]],
  "The cargo and cargos entry points with every pagination argument; location, voyage, node and nodes follow.",
  "The root Query type holds the read entry points of the tracking view. The cargo field looks up one cargo by tracking id and returns null when none exists. The cargos field lists cargos newest first as a Relay connection, with forward and backward pagination arguments and a routing status filter. The location and voyage fields look up reference data by code and number. The node field fetches any object by global id, and nodes fetches several in the order given, with null at the position of an unknown id. Everything else in the schema is reachable only through these fields and through the mutation and subscription roots.");

codeSlide("APPX · REFERENCE", "Root operation types", "graphql · SDL",
  "contracts/schema/shipping/schema.graphql", [[1, 5], [54, 60], [65, 71]],
  "One mutation and one subscription. Writes belong to the owning services, so the write surface stays small.",
  "The schema block binds the three root operation types. Mutation has a single field, registerHandlingEvent, whose description says domain failures are returned in userErrors. The write surface is small because writes belong to the owning services, and this one exists because the caller wants the recomputed cargo back in the same round trip. Subscription has a single field, cargoHandled, which emits each new handling event for one cargo as it is registered. The two roots show the other two operation types beside queries: a mutation changes state and runs its top-level fields serially, and a subscription holds a connection open and executes its selection for each event.");

codeSlide("APPX · REFERENCE", "Input and payload", "graphql · SDL",
  "contracts/schema/shipping/handling.graphql", [[60, 73], [78, 85]],
  "The mutation's input and its payload, whose userErrors list carries a refused input as data.",
  "The input type holds the cargo's tracking id, the handling type, the location code, an optional voyage number, the completion time, and an optional idempotency key. The payload type has three fields: the recorded event, the cargo with its recomputed delivery, and the userErrors list. On success the first two are set and the list is empty. On a refusal it is the other way around. A UserError carries a stable code a program can switch on, a message a person can read, and a field path that names the input field, which is null when the failure concerns the whole input. Descriptions are omitted here for space.");

codeSlide("APPX · REFERENCE", "The Delivery type", "graphql · SDL",
  "contracts/schema/shipping/cargo.graphql", [[105, 120]],
  "Derived state: no service stores it. The tracking view computes it from the itinerary and the handling events.",
  "Delivery is the derived state of a cargo, and no single service holds it. The tracking view computes it from the itinerary and the handling events, which is why the tracking view owns the rule and takes on the dependency. Four fields are nullable for stated reasons. The last known location is null before the first handling event. The current voyage is null unless the cargo is aboard a carrier. The estimated arrival is null when no estimate is available. The next expected activity is null when none is expected. The transport status, routing status and misdirected flag are always present.", { fontSize: 13 });

{
  const s = S();
  addContentTitle(s, "APPX · REFERENCE", "Error code vocabulary");
  addStatusTable(s, [
    { code: "SERVICE_UNAVAILABLE", name: "exposed", purpose: "A source owner is down. Retry within a bound, or render a degraded view." },
    { code: "BAD_USER_INPUT", name: "exposed", purpose: "An argument passed coercion and is still unacceptable, such as an invalid cursor or page size." },
    { code: "UNAUTHENTICATED", name: "exposed", purpose: "An anonymous caller reached an operation that needs a signed-in one." },
    { code: "FORBIDDEN", name: "exposed", purpose: "A signed-in caller lacks the required role for an operation or field." },
    { code: "PERSISTED_QUERY_NOT_FOUND", name: "protocol", purpose: "The server holds no document for the hash. Send the text with it." },
    { code: "PERSISTED_QUERY_REQUIRED", name: "protocol", purpose: "A trusted-document instance accepts only documents in its manifest." },
    { code: "(no code)", name: "masked", purpose: "Anything unexpected. The message is generic and the detail stays in the log and trace." },
  ], { colW: [4.10, 1.60, 6.39], rowH: 0.55 });
  addCaption(s, "Codes are contract and messages are not. A new code is reviewed like a new enum value.", 6.15);
  addNotes(s, "This table collects the execution-error codes the book uses. The first four are exposed errors: the service lists them, declares a stable code, and shows their messages. SERVICE_UNAVAILABLE and BAD_USER_INPUT come from the data and argument chapters, and UNAUTHENTICATED and FORBIDDEN come from authorization. The two persisted-query codes belong to the protocol. Anything unexpected is masked with a generic message and no code. The codes are contract and the messages are not, so a new code follows the same evolution rules as an enum value: adding one is safe for a client with a default branch and breaks one without it. Refused inputs use the separate UserErrorCode enum inside the payload. Behind a federation gateway the router uses INTERNAL_SERVER_ERROR for an unexpected failure.");
}

{
  const s = S();
  addContentTitle(s, "APPX · GLOSSARY", "Terms used in this deck");
  addTwoColBullets(s,
    [
      { text: "Connection", options: { bold: true, bullet: false } },
      "A page of a list: edges, each with a node and a cursor, plus pageInfo.",
      { text: "Cursor", options: { bold: true, bullet: false } },
      "An opaque position in a connection that a client hands back as after or before.",
      { text: "DataLoader", options: { bold: true, bullet: false } },
      "A per-request batcher: keys in, values out in order, deduplicated.",
      { text: "Entity", options: { bold: true, bullet: false } },
      "A federated object type that several subgraphs contribute fields to, shared by its key.",
      { text: "Fragment", options: { bold: true, bullet: false } },
      "A named, reusable selection set with a type condition.",
      { text: "Null propagation", options: { bold: true, bullet: false } },
      "A null in a non-null position moves up to the nearest nullable parent.",
    ],
    [
      { text: "Persisted document", options: { bold: true, bullet: false } },
      "A document the server resolves from a hash instead of receiving its text.",
      { text: "Resolver", options: { bold: true, bullet: false } },
      "The function that produces one field's value from a parent and arguments.",
      { text: "Selection set", options: { bold: true, bullet: false } },
      "The fields a client names inside braces, which also shape the response.",
      { text: "Subgraph", options: { bold: true, bullet: false } },
      "One team's GraphQL service, composed with others into a supergraph.",
      { text: "Supergraph", options: { bold: true, bullet: false } },
      "The composed schema a gateway serves to clients.",
      { text: "userErrors", options: { bold: true, bullet: false } },
      "Refused inputs returned as typed data in a mutation payload.",
    ],
    { fontSize: 11.5, h: 4.7 });
  addNotes(s, "The terms used across the sections, one sentence each. Connection, cursor and DataLoader are the paging and batching terms. Entity, subgraph and supergraph are the federation terms. Fragment, resolver and selection set describe how a document maps onto execution. Null propagation, persisted document and userErrors name the three mechanisms that the errors, performance and mutation sections build on. Keep this page open if a term from one of the sections comes up again later without being redefined.");
}

/* ======================= CLOSING ======================= */
{
  const s = S();
  addContentTitle(s, "WRAP-UP", "What to take away");
  addBullets(s, [
    "**Choose per interaction.** Seven axes decide where GraphQL fits next to REST and gRPC.",
    "**The schema is the contract.** One canonical SDL, enforced against every implementation in both directions.",
    "**Failures are partial.** Nullability sets the blast radius, and codes and paths tell a client what to do.",
    "**Evolve by addition.** Deprecate with evidence, and gate every change by class.",
    "**Bound the work.** Page caps, batching and cost limits refuse before a source is called.",
    "**Defend in layers.** Edge, document limits, then identity, with telemetry that names the operation.",
  ].map((t) => ({ text: t.replace(/\*\*/g, ""), options: {} })), { fontSize: 17 });
  addCaption(s, "The Quarkus and Python decks show each pattern in code.");
  addNotes(s, "Six points carry the deck. First, choose GraphQL per interaction with the seven axes, which leaves booking on REST, internal routing on gRPC and bulk feeds outside the graph. Second, the schema is a contract: one canonical SDL that both implementations are diffed against in both directions, so drift is caught where it starts. Third, failures are partial. Nullability sets how much of a response a failed field takes with it, and error codes and paths tell a client whether to retry, degrade or stop. Fourth, evolve by addition and deprecation, gate every change by its class, and remove a field only with usage evidence. Fifth, bound the work: page ceilings, batching and cost limits refuse or shrink a request before any source is called. Sixth, defend in layers, with the edge refusing what is cheap, document limits refusing what is expensive and identity deciding the rest, while telemetry names operations and error codes. The Quarkus and Python decks show each of these patterns in code.");
}

{
  const s = S();
  addContentTitle(s, "THANK YOU", "Q&A");
  addBullets(s, [
    "Questions on any pattern: the decision axes, execution, errors, evolution, batching, cost limits, security, observability or the final project?",
    "The Quarkus and Python implementation decks show how each stack builds these patterns against the same canonical schema.",
  ], { fontSize: 17 });
  addCaption(s, "Red Hat is the world's leading provider of enterprise open source software solutions.");
  addNotes(s, "Thank you. That is the whole 100-level arc: where GraphQL fits next to REST and gRPC and the seven axes for choosing it; the type system, nullability and the contract loop; how a request executes and how a mutation differs; errors, partial results and masking; schema design and evolution without versions; connections and batching; cost limits, persisted documents and caching; transport security and authorization; observability and federation; real-time delivery and clients; testing and debugging; and a final project that runs every control at once. The material here was the pattern and the reasoning. When you want the how, the two companion decks take over: one builds each pattern in Quarkus with SmallRye GraphQL and the other in Python with Strawberry, both against the same canonical schema. I am happy to take questions. And the standard Red Hat close: Red Hat is the world's leading provider of enterprise open source software solutions, trusted for support, training and consulting services.");
}


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

  addNotes(s, "This is the 100-level concepts deck, so the two codes point where the ideas live and where the whole series lives. On the left, the site: the chapters, the GraphQL schema and contracts, and the runnable both-stack examples, all public. On the right, the Workshops and Tutorials hub: every workshop, tutorial, and deck in the series in one place, including the REST, gRPC, and WebSockets siblings. Scan whichever is useful; both are on the Pattern Catalyst GitHub organization.");
}


writeDeck(pres, OUT).catch((e) => { console.error(e); process.exit(1); });
