"""Spec for assets/diagrams/00-lab-topology.{svg,excalidraw}. Regenerate: python3 -I diagrams/00-lab-topology.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands=[
 {"x":235,"y":40,"w":425,"h":430,"label":"Docker Compose project gql-ch00-prereq","fill":"#fafafa"},
]
nodes=[
 {"x":30,"y":70,"w":170,"h":70,"style":"user","lines":["verify.sh","examples/00-prerequisites"]},
 {"x":30,"y":200,"w":170,"h":70,"style":"box","lines":["lib.sh","examples/_lib"]},
 {"x":265,"y":80,"w":365,"h":95,"style":"box","lines":["quarkus","SmallRye GraphQL, code-first","host :8080  /graphql  /q/health"]},
 {"x":265,"y":225,"w":365,"h":70,"style":"ghost","lines":["otel-lgtm  (compose.observability.yaml)","Grafana :3000  OTLP :4317"]},
 {"x":265,"y":345,"w":365,"h":95,"style":"box","lines":["python","Strawberry on FastAPI, code-first","host :8081  /graphql  /health"]},
 {"x":725,"y":70,"w":230,"h":90,"style":"accent","lines":["contracts/schema/","shipping/*.graphql","canonical SDL"]},
 {"x":725,"y":225,"w":230,"h":80,"style":"user","lines":["graphql-inspector","run by assert_sdl_conforms"]},
]
edges=[
 {"x1":115,"y1":140,"x2":115,"y2":200,"label":"sources","lx":28,"ly":0},
 {"x1":200,"y1":220,"x2":265,"y2":140,"amber":True,"label":"POST","lx":-22,"ly":-6,"elx":-36},
 {"x1":200,"y1":250,"x2":265,"y2":390,"amber":True,"label":"POST","lx":-22,"ly":10,"elx":-36},
 {"x1":725,"y1":250,"x2":630,"y2":140,"label":"introspect","lx":32,"ly":-8,"elx":8},
 {"x1":725,"y1":282,"x2":630,"y2":395,"label":"introspect","lx":32,"ly":8,"elx":18},
 {"x1":840,"y1":225,"x2":840,"y2":160,"label":"diff both ways","lx":-62,"ly":0},
 {"x1":447,"y1":175,"x2":447,"y2":225,"dashed":True,"label":"OTLP","lx":28,"ly":0},
 {"x1":447,"y1":345,"x2":447,"y2":295,"dashed":True,"label":"OTLP","lx":28,"ly":0},
]
notes=[
 {"x":30,"y":495,"text":"verify.sh starts the project, drives both stacks through lib.sh and tears it down. Port 8080 is Quarkus, 8081 is Python.","size":12,"color":"#555555"},
]
g.emit("00-lab-topology",990,520,bands=bands,nodes=nodes,edges=edges,notes=notes)
