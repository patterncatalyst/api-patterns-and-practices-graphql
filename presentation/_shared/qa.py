#!/usr/bin/env python3
"""qa.py — structural QA for a built deck (.pptx). Standard library only.

    python3 -I presentation/_shared/qa.py <deck>.pptx [options]

Options
    --band LO-HI       required slide count range
    --figure-cap N     maximum number of figure embeds
    --max-bytes N      maximum size of the .pptx
    --repo-root DIR    root for code-slide source paths (default: two levels
                       above this file's directory)
    --out-dir DIR      where the text dump goes (default: <pptx dir>/qa)
    --text-only        text checks only: notes, fonts, planning language,
                       content rule, banned sources, code fidelity. No media
                       checks and no dump.

Exit status is 1 when any check fails. Every finding is one line:
    FAIL <check> slide K: ...
    WARN <check> slide K: ...
"""
import argparse
import hashlib
import json
import os
import posixpath
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
}
A = "{%s}" % NS["a"]
P = "{%s}" % NS["p"]

HERE = os.path.dirname(os.path.abspath(__file__))
ASSET_DIR = os.path.join(HERE, "assets")
LOGO_FILES = ("logo-candidate-2.png", "redhat-logo-white.png")
PANEL_FILES = ("cover-panel.png", "section-panel.png")

FONTS_OK = {"Red Hat Display", "Red Hat Text", "Red Hat Mono"}
NOTES_MIN = 200
TITLE_PREFIX = "API Patterns & Practices: GraphQL"

PLANNING_RE = re.compile(
    r"\b(capstone|roadmap|iterations?|waves?|coverage|r[0-9]{2}|S[0-9]{1,2}[a-z]?"
    r"|r[0-9]+\.[0-9]+|phase [0-9]+|milestone|sprint|backlog|TODO|TBD|FIXME|_plans|execution plan)\b",
    re.I)
CONTENT_RE = re.compile(
    r"\b(workarounds?|work around|bugs?|defects?|limitations?|upstream|issue ?#?[0-9]+"
    r"|reproducers?|vulnerab\w*|exploit\w*|attack\w*|bypass\w*|CVE-[0-9-]+"
    r"|leak\w*|broken|violat\w*|deviat\w*)\b|(?<!\w)#[0-9]{3,}\b",
    re.I)
BANNED_RE = re.compile(
    r"ContractSchemaDetails|removed-resources|smallrye-graphql#|ErrorExtensionProvider\b")
HEADER_RE = re.compile(
    r"^(//|#|<!--)\s*(\S+?)( \(excerpt\)| \(On the wire\)| \(On the wire, excerpt\))?\s*(-->)?$")
ELISION = {"...", "// ...", "# ...", "<!-- ... -->"}

findings = []


def fail(check, slide, msg):
    findings.append(("FAIL", check, slide, msg))


def warn(check, slide, msg):
    findings.append(("WARN", check, slide, msg))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def slide_num(name):
    return int(re.search(r"(\d+)\.xml$", name).group(1))


def rels_of(z, part):
    """Return {rId: (type_suffix, resolved_target)} for a part."""
    d, b = posixpath.split(part)
    rp = posixpath.join(d, "_rels", b + ".rels")
    out = {}
    if rp not in z.namelist():
        return out
    root = ET.fromstring(z.read(rp))
    for r in root:
        t = r.get("Type", "").rsplit("/", 1)[-1]
        tgt = r.get("Target", "")
        if r.get("TargetMode") != "External":
            tgt = posixpath.normpath(posixpath.join(d, tgt)) if not tgt.startswith("/") else tgt.lstrip("/")
        out[r.get("Id")] = (t, tgt)
    return out


