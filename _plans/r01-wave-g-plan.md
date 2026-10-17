---
layout: plan
render_with_liquid: false
title: "r01 Wave G Plan — S12 Bibliography and voice pass, S12b Footer and site-chrome cleanup"
---

# Wave G (S12 + S12b): bibliography, site-wide voice pass, site chrome

**Status: DONE 2026-10-17 (P0, B1, V1–V5 with VV1–VV5 and one repair round each, C1, C2/CV). APPROVED by user 2026-10-17 — §8 D1–D11 as recommended.**

This plan is written for Sonnet executors and Opus validators. Where it gives a value (a file list, a line number, a title, a command), use exactly that value. Line numbers are from `be72457` and may drift by a few lines; locate each one by its quoted text.

**Precondition.** S11 is done (be72457). Ch0, Ch3–27 and Appendix A are `verified` and Ch1–2 are `draft`. There are 27 example dirs and 89 figures, and CI is green at 32f3390. No chapter content changes in this wave beyond voice, citations and rule-13 restatements.

**The content rule (binding on every executor and validator).** The site is a GraphQL tutorial, not an issue tracker. This covers all reader-facing text: chapters, READMEs, code comments, chart comments, `NOTES.txt`, script and verify messages, figure labels and alt text. That text states every technique positively, as the design. It never describes framework, tool or platform defects, limitations, upstream issues, workarounds or security weaknesses, and it carries no issue numbers. Stack differences are stated neutrally. Spec conformance is stated as "the draft recommends X; the stack answers Y". This is `lgtm-professional-voice` rules 13–14. **No vulnerability detail goes anywhere in the repo, `_plans/` included.** An executor who sees something that looks like a defect or a security weakness reports it to the orchestrator in one neutral line and writes nothing about it in any file.

**The scope rule (binding).** This wave changes prose, comments, message strings, figure labels and site chrome only. No change to behaviour, assertions, identifiers, commands, `contracts/`, `scripts/`, `.github/`, or any code outside comments and string literals. Do not rename identifiers that contain a flagged word, such as the Ch9 alias `bug`. Recorded output stays as it is.

---

## 0. Facts checked (2026-10-17)

