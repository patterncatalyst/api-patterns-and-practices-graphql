"""Spec for assets/diagrams/00-shipping-domain-model.{svg,excalidraw}. Regenerate: python3 -I diagrams/00-shipping-domain-model.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands=[
 {"x":20,"y":40,"w":310,"h":275,"label":"Cargo service (REST)","fill":"#fafafa"},
 {"x":350,"y":40,"w":320,"h":275,"label":"Routing service (gRPC)","fill":"#fafafa"},
 {"x":20,"y":340,"w":650,"h":190,"label":"Handling event store","fill":"#fafafa"},
 {"x":700,"y":40,"w":280,"h":490,"label":"Shared reference types","fill":"#fafafa"},
]
nodes=[
 {"x":40,"y":75,"w":270,"h":115,"style":"accent","lines":["Cargo (Node)","id, trackingId, description","origin, destination: Location","routeSpecification, delivery, itinerary?","handlingHistory(first, after, last, before)"]},
 {"x":40,"y":235,"w":150,"h":65,"style":"box","lines":["RouteSpecification","origin, destination","arrivalDeadline"]},
 {"x":370,"y":75,"w":280,"h":65,"style":"box","lines":["Itinerary","legs: [Leg!]!","finalArrivalDate"]},
 {"x":370,"y":185,"w":280,"h":100,"style":"box","lines":["Leg","voyage?","loadLocation, unloadLocation","loadTime, unloadTime"]},
 {"x":40,"y":380,"w":200,"h":125,"style":"box","lines":["HandlingEvent (Node)","trackingId, type, location","voyage?, cargo?","completionTime","registrationTime"]},
 {"x":255,"y":380,"w":210,"h":125,"style":"box","lines":["Delivery","transportStatus, routingStatus","misdirected","estimatedTimeOfArrival?","lastKnownLocation?, currentVoyage?","nextExpectedActivity?"]},
 {"x":500,"y":380,"w":150,"h":80,"style":"box","lines":["HandlingActivity","type, location","voyage?"]},
 {"x":725,"y":75,"w":230,"h":80,"style":"sub","lines":["Location (Node)","unLocode, name, country"]},
 {"x":725,"y":215,"w":230,"h":90,"style":"sub","lines":["Voyage (Node)","number","schedule: [CarrierMovement!]!"]},
]
edges=[
 {"x1":100,"y1":190,"x2":100,"y2":235,"label":"routeSpecification","lx":58,"ly":0},
 {"x1":310,"y1":107,"x2":370,"y2":107,"amber":True,"label":"itinerary?","lx":-2,"ly":-10},
 {"x1":510,"y1":140,"x2":510,"y2":185,"label":"legs","lx":20,"ly":0},
 {"x1":650,"y1":205,"x2":725,"y2":125,"label":"locations","lx":-28,"ly":-8,"elx":-60},
 {"x1":650,"y1":260,"x2":725,"y2":260,"label":"voyage?","ly":-8,"amber":True},
 {"x1":220,"y1":190,"x2":220,"y2":380,"label":"history","lx":30,"ly":-30},
 {"x1":285,"y1":190,"x2":285,"y2":380,"label":"delivery","lx":32,"ly":30},
 {"x1":465,"y1":420,"x2":500,"y2":420},
]
notes=[
 {"x":20,"y":555,"text":"? marks a nullable field; every other field is non-null in the SDL.","size":12,"color":"#555555"},
 {"x":20,"y":575,"text":"Location is also referenced by origin, destination, lastKnownLocation and each event location.","size":12,"color":"#555555"},
]
g.emit("00-shipping-domain-model",1000,600,bands=bands,nodes=nodes,edges=edges,notes=notes)
