"""Spec for assets/diagrams/23-test-layers.{svg,excalidraw}. Regenerate: python3 -I diagrams/23-test-layers.py

The six layers of examples/23-testing/verify.sh and what each one runs
against, asserts and runs in. The first three run inside each stack's
test image (22 Quarkus tests, 18 Python tests); the other three run
from verify.sh with graphql-inspector and k6.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

COLS = [(25, 170), (215, 220), (455, 300), (775, 200)]
ROWS = [86, 156, 226, 330, 400, 470]
H = 58

layers = [
    ("1  Schema", "built from the code", ["The built schema", "the SDL the framework serves"],
     ["Types and scalars exist", "the SDL is written to /out"], ["Test image", "mvn verify | pytest"]),
    ("2  Resolver unit", "no server, or one resolver", ["A function or a resolver", "the booking source is stubbed"],
     ["Values, paths and codes", "SERVICE_UNAVAILABLE at cargo"], ["Test image", "mvn verify | pytest"]),
    ("3  Operation", "the app in process", ["The app over its HTTP layer", "documents/ posted as clients do"],
     ["data beside errors", "8 or 6 calls; 7,651 refused"], ["Test image", "mvn verify | pytest"]),
    ("4  Contract", "exported and live SDL", ["Both schemas", "contracts/schema/ is the base"],
     ["No breaking change either way", "only Subscription is unserved"], ["verify.sh", "graphql-inspector"]),
    ("5  Client document", "what clients send", ["documents/ vs the contract", "Chapter 22's four operations"],
     ["Valid documents pass", "Cargo.weight is refused"], ["verify.sh", "graphql-inspector"]),
    ("6  Load", "the running stack", ["k6 virtual users", "exact numbers of iterations"],
     ["Every check true, same calls", "per request; one write for 40 retries"], ["verify.sh", "k6 image"]),
]

nodes, edges = [], []
for i, (name, sub, against, asserts, where) in enumerate(layers):
    y = ROWS[i]
    style = "accent" if i < 3 else "box"
    for col, lines in enumerate([[name, sub], against, asserts, where]):
        x, w = COLS[col]
        nodes.append(dict(x=x, y=y, w=w, h=H, style=("ink" if col == 3 and i >= 3 else style) if col in (0, 3) else "box", lines=lines))
    for col in range(3):
        x, w = COLS[col]
        edges.append(dict(x1=x + w, y1=y + H // 2, x2=COLS[col + 1][0], y2=y + H // 2, amber=(col == 2)))

bands = [
    dict(x=15, y=56, w=970, h=238, label="Run inside each stack's test image"),
    dict(x=15, y=300, w=970, h=240, label="Run from verify.sh against the live stacks"),
]
notes = [dict(x=COLS[0][0], y=48, text="Layer", bold=True, size=12), dict(x=COLS[1][0], y=48, text="Runs against", bold=True, size=12),
         dict(x=COLS[2][0], y=48, text="Asserts", bold=True, size=12), dict(x=COLS[3][0], y=48, text="Where it runs", bold=True, size=12),
         dict(x=500, y=566, text="A test that disappears fails the build: verify.sh counts 22 Quarkus and 18 Python tests from the JUnit reports.", anchor="middle", size=12, color="#555555")]
g.emit("23-test-layers", 1000, 580, bands=bands, nodes=nodes, edges=edges, notes=notes)
