// snippet.js — code-slide source extraction. A deck keeps only specs (path,
// ranges, font size); the lines are read from the repository at build time, so
// a slide cannot drift from its source and an omission is always visible.
//
//   const { extract, snippet } = require(`${SHARED}/snippet.js`);
//   const snip = snippet("examples/13-dataloaders/python/app/loaders.py", [[1, 12], [30, 41]]);
//   addSnippetSlide(s, eyebrow, title, lang, snip, caption, { fontSize: 11 });
//
// The repository root is $REPO_ROOT (set to /repo by build.sh in the container)
// or, on the host, two levels above this file.

"use strict";

const fs = require("fs");
const path = require("path");

const REPO = process.env.REPO_ROOT || path.resolve(__dirname, "../..");

const SLASH = ["java", "js", "mjs", "ts", "kt", "go"];
const HASH = ["py", "yaml", "yml", "toml", "sh", "properties", "graphql", "gql", "conf", "env"];
const MARKUP = ["xml", "html"];
const PLAIN = ["json", "md", "txt"];

function elisionFor(src) {
  const base = path.basename(src);
  if (base === "Containerfile" || base === "Dockerfile") return "# ...";
  const ext = (base.match(/\.([A-Za-z0-9]+)$/) || [])[1] || "";
  if (SLASH.includes(ext)) return "// ...";
  if (HASH.includes(ext)) return "# ...";
  if (MARKUP.includes(ext)) return "<!-- ... -->";
  if (PLAIN.includes(ext)) return "...";
  throw new Error(`snippet: no elision style for ${src}; pass opts.elision`);
}

function readLines(src) {
  const file = path.join(REPO, src);
  if (!fs.existsSync(file)) throw new Error(`snippet: ${src} not found under ${REPO}`);
  const lines = fs.readFileSync(file, "utf8").split("\n");
  if (lines.length && lines[lines.length - 1] === "") lines.pop();
  return lines;
}

function indentOf(l) { return l.match(/^[ \t]*/)[0].length; }

// extract(src, ranges, opts) -> array of lines.
//   ranges: [[from, to], ...], 1-based, inclusive, ascending, not overlapping.
//   Non-adjacent ranges are joined by one elision line in the file's comment
//   style. opts.dedent (default true) strips the common indentation;
//   opts.elision overrides the elision text.
function extract(src, ranges, opts = {}) {
  const all = readLines(src);
  if (!Array.isArray(ranges) || ranges.length === 0) throw new Error(`snippet: ${src} needs at least one range`);
  let prevTo = 0;
  const parts = ranges.map(([from, to]) => {
    if (!Number.isInteger(from) || !Number.isInteger(to) || from < 1 || to < from || to > all.length) {
      throw new Error(`snippet: range [${from}, ${to}] is outside ${src} (1-${all.length})`);
    }
    if (from <= prevTo) throw new Error(`snippet: range [${from}, ${to}] of ${src} overlaps or precedes the previous range`);
    prevTo = to;
    return { from, to, lines: all.slice(from - 1, to) };
  });
  const body = parts.flatMap((p) => p.lines).filter((l) => l.trim() !== "");
  const cut = opts.dedent === false || body.length === 0 ? 0 : Math.min(...body.map(indentOf));
  const strip = (l) => (l.trim() === "" ? "" : l.slice(cut));
  const elision = opts.elision || (parts.length > 1 ? elisionFor(src) : "");
  const out = [];
  parts.forEach((p, i) => {
    if (i > 0 && p.from > parts[i - 1].to + 1) {
      const first = p.lines.find((l) => l.trim() !== "") || "";
      out.push(" ".repeat(Math.max(0, indentOf(first) - cut)) + elision);
    }
    p.lines.forEach((l) => out.push(strip(l)));
  });
  return out;
}

// snippet(src, ranges, opts) -> { src, lines, excerpt, tag } for addSnippetSlide.
// excerpt is true when more than one range is given or the single range is not
// the whole file. opts.tag adds a header tag such as "On the wire".
function snippet(src, ranges, opts = {}) {
  const total = readLines(src).length;
  const lines = extract(src, ranges, opts);
  const whole = ranges.length === 1 && ranges[0][0] === 1 && ranges[0][1] === total;
  return { src, lines, excerpt: !whole, tag: opts.tag };
}

module.exports = { extract, snippet, REPO };
