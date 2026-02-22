"""Entry point: orchestrate audio capture, ElevenLabs STT, tone, and WebSocket broadcast."""

import asyncio
import logging
import os
import threading

from dotenv import load_dotenv

from backend.src.audio.capture import capture_audio_loop
from backend.src.stt.elevenlabs_client import run_elevenlabs_client
from backend.src.tone.classifier import ToneClassifier
from backend.src.ws_server.server import broadcast_caption, create_server

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SAMPLE_RATE = 16000


async def main() -> None:
    # Load .env from backend dir so it works when run as python -m backend.main from repo root
    load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
    api_key = os.getenv("ELEVENLABS_API_KEY")
    if not api_key:
        logger.error("ELEVENLABS_API_KEY not set. Copy .env.example to .env and add your key.")
        return

    # ✅ Initialize tone classifier ONCE (important for performance)
    tone_classifier = ToneClassifier()

    loop = asyncio.get_running_loop()
    audio_queue: asyncio.Queue[tuple[bytes, float]] = asyncio.Queue()
    latest_volume: list[float] = [0.0]
    stop_event = asyncio.Event()

    def on_audio_chunk(pcm_bytes: bytes, volume_rms: float) -> None:
        latest_volume[0] = volume_rms
        loop.call_soon_threadsafe(audio_queue.put_nowait, (pcm_bytes, volume_rms))

    def on_transcript(text: str, caption_type: str) -> None:
        logger.info(
            "Transcript [%s]: %s",
            caption_type,
            text[:80] + ("..." if len(text) > 80 else "")
        )

        # ✅ Use new classifier
        tone, confidence = tone_classifier.classify_tone(
            text=text,
            volume=latest_volume[0],
        )

        asyncio.create_task(
            broadcast_caption(
                text=text,
                caption_type=caption_type,
                tone=tone,
                confidence=confidence,
                volume=latest_volume[0],
            )
        )

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

    async with create_server("0.0.0.0", 8765) as ws_server:
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