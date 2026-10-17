"""Spec for assets/diagrams/11-change-classes.{svg,excalidraw}. Regenerate: python3 -I diagrams/11-change-classes.py

Every change line is the text graphql-inspector printed for the fixture of the
same name in examples/11-evolution/verify.sh; every gate result is the exit code
that fixture asserted.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

X = (20, 400, 780)  # column x
bands = [
    dict(x=X[0], y=20, w=360, h=400, label="Safe (✔): clients keep working"),
    dict(x=X[1], y=20, w=360, h=400, label="Dangerous (⚠): a client may break"),
    dict(x=X[2], y=20, w=360, h=400, label="Breaking (✖): a client breaks"),
    dict(x=20, y=532, w=1120, h=118, label="Nullability runs the other way for inputs"),
]


def column(i, style, items):
    return [dict(x=X[i] + 20, y=56 + 70 * k, w=320, h=58, style=style, lines=list(it)) for k, it in enumerate(items)]


nodes = []
nodes += column(0, "box", [
    ("Add a field", "Field timeZone was added to object type Location"),
    ("Add an optional input field", "operatorId: String on RegisterHandlingEventInput"),
    ("Tighten an output", "Cargo.itinerary: Itinerary to Itinerary!"),
    ("Deprecate a field", "Itinerary.finalArrivalDate is deprecated"),
    ("Loosen an input", "completionTime: DateTime! to DateTime"),
])
nodes += column(1, "box", [
    ("Add an enum value", "TRANSSHIP added to HandlingEventType"),
    ("Add an optional argument", "destination: UnLocode added to Query.cargos"),
    ("Add a union member", "Voyage added to union SearchResult"),
    ("Implement an interface", "Leg object implements Node interface"),
])
nodes += column(2, "box", [
    ("Remove a field", "Field unloadTime was removed from object type Leg"),
    ("Loosen an output", "Cargo.trackingId: TrackingId! to TrackingId"),
    ("Require an input", "operatorId: String! added to the input"),
    ("Remove an enum value", "UNKNOWN removed from TransportStatus"),
    ("Remove a deprecated field", "finalArrivalDate (deprecated) was removed"),
])
nodes += [
    dict(x=40, y=432, w=320, h=84, style="accent", lines=["Gate result", "default: exit 0", "dangerousBreaking: exit 0"]),
    dict(x=420, y=432, w=320, h=84, style="accent", lines=["Gate result", "default: exit 0, ::warning on the pull request", "dangerousBreaking: exit 1"]),
    dict(x=800, y=432, w=320, h=84, style="accent", lines=["Gate result", "default: exit 1", "suppressRemovalOfDeprecatedField: exit 0 for", "the deprecated removal, shown as ⚠"]),
    dict(x=40, y=562, w=262, h=66, style="box", lines=["Output tightened: ✔", "Itinerary to Itinerary!"]),
    dict(x=310, y=562, w=262, h=66, style="box", lines=["Output loosened: ✖", "TrackingId! to TrackingId"]),
    dict(x=580, y=562, w=262, h=66, style="box", lines=["Input tightened: ✖", "voyageNumber: String to String!"]),
    dict(x=850, y=562, w=262, h=66, style="box", lines=["Input loosened: ✔", "DateTime! to DateTime"]),
]
notes = [dict(x=20, y=672, text="Classes are from the point of view of a client of the old schema. The strict mode is BREAKING_RULES=dangerousBreaking.", size=12, color="#555555")]
g.emit("11-change-classes", 1160, 690, bands=bands, nodes=nodes, notes=notes)
