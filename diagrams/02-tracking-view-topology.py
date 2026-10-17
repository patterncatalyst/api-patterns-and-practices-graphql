"""Spec for assets/diagrams/02-tracking-view-topology.{svg,excalidraw}. Regenerate: python3 -I diagrams/02-tracking-view-topology.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes=[
 {"x":30,"y":130,"w":170,"h":90,"style":"user","lines":["Web and mobile","clients"]},
 {"x":30,"y":330,"w":170,"h":60,"style":"ghost","lines":["Partner bulk feeds","nightly batch"]},
 {"x":340,"y":140,"w":210,"h":140,"style":"accent","lines":["Tracking view","GraphQL at /graphql","reads: cargo, itinerary,","delivery, handling history"]},
 {"x":680,"y":40,"w":190,"h":70,"style":"box","lines":["Booking service","REST"]},
 {"x":680,"y":170,"w":190,"h":70,"style":"box","lines":["Routing service","gRPC"]},
 {"x":680,"y":300,"w":190,"h":70,"style":"box","lines":["Handling event store","history and delivery"]},
]
edges=[
 {"x1":200,"y1":175,"x2":340,"y2":175,"amber":True,"label":"GraphQL query","ly":-8},
 {"x1":200,"y1":135,"x2":680,"y2":65,"label":"writes: POST /cargos","lx":-40,"ly":-10},
 {"x1":550,"y1":160,"x2":680,"y2":95,"label":"REST","lx":-17,"ly":-5.5,"elx":-27,"ely":-3.5},
 {"x1":550,"y1":205,"x2":680,"y2":205,"label":"gRPC","ly":-8},
 {"x1":550,"y1":255,"x2":680,"y2":320,"label":"read","lx":27,"ly":-2.5,"elx":17,"ely":-0.5},
 {"x1":200,"y1":365,"x2":680,"y2":350,"dashed":True,"label":"bulk feed, not GraphQL","ly":-10},
]
g.emit("02-tracking-view-topology",900,420,nodes=nodes,edges=edges,notes=[])
