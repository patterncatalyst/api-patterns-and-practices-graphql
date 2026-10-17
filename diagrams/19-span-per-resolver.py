"""Spec for assets/diagrams/19-span-per-resolver.{svg,excalidraw}. Regenerate: python3 -I diagrams/19-span-per-resolver.py

Drawn from one run of the four-cargo FanOut query on the Python stack, trace id
6874a98f5edc8bc82c21db924b595684, read back from Tempo (times in ms from the
start of the HTTP span):
  POST /graphql 0-1011; GraphQL Query: FanOut 2-1010
  cargos x1 4-255 and source.call listCargos 4-255
  node x4 255-506 and source.call getCargos 255-506
  itinerary x4 507-758, delivery x4 507-759, source.call getItineraries 507-758
  and listEventsFor 507-758
  voyage x4, loadLocation x4, unloadLocation x4 758-1010, source.call
  getVoyages 759-1010 and getLocations 759-1010
Twenty-five resolver spans and six source.call spans; each source.call is one
bar under the resolvers it serves. The Quarkus trace has the same 25 resolver
spans and eight source.call spans (Chapter 13's 8 against 6).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

X0, SCALE = 230, 0.72


def bar(label, start, end, y, style="accent", h=28):
    return dict(x=round(X0 + start * SCALE), y=y, w=max(round((end - start) * SCALE), 3), h=h, style=style, lines=[label])


bands = [
    dict(x=20, y=50, w=960, h=70, label="request"),
    dict(x=20, y=126, w=960, h=64, label="level 1: Query.cargos"),
    dict(x=20, y=196, w=960, h=76, label="level 2: CargoEdge.node"),
    dict(x=20, y=278, w=960, h=130, label="level 3: Cargo.itinerary, Cargo.delivery"),
    dict(x=20, y=414, w=960, h=172, label="level 4: Leg.voyage, loadLocation, unloadLocation"),
]
nodes = []
for t in (0, 250, 500, 750, 1000):
    nodes.append(dict(x=round(X0 + t * SCALE), y=46, w=1, h=550, style="sub", lines=[""]))
nodes += [
    bar("POST /graphql", 0, 1011, 56, "box"),
    bar("GraphQL Query: FanOut", 2, 1010, 86, "ink"),
    bar("cargos (1)", 4, 255, 132, h=24),
    bar("source.call listCargos", 4, 255, 160, "box", 24),
    bar("node (4)", 255, 506, 202),
    bar("source.call getCargos", 255, 506, 234, "box", 28),
    bar("itinerary (4)", 507, 758, 284),
    bar("delivery (4)", 507, 759, 315),
    bar("source.call getItineraries", 507, 758, 346, "box", 24),
    bar("source.call listEventsFor", 507, 758, 374, "box", 24),
    bar("voyage (4)", 758, 1010, 420),
    bar("loadLocation (4)", 758, 1010, 450),
    bar("unloadLocation (4)", 758, 1010, 480),
    bar("source.call getVoyages", 759, 1010, 514, "box", 24),
    bar("source.call getLocations", 759, 1010, 542, "box", 24),
]
edges = []
notes = [dict(x=round(X0 + t * SCALE), y=608, text=f"{t} ms", anchor="middle", size=11, color="#555555") for t in (0, 250, 500, 750, 1000)]
notes += [
    dict(x=500, y=28, text="Twenty-five resolver spans overlap in four levels; each batch is one source.call that serves all of them", anchor="middle", bold=True),
    dict(x=500, y=630, text="Spans of one Python run of FanOut, read from Tempo by the trace id the script sent. Counts in brackets are resolver spans. Eight location resolvers, one getLocations span.", anchor="middle", size=12, color="#555555"),
]
g.emit("19-span-per-resolver", 1000, 648, bands=bands, nodes=nodes, edges=edges, notes=notes)
