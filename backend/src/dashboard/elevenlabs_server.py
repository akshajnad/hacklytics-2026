# server.py
import asyncio
import json
import websockets
from client import sentiment  # your existing function

PORT = 8766

async def handle_client(websocket):
    async for message in websocket:
        # message is the transcript chunk
        score = sentiment(message)  # Snowflake Cortex call
        response = {"transcript": message, "tonal_score": score}
        await websocket.send(json.dumps(response))

async def main():
    async with websockets.serve(handle_client, "0.0.0.0", PORT):
        print(f"WebSocket server running on ws://localhost:{PORT}")
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())