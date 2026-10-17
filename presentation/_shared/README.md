# Shared deck scaffold — API Patterns & Practices: GraphQL

One Red Hat house-style scaffold, reused by all three decks in this series:

| Deck dir | What it is |
|---|---|
| `../api-patterns-graphql-100/` | 100-level **concepts**: the what and why of GraphQL, stack-agnostic |
| `../api-patterns-graphql-quarkus/` | **Quarkus** (SmallRye GraphQL) implementation of the same patterns |
| `../api-patterns-graphql-python/` | **Python / Strawberry** implementation of the same patterns |

## What lives here

- `deck-helpers.js`: the Red Hat deck helper library (`COLOR`, `FONT`, `W`, `H`, `addContentTitle`, `addBullets`, `addTwoColBullets`, `addStatusTable`, `addCodeSlide`, `addDiagramSlide`, `addSectionDivider`, `addFooter`, `addNotes`). Extend it; do not rewrite it. It matches the `lgtm-presentation` skill's copy except that titles use Red Hat Display.
- `render_svgs.py`: renders the book's 89 figures (`../../assets/diagrams/*.svg`) to PNG at 1400 px width into `png/`. Basenames match the figure names, so `addDiagramSlide(s, eyebrow, title, "<basename>", caption)` embeds by basename.
- `build.sh`: builds one deck in the pinned Node container.
- `qa.py`: structural QA of a built `.pptx`, standard library only.
- `dgen.py`, `diagrams.py`, `build_diagrams.py`: the Scene diagram engine, kept as a fallback for a figure the book does not have. Unused by the three decks.
- `assets/`: brand assets (cover panel, section panel, Red Hat logos).
- `package.json`, `package-lock.json`: `pptxgenjs` 4.0.1, pinned exactly.
  `pptxgenjs` never loads `image-size`; the `overrides` entry pins it to 2.0.4 so `npm audit --omit=dev` reports no vulnerabilities.
- `png/`: generated figures. Never commit it; it is in `.gitignore`.
- `node_modules/`: installed by `npm ci`; ignored.

## Series helpers

| Helper | Use |
|---|---|
| `defineSectionMaster(pres)` | Defines the `SECTION` slide master whose background is `section-panel.png`, so the panel is stored once per deck. Call once after `newDeck()`. |
| `addSectionDivider(slide, code, title, subtitle, { onMaster: true })` | With `onMaster`, skips the panel image; create the slide with `pres.addSlide({ masterName: "SECTION" })`. Without the option the divider is unchanged. |
| `writeDeck(pres, out)` | Writes the deflated package (`pres.stream({ compression: true })`) and prints `WROTE <out> slides: N`. Returns a promise. |
| `snippetLines(snip)` | Builds code-slide lines from a snippet: the source header first, then the snippet lines. |
| `addSnippetSlide(slide, eyebrow, title, lang, snip, caption, opts)` | `addCodeSlide` fed by a snippet. |

`addCodeSlide` colours lines that start with `#`, `//` or `<!--` green, so every source header renders green.

### Snippets

A deck keeps only specs; `snippet.js` reads the lines from the repository at build time, so a slide cannot drift from its source.

```js
const { snippet } = require(`${SHARED}/snippet.js`);
const cargo = snippet("examples/13-dataloaders/quarkus/src/main/java/com/patterncatalyst/shipping/tracking/Cargo.java",
  [[15, 18], [27, 33]]);
addSnippetSlide(s, "SCHEMA", "The Cargo record", "java · SmallRye GraphQL", cargo, caption, { fontSize: 11 });
```

| Function | Behaviour |
|---|---|
| `extract(src, ranges, opts)` | Returns the lines. `src` is repo-relative; `ranges` is `[[from, to], ...]`, 1-based, inclusive, ascending. Non-adjacent ranges are joined by one elision line in the file's comment style (`# ...` for py, yaml, toml, sh, properties, graphql and Containerfile; `// ...` for java, js and ts; `<!-- ... -->` for xml and html; `...` for json and md). Throws when a range is outside the file or out of order. `opts.dedent` (default true) strips the common indentation; `opts.elision` overrides the elision text. |
| `snippet(src, ranges, opts)` | Returns `{ src, lines, excerpt, tag }`. `excerpt` is true when more than one range is given or the single range is not the whole file. `opts.tag` adds a header tag such as `On the wire`. |
| `snippetLines(snip)` / `addSnippetSlide(...)` | In `deck-helpers.js`. The green header comes from `src`, with ` (excerpt)` added when `excerpt` is true. |

`build.sh` mounts the repository root read-only at `/repo` (`REPO_ROOT=/repo`) next to the writable `presentation/` mount, so the build reads `examples/`, `contracts/` and `_docs/`. A host build resolves the root two levels above `_shared`.

`qa.py` stays as a guard: it checks every code line against `src`, and fails when the lines of an excerpt jump over source lines with no elision line between them. Blank source lines between two lines are tolerated.

### Cover eyebrow

The series rule for every cover eyebrow: text `API PATTERNS & PRACTICES · GRAPHQL · {100|QUARKUS|PYTHON}`, `fontFace: FONT.title`, `fontSize: 13`, bold, `COLOR.red`, `charSpacing: 3`, `x: 6.00, y: 1.82, w: 6.90, h: 0.34`, left-aligned, middle. This fits on one line in all three decks.

## Fonts

Titles use Red Hat Display, body text Red Hat Text and code Red Hat Mono (SIL Open Font License). Install the three families (`redhat-display-fonts`, `redhat-text-fonts`, `redhat-mono-fonts` on Fedora) to view the decks as designed. The figures name Red Hat Text, so render them on a host that has it.

## Build

Figures, once, on the host:

```bash
cd presentation/_shared
uv run --no-project --with cairosvg==2.9.1 python -I render_svgs.py
```

A deck, in the container `registry.access.redhat.com/ubi10/nodejs-24:10.2-1791943587` (checked 2026-10-17):

```bash
bash presentation/_shared/build.sh presentation/<deck-dir>
```

`build.sh` runs `npm ci` when `node_modules` is missing, confirms that `pptxgenjs` loads, checks that every figure the deck names exists in `png/`, and runs `node deck.js`. A deck's `deck.js` sets the asset paths before requiring the helpers:

```js
const path = require("path");
const SHARED = path.resolve(__dirname, "../_shared");
process.env.DECK_ASSETS = `${SHARED}/assets`;
process.env.DECK_PNG   = `${SHARED}/png`;
const H = require(`${SHARED}/deck-helpers.js`);
```

## QA

```bash
python3 -I presentation/_shared/qa.py presentation/<deck-dir>/<deck>.pptx --band 72-84 --figure-cap 46
```

`qa.py` checks, and exits 1 on any failure:

- the slide count against `--band`;
- speaker notes of at least 200 characters on every slide;
- the Red Hat logo on every slide;
- only the three Red Hat typefaces;
- planning language and the content rule in slide text and notes;
- banned sources;
- code slides: the first line names a source file that exists, and every other line appears in it in order (contiguous unless the header says `(excerpt)`);
- figure embeds against `--figure-cap`, and the file size against `--max-bytes`.

It writes `qa/<deck>.txt` and `qa/<deck>.json` beside the deck. Render for review with LibreOffice and `pdftoppm`, using a separate `-env:UserInstallation` profile per deck, and view every contact sheet.

## Size

The tracked `presentation/` tree stays under 15 MB. `png/` is generated and never committed. Each figure embed costs about its PNG size (about 91 KB on average), so every deck has a figure cap and at most 13 dividers.
