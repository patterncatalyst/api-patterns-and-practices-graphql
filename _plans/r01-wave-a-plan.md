---
layout: plan
render_with_liquid: false
title: "r01 Wave A Plan — Ch3–Ch8 (Schema & Execution)"
---

# Wave A (S6): Ch3–Ch8, Schema & Execution

**Status: APPROVED by user 2026-10-16.**

This plan is for Sonnet executors. Wherever it names a value (port, id, timestamp, path, error code), use exactly that value. Where it says **spike**, check the behaviour before you write prose that depends on it.

**Precondition.** S4 must be done first: Ch0 `verify.sh` green on both stacks, and Ch0 prose in place, because Ch3 refers back to it. If only S4a (the harness and the Ch0 example) is done, Ch3–8 can start. Ch3's prose links to Ch0 by relative URL only, so the link resolves once S4b lands.

**Facts checked against the local jars.**
- Quarkus 3.40.1 brings in SmallRye GraphQL 2.18.5.
- SmallRye maps `java.time.Instant` (and `OffsetDateTime`/`ZonedDateTime`/`LocalDateTime`) to its built-in `DateTime` scalar.
- SmallRye's `DescriptionHelper` contains an `ISO-8601` auto-description path for date fields, so description drift on DateTime fields is a real risk.
- `io.smallrye.graphql.api.DefaultNonNull` and `io.smallrye.graphql.api.Nullable` exist.
- The CDI events `@BeforeDataFetch` and `@AfterDataFetch` exist in `io.smallrye.graphql.cdi.event`.

---

## 1. Approach

### Sequencing (DAG)

