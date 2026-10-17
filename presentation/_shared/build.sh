#!/usr/bin/env bash
# build.sh — build one deck in the pinned Node container.
#
#   bash presentation/_shared/build.sh <deck-dir>
#
# Node (npm ci, node deck.js) runs in the pinned UBI 10 Node 24 image. Figure
# rendering and QA rendering run on the host, which has the Red Hat fonts.
set -euo pipefail

IMG="registry.access.redhat.com/ubi10/nodejs-24:10.2-1791943587@sha256:8f8b90769f48b962ae25b45a77abee4c6a6b025e2dceecceee0eaaa02650dcea"

[ "$#" -eq 1 ] || { echo "usage: build.sh <deck-dir>" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRES="$(dirname "$HERE")"
REPO="$(dirname "$PRES")"
DECK="$(cd "$1" && pwd)"
case "$DECK" in
  "$PRES"/*) ;;
  *) echo "ERROR: $DECK is not under $PRES" >&2; exit 2 ;;
esac
[ -f "$DECK/deck.js" ] || { echo "ERROR: $DECK/deck.js not found" >&2; exit 2; }
REL="${DECK#"$PRES"/}"

UIDGID="$(id -u):$(id -g)"

echo "image: $IMG"

# Install the pinned dependencies when node_modules is absent or unusable.
docker run --rm -u "$UIDGID" -e HOME=/tmp -e npm_config_cache=/tmp/.npm \
  -v "$PRES:/work:z" -w /work/_shared "$IMG" \
  sh -c 'node -e "require(\"pptxgenjs\")" 2>/dev/null || npm ci --no-audit --no-fund; node -e "require(\"pptxgenjs\")"'

# Every figure the deck names must exist as a PNG.
python3 -I - "$DECK/deck.js" "$HERE/png" <<'PY'
import os, re, sys
deck_js, png = sys.argv[1], sys.argv[2]
with open(deck_js, encoding="utf-8") as fh:
    src = fh.read()
repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(deck_js))))
svgs = {f[:-4] for f in os.listdir(os.path.join(repo, "assets", "diagrams")) if f.endswith(".svg")}
names = {n for n in re.findall(r'"([A-Za-z0-9][\w.-]*)"', src) if n in svgs}
missing = sorted(n for n in names if not os.path.isfile(os.path.join(png, n + ".png")))
print(f"figures referenced: {len(names)}")
if missing:
    print("ERROR: missing PNG in _shared/png (run render_svgs.py): " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
PY

docker run --rm -u "$UIDGID" -e HOME=/tmp -e NODE_PATH=/work/_shared/node_modules \
  -e REPO_ROOT=/repo -v "$REPO:/repo:ro,z" -v "$PRES:/work:z" -w "/work/$REL" "$IMG" node deck.js
