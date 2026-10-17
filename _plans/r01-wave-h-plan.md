---
layout: plan
render_with_liquid: false
title: "r01 Wave H Plan — S13 Three decks"
---

# Wave H (S13): three decks — 100 concepts, Quarkus, Python

**Status: DONE 2026-10-17 (H0–H4, HV1–HV4, HX). APPROVED by user 2026-10-17 — §8 D1–D11 as recommended (D7 Red Hat Display for titles); D12 changed by the user: NO revision marker — no "r1.0" on the cover and no "-r1.0" in file names (`OUT` is `<deck>.pptx`, `REV` unused). This overrides every `-r1.0` mention below. Figure caps (H0 measured a 91 KB average): 100 deck ≤ 46, Quarkus ≤ 14, Python ≤ 14. Cover eyebrow on all three decks (series rule in `presentation/_shared/README.md`): text `API PATTERNS & PRACTICES · GRAPHQL · {100|QUARKUS|PYTHON}`, `fontSize: 13`, `charSpacing: 3`, `x: 6.00`, `y: 1.82`, `w: 6.90` (HV3 measured). Code on slides comes from `snippet(src, ranges)` read from the repo at build time. `qa.py` also fails a deck whose title is not "API Patterns & Practices: GraphQL …" or that carries a revision marker. Execution starts after the Appendix A live CRC run is cleaned up.**

This plan is written for Sonnet executors and Opus validators. Where it gives a value (a path, a version, a count, a regex, a command), use exactly that value. Line numbers drift; locate text by quoting it.

**Precondition.** S12 and S12b are done (59c94fb). Ch0, Ch3–27 and Appendix A are `verified` and Ch1–2 are `draft`. There are 89 figure pairs, the voice pass is clean, and CI is green. `presentation/` does not exist yet.

**The content rule (binding on every executor and validator).**
- The decks teach GraphQL, both stacks and the patterns.
- Slide text, speaker notes, captions and code comments shown on slides never describe:
  - framework, tool or platform defects;
  - limitations, upstream issues or issue numbers;
  - workarounds or spike narratives;
  - bypass or attack stories;
  - security weaknesses.
- Stack differences are stated neutrally, as teaching material.
- Spec conformance is stated as "the draft recommends X". Omit what a stack answers unless the chapter states it neutrally and it teaches something.
- No planning language appears anywhere in a deck or its source: wave, iteration, r01 or any rNN, S-numbers, capstone, roadmap, coverage, phase, `_plans`.
- This is `lgtm-professional-voice` rules 1–14.
- **The decks mine the chapters (`_docs/`), the canonical SDL (`contracts/schema/`) and the example code (`examples/`). They never mine `_plans/`.**
- An executor who finds something that looks like a defect or a weakness reports it to the orchestrator in one neutral line and writes nothing about it in any file.

**The scope rule (binding).**
- This wave writes only `presentation/**`, `.gitignore` (one line) and the root `README.md` (the decks line).
- No change to `_docs/`, `examples/`, `assets/`, `diagrams/`, `contracts/`, `scripts/`, `.github/`, `_config.yml`, `_includes/`, `_layouts/`, `_parts/` or `bibliography.md`.
- No new SVG figure. A deck needs a figure the site does not have → stop and ask (§8 D6 note).

---

## 0. Facts checked (2026-10-17)

**This repo (r01 @ 59c94fb)**
- `presentation/` is absent.
- `.gitignore` already has `presentation/_shared/node_modules/`, `presentation/**/__pycache__/`, `presentation/**/qa/`, `.deck-src/` and a global `node_modules/`.
- `_config.yml:88` already excludes `presentation/` from Jekyll, so decks are never published on Pages.
- `assets/diagrams/` holds 89 `.svg` files (568,274 bytes) and 89 `.excalidraw` files.
  - Every SVG uses `font-family="'Red Hat Text', system-ui, sans-serif"`.
  - viewBox aspect ratios run from 1.48 (`03-type-system-map`) to 3.47 (`07-resolver-chain`).
  - Chapter include lines carry captions of the form `Figure N.x — …`.
- Canonical SDL: `contracts/schema/shipping/{cargo,handling,location,scalars,schema,voyage}.graphql`, 414 lines in total. `UserErrorCode` lives in `handling.graphql`.
- Execution-error codes seen in the chapters: `BAD_USER_INPUT`, `UNAUTHENTICATED`, `FORBIDDEN`, `SERVICE_UNAVAILABLE`, `INTERNAL_SERVER_ERROR`.
- Stack versions to state on the series-map slides (re-read from the files at build time):
  - Quarkus `3.40.1` (`examples/27-final-project/quarkus/pom.xml`), with `quarkus-smallrye-graphql`;
  - Strawberry `0.335.0`, FastAPI `0.143.2` and Python `>=3.14` (`examples/27-final-project/python/pyproject.toml`).

**Sibling templates (read-only)**

| | gRPC | REST |
|---|---|---|
| Layout | `_shared/` + `api-patterns-grpc-{100,quarkus,python}/` (each `deck.js` + `<name>-r1.0.pptx`) | same, `api-patterns-rest-*` |
| `_shared` files | `README.md`, `deck-helpers.js`, `dgen.py`, `build_diagrams.py`, `diagrams.py`, `render_svgs.py`, `package.json`, `package-lock.json`, `assets/` (4 PNG), `png/` (72 PNG, 6.06 MB) | same minus `render_svgs.py`; `png/` 14; `diagrams/` 16 fallback pairs |
| Slides (= notesSlides) | 100: **99**, quarkus: **66**, python: **68** | 45 / 47 / 46 |
| `.pptx` sizes | 8.51 / 4.59 / 4.43 MB | 2.76 / 2.78 / 2.75 MB |
| Tracked `presentation/` | **24,140,029 bytes** | 10,350,836 bytes |
| Committed | `.pptx`, `deck.js`, `png/`, lockfile | same |
| Ignored | `node_modules/`, `qa/`, `__pycache__/` | same |
| PDFs | none | none |
| CI | no deck job (`contracts.yml`, `pages.yml` only) | no deck job |
| Site | no nav entry, no page; README lists the decks; `_config.yml` excludes `presentation/` | same |

- `deck-helpers.js` is byte-identical in gRPC, REST and `~/.claude/skills/lgtm-presentation/scripts/`. It sets `FONT.title: "Overpass"`, while SKILL.md and `references/theme.md` say **Red Hat Display**.
- gRPC `dgen.py` matches the skill's. gRPC `build_diagrams.py` renders PNGs with cairosvg instead of the skill's `/mnt/skills/.../soffice.py`.
- gRPC `render_svgs.py` renders `../../assets/diagrams/*.svg` to `png/` at 1400 px with cairosvg, under `python3 -I`, adding the user site-packages back.
- Deck wiring:
  - each `deck.js` sets `DECK_ASSETS`/`DECK_PNG` to `../_shared/...` and requires `../_shared/deck-helpers.js`;
  - the build runs with `NODE_PATH=$(cd ../_shared/node_modules && pwd) node deck.js`;
  - `OUT` is `<deck>-r1.0.pptx` and `REV = "r1.0"` is printed on the cover.
- Sibling structure: cover → agenda → (series map, stack decks only) → numbered `divider()` sections → closing → appendix divider → appendix. The gRPC 100 deck puts its secondary figures in an `APPENDIX_FIGURES` loop.
- Sibling text the decks must not copy:
  - the eyebrow `ROADMAP` on the agenda;
  - ALL-CAPS emphasis and stacked em dashes in the notes;
  - a gRPC appendix caption that tells a platform-limitation story.
