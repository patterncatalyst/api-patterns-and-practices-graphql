"""Spec for assets/diagrams/13-dataloader-tick.{svg,excalidraw}. Regenerate: python3 -I diagrams/13-dataloader-tick.py

Drawn from one real run of the four-cargo query on the Python stack, request
22ff1540-33dd-49c6-983f-11ce85bd91a0 in the source-call log of
GET /debug/source-calls (startMs/endMs shifted so listCargos starts at 0):
  listCargos 0-252, getCargos 252-503, getItineraries 503-754,
  listEventsFor 503-754, getVoyages 755-1006, getLocations 755-1006.
The small ticks before each bar are the load() calls the level enqueued during
one event-loop turn (4 cargos, 8 itinerary loads for 4 keys, 4 events, 4
voyages for 3 keys, 8 locations for 5 keys). The ghost lane is Chapter 12's four
getCargo calls for the cargo level: the same wall time, four calls. Ghost bars
are placed at the cargo level's interval, not measured.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

X0, SCALE = 200, 0.76


def bar(label, start, end, y, style="accent"):
    return dict(x=round(X0 + start * SCALE), y=y, w=round((end - start) * SCALE), h=30, style=style, lines=[label])


def ticks(count, start, y):
    """count load() ticks ending just before the bar that starts at 'start' ms."""
    x_end = round(X0 + start * SCALE) - 6
    return [dict(x=x_end - 7 * (count - i), y=y + 4, w=3, h=22, style="sub", lines=[""]) for i in range(count)]


bands = [
    dict(x=20, y=50, w=960, h=44, label="page"),
    dict(x=20, y=100, w=960, h=44, label="cargos"),
    dict(x=20, y=150, w=960, h=88, label="itinerary, delivery"),
    dict(x=20, y=244, w=960, h=88, label="voyage, location"),
    dict(x=20, y=352, w=960, h=170, label="Chapter 12 cargos", fill="#ffffff"),
]
nodes = []
for t in (0, 250, 500, 750, 1000):
    nodes.append(dict(x=round(X0 + t * SCALE), y=46, w=1, h=480, style="sub", lines=[""]))
nodes += [
    bar("listCargos", 0, 252, 57),
    bar("getCargos (4 keys)", 252, 503, 107),
    bar("getItineraries (4 keys)", 503, 754, 158),
    bar("listEventsFor (4 keys)", 503, 754, 198),
    bar("getVoyages (3 keys)", 755, 1006, 252),
    bar("getLocations (5 keys)", 755, 1006, 292),
]
nodes += ticks(4, 252, 107) + ticks(8, 503, 158) + ticks(4, 503, 198) + ticks(4, 755, 252) + ticks(8, 755, 292)
for i, name in enumerate(("DEF456", "STU678", "VWX901", "XYZ789")):
    nodes.append(bar("getCargo " + name, 252, 503, 362 + 36 * i, "ghost"))
edges = []
notes = [dict(x=round(X0 + t * SCALE), y=544, text=f"{t} ms", anchor="middle", size=11, color="#555555") for t in (0, 250, 500, 750, 1000)]
notes += [
    dict(x=500, y=28, text="One tick per batch: the loads queue, one dispatch, one bulk call, then the calls that depend on it", anchor="middle", bold=True),
    dict(x=500, y=566, text="Solid bars: source-call log of one Python run of the four-cargo query. Thin ticks: load() calls queued before the dispatch.", anchor="middle", size=12, color="#555555"),
    dict(x=500, y=584, text="Ghost bars, not measured: the four getCargo calls Chapter 12 made, drawn at the cargo level's interval. Four calls instead of one.", anchor="middle", size=12, color="#555555"),
]
g.emit("13-dataloader-tick", 1000, 600, bands=bands, nodes=nodes, edges=edges, notes=notes)