| Step | Executor | Owns (exclusive write set) | Depends on |
|---|---|---|---|
| **A0** Harness + contract tooling warm-up | Executor 1 | `examples/_lib/lib.sh`, `examples/_lib/README.md` | S4a |
| **A1** Ch3 (sets the baseline every other example starts from) | Executor 1, right after A0 | `_docs/03-*`, `examples/03-sdl-type-system/**`, `diagrams/03-*.py`, `diagrams/examples/03-*`, `assets/diagrams/03-*` | A0 |
| **A2a** Ch4 | Executor 2 | same pattern for `04-*` | A1 |
| **A2b** Ch5 | Executor 3 | same pattern for `05-*` | A1 |
| **A2c** Ch6 | Executor 4 | same pattern for `06-*` | A1 |
| **A3** Ch7 | Executor 5 | `07-*` | A2c (copies Ch6's async sources and source-call log) |
| **A4** Ch8 | Executor 6 | `08-*` | A3 (copies Ch7's derived `Delivery`) |
| **AV** Validation (Opus) | Opus | read-only findings, then fixes routed back to the owning executor | A2a, A2b, A4 |
| **AW** Wrap (orchestrator) | orchestrator | `_plans/*`, `_example_pages/index.md`, commits | AV |

How to run it:
- A2a, A2b and A2c run in parallel. Their write sets are disjoint, and their ports and compose project names are distinct.
- Ch7 and Ch8 run one after the other. Each copies its predecessor's example, and running them in parallel would mean writing the handling-store and derived-delivery code twice, with the risk that the two copies drift apart.
- Prose for each chapter is written by the same executor that builds its example. A chapter is a single unit.

**Executor rules (same as the gRPC template).**
- Write files only. No git.
- Do not touch `_plans/*`, `coverage-matrix.md`, `_example_pages/`, `contracts/`, `examples/_lib/` (only A0 may), `scripts/`, or any other chapter's files.
- Never delete or reinstall `contracts/node_modules`. A0 runs `npm ci --prefix contracts` once, before any parallel work starts.
- Every executor runs its own `verify.sh` green locally before handing back. It also runs `python3 -I scripts/validate.py` and `bash scripts/wordcount.sh _docs/NN-*.md`.

### Example structure: each example is a self-contained copy (same as the template)

Each `examples/NN-slug/` is a complete, independently buildable copy, started from the previous chapter's example: its own `pom.xml`, `pyproject.toml` + `uv.lock`, Containerfiles, compose, `verify.sh`, README and architecture figure. This is the gRPC choice, for three reasons:
- each CI matrix job and Docker build context covers exactly one directory;
- a reader can open a single directory and see everything that chapter uses;
- a later chapter's change (fault seeds in Ch4, async sources in Ch6) cannot silently change an earlier chapter's verified behaviour.

Package and module names stay the same: Java `com.patterncatalyst.shipping.tracking`, Python `app`. Only these change per chapter:
- the artifactId (`chNN-quarkus-<slug>`)
- the Python project name (`shipping-python-chNN-<slug>`)
- `quarkus.otel.service.name` and `OTEL_SERVICE_NAME` (`chNN-<slug>-quarkus|python`)
- container names

Pins match Ch0 (Quarkus platform 3.40.1, Strawberry 0.335.0, FastAPI 0.143.2, uvicorn 0.54.0, uv 0.13.1, the UBI10 image tags). If a newer stable release exists at execution time, bump it in **all** Wave A examples together, never in just one.

**Rejected alternatives**
- *Shared Maven module / Python package under `examples/_shared`*: it couples the chapters, widens the Docker build contexts, and lets a later edit change an earlier chapter's verified output.
- *One growing example directory with per-chapter git tags*: the CI matrix discovers directories, not tags, and readers lose the per-chapter snapshot.
- *Every chapter starting fresh from Ch0*: it duplicates the `Delivery`/handling work in Ch7 and Ch8, and the executors' code would diverge.

### How the schema slice grows

Every slice must pass `assert_sdl_conforms`. A whole type or whole output field may be absent. Anything the stack does serve must match the canonical SDL exactly, including descriptions, arguments, enum values and input fields.

| Ch | Adds to the served slice | Data behaviour |
|---|---|---|
| 0 | `Query.cargo`; `Cargo{id,trackingId,description,origin,destination}`; `Location`; `Node`; `TrackingId`, `UnLocode` | canned |
| 3 | `Query.location`, `Query.voyage`, `Query.node`; `Cargo.routeSpecification`, `.delivery`, `.itinerary`; `RouteSpecification`, `Itinerary`, `Leg`, `Voyage{id,number,schedule}`, `CarrierMovement`, `Delivery` (all 7 fields), `HandlingActivity`; enums `TransportStatus`, `RoutingStatus`, `HandlingEventType`; scalar `DateTime` | in-memory seed, embedded objects, `Delivery` stored as constants |
| 4 | same types as Ch3 | `Leg.voyage`, `Leg.loadLocation`, `Leg.unloadLocation` and `Cargo.delivery` become resolvers over sources; adds the fault-seed cargos |
| 5 | same as Ch3 (healthy seed only) | adds SDL export plus the seeded drift checks |
| 6 | same types | every source-backed resolver is async with configurable latency; adds the source-call log + `/debug/source-calls` |
| 7 | same types | `Delivery` and `HandlingActivity` derived from `handling.listEvents` + itinerary; `@include`/`@skip`, fragments, aliases |
| 8 | `Mutation.registerHandlingEvent`; `RegisterHandlingEventInput`, `RegisterHandlingEventPayload`, `UserError`, `UserErrorCode`, `HandlingEvent` (all 8 fields incl. nullable `cargo`); `Node` resolution for `evt_*` | in-memory handling store with an idempotency index |

After Ch8 the stacks serve all of `Query` except `cargos` and `Cargo.handlingHistory` (the connection types, Ch12), plus all of `Mutation`. `Subscription` arrives in Ch21. State this explicitly in each README's slice paragraph.

### Canonical seed data (identical on both stacks; Ch3 introduces it, later chapters copy it)

**Locations** (`id` = `loc_<code>`):

| unLocode | name | country |
|---|---|---|
| USNYC | New York | US |
| NLRTM | Rotterdam | NL |
| DEHAM | Hamburg | DE |
| SGSIN | Singapore | SG |
| CNSHA | Shanghai | CN |

**Voyages** (`id` = `voy_<number>`):

| number | schedule |
|---|---|
| V100S | USNYC→DEHAM, departs 2026-10-01T08:00:00Z, arrives 2026-10-09T14:00:00Z |
| V200E | DEHAM→NLRTM, departs 2026-10-10T06:00:00Z, arrives 2026-10-11T18:00:00Z |
| V300A | SGSIN→CNSHA, departs 2026-11-02T04:00:00Z, arrives 2026-11-06T10:00:00Z |

**Cargos** (`id` = `cargo_<trackingId>`):

- **ABC123**, "Palletized electronics", USNYC→NLRTM (Ch0 values are unchanged).
  - routeSpecification: USNYC→NLRTM, arrivalDeadline 2026-10-15T00:00:00Z.
  - itinerary leg 0: V100S, USNYC→DEHAM, load 2026-10-01T08:00:00Z, unload 2026-10-09T14:00:00Z.
  - itinerary leg 1: V200E, DEHAM→NLRTM, load 2026-10-10T06:00:00Z, unload 2026-10-11T18:00:00Z.
  - finalArrivalDate 2026-10-11T18:00:00Z.
  - events: `evt_1` RECEIVE USNYC, completion 2026-09-30T16:00:00Z; `evt_2` LOAD USNYC V100S, completion 2026-10-01T08:30:00Z. registrationTime = completionTime + 5 min.
  - delivery: ONBOARD_CARRIER, ROUTED, misdirected false, lastKnownLocation USNYC, currentVoyage V100S, ETA 2026-10-11T18:00:00Z, nextExpectedActivity {UNLOAD, DEHAM, V100S}.
- **XYZ789**, "Frozen seafood", SGSIN→NLRTM.
  - routeSpecification arrivalDeadline 2026-11-20T00:00:00Z.
  - itinerary `null`, no events.
  - delivery: NOT_RECEIVED, NOT_ROUTED, false, lastKnownLocation null, currentVoyage null, ETA null, nextExpectedActivity {RECEIVE, SGSIN, voyage null}.

**Ch4-only fault seeds** (delivery = XYZ789-style NOT_RECEIVED/ROUTED unless noted):
- **JKL567**, "Machine parts", USNYC→NLRTM. One leg on voyage **V404X**, USNYC→NLRTM. The voyage source *raises* "voyage service unavailable" for V404X.
- **MNO901**, "Textiles", USNYC→NLRTM. One leg whose loadLocation code is **XXBAD**. The location source *returns null* for it (a dangling reference).
- **PQR234**, "Coffee beans", USNYC→NLRTM, itinerary as ABC123. The delivery source *raises* for PQR234.

**Delivery derivation rules (Ch7+).** The "last event" is the one with the maximum completionTime; ties go to the later registration.

| Last event | transportStatus | currentVoyage | nextExpectedActivity |
|---|---|---|---|
| none | NOT_RECEIVED | null | RECEIVE at routeSpecification.origin |
| RECEIVE at L | IN_PORT | null | LOAD at leg0.loadLocation on leg0.voyage (null if there is no itinerary) |
| LOAD at L on V | ONBOARD_CARRIER | V | UNLOAD at the matching leg's unloadLocation on V |
| UNLOAD at L on V | IN_PORT | null | CLAIM at L if L = final destination, else LOAD at the next leg's load on its voyage |
| CUSTOMS | IN_PORT | null | null |
| CLAIM | CLAIMED | null | null |

Other fields:
- lastKnownLocation = the last event's location.
- routingStatus: NOT_ROUTED if there is no itinerary. MISROUTED if leg0.load ≠ origin or lastLeg.unload ≠ destination. Otherwise ROUTED.
- misdirected = the last LOAD/UNLOAD does not match a leg (location + voyage). Always false when NOT_ROUTED.
- ETA = finalArrivalDate when ROUTED and not misdirected, else null.

**DateTime wire format on both stacks:** `YYYY-MM-DDTHH:MM:SSZ` (UTC, `Z`, whole seconds).

### Ports and project names

The proposed `8100 + 10*NN` (Quarkus) / `+1` (Python) scheme is adopted. Every chapter gets a decade block, so nothing collides with Ch0's 8080/8081, the opt-in LGTM ports (3000/4317/4318/9090/3100/3200), or another chapter.
- Within Wave A, 8161 (Ch6 Python) is the ActiveMQ console default. That only matters if a reader runs ActiveMQ locally, so it is accepted.
- Later waves should note 8200 (Ch10, Vault default) and 8300/8301 (Ch20, Consul) in their READMEs.

| Ch | dir | Quarkus | Python | compose `name:` / `PROJECT` | container prefix |
|---|---|---|---|---|---|
| 3 | `03-sdl-type-system` | 8130 | 8131 | `gql-ch03-sdl` | `ch03-sdl-` |
| 4 | `04-nullability` | 8140 | 8141 | `gql-ch04-null` | `ch04-null-` |
| 5 | `05-contract-first` | 8150 | 8151 | `gql-ch05-contract` | `ch05-contract-` |
| 6 | `06-execution-model` | 8160 | 8161 | `gql-ch06-exec` | `ch06-exec-` |
| 7 | `07-queries-resolvers` | 8170 | 8171 | `gql-ch07-resolvers` | `ch07-resolvers-` |
| 8 | `08-mutations` | 8180 | 8181 | `gql-ch08-mutations` | `ch08-mutations-` |

- Container ports stay 8080 on both stacks.
- Keep Ch0's opt-in `observability` profile verbatim. Its README notes "one example's observability profile at a time" because the LGTM host ports are fixed.
- For local non-container runs: `mvn quarkus:dev -Dquarkus.http.port=81N0` and `uv run uvicorn app.main:app --port 81N1`.

**Rejected:** per-chapter random ports (the README curl lines would not be reproducible) and the 9xxx range (it clashes with the gRPC sibling's 90NN scheme on the same machine).

---

## 2. Per chapter

Common to every chapter:
- **Front matter:** `title` (the outline title), `order: N`, `part:` exactly as in the Canonical names table, `description`, `duration: "NN min read"` (words/200).
- **Length:** 2,800–3,400 prose words.
- **Figures:** embedded with `{% include excalidraw.html file="NN-slug" alt="…full sentence description…" caption="Figure N.M — …" %}`.
- **Code pairs:** use `{% include codetabs.html langs="Quarkus|Python" %}` followed by a java fence then a python fence.
- **Last three blocks, in this order:** `## On the wire` (the curl commands plus the exact values `verify.sh` asserts), then the `<div class="callout callout--safe"><p class="callout__title">Decision</p>…</div>` callout naming Ch2's seven axes, then `## Where this goes next`. This is Ch2's layout.
- **Citations:** link the Bibliography as `../../bibliography/`. Cite *GraphQL in Action* by **chapter title**, after checking it against the book's table of contents. Expected titles: ch1 "Introduction to GraphQL", ch3 "Customizing and organizing GraphQL operations", ch4 "Designing a GraphQL schema", ch5 "Implementing schema resolvers", ch6 "Working with database models and relations", ch8 "Implementing mutations".
- **Spec references:** cite the current GraphQL spec by section **name**. Use the current term "execution error" and mention once that older editions say "field error". Cite GraphQL-over-HTTP for status codes and GET.
- **Diagram specs:**
  - figures: `diagrams/NN-slug.py` calling `g.emit` (pattern of `diagrams/02-tracking-view-topology.py`);
  - architecture figure: `diagrams/examples/NN-slug-architecture.py` writing `examples/NN-slug/architecture.{svg,excalidraw}` (pattern of `00-prerequisites-architecture.py`). These are **not** counted in the 89-figure budget.
  - Highlighted nodes use `accent` (light fill), never `ink`.
- **`verify.sh` skeleton:** the Ch0 structure. One `run_stack_check <stack> <url>` per stack, then `PASS` only when both pass. Every chapter's check also includes:
  - `assert_sdl_conforms`;
  - the Ch0 `TrackingId`/`UnLocode` scalar + `specifiedByURL` checks;
  - one `__type` per request (graphql-java rejects repeated introspection fields in one request).

### Ch3: SDL and the type system in depth

**Files:** `_docs/03-sdl-and-the-type-system.md`, `examples/03-sdl-type-system/`.

**H2 outline**
1. *The schema is a type graph* — SDL as a description of named types connected by fields; the root operation types; how the tracking view's six files compose into one schema.
2. *Scalars: built-in and custom* — Int/Float/String/Boolean/ID; `TrackingId`, `UnLocode`, `DateTime`; `@specifiedBy`; coercion in three directions (serialize, parse value, parse literal); why `DateTime` is pinned to `Z`.
3. *Object types and fields* — `Cargo`, `Leg`, `CarrierMovement`; fields as edges; descriptions as part of the contract.
4. *Enums* — closed sets (`TransportStatus`, `RoutingStatus`, `HandlingEventType`); they serialize as names; adding a value is a client concern (forward to Ch11).
5. *Interfaces and `Node`* — abstract types; `possibleTypes`; `__typename`; inline fragments; Relay Global Object Identification and `node(id:)`.
6. *Unions, and why this schema has none* — when a union fits better than an interface; a counterexample only, nothing in the canonical schema.
7. *Lists and non-null wrappers* — `[Leg!]!` read inside-out; full treatment deferred to Ch4.
8. *Input types* — input versus output position; `RegisterHandlingEventInput` shown from the contract; served in Ch8.
9. *How a selection maps onto types* — the walk from the query text to types to the response shape (Figure 3.2).
10. *Code-first on two stacks* — the SmallRye vs Strawberry idioms below.
11. On the wire / Decision / Where this goes next.

**Slice:** as in the table above, healthy seed (ABC123, XYZ789). Objects are embedded in Ch3: legs hold `Location` and `Voyage` objects directly. The only resolvers are the Query fields.

**verify.sh assertions (both stacks)**
1. Full `cargo(trackingId:"ABC123")` selection over every served field returns exactly the seed values:
   - routeSpecification.arrivalDeadline = `2026-10-15T00:00:00Z`;
   - `itinerary.legs` length 2, leg 0 = {V100S, USNYC, DEHAM, `2026-10-01T08:00:00Z`, `2026-10-09T14:00:00Z`}, leg 1 = {V200E, DEHAM, NLRTM, …};
   - finalArrivalDate `2026-10-11T18:00:00Z`;
   - delivery as in the seed, with enum values as strings `ONBOARD_CARRIER`, `ROUTED`, `UNLOAD`, and `misdirected` = `false`.
2. XYZ789 returns `itinerary` null, ETA null, lastKnownLocation null, currentVoyage null, nextExpectedActivity {RECEIVE, SGSIN, voyage null}, and **no `errors`**.
3. `location(unLocode:"DEHAM")` returns {loc_DEHAM, Hamburg, DE}. `voyage(voyageNumber:"V100S")` returns {voy_V100S, schedule[0] USNYC→DEHAM with both times}. Unknown `location(unLocode:"ZZZZZ")` and `voyage(voyageNumber:"V999X")` return null with no errors.
4. Node dispatch:
   - `node(id:"loc_NLRTM"){__typename ... on Location{unLocode}}` → `Location` / `NLRTM`;
   - `cargo_ABC123` → `Cargo` / `ABC123`;
   - `voy_V200E` → `Voyage` / `V200E`;
   - `node(id:"nope")` → null;
   - `node(id:"loc_NLRTM"){__typename ... on Cargo{trackingId}}`: `assert_json_eq '{"__typename":"Location"}'` (a non-matching fragment contributes nothing).
5. Validation negatives. Each returns 200 with `assert_has_errors` and `assert_no_data`:
   - `node(id:"loc_NLRTM"){ unLocode }` (a field not on the interface; the message contains `unLocode`);
   - `cargo(trackingId:"ABC123"){ origin }` (missing subselection; message contains `origin`);
   - `cargo(trackingId:"ABC123"){ trackingId { x } }` (subselection on a scalar).
6. Introspection:
   - `TransportStatus` kind ENUM with values in order `[NOT_RECEIVED,IN_PORT,ONBOARD_CARRIER,CLAIMED,UNKNOWN]`;
   - `RoutingStatus` `[NOT_ROUTED,ROUTED,MISROUTED]`;
   - `HandlingEventType` `[RECEIVE,LOAD,UNLOAD,CUSTOMS,CLAIM]`;
   - `Node` kind INTERFACE with sorted possibleTypes `[Cargo,Location,Voyage]`;
   - `DateTime` kind SCALAR, specifiedByURL `https://www.rfc-editor.org/rfc/rfc3339`.
7. `assert_sdl_conforms`.

**Figures (4)**
- `03-type-system-map`: bands for scalar, enum, object, interface, input and wrappers. Each kind shows its tracking-view members, with arrows from `Node` to its three implementers.
- `03-selection-onto-types` (data movement): three columns. On the left the query text (`cargo → itinerary → legs → voyage`); in the middle the type nodes it lands on (Query→Cargo→Itinerary→[Leg!]!→Voyage); on the right the JSON response nested in the same shape. Amber arrows run between matching rows.
- `03-node-dispatch` (data movement): `node(id:"loc_NLRTM")` → id lookup → runtime type Location → the `... on Location` fragment applies, the `... on Cargo` fragment is skipped → the response object.
- `03-scalar-coercion` (data movement): a client variable `"2026-10-15T00:00:00Z"` → parse value → internal value (Java `Instant` / Python `datetime` in UTC) → serialize → JSON string, with literal and variable entry points.

**Stack idioms to teach**
- SmallRye:
  - `@Type`, `@Interface`; enum constants with `@Description`; `@Id`; `@NonNull`; Java `boolean` makes `Boolean!` automatically;
  - `@CustomScalar` with `CustomStringScalar`;
  - `Instant` maps to the built-in `DateTime`;
  - extend `ContractSchemaDetails` so it also sets the `DateTime` description and `specifiedByUrl`, alongside the Query description and `UnLocode`;
  - the getter rule for interface fields (`getId()`).
- Strawberry:
  - `@strawberry.type`, `@strawberry.interface`;
  - `@strawberry.enum` with `strawberry.enum_value(..., description=…)`;
  - auto camelCase (`un_locode` → `unLocode`, `final_arrival_date` → `finalArrivalDate`);
  - `strawberry.Schema(query=Query, scalar_overrides={datetime: DateTime})`, where `DateTime = strawberry.scalar(datetime, name="DateTime", description=…, specified_by_url=…, serialize=<UTC Z formatter>, parse_value=<reject non-str and naive datetimes>)`.
- **Spike in this chapter (record the answers in the README's code-first section):** whether SmallRye's DateTime output for `Instant` is `…:00Z`; whether a field `@Description` on an `Instant` field is left alone or gets "ISO-8601" appended; whether `@Description` on enum constants reaches introspection. If either description is wrong, fix it in `ContractSchemaDetails`, never in the canonical SDL.

**Citations:** *GraphQL in Action*, "Introduction to GraphQL" and "Designing a GraphQL schema"; spec "Type System" and "Scalars" (`@specifiedBy`); the Relay Global Object Identification spec.

### Ch4: Nullability and null propagation

**Files:** `_docs/04-nullability-and-null-propagation.md`, `examples/04-nullability/`.

**H2 outline**
1. *Null is a value with a contract* — absence (XYZ789's itinerary) versus failure.
2. *Reading wrapper types* — the six combinations of `T`, `T!`, `[T]`, `[T!]`, `[T]!`, `[T!]!`, and what each permits.
3. *Defaults are opposite on the two stacks* — Java is nullable unless `@NonNull`, primitives are non-null, `List<@NonNull Leg>`; Strawberry is non-null unless `| None`, and `list[Leg]` means `[Leg!]!`. Also SmallRye's `@DefaultNonNull`/`@Nullable` as a scoped flip, shown in prose (the example keeps explicit `@NonNull`).
4. *Execution errors and the nullable boundary* — the propagation rule from the spec.
5. *Walking a null up the tree* — MNO901, step by step (Figure 4.2).
6. *Error paths name where it broke, not where the null landed* — the `path` stays at the field that failed, and aliases appear in paths.
7. *Placing the fuses in the tracking schema* — `Query.cargo`, `Cargo.itinerary`, `Leg.voyage` and `edge.node` are nullable. The strict `edge.node: Cargo!` counterexample: one bad item blanks the whole page.
8. *Input-side nullability* — arguments and variables; nullable versus non-null variable positions.
9. *The experimental escape hatch* — a short note on `@experimental_disableErrorPropagation` and semantic-nullability work (SmallRye registers that directive). Not a recommendation.
10. On the wire / Decision / next.

**Slice:** same types as Ch3. In code, `Leg` stores `voyageNumber`, `loadUnLocode` and `unloadUnLocode`. The `voyage`, `loadLocation` and `unloadLocation` fields are resolvers (SmallRye `@Source` methods in the `@GraphQLApi`; Strawberry methods on `Leg`) that call `VoyageSource` and `LocationSource`. `Cargo.delivery` is a resolver over `DeliverySource`. The seed adds JKL567, MNO901 and PQR234. Resolvers are synchronous; there is no latency in this chapter.

**verify.sh assertions (both stacks)**
1. XYZ789 `itinerary` is null with no errors (`assert_null_at '.data.cargo.itinerary'`, `assert_no_errors`).
2. JKL567 `cargo{trackingId itinerary{legs{loadLocation{unLocode} voyage{number}}}}`:
   - `assert_error_count 1`;
   - `assert_error_path '["cargo","itinerary","legs",0,"voyage"]'` (Ch1 quotes this exact path);
   - `assert_null_at '.data.cargo.itinerary.legs.0.voyage'`;
   - loadLocation.unLocode = `USNYC`; trackingId = `JKL567`.
3. MNO901, same selection:
   - `assert_null_at '.data.cargo.itinerary'`; trackingId = `MNO901`;
   - error count 1; path `["cargo","itinerary","legs",0,"loadLocation"]`;
   - `assert_error_message_contains loadLocation` (graphql-java and graphql-core both name the field; this is the only message assertion in the chapter).
4. PQR234 `cargo{trackingId delivery{transportStatus}}`: `assert_null_at '.data.cargo'`; path `["cargo","delivery"]`; count 1. `data` itself must not be null, because `Query.cargo` is nullable.
5. Aliases and isolation, `{ ok: cargo(trackingId:"ABC123"){trackingId} bad: cargo(trackingId:"PQR234"){trackingId delivery{transportStatus}} }`:
   - `.data.ok.trackingId` = `ABC123`;
   - `assert_null_at '.data.bad'`;
   - path `["bad","delivery"]`.
6. Not selecting the failing field means no error: `cargo(trackingId:"PQR234"){trackingId}` gives `assert_no_errors`.
7. Input side:
   - `cargo(trackingId: null)` as a literal → errors + no data;
   - `query($t: TrackingId){ cargo(trackingId:$t){trackingId} }` (a nullable variable in a non-null position) → errors, no data, and the message contains `$t` or `t`. Assert `has_errors` + `no_data` only.
8. Introspection wrapper chains:
   - `Itinerary.legs` = NON_NULL→LIST→NON_NULL→OBJECT(Leg);
   - `Leg.voyage` = OBJECT (not NON_NULL);
   - `Leg.loadLocation` = NON_NULL→OBJECT;
   - `Cargo.delivery` = NON_NULL;
   - `Cargo.itinerary` = OBJECT.
   Use one `__type(name:"Leg"){fields{name type{kind name ofType{kind name ofType{kind name ofType{kind name}}}}}}` per type and pick the fields with a small python filter, or `json_field` + index.
9. `assert_sdl_conforms`.

Do **not** compare error message text for thrown exceptions across stacks. SmallRye hides unchecked-exception messages by default; Strawberry passes `str(exc)`. The prose names this difference and points to Ch9.

**Figures (3)**
- `04-wrapper-matrix`: a 6-row grid of wrapper, the values allowed in the response, and the Java and Python spelling.
- `04-null-bubbling-walk` (data movement): four numbered steps up the MNO901 tree:
  1. `loadLocation` resolves null;
  2. `Leg!` cannot hold it;
  3. `[Leg!]!` cannot hold it;
  4. `itinerary` (nullable) becomes null.
  `errors[0].path` is pinned at step 1, with an amber arrow from the error box to the origin field.
- `04-nullable-fuses` (data movement): the tracking type tree with the nullable fields drawn as fuses, and two blast-radius panels side by side: canonical `edge.node` nullable (one edge null) versus strict `node: Cargo!` (the whole connection null, then `data` null).

**Stack idioms:** as in H2 3. Also: SmallRye's `@NonNull` on type-use positions; Strawberry's `list[Leg | None] | None` for `[Leg]`; a SmallRye `@Source` resolver throwing versus returning null; a Strawberry resolver raising versus returning `None`. Both produce one error; the message text differs.

**Citations:** *GraphQL in Action*, "Designing a GraphQL schema"; spec "Non-Null", "List", and "Handling Execution Errors".

### Ch5: Schema-first / contract-first

**Files:** `_docs/05-contract-first-schemas.md`, `examples/05-contract-first/`.

**H2 outline**
1. *Two ways to own a schema* — SDL-first versus code-first, and where generated wire formats differ (a contrast with the gRPC book's `buf generate`).
2. *Code-first with a canonical yardstick* — this book's choice: canonical SDL in `contracts/`, both stacks code-first, a drift gate between them. Rejected: codegen from SDL into either stack.
3. *Exporting the schema each stack builds* — Quarkus `GET /graphql/schema.graphql`; Strawberry `strawberry export-schema app.schema:schema`; why introspection and export can differ (`@specifiedBy`, directives).
4. *Diffing in two directions* — live→canonical catches extra or loosened surface; canonical→live separates a slice removal from drift. Why one direction is not enough, using nullability as the example: tightening an output field is safe for clients but still drift.
5. *Framework noise* — SmallRye's injected directives and BigDecimal/BigInteger; filter them by exact name, never by pattern.
6. *Linting the contract itself* — `npm run lint` (GraphQL ESLint schema rules: descriptions, naming).
7. *What the gate does not catch* — behaviour (values, null propagation), `specifiedByURL` over introspection, default values (⚠ dangerous rather than ✖). Hence the explicit asserts.
8. *Seeing the gate fire* — the seeded drift cases.
9. *Where the breaking gate fits* — canonical versus `main` (forward to Ch11).
10. On the wire / Decision / next.

**Slice:** same as Ch3, healthy seed. Strawberry dependency becomes `strawberry-graphql[cli]==0.335.0`. **Spike:** if that extra does not provide `export-schema` at this pin, add `app/export_schema.py` that prints `schema.as_str()` and use `python -m app.export_schema`.

**verify.sh assertions (both stacks)**
1. Ch3 sanity: the ABC123 trackingId + delivery.transportStatus values.
2. Export:
   - Quarkus: `curl -fsS localhost:8150/graphql/schema.graphql > "$tmp/quarkus.graphql"`;
   - Python: `docker compose -p gql-ch05-contract exec -T python strawberry export-schema app.schema:schema > "$tmp/python.graphql"`;
   - both non-empty and containing `type Cargo implements Node`.
   `$tmp` comes from `mktemp -d` and is removed in a trap chained after compose teardown.
3. `assert_sdl_conforms "$tmp/<stack>.graphql"` (the file pointer) **and** `assert_sdl_conforms <url>` (introspection).
4. `assert_sdl_same "$tmp/quarkus.graphql" "$tmp/python.graphql"`: two stacks, one schema.
5. `npm --prefix "$REPO_ROOT/contracts" run lint` exits 0.
6. Seeded drift. Each case: apply `sed` to a copy of the stack's export, assert the copy differs (`cmp -s` must fail, otherwise "fixture did not apply" → FAIL), then `assert_sdl_drift <file> <needle>`:

   | case | sed edit | needle |
   |---|---|---|
   | tighten | `itinerary: Itinerary$` → `itinerary: Itinerary!` | `Cargo.itinerary` |
   | loosen | `trackingId: TrackingId!$` (Cargo field) → `trackingId: TrackingId` | `Cargo.trackingId` |
   | extra field | append `  weightKg: Float` after `type Cargo implements Node {` | `weightKg` |
   | enum value | delete the line matching `^\s*UNKNOWN\s*$` | `UNKNOWN` |
   | description | `The public tracking identifier.` → `Tracking id.` | `Cargo.trackingId` |

   Run all five against **both** exports. Make the patterns tolerant of graphql-java versus Strawberry printing, and anchor the loosen case so it does not hit the `Query.cargo` argument (`trackingId: TrackingId!)`).

**Figures (2)**
- `05-contract-loop` (data movement): Quarkus code and Strawberry code → exported SDL (via HTTP or CLI) → inspector diff against `contracts/schema/` → pass/fail; a side lane shows canonical → ESLint and canonical versus `main` → the breaking gate (Ch11).
- `05-two-direction-diff`: two panels. live→canonical, flagging extra fields and loosened types. canonical→live, splitting "absent type/field = slice, allowed" from "different type, missing argument or enum value, description = drift".

**Stack idioms:** SmallRye's `schema.graphql` endpoint and the `quarkus.smallrye-graphql.schema-include-*` options, mentioned but not changed; Strawberry's `export-schema` and `schema.as_str()`; a prose sketch of an in-repo unit test per stack (`@QuarkusTest` fetching the schema; pytest on `schema.as_str()`) with a forward pointer to Ch23.

**Citations:** *GraphQL in Action*, "Designing a GraphQL schema"; GraphQL Inspector and GraphQL ESLint docs (OSS); the gRPC sibling's Ch5 as the parallel.

### Ch6: The execution model

**Files:** `_docs/06-the-execution-model.md`, `examples/06-execution-model/`.

**H2 outline**
1. *A request is a document plus inputs* — query, variables, operationName.
2. *Parse* — text to AST; a syntax error stops everything.
3. *Validate* — against the schema, with no data touched; fragment cycles, unknown fields, variable usage.
4. *Coerce variables* — before any resolver runs.
5. *Execute: walking the selection set* — CollectFields, resolve field, complete value; parent value to child (Figure 6.2).
6. *Sibling fields may run in parallel* — the spec grants permission; resolver style decides what actually happens: async resolvers (`Uni` / `async def`) overlap, synchronous ones run in sequence.
7. *Top-level mutation fields run serially* — the spec rule, with an alias example (Figure 6.4). Chapter 8 asserts it on the running stacks.
8. *Assembling the response* — key order follows the selection, aliases become response keys, `errors` sits beside `data`.
9. *Meta fields cost nothing* — `__typename`.
10. *Status codes* — GraphQL-over-HTTP with `application/json` versus `application/graphql-response+json`; what each stack returns for parse and validation failures (the observed values, from `verify.sh`).
11. On the wire / Decision / next.

**Slice:** same types as Ch3. Sources are `BookingSource.getCargo`, `RoutingSource.getItinerary`, `VoyageSource.getVoyage`, `LocationSource.getLocation`, `DeliverySource.getDelivery`. All are async with latency `TRACKING_SOURCE_LATENCY_MS=250` (set in compose). They record into the **source-call log** (contract in §3).
- Quarkus resolvers return `Uni<T>` (`@Query` and `@Source`), with the delay via `Uni…onItem().delayIt().by(...)`. The request id is `io.smallrye.graphql.api.Context#getExecutionId()`, captured at method entry.
- Python resolvers are `async def` with `await asyncio.sleep`. Sources and `request_id` (a uuid4) live in a custom context from `GraphQLRouter(schema, context_getter=…)`.
- Debug endpoints are enabled by `TRACKING_DEBUG_ENDPOINTS=true` (compose only; default off):
  - Quarkus: a `quarkus-rest-jackson` resource that answers 404 when disabled;
  - Python: a FastAPI router, included only when enabled.
- Embedded `Location`s on `Leg` become source lookups as in Ch4. Delivery is still a stored constant behind `DeliverySource`.

**verify.sh assertions (both stacks).** Run `source_calls_reset` before each case.
1. Selection drives execution: `cargo(trackingId:"ABC123"){trackingId description}` gives exactly 1 call (`booking.getCargo:ABC123`), and 0 calls each for `routing.*` and `deliveries.*`.
2. Parent before child, siblings overlap: `cargo(trackingId:"ABC123"){ itinerary{legs{loadLocation{unLocode}}} delivery{transportStatus} }`:
   - `assert_calls_ordered booking.getCargo:ABC123 routing.getItinerary:ABC123`;
   - `assert_calls_ordered booking.getCargo:ABC123 delivery.getDelivery:ABC123`;
   - `assert_calls_overlap routing.getItinerary:ABC123 delivery.getDelivery:ABC123`;
   - `assert_single_request`.
3. Top-level parallel + response key order: `{ b: cargo(trackingId:"XYZ789"){trackingId} a: cargo(trackingId:"ABC123"){trackingId} }`:
   - `assert_calls_overlap booking.getCargo:XYZ789 booking.getCargo:ABC123`;
   - `json_keys .data` = `b,a` (the selection order, not alphabetical).
4. Phase failures. Each must give `assert_has_errors`, `assert_no_data`, and a source-call count of **0**:
   - parse error: an unclosed brace. Use `gql_any`, accept 200 or 400, and record each stack's status in the README;
   - validation: unknown field `weight` (the message contains `weight`);
   - validation: a fragment cycle (`fragment A on Cargo {...B} fragment B on Cargo {...A}`);
   - variable coercion: `{"t":123}`.
5. operationName:
   - a document with `query A {cargo(trackingId:"ABC123"){trackingId}} query B {cargo(trackingId:"XYZ789"){trackingId}}` and no operationName → errors, no data, 0 calls;
   - the same document with operationName `B` → `.data.cargo.trackingId` = `XYZ789`, and the calls are exactly `[booking.getCargo:XYZ789]`.
6. `{ __typename }` gives `Query` and 0 calls.
7. `assert_sdl_conforms`. Also check that the debug endpoints add nothing to the schema (that follows from conformance).

**Figures (5)**
- `06-request-phases` (data movement): POST → parse → validate → coerce variables → execute → response. Each stage has an exit arrow to "errors, no data, zero source calls", and only execute connects to the sources.
- `06-field-walk` (data movement): the field tree for the assertion-2 query, with numbered resolver invocations and the parent value handed down each edge (Cargo object → itinerary(parent) → legs[i] → loadLocation(key)).
- `06-parallel-siblings` (data movement): a timeline. Lanes `booking`, `routing`, `delivery`; `getCargo` bar first, then overlapping `getItinerary` and `getDelivery` bars. A ghost lane shows the same pair run sequentially by synchronous resolvers.
- `06-serial-mutation` (data movement): a timeline with `a: registerHandlingEvent` (write, then its payload re-read) fully finished before `b` starts.
- `06-response-assembly` (data movement): resolver results flowing into `data` in selection order, aliases renaming keys, `errors[]` beside it.

**Stack idioms:** graphql-java's AsyncExecutionStrategy versus AsyncSerialExecutionStrategy behind SmallRye; `Uni` on `@Query`/`@Source`; worker thread versus event loop for blocking versus `Uni` methods (state it only after the spike in this chapter). On Strawberry, graphql-core gathers awaitables; `async def` versus `def` resolvers; the custom context via `context_getter`.

**Citations:** *GraphQL in Action*, "Introduction to GraphQL" and "Implementing schema resolvers"; spec "Execution", "Executing Selection Sets" (normal versus serial), "Coercing Variable Values", "Validation"; GraphQL-over-HTTP "Status Codes".

### Ch7: Queries and resolvers

**Files:** `_docs/07-queries-and-resolvers.md`, `examples/07-queries-resolvers/`.

**H2 outline**
1. *Anatomy of a resolver* — parent, args, context, info on both stacks (`@Source` + parameters + injected `Context` / `self` + args + `info`).
2. *Default resolvers* — property access and why `description` costs no source call.
3. *Root resolvers and arguments* — `cargo`, `location`, `voyage`, `node`; nullable results for "not found".
4. *The resolver chain* — parent value → child arguments → source keys (Figure 7.2).
5. *Computed fields* — `Delivery` derived from handling events + itinerary; where derivation belongs (resolver versus source).
6. *Variables and defaults* — `$t: TrackingId! = "ABC123"`.
7. *Aliases* — the same field with different args in one round trip.
8. *Fragments* — named and inline; reuse for `Location`.
9. *`@include` and `@skip`* — pruning before execution saves source calls.
10. *Request context* — per-request state; one request id across every call.
11. *The repeated-fetch smell* — the same voyage fetched twice (forward to Ch13; do not fix it here).
12. On the wire / Decision / next.

**Slice:** same types. Add `HandlingSource.listEvents(trackingId)` with the seed events. `Delivery` and `HandlingActivity` are computed by the derivation rules (a resolver on `Cargo.delivery` that calls `handling.listEvents` and `routing.getItinerary`; it may reuse the parent's itinerary only through the source). Remove `DeliverySource`.

**verify.sh assertions (both stacks).** Run `source_calls_reset` before each case.
1. Resolver chain: `cargo(trackingId:"ABC123"){itinerary{legs{voyage{number}}}}`:
   - exactly 4 calls: `booking.getCargo:ABC123`, `routing.getItinerary:ABC123`, `voyage.getVoyage:V100S`, `voyage.getVoyage:V200E`;
   - `assert_calls_ordered routing.getItinerary:ABC123 voyage.getVoyage:V100S`;
   - `assert_calls_overlap voyage.getVoyage:V100S voyage.getVoyage:V200E` (list items resolve concurrently);
   - legs voyage numbers `V100S`, `V200E`.
2. Derived delivery for ABC123 equals the Ch3 seed values: ONBOARD_CARRIER, currentVoyage V100S, next {UNLOAD, DEHAM, V100S}, ETA `2026-10-11T18:00:00Z`, misdirected false. Calls include `handling.listEvents:ABC123`. XYZ789 gives NOT_RECEIVED, next {RECEIVE, SGSIN, null}.
3. Default resolver: `cargo(trackingId:"ABC123"){description}` gives exactly 1 call (booking only).
4. Variables with a default: `query($t: TrackingId! = "ABC123"){cargo(trackingId:$t){trackingId}}` with no variables gives `ABC123`.
5. Aliases: `{ ny: location(unLocode:"USNYC"){name} rtm: location(unLocode:"NLRTM"){name} }` gives `New York` and `Rotterdam`.
6. Named fragment `fragment Place on Location {unLocode name country}` on origin and destination gives the full Ch0 values.
7. Directives with `query($full: Boolean!){cargo(trackingId:"ABC123"){trackingId itinerary @include(if:$full){legs{loadTime}} delivery @skip(if:$full){transportStatus}}}`:
   - `full=false`: `assert_absent '.data.cargo.itinerary'`, 0 `routing.*` calls, delivery present;
   - `full=true`: itinerary present, `assert_absent '.data.cargo.delivery'`, 0 `handling.*` calls.
8. Context:
   - `assert_single_request` on assertion 1's calls;
   - two consecutive requests without a reset have different `request` values (`assert_distinct_requests`).
9. Repeated fetch: `cargo(trackingId:"ABC123"){itinerary{legs{a: voyage{number} b: voyage{number}}}}` gives `assert_source_call_count voyage getVoyage 4` (2 legs × 2 aliases, no per-request cache). The README's "On the wire" points to Ch13.
10. `voyage(voyageNumber:"V100S"){schedule{departureLocation{unLocode} arrivalTime}}` gives `USNYC` and `2026-10-09T14:00:00Z`; `voyage(voyageNumber:"V999X")` gives null.
11. `assert_sdl_conforms`.

**Figures (3)**
- `07-resolver-anatomy`: the four inputs (parent, args, context, info) feeding one resolver, with the Java and Python spelling of each.
- `07-resolver-chain` (data movement): `booking.getCargo(ABC123)` → Cargo value → `routing.getItinerary(ABC123)` → legs → `voyage.getVoyage(V100S)` and `(V200E)` in parallel, with keys labelled on the arrows.
- `07-directive-pruning` (data movement): the same query with `$full=false` and `$full=true`. Pruned branches are drawn ghosted, with the source calls avoided and the calls made.

**Stack idioms:** SmallRye `@Source` field methods, `@Name`, `@DefaultValue` (for arguments; none are needed in the slice), the injected `io.smallrye.graphql.api.Context`, CDI `@ApplicationScoped` sources. Strawberry `strawberry.Info`, a typed context class (subclassing `BaseContext`), `strawberry.argument`, resolvers as methods versus `strawberry.field(resolver=…)`.

**Citations:** *GraphQL in Action*, "Customizing and organizing GraphQL operations", "Implementing schema resolvers", "Working with database models and relations"; spec "Fragments", "Directives (`@include`/`@skip`)", "Field Alias".

### Ch8: Mutations and input types

**Files:** `_docs/08-mutations-and-input-types.md`, `examples/08-mutations/`.

**H2 outline**
1. *Why the write surface is one field* — writes belong to the owning services; `registerHandlingEvent` as the exception.
2. *Input types* — input versus output, no interfaces or unions in input, `RegisterHandlingEventInput` field by field.
3. *Coercion: the first line of defence* — scalars, enums, unknown fields; these fail as request errors, before any write.
4. *Domain validation as data* — `userErrors` with `UserErrorCode` and a `field` path; why not top-level `errors` (forward to Ch9).
5. *The payload and the re-read* — return `handlingEvent` and `cargo` with delivery recomputed, so the client needs no follow-up query.
6. *Mutation fields run in order* — Ch6's rule, observed on the running stacks.
7. *Retries and `idempotencyKey`* — atomic check-and-insert; same key returns the original; no key means duplicates.
8. *Mutations and HTTP* — POST only; GraphQL-over-HTTP requires a 4xx for a mutation over GET (405 recommended, with `Allow` per RFC 9110); observed: Quarkus 405 without `Allow`, Strawberry 400 `text/plain`.
9. *Naming and shape conventions* — verb-noun, single `input`, payload per mutation; `clientMutationId` rejected in favour of `idempotencyKey`.
10. On the wire / Decision / next.

**Slice:** Ch7 plus the Mutation and handling types, `HandlingEvent` (all fields, `cargo` resolver nullable), and `node(id:"evt_N")`.
- `HandlingSource` gains `appendEvent` (latency 250 ms) and `findByIdempotencyKey`.
- New ids are `evt_<n>`, sequential after the seed (`evt_3` is the first).
- registrationTime is the server clock (not asserted).
- Validation collects **all** applicable userErrors in this order: trackingId, location, voyageNumber (required / not-allowed / unknown), completionTime (future means after server now).

**verify.sh assertions (both stacks, run in this order: state is in memory and carries forward)**
1. Coercion failures. Each gives `assert_has_errors`, `assert_no_data`, and 0 `handling.appendEvent` calls:
   - `type` missing;
   - `type:"TELEPORT"` via variables;
   - `location:123`;
   - `completionTime:"yesterday"`;
   - an extra input field `weightKg:1`.
2. userErrors. Each gives no top-level errors, `handlingEvent` null, `cargo` null, 0 appends, and `assert_json_eq` on `userErrors{code field}`; `message` must be non-empty:
   - LOAD at DEHAM with no voyageNumber → `[{"code":"VOYAGE_REQUIRED","field":["input","voyageNumber"]}]`;
   - RECEIVE with voyageNumber V100S → `VOYAGE_NOT_ALLOWED`;
   - LOAD on `V999X` → `UNKNOWN_VOYAGE`;
   - completionTime `2099-01-01T00:00:00Z` → `INVALID_COMPLETION_TIME` with `["input","completionTime"]`;
   - trackingId `NOPE99` plus location `ZZZZZ` → `[UNKNOWN_CARGO ["input","trackingId"], UNKNOWN_LOCATION ["input","location"]]`, in that order.
3. Success: UNLOAD, ABC123, DEHAM, V100S, `2026-10-09T15:00:00Z`, key `k-001`:
   - handlingEvent {id `evt_3`, type UNLOAD, location.unLocode DEHAM, voyage.number V100S, completionTime `2026-10-09T15:00:00Z`, trackingId ABC123};
   - cargo.delivery {IN_PORT, lastKnownLocation DEHAM, currentVoyage null, next {LOAD, DEHAM, V200E}};
   - `userErrors` = `[]`; exactly 1 append.
4. Replay with the same input and `k-001`: `evt_3`, 0 appends.
5. Same key, different completionTime `2026-10-09T16:00:00Z`: returns `evt_3` with the **original** completionTime `2026-10-09T15:00:00Z`, 0 appends.
6. Serial pair, `source_calls_reset` first. One document: `a:` LOAD DEHAM V200E `2026-10-10T06:30:00Z` key `k-002`, then `b:` UNLOAD NLRTM V200E `2026-10-11T18:30:00Z` key `k-003`:
   - a.handlingEvent.id `evt_4`; b `evt_5`;
   - `a.cargo.delivery` {ONBOARD_CARRIER, currentVoyage V200E, next {UNLOAD, NLRTM, V200E}} (the payload completes before `b` starts);
   - `b.cargo.delivery` {IN_PORT, lastKnownLocation NLRTM, currentVoyage null, next {CLAIM, NLRTM, null}, ETA `2026-10-11T18:00:00Z`};
   - `assert_calls_ordered handling.appendEvent:evt_4 handling.appendEvent:evt_5` (the append key is the new event id);
   - `json_keys .data` = `a,b`.
7. No key, twice: CUSTOMS ABC123 NLRTM `2026-10-12T09:00:00Z` gives `evt_6`, then `evt_7` (distinct ids, 1 append each).
8. GET refusal: `gql_get` with the mutation from step 7. Status ≠ 200, 0 appends, and `node(id:"evt_8")` is null afterwards. Record the observed status per stack (expected 405).
9. `node(id:"evt_3"){__typename ... on HandlingEvent{type cargo{trackingId}}}` gives `HandlingEvent`, `UNLOAD`, `ABC123`.
10. `RegisterHandlingEventInput` introspection: `inputFields{name defaultValue}`, where every `defaultValue` is `null` (this catches Strawberry's `= null` default drift).
11. `assert_sdl_conforms` (Mutation root served; Subscription is still a slice removal).

**Figures (3)**
- `08-mutation-flow` (data movement): JSON variables → input coercion (fail goes to `errors[]`) → domain validation (fail goes to `userErrors`) → idempotency lookup → `appendEvent` → re-read cargo + delivery → payload.
- `08-errors-vs-usererrors`: two response envelopes side by side, a coercion failure (`data` absent, `errors[]`) versus a domain failure (`data.registerHandlingEvent.userErrors`, no `errors`).
- `08-idempotent-replay` (data movement): a timeline of the first request (`k-001` → `evt_3` written), a lost response, the retry (`k-001` → lookup hit → `evt_3` returned, store unchanged), and a ghost lane for a retry with no key that writes a duplicate.

**Stack idioms**
- SmallRye:
  - `@Mutation`; `@Input("RegisterHandlingEventInput")` on a record. **Spike:** record input binding; fall back to a POJO with a no-arg constructor if records fail. Be explicit about the name because SmallRye otherwise suffixes `Input`.
  - `@NonNull` input fields; `List<@NonNull String> field`;
  - `ContractSchemaDetails` extended to set the Mutation root description (SmallRye writes "Mutation root");
  - a thread-safe store (`ConcurrentHashMap.computeIfAbsent` for the key);
  - `Uni<RegisterHandlingEventPayload>`.
- Strawberry:
  - `@strawberry.input`, `@strawberry.mutation`, `@strawberry.type(description=…) class Mutation`;
  - optional input fields declared so the SDL has **no** `= null`. Use the documented current idiom at 0.335: `strawberry.Maybe` if documented, else `strawberry.UNSET`;
  - `asyncio.Lock` around check-and-insert.

**Citations:** *GraphQL in Action*, "Implementing mutations"; spec "Input Objects", "Input Coercion", serial execution; GraphQL-over-HTTP (GET and 405).

---

## 3. Harness additions (`examples/_lib/lib.sh`, A0)

All of these are backward compatible, `bash -n` and shellcheck clean, and use stdlib `python3 -I` for JSON. Document each in `examples/_lib/README.md`'s table. JSON-path arguments use the existing `json_field` dot syntax.

| Function | Contract |
|---|---|
| `_gql_body <query> [vars] [operationName]` | Extended: adds `"operationName"` when the third argument is non-empty. |
| `gql <url> <query> [vars] [operationName]` | Unchanged behaviour; fourth argument optional. |
| `gql_any <url> <query> [vars] [operationName]` | POST like `gql` but never fails on status. Prints line 1 = HTTP status, rest = body. Non-zero only on a transport failure. |
| `gql_get <url> <query> [vars]` | GET with URL-encoded `query`/`variables` (`Accept: application/json`). Output format as `gql_any`. |
| `status_of <gql_any-output>` / `body_of <gql_any-output>` | Split the two parts. |
| `assert_status_in <"200 400"> <status> [ctx]` | Status is in the space-separated set. |
| `assert_no_data <json> [ctx]` | `data` is absent or JSON null (factors out Ch0's inline check). |
| `assert_null_at <json> <path> [ctx]` | The path **exists** and is JSON null. Absent fails, with a message that says absent. |
| `assert_absent <json> <path> [ctx]` | The final key is not present (null fails). |
| `assert_error_count <json> <n> [ctx]` | `len(errors) == n` (absent counts as 0). |
| `assert_error_path <json> <path-json-array> [ctx]` | Some `errors[i].path` equals the array exactly: types matter, so `0` ≠ `"0"`. Prints all paths on failure. |
| `assert_error_message_contains <json> <needle> [ctx]` | Some error message contains the needle. |
| `assert_json_eq <expected-json> <actual-json> [ctx]` | Parsed equality; object key order ignored, list order significant. |
| `json_len <path>` (stdin) | Length of a list or object. |
| `json_keys <path>` (stdin) | Comma-joined keys **in document order**. |
| `graphql_base <url>` | Strips a trailing `/graphql`. |
| `source_calls_reset <graphql-url>` | `DELETE <base>/debug/source-calls`; expects 204, else FAIL. |
| `source_calls <graphql-url>` | `GET <base>/debug/source-calls`; prints `{"calls":[…]}`. |
| `assert_source_call_count <calls-json> <source> <op or *> <n> [ctx]` | Count of matching entries. |
| `assert_source_calls_exactly <calls-json> <k1,k2,…> [ctx]` | The multiset of `source.op:key` equals the list (order ignored). |
| `assert_calls_ordered <calls-json> <keyA> <keyB> [ctx]` | Each key matches exactly one call, and A.endMs ≤ B.startMs. |
| `assert_calls_overlap <calls-json> <keyA> <keyB> [ctx]` | A.startMs < B.endMs and B.startMs < A.endMs. |
| `assert_single_request <calls-json> [ctx]` | Every entry has the same non-empty `request`. |
| `assert_distinct_requests <calls-json> [ctx]` | At least 2 distinct `request` values. |
| `assert_sdl_conforms <pointer> [ctx]` | Documented to accept a URL **or** file/glob pointer (the code already allows it). |
| `assert_sdl_same <ptrA> <ptrB> [ctx]` | Diff A→B and B→A; no change line remains after `LGTM_SDL_IGNORE` and the `specifiedBy` filter. |
| `assert_sdl_drift <pointer> <needle> [ctx]` | Runs `assert_sdl_conforms` in a subshell. Passes only if it **fails** and its combined output contains the needle. A tool error (rc 2 path) is a FAIL, not a "drift detected". |
| `ensure_contracts_tools` | Wrapped in `flock "${TMPDIR:-/tmp}/gql-contracts-npm.lock"` so concurrent `verify.sh` runs never race `npm ci`. |

**Source-call log contract.** Identical on both stacks; it is not part of the schema.
- Endpoints: `GET /debug/source-calls` → `200 {"calls":[{"request":str,"source":str,"op":str,"key":str,"startMs":number,"endMs":number}, …]}`, sorted by `startMs`. `DELETE` → `204`.
- `startMs`/`endMs` are monotonic milliseconds since process start (`System.nanoTime` / `time.perf_counter`).
- `source` ∈ `booking|routing|voyage|location|delivery|handling`. `op` is the method name (`getCargo`, `getItinerary`, `getVoyage`, `getLocation`, `getDelivery`, `listEvents`, `appendEvent`, `findByIdempotencyKey`). `key` is the lookup key; for `appendEvent` it is the new event id.
- Enabled only when `TRACKING_DEBUG_ENDPOINTS=true`; otherwise 404 or not mounted. It exists from Ch6 on and is reused by Ch13, Ch19 and Ch24.

A0 self-test: run Ch0 `verify.sh` green after the edits. Run `bash -n` and `python3 -I scripts/validate.py`.

---

## 4. Acceptance criteria

**Per chapter (Ch3–Ch8)**
- `_docs/NN-*.md` exists with valid front matter (`part:` resolves, `order` = N).
- `bash scripts/wordcount.sh _docs/NN-*.md` reports 2,800–3,400 words.
- The chapter's budgeted figures exist (3:4, 4:3, 5:2, 6:5, 7:3, 8:3 = 20). Each is a paired `assets/diagrams/NN-slug.{svg,excalidraw}` with a spec at `diagrams/NN-slug.py` that regenerates it with `python3 -I`, and each is embedded with full-sentence alt text and a `Figure N.M — …` caption.
- The chapter has `## On the wire` whose values match `verify.sh` byte for byte, then a Decision callout naming axes from Ch2, then `## Where this goes next`.
- At least one `codetabs` Quarkus|Python pair.
- `examples/NN-slug/` contains README.md (slice, ports table, run, On the wire table, pins, code-first notes, diagram regen line), compose.yaml (fixed `name:`), an executable verify.sh, .gitignore, architecture.svg + .excalidraw (spec under `diagrams/examples/`), and `quarkus/` + `python/` with a `uv.lock`.
- `verify.sh` prints `PASS` locally; every assertion listed in §2 is present for **both** stacks; it uses only the harness plus stdlib.
- `assert_sdl_conforms` passes on both stacks.
- No planning language in `_docs/0[3-8]*` or `examples/0[3-8]*/README.md`. Gate: `grep -rniE 'wave [a-z0-9]|\bS[0-9]{1,2}\b|\br0[0-9]\b|iteration|capstone|coverage matrix|phase [0-9]|TODO|TBD'` returns nothing.
- No vendor products.
- `lgtm-professional-voice`: 0 ban-tier findings.
- `lgtm-idiomatic-review`: 0 unresolved substantive findings on the example code.

**For the wave**
- `python3 -I scripts/validate.py` exits 0.
- `GATE=1 bash scripts/wordcount.sh` passes.
- The Jekyll build (ruby:3.3 container) is clean.
- `npm --prefix contracts run lint` and `run breaking` pass; `contracts/` is untouched.
- The CI examples matrix shows `verify: 03-sdl-type-system` … `verify: 08-mutations` green, and `ci-ok` is green on PR #1.
- Running the six verify.sh scripts concurrently on one host succeeds (proves ports, projects and the npm lock).
- Site figure total after the wave is the previous count plus 20.
- Ch1's quoted path `["cargo","itinerary","legs",0,"voyage"]` and Ch1/Ch2's forward references (Node, enums, input types, custom scalars, parallel versus serial) are all delivered.

---

## 5. Risks and how each is detected

| Risk | Detection / mitigation |
|---|---|
| The SmallRye `DateTime` description or `specifiedBy` differs from canonical (built-in scalar; the `ISO-8601` description path) | `assert_sdl_conforms` description grep; the `__type(name:"DateTime"){specifiedByURL}` assert. Fix in `ContractSchemaDetails`. |
| DateTime wire format differs (`+00:00` from Python `isoformat`, fractional seconds) | Exact-string asserts on every timestamp; Strawberry `scalar_overrides` with a Z formatter. |
| Strawberry auto camelCase surprises (`un_locode`, acronyms) | Conformance reports a removed or added field. Use `strawberry.field(name=…)` only when auto camelCase is wrong. |
| Opposite nullability defaults (a Java `List<Leg>` printed as `[Leg]`) | Canonical→live breaking ✖; Ch4 asserts the wrapper chains explicitly. |
| Tightening nullability is invisible in one diff direction | The two-direction diff (fwd catches it); Ch5's "tighten" drift case proves it. |
| Strawberry optional input prints `= null` (⚠ dangerous, not ✖, so conformance misses it) | Ch8 `inputFields{defaultValue}` all null. |
| Enum value descriptions are not emitted by SmallRye | Description grep in conformance; fallback is the `ContractSchemaDetails` transform. |
| Null-propagation messages and paths differ across engines | Assert only path (exact array), count and data shape; one message assert (`loadLocation`), where both engines name the field. |
| SmallRye hides runtime-exception messages | Not asserted; prose explains it; Ch9 owns it. |
| graphql-java bad-faith introspection rejects repeated `__type` or deep queries | One `__type` per request; keep `ofType` depth ≤ 4. |
| Parallel execution not actually concurrent (synchronous resolvers; Uni on the wrong thread; graphql-java dispatch) | `assert_calls_overlap` fails loudly. Spike in Ch6. If SmallRye serializes `Uni` `@Source` siblings, investigate before changing the claim; never weaken the prose to match a bug silently. |
| Serial-mutation semantics not observable | Two independent observables in Ch8: append ordering in the log **and** `a`'s payload showing the state before `b`. |
| Request id not stable across async hops (Quarkus request context) | `assert_single_request`; capture `Context#getExecutionId()` at method entry. |
| Timing flakiness on CI | Only ordering and overlap of 250 ms windows are asserted, never absolute durations; CI retries 3×. |
| Ch8 tests depend on order (in-memory state) | Fixed sequence in §2; event ids asserted at each step, so a skipped or reordered step fails immediately. |
| Strawberry parse-error HTTP status (400 vs 200) or Quarkus GET handling differs | `gql_any` + `assert_status_in`; observed values are recorded in README and prose, not assumed. |
| Concurrent `npm ci` corrupting `contracts/node_modules` | `flock` in `ensure_contracts_tools`; A0 warms it once; executors are forbidden from reinstalling it. |
| Ch5 `sed` drift fixture silently not applying | A `cmp` guard turns a no-op into a FAIL. |
| `assert_sdl_drift` passing on a tool error | Tool errors return rc 2 with "could not compare"; `assert_sdl_drift` treats that as FAIL. |
| Debug endpoints leaking into the schema or production config | Conformance (the schema is unchanged); env-gated, default off; the README labels them lab-only. |
| SmallRye `@Input` record binding or the `Input` suffix | The Ch8 spike; conformance catches a name like `RegisterHandlingEventInputInput`. |
| Citation drift (wrong book chapter title; outdated spec term "field error") | Opus validation checks titles against the book ToC and the spec's current terms. |
| Planning language leaking into reader-facing files | The grep gate in acceptance. |
| Stale `_plans/iteration-plan.md` text ("71 across the site (band 60–72)", status table) | Fixed in AW (orchestrator only). |

---

## 6. Coverage-matrix and plan updates (AW, orchestrator only)

1. At each chapter's checkpoint commit, set Ch3–Ch8 to `draft` in **both** the Topics table (T4–T9) and the Full chapter inventory. This turns on `validate.py`'s file-presence check and the wordcount GATE for that chapter.
2. After the PR's CI examples matrix is green for `03`–`08`, flip the same 12 cells to `verified`. Ch0 (T1, R1 unaffected) must already be `verified`. If it is not, leave Ch3–8 at `draft`, because a chapter cannot be verified on an unverified base.
3. Leave the Diagram budget table unchanged; the counts are already allocated. Record the actual Wave A figure count (20) in the r01 RESUME POINTER.
4. `_example_pages/index.md`: it does not exist in this repo yet. If S4 has not created it, create it mirroring the gRPC page (SDL wording instead of Protobuf) with the Ch0 row. Then add rows 03–08:
   - **03** — Type system: enums, `Node` dispatch, `DateTime`/custom scalars, both stacks.
   - **04** — Null propagation: voyage null with its error path, `loadLocation` bubbling to `itinerary`, delivery nulling `cargo`.
   - **05** — Contract-first: SDL export from both stacks, two-direction drift gate, seeded drift fails.
   - **06** — Execution phases with zero source calls on failure, parallel sibling resolvers, operationName.
   - **07** — Resolver chain keys, derived `Delivery`, `@include`/`@skip` pruning, request context.
   - **08** — `registerHandlingEvent`: coercion vs `userErrors`, payload re-read, serial aliased mutations, idempotent replay.
5. `_plans/r01-execution-plan.md` RESUME POINTER: S6 set to done with the date, the Opus-validation note, and the spike findings (DateTime format, enum descriptions, input binding, observed HTTP statuses). Fix `_plans/iteration-plan.md` (89 diagrams, band 80–95; status rows).
6. Commits: one checkpoint commit per chapter on `r01` (`docs(§N): …` covering prose + figures + example), plus `chore(rNN.x)`-style commits for the harness and the plans updates, per lgtm-github conventions. Then push, watch CI, and flip to verified in a follow-up commit.

---

### Critical files for implementation
- /home/rsedor/Dev/api-patterns-and-practices-graphql/examples/_lib/lib.sh
- /home/rsedor/Dev/api-patterns-and-practices-graphql/examples/00-prerequisites/verify.sh (and its `quarkus/…/ContractSchemaDetails.java`, `python/app/schema.py`)
- /home/rsedor/Dev/api-patterns-and-practices-graphql/contracts/schema/shipping/cargo.graphql and handling.graphql
- /home/rsedor/Dev/api-patterns-and-practices-graphql/_plans/coverage-matrix.md
- /home/rsedor/Dev/api-patterns-and-practices-graphql/scripts/generate_diagram.py

---

## 7. Pitfalls found in A1 validation (binding on A2–A4 executors)

1. Keep `ContractSchemaDetails.withCurrentTypes` in every copy. Any `SchemaTransformer` change rebuilds types; without the wrapper, fragments on a `Node` implementer silently select nothing. Always assert a field selected through `... on X` via `node(id:)`, not only `__typename`.
2. Python scalars: `NewType` + `StrawberryConfig(scalar_map=...)`. Never pass a type to `strawberry.scalar(...)`; no `scalar_overrides` (deprecated at 0.335.0). This supersedes the scalar idiom text in §2 Ch3.
3. Assert nulls with `assert_null_at`, absent keys with `assert_absent` — never string-compare `"null"`. Compare booleans and typed objects with `assert_json_eq`.
4. Helpers called inside `$(...)` don't get `set -e`: end every assertion inside them with `|| return 1`.
5. `assert_sdl_drift`: the needle must appear in graphql-inspector's change line (e.g. `Leg.loadTime`); the context string doesn't count. Loosening a type shows in the canonical→live direction.
6. SmallRye enum order is alphabetical (Jandex), not configurable: compare enum values as sets.
7. A record-style `id()` on `Node` breaks startup once `Query.node` exists: keep `getId()`.
8. Constructor injection in `@GraphQLApi` and source beans.
9. GraphQL enum literals are bare in documents (`type: LOAD`); only variables carry strings (matters for Ch8 coercion cases).
10. Request errors: the spec says `data` should be absent; Quarkus omits it, Strawberry sends `"data": null` — assert with `assert_no_data`.

## 8. Follow-ups noted during A2 (for AV / AW)

- `lib.sh`: add a public teardown-hook API (Ch5 `verify.sh` chains cleanup after the private `_lib_teardown`).
- `lib.sh` is bash-only (`BASH_SOURCE`); never source it from zsh — say so in `examples/_lib/README.md`.
- Ch5 sets `quarkus.smallrye-graphql.schema-include-scalars=true` (needed for the exported SDL to parse); later examples that export SDL need the same.

## 9. Ch6 findings and handoff to Ch7 (binding on A3/A4)

Observed (spike evidence in the Ch6 README):
- Quarkus overlaps sibling resolvers whether they return `Uni` (event loop, no thread held) or plain values (each blocking call gets its own worker thread). Python overlaps `async def` siblings; plain `def` with blocking work runs strictly in sequence. The plan's "synchronous ones run in sequence" holds only on Python.
- Strawberry 0.335.0 executes the first operation when a multi-operation document arrives without `operationName`; the spec (GetOperation) and SmallRye make it a request error. Documented as a Strawberry deviation; asserted per stack.
- Both stacks answer 200 for parse/validation/coercion/operation-selection errors even with `Accept: application/graphql-response+json` (Quarkus echoes that content type; Strawberry answers `application/json`). Quarkus `GET /graphql` → 405 for a query; Strawberry → 200 (Ch8 covers GET).

Copying Ch6 into Ch7:
- Request id: Quarkus takes `io.smallrye.graphql.api.Context` on every resolver (incl. `@Source`) and reads `getExecutionId()` at entry, passing it into sources explicitly; Python uses `info.context` (`TrackingContext`, uuid4 per request via `context_getter`).
- Python layering: `app/context.py` has no runtime imports of sources (cycle); `app/deps.py` builds the context and `get_calls`; `debug.py`/`main.py` import from `deps`.
- Source shape: `getX(request, key)` over `SourceCalls.call(...)`; add `HandlingSource` in the same shape and register `handling` in the per-request source set on Python.
- Quarkus: `Leg` `@Ignore`s the codes; `Cargo` has no component for `itinerary`/`delivery`; `@NonNull` on a `Uni`-returning `@Source` works; keep `ContractSchemaDetails.withCurrentTypes`.
- `Query.node` dispatches on id prefix (`cargo_`, `loc_`, `voy_`) into sources.
- Config: `TRACKING_SOURCE_LATENCY_MS` (default 0) and `TRACKING_DEBUG_ENDPOINTS` (default false); compose sets 250 / true.
- Never `pkill -f` patterns while other executors run uvicorn.

## 10. Ch7 findings and handoff to Ch8 (binding on A4)

- Plan assertion 7 corrected: `full=false` still calls `routing.getItinerary` once, because the derived `Delivery` needs the itinerary as input. Asserted instead: `full=false` → exactly `booking.getCargo`, `routing.getItinerary`, `handling.listEvents`; `full=true` → `booking.getCargo` + `routing.getItinerary`, 0 `handling.*`; `itinerary` + `delivery` together → 2 `routing.getItinerary` calls (no caching yet; Ch13 fixes this with DataLoaders).
- Ch8 copies Ch7: ports 8180/8181, project `gql-ch08-mutations`, containers `ch08-mutations-*`, artifactId `ch08-quarkus-mutations`, Python project `shipping-python-ch08-mutations`; re-run `uv lock` after renaming.
- Event model: `HandlingRecord` (Java record / `app/handling.py`) is the internal stored form (id, trackingId, type, unLocode, voyageNumber, completionTime, registrationTime); the GraphQL `HandlingEvent` type is new in Ch8. Ch7's store is immutable (`Map.of` / plain dict) — Ch8 needs a thread-safe mutable store (`ConcurrentHashMap` with atomic idempotency check-and-insert; Python `asyncio.Lock`), and `HandlingSource.listEvents` must read from it.
- `DeliveryDerivation` picks the last event by (completionTime, registrationTime) — appended events need no change; unknown voyage → null voyage, no throw.
- `Cargo.delivery` re-reads handling events at resolve time on both stacks (no caching) — the Ch8 serial-mutation payload assertions depend on this.
- Untested prose in Ch7: `@DefaultValue` / Strawberry argument-default spelling — AV must check.
