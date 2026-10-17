"""Spec for assets/diagrams/01-request-path.{svg,excalidraw}. Regenerate: python3 -I diagrams/01-request-path.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes=[
 {"x":30,"y":55,"w":140,"h":70,"style":"user","lines":["Client","web or mobile"]},
 {"x":205,"y":55,"w":155,"h":70,"style":"box","lines":["POST /graphql","query + variables"]},
 {"x":410,"y":65,"w":150,"h":50,"style":"box","lines":["1  Parse","text to syntax tree"]},
 {"x":410,"y":140,"w":150,"h":50,"style":"box","lines":["2  Validate","check against schema"]},
 {"x":410,"y":215,"w":150,"h":50,"style":"accent","lines":["3  Execute","walk the selection set"]},
 {"x":410,"y":290,"w":150,"h":60,"style":"accent","lines":["4  Resolvers","one function per field"]},
 {"x":30,"y":285,"w":150,"h":70,"style":"ink","lines":["One JSON response","data and errors"]},
 {"x":650,"y":190,"w":220,"h":60,"style":"sub","lines":["Cargo service","REST"]},
 {"x":650,"y":270,"w":220,"h":60,"style":"sub","lines":["Routing service","gRPC"]},
 {"x":650,"y":350,"w":220,"h":60,"style":"sub","lines":["Handling event store","history and delivery"]},
]
edges=[
 {"x1":170,"y1":90,"x2":205,"y2":90},
 {"x1":360,"y1":90,"x2":410,"y2":90,"amber":True},
 {"x1":485,"y1":115,"x2":485,"y2":140},
 {"x1":485,"y1":190,"x2":485,"y2":215},
 {"x1":485,"y1":265,"x2":485,"y2":290},
 {"x1":560,"y1":320,"x2":650,"y2":220,"label":"calls","lx":-8,"ly":-14},
 {"x1":560,"y1":320,"x2":650,"y2":300},
 {"x1":560,"y1":330,"x2":650,"y2":380},
 {"x1":410,"y1":320,"x2":180,"y2":320,"amber":True,"label":"results","ly":-8},
 {"x1":105,"y1":285,"x2":105,"y2":125,"amber":True,"label":"HTTP response","lx":-30,"elx":-21.7},
]
bands=[{"x":390,"y":35,"w":190,"h":340,"label":"GraphQL server","fill":"#fafafa"}]
notes=[{"x":450,"y":20,"text":"One endpoint, one request, one response","anchor":"middle","bold":True,"size":12}]
g.emit("01-request-path",900,430,bands=bands,nodes=nodes,edges=edges,notes=notes)
