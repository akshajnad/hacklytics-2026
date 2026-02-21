"""WebSocket server for streaming caption events to iPhone clients."""

import asyncio
import json
import logging
import time
from typing import Set

from websockets.asyncio.server import ServerConnection, serve

logger = logging.getLogger(__name__)

# Connected clients. Only modified from the asyncio event loop (handler + broadcast).
connected_clients: Set[ServerConnection] = set()


def _unix_timestamp() -> float:
    """Return current time as Unix timestamp (float, seconds)."""
    return time.time()


def build_caption_event(
    text: str,
    caption_type: str,
    tone: str,
    confidence: float,
    volume: float,
) -> str:
    """Build a structured caption event JSON string.

    Compatible with Swift URLSessionWebSocketTask (text frames).
    """
    payload = {
        "type": "caption",
        "text": text,
        "caption_type": caption_type,
        "tone": tone,
        "confidence": confidence,
        "volume": volume,
        "timestamp": _unix_timestamp(),
    }
    return json.dumps(payload)


async def _handler(websocket: ServerConnection) -> None:
    connected_clients.add(websocket)
    logger.info("Client connected; total=%d", len(connected_clients))
    try:
        async for _ in websocket:
            pass
    except Exception as e:
        logger.debug("Client disconnect: %s", e)
    finally:
        connected_clients.discard(websocket)
        logger.info("Client disconnected; total=%d", len(connected_clients))


async def broadcast_caption(
    text: str,
    caption_type: str,
    tone: str,
    confidence: float,
    volume: float,
) -> None:
    """Broadcast a caption event to all connected clients. Non-blocking; safe for multiple clients."""
    msg = build_caption_event(
        text=text,
        caption_type=caption_type,
        tone=tone,
        confidence=confidence,
        volume=volume,
    )
    clients = list(connected_clients)
    if not clients:
        logger.debug("No clients connected; caption not broadcast")
        return

    logger.info("Broadcasting caption [%s] to %d client(s): %.60s", caption_type, len(clients), text[:60] + ("..." if len(text) > 60 else ""))

    results = await asyncio.gather(
        *[ws.send(msg) for ws in clients],
        return_exceptions=True,
    )
    for ws, r in zip(clients, results):
        if isinstance(r, Exception):
            logger.warning("Broadcast failed to one client: %s", r)
            connected_clients.discard(ws)


def create_server(host: str = "0.0.0.0", port: int = 8765):
    """Create WebSocket server. Use with: async with create_server() as server: await server.serve_forever()."""
    return serve(_handler, host, port)
