"""Ch21 Real-time - a subscription test client on gql's WebSocket transport (Chapter 27: through the edge, with a bearer token).

    subscribe.py --url wss://edge:8443/graphql --subprotocol graphql-transport-ws \
                 --tracking-id ABC123 --count 1 --timeout 30 [--query FILE] [--frames]

The bearer token comes from the ``TOKEN`` environment variable and travels on the
HTTP upgrade request; no token is an anonymous caller.

Subscribes to ``Subscription.cargoHandled`` for one tracking id and prints one
JSON line per ``next`` message, ``{"data": ..., "errors": ...}`` exactly as the
server sent it (a field the caller may not read is an error in the ``next``
message of its event). An error message that ends the subscription prints
``{"error": [...]}`` and a server-side ``complete`` prints ``{"complete": true}``.
Exit status: 0 after ``--count`` events (or after a ``complete``), 1 on an
error message, 2 on timeout, 3 when the upgrade is refused.

The protocol is gql's: ``WebsocketsTransport`` speaks ``graphql-transport-ws`` or
the older ``graphql-ws`` as requested, and this script only builds the document and
reads the results. With ``--frames`` the frames gql exchanges (``>>>`` sent, ``<<<``
received) are echoed to stderr, which is how the chapter's figure is drawn from a run.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import ssl
import sys
from pathlib import Path

from gql import Client, gql
from gql.transport.exceptions import TransportConnectionFailed, TransportQueryError, TransportServerError
from gql.transport.websockets import WebsocketsTransport

DEFAULT_DOCUMENT = """
subscription Watch($id: TrackingId!) {
  cargoHandled(trackingId: $id) {
    id
    type
    location { name }
    cargo { trackingId delivery { transportStatus } }
  }
}
"""


class _FrameFilter(logging.Filter):
    """Keep only the lines gql logs for a frame sent (``>>>``) or received (``<<<``)."""

    def filter(self, record: logging.LogRecord) -> bool:
        return record.getMessage().startswith((">>> ", "<<< "))


def _echo_frames() -> None:
    handler = logging.StreamHandler(sys.stderr)
    handler.addFilter(_FrameFilter())
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger = logging.getLogger("gql.transport.common.base")
    logger.addHandler(handler)
    logger.setLevel(logging.DEBUG)


async def watch(args: argparse.Namespace) -> int:
    document = gql(Path(args.query).read_text() if args.query else DEFAULT_DOCUMENT)
    token = os.environ.get("TOKEN", "")
    transport = WebsocketsTransport(
        url=args.url,
        subprotocols=[args.subprotocol],
        headers={"Authorization": f"Bearer {token}"} if token else None,
        # The default context trusts the system roots and the file SSL_CERT_FILE names.
        ssl=ssl.create_default_context() if args.url.startswith("wss://") else False,
    )
    received = 0
    try:
        async with asyncio.timeout(args.timeout):
            async with Client(transport=transport) as session:
                async for result in session.subscribe(
                    document, variable_values={"id": args.tracking_id}, get_execution_result=True
                ):
                    print(json.dumps({"data": result.data, "errors": result.errors}), flush=True)
                    received += 1
                    if received >= args.count:
                        return 0
        print(json.dumps({"complete": True}), flush=True)
        return 0
    except TransportQueryError as failure:
        if failure.data is not None:
            # A next message that carries errors beside its data: one event, as the server sent it.
            print(json.dumps({"data": failure.data, "errors": failure.errors}), flush=True)
            return 0
        print(json.dumps({"error": failure.errors}), flush=True)
        return 1
    except TimeoutError:
        return 2
    except (TransportServerError, TransportConnectionFailed, OSError) as failure:
        print(json.dumps({"refused": str(failure)}), flush=True)
        return 3


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--url", required=True)
    parser.add_argument("--subprotocol", default="graphql-transport-ws")
    parser.add_argument("--tracking-id", default="ABC123")
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--query", help="a file holding the subscription document")
    parser.add_argument("--frames", action="store_true")
    args = parser.parse_args()
    if args.frames:
        _echo_frames()
    return asyncio.run(watch(args))


if __name__ == "__main__":
    sys.exit(main())
