"""Spec for assets/diagrams/04-wrapper-matrix.{svg,excalidraw}. Regenerate: python3 -I diagrams/04-wrapper-matrix.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

# Columns: SDL wrapper, what the response may hold, the Java spelling, the Python spelling.
COLS = [(20, 120), (150, 330), (490, 270), (770, 270)]
ROW_Y = [74, 138, 202, 266, 330, 394]
H = 52
# (wrapper, field in the tracking view or "", allowed, java, python, highlighted)
rows = [
    ("T", "Leg.voyage", "an object, or null", "T (no annotation)", "T | None", True),
    ("T!", "Leg.loadLocation", "an object", "@NonNull T", "T", True),
    ("[T]", "", "null; [] ; [null, object, ...]", "List<T>", "list[T | None] | None", False),
    ("[T!]", "", "null; [] ; [object, ...]", "List<@NonNull T>", "list[T] | None", False),
    ("[T]!", "", "[] ; [null, object, ...]", "@NonNull List<T>", "list[T | None]", False),
    ("[T!]!", "Itinerary.legs", "[] ; [object, ...]", "@NonNull List<@NonNull T>", "list[T]", True),
]
nodes = []
for y, (wrapper, field, allowed, java, python, hot) in zip(ROW_Y, rows):
    style = "accent" if hot else "box"
    nodes.append(dict(x=COLS[0][0], y=y, w=COLS[0][1], h=H, style=style, lines=[wrapper, field] if field else [wrapper]))
    nodes.append(dict(x=COLS[1][0], y=y, w=COLS[1][1], h=H, style=style, lines=[allowed]))
    nodes.append(dict(x=COLS[2][0], y=y, w=COLS[2][1], h=H, style=style, lines=[java]))
    nodes.append(dict(x=COLS[3][0], y=y, w=COLS[3][1], h=H, style=style, lines=[python]))
notes = [
    dict(x=80, y=60, text="SDL type", anchor="middle", bold=True),
    dict(x=315, y=60, text="Allowed in the response", anchor="middle", bold=True),
    dict(x=625, y=60, text="Quarkus (SmallRye)", anchor="middle", bold=True),
    dict(x=905, y=60, text="Python (Strawberry)", anchor="middle", bold=True),
    dict(x=20, y=30, text="Six wrapper combinations for any type T, read inside-out", bold=True, size=14),
    dict(x=530, y=476, text="Highlighted rows are the three the tracking view uses: Leg.voyage, Leg.loadLocation and Itinerary.legs.", anchor="middle", size=12, color="#555555"),
]
g.emit("04-wrapper-matrix", 1060, 500, nodes=nodes, notes=notes)
