"""Spec for assets/diagrams/16-invalidation-on-write.{svg,excalidraw}. Regenerate: python3 -I diagrams/16-invalidation-on-write.py

Drawn from the case-9 run of examples/16-caching/verify.sh (ABC123, handling
TTL 20 s, both stacks): the handling-events entry for ABC123 is filled by a read,
hit by the next, evicted by registerHandlingEvent after the append, refilled by
the payload's own read of the cargo, and hit again. The source-call counts are
the ones verify.sh asserts; the registration payload shows IN_PORT.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes = [
    dict(x=30, y=80, w=320, h=100, style="box", lines=["1. Read cargo(ABC123) delivery", "handling-events:ABC123 is empty", "listEventsFor:ABC123, 1 call", "transportStatus: ONBOARD_CARRIER"]),
    dict(x=390, y=80, w=320, h=100, style="box", lines=["2. Read it again", "entry found", "0 handling calls", "transportStatus: ONBOARD_CARRIER"]),
    dict(x=750, y=80, w=320, h=100, style="box", lines=["3. registerHandlingEvent", "UNLOAD at DEHAM on V100S", "appendEvent, 1 call: evt_10", "the owner now holds 3 events"]),
    dict(x=750, y=250, w=320, h=100, style="accent", lines=["4. Evict handling-events:ABC123", "after the append,", "before the payload reads the cargo", "so it cannot see the old list"]),
    dict(x=390, y=250, w=320, h=100, style="accent", lines=["5. Payload reads cargo.delivery", "entry missing: listEventsFor:ABC123", "1 call, refills the entry", "transportStatus: IN_PORT"]),
    dict(x=30, y=250, w=320, h=100, style="box", lines=["6. Read cargo(ABC123) again", "entry found", "0 handling calls", "transportStatus: IN_PORT"]),
]
edges = [
    dict(x1=350, y1=130, x2=390, y2=130),
    dict(x1=710, y1=130, x2=750, y2=130),
    dict(x1=910, y1=180, x2=910, y2=250, amber=True),
    dict(x1=750, y1=300, x2=710, y2=300, amber=True),
    dict(x1=390, y1=300, x2=350, y2=300),
]
notes = [
    dict(x=550, y=36, text="Invalidation on write: evict before the payload re-reads", anchor="middle", bold=True),
    dict(x=550, y=392, text="Without step 4 the payload would answer ONBOARD_CARRIER for the event it had just recorded.", anchor="middle", size=12, color="#555555"),
    dict(x=550, y=412, text="The TTL (20 s here, 60 s by default) bounds staleness from writers that never call this service.", anchor="middle", size=12, color="#555555"),
]
g.emit("16-invalidation-on-write", 1100, 436, nodes=nodes, edges=edges, notes=notes)