- **pptxgenjs stores one media copy per `addImage` call**, as measured in the gRPC 100 deck: 180 media parts, including 86 copies of the 6 KB footer logo and 13 copies of the 92 KB `section-panel.png`. Diagram PNGs average about 85 KB at 1400 px.
- `addFooter` and `addSectionDivider` wrap `addImage` in `try { } catch {}`, so a missing image produces no build error.
- The skill ships no QA script. Its QA is the command sequence: `node deck.js` → `soffice --convert-to pdf` → `pdftoppm`. pptxgenjs writes a notesSlide for every slide, so counting notes parts proves nothing; QA must read the note text.

**Versions (registry checks 2026-10-17)**

| Item | Version | Source / note |
|---|---|---|
| `pptxgenjs` | **4.0.1** (`latest`; published 2025-06-26; `beta` = 4.0.1-beta.2) | `npm view pptxgenjs` |
| `@types/node` (transitive, `^22.8.1`) | 22.20.5 | newest 22.x; 26.6.5 is outside the range pptxgenjs declares |
| `image-size` (`^1.2.1`) | 1.2.1 | 2.0.4 is outside the range |
| `jszip` (`^3.10.1`) | 3.10.2 | |
| `https` (`^1.0.0`) | 1.0.0 | |
| `cairosvg` | **2.9.1** | PyPI JSON |
| Node image | `registry.access.redhat.com/ubi10/nodejs-24:10.2-1791943587` (= `:latest`, digest `sha256:8f8b90769f48b962ae25b45a77abee4c6a6b025e2dceecceee0eaaa02650dcea`, created 2026-10-14) | `skopeo inspect`; same pin as `examples/22-client-integration/clients/js/Containerfile` |

The gRPC lockfile already resolves exactly these transitive versions.

**Host (QA tools; not pinned, recorded)**
- Node v22.22.2, which is why the Node build runs in the container.
- LibreOffice 26.2.6.3, pdftoppm 26.01.0, ImageMagick 7.1.2-32 (`montage`), Docker 29.9.1, uv 0.13.0.
- `redhat-display-fonts`, `redhat-text-fonts` and `redhat-mono-fonts` 4.1.0 are installed.
- cairosvg is not installed; it runs through `uv run --with`.

**Chapter text that the decks must not carry onto slides (content rule)**
- `ContractSchemaDetails` (Ch0, 3, 5, 10, 11 prose and every Quarkus example).
- `quarkus.class-loading.removed-resources…ErrorExtensionProvider` (in `application.properties` of examples 09, 12, 22 and others).
- The "SmallRye defaults differ from the contract" passages (Ch3).
- The Ch6 multi-operation `operationName` difference.
- The status-code conformance passages, except as "the draft recommends".
- Cache `BYPASS`/bypass wording (Ch16).
- Appendix A seccomp/anyuid detail.
- Any passage in Ch14/17 that reads as an attack recipe.
- The Ch15 persisted-document route may appear only as design ("a router route in front of the GraphQL endpoint resolves the hash"), exactly as Ch15 frames it.

---

## 1. Approach

Clone gRPC's `presentation/` structure and re-skin it for GraphQL. Deliberate differences, each justified in §0 or §8:
1. `FONT.title` is Red Hat Display.
2. `png/` is generated and gitignored.
3. Figure and divider embeds are capped by the size budget (§1 Size budget).
4. `_shared/build.sh` (pinned container) and `_shared/qa.py` (stdlib QA) are new.
5. Slide titles are 2–5-word noun phrases and the claim goes in the caption (voice rule 5; the siblings use sentence titles).
6. Diagram captions start with the book's figure number (`Figure 13.2 — …`).

### Sequencing (DAG)

| Step | Executor | Owns (exclusive write set) | Depends on |
|---|---|---|---|
| **H0** Probe | orchestrator | scratch only. (1) Render all 89 SVGs with `uv run --with cairosvg==2.9.1` into scratch and record the total bytes and the average and maximum PNG size. (2) `npm install --package-lock-only` for `pptxgenjs@4.0.1` in the pinned container on a scratch copy, then diff the result against gRPC's lock. (3) `npm audit --omit=dev` result. (4) Container `-u $(id -u):$(id -g)` with a `:z` mount works. (5) Finalize the per-deck figure caps (§1 Size budget) from the measured average. | — |
| **H1** `_shared` scaffold | Executor S (Sonnet) | `presentation/_shared/**`; `.gitignore` (one line: `presentation/_shared/png/`); root `README.md` (decks bullet + Layout row) | H0 |
| **HV1** | Opus | read-only | H1 |
| **H2** 100 deck | Executor C (Sonnet) | `presentation/api-patterns-graphql-100/**` | HV1 |
| **H3** Quarkus deck | Executor Q (Sonnet) | `presentation/api-patterns-graphql-quarkus/**` | HV1 |
| **H4** Python deck | Executor P (Sonnet) | `presentation/api-patterns-graphql-python/**` | HV1 |
| **HV2 / HV3 / HV4** | Opus, one per deck | read-only; findings routed to that deck's executor | its H2/H3/H4 |
| **HX** Cross-deck pass | Opus | read-only: agenda parity, terminology, series-map claims, total size | HV2–HV4 pass |
| **HW** Wrap | orchestrator | `_plans/*`, commits, pushes | HX, CI green |

How to run it:
- **H2, H3 and H4 run in parallel** once HV1 passes. Their write sets are disjoint, and all three only read `_shared/`, `_docs/`, `contracts/` and `examples/`.
- `png/` is written once, by H1. Deck executors never re-run `render_svgs.py`; a missing PNG goes back to the orchestrator.
- **Parallel-safety rules**:
  - container mounts use `:z` (shared label), never `:Z`;
  - every `soffice` call passes its own `-env:UserInstallation=file://<scratch>/lo-<deck>`, because concurrent LibreOffice instances on one profile fail;
  - every `scan.sh` call sets `TMPDIR=<scratch>`.
- **Repair rounds:** at most two per deck. A third failure goes back to the user.
- **Commits** (orchestrator, §8 D10). Push after each one:
  - `docs(deck): shared deck scaffold — helpers, figure renderer, build and QA` (H1, after HV1);
  - `docs(deck): GraphQL concepts deck (100)` (H2, after HV2);
  - `docs(deck): Quarkus implementation deck` (H3, after HV3);
  - `docs(deck): Python implementation deck` (H4, after HV4);
  - `docs(r01): S13 complete — three decks; S14 next` (HW, plans only).

### Size budget (hard limit: tracked `presentation/` < 15,000,000 bytes; target ≤ 12,500,000)

Unit costs (gRPC measurements; H0 replaces the figure average with the measured one):

| Embed | Bytes per use |
|---|---|
| section divider (`section-panel.png` + white logo) | ~95 KB |
| cover (`cover-panel.png` + logo) | ~84 KB |
| content-slide footer logo | ~6 KB |
| one figure PNG | ~85 KB |

| Deck | Slides | Dividers (incl. appendix) | Figure embeds (cap) | Target size |
|---|---|---|---|---|
| 100 | 77 | 13 | **≤ 50** | ≤ 6.0 MB |
| Quarkus | 66 | 13 | **≤ 16** | ≤ 3.0 MB |
| Python | 66 | 13 | **≤ 16** | ≤ 3.0 MB |
| `_shared` (code, assets, lock, README) + 3 × `deck.js` | — | — | — | ≤ 0.6 MB |
| **Total tracked** | | | | **≤ 12.6 MB** |