**Books (O'Reilly Learning catalog, `search_oreilly_content`, 2026-10-17; book-level only, the tool returns no tables of contents)**

| Book | Author(s) | Publisher | Edition | Published | ISBN | Current link in `bibliography.md` |
|---|---|---|---|---|---|---|
| *GraphQL in Action* | Samer Buna | Manning | 1st | 2021-03-29 | 9781617295683 | manning.com/books/graphql-in-action |
| *GraphQL Best Practices* | Artur Czemiel | Packt | 1st | 2024-10-11 | 9781835467145 | packtpub.com/…/graphql-best-practices-9781835467145 |
| *Full Stack GraphQL Applications* | William Lyon | Manning | 1st | 2022-08-31 | 9781617297038 | manning.com/books/fullstack-graphql-applications (the executor confirms it resolves) |
| *Designing Data-Intensive Applications*, 2nd ed. | Martin Kleppmann, Chris Riccomini | O'Reilly | 2nd | 2026-02-18 | 9781098119058 | oreilly.com/library/view/…/9781098119058/ |

Titles, authors and the DDIA edition match the execution plan's "Reference books" section. The execution plan gives no year; the years come from the catalog.

**`bibliography.md` today:** front matter `layout: plan`, `permalink: /bibliography/`. It has an intro paragraph with the "reference works, not sources" disclaimer, a Books table (Title, Author(s), Publisher, Focus), a "Specifications and primary docs" table (7 rows), and a closing disclaimer sentence. The acceptance criterion's "disclaimer present" is already met. The REST sibling adds a **Year** column. The gRPC sibling has one combined table. Neither sibling has a per-chapter mapping, so that section is new here.

**Citations in `_docs/` today** (grep for Buna, Czemiel, Lyon, Kleppmann and the four titles):

| Chapter | Line | Book | Chapter title cited |
|---|---|---|---|
| Ch1 | 205 | GiA; FSGA | book-level (no chapter title) |
| Ch2 | 156 | GiA; FSGA | book-level |
| Ch3 | 313 | GiA | "Introduction to GraphQL", "Designing a GraphQL schema" |
| Ch4 | 19, 239 | GiA | "Designing a GraphQL schema" (L19 names the book without its author) |
| Ch5 | 314 | GiA | "Designing a GraphQL schema" |
| Ch6 | 269 | GiA | "Introduction to GraphQL", "Implementing schema resolvers" |
| Ch7 | 300 | GiA | "Customizing and organizing GraphQL operations", "Implementing schema resolvers", "Working with database models and relations" |
| Ch8 | 317 | GiA | "Implementing mutations" |
| Ch9 | 274 | GBP; GiA | "Describing Errors in GraphQL"; "Implementing mutations" |
| Ch10 | 245 | GiA; GBP | "Designing a GraphQL schema"; "Crafting Effective GraphQL Schemas" |
| Ch11 | 23, 282 | DDIA; GBP | "Encoding and Evolution"; "Crafting Effective GraphQL Schemas" |
| Ch12 | 29, 299 | DDIA; FSGA | "Storage and Retrieval"; "Advanced GraphQL considerations" |
| Ch13 | 39, 313 | DDIA; GiA | "Defining Nonfunctional Requirements"; "Optimizing data fetching" |
| Ch14 | 25, 84, 249 | DDIA; GBP | "Defining Nonfunctional Requirements" (L84 by surname only, after L25); "Keeping Data Secure" |
| Ch16 | 24, 273 | DDIA; GiA | "Trade-offs in Data Systems Architecture"; "Optimizing data fetching" (L273 says "second edition"; every other chapter says "2nd edition") |
| Ch17 | 250 | GBP | "Keeping Data Secure" |
| Ch18 | 325 | FSGA | "Adding authorization and authentication" |
| Ch22 | 319 | FSGA; GiA | book-level ("builds a React client on Apollo Client"; "consuming a GraphQL API from a client application") |
| Ch27 | 228 | FSGA | "Adding authorization and authentication", "Advanced GraphQL considerations" |
| Ch27, A | 228, 279 | — | "The bibliography lists …" (a general pointer) |

Ch0, Ch15, Ch19, Ch20, Ch21, Ch23, Ch24, Ch25 and Ch26 cite no book.

**DDIA criterion (Ch12/13/14/16): met.** Ch12 L29 and L299, Ch13 L39 and L313, Ch14 L25, L84 and L249, Ch16 L24 and L273. Ch11 cites it too.

**Chapter titles already verified** (Wave B §9 and Wave C §9):
- DDIA: Ch1 "Trade-offs in Data Systems Architecture", Ch4 "Storage and Retrieval", Ch5 "Encoding and Evolution".
- GBP: Ch3 "Crafting Effective GraphQL Schemas", Ch10 "Keeping Data Secure".
- GiA: Ch4 "Designing a GraphQL schema", Ch7 "Optimizing data fetching", Ch8 "Implementing mutations".
- FSGA: Ch7 "Adding authorization and authentication", Ch9 "Advanced GraphQL considerations".

**Cited in prose but not recorded as verified (B1 verifies these six):**
- DDIA "Defining Nonfunctional Requirements" (Ch13, Ch14)
- GiA "Introduction to GraphQL" (Ch3, Ch6)
- GiA "Implementing schema resolvers" (Ch6, Ch7)
- GiA "Customizing and organizing GraphQL operations" (Ch7)
- GiA "Working with database models and relations" (Ch7)
- GBP "Describing Errors in GraphQL" (Ch9)

**Coverage against the execution plan's book ranges:**
- GiA, planned for Ch1–9 and Ch22: all are cited, plus Ch10, Ch13 and Ch16.
- GBP, planned for Ch10 and Ch14–18: Ch10, Ch14 and Ch17 are cited, plus Ch9 and Ch11. **Ch15, Ch16 and Ch18 are not cited.**
- FSGA, planned for Ch19–22 and Ch27: Ch22 and Ch27 are cited, plus Ch1, Ch2, Ch12 and Ch18. **Ch19, Ch20 and Ch21 are not cited.**
- DDIA: as planned, plus Ch11. (§8 D3.)

**Prose word counts** (`bash scripts/wordcount.sh`, be72457):

| File | Words |
|---|---|
| Ch0 | 3391 |
| Ch1 | 3374 |
| Ch2 | 3171 |
| Ch3 | 3126 |
| Ch4 | 3058 |
| Ch5 | 3370 |
| Ch6 | 3260 |
| Ch7 | 2937 |
| Ch8 | 3357 |
| Ch9 | 2972 |
| Ch10 | 2912 |
| Ch11 | 2942 |
| Ch12 | 2935 |
| Ch13 | 3103 |
| Ch14 | 2995 |
| Ch15 | 3164 |
| Ch16 | 3165 |
| Ch17 | 2878 |
| Ch18 | 3074 |
| Ch19 | 2933 |
| Ch20 | 3028 |
| Ch21 | 3047 |
| Ch22 | 2902 |
| Ch23 | 3112 |
| Ch24 | 2983 |
| Ch25 | 3045 |
| Ch26 | 3040 |
| Ch27 | 2950 |
| A | 3126 |
| outline | 432 (not gated) |

All chapters are inside 2,800–3,400. Ch0, Ch1, Ch5 and Ch8 are within 45 words of the ceiling. `scripts/wordcount.sh` still states a 2,000–2,500 target with `MIN=2000`; the GATE enforces only the floor.

**Voice baseline (read-only approximation; `scan.sh` itself needs `mktemp`, so P0 runs it).**
- Ban-tier pattern grep over `_docs`, `_parts`, `index.html`, `_example_pages`, `bibliography.md` and `examples/`: the only hits are 38 × `deliberately`, all outside prose:
  - Containerfile comments "Bump deliberately" (developer-facing; each gives its reason).
  - The `Mutation` description "The write surface; deliberately small because writes belong to the owning services." This is canonical SDL text (`contracts/schema/shipping/schema.graphql:52`) reproduced by both stacks. It is a contract string, so it **stays**.
- No ban-tier hit in chapter prose.

**Rule-13 baseline (read-only grep of the watch patterns over everything outside `_plans`, `node_modules`, `target` and `_site`):**

Domain uses, to keep unless §8 says otherwise:
- `bug` as the Ch9 alias (prose, README, `verify.sh`, figure 09-partial-data-errors).
- `BYPASS` / "bypass shared caches" (Ch16, Ch18, the nginx comments).
- "broken domain rules" (Ch8 and its README).
- "broken promise" (Ch10).
- "broken graph" / "broken subgraph" / "broken fixtures" (Ch20 and its verify message, `compose-supergraph.mjs`).
- "silently did nothing" (Ch11:129).
- "misreading cursors" (Ch12:45).
- "never reaches it" (`HandlingRegistration.java` / `registration.py` in 09–14 and 19–25).
- "never reaches GraphQL" (Ch18/27 `auth.py`).
- "an outside caller never reaches them" (Ch25:140).
- "a refused operation never reaches" (Ch18 README).
- "silently misreading old cursors" (`Pagination.java` / `pagination.py` in 12–14 and 19–25; Ch15–18 and Ch27 already read "without misreading").
- "the rule cannot be bypassed" (Ch18/27 `access.py`).
- "Partner feeds bypass the graph" (Ch2:118).
- "schema-violating result" (`index.html:46`).
- "a deterministic bug" (`.github/workflows/contracts.yml:244`, a CI comment, out of scope).
- `lib.sh:908` ("never reads as a match"), `lib.sh:2249` ("never reaches telemetry").
- "never reads as conformance" (Ch0:131).

Tool-behaviour framing to restate (§8 D6):
- `ContractSchemaDetails.java:29` "…that the SmallRye GraphQL annotations cannot express", with "SmallRye always writes…" and "SmallRye appends…" items. Present in examples 14, 15, 16, 17, 18 and 23. Examples 13 and 19–27 already use the positive form "Applies the details of the canonical SDL to the generated schema".
- "graphql-inspector does not compare specifiedByURL" / "…does not read specifiedByURL" / "…never reads it from introspection". Present in `verify.sh` of 00, 03, 08, 10 and 11, and in `examples/_lib/lib.sh:1697` and `:1742`.
- `PersistedDocumentRoute.java:256–257` "malformed extensions: SmallRye ignores them too" (15, 16).
- `examples/15-persisted-queries/verify.sh:421` "Strawberry ignores the URL parameter on POST…".

**Files landed after the 2026-10-16 scrub** (`git diff --name-only ef6f8ce HEAD`, excluding `_plans/`):
- `_docs/`: 00, 09, 14, 16, 19–27 and 99.
- `_example_pages/index.md`.
- 62 files under `assets/diagrams/`.
- Diagram specs for 00, 19–27 and A, plus 26 under `diagrams/examples/`.
- Every example dir 00–27 and 99 (the DX telemetry switch touched all of them).
- `examples/_lib/`.

The rule-13 sweep therefore covers every example dir, not only 19–27.

**Site chrome today** (rule 14):
- `_includes/footer.html`: Site column with Outline and Bibliography; Reference column with GraphQL, spec, SmallRye, Strawberry, GitHub and Issues. Already the post-PR-#6 shape, with no `/plans/` link.
- `index.html`: Start reading and View on GitHub; no plan button.
- `_layouts/part_index.html`: "Coming soon … Check back soon." (never rendered; every part has chapters).
- `_includes/header.html`: Chapters · Examples · Bibliography · GitHub.
- `_layouts/plan.html`: no plan wording rendered.
- `_parts/*`: 13 blurbs, no labels.
- `_docs/00-outline.md:17`: "points to a planned WebSockets book". This is the approved series forward pointer; keep it.
- `_example_pages/index.md:15`: **"More examples land here as new chapters ship."** Stale; delete.
- `_config.yml`: `plans: output: false` ✓.
- No chapter carries a status footer.
- **No root `README.md`.** gRPC has a 64-line one. Root READMEs are excluded from Jekyll, so this is a repo-facing gap.

**gRPC PR #6 (`4b33d5f`), the pattern:** 19 files, +17/−26.
- Footer: removed the "Build & iteration plan", "Coverage matrix" and "Domain glossary" links.
- `index.html`: removed the "Build & iteration plan" button.
- `part_index.html`: "Coming soon" text without the roadmap link.
- `_example_pages/index.md` and the outline: one line each.
- 15 planned-chapter stubs: one line each.

The GraphQL site was seeded after #6, so only the residue listed above applies.

**`_site/` on disk is stale** (built 2026-10-16 00:55, before `1e962b1` set `output: false`). `grep -rl '/plans/' _site` lists `_site/plans/*` and `sitemap.xml` today. Only a fresh build is evidence.

**CI.**
- `contracts.yml` runs on `pull_request`; every push to PR #1 runs all 25 `verify:` jobs (the discovery matrix is not path-filtered), plus `site` (validate.py, wordcount GATE, jekyll build), `k8s-manifests` and `ci-ok`. `cancel-in-progress: true`.
- `pages.yml` builds on any branch and deploys only from `main`.

---

## 1. Approach

### Sequencing (DAG)

| Step | Executor | Owns (exclusive write set) | Depends on |
|---|---|---|---|
| **P0** Baseline | orchestrator | scratch only: `scan.sh` summary, `--files`, `--tier ban --hits all`, `--hits defect`/`upstream`/`spec-violation`/`security` (with `--ext +sh,yaml,java,properties,conf,tpl,mjs,txt`), wordcount table | — |
| **B1** Bibliography | Executor B (Sonnet) | `bibliography.md` only; plus a **citation-correction table** handed to the orchestrator (no chapter edits) | P0 |
| **BV** | Opus | read-only | B1 |
| **V1** Parts 0–2 | Executor V1 | `_docs/00-outline.md`, `_docs/00-*`, `01-*`, `02-*`, `03-*`, `04-*`, `05-*`; `examples/00-prerequisites/**`, `03-sdl-type-system/**`, `04-nullability/**`, `05-contract-first/**` (README, comments, verify messages); `diagrams/0[0-5]-*.py`, `diagrams/examples/0[0-5]-*`, `assets/diagrams/0[0-5]-*` | BV |
| **V2** Parts 3–5 | Executor V2 | `_docs/06-*` … `11-*`; `examples/06-*` … `11-*`; diagrams and assets `06`–`11` | BV |
| **V3** Parts 6–8 | Executor V3 | `_docs/12-*` … `18-*`; `examples/12-*` … `18-*`; diagrams and assets `12`–`18` | BV |
| **V4** Parts 9–11 | Executor V4 | `_docs/19-*` … `24-*`; `examples/19-*` … `24-*`; diagrams and assets `19`–`24` | BV |
| **V5** Part 12 | Executor V5 | `_docs/25-*`, `26-*`, `27-*`, `99-*`; `examples/25-*`, `26-*` (README, chart comments, `NOTES.txt`, script messages), `27-*`, `99-*`; diagrams and assets `25`–`27` and `A-*` | BV |
| **VV1–VV5** | Opus, one per batch | read-only; findings routed to the batch owner | its Vn |
| **C1** Site chrome + cross-cutting (S12b) | Executor C (Sonnet) | `_includes/footer.html`, `_includes/header.html`, `index.html`, `_layouts/*.html`, `_parts/*.md`, `_example_pages/index.md`, root `README.md` (new, §8 D7), `examples/_lib/lib.sh` (comments only), `examples/_lib/README.md`, `contracts/README.md` (prose only), `diagrams/README.md` | P0 (disjoint from V1–V5, so it runs in parallel) |
| **C2** Build + final sweep (S12b) | Executor C, then an Opus validator (CV) | scratch build output only | V1–V5 validated, C1 |
| **GW** Wrap | orchestrator | `_plans/*`, `coverage-matrix.md` (no status change), commits, deliberate fixes | CV, CI green |

How to run it:
- **Partition by part.** Each executor owns every reader-facing file of its chapters: the chapter, the example README, code comments and string literals in the example, the verify/smoke messages, chart comments, the diagram specs and the generated pairs. No file is shared between two V executors.
- **Batch sizes.** V1 has 6 chapters plus the outline (~19.9k words), V2 6 (~18.6k), V3 7 (~21.3k), V4 6 (~18.0k), V5 4 (~12.2k plus the three cluster/final dirs, the heaviest code-comment surface). If P0's `--files` shows V3 far heavier than the rest, move Ch18 to V4 before dispatch.
- **Citation corrections flow one way.** B1 writes only `bibliography.md` and hands the orchestrator a table of `chapter:line → corrected sentence` (title fixes, "second edition" → "2nd edition", author-on-first-mention). The orchestrator pastes each batch's rows into that batch's brief, and the Vn executor applies them. Nobody else edits chapter citations.
- **C1 runs beside the V batches** because its files are disjoint. **C2 waits for every VVn to pass**, because its sweep is the final one.
- **Repair rounds.** At most two per batch. A third failure goes back to the user.
- **Commits** (orchestrator, §8 D9):
  - `docs(site): bibliography — editions, years and where each book is cited` (B1)
  - `docs(§0–§5): voice pass` … `docs(§25–§A): voice pass` (one per V batch)
  - `docs(site): site chrome and root README (voice rules 13–14)` (C1/C2)
  - Push after each; CI cancels superseded runs.

**Executor rules (unchanged from Waves A–F, binding)**
- Write files only; no git.
- Edit only your write set. Never touch `_plans/*`, `coverage-matrix.md`, `scripts/`, `contracts/schema/`, `.github/`, or another batch's files.
- **Do not change** (skill list):
  - code, code blocks and inline code;
  - commands, flags, paths, URLs and environment variables;
  - identifiers containing a flagged word (the `bug` alias, the `BYPASS` header value, `shared-iterations`);
  - recorded output, quoted error messages and quoted third-party text;
  - canonical SDL description strings, which are contract text reproduced by both stacks (e.g. "deliberately small").
- **Comment and string-literal edits only** in code files. A Java/Python comment change needs no rebuild, but run `bash -n` on every edited `.sh`. Do not change the text of any assertion argument that another script greps for. If a verify message is edited, read it in the script's output path; run that example's `verify.sh` only if the edit touches anything other than a message string or comment.
- **Figures.** If a label, title, alt text or caption changes: alt text and caption live in the chapter's include line; labels live in the spec. Regenerate both files of the pair from `diagrams/<name>.py`, never hand-edit the SVG, render to PNG and view it. The pair count stays 89.
- **Word count.**
  - After editing, every chapter stays within **2,800–3,400** prose words (`bash scripts/wordcount.sh _docs/NN-*.md`).
  - The net change per chapter stays within **±150 words** unless the brief says otherwise.
  - Ch0 (3,391), Ch1 (3,374), Ch5 (3,370) and Ch8 (3,357) must not grow: any added clause is paid for by a cut in the same chapter.
  - Report before and after counts.
- **Before handing back:** run `scan.sh --tier ban` on your files (0 hits, or each survivor kept with a stated reason), the rule-13 `--hits` list on your files (each survivor classified), `python3 -I scripts/validate.py; echo rc=$?` (not piped) and the wordcount report.
- `scan.sh` writes temp files: run it with `TMPDIR=<session scratch>`.

**Rejected alternatives (one line each)**
- *One executor for the whole site*: about 90k words plus 28 READMEs plus comments does not fit one context; the skill says to partition.
- *Split by hit count across parts*: splits a part's cross-references across executors; part boundaries keep each chapter's next-chapter pointers in one head.
- *Executors edit citations from their own research*: five agents verifying the same six titles; one researcher (B1) and a correction table keep it consistent.
- *Rewrite chapters for length*: the counts are already in band; this is a voice pass, not a re-depth.
- *Force citations into Ch15/16/18 (Czemiel) and Ch19–21 (Lyon) to match the plan's ranges*: §8 D3.

---

## 2. Per step

### 2.1 B1: Bibliography

**Research (read-only).**
1. For each of the six unverified titles in §0, open the publisher's public contents page with WebFetch and record the chapter number and exact title, character for character (case, "and" vs "&"):
   - Manning `manning.com/books/graphql-in-action`
   - Packt `packtpub.com/en-us/product/graphql-best-practices-9781835467145`
   - O'Reilly `oreilly.com/library/view/designing-data-intensive-applications/9781098119058/`
   - Manning `manning.com/books/fullstack-graphql-applications` (also confirm the URL resolves; if it redirects, use the final URL)
2. Fallback: the O'Reilly Learning pages for the ISBNs in §0. `search_oreilly_content` gives only the book record.
3. A title that cannot be confirmed from a contents page goes in the correction table as a **book-level** rewrite of the sentence (§8 D2). The sentence keeps the same word count ±10.
4. Re-confirm the 10 already-verified titles from the same pages; this is a cheap check and it fills in the chapter numbers.

**`bibliography.md` changes.**
- Front matter unchanged.
- **Books table:** columns `Title | Author(s) | Publisher | Edition | Year | Focus`.
  - Editions: 1st, 1st, 1st, 2nd. Years: 2021, 2024, 2022, 2026.
  - Title links as today (FSGA URL as confirmed).
  - The "Focus" cells describe the book in general terms, as now, aligned to what this site cites from it:
    - GiA: "The language, schema design, resolvers, data fetching, mutations, client use"
    - GBP: "Schema design, error descriptions, query limits and security"
    - FSGA: "End-to-end applications, authorization, pagination, React and Apollo clients"
    - DDIA: unchanged
- **New section `## Where each book is cited`**, after the Books table:
  - One H3 per book.
  - A two-column table `| Chapter here | Chapter of the book |`. The left cell is a relative link `[Ch12 · Connections and pagination](../docs/12-connections-and-pagination/)`; use `{{ '/docs/…/' | relative_url }}`, as `_example_pages/index.md` does. The right cell is the verified title, plus the chapter number if B1 confirmed it, or "the book as a whole" for book-level citations.
  - Rows from §0's citation table, after B1's corrections:
    - GiA rows: Ch1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 16, 22.
    - GBP rows: Ch9, 10, 11, 14, 17.
    - FSGA rows: Ch1, 2, 12, 18, 22, 27.
    - DDIA rows: Ch11, 12, 13, 14, 16.
  - One plain lead sentence for the section: "Each chapter's closing section names the parts of these books that cover the same ground."
- **Specifications table:** unchanged. Optionally add RFC 9111 and the OpenTelemetry specification, since several chapters cite them by section; **only if** BV agrees. Default: unchanged.
- **Disclaimer:** keep both sentences as they are. The intro says "reference works, not sources — no text or code from any of them is reproduced here", and the close says "These titles inform this site's coverage and rigor only…".
- Voice: the intro has one em dash; leave it. No meta-narration.
- `bibliography.md` is not gated by wordcount.

**Correction table (hand-back to the orchestrator), at least these rows:**
- Ch16:273 "second edition" → "2nd edition" (consistency).
- Ch4:19 first mention of *GraphQL in Action* without its author → "Samer Buna's *GraphQL in Action*". Ch4:239 then drops "Samer Buna's" to keep the word count. Rule 11: name the author once.
- One row per unverified title, either confirmed (no change) or rewritten to book level.
- Ch22:319: book-level is fine (§8 D4). If B1 confirms the relevant GiA and FSGA client chapters, offer the titled form as an optional row; V4 applies it only within Ch22's word budget.

**BV checks:**
- Every row in "Where each book is cited" matches a sentence in the chapter (grep).
- No chapter citation is absent from the mapping.
- Every chapter title in the mapping and in the correction table is one B1 confirmed, with the source URL recorded in the hand-back (not in the repo).
- The four books' title, author, publisher and edition equal §0.
- The disclaimer is present.
- `{{ … | relative_url }}` renders: `bibliography.md` has no `render_with_liquid: false`. Confirm in C2's build.

### 2.2 V1–V5: Site-wide voice pass (rules 1–14)

**Inputs per batch** (the orchestrator pastes them into each brief; a subagent does not inherit the skill):
- the audience contract and rules 1–14 verbatim from `lgtm-professional-voice/SKILL.md`;
- the do-not-change list;
- the `references/surfaces.md` sections for prose, captions, diagram labels and framework behaviour (the rule-13 table);
- that batch's lines from P0's `scan.sh --hits all` output, both tiers, filtered to its files;
- that batch's rule-13 baseline from §0;
- that batch's rows from B1's correction table;
- the batch's word-count table.

**Read-through checklist per chapter** (read the chapter, not only the hits):
1. Rules 1–4: confessional words, defensive contrast, meta-narration, school framing. Keep "deliberately" at most once per chapter, and only with its reason.
2. Rule 5: H2s name the concept. No file name as a heading; `## On the wire` and `## Where this goes next` are house headings, so keep them.
3. Rule 6: general nouns in explanation, literal names in commands.
4. Rule 7: generated-text tells; "isn't X — it's Y" reflexes; stacked em dashes.
5. Rule 8: no ALL-CAPS emphasis or exclamation marks in prose. HTTP verbs, `PASS`/`FAIL`, enum values and status names stay.
6. Rule 9: hedges and filler.
7. Rule 10: no tracking codes, wave or step labels, `_plans/` paths, "the roadmap".
8. Rule 11: each non-obvious term is explained once, on first use in the chapter.
9. Rule 12: four or more parallel items become a list or table; a sentence with two em dashes becomes two sentences.
10. Rule 13: every hit from the §0 baseline and P0 in the batch is classified as **keep (domain use, with reason)** or **restate as design**. Apply §8 D5/D6 as decided.
11. Rule 14: chapters and READMEs link only to reader content (chapters, examples, bibliography, external docs). No `/plans/` link.
12. Captions read `Figure N.M — <what it shows>`; alt text is full sentences describing the content; the two differ.
13. Cross-references are by chapter number or section name.
14. Citations: apply the correction-table rows; books by verified chapter title or book-level; docs by page title (Wave D §9).

**Per-batch rule-13 assignments (from §0, decisions as recommended):**
- **V1:** `examples/00-prerequisites/verify.sh`, `03-sdl-type-system/verify.sh` (specifiedByURL comments → D6). Ch0:131 "never reads as conformance": keep. Ch2:118 "Partner feeds bypass the graph": keep, or "go around the graph" at the executor's choice. Ch3:243 neutral stack difference: keep.
- **V2:** `examples/08-mutations/verify.sh`, `10-schema-design/verify.sh`, `11-evolution/verify.sh` (specifiedByURL → D6). `HandlingRegistration`/`registration.py` "never reaches it" in 09–11: keep (D5). The Ch9 `bug` alias everywhere: keep (identifier). Ch8 "broken domain rules", Ch10 "broken promise", Ch11:129 "silently did nothing": keep.
- **V3:**
  - `Pagination.java`/`pagination.py` in 12, 13, 14: drop "silently" (D5).
  - `ContractSchemaDetails.java` Javadoc in 14–18: restate to the positive Ch13 form (D6), as a list of what the observer applies, with no "cannot", "always writes" or "appends".
  - `PersistedDocumentRoute.java:256–257` (15, 16) → "malformed extensions are treated as absent".
  - `examples/15-persisted-queries/verify.sh:421` → "On POST the body's document runs; the URL parameter is not read."
  - Ch16/Ch18 `bypass`, Ch18/27 `access.py` and `auth.py`: keep.
- **V4:**
  - `Pagination`/`pagination` in 19–24: drop "silently".
  - `ContractSchemaDetails.java` in 23 → D6.
  - `HandlingRegistration` in 19–24: keep.
  - Ch20 "broken graph/subgraph/fixtures" and `compose-supergraph.mjs`: keep.
  - Also re-read every `Node.java` Javadoc in 19–24 against the fabe070 wording (Wave D/E §9 S12b inputs).
- **V5:**
  - `Pagination`/`pagination` in 25: drop "silently".
  - Ch25:140 "never reaches them": keep.
  - Read every chart comment, `NOTES.txt`, `values.yaml` comment and `scripts/*.sh` message in 26, 27 and 99. These landed after the scrub; Wave F §9 flags the OpenShift and Keycloak notes. They are the most likely place for "anyuid exception", "workaround" or platform-at-fault wording. State each as design ("OpenShift's `anyuid` SCC lists no seccomp profiles, so the chart leaves the field empty for that pod").

**VVn (Opus) per batch:**
1. Re-scan the batch's files with `scan.sh --tier ban` (0, or kept with reasons) and with the rule-13 labels (every survivor classified as domain use).
2. Read every changed paragraph against `references/before-after.md`, and check the paragraph after each edit for choppy fragments.
3. `git diff --word-diff` on the batch: no change inside fences, inline code, commands, URLs, identifiers, recorded output or quoted messages; no SDL description string changed; code files differ only in comments or message strings.
4. Word counts: within 2,800–3,400 and ±150.
5. Regenerated figures: `python diagrams/<name>.py` reproduces the committed pair byte for byte; PNG viewed.
6. Citation rows applied exactly; no new book claim beyond B1's table.
7. Content rule: zero defect, upstream, workaround or security-weakness wording in the batch, and no issue numbers.
8. `validate.py` rc 0.

### 2.3 C1: Site chrome and cross-cutting files (S12b, part 1)

1. **`_includes/footer.html`:** verify that it links only to Outline, Bibliography, the four reference sites, the repo and its issues. No change expected. The Issues link is allowed (`references/surfaces.md`, Site chrome).
2. **`index.html`:**
   - Verify there is no plan link, no iteration label and no sequence number.
   - The `{%- comment -%}` block about "new parts appear here" is a template comment that never renders; keep it.
   - `index.html:46` "schema-violating result" → "a result that does not match the schema" (§8 D5 lists it; recommended as a small reword because the phrase hits the spec-violation scan).
   - The "Coming soon" card meta: keep (never rendered now).
3. **`_layouts/part_index.html`, `plan.html`, `tutorial.html`, `default.html`, `_includes/header.html`:** verify that none renders a plan link, a status chip or an iteration label. No change expected.
4. **`_parts/*.md` (13):** blurbs follow the title rules (noun phrases, no label). Read all 13; edit only on a rule hit.
5. **`_example_pages/index.md`:** delete line 15, "More examples land here as new chapters ship.", and the blank line after it. Read all 27 row descriptions for rules 7, 12 and 13. The row descriptions were written by the wave orchestrators, and some use defence and refusal vocabulary, which is fine as design.
6. **`_docs/00-outline.md`** is owned by V1. V1 checks line 17 ("planned WebSockets book", keep) and the part list; no sequence numbers.
7. **Root `README.md` (new, §8 D7):** modeled on gRPC's README structure.
   - Title.
   - A two-sentence lead.
   - The series line: REST → gRPC → GraphQL → WebSockets, linking both public sibling repos.
   - "What's here":
     - 28 chapters + Appendix A.
     - Both stacks.
     - Contract-first SDL with graphql-inspector.
     - Behavioural `verify.sh`.
     - Three tiers.
     - **No decks line** until S13 adds it.
   - "Domain": the tracking view.
   - "Build locally": the `ruby:3.3` container command from the RESUME POINTER, with a placeholder bundle dir.
   - "Run an example": `bash examples/NN-*/verify.sh`.
   - "Licence": MIT, per `_config.yml`.
   - No plan links, no `r01`, no step labels, no issue numbers.
   - About 50 lines. `README.md` is already in `_config.yml`'s `exclude`.
8. **`examples/_lib/lib.sh` (comments only), lines 1697 and 1742:** restate the specifiedByURL comments as design. For example: "The diff covers types, fields and arguments; `specifiedByURL` is compared by the scalar loop in `assert_sdl_conforms`, so `@specifiedBy` lines are filtered here." Then run `bash -n examples/_lib/lib.sh`.
9. **`examples/_lib/README.md`, `contracts/README.md`, `diagrams/README.md`:** read-through under rules 1–14.
10. **`_config.yml`:** confirm `plans: output: false`. No edit.

### 2.4 C2: Build and final sweep (S12b, part 2)

1. **Fresh Jekyll build** into a scratch destination, so the stale `_site/` cannot mask anything:

   ```
   docker run --rm -u $(id -u):$(id -g) -e HOME=/tmp -e BUNDLE_PATH=/bundle -v "$PWD":/site:Z -v <scratch>/bundle:/bundle:Z -w /site ruby:3.3 sh -c 'bundle install && bundle exec jekyll build --trace -d /tmp/site-out && grep -rl "/plans/" /tmp/site-out; echo rc=$?'
   ```

   Or build into `_site/`, which `jekyll build` cleans, then run `grep -rl '/plans/' _site`. **Expected: no file listed (grep rc=1)**, and no `plans/` directory in the output.
2. **More checks on the output:**
   - `grep -rliE 'iteration[- ]plan|coverage[- ]matrix|roadmap|\br01\b|\bwave [a-f]\b' <out>` returns nothing.
   - `bibliography/index.html` contains all four titles, the "Where each book is cited" section, rendered `/api-patterns-and-practices-graphql/docs/…` links, and both disclaimer sentences.
   - `sitemap.xml` holds no `/plans/` URL.
3. **Final rule-13 sweep (CV, Opus, read-only)** over the whole tree outside `_plans`, `node_modules`, `target` and `_site`:

   ```
   scan.sh --ext +sh,yaml,yml,java,properties,conf,tpl,mjs,txt --hits defect|upstream|spec-violation|security|plan link
   ```

   Plus a plain grep for `#[0-9]{3,5}`, `smallrye-graphql#`, `reported upstream`, `workaround`, `limitation`. Every hit is either on the keep list of §8 D5 (with its reason) or a finding routed back to its owner. Scope: chapters, READMEs, code comments, verify, smoke and script messages, chart comments, `NOTES.txt`, figure specs and SVG text. **Expected: 0 unclassified hits.**
4. **`_plans/` check (orchestrator, internal):** confirm no vulnerability detail is present. `_plans/upstream/` holds the three filed SmallRye bug bodies (non-security) and stays as it is. The RESUME POINTER issue numbers are internal and allowed.

---

## 3. Harness and CI additions

**None.** No change to `scripts/`, `.github/`, `examples/_lib` behaviour or `contracts/`. A voice gate in CI (`scan.sh --tier ban --fail`) is an S14 decision (§8 D10).

---

## 4. Acceptance criteria

**Bibliography (S12)**
- `bibliography.md` lists exactly the four books with the title, author(s), publisher and edition of §0, plus the year.
- The disclaimer sentences are present: `grep -c 'not sources' bibliography.md` ≥ 1 and `grep -c 'inform this site' bibliography.md` = 1.
- The "Where each book is cited" section has one row per citing chapter. DDIA rows cover **Ch12, Ch13, Ch14, Ch16** (and Ch11).
- `grep -nE 'Kleppmann|Designing Data-Intensive' _docs/1[2346]-*.md` returns at least one line per file.
- Every book chapter title in `_docs/` and in `bibliography.md` is on B1's confirmed list, and BV holds the source URLs. No unconfirmed title remains.
- Every chapter says "2nd edition" for DDIA: `grep -n 'second edition' _docs` returns nothing.

**Voice (S12)**
- `scan.sh --tier ban` over `_docs _parts index.html _example_pages bibliography.md README.md examples contracts/README.md diagrams/README.md` shows only kept hits. The kept hits are the SDL "deliberately small" string and the Containerfile "Bump deliberately" comments, each listed in the hand-back.
- The rule-13 labels over the same tree, with `--ext +sh,yaml,yml,java,properties,conf,tpl,mjs,txt`, show only §8 D5 keep-list hits.
- `grep -rn 'silently misreading' examples` returns nothing (if D5 is as recommended).
- `grep -rln 'annotations cannot' examples` returns nothing.
- `grep -rnE 'graphql-inspector (does not|never)|SmallRye ignores|Strawberry ignores' examples` returns nothing (if D6 is as recommended).
- Every chapter is within 2,800–3,400 (`bash scripts/wordcount.sh`), with net change ≤ ±150 per chapter or a justification in the hand-back; `GATE=1 bash scripts/wordcount.sh` exits 0.
- `git diff be72457 -- contracts/ scripts/ .github/` is empty.
- No line inside a fenced block, inline code or identifier changed (VVn's word-diff check).
- Figures: still 89 pairs, and every changed pair regenerates byte-identically from its spec.
- `python3 -I scripts/validate.py; echo rc=$?` prints `rc=0`.

**Site chrome (S12b)**
- `_example_pages/index.md` has no "land here as new chapters ship".
- Root `README.md` exists, with no `r01`, `S1x`, wave label, `_plans/` path or issue number: `grep -nE '\br0[0-9]\b|\bS1[0-4]\b|[Ww]ave [A-G]|_plans|#[0-9]{3,}' README.md` returns nothing.
- `_config.yml` has `plans:` with `output: false`.
- A fresh Jekyll build in `ruby:3.3` is clean (`--trace`, no warnings beyond the baseline), and **`grep -rl '/plans/' <build-dir>` is empty**.
- The footer, homepage, part index and examples index link only to outline, chapters, examples, bibliography, external reference sites, the repo and its issues.

**Wave**
- On PR #1, all 25 `verify:` jobs plus `site`, `k8s-manifests`, `contracts` and `ci-ok` are green after the last Wave G push.
- No chapter status changes in `coverage-matrix.md`; Ch1–2 stay `draft`, since they carry no example.
- No compose project or cluster was started by this wave, except any example verify an executor chose to run, which is torn down by its trap.

---

## 5. Risks and detection

| Risk | Detection / mitigation |
|---|---|
| A publisher contents page is unreachable or behind login | Fallback: the O'Reilly Learning page for the ISBN. If still unconfirmed, rewrite the sentence to book level (D2); never guess a title. |
| A voice edit changes a fenced block, inline code or an identifier | VVn word-diff check; `scan.sh` blanks code, so executors edit prose only. |
| A comment edit in Java/Python breaks a build (an unclosed `/**`, a docstring quote) | VVn reads every code-file diff; CI's 25 verify jobs rebuild every image. Restrict edits to whole comment lines. |
| A verify-message edit changes text that another check greps for | Messages are free text in `lib.sh` assertions; nothing parses them. VVn greps the message text across `examples/` before accepting a change. |
| Word count drifts out of band (Ch0, Ch1, Ch5, Ch8 near the ceiling) | ±150 rule; wordcount report before and after in each hand-back; the GATE enforces only the floor, so VVn checks the ceiling by hand. |
| Rule-13 restatements turn into new claims | Restate only what the code does (as in fabe070); no new behaviour claims; VVn compares against the code. |
| The stale `_site/` gives a false `/plans/` result | C2 builds into a fresh destination or lets `jekyll build` clean `_site/`; only that output counts. |
| Liquid in the new bibliography table does not render | C2 checks `bibliography/index.html` for resolved links. |
| Two executors touch a shared file (lib.sh, glossary, `_example_pages`) | Single-owner sets in §1; lib.sh and `_example_pages` are C1's only. |
| A label change regenerates a figure differently from its committed pair (a generator drift) | Regenerate only edited specs; byte-identical check on untouched specs is not required. If an edited spec's pair diff touches more than the label, stop and report. |
| CI flake (a Maven Central fetch, Wave F §9) | Re-run the failed jobs once; record it in GW. |
| An executor writes defect or vulnerability detail into `_plans/` or a hand-back file in the repo | Content rule; hand-backs go to the orchestrator in chat only; CV greps `_plans/` for new files. |

---

## 6. Coverage-matrix and plan updates (orchestrator only)

1. `coverage-matrix.md`: no status changes.
2. `_plans/iteration-plan.md`: S12 → done (voice scan clean), S12b → done.
3. `_plans/r01-execution-plan.md` RESUME POINTER: add rows for S12 (done, date, CI sha) and S12b (done), and keep "S13 next". Keep the note "Do not merge r01 → main until the user clears it."
4. Add **§9 "Wave G findings"** to this plan at GW. It holds engineering notes only, in the neutral form: verified book chapter titles with numbers (no URLs needed), kept watch-tier hits with reasons, any scan pattern worth adding to a project `.voice-patterns.tsv` for S14.
5. `_plans/domain-glossary.md`: no change.

---

## 7. Binding pitfalls carried forward (every Wave G executor)

- **From Waves A–F (still binding):**
  - Reader-facing text is a tutorial (Wave C §9).
  - Books are cited by verified chapter title, docs by page title (Wave B/D §9).
  - Figures are numbered by order of appearance, with full-sentence alt text, rendered and viewed (Wave B §9).
  - Never hand-edit SVG.
  - `validate.py` exit code is checked directly.
  - No `{{`/`{%` in prose outside includes and fences.
  - Stack differences are stated neutrally.
  - "Platform differences as design" (Wave F content rule).
- **New in Wave G:**
  - **G-1.** Prose, comments and message strings only; any other diff line is out of scope and gets reverted.
  - **G-2.** Contract description strings and identifiers are never reworded, even when a scan flags them.
  - **G-3.** Every survivor of a ban-tier or rule-13 pattern is listed with a one-line reason in the hand-back.
  - **G-4.** Citations change only through B1's table.
  - **G-5.** No chapter grows past 3,400 or shrinks below 2,800; Ch0, Ch1, Ch5 and Ch8 must not grow.
  - **G-6.** Hand-backs and findings go to the orchestrator, never into a repo file; nothing about a suspected defect or security weakness is written anywhere.

---

## 8. Open decisions needing user input (each with a recommendation)

1. **Bibliography layout.**
   - (a) **Keep the Books table, add Edition and Year columns, and add a "Where each book is cited" section** with one table per book (chapter here → chapter of the book).
   - (b) Add Year only (REST parity), with no mapping.
   - (c) Mapping only inside each chapter's closing section (already true).

   **Recommend (a):** it meets the per-chapter mapping requirement and keeps sibling parity on the table.
2. **Unverified chapter titles** (six, §0).
   - (a) **B1 verifies each against the publisher's public contents page.** Confirmed titles stay; unconfirmed ones become book-level citations.
   - (b) Rewrite all six to book level now.
   - (c) Leave them as they are.

   The O'Reilly MCP search returns book records only (tested 2026-10-17), so it cannot verify chapters. **Recommend (a).**
3. **Gaps against the execution plan's book ranges** (Czemiel Ch15, 16, 18; Lyon Ch19, 20, 21).
   - (a) **Do not add citations to fill the ranges.** The mapping reports actual citations, and the Focus column describes each book as this site uses it. Neither book has a verified chapter on persisted queries, observability, federation or subscriptions.
   - (b) Add one sentence each where B1 confirms a matching chapter, inside each chapter's ±150 budget.

   **Recommend (a).** The acceptance criterion names only DDIA in Ch12/13/14/16, which is met.
4. **Book-level citations in Ch1, Ch2 and Ch22.**
   - (a) **Keep them book-level**: Ch1 and Ch2 are overview chapters, and Ch22 describes each book's client approach as a whole.
   - (b) Add verified chapter titles to Ch22 if B1 confirms them.

   **Recommend (a)**, with (b) optional for Ch22 only if it fits the budget.
5. **Inherited comment and prose hits judged domain uses.**
   - Keep: "never reaches it" (`HandlingRegistration`), the `bug` alias, `BYPASS`/bypass (cache), "broken" (domain rules, promise, graph, fixtures), "silently did nothing" (Ch11), "misreading cursors" (Ch12), "the rule cannot be bypassed", "Partner feeds bypass the graph", `lib.sh` "never reads as a match" and "never reaches telemetry", Containerfile "Bump deliberately", the SDL "deliberately small", and the CI comment "a deterministic bug".
   - Small edits:
     - drop "silently" from "silently misreading old cursors" in 12–14 and 19–25, matching Ch15–18 and Ch27;
     - `index.html` "schema-violating result" → "a result that does not match the schema".

   **Recommend keep-all plus the two small edits.**
6. **Tool-behaviour comments.** These are the `ContractSchemaDetails` Javadoc "cannot express / always writes / appends" (14, 15, 16, 17, 18, 23), the specifiedByURL comments (`verify.sh` 00, 03, 08, 10, 11; `lib.sh:1697`, `:1742`), "SmallRye ignores them too" (15, 16) and "Strawberry ignores the URL parameter on POST" (15).
   - (a) **Restate as design**, using the Ch13/19+ Javadoc as the model.
   - (b) Keep them as neutral facts.

   **Recommend (a).** They are code comments, which rule 13 covers explicitly.
7. **Root `README.md`.**
   - (a) **Add one in S12b**, modeled on gRPC's, with no deck line until S13.
   - (b) Defer to S14.
   - (c) None.

   **Recommend (a).** It is the GitHub landing page and the only reader-facing surface the site build excludes.
8. **Template "Coming soon" branches and the examples-index sentence.**
   - Delete "More examples land here as new chapters ship."
   - Keep the never-rendered "Coming soon" branches in `index.html` and `part_index.html`, for gRPC template parity; rule 14 allows a plain stub.

   **Recommend as stated.**
9. **Commit and push granularity.**
   - (a) **One commit per step** (B1, V1–V5, C): seven commits, each pushed, with CI cancelling superseded runs and the final run fully green.
   - (b) One squash commit for the wave.

   **Recommend (a)**, matching Waves A–F.
10. **CI and gate changes.**
    - (a) **None in this wave.** Leave `wordcount.sh`'s 2,000–2,500 header and `MIN=2000` as they are. At S14, decide whether to align its text to 2,800–3,400 and whether to add `scan.sh --tier ban --fail` (with a project pattern file for the keep list) as a CI step.
    - (b) Do both now.

    **Recommend (a):** `scripts/` and `.github/` stay out of this wave's write sets.
11. **`_plans/` in the voice pass.** **Recommend: excluded.** The plans are internal and unrendered. The orchestrator only confirms that they hold no vulnerability detail (C2 step 4).

### Critical files for implementation
- `/home/rsedor/Dev/api-patterns-and-practices-graphql/bibliography.md`
- `/home/rsedor/Dev/api-patterns-and-practices-graphql/_docs/` (the citing chapters in §0, and every chapter for V1–V5)
- `/home/rsedor/Dev/api-patterns-and-practices-graphql/_example_pages/index.md`, `/home/rsedor/Dev/api-patterns-and-practices-graphql/index.html`, `/home/rsedor/Dev/api-patterns-and-practices-graphql/_includes/footer.html`, `/home/rsedor/Dev/api-patterns-and-practices-graphql/_layouts/part_index.html`
- `/home/rsedor/Dev/api-patterns-and-practices-graphql/examples/_lib/lib.sh` (comments at 1697 and 1742) and `examples/1[4-8]-*/quarkus/.../ContractSchemaDetails.java`, `examples/23-testing/quarkus/.../ContractSchemaDetails.java`
- `/home/rsedor/.claude/skills/lgtm-professional-voice/SKILL.md`, `references/surfaces.md`, `scripts/scan.sh`, `scripts/patterns.tsv`
- Templates (read-only): `/home/rsedor/Dev/api-patterns-and-practices-grpc/README.md`, `/home/rsedor/Dev/api-patterns-and-practices-rest/bibliography.md`, gRPC commit `4b33d5f`

---

## 9. Wave G findings

- **Liquid processes fenced code.** A Go or Helm template (`{{ … }}`) inside a fence renders empty unless the fence is wrapped in `{% raw %}` … `{% endraw %}`. Fixed in Ch25, Ch26 and Appendix A. Candidate S14 gate: `validate.py` fails a fence containing `{{` that is not inside raw.
- **Publisher contents pages** (O'Reilly, Packt) refuse automated fetches. Manning's livebook chapter pages confirm titles. Seven chapter titles (four DDIA, three GBP) are cited book-level.
- **Restating a sentence can introduce a factual error.** Each validator caught one: the introspection-guard comment, the restricted-v2 sentence, and the Ch17 body-limit wording left inconsistent across files. Restate the fact, then check it against the code.
- **Restate a rule-13 phrase in every file that repeats it** (chapter, README, verify comment, figure), not only in the chapter.
- **A Jekyll build with the repo mounted can rewrite `Gemfile.lock`** (Bundler adds its own checksum). Revert it after a scratch build.

(Appended at GW.)

---

## 10. Host hygiene and what comes next

- This wave starts no cluster. `gql-tracking` stays Stopped and CRC stays Stopped.
- Any example `verify.sh` an executor runs tears itself down through the harness trap.
- Jekyll builds only in the `ruby:3.3` container, with the bundle dir in the session scratch.
- `scan.sh` runs with `TMPDIR` set to the session scratch.
- **S13 (three decks) comes next and depends on S12.** S13 adds the decks line to the root README.
- **S14 (release gate and publish)** runs the full sweep, including the voice gate (rules 13–14) and the re-check of the `braces` advisory. **S14 does not merge `r01` to `main` until the user clears it.** The hub `_data/sites.yml` and `_data/books.yml` entries are the user's out-of-repo follow-up.