def para_lines(p):
    """Text of one a:p, split on a:br, slide-number fields dropped."""
    lines = [""]
    for el in p:
        if el.tag == A + "r":
            t = el.find(A + "t")
            parts = ((t.text or "") if t is not None else "").split("\n")
            lines[-1] += parts[0]
            lines.extend(parts[1:])
        elif el.tag == A + "br":
            lines.append("")
        elif el.tag == A + "fld":
            if el.get("type", "").startswith("slidenum"):
                continue
            t = el.find(A + "t")
            lines[-1] += (t.text or "") if t is not None else ""
    return lines


def shape_is_placeholder(sp, kind):
    ph = sp.find("p:nvSpPr/p:nvPr/p:ph", NS)
    return ph is not None and ph.get("type") == kind


def shape_lines(sp):
    out = []
    for p in sp.iter(A + "p"):
        out.extend(para_lines(p))
    return out


def shape_uses_mono(sp):
    for el in sp.iter(A + "latin"):
        if el.get("typeface") == "Red Hat Mono":
            return True
    return False


def xfrm(sp):
    off = sp.find("p:spPr/a:xfrm/a:off", NS)
    ext = sp.find("p:spPr/a:xfrm/a:ext", NS)
    if off is None or ext is None:
        return None
    return (int(off.get("x")), int(off.get("y")), int(ext.get("cx")), int(ext.get("cy")))


def analyse_slide(root):
    """Return (prose_lines, code_shapes) for a slide tree.

    code_shapes: list of line lists, one per text shape set in Red Hat Mono and
    placed inside a 151515-filled rectangle.
    """
    dark = []
    for sp in root.iter(P + "sp"):
        clr = sp.find("p:spPr/a:solidFill/a:srgbClr", NS)
        if clr is not None and clr.get("val", "").upper() == "151515":
            box = xfrm(sp)
            if box:
                dark.append(box)
    prose, code = [], []
    for sp in root.iter(P + "sp"):
        lines = shape_lines(sp)
        if not any(l.strip() for l in lines):
            continue
        box = xfrm(sp)
        inside = False
        if box and dark and shape_uses_mono(sp):
            for dx, dy, dw, dh in dark:
                if dx <= box[0] <= dx + dw and dy <= box[1] <= dy + dh:
                    inside = True
        (code if inside else prose).append(lines if inside else lines)
    prose_lines = [l for ls in prose for l in ls]
    for gf in root.iter(P + "graphicFrame"):
        for p in gf.iter(A + "p"):
            prose_lines.extend(para_lines(p))
    return prose_lines, code


def notes_text(z, notes_part):
    root = ET.fromstring(z.read(notes_part))
    chunks = []
    for sp in root.iter(P + "sp"):
        if shape_is_placeholder(sp, "sldNum") or shape_is_placeholder(sp, "sldImg"):
            continue
        chunks.extend(shape_lines(sp))
    return "\n".join(chunks).strip()


def check_code(si, code_shapes, repo_root):
    for lines in code_shapes:
        lines = [l.rstrip() for l in lines]
        nonblank = [l for l in lines if l.strip()]
        if not nonblank:
            continue
        m = HEADER_RE.match(nonblank[0].strip())
        if not m:
            fail("code", si, "first code line is not a source header: %r" % nonblank[0][:80])
            continue
        rel, tag = m.group(2), (m.group(3) or "")
        path = os.path.join(repo_root, rel)
        if not os.path.isfile(path):
            fail("code", si, "source file not found: %s" % rel)
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = [l.strip() for l in fh.read().splitlines()]
        excerpt = "excerpt" in tag
        body = [l.strip() for l in nonblank[1:]]
        if not body:
            continue
        has_elision = any(l in ELISION for l in body)
        if has_elision and not excerpt:
            fail("code", si, "elision line without (excerpt) in header of %s" % rel)
        # Split the body at elision lines. Each segment must be contiguous in
        # the source (blank source lines tolerated); segments follow in order.
        segments, cur = [], []
        for l in body:
            if l in ELISION:
                if cur:
                    segments.append(cur)
                cur = []
            else:
                cur.append(l)
        if cur:
            segments.append(cur)

        def match_at(seg, start):
            j = start
            for l in seg:
                while j < len(src) and src[j] == "":
                    j += 1
                if j >= len(src) or src[j] != l:
                    return None
                j += 1
            return j

        pos = 0
        for n, seg in enumerate(segments):
            end = None
            for k in range(pos, len(src)):
                if src[k] == seg[0]:
                    end = match_at(seg, k)
                    if end is not None:
                        break
            if end is None:
                missing = next((l for l in seg if l not in src[pos:]), None)
                if missing is not None:
                    fail("code", si, "line not in %s (or out of order): %r" % (rel, missing[:80]))
                elif excerpt:
                    fail("code", si, "lines of %s jump over source lines with no elision line between them: %r"
                         % (rel, seg[0][:60]))
                else:
                    fail("code", si, "lines of %s are not contiguous but the header lacks (excerpt)" % rel)
                break
            pos = end


