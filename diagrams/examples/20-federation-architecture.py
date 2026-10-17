"""Spec for examples/20-federation/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/20-federation-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "20-federation")
g.emit("architecture", 1000, 560,
 bands=[dict(x=20, y=20, w=960, h=520, label="examples/20-federation - compose stack (gql-ch20-federation)")],
 nodes=[
  dict(x=40, y=240, w=150, h=70, style="user", lines=["curl / verify.sh", "client"]),
  dict(x=250, y=70, w=190, h=70, style="accent", lines=["gateway-a", "Hive Gateway, host 8300"]),
  dict(x=250, y=410, w=190, h=70, style="accent", lines=["gateway-b", "Hive Gateway, host 8301"]),
  dict(x=520, y=50, w=210, h=60, style="box", lines=["cargo-quarkus", "SmallRye, host 8302"]),
  dict(x=520, y=125, w=210, h=60, style="box", lines=["handling-python", "Strawberry, host 8305"]),
  dict(x=520, y=235, w=210, h=70, style="user", lines=["composer-a, composer-b", "one-shot, same image as the gateways"]),
  dict(x=520, y=355, w=210, h=60, style="box", lines=["cargo-python", "Strawberry, host 8303"]),
  dict(x=520, y=430, w=210, h=60, style="box", lines=["handling-quarkus", "SmallRye, host 8304"]),
  dict(x=790, y=235, w=170, h=70, style="sub", lines=["volume supergraph", "supergraph-a, supergraph-b"]),
  dict(x=790, y=360, w=170, h=60, style="ghost", lines=["fixtures/", "two failing subgraphs"]),
 ],
 edges=[
  dict(x1=190, y1=265, x2=250, y2=110, label="POST /graphql", lx=-26, ly=-18),
  dict(x1=190, y1=285, x2=250, y2=440, label="POST /graphql", lx=-26, ly=24),
  dict(x1=440, y1=90, x2=520, y2=80),
  dict(x1=440, y1=120, x2=520, y2=150),
  dict(x1=440, y1=440, x2=520, y2=385),
  dict(x1=440, y1=460, x2=520, y2=460),
  dict(x1=625, y1=185, x2=625, y2=235, dashed=True, label="_service", lx=34, ly=0),
  dict(x1=625, y1=355, x2=625, y2=305, dashed=True, label="_service", lx=34, ly=0),
  dict(x1=730, y1=270, x2=790, y2=270, amber=True, label="writes", lx=0, ly=-10),
  dict(x1=830, y1=360, x2=730, y2=295, dashed=True, label="--file", lx=14, ly=18),
 ],
 notes=[dict(x=40, y=520, text="The gateways mount the supergraph volume read-only and load the file; the composers publish no port.", size=12, color="#555555")])