- `png/` (about 7.5 MB for 89 figures) is not tracked (§8 D6). It would push the total past 15 MB.
- If H0's measured figure average is above 85 KB, scale each cap with `cap = floor((deck target − dividers − cover − logos) / avg)`, and cut appendix figures first.
- No deck may raise its divider count above 13.

### Build procedure (all decks)

```bash
# once (H1): figures, on the host — the host has the Red Hat fonts the SVGs name
cd presentation/_shared && uv run --no-project --with cairosvg==2.9.1 python -I render_svgs.py

# per deck: build in the pinned container (wrapper: presentation/_shared/build.sh <deck-dir>)
IMG=registry.access.redhat.com/ubi10/nodejs-24:10.2-1791943587
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e npm_config_cache=/tmp/.npm \
  -v "$PWD/presentation:/work:z" -w /work/_shared "$IMG" \
  sh -c 'test -d node_modules || npm ci --no-audit --no-fund; node -e "require(\"pptxgenjs\")"'
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e NODE_PATH=/work/_shared/node_modules \
  -v "$PWD/presentation:/work:z" -w /work/<deck-dir> "$IMG" node deck.js
```

- `build.sh` runs exactly these two commands.
- If `node_modules` is absent or `require("pptxgenjs")` fails, it reinstalls with `npm ci`.
- It then confirms that every PNG name the deck references exists in `_shared/png/`, by grepping `deck.js` for `addDiagramSlide(` and `file:` entries, before it runs `node deck.js`.
- `deck.js` keeps the sibling wiring unchanged (`SHARED = path.resolve(__dirname, "../_shared")`), so a host build with Node 24 also works.

### QA procedure (every deck, every round)

1. **Build:** `bash presentation/_shared/build.sh <deck-dir>`. It must exit 0 and print `WROTE … slides: N`, with N in the deck's band (§8 D1).
2. **Structural QA:** `python3 -I presentation/_shared/qa.py presentation/<deck-dir>/<deck>-r1.0.pptx`. It must exit 0. The checks (§2.1) also write `qa/<deck>.txt` (slide text and notes, one block per slide) and `qa/<deck>.json` (per-slide facts).
3. **Voice scan:** `TMPDIR=<scratch> ~/.claude/skills/lgtm-professional-voice/scripts/scan.sh --tier ban presentation/<deck-dir> presentation/<deck-dir>/qa`. Expect 0 hits, or each survivor listed with a reason (identifiers inside code lines only). Repeat with `--hits all --tier watch` and triage.
4. **Render:**
   - `soffice -env:UserInstallation=file://<scratch>/lo-<deck> --headless --convert-to pdf --outdir presentation/<deck-dir>/qa <pptx>`.
   - The PDF page count must equal N (`pdfinfo`).
   - `pdftoppm -jpeg -r 50 qa/<deck>.pdf qa/pg`, then `montage qa/pg-*.jpg -tile 4x3 -geometry +4+4 qa/sheet-%02d.jpg`.
   - The executor and the validator **view every contact sheet**.
   - Every code slide, table slide and the cover are also rendered at `-r 110` (`-f K -l K`) and viewed.
   - Eyeball checklist (skill):
     - titles do not overflow;
     - code captions sit below the dark box;
     - no code line overflows the box;
     - table first columns do not wrap;
     - diagrams are centred and not upscaled past legibility;
     - the logo is bottom-right on every content slide;
     - divider text sits on the panel.
5. **Code fidelity and content:** covered by `qa.py`. The validator also reads `deck.js` in full against the chapters it cites.

### Executor rules (binding; restate them in every brief, because subagents do not inherit skills)

- Write files only; no git. Edit only your write set.
- Paste into every brief:
  - the skill house conventions (fonts, `#EE0000`, logo on every slide via `S()`, notes on every slide, cross-reference by concept and never by slide number, no build or process language, appendix "keep open in another window");
  - the voice rules 1–14 and the surfaces table;
  - the content rule;
  - the scope rule.
- **Slide titles:** 2–5-word noun phrases naming the concept ("Null propagation", "The DataLoader tick"). The claim goes in the caption.
- **Eyebrows:** short ALL-CAPS topic labels, which are the helper's typography (`NULLABILITY`, `APPX · REFERENCE`). Never `ROADMAP`; the agenda eyebrow is `OVERVIEW`.
- **Captions:**
  - one line, ≤ 110 characters;
  - diagram captions start with the book's figure number, `Figure N.x — `, taken from that figure's include line in `_docs/` (`grep -n 'file="<name>"' _docs/*.md`), followed by a short noun phrase.
- **Notes:**
  - every slide; ≥ 200 characters each;
  - body slides 120–250 words; appendix slides ≥ 40 words;
  - structure: what the slide shows → the point → where the chapter covers it ("Chapter 13 covers the tick in detail");
  - no delivery coaching, no ALL-CAPS emphasis, at most one em dash per sentence.
  - The cover note may introduce the speaker, as the siblings do.
- **Code slides:**
  - The first line is a source header comment with a repo-relative path. `addCodeSlide` renders it green. Use the comment marker of the code's language: `// examples/13-dataloaders/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/EventLoaders.java` (Java), `# examples/13-dataloaders/python/app/loaders.py` (Python), `# contracts/schema/shipping/cargo.graphql` (SDL, documents), `# _docs/09-error-handling.md (On the wire)` (recorded JSON).
  - Append ` (excerpt)` when lines are omitted. An omitted run is shown as one elision line: `...`, `// ...` or `# ...`.
  - Every other line is copied character for character from that file. Indentation may be reduced uniformly. No added comments, no renamed identifiers, no reflowed lines.
  - Limits: ≤ 22 lines at 11 pt, ≤ 26 at 10 pt.
  - The `lang` chip names the language and framework (`java · SmallRye GraphQL`, `python · Strawberry`, `graphql · SDL`, `json · response`).
- **Never quote** the files and lines listed at the end of §0.
- **Figures:** only `assets/diagrams/*` basenames, through `addDiagramSlide`, within your deck's cap. No `diagrams.py` scenes and no hand-drawn shapes standing in for a diagram.
- **Before handing back:** run QA steps 1–4, then report the slide count, the figure-embed count, the `.pptx` bytes, the `qa.py` output, the `scan.sh` survivors with reasons, and the list of contact sheets viewed.

**Rejected alternatives**
- *Byte-for-byte gRPC mirror including `png/` and every figure in the 100 deck:* about 20 MB tracked, which breaks the 15 MB criterion.
- *Rewrite `deck-helpers.js` to reuse one image part per file (smaller decks):* the skill says extend, don't rewrite, and sibling parity is lost.
- *Lower the PNG width below 1400 px:* figures with long labels (`07-resolver-chain` at aspect 3.47) become unreadable when projected.
- *Everything on the host:* the host has Node 22, while the standing rule requires the pinned Node 24 container.
- *Everything in the container:* the UBI image has no Red Hat fonts and no LibreOffice, so cairosvg and soffice output would use fallback fonts. Mounting host fonts into the container adds SELinux label handling for no gain.
- *New figures drawn with the Scene engine:* the site's 89 figures cover every chapter, and new diagrams outside the site's generator are out of scope.

