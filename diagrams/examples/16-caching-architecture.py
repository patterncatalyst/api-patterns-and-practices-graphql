"""Spec for examples/16-caching/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/16-caching-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "16-caching")
g.emit("architecture", 1000, 520,
 bands=[dict(x=20, y=20, w=960, h=480, label="examples/16-caching - compose stack (gql-ch16-caching)")],
 nodes=[
  dict(x=40, y=230, w=150, h=70, style="user", lines=["curl / verify.sh", "client"]),
  dict(x=290, y=70, w=230, h=60, style="accent", lines=["edge/nginx.conf", "mounted :ro,z"]),
  dict(x=290, y=175, w=230, h=150, style="accent", lines=["edge  (nginx, UBI 10)", "proxy_cache, runs as uid 1001", ":8262 -> quarkus", ":8263 -> python"]),
  dict(x=620, y=70, w=330, h=130, style="box", lines=["quarkus", "CachePolicy (@AfterExecute)", "quarkus-cache: voyages, locations,", "handling-events", ":8260 /graphql, direct"]),
  dict(x=620, y=250, w=330, h=130, style="box", lines=["python", "CachePolicy (SchemaExtension)", "cachetools TTLCache x 3", ":8261 /graphql, direct"]),
  dict(x=620, y=410, w=330, h=60, style="ghost", lines=["otel-lgtm (compose.observability.yaml)"]),
 ],
 edges=[
  dict(x1=190, y1=265, x2=290, y2=250, label="GET", lx=0, ly=-10),
  dict(x1=405, y1=130, x2=405, y2=175, label="reads at start", amber=True, lx=52, ly=2),
  dict(x1=520, y1=205, x2=620, y2=140, label="miss", lx=-4, ly=-12),
  dict(x1=520, y1=295, x2=620, y2=315, label="miss", lx=0, ly=-10),
 ],
 notes=[dict(x=40, y=488, text="The direct ports (8260, 8261) carry the source-call log and the server caches; the edge ports (8262, 8263) carry the HTTP cache.", size=12, color="#555555")])
