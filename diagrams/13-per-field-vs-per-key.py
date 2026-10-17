"""Spec for assets/diagrams/13-per-field-vs-per-key.{svg,excalidraw}. Regenerate: python3 -I diagrams/13-per-field-vs-per-key.py

The location calls of the four-cargo query. The keys are those verify.sh asserts:
Quarkus logs location.getLocations DEHAM+SGSIN+USNYC and CNSHA+DEHAM+NLRTM (two
calls, DEHAM in both); Python logs one call, CNSHA+DEHAM+NLRTM+SGSIN+USNYC.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=470, h=370, label="SmallRye: one loader per field, keyed by the Leg"),
    dict(x=510, y=50, w=470, h=370, label="Strawberry: one loader per kind of key, shared"),
]
nodes = [
    dict(x=45, y=95, w=190, h=56, style="box", lines=["Leg.loadLocation", "loader keyed by Leg"]),
    dict(x=265, y=95, w=200, h=56, style="box", lines=["Leg.unloadLocation", "loader keyed by Leg"]),
    dict(x=45, y=215, w=190, h=70, style="accent", lines=["getLocations", "DEHAM+SGSIN+USNYC"]),
    dict(x=265, y=215, w=200, h=70, style="accent", lines=["getLocations", "CNSHA+DEHAM+NLRTM"]),
    dict(x=45, y=335, w=420, h=56, style="box", lines=["DEHAM travels in both calls", "2 calls for the query"]),
    dict(x=535, y=95, w=190, h=56, style="box", lines=["Leg.loadLocation", "loads by UN/LOCODE"]),
    dict(x=755, y=95, w=200, h=56, style="box", lines=["Leg.unloadLocation", "loads by UN/LOCODE"]),
    dict(x=535, y=215, w=420, h=70, style="accent", lines=["one location loader, keyed by code", "getLocations CNSHA+DEHAM+NLRTM+SGSIN+USNYC"]),
    dict(x=535, y=335, w=420, h=56, style="box", lines=["DEHAM is one key, loaded once", "1 call for the query"]),
]
edges = [
    dict(x1=140, y1=151, x2=140, y2=215),
    dict(x1=365, y1=151, x2=365, y2=215),
    dict(x1=140, y1=285, x2=140, y2=335, dashed=True),
    dict(x1=630, y1=151, x2=680, y2=215),
    dict(x1=855, y1=151, x2=810, y2=215),
    dict(x1=745, y1=285, x2=745, y2=335, dashed=True),
]
notes = [
    dict(x=500, y=28, text="The same query, two batching units: 2 location calls on Quarkus, 1 on Python", anchor="middle", bold=True),
    dict(x=500, y=444, text="Either count is independent of page size. The difference is only whether two fields that want the same thing share a loader.", anchor="middle", size=12, color="#555555"),
]
g.emit("13-per-field-vs-per-key", 1000, 470, bands=bands, nodes=nodes, edges=edges, notes=notes)
