"""Spec for assets/diagrams/02-decision-framework.{svg,excalidraw}. Regenerate: python3 -I diagrams/02-decision-framework.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

axes=[("Client diversity","shape variance"),("Aggregation","across sources"),("Read and write","balance"),("Caching needs","edge and server"),("Contract","and evolution style"),("Operational","and security cost"),("Team ownership","and federation")]
nodes=[];edges=[]
for i,(a,b) in enumerate(axes):
    y=40+i*58
    nodes.append({"x":30,"y":y,"w":240,"h":48,"style":"box","lines":[a,b]})
    edges.append({"x1":270,"y1":y+24,"x2":340,"y2":y+24})
nodes.append({"x":340,"y":40,"w":200,"h":396,"style":"ink","lines":["Run each interaction","through the axes","","Score each axis","Write the reason down","Then choose"]})
outs=[("GraphQL","Customer tracking view","accent",70),("REST","Booking writes","box",160),("gRPC","Internal routing","box",250),("Not GraphQL","Partner bulk feeds","ghost",340)]
for t,s,st,y in outs:
    nodes.append({"x":620,"y":y,"w":250,"h":64,"style":st,"lines":[t,s]})
    edges.append({"x1":540,"y1":y+32,"x2":620,"y2":y+32,"amber":st=="accent","dashed":st=="ghost"})
notes=[{"x":150,"y":28,"text":"Seven axes","anchor":"middle","bold":True},{"x":745,"y":28,"text":"One answer per interaction","anchor":"middle","bold":True}]
g.emit("02-decision-framework",900,460,nodes=nodes,edges=edges,notes=notes)
