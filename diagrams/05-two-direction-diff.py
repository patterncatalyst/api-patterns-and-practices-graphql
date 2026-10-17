"""Spec for assets/diagrams/05-two-direction-diff.{svg,excalidraw}. Regenerate: python3 -I diagrams/05-two-direction-diff.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=20, w=540, h=420, label="live to canonical: does the stack expose more, or tighter?"),
    dict(x=580, y=20, w=540, h=420, label="canonical to live: does what the stack serves differ?"),
]
nodes = [
    # left panel
    dict(x=40, y=60, w=190, h=70, style="box", lines=["Extra field", "weightKg: Float on Cargo"]),
    dict(x=260, y=60, w=280, h=70, style="accent", lines=["FAIL: breaking", "Field weightKg was removed from", "object type Cargo"]),
    dict(x=40, y=150, w=190, h=70, style="box", lines=["Tightened output", "itinerary: Itinerary!"]),
    dict(x=260, y=150, w=280, h=70, style="accent", lines=["FAIL: breaking", "Field Cargo.itinerary changed type", "from Itinerary! to Itinerary"]),
    dict(x=40, y=240, w=190, h=70, style="box", lines=["Slice", "HandlingEvent not served"]),
    dict(x=260, y=240, w=280, h=70, style="box", lines=["Safe, ignored", "Type HandlingEvent was added"]),
    # right panel
    dict(x=600, y=60, w=190, h=60, style="box", lines=["Slice", "HandlingEvent not served"]),
    dict(x=820, y=60, w=280, h=60, style="ghost", lines=["Allowed: slice removal", "Type HandlingEvent was removed"]),
    dict(x=600, y=135, w=190, h=60, style="box", lines=["Loosened output", "trackingId: TrackingId"]),
    dict(x=820, y=135, w=280, h=60, style="accent", lines=["FAIL: drift", "Field Cargo.trackingId changed", "type from TrackingId! to TrackingId"]),
    dict(x=600, y=210, w=190, h=60, style="box", lines=["Enum value removed", "UNKNOWN"]),
    dict(x=820, y=210, w=280, h=60, style="accent", lines=["FAIL: drift", "Enum value UNKNOWN was removed", "from enum TransportStatus"]),
    dict(x=600, y=285, w=190, h=60, style="box", lines=["Description changed", "Tracking id."]),
    dict(x=820, y=285, w=280, h=60, style="accent", lines=["FAIL: drift, though marked safe", "Field Cargo.trackingId description", "changed from The public ..."]),
]
edges = [
    dict(x1=230, y1=95, x2=260, y2=95, amber=True),
    dict(x1=230, y1=185, x2=260, y2=185, amber=True),
    dict(x1=230, y1=275, x2=260, y2=275, dashed=True),
    dict(x1=790, y1=90, x2=820, y2=90, dashed=True),
    dict(x1=790, y1=165, x2=820, y2=165, amber=True),
    dict(x1=790, y1=240, x2=820, y2=240, amber=True),
    dict(x1=790, y1=315, x2=820, y2=315, amber=True),
]
notes = [
    dict(x=40, y=345, text="Reported by the live-to-canonical diff only:", size=12, color="#555555"),
    dict(x=40, y=363, text="the opposite diff lists a tighter output as safe (a check mark).", size=12, color="#555555"),
    dict(x=40, y=395, text="One direction would pass a tightened field.", size=12, bold=True),
    dict(x=600, y=370, text="Reported by the canonical-to-live diff only: a loosened type, a missing", size=12, color="#555555"),
    dict(x=600, y=388, text="enum value or argument, a changed description.", size=12, color="#555555"),
    dict(x=600, y=420, text="Only whole types, output fields and roots may be absent.", size=12, bold=True),
]
g.emit("05-two-direction-diff", 1140, 460, bands=bands, nodes=nodes, edges=edges, notes=notes)
