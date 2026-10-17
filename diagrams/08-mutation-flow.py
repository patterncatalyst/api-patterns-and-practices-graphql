"""Spec for assets/diagrams/08-mutation-flow.{svg,excalidraw}. Regenerate: python3 -I diagrams/08-mutation-flow.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

W, GAP, Y, H = 136, 28, 100, 84


def x_of(i):
    return 20 + i * (W + GAP)


stages = [
    ("Variables", "user", ["JSON object", "$input"]),
    ("Input coercion", "accent", ["scalars, enums,", "unknown fields"]),
    ("Domain validation", "accent", ["cargo, location,", "voyage, time"]),
    ("Key lookup", "accent", ["findByIdempotencyKey", "only with a key"]),
    ("appendEvent", "accent", ["atomic check", "and insert"]),
    ("Re-read", "accent", ["Cargo.delivery from", "listEvents"]),
    ("Payload", "box", ["handlingEvent, cargo,", "userErrors"]),
]
nodes = [dict(x=x_of(i), y=Y, w=W, h=H, style=s, lines=[t] + d) for i, (t, s, d) in enumerate(stages)]

# Exits drawn below the stage they leave.
nodes += [
    dict(x=x_of(1) - 7, y=270, w=150, h=84, style="sub", lines=["errors[]", "data absent or null", "nothing written"]),
    dict(x=x_of(2) - 7, y=270, w=150, h=84, style="sub", lines=["userErrors[]", "event and cargo null", "nothing written"]),
    dict(x=x_of(3) + 20, y=270, w=150, h=84, style="accent", lines=["Key hit", "the original event", "nothing written"]),
]
cx = lambda i: x_of(i) + W / 2
edges = [dict(x1=x_of(i) + W, y1=Y + H / 2, x2=x_of(i + 1), y2=Y + H / 2, amber=(i >= 1)) for i in range(6)]
edges += [
    dict(x1=cx(1), y1=Y + H, x2=cx(1), y2=270, dashed=True, label="fails", lx=24, ly=0),
    dict(x1=cx(2), y1=Y + H, x2=cx(2), y2=270, dashed=True, label="fails", lx=24, ly=0),
    dict(x1=cx(3), y1=Y + H, x2=cx(3) + 20, y2=270, amber=True, label="hit", lx=-20, ly=0),
    dict(x1=x_of(3) + 20 + 150, y1=312, x2=cx(5) + 30, y2=Y + H, amber=True, label="re-read", lx=24, ly=22),
]
notes = [
    dict(x=600, y=28, text="registerHandlingEvent: from the input object to the payload", anchor="middle", bold=True),
    dict(x=600, y=392, text="Coercion belongs to the engine and runs before the resolver. Validation, lookup, append and re-read run in the resolver.", anchor="middle", size=12, color="#555555"),
    dict(x=600, y=412, text="A request with a new key, or no key, takes the full path to appendEvent. A key hit skips the append and goes straight to the re-read.", anchor="middle", size=12, color="#555555"),
]
g.emit("08-mutation-flow", 1200, 440, nodes=nodes, edges=edges, notes=notes)
