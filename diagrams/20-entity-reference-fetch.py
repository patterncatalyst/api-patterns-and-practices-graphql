"""Spec for assets/diagrams/20-entity-reference-fetch.{svg,excalidraw}. Regenerate: python3 -I diagrams/20-entity-reference-fetch.py

Drawn from one run of examples/20-federation/verify.sh: DEF456's seven events name
seven locations, three of them distinct. The handling subgraph returns references,
the gateway sends them as representations in one `_entities` request, and the cargo
subgraph resolves them with one bulk call, location.getLocations:DEHAM+NLRTM+USNYC.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=20, y=50, w=960, h=380, label="From a reference to a resolved entity")]
nodes = [
    dict(x=40, y=90, w=210, h=100, style="box", lines=["handling subgraph", "HandlingEvent.location", "returns Location { unLocode }", "seven events, seven references"]),
    dict(x=300, y=85, w=250, h=110, style="user", lines=["gateway", "one _entities request:", "{__typename: \"Location\",", " unLocode: \"DEHAM\"}, ...", "to the cargo subgraph"]),
    dict(x=600, y=90, w=190, h=100, style="accent", lines=["cargo subgraph", "@Resolver locationByUnLocode", "resolve_reference + DataLoader", "one call for every key"]),
    dict(x=600, y=250, w=190, h=70, style="accent", lines=["location.getLocations", "DEHAM+NLRTM+USNYC"]),
    dict(x=300, y=250, w=250, h=70, style="user", lines=["gateway", "merges each name into its event"]),
    dict(x=40, y=250, w=210, h=70, style="box", lines=["client", "location { name } on every event"]),
    dict(x=820, y=90, w=140, h=100, style="ghost", lines=["resolvable: false", "handling has no", "entity resolver", "for Location"]),
]
edges = [
    dict(x1=250, y1=140, x2=300, y2=140, label="reference", lx=0, ly=-10),
    dict(x1=550, y1=140, x2=600, y2=140, amber=True, label="entities", lx=0, ly=-10),
    dict(x1=695, y1=190, x2=695, y2=250, amber=True, label="sorted, distinct", lx=48, ly=0),
    dict(x1=600, y1=285, x2=550, y2=285, label="names", lx=0, ly=-10),
    dict(x1=300, y1=285, x2=250, y2=285, label="response", lx=0, ly=-10),
]
notes = [
    dict(x=500, y=28, text="A reference costs the cargo subgraph one bulk call, not one call per event", anchor="middle", bold=True),
    dict(x=40, y=370, text="The same shape on both stacks: SmallRye hands the resolver the list of keys (federation.batch-resolving-enabled);", size=12, color="#555555"),
    dict(x=40, y=388, text="Strawberry calls resolve_reference once per representation and a request-scoped DataLoader batches them.", size=12, color="#555555"),
]
g.emit("20-entity-reference-fetch", 1000, 450, bands=bands, nodes=nodes, edges=edges, notes=notes)