def main():
    ap = argparse.ArgumentParser(description="Structural QA for a deck.")
    ap.add_argument("pptx")
    ap.add_argument("--band")
    ap.add_argument("--figure-cap", type=int)
    ap.add_argument("--max-bytes", type=int)
    ap.add_argument("--repo-root", default=os.path.normpath(os.path.join(HERE, "..", "..")))
    ap.add_argument("--out-dir")
    ap.add_argument("--text-only", action="store_true")
    args = ap.parse_args()
    with zipfile.ZipFile(args.pptx) as z:
        return run(args, z)


def run(args, z):
    names = z.namelist()
    slide_parts = sorted((n for n in names if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)), key=slide_num)
    count = len(slide_parts)
    print("slides: %d" % count)

    if args.band:
        lo, hi = (int(x) for x in args.band.split("-"))
        if not lo <= count <= hi:
            fail("band", 0, "%d slides outside %d-%d" % (count, lo, hi))

    asset_hash = {}
    for f in LOGO_FILES + PANEL_FILES:
        with open(os.path.join(ASSET_DIR, f), "rb") as fh:
            asset_hash[sha(fh.read())] = f
    logo_hash = {h for h, f in asset_hash.items() if f in LOGO_FILES}

    facts, dump = [], []
    fig_embeds = 0
    fig_parts = set()
    all_media = set()
    for part in slide_parts:
        si = slide_num(part)
        root = ET.fromstring(z.read(part))
        raw = z.read(part).decode("utf-8")
        rels = rels_of(z, part)

        # notes
        notes_part = next((t for (ty, t) in rels.values() if ty == "notesSlide"), None)
        notes = notes_text(z, notes_part) if notes_part else ""
        ncollapsed = re.sub(r"\s+", " ", notes).strip()
        if len(ncollapsed) < NOTES_MIN:
            fail("notes", si, "speaker notes %d characters, need %d" % (len(ncollapsed), NOTES_MIN))

        # fonts
        faces = set(re.findall(r'typeface="([^"]*)"', raw))
        bad = sorted(f for f in faces if f not in FONTS_OK)
        if bad:
            fail("fonts", si, "typeface outside the Red Hat set: %s" % ", ".join(bad))

        prose, code_shapes = analyse_slide(root)
        code_lines = [l for ls in code_shapes for l in ls]
        slide_text = "\n".join(prose + code_lines)

        # planning language: slide text, code and notes
        for label, text in (("slide", slide_text), ("notes", notes)):
            for m in PLANNING_RE.finditer(text):
                fail("planning", si, "%s text has %r" % (label, m.group(0)))

        # content rule: prose fails, code warns
        for label, text in (("slide", "\n".join(prose)), ("notes", notes)):
            for m in CONTENT_RE.finditer(text):
                fail("content", si, "%s prose has %r" % (label, m.group(0)))
        for l in code_lines:
            for m in CONTENT_RE.finditer(l):
                warn("content", si, "code line has %r: %s" % (m.group(0), l.strip()[:80]))

        # banned sources
        for label, text in (("slide", slide_text), ("notes", notes)):
            for m in BANNED_RE.finditer(text):
                fail("banned", si, "%s text has %r" % (label, m.group(0)))

        # code fidelity
        check_code(si, code_shapes, args.repo_root)

        # media
        media = [t for (ty, t) in rels.values() if ty == "image"]
        hashes = [sha(z.read(t)) for t in media]
        has_logo = any(h in logo_hash for h in hashes)
        figs = [t for t, h in zip(media, hashes, strict=True) if h not in asset_hash]
        if not args.text_only:
            if not has_logo:
                fail("logo", si, "no Red Hat logo image on the slide")
            fig_embeds += len(figs)
            fig_parts.update(figs)
        all_media.update(media)

        title = next((l.strip() for l in prose if l.strip()), "")
        facts.append({
            "slide": si, "text_start": title[:80], "notes_chars": len(ncollapsed),
            "logo": has_logo, "figures": len(figs), "code_blocks": len(code_shapes),
            "code_lines": len(code_lines),
        })
        dump.append("=== slide %d ===\n%s\n--- notes ---\n%s\n" % (si, "\n".join(prose + code_lines), notes))

    core = "docProps/core.xml"
    title = ""
    if core in names:
        t = ET.fromstring(z.read(core)).find("{http://purl.org/dc/elements/1.1/}title")
        title = (t.text or "") if t is not None else ""
    if not title.startswith(TITLE_PREFIX):
        fail("title", 0, "document title %r does not start with %r" % (title, TITLE_PREFIX))

    size = os.path.getsize(args.pptx)
    print("pptx bytes: %d" % size)
    if args.max_bytes and size > args.max_bytes:
        fail("size", 0, "%d bytes exceeds %d" % (size, args.max_bytes))

    if not args.text_only:
        print("figure embeds: %d" % fig_embeds)
        if len(fig_parts) != fig_embeds:
            fail("figures", 0, "%d figure embeds but %d distinct figure media parts" % (fig_embeds, len(fig_parts)))
        if args.figure_cap is not None and fig_embeds > args.figure_cap:
            fail("figures", 0, "%d figure embeds exceed the cap of %d" % (fig_embeds, args.figure_cap))
        deck_js = os.path.join(os.path.dirname(os.path.abspath(args.pptx)), "deck.js")
        if os.path.isfile(deck_js):
            with open(deck_js, encoding="utf-8") as fh:
                src = fh.read()
            literal = re.findall(
                r'addDiagramSlide\(\s*\w+\s*,\s*"[^"]*"\s*,\s*"[^"]*"\s*,\s*"[^"]+"', src)
            loops = len(re.findall(r'\bfile:\s*"[^"]+"', src))
            if fig_embeds < len(literal) + loops:
                fail("figures", 0, "deck.js names %d figures but the deck embeds %d" % (len(literal) + loops, fig_embeds))
        # slides that carry a divider panel or cover are not figure slides: nothing further.

        out_dir = args.out_dir or os.path.join(os.path.dirname(os.path.abspath(args.pptx)), "qa")
        os.makedirs(out_dir, exist_ok=True)
        stem = os.path.splitext(os.path.basename(args.pptx))[0]
        with open(os.path.join(out_dir, stem + ".txt"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(dump))
        with open(os.path.join(out_dir, stem + ".json"), "w", encoding="utf-8") as fh:
            json.dump({"pptx": os.path.basename(args.pptx), "slides": count, "bytes": size,
                       "figure_embeds": fig_embeds, "per_slide": facts}, fh, indent=2)

    fails = 0
    for level, check, slide, msg in findings:
        where = "slide %d" % slide if slide else "deck"
        print("%s %s %s: %s" % (level, check, where, msg))
        if level == "FAIL":
            fails += 1
    if fails:
        print("QA FAILED: %d finding(s)" % fails)
        return 1
    print("QA OK (%d warning(s))" % sum(1 for f in findings if f[0] == "WARN"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
