"""Realtime backend entry point.

Pipeline:
1) Capture microphone PCM chunks + RMS volume.
2) Stream audio to ElevenLabs realtime STT.
3) Broadcast every transcript chunk to iOS via websocket.
4) Recompute tone only at 10-word partial boundaries, and reuse last tone between boundaries.
5) Receive final meeting payload from iOS and hand off to a placeholder ingest function.
"""

import asyncio
import logging
import os
import re
import threading

from dotenv import load_dotenv

from backend.src.audio.capture import capture_audio_loop
from backend.src.dashboard.visualization import handle_meeting_payload_placeholder
from backend.src.stt.elevenlabs_client import run_elevenlabs_client
from backend.src.tone_analysis.client import sentiment
from backend.src.ws_server.server import broadcast_caption, create_server

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SAMPLE_RATE = 16000


def _count_words(text: str) -> int:
    """Count words in partial transcript text for the 10-word tone cadence."""
    return len(re.findall(r"\b[\w']+\b", text))


def _coerce_confidence(raw_confidence: object) -> float:
    """Clamp tone confidence values into [0.0, 1.0] with safe fallback."""
    try:
        value = float(raw_confidence)
    except (TypeError, ValueError):
        return 0.5
    return max(0.0, min(1.0, value))


def _classify_tone(text: str) -> tuple[str, float]:
    """Call sentiment backend and normalize output for websocket payloads."""
    try:
        tone_result = sentiment(text)
    except Exception as exc:
        logger.warning("Tone analysis failed, using neutral: %s", exc)
        return "neutral", 0.5

    label = str(
        tone_result.get("label")
        or tone_result.get("tone")
        or "neutral"
    ).strip().lower()
    if not label:
        label = "neutral"
    confidence = _coerce_confidence(tone_result.get("confidence", 0.5))
    return label, confidence


async def main() -> None:
    # Load .env from backend dir so it works when run as python -m backend.main from repo root
    load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
    api_key = os.getenv("ELEVENLABS_API_KEY")
    if not api_key:
        logger.error("ELEVENLABS_API_KEY not set. Copy .env.example to .env and add your key.")
        return

    loop = asyncio.get_running_loop()
    audio_queue: asyncio.Queue[tuple[bytes, float]] = asyncio.Queue()
    latest_volume: list[float] = [0.0]

    # Streaming tone state:
    # - Start neutral
    # - Recompute only when partial transcript crosses a new 10-word bucket (10/20/30...)
    # - Keep sending the most recent tone for every chunk in between
    last_tone_label: list[str] = ["neutral"]
    last_tone_confidence: list[float] = [0.5]
    last_analyzed_word_bucket: list[int] = [0]
    last_analyzed_text: list[str] = [""]
    stop_event = asyncio.Event()

    def on_audio_chunk(pcm_bytes: bytes, volume_rms: float) -> None:
        latest_volume[0] = volume_rms
        loop.call_soon_threadsafe(audio_queue.put_nowait, (pcm_bytes, volume_rms))

    def on_transcript(text: str, caption_type: str) -> None:
        cleaned_text = text.strip()
        if not cleaned_text:
            return

        word_count = _count_words(cleaned_text)
        current_bucket = word_count // 5

        # If partial text shrinks/reset (new sentence segment), reset cadence state.
        if caption_type == "partial" and current_bucket < last_analyzed_word_bucket[0]:
            last_tone_label[0] = "neutral"
            last_tone_confidence[0] = 0.5
            last_analyzed_word_bucket[0] = 0
            last_analyzed_text[0] = ""

        should_recompute_tone = (
            current_bucket > 0
            and current_bucket != last_analyzed_word_bucket[0]
            and cleaned_text != last_analyzed_text[0]
        )

        # Tone is computed from the full current partial only when entering a new 10-word bucket.
        if should_recompute_tone:
            tone_label, confidence = _classify_tone(cleaned_text)
            last_tone_label[0] = tone_label
            last_tone_confidence[0] = confidence
            last_analyzed_word_bucket[0] = current_bucket
            last_analyzed_text[0] = cleaned_text

        # logger.info(
        #     "Transcript [%s]: %s",
        #     caption_type,
        #     cleaned_text[:80] + ("..." if len(cleaned_text) > 80 else "")
        # )

        # Every chunk is broadcast (partial and final), always using latest known tone + latest volume.
        asyncio.create_task(
            broadcast_caption(
                text=cleaned_text,
                caption_type=caption_type,
                tone=last_tone_label[0],
                confidence=last_tone_confidence[0],
                volume=latest_volume[0],
            )
        )

        # Final chunks are commit boundaries; reset tone cadence for next utterance.
        if caption_type == "final":
            last_tone_label[0] = "neutral"
            last_tone_confidence[0] = 0.5
            last_analyzed_word_bucket[0] = 0
            last_analyzed_text[0] = ""

    capture_stop = threading.Event()
    capture_thread = threading.Thread(
        target=capture_audio_loop,
        args=(on_audio_chunk, capture_stop),
        daemon=True,
    )
    capture_thread.start()
    logger.info("Audio capture started")

    elevenlabs_task = asyncio.create_task(
        run_elevenlabs_client(
            api_key=api_key,
            audio_queue=audio_queue,
            on_transcript=on_transcript,
            stop_event=stop_event,
        )
    )

    async with create_server(
        "0.0.0.0",
        8765,
        on_meeting_payload=handle_meeting_payload_placeholder,
    ) as ws_server:
        logger.info("WebSocket server listening on ws://0.0.0.0:8765")
        server_task = asyncio.create_task(ws_server.serve_forever())
        try:
            await asyncio.Future()  # Run until interrupted (e.g. Ctrl+C)
        except asyncio.CancelledError:
            pass
        finally:
            stop_event.set()
            capture_stop.set()

            elevenlabs_task.cancel()
            try:
                await elevenlabs_task
            except asyncio.CancelledError:
                pass

            server_task.cancel()
            try:
                await server_task
            except asyncio.CancelledError:
                pass

            capture_thread.join(timeout=2.0)
            logger.info("Shutdown complete")


if __name__ == "__main__":
    asyncio.run(main())