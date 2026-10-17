"""Spec for assets/diagrams/13-batched-load.{svg,excalidraw}. Regenerate: python3 -I diagrams/13-batched-load.py

The same query as 13-n-plus-one-fanout, with one bulk call per level. The keys are
the ones the Python stack logged (and verify.sh asserts) for it: six calls. The
side note gives the Quarkus total of eight (a second getItineraries for
Cargo.delivery, a second getLocations for the unload side).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=20, y=50, w=960, h=380, label="One bulk call per level: 6 source calls on Python")]
nodes = [
    dict(x=40, y=190, w=150, h=70, style="box", lines=["listCargos", "key *"]),
    dict(x=225, y=190, w=150, h=70, style="accent", lines=["getCargos", "4 keys"]),
    dict(x=420, y=110, w=190, h=70, style="accent", lines=["getItineraries", "4 keys"]),
    dict(x=420, y=270, w=190, h=70, style="accent", lines=["listEventsFor", "4 keys"]),
    dict(x=655, y=110, w=160, h=70, style="accent", lines=["getVoyages", "V100S+V200E+V300A"]),
    dict(x=655, y=230, w=160, h=84, style="accent", lines=["getLocations", "CNSHA+DEHAM+NLRTM", "+SGSIN+USNYC"]),
    dict(x=840, y=110, w=125, h=70, style="ghost", lines=["Quarkus:", "one call per field"]),
]
edges = [
    dict(x1=190, y1=225, x2=225, y2=225),
    dict(x1=375, y1=215, x2=420, y2=145),
    dict(x1=375, y1=235, x2=420, y2=305),
    dict(x1=610, y1=145, x2=655, y2=145),
    dict(x1=610, y1=170, x2=655, y2=250),
]
notes = [
    dict(x=500, y=28, text="A call starts after the call its keys come from; calls on the same tick run together", anchor="middle", bold=True),
    dict(x=40, y=350, text="The four-key calls carry DEF456+STU678+VWX901+XYZ789: the cargos of the page, sorted, joined with +.", size=12, color="#555555"),
    dict(x=40, y=380, text="Quarkus makes 8 calls for the same query: Cargo.itinerary and Cargo.delivery each have a loader, so getItineraries runs twice,", size=12, color="#555555"),
    dict(x=40, y=398, text="and loadLocation and unloadLocation each have one, so getLocations runs twice (DEHAM+SGSIN+USNYC and CNSHA+DEHAM+NLRTM).", size=12, color="#555555"),
    dict(x=40, y=416, text="Both counts are constant in page size.", size=12, color="#555555"),
]
g.emit("13-batched-load", 1000, 450, bands=bands, nodes=nodes, edges=edges, notes=notes)
