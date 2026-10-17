"""Spec for assets/diagrams/13-n-plus-one-fanout.{svg,excalidraw}. Regenerate: python3 -I diagrams/13-n-plus-one-fanout.py

The tree is the four-cargo query of Chapter 12 (cargos(first: 4) with itinerary
legs, voyage, both locations, and delivery). The counts are the ones Chapter 12's
verify.sh asserted on both stacks: listCargos 1, getCargo 4, getItinerary 8,
listEvents 4, getVoyage 4, getLocation 8, total 29. The keys come from the
seed: legs of VWX901, STU678 (both V300A, SGSIN to CNSHA) and DEF456 (V100S,
V200E).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=20, y=50, w=960, h=400, label="Every field fetches for itself: 29 source calls")]
nodes = [
    dict(x=40, y=215, w=150, h=70, style="box", lines=["cargos(first: 4)", "listCargos x1"]),
    dict(x=225, y=215, w=150, h=70, style="box", lines=["CargoEdge.node", "getCargo x4"]),
    dict(x=420, y=130, w=190, h=70, style="box", lines=["Cargo.itinerary", "getItinerary x4"]),
    dict(x=420, y=300, w=190, h=84, style="box", lines=["Cargo.delivery", "getItinerary x4", "listEvents x4"]),
    dict(x=655, y=90, w=160, h=60, style="box", lines=["Leg.voyage", "getVoyage x4"]),
    dict(x=655, y=180, w=160, h=60, style="box", lines=["Leg.loadLocation", "getLocation x4"]),
    dict(x=655, y=270, w=160, h=60, style="box", lines=["Leg.unloadLocation", "getLocation x4"]),
    dict(x=840, y=90, w=125, h=60, style="accent", lines=["V300A, V300A", "V100S, V200E"]),
    dict(x=840, y=180, w=125, h=60, style="accent", lines=["SGSIN, SGSIN", "USNYC, DEHAM"]),
    dict(x=840, y=270, w=125, h=60, style="accent", lines=["CNSHA, CNSHA", "DEHAM, NLRTM"]),
]
edges = [
    dict(x1=190, y1=250, x2=225, y2=250),
    dict(x1=375, y1=240, x2=420, y2=170),
    dict(x1=375, y1=260, x2=420, y2=335),
    dict(x1=610, y1=150, x2=655, y2=120),
    dict(x1=610, y1=170, x2=655, y2=210),
    dict(x1=610, y1=180, x2=655, y2=300),
    dict(x1=815, y1=120, x2=840, y2=120),
    dict(x1=815, y1=210, x2=840, y2=210),
    dict(x1=815, y1=300, x2=840, y2=300),
]
notes = [
    dict(x=500, y=28, text="one call per field occurrence, 1 + 4 + 8 + 4 + 4 + 8 = 29", anchor="middle", bold=True),
    dict(x=40, y=418, text="Highlighted: the same key fetched more than once in one request (V300A twice, SGSIN twice, CNSHA twice, DEHAM once per side, and the itinerary of every cargo twice).", size=12, color="#555555"),
    dict(x=40, y=438, text="Counts are the ones the Chapter 12 example asserted for this query.", size=12, color="#555555"),
]
g.emit("13-n-plus-one-fanout", 1000, 470, bands=bands, nodes=nodes, edges=edges, notes=notes)
