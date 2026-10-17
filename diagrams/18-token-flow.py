"""Spec for assets/diagrams/18-token-flow.{svg,excalidraw}. Regenerate: python3 -I diagrams/18-token-flow.py

Drawn from one run of examples/18-authn-authz/verify.sh: ana's password-grant
token, the claims verify.sh relies on, the JWKS read, and the 401 exit that a
tampered or wrong-audience token takes before GraphQL runs.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=20, y=50, w=960, h=380, label="From a login to a validated identity")]
nodes = [
    dict(x=40, y=100, w=190, h=70, style="user", lines=["client", "ana / ana-fixture-pw"]),
    dict(x=310, y=100, w=230, h=70, style="box", lines=["Keycloak token endpoint", "realm shipping, tracking-cli, localhost:8282"]),
    dict(x=620, y=90, w=340, h=100, style="accent", lines=["the access token (JWT)", "iss localhost:8282/realms/shipping, aud tracking-api", "realm_access.roles [shipper]", "shipper ACME, sub, exp"]),
    dict(x=310, y=250, w=230, h=80, style="box", lines=["GraphQL server", "quarkus-oidc  |  PyJWT", "signature, iss, aud, exp"]),
    dict(x=40, y=255, w=190, h=70, style="box", lines=["Keycloak JWKS", "read at keycloak:8080, cached"]),
    dict(x=620, y=255, w=340, h=70, style="accent", lines=["identity in the context", "roles and shipper; the token is dropped"]),
    dict(x=310, y=355, w=230, h=55, style="ink", lines=["HTTP 401", "WWW-Authenticate: Bearer"]),
]
edges = [
    dict(x1=230, y1=135, x2=310, y2=135, label="password grant", lx=0, ly=-8),
    dict(x1=540, y1=135, x2=620, y2=135, amber=True, label="issues", lx=0, ly=-8),
    dict(x1=700, y1=190, x2=540, y2=270, label="Authorization: Bearer", lx=50, ly=-20),
    dict(x1=310, y1=290, x2=230, y2=290, dashed=True, label="keys", lx=0, ly=-8),
    dict(x1=540, y1=290, x2=620, y2=290, amber=True, label="valid", lx=0, ly=-8),
    dict(x1=425, y1=330, x2=425, y2=355, dashed=True),
]
notes = [
    dict(x=500, y=28, text="A token is checked before any GraphQL runs", anchor="middle", bold=True),
    dict(x=500, y=455, text="No header at all is an anonymous caller, not a 401. The password grant is for the lab; production uses the authorization code flow with PKCE.", anchor="middle", size=12, color="#555555"),
    dict(x=555, y=375, text="a tampered, wrong-audience or expired token", size=11, color="#555555"),
]
g.emit("18-token-flow", 1000, 480, bands=bands, nodes=nodes, edges=edges, notes=notes)