---

## 2. Per step

### 2.1 H1: `_shared` scaffold (Executor S)

Files (gRPC source → this repo):

| File | Action |
|---|---|
| `deck-helpers.js` | Copy from gRPC. Change exactly `title:   "Overpass",` → `title:   "Red Hat Display",` and the header comment `Title 30pt Overpass SemiBold` → `Title 30pt Red Hat Display`. No other diff (HV1 checks with `diff`). |
| `dgen.py`, `build_diagrams.py`, `diagrams.py` | Copy unchanged (the fallback engine, unused; README says so). |
| `render_svgs.py` | Copy. Change only the docstring and comment counts (`72` → `89`) and add the `uv run` invocation to the docstring. Logic unchanged. |
| `assets/*.png` (4) | Copy; must be `cmp`-identical to the skill's `assets/`. |
| `package.json` | Name `api-patterns-graphql-presentation-shared`; description re-skinned to GraphQL; `"dependencies": { "pptxgenjs": "4.0.1" }` (exact, no caret); add `"engines": { "node": ">=24" }`; scripts `figures`, `diagrams`, `build` (→ `bash build.sh`), `qa` (→ `python3 -I qa.py`). |
| `package-lock.json` | Generated in the pinned container with `npm install --package-lock-only`. Must resolve exactly the versions in §0. HV1 diffs it against gRPC's lock; expected differences are the root name and the `pptxgenjs` spec only. |
| `README.md` | Port gRPC's and re-skin it: deck table, 89 figures, `uv run` render command, the container build, QA steps, the size rule ("`png/` is generated; never commit it"), and the font note (Red Hat Display / Text / Mono, OFL; install them to view the decks as designed). |
| `build.sh` (new) | §1 Build procedure: `set -euo pipefail`; argument is the deck dir; checks the PNGs exist; trial-requires pptxgenjs; prints the image tag in use. `bash -n` and shellcheck clean. |
| `qa.py` (new, stdlib only, `python3 -I`) | Checks below. Exit 1 on any failure; prints one line per finding. |

`qa.py` checks (read the `.pptx` with `zipfile` and `xml.etree`):
1. **Slides:** count `ppt/slides/slideN.xml`; print it. Optional `--band LO-HI`.
2. **Notes on every slide:** each slide has a `notesSlide` relationship. Its `<a:t>` text, minus the slide-number placeholder, is at least 200 characters after whitespace collapse.
3. **Logo on every slide:** each slide's image relationships include a media part whose SHA-256 equals `assets/logo-candidate-2.png` or `assets/redhat-logo-white.png` (for dividers).
4. **Fonts:** every `typeface` attribute in slide XML is one of `Red Hat Display`, `Red Hat Text`, `Red Hat Mono`.
5. **Planning language (all slide and notes text, code included, no exceptions), case-insensitive:** `\b(capstone|roadmap|iterations?|waves?|coverage|r[0-9]{2}|S[0-9]{1,2}[a-z]?|phase [0-9]+|milestone|sprint|backlog|TODO|TBD|FIXME|_plans|execution plan)\b`. The cover marker `r1.0` does not match.
6. **Content rule (prose: titles, bullets, captions, tables, notes):** `\b(workarounds?|work around|bugs?|defects?|limitations?|upstream|issue ?#?[0-9]+|#[0-9]{3,}|reproducers?|vulnerab\w*|exploit\w*|attack\w*|bypass\w*|CVE-[0-9-]+|leak\w*|broken|violat\w*|deviat\w*)\b` → fail. The same pattern in code lines → warning, listed for validator triage.
7. **Banned sources:** `ContractSchemaDetails|removed-resources|smallrye-graphql#|ErrorExtensionProvider\b` anywhere → fail.
8. **Code fidelity:**
   - For each text body whose runs use `Red Hat Mono` inside a slide that has a `151515`-filled rect, split the text on line breaks.
   - Line 1 must match `^(//|#|<!--)\s*(\S+?)( \(excerpt\)| \(On the wire\)| \(On the wire, excerpt\))?\s*(-->)?$`, and the path must exist relative to the repo root.
   - Every other non-blank line that is not an elision line must equal a line of that file after `strip()`.
   - Lines must appear in file order, so the slide is a subsequence of the file.
   - Without `(excerpt)`, the lines must also be contiguous.
9. **Diagram images:** every slide whose `deck.js` block calls `addDiagramSlide` carries a non-logo, non-panel media part. Cross-check: the number of media parts that are neither logos nor panels equals the number of figure embeds, and that number is ≤ the deck's `--figure-cap`.
10. **Sizes:** print the `.pptx` bytes. Optional `--max-bytes`.
11. **Text dump:** write `qa/<deck>.txt` (`=== slide K ===`, slide text, `--- notes ---`, notes) and `qa/<deck>.json`.

H1 also:
- runs `render_svgs.py` (89 PNGs) and records the bytes;
- runs `npm ci` in the container;
- smoke-tests `build.sh` and `qa.py` against a throwaway three-slide deck in scratch (never in the repo);
- adds `presentation/_shared/png/` to `.gitignore`;
- adds to the root `README.md`:
  - under "What's here": `- **Three decks:** a 100-level GraphQL concepts deck plus Quarkus and Python implementation decks (`presentation/`).`
  - in the Layout table: ``| `presentation/` | The three `.pptx` decks and their builders (concepts, Quarkus, Python). |``

**HV1 checks:**
- `diff` of each copied file against gRPC (only the stated lines differ);
- `cmp` of the assets against the skill;
- lockfile versions;
- `build.sh` and `qa.py` read in full;
- `qa.py` passes the smoke deck and fails seeded failures (missing notes, the word "wave", a code line not in its file, an Overpass typeface), run in scratch;
- `git status` shows no `png/` and no `node_modules/`.

### 2.2 H2: `api-patterns-graphql-100` (concepts; ~77 slides; ≤ 50 figure embeds)

- **Stack-agnostic.** Snippets are wire-level only: SDL from `contracts/schema/shipping/`, GraphQL documents, and JSON from the chapters' "On the wire" blocks. No Java and no Python.
- Header: `"use strict"`, the `_shared` wiring, `OUT = api-patterns-graphql-100-r1.0.pptx`, `REV = "r1.0"`, `pres.title` per §8 D5.
- Cover as gRPC: eyebrow `API PATTERNS & PRACTICES · GRAPHQL · 100`, headline "GraphQL: / the what, the why.", italic summary naming the tracking view and both companion decks, the speaker block, `REV`, the logo.

