"""Spec for assets/diagrams/27-final-architecture.{svg,excalidraw}. Regenerate: python3 -I diagrams/27-final-architecture.py

The components and networks of the compose tier of examples/27-final-project, each
labelled with the chapter it comes from. The host reaches the edge on 8370 and 8371;
the internal instances, Keycloak and the observability backend publish on 127.0.0.1
only; the public instances publish nothing.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=960, h=450, label="Compose project gql-ch27-final: networks public, ops and backend (internal)"),
]
nodes = [
    dict(x=40, y=120, w=150, h=90, style="user", lines=["client", "bearer token,", "traceparent"]),
    dict(x=240, y=100, w=210, h=130, style="accent", lines=["edge (Ch25)", "TLS 1.3, 64k body limit", "/graphql + upgrade, /events/", "host 8370 and 8371"]),
    dict(x=520, y=80, w=220, h=80, style="box", lines=["quarkus, python (Ch14, 17, 18, 21)", "public, introspection off", "publish nothing"]),
    dict(x=520, y=185, w=220, h=80, style="sub", lines=["internal instances", "same images, introspection on", "127.0.0.1 8372, 8373"]),
    dict(x=790, y=80, w=170, h=80, style="box", lines=["keycloak 26.8.1 (Ch18)", "realm shipping", "127.0.0.1 8374"]),
    dict(x=790, y=185, w=170, h=80, style="accent", lines=["lgtm 0.37.0 (Ch19, 25)", "Tempo, Loki, Prometheus", "127.0.0.1 8375 to 8378"]),
    dict(x=240, y=300, w=210, h=80, style="sub", lines=["client profile (Ch21)", "gql-ch27-client:1.0", "wss through the edge"]),
    dict(x=520, y=300, w=220, h=80, style="sub", lines=["load profile (Ch23)", "gql-ch27-load:1.0, k6 v2.3.0", "fanout and cost runs"]),
    dict(x=790, y=300, w=170, h=80, style="ghost", lines=["contracts/schema/", "assert_sdl_equals on", "the internal instances"]),
    dict(x=40, y=410, w=460, h=80, style="ghost", lines=["Left in their own chapters", "persisted documents (15), caching (16), federation (20),", "clients and test suites (22, 23), dev instances (24)"]),
]
edges = [
    dict(x1=190, y1=165, x2=240, y2=165, label="TLS 1.3", lx=0, ly=-12),
    dict(x1=450, y1=140, x2=520, y2=120, label="Authorization", lx=0, ly=-14),
    dict(x1=630, y1=160, x2=630, y2=185, dashed=True),
    dict(x1=740, y1=120, x2=790, y2=120, amber=True, label="JWKS", lx=0, ly=-12),
    dict(x1=740, y1=225, x2=790, y2=225, amber=True, label="OTLP", lx=0, ly=-12),
    dict(x1=740, y1=150, x2=820, y2=185, amber=True),
    dict(x1=345, y1=300, x2=345, y2=230, dashed=True),
    dict(x1=630, y1=300, x2=480, y2=215, dashed=True),
    dict(x1=790, y1=300, x2=740, y2=255, dashed=True),
]
notes = [
    dict(x=500, y=28, text="One edge, two public instances, two internal instances, one identity provider, one observability backend", anchor="middle", bold=True),
    dict(x=500, y=522, text="Every component is the image of an earlier chapter; the chapter adds the wiring between them, not a new feature.", anchor="middle", size=12, color="#555555"),
]
g.emit("27-final-architecture", 1000, 545, bands=bands, nodes=nodes, edges=edges, notes=notes)
