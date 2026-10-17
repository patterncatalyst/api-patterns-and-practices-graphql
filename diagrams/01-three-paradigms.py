"""Spec for assets/diagrams/01-three-paradigms.{svg,excalidraw}. Regenerate: python3 -I diagrams/01-three-paradigms.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

cols=[("REST","resources and verbs",30,"box",False),("gRPC","typed methods",320,"box",False),("GraphQL","one graph, one selection",610,"accent",True)]
# Everything is drawn DY lower and the canvas is DY taller, so the title
# at y=10 clears the top edge (no negative viewBox).
DY=12
nodes=[];bands=[];edges=[];notes=[]
rows=[
 [["Mental model","Nouns and verbs","GET /cargos/ABC123"],["Mental model","Typed calls between services","GetItinerary, ListEvents"],["Mental model","Traverse a typed graph","cargo { delivery itinerary }"]],
 [["Call shape","Several GETs, one per resource","/cargos/{id}, /itinerary, /events"],["Call shape","Generated stubs, binary HTTP/2","One call per owning service"],["Call shape","One POST to /graphql","query + variables in the JSON body"]],
 [["Result","Fixed representations","Over- and under-fetching"],["Result","Fixed response messages","Needs a proxy in a browser"],["Result","JSON shaped like the query","One round trip for the screen"]],
]
for ci,(t,sub,x,st,hl) in enumerate(cols):
    bands.append({"x":x-10,"y":20+DY,"w":280,"h":470,"label":"","fill":"#fff8ef" if hl else "#fafafa"})
    notes.append({"x":x+130,"y":50+DY,"text":t,"anchor":"middle","bold":True,"size":18})
    notes.append({"x":x+130,"y":70+DY,"text":sub,"anchor":"middle","size":12,"color":"#555555"})
    for ri,r in enumerate(rows):
        nodes.append({"x":x,"y":95+ri*130+DY,"w":260,"h":105,"style":"accent" if hl else "box","lines":r[ci]})
        if ri<2: edges.append({"x1":x+130,"y1":200+ri*130+DY,"x2":x+130,"y2":225+ri*130+DY})
notes.append({"x":450,"y":10+DY,"text":"Intent: show the state and remaining route of cargo ABC123","anchor":"middle","bold":True,"size":13})
g.emit("01-three-paradigms",900,510+DY,bands=bands,nodes=nodes,edges=edges,notes=notes)
