"""ElevenLabs Realtime STT WebSocket client."""

import asyncio
import json
import logging
from typing import Any, AsyncIterator, Callable, Optional

from websockets.asyncio.client import connect
from websockets.asyncio.client import ClientConnection
from backend.src.dashboard.client import sentiment

logger = logging.getLogger(__name__)

ELEVENLABS_WS_URL = "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
SAMPLE_RATE = 16000


async def run_elevenlabs_client(
    api_key: str,
    audio_queue: asyncio.Queue[tuple[bytes, float]],
    on_transcript: Callable[[str, str], None],
    stop_event: asyncio.Event,
) -> None:
    """Connect to ElevenLabs Realtime STT, send audio, emit transcripts.

    Args:
        api_key: ElevenLabs API key.
        audio_queue: Queue of (pcm_bytes, volume_rms). Client consumes and sends.
        on_transcript: Callback(text, caption_type). caption_type is "partial" or "final".
        stop_event: When set, disconnect and exit.
    """
    url = (
        f"{ELEVENLABS_WS_URL}?audio_format=pcm_16000"
        "&commit_strategy=vad&language_code=en"
    )
    additional_headers = {"xi-api-key": api_key}

    while not stop_event.is_set():
        try:
            async with connect(url, additional_headers=additional_headers) as ws:
                logger.info("ElevenLabs session started")
                # Run sender and receiver concurrently
                await asyncio.gather(
                    _send_audio(ws, audio_queue, stop_event),
                    _receive_transcripts(ws, on_transcript, stop_event),
                )
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.warning("ElevenLabs client error: %s", e)
            if stop_event.is_set():
                break
            await asyncio.sleep(2)


async def _send_audio(
    ws: ClientConnection,
    audio_queue: asyncio.Queue[tuple[bytes, float]],
    stop_event: asyncio.Event,
) -> None:
    """Send audio chunks to ElevenLabs."""
    import base64

    chunks_sent = 0
    while not stop_event.is_set():
        try:
            pcm_bytes, _ = await asyncio.wait_for(audio_queue.get(), timeout=0.5)
            audio_b64 = base64.b64encode(pcm_bytes).decode("ascii")
            msg = {
                "message_type": "input_audio_chunk",
                "audio_base_64": audio_b64,
                "commit": False,
                "sample_rate": SAMPLE_RATE,
            }
            await ws.send(json.dumps(msg))
            chunks_sent += 1
            if chunks_sent == 20:
                logger.info("Audio streaming to ElevenLabs (20 chunks sent)")
        except asyncio.TimeoutError:
            continue
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.warning("Send audio error: %s", e)
            break


async def _receive_transcripts(
    ws: ClientConnection,
    on_transcript: Callable[[str, str], None],
    stop_event: asyncio.Event,
) -> None:
    """Receive and dispatch transcript events from ElevenLabs."""
    try:
        async for raw in ws:
            if stop_event.is_set():
                break
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                continue
            mt = data.get("message_type")
            if mt == "session_started":
                logger.info("ElevenLabs session confirmed")
            elif mt == "partial_transcript":
                text = data.get("text", "")
                if text.strip():
                    on_transcript(text.strip(), "partial")
            elif mt == "committed_transcript":
                text = data.get("text", "")
                if text.strip():
                    on_transcript(text.strip(), "final")
                    print(sentiment(text.strip()))
            elif mt in (
                "error",
                "auth_error",
                "quota_exceeded",
                "rate_limited",
                "queue_overflow",
                "resource_exhausted",
                "session_time_limit_exceeded",
                "input_error",
                "chunk_size_exceeded",
                "insufficient_audio_activity",
                "transcriber_error",
                "commit_throttled",
                "unaccepted_terms",
            ):
                logger.error("ElevenLabs error: %s", data.get("error", data))
    except asyncio.CancelledError:
        pass
    except Exception as e:
        logger.warning("Receive transcripts error: %s", e)
