"""Spec for assets/diagrams/07-directive-pruning.{svg,excalidraw}. Regenerate: python3 -I diagrams/07-directive-pruning.py

Both panels run  cargo { trackingId  itinerary @include(if: $full) { ... }  delivery @skip(if: $full) { ... } }.
The call lists are the source-call logs of the chapter's check on both stacks.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")


def field(x, y, name, detail, kept):
    style = "accent" if kept else "ghost"
    return dict(x=x, y=y, w=250, h=70, style=style, lines=[name, detail, "resolved" if kept else "not collected, not resolved"])


def panel(x0, title, itinerary_kept, made, avoided):
    """One panel: itinerary on the left, delivery on the right, calls made and avoided below."""
    delivery_kept = not itinerary_kept
    left, right = x0 + 25, x0 + 305
    directive = "true" if itinerary_kept else "false"
    return dict(
        bands=[dict(x=x0, y=50, w=580, h=420, label=title)],
        nodes=[
            dict(x=x0 + 195, y=90, w=190, h=56, style="accent", lines=["cargo", "booking.getCargo"]),
            field(left, 200, f"itinerary @include(if: {directive})", "legs { loadTime }", itinerary_kept),
            field(right, 200, f"delivery @skip(if: {directive})", "transportStatus", delivery_kept),
            dict(x=left, y=330, w=250, h=110, style="accent" if itinerary_kept else "ghost", lines=made[0] if itinerary_kept else avoided[0]),
            dict(x=right, y=330, w=250, h=110, style="accent" if delivery_kept else "ghost", lines=made[1] if delivery_kept else avoided[1]),
        ],
        edges=[
            dict(x1=x0 + 260, y1=146, x2=left + 125, y2=200, amber=itinerary_kept, dashed=not itinerary_kept),
            dict(x1=x0 + 320, y1=146, x2=right + 125, y2=200, amber=delivery_kept, dashed=not delivery_kept),
            dict(x1=left + 125, y1=270, x2=left + 125, y2=330, amber=itinerary_kept, dashed=not itinerary_kept,
                 label="calls made" if itinerary_kept else "calls avoided", lx=46, ly=0),
            dict(x1=right + 125, y1=270, x2=right + 125, y2=330, amber=delivery_kept, dashed=not delivery_kept,
                 label="calls made" if delivery_kept else "calls avoided", lx=46, ly=0),
        ],
    )


# $full = false: delivery runs and asks routing and handling for its inputs.
false_panel = panel(
    20, "$full = false", itinerary_kept=False,
    made=(None, ["3 calls made", "booking.getCargo", "routing.getItinerary (input)", "handling.listEvents (input)"]),
    avoided=(["1 call avoided", "a second routing.getItinerary", "for the same key"], None),
)
# $full = true: itinerary runs; the derivation and its handling call never happen.
true_panel = panel(
    620, "$full = true", itinerary_kept=True,
    made=(["2 calls made", "booking.getCargo", "routing.getItinerary"], None),
    avoided=(None, ["2 calls avoided", "handling.listEvents", "routing.getItinerary (input)"]),
)
panels = (false_panel, true_panel)
notes = [
    dict(x=600, y=28, text="The same document, pruned by a variable before any field is resolved", anchor="middle", bold=True),
    dict(x=600, y=494, text="Dashed boxes are branches the engine never collects. delivery fetches routing as an input, so with both fields selected routing is asked twice.", anchor="middle", size=12, color="#555555"),
]
g.emit(
    "07-directive-pruning", 1220, 510,
    bands=[b for p in panels for b in p["bands"]],
    nodes=[n for p in panels for n in p["nodes"]],
    edges=[e for p in panels for e in p["edges"]],
    notes=notes,
)