| # | Section (divider code + title) | Chapters | Slides | Content (figures by basename; code by source) |
|---|---|---|---|---|
| — | Cover, Agenda (`OVERVIEW`) | — | 2 | Agenda: 12 sections in two columns |
| 01 | Why GraphQL, and the decision lens | 1, 2 | 1 + 6 | `01-three-paradigms`, `01-request-path`; code: the first tracking query and its response (`# _docs/01-from-rest-and-rpc-to-graphql.md`, "What a query looks like"); table "Where GraphQL wins and loses" (Ch1); `02-decision-framework` (seven axes); `02-tracking-view-topology` |
| 02 | The schema: SDL and types | 3, 4, 5 | 1 + 6 | `03-type-system-map`; code: `Cargo` and `Node` (`# contracts/schema/shipping/cargo.graphql (excerpt)`); `03-scalar-coercion`; `04-wrapper-matrix`; `04-null-bubbling-walk`; `05-contract-loop` |
| 03 | Execution: resolvers, queries, mutations | 6, 7, 8 | 1 + 5 | `06-request-phases`, `07-resolver-chain`; code: a document with variables, aliases, a fragment and `@include` (from an `examples/07-queries-resolvers` document or Ch7 "On the wire"); `08-mutation-flow`, `08-idempotent-replay` |
| 04 | Errors and partial results | 9 | 1 + 4 | `09-error-taxonomy`, `09-partial-data-errors`; code: a response with `data`, `errors` and `extensions.code` (Ch9 "On the wire"); `09-error-masking` |
| 05 | Schema design and evolution | 10, 11 | 1 + 5 | `10-demand-oriented-schema`, `10-node-identity`, `11-change-classes`; code: `finalArrivalDate @deprecated` beside `finalArrivalTime` (`contracts/schema/shipping/*.graphql`, excerpt); `11-deprecation-lifecycle` |
| 06 | Data fetching at scale | 12, 13 | 1 + 6 | `12-connection-anatomy`, `12-offset-vs-keyset`; code: `cargos(first:, after:)` with `pageInfo` (Ch12 "On the wire"); `13-n-plus-one-fanout`, `13-batched-load`, `13-dataloader-tick` |
| 07 | Performance and safety | 14, 15, 16 | 1 + 6 | `14-limit-pipeline`, `14-cost-accumulation`, `15-apq-handshake`, `15-apq-vs-trusted`, `16-cache-layers`, `16-cache-policy-decision` |
| 08 | Security | 17, 18 | 1 + 4 | `17-hardened-request-path`, `17-public-vs-internal-endpoints`, `18-authorization-layers`, `18-errors-vs-nulls` |
| 09 | Observability and federation | 19, 20 | 1 + 4 | `19-one-endpoint-blind-spot`, `19-span-per-resolver`, `20-subgraph-ownership`, `20-query-plan` |
| 10 | Real time and clients | 21, 22 | 1 + 3 | `21-three-ways-to-push`; table "Choosing a push transport" (subscriptions over WebSocket, GraphQL over SSE, plain SSE, raw WebSockets; Ch21 "Choosing between them"); notes point to the WebSockets site in this series as the next title, in Ch21's wording "the forthcoming WebSockets book"; `22-normalized-cache-update` |
| 11 | Testing and debugging | 23, 24 | 1 + 2 | `23-test-layers`, `24-diagnosis-path` |
| 12 | Running it, and the final project | 25, 26, 27, A | 1 + 4 | `26-compose-to-kubernetes`, `27-final-architecture`, `27-request-defences`; table "The decision axes, run against the whole system" (Ch27 "Decision") |
| A | Appendix | 0, A | 1 + 6 | figures loop: `00-shipping-domain-model`, `00-lab-topology`, `21-event-path`, `A-same-chart-on-openshift`; code: the `Query` type (`contracts/schema/shipping/schema.graphql`, excerpt if > 26 lines); glossary (`addTwoColBullets`, **Term** — one sentence, alphabetical: connection, cursor, DataLoader, entity, fragment, null propagation, persisted document, resolver, selection set, subgraph, supergraph, `userErrors`) |
| — | Closing (`THANK YOU`, "Q&A") | — | 1 | Bullets point to the two implementation decks; Red Hat close (sibling boilerplate) |

Totals: 2 + 12 dividers + 55 body + 7 appendix (incl. divider) + 1 = **77 slides**; 46 + 4 = **50 figure embeds**; 13 dividers. Where a slide uses a table (`addStatusTable` with `colW`, e.g. `[2.60, 3.40, 6.09]`), the error-code vocabulary may replace a Section 04 bullet slide inside the count.

### 2.3 H3: `api-patterns-graphql-quarkus` (~66 slides; ≤ 16 figure embeds)

- Every code line comes from `examples/*/quarkus/**`.
- Cover headline "The Quarkus / implementation."; summary names SmallRye GraphQL on Quarkus, code-first against the canonical SDL.
- Slide 3 is the series map: concepts deck → this deck → Python deck; the versions read from the pom; "one canonical SDL; each stack's exported schema is diffed against it in CI".

| # | Section | Chapters | Slides | Content (sources to mine; confirm every identifier in the file) |
|---|---|---|---|---|
| — | Cover, Agenda, Series map | — | 3 | |
| 01 | Setup and the code-first schema | 0, 3 | 1 + 4 | `00-lab-topology`; `pom.xml` extensions (`quarkus-smallrye-graphql`, `quarkus-opentelemetry`, `quarkus-smallrye-health`; excerpt); `TrackingApi.java` `@GraphQLApi` + `@Query` (Ch3); records to SDL types (`Voyage.java`, `UnLocode.java`) |
| 02 | Nullability and the contract gate | 4, 5 | 1 + 3 | `@NonNull` on record components (Ch4 example); `05-two-direction-diff`; schema export settings from `application.properties` (excerpt; never the `removed-resources` line) |
| 03 | Execution and resolvers | 6, 7 | 1 + 4 | `06-parallel-siblings`; a `Uni`-returning `@Source` field; `Context` and `getExecutionId()` for the request id (Ch6/7); arguments and defaults |
| 04 | Mutations and errors | 8, 9 | 1 + 4 | `@Mutation` with `RegisterHandlingEventInput` (`@Input` record); `RegisterHandlingEventPayload` with `userErrors`; `HandlingStore` idempotency by `idempotencyKey`; `09-error-masking` with `SourceUnavailableException` → `SERVICE_UNAVAILABLE` (the class, not the ServiceLoader wiring) |
| 05 | Schema design and evolution | 10, 11 | 1 + 3 | `Node` interface + `Query.node` dispatch by id prefix; `io.smallrye.graphql.api.Deprecated(reason)` on the record component (the annotation only); `11-deprecation-lifecycle` |
| 06 | Pagination and batching | 12, 13 | 1 + 4 | `CargoConnection`/`CargoEdge`/`PageInfo` records; `Pagination.java` cursor encoding; `13-per-field-vs-per-key`; batched `@Source List<…>` resolver (Ch13) |
| 07 | Cost, persisted documents, caching | 14, 15, 16 | 1 + 5 | `14-limit-pipeline`; `TrackingCostCalculator`/`QueryCost` (excerpt); `15-persisted-document-seam`; `PersistedDocumentRoute.init` router registration (as design); `CachePolicy`/`BulkCache` + `Cache-Control` |
| 08 | Transport security and access control | 17, 18 | 1 + 4 | TLS properties (excerpt); `IntrospectionSwitch` (public vs internal instance); `quarkus-oidc` config (excerpt); operation/object/field rules (`OperatorRoleRequiredException`, `SecurityErrorTranslator`; excerpt) |
| 09 | Observability and federation | 19, 20 | 1 + 4 | `19-telemetry-pipeline`; `Telemetry.java` span attributes (excerpt); federation entity with `@Key` and its batch resolver (`examples/20-federation/quarkus/*`); `20-cross-stack-topology` |
| 10 | Subscriptions and clients | 21, 22 | 1 + 3 | `@Subscription` returning `Multi` (Ch21 `TrackingApi`); `EventsResource` SSE feed; SmallRye typesafe client interface (`examples/22-client-integration/quarkus`) |
| 11 | Testing and debugging | 23, 24 | 1 + 3 | `23-test-layers`; `@QuarkusTest` operation test (`TrackCargoTest.java`, excerpt); `24-dev-vs-prod-surfaces` |
| 12 | Running it | 25, 26, 27, A | 1 + 4 | `Containerfile` (UBI openjdk-25, multi-stage, excerpt); `25-compose-tier-topology`; Helm values for one chart, both stacks (excerpt); `A-in-cluster-build` |
| — | Closing | — | 1 | |
| A | Appendix | — | 1 + 3 | full listings, each `(excerpt)` where any line is excluded: final-project `pom.xml`; final-project `application.properties` (omit any excluded line, marked excerpt); one complete resolver class (`HandlingApi.java` or the final-project `TrackingApi.java`, whichever fits 26 lines at 10 pt) |

