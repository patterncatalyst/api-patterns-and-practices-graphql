"""Ch21 Real-time - a subscription test client on gql's WebSocket transport.

    subscribe.py --url ws://quarkus:8080/graphql --subprotocol graphql-transport-ws \
                 --tracking-id ABC123 --count 2 --timeout 30 [--query FILE] [--frames]

Subscribes to ``Subscription.cargoHandled`` for one tracking id and prints one
JSON line per ``next`` payload. A GraphQL error prints ``{"error": [...]}`` and a
server-side ``complete`` prints ``{"complete": true}``. Exit status: 0 after
``--count`` events (or after a ``complete``), 1 on a GraphQL error, 2 on timeout.

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
import sys
from pathlib import Path

from gql import Client, gql
from gql.transport.exceptions import TransportQueryError
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
    transport = WebsocketsTransport(url=args.url, subprotocols=[args.subprotocol])
    received = 0
    try:
        async with asyncio.timeout(args.timeout):
            async with Client(transport=transport) as session:
                async for result in session.subscribe(
                    document, variable_values={"id": args.tracking_id}
                ):
                    print(json.dumps(result), flush=True)
                    received += 1
                    if received >= args.count:
                        return 0
        print(json.dumps({"complete": True}), flush=True)
        return 0
    except TransportQueryError as failure:
        print(json.dumps({"error": failure.errors}), flush=True)
        return 1
    except TimeoutError:
        return 2


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
