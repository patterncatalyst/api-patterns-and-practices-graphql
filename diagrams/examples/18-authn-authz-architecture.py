"""Spec for examples/18-authn-authz/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/18-authn-authz-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "18-authn-authz")
g.emit("architecture", 1000, 540,
 bands=[dict(x=20, y=20, w=960, h=500, label="examples/18-authn-authz - compose stack (gql-ch18-authn-authz)")],
 nodes=[
  dict(x=40, y=215, w=170, h=70, style="user", lines=["curl / verify.sh", "client + bearer token"]),
  dict(x=330, y=50, w=270, h=140, style="box", lines=["quarkus", "SmallRye GraphQL + quarkus-oidc", "@Authenticated / @RolesAllowed", "Viewer from SecurityIdentity", "BookingSource applies ownership", ":8080 -> host :8280 /graphql"]),
  dict(x=330, y=330, w=270, h=140, style="box", lines=["python", "Strawberry on FastAPI + PyJWT", "IsAuthenticated / IsOperator", "Identity in TrackingContext", "BookingSource applies ownership", ":8080 -> host :8281 /graphql"]),
  dict(x=720, y=180, w=240, h=140, style="accent", lines=["keycloak", "realm shipping (imported)", "ana, bo, ops", "tracking-cli, other-cli,", "short-cli", ":8080 -> host :8282 (tokens)", "JWKS over the compose network"]),
  dict(x=720, y=380, w=240, h=60, style="ghost", lines=["otel-lgtm", "(compose.observability.yaml)"]),
  dict(x=720, y=60, w=240, h=70, style="accent", lines=["contracts/schema/", "shipping/*.graphql (anonymous diff)"]),
 ],
 edges=[
  dict(x1=210, y1=240, x2=330, y2=130, label="POST + Bearer", lx=-30, ly=-20),
  dict(x1=210, y1=260, x2=330, y2=380, label="POST + Bearer", lx=-30, ly=30),
  dict(x1=210, y1=250, x2=720, y2=250, label="password grant (lab)", amber=True, dashed=True, lx=0, ly=-8),
  dict(x1=600, y1=150, x2=720, y2=215, label="JWKS", dashed=True, lx=0, ly=-10),
  dict(x1=600, y1=370, x2=720, y2=285, label="JWKS", dashed=True, lx=0, ly=20),
  dict(x1=600, y1=90, x2=720, y2=95, label="introspect + diff", amber=True, lx=0, ly=-10),
  dict(x1=600, y1=445, x2=720, y2=420, label="OTLP", dashed=True, lx=0, ly=18),
 ],
 notes=[dict(x=40, y=500, text="Tokens are fetched at localhost:8282, so their issuer is that address; the apps pin it and read keys by the back channel.", size=12, color="#555555")])