Totals: 3 + 12 dividers + 45 body + 1 + 4 appendix (incl. divider) = **65 slides** (band 60–72); about **14 figure embeds**. Section 04: state the Ch13 batch-failure behaviour only if needed, and neutrally ("a failing key fails the batch's future; every edge in it is null with one error per path"). Prefer not to.

### 2.4 H4: `api-patterns-graphql-python` (~66 slides; ≤ 16 figure embeds)

- Every code line comes from `examples/*/python/**`.
- Cover headline "The Python / Strawberry build."; summary names Strawberry on FastAPI, managed with uv.
- Series map as in Quarkus, with the versions from `pyproject.toml`.
- **Same 12 sections and order as Quarkus**, so the two decks map one to one:

| # | Section | Slides | Sources to mine |
|---|---|---|---|
| 01 | Setup and the code-first schema | 1 + 4 | `00-lab-topology`; `pyproject.toml` (excerpt); `app/main.py` (`GraphQLRouter`, `context_getter`); `app/schema.py`/`model.py` `@strawberry.type` |
| 02 | Nullability and the contract gate | 1 + 3 | optional vs required annotations (Ch4); `05-two-direction-diff`; schema export |
| 03 | Execution and resolvers | 1 + 4 | `06-parallel-siblings`; `async def` resolvers; `info.context` (`app/context.py`, `deps.py`); `strawberry.Maybe` arguments |
| 04 | Mutations and errors | 1 + 4 | input type + payload `userErrors` (`registration.py`, `handling.py`); idempotency; `app/errors.py` + `09-error-masking` |
| 05 | Schema design and evolution | 1 + 3 | `Node` + `node` dispatch; `deprecation_reason=`; `11-deprecation-lifecycle` |
| 06 | Pagination and batching | 1 + 4 | `app/pagination.py`; `app/loaders.py` (Strawberry `DataLoader`); `13-dataloader-tick` or `13-per-field-vs-per-key` |
| 07 | Cost, persisted documents, caching | 1 + 5 | `14-limit-pipeline`; `app/limits.py` (validation rules + cost extension; excerpt); `15-persisted-document-seam`; `app/persisted.py`; `app/cache_policy.py` |
| 08 | Transport security and access control | 1 + 4 | uvicorn TLS settings (compose/Containerfile excerpt); introspection control; `app/auth.py` (PyJWT validation); `app/permissions.py`/`access.py` |
| 09 | Observability and federation | 1 + 4 | `19-telemetry-pipeline`; `app/telemetry.py`; Strawberry federation entity (`examples/20-federation/python/*`); `20-cross-stack-topology` |
| 10 | Subscriptions and clients | 1 + 3 | async-generator `Subscription` (Ch21 `schema.py`/`events.py`); SSE feed; `gql` client (`examples/22-client-integration`) |
| 11 | Testing and debugging | 1 + 3 | `23-test-layers`; pytest operation test (`tests/test_operations.py`, excerpt; `conftest.py` fixture); `24-dev-vs-prod-surfaces` |
| 12 | Running it | 1 + 4 | `Containerfile` (UBI python, uv, excerpt); `25-compose-tier-topology`; Helm values; `A-in-cluster-build` |

Plus cover, agenda, series map, closing, and an appendix (divider + 3 full listings: `pyproject.toml`, final-project `app/main.py`, one complete resolver module that fits). **≈ 65 slides, about 14 figure embeds.**

### 2.5 HV2–HV4: per-deck validation (Opus, read-only)

1. Re-run QA steps 1–4 independently. View every contact sheet and every code and table slide at 110 dpi.
2. Read `deck.js` in full:
   - every claim matches the chapter it cites;
   - no plan-sourced content;
   - stack differences are neutral;
   - nothing on the never-quote list.
3. Code fidelity: open each source file for 5 or more code slides, beyond `qa.py`'s line check, and confirm the excerpt is representative and not misleading.
4. Notes: read all of them for voice rules 1–14, the structure (shows → point → chapter) and the 200-character floor.
5. Size, slide band, figure cap, divider count.
6. Findings go back to the executor as a numbered list; at most two repair rounds.

### 2.6 HX: cross-deck pass (Opus, read-only)

- The agenda and section titles of the Quarkus and Python decks match one to one.
- The 100 deck's section names are consistent with the part names.
- Terminology is the same across decks: tracking view, `userErrors`, connection, DataLoader, persisted document, subgraph.
- The series-map claims are accurate.
- Total tracked size: `git ls-files -z presentation | xargs -0 du -cb | tail -1` < 15,000,000 (run after the files are staged by HW, or compute it over the files that would be tracked).

---

## 3. Harness and CI additions

**No CI change in S13** (§8 D9). Neither sibling has a deck job.

- `pages.yml` is unaffected, because `_config.yml` already excludes `presentation/`.
- `contracts.yml` is unaffected; `ci-ok` stays the only required check.
- The repo-wide `node_modules/` ignore already covers `_shared/node_modules/`.
- S14 decides whether to add a `python -I presentation/_shared/qa.py --text-only` step, which needs no Node, to the `site` job. That step would run the planning and content greps and the notes coverage check over the committed `.pptx` files. S14 also decides on `scan.sh --tier ban --fail` (Wave G D10).

---

## 4. Acceptance criteria

**Build and pins**
- `presentation/_shared/package.json` declares `"pptxgenjs": "4.0.1"` exactly.
- `package-lock.json` resolves `pptxgenjs` 4.0.1, `jszip` 3.10.2, `image-size` 1.2.1, `@types/node` 22.20.5 and `https` 1.0.0.
- `npm ci` succeeds in `registry.access.redhat.com/ubi10/nodejs-24:10.2-1791943587`.
- `bash presentation/_shared/build.sh <deck>` exits 0 for all three decks and prints `WROTE …/<deck>-r1.0.pptx slides: N`.
- `presentation/_shared/README.md` records the image tag and the date checked.
- `diff` against gRPC: `deck-helpers.js` differs only in the two `Overpass` lines, the header comment (GraphQL decks), the neutral `newDeck()` default title "API Patterns & Practices: GraphQL" and neutralised REST comments (HV1); `dgen.py`, `build_diagrams.py` and `diagrams.py` are identical; the four assets are `cmp`-identical to the skill's.

**Decks**
- Three files exist: `presentation/api-patterns-graphql-{100,quarkus,python}/api-patterns-graphql-{100,quarkus,python}-r1.0.pptx`, each beside its `deck.js`.
- Slide counts within D1's bands: 100 in 72–84, Quarkus and Python in 60–72.
- `python3 -I presentation/_shared/qa.py <pptx> --band … --figure-cap …` exits 0 for each. That covers:
  - notes on every slide, ≥ 200 characters;
  - the logo on every slide;
  - only the three Red Hat fonts;
  - zero planning-language hits;
  - zero content-rule hits in prose;
  - zero banned sources;
  - every code slide traced to an existing file with all lines present in order;
  - every diagram slide carrying its image;
  - figure embeds within the cap.
