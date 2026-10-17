---
layout: plan
render_with_liquid: false
title: "r01 Wave B Plan — Ch9–Ch13 (Reliability, Evolution, Data at Scale)"
---

# Wave B (S7): Ch9–Ch13, Reliability, Evolution and Data at Scale

**Status: DONE 2026-10-16. APPROVED by user 2026-10-16 (all four §8 recommendations accepted); Ch9–13 verified, CI green at f1aff13.**

This plan is for Sonnet executors. Where it names a value (port, id, timestamp, cursor rule, error code, message, path), use that exact value. Where it says **spike**, check the behaviour on the pinned versions before writing any prose that depends on it, and record what you observe in the example README's "Code-first notes".

**Precondition.** S6 (Wave A) is done: Ch0–Ch8 `verified`, CI green at `2e877f2`. Wave B starts from `examples/08-mutations/`.

**Facts checked against the local jars and wheels (2026-10-16).** These are inputs to the plan. Behaviour still marked *spike* has not been run.
- SmallRye GraphQL 2.18.5 runs on graphql-java 25.0 with java-dataloader. A `@Source List<S>` method becomes a `BatchDataFetcher`. `ExecutionService` creates one `org.dataloader.DataLoader` per batch operation **per request**. When the operation takes no GraphQL arguments it uses `DataLoaderFactory.newDataLoader(loader)` with the default options, so caching is on and the cache key is the source object (`equals`/`hashCode`). `UniDataFetcher` and `CompletionStageDataFetcher` both extend `AbstractAsyncDataFetcher` (the batchable async path).
- SmallRye error machinery:
  - `io.smallrye.graphql.api.ErrorCode` annotation on exception classes;
  - `ErrorExtensionProvider` SPI;
  - built-in providers `ErrorCodeExtensionProvider` (key `code`; uses the `@ErrorCode` value, otherwise the kebab-case simple class name without `Exception`) and `ExceptionNameErrorExtensionProvider`;
  - hidden-message default `"System error"`;
  - Quarkus config keys `quarkus.smallrye-graphql.show-runtime-exception-message`, `hide-checked-exception-message`, `default-error-message`, `error-extension-fields`, `print-data-fetcher-exception` and `unwrap-exceptions`;
  - CDI events `@ErrorDataFetch` and `@ErrorExecute` in `io.smallrye.graphql.cdi.event`.
- SmallRye API also has `io.smallrye.graphql.api.Deprecated(reason)` (targets FIELD/METHOD/PARAMETER) and `java.lang.Deprecated` handling in `DeprecatedDirectivesHelper`, plus `@Union` and `@OneOf`.
- Strawberry 0.335.0 has `strawberry.dataloader.DataLoader(load_fn, max_batch_size=None, cache=True, cache_key_fn=None, cache_map=None)`.
  - Dispatch is scheduled with `loop.call_soon`: one event-loop tick collects the loads.
  - An exception *instance* in the returned list fails only that key.
  - `WrongNumberOfResultsReturned` is raised when the lengths differ.
- Strawberry `MaskErrors(should_mask_error=…, error_message="Unexpected error.")` rebuilds the masked `GraphQLError` **without `extensions`**.
- graphql-core is **3.3.0**. `GraphQLError` copies `original_error.extensions` when it is a dict. A `GraphQLError` raised from a resolver becomes the `original_error` of the located error, so it is masked unless the predicate allows it.
- `strawberry.relay` `ListConnection` uses offset cursors (`base64("arrayconnection:<n>")`), its own `PageInfo`/edge descriptions, and no `totalCount`.
- graphql-inspector 7.0.1:
  - CLI `diff` accepts `--rule <name>`; the rules include `dangerousBreaking` and `suppressRemovalOfDeprecatedField`;
  - exit 1 only on breaking;
  - `fieldDeprecationAdded` / `fieldDeprecationRemoved` are NonBreaking;
  - enum value added to an existing enum is Dangerous;
  - optional argument added to an existing field is Dangerous;
  - required input field added is Breaking, nullable input field added is NonBreaking;
  - field removal is Breaking, and the message contains `(deprecated)` when the removed field was deprecated.
- `origin/main` currently has **no** `contracts/schema`, so `npm run breaking` against `main` skips ("first introduction"). Any demonstration of the gate on r01 must therefore use `BASE_DIR`.
- The site has 26 figures. Wave B adds 17, for a total of 43.

---

## 1. Approach

### Sequencing (DAG)

