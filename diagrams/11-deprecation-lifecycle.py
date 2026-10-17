"""Spec for assets/diagrams/11-deprecation-lifecycle.{svg,excalidraw}. Regenerate: python3 -I diagrams/11-deprecation-lifecycle.py

The gate lines are the output of graphql-inspector, run by contracts/scripts/breaking.sh
on the fixtures of examples/11-evolution/verify.sh: real-change (steps 1 and 2,
which ran as one gate run) and remove-deprecated (step 4, with and without
suppressRemovalOfDeprecatedField). Step 3 has no schema change and so no gate line.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

X = (30, 330, 630, 930)  # step columns, 260 wide
bands = [
    dict(x=20, y=20, w=1160, h=130, label="The change"),
    dict(x=20, y=170, w=1160, h=140, label="What the gate prints"),
    dict(x=20, y=330, w=1160, h=140, label="What clients see"),
]
nodes = [
    dict(x=X[0], y=56, w=260, h=80, style="accent", lines=["1. Add the replacement", "finalArrivalTime: DateTime!", "served beside the old field"]),
    dict(x=X[1], y=56, w=260, h=80, style="accent", lines=["2. Deprecate with a reason", "@deprecated(reason:", "\"Use `finalArrivalTime`.\")"]),
    dict(x=X[2], y=56, w=260, h=80, style="box", lines=["3. Observe usage", "operation telemetry", "until no caller selects the old field"]),
    dict(x=X[3], y=56, w=260, h=80, style="accent", lines=["4. Remove with a sign-off", "finalArrivalDate deleted", "from the schema"]),

    dict(x=X[0], y=206, w=260, h=90, style="box", lines=["✔  Field finalArrivalTime was", "added to object type Itinerary", "exit 0"]),
    dict(x=X[1], y=206, w=260, h=90, style="box", lines=["✔  Field Itinerary.finalArrivalDate", "is deprecated", "exit 0"]),
    dict(x=X[2], y=206, w=260, h=90, style="ghost", lines=["no schema change", "nothing for the gate to print"]),
    dict(x=X[3], y=206, w=260, h=90, style="accent", lines=["✖  Field finalArrivalDate (deprecated)", "was removed from object type Itinerary", "exit 1; with the sign-off rule: ⚠, exit 0"]),

    dict(x=X[0], y=366, w=260, h=90, style="box", lines=["Existing clients", "are unchanged", "new clients can adopt the new name"]),
    dict(x=X[1], y=366, w=260, h=90, style="box", lines=["Both fields execute", "and return the same instant;", "fields hides the old one by default"]),
    dict(x=X[2], y=366, w=260, h=90, style="box", lines=["Clients migrate", "on their own schedule", "(telemetry: Chapter 19)"]),
    dict(x=X[3], y=366, w=260, h=90, style="box", lines=["A client that still selects", "the old field fails validation", "so removal is a decision"]),
]
edges = [dict(x1=X[i] + 260, y1=96, x2=X[i + 1], y2=96, amber=True) for i in range(3)]
notes = [dict(x=20, y=494, text="Steps 1 and 2 shipped as one change in this chapter's example. The gate reports them together.", size=12, color="#555555")]
g.emit("11-deprecation-lifecycle", 1200, 512, bands=bands, nodes=nodes, edges=edges, notes=notes)