- `scan.sh --tier ban` over each deck dir and its `qa/` text dump: 0 hits, or each survivor is an identifier inside a code line, listed with a reason.
- Every figure used is an `assets/diagrams/` basename. `git status` shows no new file under `assets/` or `diagrams/`, and nothing under `presentation/_shared/diagrams/`.
- Rendering: the PDF page count equals the slide count for each deck. Every contact sheet and every code and table slide was viewed by the executor and the validator, as listed in the hand-back.
- Quarkus and Python agendas have the same 12 section titles in the same order.

**Size and repo hygiene**
- `git ls-files -z presentation | xargs -0 du -cb | tail -1` is < **15,000,000**, with a target ≤ 12,600,000. Per deck: 100 ≤ 6.0 MB, Quarkus ≤ 3.0 MB, Python ≤ 3.0 MB.
- `git ls-files presentation | grep -E 'node_modules|/qa/|/png/|\.pdf$'` returns nothing.
- `git diff 59c94fb --stat -- _docs examples assets diagrams contracts scripts .github _config.yml _includes _layouts _parts bibliography.md` is empty.
- The root `README.md` has the decks bullet and Layout row, with no planning language: `grep -nE '\br0[0-9]\b|\bS1[0-4]\b|[Ww]ave [A-H]|_plans' README.md` returns nothing.
- A fresh Jekyll build in `ruby:3.3` is clean, `_site/` has no `presentation/`, and `Gemfile.lock` is reverted if Bundler touched it (Wave G §9).

**Wave**
- On PR #1, every job (all `verify:` jobs, `site`, `k8s-manifests`, `contracts`, `ci-ok`) is green after the last Wave H push.
- PR #1 stays draft and r01 is not merged.
- No compose project or cluster was started.

---

## 5. Risks and detection

| Risk | Detection / mitigation |
|---|---|
| pptxgenjs missing in a fresh sandbox | `build.sh` runs `npm ci` from the lockfile when `node_modules` is absent, then trial-requires `pptxgenjs` before building. HV1 tests this from a clean checkout in scratch. |
| Planning or capstone language in a deck | `qa.py` regex over every slide and note (code included), `scan.sh` over `deck.js` and the text dump, and briefs that forbid `_plans/` as a source. Validators read all notes. |
| Content-rule leakage (defects, workarounds, `ContractSchemaDetails`, masking-provider wiring, bypass wording) | §0 never-quote list; `qa.py` banned-source and content regexes; validators compare each claim against the chapter. |
| Size over 15 MB | Per-deck figure caps and a divider cap of 13; `png/` gitignored; `qa.py` prints bytes; HX totals the tracked files before HW commits. If over: cut appendix figures, then body figures that repeat across decks. |
| Missing PNG yields a slide with no diagram (the helper swallows the error) | `build.sh` pre-checks every referenced name; `qa.py` check 9. |
| Code on a slide drifts from the example | `qa.py` check 8 (file exists; lines verbatim and in order); validator spot-reads 5 or more files per deck. |
| Fallback fonts in figures (cairosvg without Red Hat Text) | Render on the host, which has `redhat-text-fonts` 4.1.0; HV1 views five PNGs at full size. |
| Concurrent builds collide (SELinux `:Z`, LibreOffice profile lock) | `:z` mounts; a per-deck `-env:UserInstallation`; per-deck `qa/` dirs. |
| Code lines overflow or titles wrap badly | Line limits (22 at 11 pt, 26 at 10 pt); contact-sheet review; 110-dpi review of code slides. |
| Notes thin or coaching in tone | 200-character floor in `qa.py`; word ranges in the brief; validators read every note. |
| Stack decks diverge in structure | Fixed 12-section table shared by H3 and H4; HX checks parity. |
| A deck states a version that drifted | Versions are read from the `pom.xml`/`pyproject.toml` at authoring time; the validator re-reads them. |
| `npm audit` reports an advisory in a transitive dependency | H0 records the result. Dev-time only (the decks ship as `.pptx`); report it to the user, and do not override ranges unless an upstream fix exists. |
| A deck needs a figure the site lacks | Stop and ask (D6 note); never draw one. |
| Bundler rewrites `Gemfile.lock` during the Jekyll check | Revert after the build (Wave G §9). |
| CI flake (Maven Central fetch) on the push | Re-run the failed jobs once and record it in HW (Wave F §9). |

---

## 6. Coverage-matrix and plan updates (orchestrator only)

1. `coverage-matrix.md`: no change.
2. `_plans/iteration-plan.md`: S13 → done.
3. `_plans/r01-execution-plan.md` RESUME POINTER: S13 row → done (date, CI sha, slide counts, tracked size); S14 → next. Keep "Do not merge r01 → main until the user clears it."
4. Append **§9 "Wave H findings"** here at HW: engineering notes only.
5. `_plans/domain-glossary.md`: no change.

---

## 7. Binding pitfalls carried forward (every Wave H executor)

- **From Waves A–G (still binding):**
  - Reader-facing text is a tutorial (Wave C §9; rules 13–14).
  - Stack differences are neutral.
  - Books are cited by verified chapter title.
  - Never hand-edit SVG; figures come only from `assets/diagrams/`.
  - Check exit codes directly; never pipe a gate through `tail`.
  - Restate a fact, then check it against the code (Wave G §9).
- **New in Wave H:**
  - **H-1.** Mine `_docs/`, `contracts/` and `examples/` only; `_plans/` is never a source.
  - **H-2.** Every code slide starts with a source header; every other line is verbatim from that file; omitted runs are elision lines; ` (excerpt)` marks any omission.
  - **H-3.** Titles are 2–5-word concept names; claims go in captions; diagram captions start with the book's figure number.
  - **H-4.** Notes on every slide, ≥ 200 characters, in the voice of rules 1–14.
  - **H-5.** Stay within the figure cap and 13 dividers. Bytes are counted per embed.
  - **H-6.** Never run `render_svgs.py`, `npm install` or a `git` command in a deck step.
  - **H-7.** `:z` mounts, a per-deck LibreOffice profile, `TMPDIR` set to scratch.
  - **H-8.** Hand-backs go to the orchestrator in chat; nothing about a suspected defect is written into any file.

---

## 8. Open decisions needing user input (each with a recommendation)

1. **Slide counts.**
   - (a) **100 ≈ 77 (band 72–84), Quarkus ≈ 65 and Python ≈ 65 (band 60–72).** This sits between REST (45/47/46) and gRPC (99/66/68). The 100 deck is below gRPC's because of the size budget.
   - (b) gRPC parity (about 99/66/68) with `png/` untracked; the estimated total is about 14.5 MB, with no headroom.

   **Recommend (a).**
2. **Commit the built `.pptx` files?**
   - (a) **Yes, as both siblings do.** They are the deliverable on GitHub, and the site build excludes `presentation/`.
   - (b) No; build from source only.

   **Recommend (a).**
3. **PDF exports.**
   - (a) **None in git.** PDFs live only in the gitignored `qa/`, as in the siblings; each would add about 3–6 MB.
   - (b) Commit one PDF per deck.

   **Recommend (a).**
