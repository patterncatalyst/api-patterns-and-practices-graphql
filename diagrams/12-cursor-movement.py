"""Spec for assets/diagrams/12-cursor-movement.{svg,excalidraw}. Regenerate: python3 -I diagrams/12-cursor-movement.py

Drawn from one real run of the chapter's requests on both stacks (they return the
same bodies): cargos(first: 2) three times, each after the previous endCursor,
then cargos(last: 2, before: <cursor of ABC123>). The cursor tails are the last
eight characters of the cursors the run returned, recomputed here from the
documented plaintext cargo|v1|<bookedAt>|<trackingId>. The hasNext/hasPrev values
are the ones verify.sh asserts.
"""
import base64
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")


def tail(booked_at, tracking_id):
    plain = f"cargo|v1|{booked_at}|{tracking_id}".encode()
    return base64.urlsafe_b64encode(plain).rstrip(b"=").decode()[-8:]


CARGOS = [  # the booking index, newest first
    ("VWX901", "2026-09-29T09:00:00Z"),
    ("XYZ789", "2026-09-28T09:00:00Z"),
    ("STU678", "2026-09-27T09:00:00Z"),
    ("DEF456", "2026-09-26T09:00:00Z"),
    ("ABC123", "2026-09-25T09:00:00Z"),
    ("GHI345", "2026-09-24T09:00:00Z"),
]
X0, W, GAP = 45, 140, 14


def x_of(i):
    return X0 + i * (W + GAP)


bands = [
    dict(x=20, y=50, w=960, h=110, label="the booking index, newest booking first"),
    dict(x=20, y=190, w=960, h=140, label="forward: first: 2, each page after the previous endCursor"),
    dict(x=20, y=360, w=960, h=140, label="backward: last: 2, before: the cursor of ABC123"),
]
nodes = []
for i, (tid, booked) in enumerate(CARGOS):
    nodes.append(dict(x=x_of(i), y=84, w=W, h=62, style="box", lines=[tid, "booked " + booked[5:10], "cursor ..." + tail(booked, tid)]))

page_specs = [
    (0, "page 1: VWX901, XYZ789", "hasNext true, hasPrev false"),
    (2, "page 2: STU678, DEF456", "hasNext true, hasPrev true"),
    (4, "page 3: ABC123, GHI345", "hasNext false, hasPrev true"),
]
for start, title, flags in page_specs:
    nodes.append(dict(x=x_of(start) + 5, y=228, w=2 * W + GAP - 70, h=62, style="accent", lines=[title, flags]))
edges = [
    dict(x1=x_of(1) + W - 65, y1=259, x2=x_of(2) + 5, y2=259, amber=True, label="endCursor", lx=0, ly=-8),
    dict(x1=x_of(3) + W - 65, y1=259, x2=x_of(4) + 5, y2=259, amber=True, label="endCursor", lx=0, ly=-8),
]
nodes.append(dict(x=x_of(2), y=398, w=2 * W + GAP, h=62, style="accent", lines=["STU678, DEF456", "hasNext true, hasPrev true"]))
edges.append(dict(x1=x_of(4) + 10, y1=146, x2=x_of(3) + W - 60, y2=398, amber=True, label="before = cursor of ABC123", lx=60, ly=75))
notes = [
    dict(x=500, y=28, text="Three pages forward, one page backward: the cursors are positions in the index, not page numbers", anchor="middle", bold=True),
    dict(x=500, y=522, text="Backward results keep connection order (newest first). Both flags are computed from the index, not approximated.", anchor="middle", size=12, color="#555555"),
]
g.emit("12-cursor-movement", 1000, 540, bands=bands, nodes=nodes, edges=edges, notes=notes)