| Step | Executor | Owns (exclusive write set) | Depends on |
|---|---|---|---|
| **B0** Harness + contract changes | Executor 1 | `examples/_lib/lib.sh`, `examples/_lib/README.md`, `contracts/scripts/breaking.sh`, `contracts/README.md`, `contracts/schema/shipping/schema.graphql`, `contracts/schema/shipping/cargo.graphql` | S6 |
| **B1** Ch9 Error handling | Executor 2 | `_docs/09-*`, `examples/09-error-handling/**`, `diagrams/09-*.py`, `diagrams/examples/09-*`, `assets/diagrams/09-*` | B0 |
| **B2** Ch10 Schema design patterns | Executor 3 | same pattern for `10-*` | B0 |
| **B3** Ch11 Evolution and versioning | Executor 3 (after B2) | `11-*` | B2 (copies Ch10) |
| **B4** Ch12 Connections and pagination | Executor 2 (after B1) | `12-*` | B1 (copies Ch9) **and** B2 (ports `Query.nodes` from Ch10's code) |
| **B5** Ch13 N+1 and DataLoaders | Executor 4 | `13-*` | B4 (copies Ch12) |
| **BV1…BV5** Validation (Opus), one per chapter | Opus | read-only findings; fixes routed to the owning executor | the chapter's step |
| **BW** Wrap (orchestrator) | orchestrator | `_plans/*`, `_example_pages/index.md`, commits, coverage-matrix flips | BV1–BV5 + CI green |

How to run it:
- B1 and B2 run in parallel. B3 and B4 run in parallel. B5 is last. That gives a critical path of four content steps (B0 → B1/B2 → B3/B4 → B5).
- Each BVn starts as soon as its chapter's checkpoint commit lands; it does not wait for the wave.
- B4 applies the Ch11 deprecation patch from §2 Ch11 ("Deprecation patch"), not Ch11's code. The patch is two annotations and one field per stack, and the canonical SDL that B0 lands is the yardstick. B5 inherits the patch from B4.

**Executor rules (unchanged from Wave A, binding).**
- Write files only, no git.
- Do not touch:
  - `_plans/*`, `coverage-matrix.md` or `_example_pages/`;
  - `contracts/` (only B0 may) or `examples/_lib/` (only B0 may);
  - `scripts/`;
  - any other chapter's files, including every verified Ch0–Ch8 file.
- Never delete or reinstall `contracts/node_modules`.
- Every executor, before handing back:
  - runs its own `verify.sh` green;
  - runs `python3 -I scripts/validate.py` and `bash scripts/wordcount.sh _docs/NN-*.md`;
  - runs `npm --prefix contracts run lint`.

**Orchestrator rule (the Wave A slip, now explicit).** At each chapter's checkpoint commit, flip that chapter to `draft` in **both** the Topics table (T10–T14) and the Full chapter inventory, **in the same commit** as the chapter. Then push, so CI runs `verify: NN-*`, the wordcount GATE and `validate.py`'s file and diagram checks against it. "Verified" comes only after BVn passes and the CI `verify: NN-*` job is green.

**Rejected alternatives (one line each)**
- *A fully serial Ch9→Ch10→Ch11→Ch12→Ch13 chain*: it is slower by one step and buys nothing. The two cross-links (Ch10 `nodes`, Ch11 deprecation) are small and fully specified here.
- *Ch12/13 built from Ch8*: they would lose Ch9's exposed/masked error machinery, which Ch12 needs for `BAD_USER_INPUT` cursors and the `GHI345` outage.
- *A runtime toggle in Ch13 between batched and unbatched resolvers*: this means two code paths for every field and is not how either framework is used. The "before" numbers are asserted by Ch12's `verify.sh` instead, which is how Ch7 asserted the "4" that Ch13 reduces.
- *`strawberry.relay` connections*: offset cursors defeat the stability-under-inserts lesson, the descriptions and `totalCount` differ from the canonical SDL, and `relay.Node`/`GlobalID` conflict with the canonical `Node.id` values.
- *Demonstrating a breaking change by committing a breaking SDL edit*: it would make CI red. Fixture directories through `BASE_DIR`/`NEW_DIR` exercise the same script instead.

### Example structure

Same as Wave A §1: a self-contained copy per chapter, with package `com.patterncatalyst.shipping.tracking` and Python `app`. Per chapter, change:
- artifactId `chNN-quarkus-<slug>`;
- Python project `shipping-python-chNN-<slug>`, then **re-run `uv lock`** after the rename;
- `quarkus.otel.service.name` / `OTEL_SERVICE_NAME` = `chNN-<slug>-quarkus|python`;
- the container names and compose `name:`.

Add `python/.ruff_cache/` to each new `.gitignore`.

Pins are identical to Wave A:
- Quarkus platform 3.40.1;
- Strawberry 0.335.0, FastAPI 0.143.2, uvicorn 0.54.0, uv 0.13.1, pydantic-settings 2.16.0;
- the OTel pins as in Ch8;
- `ubi10/openjdk-25:1.24-16` / `-runtime:1.24-16`;
- `ubi10/python-314-minimal:10.2-1791928506`;
- `grafana/otel-lgtm:0.36.0`.

If a newer stable release exists at execution time, **do not** bump it inside Wave B. Record it in the RESUME POINTER for a separate all-examples chore.

### How the schema slice grows

| Ch | Base | Adds to the served slice | Data behaviour |
|---|---|---|---|
| 9 | Ch8 | nothing new in the SDL | re-adds the fault seeds JKL567, MNO901 and PQR234. Exposed errors carry `extensions.code`; unexpected errors are masked as `"Internal server error."`, with the detail kept in the server log |
| 10 | Ch8 | `Query.nodes(ids: [ID!]!): [Node]!` | healthy seed; `nodes` resolves each id through its source (one call per id, which Ch13 batches) |
| 11 | Ch10 | `Itinerary.finalArrivalTime: DateTime!`; `Itinerary.finalArrivalDate` served `@deprecated(reason: "Use `finalArrivalTime`.")` | healthy seed; both fields return the same instant |
| 12 | Ch9 (+ Ch10 `nodes`, + Ch11 deprecation patch) | `Query.cargos` and `Cargo.handlingHistory` with `CargoConnection`, `CargoEdge`, `HandlingEventConnection`, `HandlingEventEdge`, `PageInfo` | Ch12 seed (below). Keyset pagination with opaque cursors; `CargoEdge.node` hydrated per edge through `booking.getCargo`; drops Ch9's fault seeds and keeps its error machinery |
| 13 | Ch12 | same types | every source-backed fan-out batched: SmallRye `@Source List<…>` batch resolvers, Strawberry per-request `DataLoader`s; bulk source operations |

After Ch13 the stacks serve the whole canonical SDL except `Subscription` (Ch21). State this in Ch12's and Ch13's README slice paragraph. Ch9 and Ch10 serve `finalArrivalDate` without the deprecation and without `finalArrivalTime`. That is the contract as it stood before Ch11, which is why conformance still passes (see §5 and Pitfall B-3). Say so in their READMEs.

### Canonical SDL changes (B0, the only `contracts/` edits in the wave)

1. `schema.graphql`, in `type Query` after `node`:
   ```graphql
   """Fetch several objects by their global ids, in the order given. An unknown id yields null at its position."""
   nodes(
     """The global ids of the objects to fetch."""
     ids: [ID!]!
   ): [Node]!
   ```
2. `cargo.graphql`, in `type Itinerary`:
   ```graphql
   """When the final leg arrives."""
   finalArrivalTime: DateTime!
   """When the final leg arrives."""
   finalArrivalDate: DateTime! @deprecated(reason: "Use `finalArrivalTime`.")
   ```
3. B0 proves the change is non-breaking with the real gate:
   - copy the pre-change `contracts/schema` to a temp dir;
   - run `BASE_DIR=<tmp>/schema npm --prefix contracts run breaking`; it must exit 0 and report `✔` additions plus "is deprecated";
   - then run `npm run lint`.
4. B0 re-runs **every** existing `verify.sh` (Ch0, Ch3–Ch8) concurrently and requires all green. Older slices must still conform: `nodes`/`finalArrivalTime` absent is a slice removal, and "no longer deprecated" is NonBreaking. If any fails, stop and report; do not edit a verified chapter.
5. Update `contracts/README.md`: the gate rules, `NEW_DIR`, `BREAKING_RULES`, and the dangerous-change policy (§8 decision 2).

### Canonical seed data additions

**Ch9 (on top of the Ch8 seed: ABC123, XYZ789, the handling store with `evt_1`, `evt_2`).** These re-add the Ch4 fault seeds, with the PQR234 fault moved, because Ch7 removed `DeliverySource`:
- **JKL567**, "Machine parts", USNYC→NLRTM. One leg on **V404X**, USNYC→NLRTM, load `2026-10-01T08:00:00Z`, unload `2026-10-09T14:00:00Z`; finalArrival = unload. The voyage source fails for V404X with the **exposed** error `SourceUnavailable("voyage service unavailable")`, code `SERVICE_UNAVAILABLE`.
- **MNO901**, "Textiles", USNYC→NLRTM. One leg USNYC→NLRTM on V100S whose loadLocation code is **XXBAD**; the location source returns null for it.
- **PQR234**, "Coffee beans", USNYC→NLRTM, itinerary as ABC123, no events. `handling.listEvents("PQR234")` raises an **unexpected** error. Quarkus throws `IllegalStateException`; Python raises `RuntimeError`. The message is exactly `handling projection corrupted on shard handling-primary-3`; the masking assertions grep for the shard name.
- JKL567, MNO901 and PQR234 have no events. Their delivery is derived by the Ch7 rules.

**Ch10/Ch11:** the Ch8 seed unchanged.

**Ch12/Ch13 seed** (replaces the Ch9 fault seeds; ABC123/XYZ789 values unchanged). Each cargo gains a private `bookedAt` (not in the schema) and the booking index stores `routingStatus`. That stored value must equal the derived value; Ch12 asserts this.

| # (newest first) | trackingId | description | route (origin→dest) | arrivalDeadline | bookedAt | itinerary | routingStatus |
|---|---|---|---|---|---|---|---|
| 1 | VWX901 | Furniture | SGSIN→CNSHA | 2026-11-10T00:00:00Z | 2026-09-29T09:00:00Z | 1 leg V300A SGSIN→CNSHA, load 2026-11-02T04:00:00Z, unload 2026-11-06T10:00:00Z; finalArrival 2026-11-06T10:00:00Z | ROUTED |
| 2 | XYZ789 | Frozen seafood | SGSIN→NLRTM | 2026-11-20T00:00:00Z | 2026-09-28T09:00:00Z | null | NOT_ROUTED |
| 3 | STU678 | Rubber goods | SGSIN→NLRTM | 2026-11-20T00:00:00Z | 2026-09-27T09:00:00Z | 1 leg V300A SGSIN→CNSHA (same times as VWX901); finalArrival 2026-11-06T10:00:00Z | MISROUTED (last unload CNSHA ≠ NLRTM) |
| 4 | DEF456 | Auto parts | USNYC→NLRTM | 2026-10-15T00:00:00Z | 2026-09-26T09:00:00Z | as ABC123 (V100S, V200E) | ROUTED |
| 5 | ABC123 | Palletized electronics | USNYC→NLRTM | 2026-10-15T00:00:00Z | 2026-09-25T09:00:00Z | as Ch3 | ROUTED |
| 6 | GHI345 | Medical supplies | USNYC→DEHAM | 2026-10-20T00:00:00Z | 2026-09-24T09:00:00Z | null | NOT_ROUTED |

- `booking.getCargo("GHI345")` fails with the exposed `SourceUnavailable("booking service unavailable")`, code `SERVICE_UNAVAILABLE`. The booking **index** (`listCargos`) still lists it.

**DEF456 events.** registrationTime = completion + 5 min. Ids continue after ABC123's `evt_1`/`evt_2`; the first new registration is **`evt_10`**.

| id | type | location | voyage | completionTime |
|---|---|---|---|---|
| evt_3 | RECEIVE | USNYC | — | 2026-09-30T15:00:00Z |
| evt_4 | LOAD | USNYC | V100S | 2026-10-01T08:15:00Z |
| evt_5 | UNLOAD | DEHAM | V100S | 2026-10-09T14:30:00Z |
| evt_6 | LOAD | DEHAM | V200E | 2026-10-10T06:15:00Z |
| evt_7 | UNLOAD | NLRTM | V200E | 2026-10-11T18:20:00Z |
| evt_8 | CUSTOMS | NLRTM | — | 2026-10-12T08:00:00Z |
| evt_9 | CLAIM | NLRTM | — | 2026-10-12T15:00:00Z |

Derived delivery for DEF456:
- CLAIMED, ROUTED, misdirected false;
- lastKnownLocation NLRTM, currentVoyage null;
- ETA `2026-10-11T18:00:00Z`;
- nextExpectedActivity null.

Derived for VWX901: NOT_RECEIVED, ROUTED, ETA `2026-11-06T10:00:00Z`, next {RECEIVE, SGSIN, null}. For STU678: NOT_RECEIVED, MISROUTED, ETA null, next {RECEIVE, SGSIN, null}.

**Ordering and cursors (Ch12/13, identical on both stacks; byte-identical cursors).**
- `cargos` is newest first by (`bookedAt` desc, `trackingId` desc).
- The cargo cursor is base64url **without padding** (RFC 4648 §5) of UTF-8 `cargo|v1|<bookedAt as YYYY-MM-DDTHH:MM:SSZ>|<trackingId>`.
- `handlingHistory` is newest first by (`completionTime` desc, numeric id sequence desc).
- The event cursor is base64url-nopad of `evt|v1|<completionTime>|<seq>`, where `seq` is the integer in `evt_<seq>`.
- Java: `Base64.getUrlEncoder().withoutPadding()`. Python: `base64.urlsafe_b64encode(b).rstrip(b"=")`.
- Decoding rejects a wrong prefix, wrong version, bad base64 or a bad field count with `BAD_USER_INPUT`.
- Page-size rules: default page size 10 when neither `first` nor `last` is given; `first`/`last` must be in 0..50; combining them is an error.

### Error codes (Ch9 defines; Ch12/13 reuse) — identical strings on both stacks

| `extensions.code` | Raised for | Message (exact) | Exposed? |
|---|---|---|---|
| `SERVICE_UNAVAILABLE` | a source outage (`V404X` voyage, `GHI345` booking) | `voyage service unavailable` / `booking service unavailable` | yes |
| `BAD_USER_INPUT` (Ch12+) | values that pass coercion but are invalid | `first must be between 0 and 50`, `last must be between 0 and 50`, `first and last cannot be combined`, `after is not a valid cursor for this connection`, `before is not a valid cursor for this connection` | yes |
| *(no code)* | anything unexpected | `Internal server error.` | masked; detail only in the server log |

Request errors (parse, validation, coercion) keep each engine's own message. No codes are added for them, because SmallRye and graphql-core generate them before any resolver runs.

### Ports and project names

| Ch | dir | Quarkus | Python | compose `name:` / `PROJECT` | container prefix | artifactId / Python project |
|---|---|---|---|---|---|---|
| 9 | `09-error-handling` | 8190 | 8191 | `gql-ch09-errors` | `ch09-errors-` | `ch09-quarkus-errors` / `shipping-python-ch09-errors` |
| 10 | `10-schema-design` | 8200 | 8201 | `gql-ch10-design` | `ch10-design-` | `ch10-quarkus-design` / `shipping-python-ch10-design` |
| 11 | `11-evolution` | 8210 | 8211 | `gql-ch11-evolution` | `ch11-evolution-` | `ch11-quarkus-evolution` / `shipping-python-ch11-evolution` |
| 12 | `12-pagination` | 8220 | 8221 | `gql-ch12-pagination` | `ch12-pagination-` | `ch12-quarkus-pagination` / `shipping-python-ch12-pagination` |
| 13 | `13-dataloaders` | 8230 | 8231 | `gql-ch13-dataloaders` | `ch13-dataloaders-` | `ch13-quarkus-dataloaders` / `shipping-python-ch13-dataloaders` |

- Container port 8080.
- The Ch10 README notes that 8200 is HashiCorp Vault's default port.
- The observability profile is copied verbatim, with the note "one example's observability profile at a time".

---

## 2. Per chapter

Common to every chapter (as in Wave A §2):
- **Front matter:** `title` (outline title), `order: N`, `part:` exactly as in the Canonical names table (Ch9 "Reliability: Errors & Partial Results"; Ch10/11 "Schema Evolution & the Living Contract"; Ch12/13 "Data Fetching at Scale"), `description`, `duration` (words/200).
- **Length and figures:**
  - 2,800–3,400 prose words (`wordcount.sh`; the gate floor is 2,000);
  - figures via `{% include excalidraw.html file="NN-slug" alt="…full sentences…" caption="Figure N.M — …" %}`;
  - at least one `{% include codetabs.html langs="Quarkus|Python" %}` followed by java then python fences.
- **Last three blocks:** `## On the wire` (curl lines plus the exact values `verify.sh` asserts), then the Decision callout naming Ch2's axes, then `## Where this goes next`.
- **Prose rules:**
  - no `{{` or `{%` in prose outside includes/fences (the `unguarded-liquid` check);
  - cite books by **chapter title, checked against the ToC** (the O'Reilly search tool or the publisher page); never by number alone;
  - spec sections by **name**; use the term "execution error" and mention once that older editions say "field error".
- **Diagram specs:** `diagrams/NN-slug.py` (pattern `06-parallel-siblings.py` for timelines, `02-tracking-view-topology.py` for graphs). Architecture figures are `diagrams/examples/NN-slug-architecture.py` writing `examples/NN-slug/architecture.{svg,excalidraw}` and are not counted. Highlighted nodes use `accent`. Timeline figures are drawn from **one real run's** source-call log, stated in the spec docstring.
- **verify.sh skeleton:** Ch8's skeleton:
  - `run_stack_check <stack> <url> …` per stack, then `PASS` when both pass;
  - `source_calls_reset` before each counted case;
  - one `__type` per request;
  - the scalar `kind`/`specifiedByURL` loop;
  - `assert_sdl_conforms` last;
  - the scratch dir cleaned with the new `on_exit` hook (§3), not a hand-chained trap.
- **README sections** (Ch8 order): The served slice, Run it, The source-call log (lab only), Ports, On the wire, Code-first notes (spike results), Diagram.

### Ch9: Error handling

**Files:** `_docs/09-error-handling.md`, `examples/09-error-handling/` (from Ch8).

**Learning goals.** By the end of the chapter the reader can:
- tell request errors from execution errors by shape (data absent vs partial data plus `path`) and by origin;
- read `message`/`locations`/`path`/`extensions`;
- predict where nulls land when an error meets non-null types (Ch4);
- design a stable `extensions.code` vocabulary;
- mask unexpected failures on both stacks while keeping the detail in server logs;
- state what GraphQL-over-HTTP says about status codes for each media type, and what each stack actually does;
- choose between `errors[]`, payload `userErrors` and result unions.

**H2 outline**
1. *Two kinds of failure, one array.* Request errors (parse, validate, coerce, operation selection: no `data`) versus execution errors (a resolver failed: `data` plus `path`). Uses the spec's terms.
2. *Anatomy of an error.* `message`, `locations`, `path` (indices are numbers, aliases appear), `extensions` (the only place for custom keys). Order across errors is not significant.
3. *Partial data: errors beside data.* The three-alias query (Figure 9.1).
4. *Where the null lands.* The Ch4 rule in this light: one error and one null hole, and the hole is at the nearest nullable ancestor (`bug` → `cargo` null).
5. *A code vocabulary in `extensions`.* The table above. Codes are contract, messages are not. Why request errors keep engine messages.
6. *Masking what clients must not see.*
   - SmallRye: unchecked messages are hidden by default (Ch4's `"System error"`); `show-runtime-exception-message` is an allowlist; `default-error-message`; `error-extension-fields`; `@ErrorCode`; `print-data-fetcher-exception` for the log.
   - Strawberry: `MaskErrors` with a predicate (an allowlist of `ExposedError`); the server log.
   - Masking is an allowlist on both stacks (Figure 9.3).
7. *Status codes and media types.* GraphQL-over-HTTP: `application/json` → 200 for any well-formed response; `application/graphql-response+json` → 4xx/5xx when `data` is absent, 2xx once execution started. Observed: Quarkus echoes `application/graphql-response+json` with 200 for request errors (a deviation); Strawberry answers `application/json` (the permitted fallback). Monitoring implications (Ch19 forward).
8. *Errors as data.* Ch8's `userErrors` contrasted with a result union (`union RegisterHandlingEventResult = RegisterHandlingEventSuccess | ValidationFailed`), shown as an **SDL sketch only** (not served, no codetabs; see §8 decision 4). The trade-offs: exhaustiveness, `__typename` branching, evolution (adding a member is dangerous, Ch11), and why the book keeps payload `userErrors`. The Decision callout of Ch2 holds.
9. *What a message should say.* Human, specific, no internals; stable codes for machines.
10. On the wire / Decision / Where this goes next.

**Example design**
- **Quarkus**
  - New `SourceUnavailableException extends RuntimeException`, annotated `@ErrorCode("SERVICE_UNAVAILABLE")`.
  - `VoyageSource.getVoyage` returns `Uni.createFrom().failure(new SourceUnavailableException("voyage service unavailable"))` for V404X.
  - `HandlingSource.listEvents` fails with `IllegalStateException("handling projection corrupted on shard handling-primary-3")` for PQR234.
  - The fault seeds go in `TrackingData`.
  - `application.properties` adds:
    ```
    quarkus.smallrye-graphql.show-runtime-exception-message=com.patterncatalyst.shipping.tracking.SourceUnavailableException
    quarkus.smallrye-graphql.default-error-message=Internal server error.
    quarkus.smallrye-graphql.error-extension-fields=code
    quarkus.smallrye-graphql.print-data-fetcher-exception=true
    ```
  - Optional `ErrorLogging` bean observing `@ErrorDataFetch` to log `executionId` + path. Include it only if `print-data-fetcher-exception` alone does not put the shard string in the log (spike).
- **Python**
  - New `app/errors.py`:
    ```python
    class ExposedError(Exception):
        code: ClassVar[str]
        def __init__(self, message: str) -> None:
            super().__init__(message)
            self.extensions = {"code": self.code}

    class SourceUnavailable(ExposedError):
        code = "SERVICE_UNAVAILABLE"

    def should_mask(error: GraphQLError) -> bool:
        return error.original_error is not None and not isinstance(error.original_error, ExposedError)
    ```
  - `schema = strawberry.Schema(..., extensions=[MaskErrors(should_mask_error=should_mask, error_message="Internal server error.")])`.
  - Sources raise `SourceUnavailable("voyage service unavailable")` and `RuntimeError("handling projection corrupted on shard handling-primary-3")`.
- **Spikes (record the results in the README):**
  - (a) Does SmallRye emit `extensions.code` for a **hidden** exception, for example `illegal-state`? If yes: try `error-extension-fields` combinations. If none hides it, assert the observed value, state in prose that it reveals the exception's simple class name, and list it under §5.
  - (b) Does `classification` still appear when it is not in `error-extension-fields`?
  - (c) Does Strawberry log the original exception (with the shard string) **before** `MaskErrors` anonymises it? If not, override `Schema.process_errors` in a `strawberry.Schema` subclass (the documented logging hook) to log `error.original_error`.
  - (d) MNO901's null-in-non-null on Python carries `original_error=TypeError`, so `should_mask` masks it; on Quarkus the graphql-java `NonNullableFieldWasNullError` is not a fetch exception and is shown. Assert per stack and explain.
- Debug endpoints and the source-call log are copied unchanged.

**verify.sh assertions (both stacks unless marked)**
1. Exposed execution error. Query: JKL567 `cargo(trackingId:"JKL567"){trackingId itinerary{legs{loadLocation{unLocode} voyage{number}}}}`.
   - `assert_error_count 1`; `assert_error_path ["cargo","itinerary","legs",0,"voyage"]`;
   - `assert_error_message_at … "voyage service unavailable"` (now identical on both stacks; in Ch4 it differed);
   - `assert_error_extension … code '"SERVICE_UNAVAILABLE"'`; `assert_error_shape execution` (message, locations, path);
   - `assert_null_at '.data.cargo.itinerary.legs.0.voyage'`; loadLocation `USNYC`.
2. Masked execution error. Query: PQR234 `cargo{trackingId delivery{transportStatus}}`.
   - `assert_null_at '.data.cargo'`; path `["cargo","delivery"]`; message exactly `Internal server error.`;
   - `assert_body_not_contains` for each of `handling-primary-3`, `IllegalStateException`, `RuntimeError`, `com.patterncatalyst`;
   - `assert_error_extension_absent … code` on Python. On Quarkus: absent, or the spike-(a) observed value.
   - `compose_logs <service> | grep -c handling-primary-3` ≥ 1: the detail is kept server-side.
3. Partial data, three aliases (Figure 9.1). Query:
   ```graphql
   { ok: cargo(trackingId:"ABC123"){trackingId}
     outage: cargo(trackingId:"JKL567"){itinerary{legs{voyage{number}}}}
     bug: cargo(trackingId:"PQR234"){delivery{transportStatus}} }
   ```
   - error count 2; paths `["outage","itinerary","legs",0,"voyage"]` and `["bug","delivery"]`;
   - `.data.ok.trackingId` = `ABC123`; `assert_null_at '.data.bug'`; `json_keys .data` = `ok,outage,bug`.
4. Null propagation interplay: MNO901 `cargo{trackingId itinerary{legs{loadLocation{unLocode}}}}`.
   - `assert_null_at '.data.cargo.itinerary'`; path `["cargo","itinerary","legs",0,"loadLocation"]`; count 1;
   - message: Quarkus contains `loadLocation`; Python `Internal server error.` (spike d, per-stack expected value passed in).
5. Request error shape: `{ cargo(trackingId:"ABC123"){ weight } }`.
   - `assert_has_errors`, `assert_no_data`, `assert_error_shape request` (every error has `message` and `locations`, none has `path`);
   - 0 source calls.
6. Status codes and media types, via `gql_meta <url> <accept> <query>`:

   | case | `Accept: application/json` | `Accept: application/graphql-response+json` |
   |---|---|---|
   | request error (case 5) | `200 application/json` both | Quarkus `200 application/graphql-response+json`, Python `200 application/json` |
   | execution error (case 1) | `200 application/json` | Quarkus `200 application/graphql-response+json`, Python `200 application/json` |

   Expected values are passed per stack into `run_stack_check`. If an observation differs from Wave A §9, stop and report before changing prose.
7. Errors as data, the contrast: `registerHandlingEvent` LOAD at DEHAM on `V999X`.
   - `assert_no_errors`; `userErrors` `[{"code":"UNKNOWN_VOYAGE","field":["input","voyageNumber"]}]`;
   - `handlingEvent` null; 0 `handling.appendEvent`.
8. Masking does not hide exposed errors inside a batch of siblings: `{ a: voyage(voyageNumber:"V404X"){number} b: voyage(voyageNumber:"V100S"){number} }`.
   - count 1, path `["a"]`, code `SERVICE_UNAVAILABLE`, `.data.b.number` `V100S`, `assert_null_at '.data.a'`.
9. Scalar checks; `assert_sdl_conforms` (no SDL change).

**Figures (4)**
- `09-partial-data-errors` (data movement): the case-3 response.
  - Left: the `data` tree with three branches; `ok` is filled, `outage…voyage` is a null hole, `bug` is a null hole at the cargo.
  - Right: `errors[]`, two entries; an amber arrow from each `path` to its hole.
  - Note: "a path names where it broke; the null lands at the nearest nullable ancestor".
- `09-error-taxonomy`: request lane (parse → validate → coerce → select operation) exiting to "errors, no data, no resolver ran". Execution lane (resolver → exposed or unexpected) exiting to "data + errors with path". Domain lane (validation in the mutation) exiting to "data with userErrors, no errors". Each lane is tagged with its HTTP status under each media type.
- `09-error-masking` (data movement):
  - source throws → resolver → engine error;
  - allowlist check (SmallRye `show-runtime-exception-message` / Strawberry `should_mask`);
  - exposed path → client gets message + `code`; masked path → client gets `Internal server error.`;
  - side arrow to the server log with the full detail and request id.
- `09-failure-shapes`: one failure (an unknown voyage) in three envelopes side by side: top-level `errors[]`, payload `userErrors`, and a result union with `__typename`, each with what the client must branch on.

**Citations.**
- Spec "Response" (the "Errors" / "Error Result Format" text and `path`/`locations`) and "Handling Execution Errors".
- GraphQL-over-HTTP "Status Codes" and media types.
- *GraphQL Best Practices* (its error-handling chapter, by title after checking the ToC).
- *GraphQL in Action* "Implementing mutations" (userErrors context, title as in Wave A).
- Quarkus SmallRye GraphQL guide (error extensions/hiding) and Strawberry docs ("Dealing with errors", `MaskErrors`).

### Ch10: Schema design patterns

**Files:** `_docs/10-schema-design-patterns.md`, `examples/10-schema-design/` (from Ch8).

**Learning goals.** By the end of the chapter the reader can:
- design demand-first (from the screens and calls clients make, not the tables);
- apply naming conventions consistently and spot an inconsistency (`finalArrivalDate` on a `DateTime`, the Ch11 hook);
- use Node and global ids as an identity contract (opaque, refetchable, unique across types) with `node`/`nodes`;
- choose interfaces vs unions; choose objects over foreign keys (with `HandlingEvent.trackingId` as a deliberate, documented denormalization);
- shape mutations as one `input` plus one `Payload`;
- use enums for closed sets, nullable fields across service boundaries, and connections for unbounded lists;
- check conventions mechanically on both the canonical SDL and the live schemas.

**H2 outline**
1. *Design from demand.* The tracking screen's three panels map to fields, and fields map to owners (Figure 10.1). What stays out of the graph (Money, booking writes).
2. *Names are the interface.* PascalCase types, camelCase fields and args, SCREAMING_SNAKE enum values; `…Input`, `…Payload`, `…Connection`/`…Edge`; time-valued fields end in `Time`/`Deadline`. The one exception (`finalArrivalDate`), handed to Ch11.
3. *Identity: `Node` and global ids.* Unique across the graph, opaque by contract even when readable, prefix dispatch; the refetch rule (`node(id: x.id).id == x.id`); `nodes(ids:)` for client caches. Base64-encoded "Type:key" ids as the alternative, and why opacity matters more than format (Figure 10.2).
4. *Objects, not foreign keys.* `Leg.voyage`, not `voyageNumber`; the cost moves to resolvers (Ch13). `HandlingEvent.trackingId` stays as resilience when the cargo service is down.
5. *Interfaces versus unions.* `Node` as a shared contract; unions for disjoint results (Ch9 sketch). `possibleTypes` now includes `HandlingEvent`.
6. *Inputs and payloads.* One `input` argument, one payload per mutation, `userErrors`; optional input fields so additions stay safe (Ch11). `@oneOf` input objects mentioned as an option. **Spike:** whether the current spec edition defines it and whether both stacks support it at these pins (`io.smallrye.graphql.api.OneOf` exists; Strawberry `one_of=True`). Prose only, not served.
7. *Enums, scalars and nullability as design.* Closed sets, string-backed custom scalars, and the Ch4 fuses as design decisions.
8. *Lists that grow are connections.* A forward pointer to Ch12, with `nodes` as the bounded exception.
9. *Checking design mechanically.* GraphQL ESLint on the canonical SDL plus the live-schema convention check in `verify.sh`.
10. On the wire / Decision / next.

**Example design**
- **Quarkus**
  ```java
  @Query @NonNull
  public Uni<List<Node>> nodes(@Name("ids") @NonNull List<@NonNull @Id String> ids, Context context)
  ```
  - The `@Description` texts are exactly the canonical ones.
  - The body maps each id through the existing `node` dispatch (extract a private `resolveNode(request, id)`), then `Uni.join().all(unis).andFailFast()`, preserving order.
  - An empty list returns `Uni.createFrom().item(List.of())`.
- **Python**
  ```python
  async def nodes(self, info, ids: Annotated[list[strawberry.ID], strawberry.argument(description=…)]) -> list[Node | None]
  ```
  - The body is `asyncio.gather` over the same `resolve_node` helper (extracted from `node`).
- No new sources. Each id is one source call, the N+1 that Ch13 batches.

**verify.sh assertions**
1. Refetch rule for each implementer: obtain the id naturally, then `node(id:$id){id __typename ... on X {<field>}}` and assert `id` equals, `__typename` equals, and the fragment field is the seed value.
   - Cargo via `cargo(ABC123){id}` → `cargo_ABC123`, fragment `trackingId` ABC123;
   - Location via `cargo(ABC123){itinerary{legs{loadLocation{id}}}}` leg 0 → `loc_USNYC`, `unLocode`;
   - Voyage via `legs{voyage{id}}` leg 1 → `voy_V200E`, `number`;
   - HandlingEvent `evt_1` → `type` RECEIVE.
2. `nodes(ids:["cargo_ABC123","loc_NLRTM","nope","voy_V200E","cargo_ABC123"]){__typename}`: `assert_json_eq '[{"__typename":"Cargo"},{"__typename":"Location"},null,{"__typename":"Voyage"},{"__typename":"Cargo"}]'`, no errors.
   - Source calls: `assert_source_calls_exactly booking.getCargo:ABC123,location.getLocation:NLRTM,voyage.getVoyage:V200E,booking.getCargo:ABC123` ("nope" makes no call; the duplicate id is fetched twice, which Ch13 fixes).
3. `nodes(ids: [])` → `[]`.
4. `__type(name:"Node"){possibleTypes{name}}` sorted `[Cargo,HandlingEvent,Location,Voyage]`.
5. Live convention check: one `__schema{types{name kind description fields{name description args{name description}} inputFields{name description} enumValues{name description}}}` request per stack, piped to a chapter-local python checker in `verify.sh`.
   - It skips `__*`, the built-in scalars, and `$LGTM_SDL_FRAMEWORK_TYPES`.
   - It asserts:
     - type names PascalCase; fields/args camelCase; enum values `^[A-Z][A-Z0-9_]*$`;
     - every INPUT_OBJECT ends in `Input`;
     - every Mutation field has exactly one arg `input` of `NON_NULL`→INPUT_OBJECT and returns NON_NULL→OBJECT named `…Payload`;
     - every type/field/arg/enum value has a non-empty description;
     - every implementer of `Node` has `id: ID!`.
   - Prints offenders on failure.
6. `npm --prefix "$REPO_ROOT/contracts" run lint` exits 0.
7. Payload invariant: a failing mutation (RECEIVE + V100S) still returns non-null `registerHandlingEvent` with `userErrors` length 1 and `assert_no_errors`.
8. Scalar checks; `assert_sdl_conforms` (now serves `Query.nodes`).

**Figures (2)**
- `10-demand-oriented-schema` (data movement): the tracking screen's panels (status header, route, timeline) → the fields each one selects → the owning sources (booking, routing, voyage, location, handling). Amber arrows show one screen, one query, five owners.
- `10-node-identity` (data movement): ids flowing from three paths (`cargo.id`, `leg.loadLocation.id`, `handlingEvent.id`) into a client cache keyed by id. `node(id:)`/`nodes(ids:)` → prefix dispatch → owning source → the same object back.

**Citations.**
- *GraphQL Best Practices* (its schema-design chapter, title checked).
- *GraphQL in Action* "Designing a GraphQL schema".
- Relay Global Object Identification spec; spec "Interfaces", "Unions", "Input Objects" (and "OneOf Input Objects" if spike 6 confirms it is in the current edition).
- GraphQL ESLint docs.

### Ch11: Evolution and versioning

**Files:** `_docs/11-evolution-and-versioning.md`, `examples/11-evolution/` (from Ch10).

**Learning goals.** By the end of the chapter the reader can:
- explain why GraphQL evolves one schema continuously instead of versioning URLs, and when a new endpoint is still justified;
- classify a change as safe, dangerous or breaking from the client's point of view, including the nullability asymmetry (tightening an output is safe for clients, loosening is breaking; inputs are the reverse);
- run the deprecation lifecycle (add the replacement → deprecate with a reason → observe usage → remove deliberately);
- run the breaking gate on fixtures and read its output;
- decide the gate policy for dangerous changes.

**H2 outline**
1. *One schema, many clients, no version numbers.* Additive evolution; field-level deprecation; why `/v2` is a last resort. DDIA on backward and forward compatibility (its encoding/evolution chapter, title checked).
2. *Safe, dangerous, breaking.* The inspector's three levels with this schema's examples (Figure 11.1). Ch3's enum warning and Ch8's optional-input design pay off here.
3. *Nullability cuts both ways.* Output tighten is safe for clients but drift for the conformance gate (Ch5); output loosen breaks; required input breaks; optional input is safe.
4. *The deprecation path, live.* `finalArrivalDate` → `finalArrivalTime` on both stacks: still executable, flagged in introspection, hidden by default from `fields`.
5. *Removing a field deliberately.* The default gate fails; `suppressRemovalOfDeprecatedField` turns a deprecated removal into dangerous; usage evidence first (Ch19 forward) (Figure 11.2).
6. *Running the gate.* `contracts/scripts/breaking.sh`: base ref vs working tree; `BASE_DIR`/`NEW_DIR` for fixtures; `BREAKING_RULES`; why `main` is the baseline; the first-introduction skip.
7. *Should dangerous changes fail?* The policy (§8 decision 2): report as PR warnings, fail on breaking, strict mode for opt-in teams.
8. *What the gate cannot see.* Behaviour changes, default-value semantics, deprecation state in the slice conformance check (hence `assert_deprecated`).
9. *Evolving the two stacks.* SmallRye and Strawberry deprecation spellings; tests stay green.
10. On the wire / Decision / next.

**Deprecation patch (Ch11, also applied by B4 to Ch12):**
- **Quarkus:** the `Itinerary` record gains a component `@NonNull @Description("When the final leg arrives.") Instant finalArrivalTime`, and the `finalArrivalDate` component gains `@io.smallrye.graphql.api.Deprecated(reason = "Use `finalArrivalTime`.")`.
  - **Spike:** that this produces `isDeprecated: true` with exactly that reason and no "(ISO-8601)" side effects (`ContractSchemaDetails` already strips that suffix).
  - Fallback: `@java.lang.Deprecated` plus whatever reason source SmallRye reads. Record which worked.
  - Both components get the same `Instant` in the seed/derivation.
- **Python:**
  ```python
  final_arrival_time: datetime = strawberry.field(description="When the final leg arrives.")
  final_arrival_date: datetime = strawberry.field(description="When the final leg arrives.", deprecation_reason="Use `finalArrivalTime`.")
  ```

**Example design**
- The stack code is Ch10 plus the deprecation patch.
- Fixture tooling lives in `verify.sh` with a stdlib python editor:
  - copy `contracts/schema` to `$TMP/base/schema` and `$TMP/new/schema`;
  - apply one textual edit to `new` with `python3 -I -c` (`str.replace` with `count == 1` enforced, otherwise "fixture did not apply" → FAIL);
  - run `assert_gate`.
- No fixture files are committed; the edits are listed in `verify.sh` and the README table.

**verify.sh assertions**
1. Both fields, one value: `cargo(ABC123){itinerary{finalArrivalTime finalArrivalDate}}` → both `2026-10-11T18:00:00Z`; `assert_no_errors`. A deprecated field still executes.
2. `assert_deprecated <url> Itinerary finalArrivalDate "Use \`finalArrivalTime\`."` and `assert_not_deprecated <url> Itinerary finalArrivalTime`.
3. `__type(name:"Itinerary"){fields{name}}` (default `includeDeprecated:false`) does not list `finalArrivalDate`; with `fields(includeDeprecated:true)` it does.
4. Stack conformance: `assert_sdl_conforms` on both stacks.
5. The gate on fixtures (`assert_gate <rc> <needle> <base> <new> [rules]`). Run once, not per stack, after both stack checks:

   | case | edit to `new` | rules | rc | needle |
   |---|---|---|---|---|
   | no change | none | — | 0 | `No changes detected` |
   | the real Ch11 change | `base` = canonical with `finalArrivalTime` + `@deprecated` removed; `new` = canonical | — | 0 | `is deprecated` |
   | safe: add field | add `"""IANA time zone, for example \`Europe/Amsterdam\`."""` + `timeZone: String` to `Location` | — | 0 | `Field 'timeZone' was added to object type 'Location'` |
   | safe: add optional input field | add described `operatorId: String` to `RegisterHandlingEventInput` | — | 0 | `operatorId` |
   | safe: tighten output | `itinerary: Itinerary` → `itinerary: Itinerary!` | — | 0 | `Cargo.itinerary` |
   | dangerous: enum value | add described `TRANSSHIP` to `HandlingEventType` | — | 0 | `Enum value 'TRANSSHIP' was added to enum 'HandlingEventType'` |
   | dangerous → strict | same edit | `dangerousBreaking` | 1 | `TRANSSHIP` |
   | dangerous: optional argument | add described `destination: UnLocode` arg to `Query.cargos` | — | 0 | `destination` |
   | breaking: remove field | delete `Leg.unloadTime` and its description | — | 1 | `Field 'unloadTime' was removed from object type 'Leg'` |
   | breaking: loosen output | `trackingId: TrackingId!` (on `Cargo`) → `trackingId: TrackingId` | — | 1 | `TrackingId!` |
   | breaking: required input | add described `operatorId: String!` to the input | — | 1 | `operatorId` |
   | breaking: remove enum value | delete `UNKNOWN` (and its description) from `TransportStatus` | — | 1 | `UNKNOWN` |
   | lifecycle: remove the deprecated field | delete `finalArrivalDate` (and its description) | — | 1 | `(deprecated) was removed` |
   | lifecycle: deliberate removal | same edit | `suppressRemovalOfDeprecatedField` | 0 | `finalArrivalDate` |

   - Needles are matched against the gate output **excluding** `lib.sh:` lines (Pitfall §7.5 analogue).
   - Executors must confirm each needle against the actual inspector message text and adjust only the needle, never the classification.
6. `npm --prefix contracts run lint` exits 0.
7. Scalar checks.

**Figures (2)**
- `11-change-classes`: three columns (safe ✔, dangerous ⚠, breaking ✖), each listing this schema's examples from the table. The gate result is shown under each column for the default and strict modes, plus a strip for nullability direction (output vs input).
- `11-deprecation-lifecycle` (data movement): a timeline.
  1. Add `finalArrivalTime` (✔).
  2. Deprecate `finalArrivalDate` with a reason (✔); both stacks serve both; clients migrate.
  3. Usage drops to zero (operation telemetry, Ch19).
  4. Removal: ✖ by default, ⚠ with `suppressRemovalOfDeprecatedField`, the explicit sign-off.

**Citations.**
- GraphQL Inspector docs (diff, rules).
- spec "@deprecated" / "Schema Introspection" (`includeDeprecated`).
- *DDIA* 2nd ed. (its encoding/evolution chapter, title checked; compatibility directions).
- *GraphQL Best Practices* (schema evolution, title checked).

### Ch12: Connections and pagination

**Files:** `_docs/12-connections-and-pagination.md`, `examples/12-pagination/` (from Ch9, plus Ch10 `nodes` ported, plus the Ch11 deprecation patch, plus the Ch12 seed).

**Learning goals.** By the end of the chapter the reader can:
- explain offset vs keyset pagination and why keyset survives inserts (DDIA, ordered index range scans);
- implement Relay Cursor Connections exactly (edges/node/cursor, `PageInfo`, `first`/`after` and `last`/`before` semantics);
- keep cursors opaque and versioned;
- validate pagination arguments as `BAD_USER_INPUT`;
- explain `totalCount`'s cost;
- read the `edge.node` fuse on a live page;
- measure the N+1 that hydrating nodes causes.

**H2 outline**
1. *Lists that grow need pages.* Unbounded lists versus cost (Ch14 forward).
2. *Offset versus keyset.* DDIA: offset re-scans and shifts; keyset seeks on an ordered key (Figure 12.3).
3. *The connection shape.* Connection → edges → `{cursor, node}`, `pageInfo`, `totalCount`; the canonical types (Figure 12.1).
4. *Cursors are opaque.* What this example encodes (prefix, version, sort key) and why clients must not parse it; cross-connection cursors rejected.
5. *Paging forward.* `first`/`after`; `hasNextPage`; `endCursor`.
6. *Paging backward.* `last`/`before`; edges stay in connection order; `hasPreviousPage`. The spec permits approximation in the opposite direction; this example computes both exactly (Figure 12.2).
7. *Stable under inserts.* A late-registered event lands in the range already read; keyset does not repeat it, offset would.
8. *Filters and `totalCount`.* `routingStatus` pushed down to the booking index; counting as a cost; nullable `totalCount`.
9. *Bad arguments are errors.* `BAD_USER_INPUT` per the spec's "first must be non-negative" and the server's own limits; where the null lands (`data` for `Query.cargos!`, `cargo` for `handlingHistory!`).
10. *One bad node, one null edge.* The Ch4 fourth fuse live with `GHI345` (Figure 12.4).
11. *Code-first connections on two stacks.* Plain types on both, and why not `strawberry.relay`.
12. *The cost of hydrating a page.* 29 source calls for a four-cargo page; Ch13's number.
13. On the wire / Decision / next.

**Example design (both stacks)**
- **Sources**
  - `BookingSource.listCargos(request, routingStatus, page)`: keyset over the booking index. It returns `{entries:[(trackingId, bookedAt)], hasNext, hasPrev, totalCount}`. Log key = the `routingStatus` value or `*`.
  - `HandlingSource.pageEvents(request, trackingId, page)`: same shape over the store. Log key = trackingId.
  - `booking.getCargo` hydrates `CargoEdge.node`, per edge.
- **Shared per-stack `Pagination` helper.** It owns:
  - the argument rules (default 10, range 0..50, no `first`+`last`);
  - cursor encode/decode;
  - the slice algorithm (Relay spec "Pagination algorithm": apply the after/before bounds, then first/last).
- **Quarkus**
  - Records `CargoConnection`, `CargoEdge`, `HandlingEventConnection`, `HandlingEventEdge`, `PageInfo` with canonical `@Description`s; `edges` is `@NonNull List<@NonNull CargoEdge>`.
  - `CargoEdge` holds `cursor` + `@Ignore String trackingId`; `node` is a `@Source CargoEdge` resolver returning `Uni<Cargo>` (nullable).
  - `Query.cargos(Integer first, String after, Integer last, String before, RoutingStatus routingStatus, Context)` returns `@NonNull Uni<CargoConnection>`.
  - `Cargo.handlingHistory` is a `@Source Cargo` resolver with the four arguments returning `@NonNull Uni<HandlingEventConnection>`.
  - New `BadUserInputException extends RuntimeException`, annotated `@ErrorCode("BAD_USER_INPUT")`, appended to `show-runtime-exception-message` (comma-separated).
  - `HandlingStore` keeps a sorted view.
- **Python**
  - Plain `@strawberry.type` classes with canonical descriptions.
  - Arguments use `strawberry.Maybe[int | None]` etc. so the SDL prints **no `= null`**. **Spike:** Maybe on resolver arguments at 0.335; fallback is documented in the README.
  - `BadUserInput(ExposedError)` with code `BAD_USER_INPUT`.
- The seed is the Ch12 table; the Ch9 fault seeds are removed.

**verify.sh assertions (both stacks, in this order; handling state carries forward)**
1. Ch1's query delivered: `cargo(ABC123){handlingHistory(first:2){edges{node{id}} pageInfo{hasNextPage}}}` → ids `[evt_2, evt_1]`, `hasNextPage` false.
2. Forward cursor movement, `cargos(first:2[, after:$c]){edges{cursor node{trackingId}} pageInfo{hasNextPage hasPreviousPage startCursor endCursor} totalCount}`:
   - page 1: `[VWX901, XYZ789]`, next true, prev false, totalCount 6, `startCursor` == `edges[0].cursor`, `endCursor` == `edges[1].cursor`;
   - page 2 (after page-1 `endCursor`): `[STU678, DEF456]`, next true, prev true;
   - page 3: `[ABC123, null]` (see case 6), next false, prev true;
   - `edges[0].cursor` of page 1 equals the literal base64url of `cargo|v1|2026-09-29T09:00:00Z|VWX901` (computed in verify.sh with python `base64`). The same literal on both stacks: one encoding, two stacks.
   - `assert_body_not_contains` cursor-plaintext `VWX901` within `.edges[].cursor` (opacity).
3. Backward:
   - `cargos(last:2, before:<cursor of ABC123>)` → `[STU678, DEF456]` (connection order kept), prev true, next true;
   - `cargos(last:2)` → `[ABC123, GHI345-edge]`, prev true, next false.
4. Filter and consistency:
   - `cargos(routingStatus: MISROUTED){edges{node{trackingId delivery{routingStatus}}} totalCount}` → `[STU678]`, routingStatus `MISROUTED`, totalCount 1;
   - `NOT_ROUTED` → `[XYZ789, GHI345]` (node 2 null, case 6), XYZ789 delivery `NOT_ROUTED`, totalCount 2;
   - `ROUTED` → trackingIds `[VWX901, DEF456, ABC123]`, totalCount 3.
   - Source calls for the MISROUTED case include exactly one `booking.listCargos:MISROUTED`.
5. `first:0` → edges `[]`, next true, `startCursor`/`endCursor` null (`assert_null_at`).
6. The edge fuse on page 3:
   - `assert_error_count 1`; `assert_error_path ["cargos","edges",1,"node"]`; code `SERVICE_UNAVAILABLE`; message `booking service unavailable`;
   - `assert_null_at '.data.cargos.edges.1.node'`; `.edges.1.cursor` non-empty; `.edges.0.node.trackingId` `ABC123`; `pageInfo` present.
7. Bad arguments. Each gives code `BAD_USER_INPUT` and the exact message:
   - `cargos(first:-1)`, `cargos(first:51)` (`first must be between 0 and 50`): `assert_null_at '.data'`;
   - `cargos(first:1,last:1)` (`first and last cannot be combined`);
   - `cargos(after:"bm9wZQ")` (`after is not a valid cursor for this connection`);
   - an event cursor passed to `cargos(after:)`: same message;
   - a cargo cursor passed to `cargo(DEF456){handlingHistory(after:)}` → `assert_null_at '.data.cargo'`, path `["cargo","handlingHistory"]`.
8. Stability under inserts on `cargo(DEF456){handlingHistory(first:3[,after]){edges{cursor node{id}} pageInfo{hasNextPage endCursor} totalCount}}`:
   - page 1 → `[evt_9, evt_8, evt_7]`, totalCount 7;
   - register CUSTOMS DEF456 NLRTM `2026-10-11T20:00:00Z` (no key) → `evt_10`;
   - page 2 with page-1 `endCursor` → `[evt_6, evt_5, evt_4]`: no repeat of `evt_7`, no skip;
   - page 3 → `[evt_3]`, next false;
   - a fresh `first:3` → `[evt_9, evt_8, evt_10]`, totalCount 8. Its third item is `evt_10`, so an offset-3 page would begin at `evt_7` again. The prose and Figure 12.3 cite this exact pair.
9. `last:2` on handlingHistory → `[evt_4, evt_3]`, `hasPreviousPage` true.
10. Argument defaults: `__type(name:"Query"){fields{name args{name defaultValue}}}`, filtered to `cargos`, has every `defaultValue` null. The same on `__type(name:"Cargo")` for `handlingHistory` (the Pitfall §7/Ch8 `= null` check).
11. The N+1 baseline (the number Ch13 reduces), `source_calls_reset` first. Query `Q_FAN`:
    ```graphql
    cargos(first:4){edges{node{trackingId itinerary{legs{voyage{number} loadLocation{unLocode} unloadLocation{unLocode}}} delivery{transportStatus}}}}
    ```
    Counts:
    - total `assert_source_call_count calls '*' '*' 29`;
    - `booking listCargos 1`, `booking getCargo 4`, `routing getItinerary 8`, `handling listEvents 4`, `voyage getVoyage 4`, `location getLocation 8`;
    - `assert_source_call_keys calls voyage getVoyage V300A,V300A,V100S,V200E` (the same key fetched twice).
12. `nodes` N+1 baseline: `nodes(ids:["cargo_ABC123","cargo_XYZ789","loc_DEHAM","loc_NLRTM","voy_V100S"])` → 5 calls.
13. Deprecation patch present: `assert_deprecated … Itinerary finalArrivalDate …`.
14. Scalar checks; `assert_sdl_conforms` (now serving the connection types: only `Subscription` remains a slice removal).

**Figures (4)**
- `12-connection-anatomy`: `Query.cargos` → `CargoConnection` {edges `[CargoEdge!]!`, pageInfo `PageInfo!`, totalCount `Int`} → `CargoEdge` {cursor `String!`, node `Cargo` (nullable, marked as a fuse)}, with the four `PageInfo` fields annotated.
- `12-cursor-movement` (data movement): the six cargos in index order as a strip. Three forward pages of 2, with `endCursor` handed to the next `after`. Below, the backward request `last:2, before:<ABC123>` selecting the same middle page. The `hasNext`/`hasPrev` values are printed per page.
- `12-offset-vs-keyset` (data movement): the DEF456 history before and after `evt_10` is inserted. The offset lane shows page 2 = items 4–6 now starting at `evt_7` (a duplicate); the keyset lane shows `after=evt_7` seeking straight to `evt_6`. DDIA is cited in the note.
- `12-edge-node-fuse` (data movement): the page-3 response; edge 1 keeps its cursor while `node` is null; `errors[0].path` `["cargos","edges",1,"node"]` with an amber arrow; `pageInfo` intact.

**Citations.**
- Relay "GraphQL Cursor Connections" (connection types, arguments, pagination algorithm, `PageInfo`).
- *DDIA* 2nd ed. (its storage-and-retrieval / indexing chapter for ordered range scans; title checked).
- *Full Stack GraphQL Applications* (its pagination coverage, title checked).
- spec "List" and "Non-Null" (the fuse).

### Ch13: The N+1 problem and DataLoaders

**Files:** `_docs/13-n-plus-one-and-dataloaders.md`, `examples/13-dataloaders/` (from Ch12).

**Learning goals.** By the end of the chapter the reader can:
- count N+1 on a real query (29 calls);
- explain level-by-level batching and the DataLoader contract (keys in, values out in the same order, per-request cache);
- explain the "tick" on each stack (the event-loop `call_soon` on Strawberry, graphql-java's per-level dispatch on SmallRye);
- implement it idiomatically: SmallRye `@Source List<…>` batch resolvers and Strawberry `DataLoader` in the request context;
- design bulk source operations;
- state the stack difference (per-field loaders vs shared key-space loaders);
- reason about the blast radius of a failing key and about cache scope (per request; cross-request caching is Ch16).

**H2 outline**
1. *Counting the N+1.* Ch12's 29 calls, field by field (Figure 13.1); Ch7's repeated voyage; Ch1's twenty-four locations.
2. *Batching by level.* One call per field level instead of per parent (Figure 13.2). DDIA on round trips and request amplification (title checked).
3. *The DataLoader contract.* Keys → values in key order, `null` for not found, per-key errors; dedupe and cache within a request.
4. *The tick.* Strawberry collects every `load()` made before the event loop's next turn (`call_soon`); graphql-java dispatches a level's loaders once the level's fields have been fetched (Figure 13.3, from a real run).
5. *Batching on SmallRye.* `@Source List<Leg>` returns `Uni<List<Voyage>>`; the batch is keyed by the parent object; one loader per field.
6. *DataLoaders on Strawberry.* A `Loaders` object built per request in `context_getter`; `load_fn` over a bulk source; the loader keyed by value and shared across fields.
7. *Per field versus per key.* Why Quarkus makes 2 location and 2 routing calls where Python makes 1. Both are independent of page size (Figure 13.4).
8. *Where batching sits.* Bulk operations on the owners (`getVoyages`, `getLocations`…), one round trip each; `max_batch_size` when owners cap batch size.
9. *Ch7's duplicates, gone.* The alias pair; `itinerary` + `delivery`; `nodes`.
10. *A failing key in a batch.* Per-key exception vs whole-batch failure (Figure 13.5); Ch9's codes still apply.
11. *Scope: one request.* Loaders die with the request; cross-request caching and invalidation belong to Ch16.
12. On the wire / Decision / next.

**Example design**
- **Bulk source ops** (both stacks). The log key is the **sorted distinct keys joined with `+`**:
  - `booking.getCargos`, `routing.getItineraries`, `voyage.getVoyages`, `location.getLocations`, `handling.listEventsFor`.
  - Each returns per-key outcomes in key order (a value, null for unknown, or a failure).
  - The single-key ops remain for the root fields (`Query.cargo`, `Query.location`, `Query.voyage`, `node`).
- **Quarkus** (all in the `@GraphQLApi` classes; constructor injection):
  - `public Uni<List<Cargo>> node(@Source List<CargoEdge> edges, Context context)`. It fails the whole Uni with `SourceUnavailableException` when any outcome failed (spike expectation; see case 9).
  - `public Uni<List<Itinerary>> itinerary(@Source List<Cargo> cargos, Context context)`.
  - `@NonNull public Uni<List<Delivery>> delivery(@Source List<Cargo> cargos, Context context)`, combining `routing.getItineraries` and `handling.listEventsFor`.
  - `public Uni<List<Voyage>> voyage(@Source List<Leg> legs, Context context)`.
  - `@NonNull` `loadLocation`/`unloadLocation(@Source List<Leg> legs, Context)`.
  - `HandlingEvent.location`/`voyage(@Source List<HandlingEvent> …)`.
  - `Query.nodes` groups ids by prefix and calls one bulk op per type directly (root fields cannot be `@Source`-batched).
  - **Spikes:**
    - (a) `Uni<List<T>>` return on a batch method works (fallback `CompletionStage<List<T>>`);
    - (b) a `Context` parameter is accepted on a batch method and `getExecutionId()` is stable (fallback: `@Inject Context`, read at entry);
    - (c) `@NonNull` on a batch method yields `T!` for the field, not `[T]`; conformance proves it;
    - (d) the alias pair `a:`/`b:` shares one loader and dedupes on the cached `Leg` (record equality);
    - (e) dispatch with `Uni` parents produces exactly one batch per field per level. If it splits, investigate graphql-java's dispatch strategy before changing any expected count; never weaken a count silently.
- **Python:**
  - `app/loaders.py`:
    ```python
    @dataclass(frozen=True, slots=True)
    class Loaders:
        cargo: DataLoader[str, Cargo | None]
        itinerary: DataLoader[str, Itinerary | None]
        events: DataLoader[str, list[HandlingRecord]]
        voyage: DataLoader[str, Voyage | None]
        location: DataLoader[str, Location | None]
    ```
  - It is built in `deps.get_context` per request; `TrackingContext.loaders`.
  - `load_fn`s call the bulk sources and map failures to exception instances at their positions.
  - Resolvers: `await info.context.loaders.voyage.load(self.voyage_number)`; `Cargo.itinerary` and `Cargo.delivery` share `loaders.itinerary` (so Ch7's duplicate routing call disappears); `CargoEdge.node` uses `loaders.cargo`.
  - Keep `context.py` free of runtime source imports (§9 layering).
- The handling store, mutation and pagination are unchanged from Ch12.

**verify.sh assertions** (`source_calls_reset` before each)
1. `Q_FAN` from Ch12, same data as Ch12 (assert the trackingIds and leg voyage numbers).
   - Python: total `6`;
     - `assert_source_call_keys` for:
       - `booking getCargos DEF456+STU678+VWX901+XYZ789`;
       - `routing getItineraries DEF456+STU678+VWX901+XYZ789`;
       - `handling listEventsFor DEF456+STU678+VWX901+XYZ789`;
       - `voyage getVoyages V100S+V200E+V300A`;
       - `location getLocations CNSHA+DEHAM+NLRTM+SGSIN+USNYC`;
     - `booking listCargos 1`.
   - Quarkus: total `8`;
     - routing `DEF456+STU678+VWX901+XYZ789,DEF456+STU678+VWX901+XYZ789`;
     - location `DEHAM+SGSIN+USNYC,CNSHA+DEHAM+NLRTM`;
     - the others as Python.
   - Both: `assert_source_call_count calls '*' getCargo 0` and `voyage getVoyage 0` (no single-key fan-out left).
2. The tick (both):
   - `assert_calls_ordered` `booking.listCargos:*` → `booking.getCargos:DEF456+STU678+VWX901+XYZ789` → `handling.listEventsFor:DEF456+STU678+VWX901+XYZ789` → `voyage.getVoyages:V100S+V200E+V300A` (three pairwise asserts);
   - `assert_calls_overlap handling.listEventsFor:… voyage…`: **not** expected (different levels). Instead assert overlap of `voyage.getVoyages:V100S+V200E+V300A` with the location batch: Python `location.getLocations:CNSHA+DEHAM+NLRTM+SGSIN+USNYC`; Quarkus `location.getLocations:DEHAM+SGSIN+USNYC`;
   - Quarkus only: `assert_calls_overlap location.getLocations:DEHAM+SGSIN+USNYC location.getLocations:CNSHA+DEHAM+NLRTM`;
   - `assert_single_request`.
3. Ch7's alias pair: `cargo(ABC123){itinerary{legs{a: voyage{number} b: voyage{number}}}}` → both stacks `assert_source_call_keys voyage getVoyages V100S+V200E` (exactly 1 call; Ch7 asserted 4). Leg-0 `a` and `b` are both `V100S`.
4. Ch7's itinerary + delivery: `cargo(ABC123){itinerary{finalArrivalTime} delivery{transportStatus}}` → Python `routing getItineraries 1`; Quarkus `2` (per-field loaders, the documented difference).
5. History fan-out (Ch1's claim): `cargo(DEF456){handlingHistory(first:7){edges{node{location{unLocode} voyage{number}}}}}` → `location getLocations` keys `DEHAM+NLRTM+USNYC` (1 call) and `voyage getVoyages` keys `V100S+V200E` (1 call), both stacks. Ch12 made 7 + 4.
6. `nodes(ids:["cargo_ABC123","cargo_XYZ789","loc_DEHAM","loc_NLRTM","voy_V100S"])` → order and types as requested; 3 calls: `booking.getCargos:ABC123+XYZ789`, `location.getLocations:DEHAM+NLRTM`, `voyage.getVoyages:V100S` (Ch12: 5).
7. Request scope: run `Q_FAN` twice without a reset → `assert_distinct_requests`; the per-request totals are equal (6/8 each, 12/16 in all); nothing is cached across requests.
8. Not found inside a batch: `voyage(voyageNumber:"V999X")` is still the single-key root (null, no errors). `nodes(ids:["voy_V999X","voy_V100S"])` → `[null, {Voyage}]`, one `voyage.getVoyages:V100S+V999X`.
9. Blast radius: `cargos(last:2){edges{node{trackingId}}}` (ABC123, GHI345).
   - Python: error count 1, path `["cargos","edges",1,"node"]`, `.edges.0.node.trackingId` `ABC123`.
   - Quarkus (expected; spike confirms): error count 2, paths `…,0,"node"` and `…,1,"node"`, both nodes null, code `SERVICE_UNAVAILABLE`. If SmallRye shows per-item behaviour instead, assert the observed values and rewrite the prose to match. Never hand-roll a per-item workaround.
10. The payload still re-reads after a write (the batched resolvers did not break Ch8): register UNLOAD DEHAM V100S `2026-10-09T15:00:00Z` for ABC123 → `evt_10`, `cargo.delivery.transportStatus` `IN_PORT`.
11. Deprecation check; scalar checks; `assert_sdl_conforms` (the batch methods must not change the schema; spike c).

**Figures (5)**
- `13-n-plus-one-fanout` (data movement): the `Q_FAN` tree with each field labelled by its Ch12 call count (`getCargo ×4`, `getItinerary ×8`, `listEvents ×4`, `getVoyage ×4`, `getLocation ×8`; total 29). Duplicate keys (`V300A` twice, `SGSIN` twice) are highlighted.
- `13-batched-load` (data movement): the same tree with one bulk call per level and the keys listed on the arrows (Python 6). A side note gives the Quarkus counts (8).
- `13-dataloader-tick` (data movement): a timeline from one real Python run of `Q_FAN`. Lanes are the levels. Small ticks are the `load()` calls enqueued during one event-loop turn, then a dispatch arrow, then the bulk call bar, then the futures resolving. The ghost lane is Ch12's unbatched calls for one level.
- `13-per-field-vs-per-key`: two panels. SmallRye: separate loaders for `loadLocation` and `unloadLocation`, keyed by `Leg`, two bulk calls sharing `DEHAM`. Strawberry: one `location` loader keyed by UN/LOCODE shared by both fields, one call.
- `13-batch-blast-radius` (data movement): one bulk `getCargos` with `GHI345` failing. Strawberry: the exception instance at one position, one null edge. SmallRye: the whole batch future fails, every edge in the batch is null, one error per path.

**Citations.**
- *DDIA* 2nd ed. (batching and round trips, title checked).
- *GraphQL in Action* (its data-fetching optimization chapter, title checked; expected "Optimizing data fetching").
- SmallRye GraphQL docs (batching with `@Source List`), Strawberry docs ("DataLoaders"), the graphql-java dataloader docs (dispatch).

---

## 3. Harness additions (`examples/_lib/lib.sh` and `contracts/scripts/breaking.sh`, B0)

All changes are backward compatible, `bash -n` and shellcheck clean, and use stdlib `python3 -I`. Document each in `examples/_lib/README.md`'s table. Also add the Wave A §8 notes: bash-only (never source from zsh), and the teardown hook.

| Function | Contract |
|---|---|
| `on_exit <command…>` | Registers a command to run after `_lib_teardown` in the EXIT trap. Multiple calls run in registration order. `compose_up`'s trap calls `_lib_teardown` then the hooks, and keeps the exit status. Replaces hand-chained traps (Ch8 style) in new chapters. |
| `compose_logs <service>` | `docker compose -p "$_LIB_COMPOSE_PROJECT" -f "$_LIB_COMPOSE_FILE" logs --no-color <service>`. FAIL if no stack is up. |
| `gql_any <url> <query> [vars] [operationName] [accept]` | Extended: optional 5th argument sets the `Accept` header (default `application/json`). Output unchanged. |
| `gql_meta <url> <accept> <query> [vars]` | POSTs with that `Accept`. Prints one line, `<status> <media-type>` (Content-Type without parameters). Non-zero only on transport failure. |
| `assert_error_message_at <json> <path-json-array> <expected> [ctx]` | The error whose `path` equals the array has exactly that message. |
| `assert_error_extension <json> <path-json-array> <key> <expected-json> [ctx]` | That error's `extensions[key]` parses equal to the expected JSON (types matter). |
| `assert_error_extension_absent <json> <path-json-array> <key> [ctx]` | That error has no `extensions[key]` (absent `extensions` passes). |
| `assert_error_shape <json> <request\|execution> [ctx]` | `request`: every error has a non-empty `message` and `locations`, and none has `path`. `execution`: every error has `message`, `locations` and a non-empty `path`. |
| `assert_body_not_contains <text> <needle> [ctx]` | The needle does not occur anywhere in the text. Prints its position on failure. |
| `assert_source_call_count <calls> <source or *> <op or *> <n> [ctx]` | Extended: `*` for source matches every source (so `'*' '*' n` is the total). |
| `assert_source_call_keys <calls> <source> <op> <k1,k2,…> [ctx]` | The multiset of `key` values for `source.op` equals the list (order ignored). An empty list means no such calls. |
| `assert_deprecated <url> <Type> <field> <reason> [ctx]` | One `__type(name:)` request with `fields(includeDeprecated:true){name isDeprecated deprecationReason}`. The field exists, `isDeprecated` is true, and the reason is exactly equal. |
| `assert_not_deprecated <url> <Type> <field> [ctx]` | The field exists and `isDeprecated` is false. |
| `run_gate <base-dir> <new-dir> [rule,…]` | Runs `BASE_DIR=<base> NEW_DIR=<new> BREAKING_RULES=<rules> bash "$CONTRACTS_DIR/scripts/breaking.sh"`. Prints combined output; returns its exit code. |
| `assert_gate <expected-rc> <needle> <base-dir> <new-dir> [rules] [ctx]` | Runs `run_gate`. Passes only if rc equals the expected value **and** the needle is in the output (excluding `lib.sh:` lines). An output containing "could not"/"Error:" from the tool with rc ≠ expected is reported as a tool error, not as a gate verdict. |

**`contracts/scripts/breaking.sh` (B0):**
- `NEW_DIR=<dir>` (default `schema`) is the new side; `BASE_DIR`/`BASE_REF` are unchanged.
- `BREAKING_RULES=<comma list>` maps to repeated `--rule <name>`; the empty default keeps current behaviour.
- When `GITHUB_ACTIONS=true`, every `⚠` line is echoed as `::warning title=Dangerous schema change::<line>`, so dangerous changes show on the PR without failing it (§8 decision 2).
- Exit codes are unchanged (0 ok/skip, 1 breaking, 2 base ref unresolved).
- Update the header comment and `contracts/README.md`.

**Source-call log contract, extended.** Batch ops use plural names (`getCargos`, `getItineraries`, `getVoyages`, `getLocations`, `listEventsFor`), and their `key` is the sorted distinct keys joined with `+`. New Ch12 ops: `booking.listCargos` (key = routingStatus or `*`) and `handling.pageEvents` (key = trackingId). Update the comment block in `lib.sh` and the README table.

**B0 self-test.**
- `bash -n`; shellcheck if available;
- Ch0 and Ch8 `verify.sh` green;
- the full concurrent run of Ch0/Ch3–Ch8 after the SDL change (§1);
- `npm run lint`;
- `BASE_DIR` gate run on the pre-change copy (rc 0);
- one smoke run of `assert_gate 1 'was removed'` on a scratch fixture.

---

## 4. Acceptance criteria

**Per chapter (Ch9–Ch13)**
- `_docs/NN-*.md` exists with valid front matter (`part:` resolves, `order` = N), and `bash scripts/wordcount.sh` reports 2,800–3,400.
- The budgeted figures exist (9:4, 10:2, 11:2, 12:4, 13:5 = 17):
  - each paired at `assets/diagrams/NN-slug.{svg,excalidraw}` with a spec at `diagrams/NN-slug.py` that regenerates byte-identically with `python3 -I`;
  - each embedded with full-sentence alt text and a `Figure N.M — …` caption;
  - each timeline figure's spec docstring names the run it was drawn from.
- `## On the wire` matches `verify.sh` byte for byte, then the Decision callout naming Ch2 axes, then `## Where this goes next`. At least one Quarkus|Python codetabs pair.
- `examples/NN-slug/` has README (Ch8's sections plus spike results), `compose.yaml` (fixed `name:`), an executable `verify.sh`, `.gitignore` (incl. `.ruff_cache/`), `architecture.svg` + `.excalidraw` (spec under `diagrams/examples/`), and `quarkus/` + `python/` with a re-generated `uv.lock`.
- `verify.sh` prints `PASS`. Every §2 assertion is present for both stacks (or explicitly per stack where §2 says so). It uses only the harness plus stdlib. `assert_sdl_conforms` passes on both stacks.
- No planning language: `grep -rniE 'wave [a-z0-9]|\bS[0-9]{1,2}\b|\bB[0-9]\b|\br0[0-9]\b|iteration|capstone|coverage matrix|phase [0-9]|TODO|TBD' _docs/09* _docs/1[0-3]* examples/09*/README.md examples/1[0-3]*/README.md` returns nothing.
- `lgtm-professional-voice`: 0 ban-tier findings. `lgtm-idiomatic-review`: 0 unresolved substantive findings. In particular, no hand-rolled DataLoader, batching queue, error-masking middleware or connection library where SmallRye/Strawberry provide one.

**Chapter-specific**
- Ch9: identical `message` and `extensions.code` for exposed errors on both stacks; masked responses contain none of `handling-primary-3`/exception class names, while the server log does; status/media-type values recorded per stack.
- Ch10: the `nodes` order/null semantics and the live convention check pass on both stacks.
- Ch11: all 14 gate fixture cases pass with the stated exit codes. `contracts/scripts/breaking.sh` itself is exercised, not a re-implementation. CI stays green.
- Ch12: a byte-identical first cursor on both stacks; forward, backward, filter, insert-stability and fuse cases pass; Ch12's N+1 baseline is 29.
- Ch13: Python 6 / Quarkus 8 calls for `Q_FAN`; Ch7's alias case goes 4 → 1 on both stacks; history fan-out 11 → 2; `nodes` 5 → 3.

**For the wave**
- `python3 -I scripts/validate.py` exits 0; `GATE=1 bash scripts/wordcount.sh` passes; the Jekyll build (ruby:3.3 container) is clean.
- `npm --prefix contracts run lint` and `run breaking` pass. The `contracts/` diff is exactly the §1 additions plus the `breaking.sh`/README changes.
- All Ch0/Ch3–Ch13 `verify.sh` scripts run concurrently on one host and all pass.
- On PR #1: `verify: 09-error-handling` … `verify: 13-dataloaders` green, and `ci-ok` green.
- Site figure total = 43.
- The forward references made by Ch1–Ch8 are delivered. Opus checks each against the shipped text:
  - Ch1's `handlingHistory(first: 2)`, "twenty-four locations" and status-code claims;
  - Ch3's enum-evolution and union references;
  - Ch4's fourth fuse and message-masking references;
  - Ch5's breaking-gate and tighten references;
  - Ch6's and Ch7's "Chapter 13 batches it";
  - Ch8's `errors`/`extensions`/union and optional-input references.

---

## 5. Risks and detection

| Risk | Detection / mitigation |
|---|---|
| SmallRye emits `extensions.code` (kebab class name) for a hidden exception, a masking leak | Ch9 spike (a); `assert_error_extension_absent` on Quarkus. Fallback order: `error-extension-fields` tuning; else assert the observed value and document it as a SmallRye limitation in prose and README. Never write a custom masking layer. |
| Strawberry logs after masking, losing the detail | Ch9 `compose_logs … grep handling-primary-3`; fallback: override `Schema.process_errors` (documented hook). |
| `MaskErrors` masks `BAD_USER_INPUT`/`SERVICE_UNAVAILABLE` (e.g. raising `GraphQLError` directly) | Always raise `ExposedError` subclasses; Ch9/Ch12 assert the code and message on Python. |
| Status/media-type behaviour differs from the Wave A observations | `gql_meta` asserts per-stack expected values; on a mismatch, stop and report before editing prose. |
| SmallRye batch methods with `Uni<List<>>`, `Context` or `@NonNull` behave unexpectedly (wrong SDL `[T]`, no batching, missing request id) | `assert_sdl_conforms`, `assert_source_call_keys`, `assert_single_request` fail loudly. Spikes 13a–c record the fallbacks used. |
| graphql-java dispatch splits a level into several batches when parents are async | Exact per-op call counts. Investigate the dispatch before changing an expected count. |
| Alias pair not deduped on SmallRye (cache key = `Leg` record) | Ch13 case 3. If 2 calls are observed, record it and explain (the loader's cache key), and keep the claim honest. |
| Whole-batch failure on Quarkus differs from expectation | Ch13 case 9 asserts the observed per-stack values; prose follows the evidence. |
| Older chapters stop conforming after the canonical additions | B0 runs every existing `verify.sh` concurrently before anything else lands. |
| Conformance ignores deprecation state (NonBreaking lines) | `assert_deprecated` in Ch11–Ch13. Ch9/Ch10 READMEs state that their slice predates the deprecation. Pitfall B-3. |
| Inspector message text differs from the planned needles | Executors confirm each needle against real output and adjust only the needle. The rc/classification is the assertion. |
| A gate fixture silently not applying | `count == 1` replacement guard → "fixture did not apply" FAIL. |
| A tool error read as "breaking" (rc 1) | `assert_gate` requires the needle as well as the rc; tool errors are reported separately. |
| Strawberry optional arguments print `= null` (dangerous, invisible to conformance) | Ch12 case 10 (`args{defaultValue}` all null); `strawberry.Maybe` spike. |
| Cursors differ across stacks (time formatting, padding) | Ch12 case 2 asserts the computed literal on both stacks. |
| Stored `routingStatus` in the booking index disagrees with the derivation | Ch12 case 4 consistency asserts (MISROUTED, NOT_ROUTED). |
| Handling-state order dependence in Ch12/13 | A fixed sequence; ids asserted at each write (`evt_10`). |
| Timing flakiness in tick/overlap asserts | Only order and overlap of 250 ms windows are asserted, never durations; CI retries 3×. |
| Port 8200 (Vault) taken on a reader's machine | README note; ports are overridable with the documented `-Dquarkus.http.port` / `--port`. |
| Citation drift (book chapter titles; DDIA 2nd ed. structure differs from the 1st) | Cite by title only after checking the ToC (O'Reilly search). Opus validation checks every title and spec section name. |
| Untested code in prose (Ch9 union sketch, Ch10 `@oneOf`) | SDL-only sketches, no codetabs; Opus validation flags any Java/Python in prose that the example does not run. |
| Main has no SDL baseline yet, so the CI gate skips on r01 | Ch11 says so and demonstrates the gate with `BASE_DIR`/`NEW_DIR`. Once PR #1 merges, the `main` baseline applies to every later PR. |

---

## 6. Coverage-matrix and plan updates (orchestrator only)

1. **At each chapter checkpoint (explicit step, same commit as the chapter):** set the chapter to `draft` in both the Topics table (T10 Ch9, T11 Ch10, T12 Ch11, T13 Ch12, T14 Ch13) and the Full chapter inventory. Run `python3 -I scripts/validate.py` and `GATE=1 bash scripts/wordcount.sh` before committing. Push, so CI exercises it.
2. **Verified:** after BVn passes **and** CI `verify: NN-*` is green on PR #1, flip that chapter's two cells to `verified`, either in a follow-up commit per chapter or in one BW commit. Never flip to verified ahead of CI evidence.
3. Leave the Diagram budget table unchanged (9:4, 10:2, 11:2, 12:4, 13:5). Record the actual Wave B count (17; site total 43) in the RESUME POINTER.
4. `_example_pages/index.md`: add rows 09–13:
   - **09** — Exposed vs masked execution errors, partial data with error paths, error codes in `extensions`, status codes by media type, both stacks.
   - **10** — `Node` refetch rule, `nodes(ids:)`, live naming and payload conventions checked on both stacks.
   - **11** — `finalArrivalDate` deprecated for `finalArrivalTime`, and the breaking gate run on safe, dangerous and breaking fixtures.
   - **12** — Relay connections with opaque keyset cursors, forward and backward paging, stability under inserts, the edge-node fuse.
   - **13** — N+1 measured and batched: SmallRye `@Source List` batch resolvers and Strawberry DataLoaders, call counts 29 → 6/8.
5. `_plans/r01-execution-plan.md` RESUME POINTER:
   - S7 set to done with the date, the Opus-validation note and the spike findings (masked `code`, log retention, status/media types, `Maybe` arguments, SmallRye batch signatures, dispatch, alias dedupe, blast radius, deprecation annotation);
   - the "Open for Ch11" note replaced by the decided dangerous-change policy;
   - the canonical SDL additions noted under SDL design decisions.
   - `_plans/iteration-plan.md`: S7 → done.
6. Commits: one checkpoint commit per step on `r01`:
   - `chore(r01.x): Wave B harness + contract additions` for B0;
   - `docs(§N): …` per chapter (prose + figures + example + matrix `draft`);
   - `fix(§N): …` for validation fixes;
   - `docs(r01): Wave B verified` for the flips and plan updates.
   Push after each, and watch CI (lgtm-github conventions).

---

## 7. Binding pitfalls carried from Wave A (every Wave B executor)

From Wave A §7 (A1 validation):
1. Keep `ContractSchemaDetails.withCurrentTypes` in every copy, and assert fields through `... on X` via `node(id:)`/`nodes(ids:)`, not only `__typename`.
2. Python scalars use `NewType` + `StrawberryConfig(scalar_map=…)`. Never pass a type to `strawberry.scalar(...)`, and no `scalar_overrides`.
3. Nulls use `assert_null_at`; absent keys use `assert_absent`; booleans and objects use `assert_json_eq`. Never string-compare `"null"`.
4. Helpers called inside `$(...)` end every assertion with `|| return 1`.
5. Drift and gate needles must appear in the tool's change line; context strings never count.
6. SmallRye enum order is alphabetical: compare enum values as sets.
7. Keep `getId()` on `Node`; no record-style `id()`.
8. Constructor injection in `@GraphQLApi` and source beans.
9. Enum literals are bare in documents; only variables carry strings.
10. Request errors: Quarkus omits `data`, Strawberry sends `"data": null`. Assert with `assert_no_data`.

From Wave A §8–§10:

11. `lib.sh` is bash-only. Use `on_exit` (new) instead of chaining `_lib_teardown` by hand.
12. Examples that export SDL need `quarkus.smallrye-graphql.schema-include-scalars=true`.
13. Quarkus overlaps both `Uni` and blocking siblings; Python overlaps only `async def`. Keep every source-backed resolver async.
14. Strawberry runs the first operation of a multi-operation document without `operationName` (a deviation); assert per stack.
15. Both stacks answer 200 for request errors, even with `Accept: application/graphql-response+json` (Quarkus echoes that type; Strawberry answers `application/json`). GET: Quarkus 405 / Strawberry 200 for queries; mutation over GET is Quarkus 405 / Strawberry 400.
16. Request id:
    - Quarkus: read `Context#getExecutionId()` at method entry and pass it to sources (re-check it for batch methods, spike 13b);
    - Python: `info.context.request_id`, a uuid4 per request via `context_getter`.
17. Python layering: `app/context.py` has no runtime imports of sources; `app/deps.py` builds the context (and now the loaders); `debug.py`/`main.py` import from `deps`.
18. Source shape `getX(request, key)` over `SourceCalls.call(...)`, with batch ops in the same seam. `Leg` `@Ignore`s its codes. `Query.node` dispatches on the `cargo_`/`loc_`/`voy_`/`evt_` prefixes.
19. Config: `TRACKING_SOURCE_LATENCY_MS` (default 0) and `TRACKING_DEBUG_ENDPOINTS` (default false); compose sets 250 / true.
20. Never `pkill -f` patterns while other executors' uvicorn processes run.
21. `Cargo.delivery` needs the itinerary, so `@include(if:false)` on itinerary still calls routing.
22. After renaming the Python project, re-run `uv lock`.
23. `HandlingRecord` is the internal form; `HandlingEvent` is the GraphQL type. The store is thread-safe (`ConcurrentHashMap` with atomic idempotency / `asyncio.Lock`). `listEvents` reads the store.
24. `Cargo.delivery` re-reads handling events at resolve time. Ch12/13 assertions after writes depend on it, so loaders must be per request, never module-level.
25. Optional Strawberry inputs (and now arguments) must print no `= null`: use `strawberry.Maybe`; assert `defaultValue` null.
26. SmallRye `@Input("…")` names explicitly; `ContractSchemaDetails` sets the Query and Mutation root descriptions.
27. Untested prose is a validation finding. Every Java/Python snippet in prose must exist in the example, or be removed.

New in Wave B (binding):
- **B-1.** Exposed errors are an allowlist on both stacks (`show-runtime-exception-message` / `should_mask`). Everything else is masked.
- **B-2.** Batch source keys are sorted distinct keys joined with `+`, never `,`, which would break `assert_source_calls_exactly`.
- **B-3.** `assert_sdl_conforms` does not compare deprecation state. Ch11+ examples call `assert_deprecated`.
- **B-4.** Never edit a verified Ch0–Ch8 file; if the B0 SDL change breaks one, stop and report.

---

## 8. Open decisions needing user input (each with a recommendation)

1. **Canonical SDL additions in Wave B:** `Query.nodes(ids: [ID!]!): [Node]!` (Ch10, batched in Ch13), plus `Itinerary.finalArrivalTime` with `finalArrivalDate` deprecated (Ch11's live deprecation path).
   **Recommend yes**, landed in B0 and proven non-breaking with the gate. The alternative, a fixture-only deprecation, loses the live "deprecated field still executes / hidden from introspection by default" assertions.
2. **Should the breaking gate fail on dangerous changes?**
   **Recommend no for the default CI gate.** Keep failing only on breaking, surface every dangerous change as a GitHub `::warning` annotation on the PR, and offer `BREAKING_RULES=dangerousBreaking` as an opt-in strict mode, demonstrated in Ch11. Dangerous changes (an added enum value, an added optional argument) are routine evolution that needs a reviewer's eye, not a red build; removal of a deprecated field stays breaking unless a PR deliberately sets `suppressRemovalOfDeprecatedField`.
3. **The Quarkus cross-field dedupe gap.** SmallRye batches per field, so `Q_FAN` makes 8 calls vs Python's 6, and Ch7's itinerary+delivery pair stays at 2 routing calls on Quarkus.
   **Recommend accepting and teaching it.** It is constant in page size, and the N+1 is gone. Do not add a custom shared loader or a request-scoped cache on Quarkus (not idiomatic SmallRye); Ch16 covers request and response caching.
4. **The Ch9 result-union pattern: served or sketched?**
   **Recommend an SDL sketch in prose only**, with no canonical addition and no code tabs. The canonical contract keeps payload `userErrors` (Ch3/Ch8 already commit to this), and a second write surface would confuse the contract.

### Critical Files for Implementation
- examples/_lib/lib.sh
- contracts/scripts/breaking.sh (plus contracts/schema/shipping/schema.graphql and cargo.graphql)
- examples/08-mutations/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/TrackingApi.java (and SourceCalls.java, ContractSchemaDetails.java, application.properties)
- examples/08-mutations/python/app/model.py (and schema.py, deps.py, sources.py, context.py)
- _plans/coverage-matrix.md

---

## 9. Wave B findings (binding on Wave C and later)

Recorded from execution and Opus validation, 2026-10-16.

**Framework facts (pinned versions)**
- **SmallRye `@Id List<String>`.** The schema prints `[ID]`, but every request fails at run time with "Unknown Scalar Type [java.util.List]". This reproduces on 2.18.5, 3.0.0.Beta7 and `main`. The workaround is `List<@NonNull String>` plus an `ID_LIST` rewrite in `ContractSchemaDetails`. Filed as smallrye/smallrye-graphql#2733.
- **SmallRye `@io.smallrye.graphql.api.Deprecated(reason)` and `@java.lang.Deprecated`.** Both print `@deprecated`, but introspection reports `isDeprecated:false`, because SmallRye never calls graphql-java's `Builder.deprecate(reason)`. This reproduces on 2.18.5, 3.0.0.Beta7 and `main`. The workaround: keep the SmallRye annotation as the single source of the reason, and have `ContractSchemaDetails` call `field.deprecate(reason)`. Filed as smallrye/smallrye-graphql#2734.
- **Masking.** SmallRye's built-in `ErrorCodeExtensionProvider` leaks a kebab-case class name (`illegal-state`) as `extensions.code` for hidden exceptions.
  - Fix: `DeclaredErrorCodeProvider`, registered through the `ErrorExtensionProvider` ServiceLoader file, plus `quarkus.class-loading.removed-resources."io.smallrye\:smallrye-graphql"=META-INF/services/io.smallrye.graphql.api.ErrorExtensionProvider`.
  - That setting also drops `ExceptionNameErrorExtensionProvider`.
  - Masked errors on Quarkus carry `"code":null`; Strawberry sends no `extensions`.
  - The fix holds in the fast-jar prod image.
- **Server logs.** Neither stack's log carries the GraphQL path or a request id. Never claim it does.
- **Mutiny zero delay.** Mutiny rejects `delayIt().by(Duration.ZERO)`. The `SourceCalls.afterLatency` guard is present in Ch6 through Ch13.
- **SmallRye batching.** SmallRye batches per field: one `@Source List` loader per field, deduped by parent-object equality. A failing key fails the whole batch future, so every edge in the batch is null with one error per path. Strawberry fails only the failing key.
- **Strawberry resolver arguments.** Use `strawberry.Maybe[T | None] = None`; this prints no `= null`.
- **Introspection limit.** graphql-java rejects two `__Type.fields` selections in one request ("BadFaithIntrospection").
- **Store time precision.** Store times at whole-second precision whenever a cursor encodes the time.

**GraphQL-over-HTTP (current working draft, http-spec.graphql.org/draft)**
- A response without `data` must get a 4xx or 5xx: 400 for a parse error, 422 for validation, an undetermined operation or coercion failure.
- A response with `data` must get a 2xx: 200 when clean, and 294 (should) when errors accompany the data, recommended only with `application/graphql-response+json`. The draft's own example 5.4.1 contradicts the 294 rule.
- Legacy `application/json` clients should get the same codes.
- Both stacks answer 200 everywhere. Ch1, Ch4, Ch6 and Ch9 now agree on all of this.

**Harness and CI**
- CI runners have no `contracts/node_modules`. Call `ensure_contracts_tools` before any direct npm or npx in `verify.sh`; `assert_sdl_conforms`, `run_gate` and `assert_gate` already do.
- `compose_up` now runs `down -v` first, so a reader's leftover stack can't break a mutating example.
- `validate.py` piped through `tail` hides its exit code. Check `$?` or `PIPESTATUS`.

**Authoring**
- Number figures by order of appearance.
- Write alt text in full sentences.
- Render every figure to PNG and view it before handing it over.
- Cite every book by a verified chapter title. Verified so far:
  - DDIA 2nd ed.: Ch4 "Storage and Retrieval", Ch5 "Encoding and Evolution".
  - *GraphQL Best Practices*: Ch3 "Crafting Effective GraphQL Schemas".
  - *GraphQL in Action*: Ch4 "Designing a GraphQL schema", Ch7 "Optimizing data fetching", Ch8 "Implementing mutations".
  - *Full Stack GraphQL Applications*: Ch9 "Advanced GraphQL considerations".
- Validators drafted the corrections to forward statements in verified chapters (Ch1, Ch2, Ch4, Ch6, Ch10). Those corrections were applied as deliberate fixes and re-verified, not as side effects.