4. **Site page or nav link for the decks.**
   - (a) **None.** The siblings have no nav entry or page, and Pages does not publish `presentation/`. The root README gets the decks bullet and Layout row.
   - (b) A `/decks/` page linking to the GitHub blob URLs, as an S13 site change.

   **Recommend (a).**
5. **Deck titles (`pres.title` / cover).**
   - (a) **gRPC pattern:**
     - "API Patterns & Practices: GraphQL — 100 (Concepts)": eyebrow `API PATTERNS & PRACTICES · GRAPHQL · 100`, headline "GraphQL: the what, the why.";
     - "API Patterns & Practices: GraphQL — Quarkus Implementation": headline "The Quarkus implementation.", subtitle naming SmallRye GraphQL;
     - "API Patterns & Practices: GraphQL — Python / Strawberry Implementation": headline "The Python / Strawberry build.".

     Files are `api-patterns-graphql-{100,quarkus,python}-r1.0.pptx`. The README drops gRPC's "201" label, since the titles do not carry it.
   - (b) Name the frameworks in the main titles ("… SmallRye GraphQL on Quarkus").

   **Recommend (a).**
6. **`png/` tracked or generated.**
   - (a) **Generated and gitignored:** `render_svgs.py` rebuilds all 89 in seconds from the committed SVGs. This is the only way to keep the decks within the budget.
   - (b) Track only the PNGs the decks use (about 55, around 4.7 MB). The tracked total is then about 17 MB, over the limit.
   - (c) Track all of them (gRPC parity), about 20 MB.

   **Recommend (a).** If a deck needs a figure the site lacks, the choices are to add it to the site through `lgtm-diagram-generator` (a separate, user-approved site change) or to use `_shared/diagrams.py`. Recommend neither in S13.
7. **Title font.**
   - (a) **Red Hat Display** (SKILL.md, `theme.md`, your rule).
   - (b) Overpass (the skill's script and both siblings).

   **Recommend (a).** It is a two-line diff, recorded in the `_shared` README. Raise the stale `deck-helpers.js` token with the skill owner separately.
8. **Where each tool runs.**
   - (a) **Node (`npm ci`, `node deck.js`) in the pinned UBI Node 24 container. cairosvg (through `uv`, 2.9.1) and the QA renderers (LibreOffice, pdftoppm, ImageMagick) on the host,** because they need the Red Hat fonts the image lacks.
   - (b) Everything in the container, with fonts mounted and LibreOffice installed into a custom image.
   - (c) Everything on the host (sibling practice), but the host has Node 22.

   **Recommend (a).**
9. **A `decks` CI job.**
   - (a) **None in S13** (sibling parity, and Wave G D10 deferred CI gates to S14). At S14, consider a Node-free `qa.py --text-only` step in the `site` job.
   - (b) A full `decks` job (container build plus `qa.py`) now.

   **Recommend (a).**
10. **Commit granularity.**
    - (a) **Five commits** (`_shared`, each deck, wrap), each pushed.
    - (b) One squash commit.

    **Recommend (a)**, matching Waves A–G.
11. **New `_shared` scripts beyond the siblings.**
    - (a) **Add `build.sh` (pinned container) and `qa.py` (stdlib QA).** They make the pins and the acceptance checks reproducible, and S14 can reuse `qa.py`.
    - (b) Commands in the README only, as the siblings do.

    **Recommend (a).**
12. **The cover revision marker `r1.0` and the `-r1.0` file suffix.**
    - (a) **Keep.** The skill's versioning rule requires them, the siblings use them, and the planning-language regex (`r[0-9]{2}`) does not match them.
    - (b) Drop them.

    **Recommend (a).**

### Critical files for implementation
- `/home/rsedor/Dev/api-patterns-and-practices-grpc/presentation/_shared/` (`deck-helpers.js`, `render_svgs.py`, `README.md`, `package.json`, `package-lock.json`): templates to port
- `/home/rsedor/Dev/api-patterns-and-practices-grpc/presentation/api-patterns-grpc-{100,quarkus,python}/deck.js`: structure templates (cover, divider, appendix loop, closing)
- `/home/rsedor/.claude/skills/lgtm-presentation/SKILL.md`, `references/deck-builder.md`, `references/theme.md`; `/home/rsedor/.claude/skills/lgtm-professional-voice/SKILL.md`, `references/surfaces.md`, `scripts/scan.sh`
- `/home/rsedor/Dev/api-patterns-and-practices-graphql/_docs/*.md` (figure captions, "On the wire" blocks), `/home/rsedor/Dev/api-patterns-and-practices-graphql/contracts/schema/shipping/*.graphql`, `/home/rsedor/Dev/api-patterns-and-practices-graphql/examples/*/{quarkus,python}/**`
- `/home/rsedor/Dev/api-patterns-and-practices-graphql/.gitignore`, `/home/rsedor/Dev/api-patterns-and-practices-graphql/README.md`

---

## 9. Wave H findings

- **pptxgenjs `writeFile` on Node does not compress.** Write with `pres.stream({compression:true})` (`writeDeck` in `_shared`).
- **A section image added on every divider is stored every time.** One `defineSlideMaster` background saves about 1.1 MB per 13-divider deck (`defineSectionMaster` / `addSectionDivider({onMaster:true})`).
- **Code on slides is read at build time** (`snippet(src, ranges)`, with the repo mounted read-only into the build container). Elisions are automatic, and `qa.py` fails drift and silent jumps. Hand-copied, cached and generated code each failed review in a different way.
- **The cover eyebrow with the full series name fits at 13 pt with `charSpacing` 3** (measured), not at the skill's 14/6.
- **`image-size` (a declared pptxgenjs dependency that it never loads)** is overridden to 2.0.4 for a clean `npm audit`, with byte-identical output.
- **The Docker-strategy OpenShift build (buildah) leaves `WORKDIR` root-owned**, so both Ch27 build stages run as root. The runtime stages stay non-root.
- **otel-lgtm needs `CAP_DAC_OVERRIDE` to create `/data` as root**, so `lgtm.dropAllCapabilities` is false only on OpenShift.
- **CI retries now back off 60 s then 180 s.** Maven Central "artifact absent" misses cleared within minutes three times.

(Appended at HW.)

---

## 10. Host hygiene and what comes next

- This wave starts no compose project and no cluster. `gql-tracking` and CRC stay Stopped.
- Containers run `--rm`. Scratch holds the LibreOffice profiles, the `scan.sh` temp files, the H0 probe renders and the smoke deck. `qa/` dirs are gitignored and may be deleted after HW.
- Jekyll builds only in `ruby:3.3`, with the bundle dir in scratch; revert `Gemfile.lock` if it changes.
- **S14 (release gate) comes next.** Its full green sweep adds the decks: `qa.py` on all three decks, and the `scan.sh` gate if adopted. The user clears any r01 → `main` merge.
```

### Critical Files for Implementation
- /home/rsedor/Dev/api-patterns-and-practices-grpc/presentation/_shared/deck-helpers.js
- /home/rsedor/Dev/api-patterns-and-practices-grpc/presentation/_shared/render_svgs.py
- /home/rsedor/Dev/api-patterns-and-practices-grpc/presentation/api-patterns-grpc-100/deck.js
- /home/rsedor/.claude/skills/lgtm-presentation/references/deck-builder.md
- /home/rsedor/Dev/api-patterns-and-practices-graphql/_plans/r01-execution-plan.md