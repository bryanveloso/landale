"""WebSocket client for consuming transcriptions from Phoenix server."""

import asyncio
import json
import time
from collections.abc import Callable
from datetime import datetime

import websockets
from websockets.client import WebSocketClientProtocol

from .events import TranscriptionEvent
from .logger import get_logger

logger = get_logger(__name__)


class TranscriptionWebSocketClient:
    """WebSocket client for consuming transcriptions from Phoenix server."""

    def __init__(self, server_url: str = "ws://saya:7175", channel: str = "transcription:live"):
        self.server_url = server_url
        self.channel = channel
        self.ws: WebSocketClientProtocol | None = None
        self.transcription_handlers = []
        self._connected = False

    def on_transcription(self, handler: Callable[[TranscriptionEvent], None]):
        """Register a handler for transcription events."""
        self.transcription_handlers.append(handler)

    async def connect(self):
        """Connect to Phoenix WebSocket server."""
        try:
            # Connect to Phoenix socket endpoint
            socket_url = f"{self.server_url}/socket/websocket"
            self.ws = await websockets.connect(socket_url)
            logger.info(f"Connected to Phoenix WebSocket at {socket_url}")

            # Join the transcription channel
            join_message = {"topic": self.channel, "event": "phx_join", "payload": {}, "ref": "1"}
            await self.ws.send(json.dumps(join_message))
            logger.info(f"Joining channel: {self.channel}")

            self._connected = True

        except Exception as e:
            logger.error(f"Failed to connect to Phoenix server: {e}")
            raise

    async def disconnect(self):
        """Disconnect from Phoenix WebSocket server."""
        if self.ws:
            try:
                # Leave the channel
                leave_message = {"topic": self.channel, "event": "phx_leave", "payload": {}, "ref": "2"}
                await self.ws.send(json.dumps(leave_message))
                await self.ws.close()
                logger.info("Disconnected from Phoenix server")
            except Exception as e:
                logger.warning(f"Error during disconnect: {e}")
            finally:
                self.ws = None
                self._connected = False

    async def listen(self):
        """Listen for transcription events from Phoenix server."""
        if not self.ws:
            raise RuntimeError("Not connected to Phoenix server")

        try:
            async for message in self.ws:
                try:
                    data = json.loads(message)
                    await self._handle_message(data)
                except json.JSONDecodeError:
                    logger.warning(f"Invalid JSON message: {message}")
                except Exception as e:
                    logger.error(f"Error processing message: {e}")

        except websockets.exceptions.ConnectionClosed:
            logger.info("Phoenix WebSocket connection closed")
            self._connected = False
        except Exception as e:
            logger.error(f"Error listening to Phoenix server: {e}")
            self._connected = False

    async def _handle_message(self, data: dict):
        """Handle incoming Phoenix WebSocket messages."""
        event = data.get("event")
        topic = data.get("topic")
        payload = data.get("payload", {})

        # Handle channel join confirmation
        if event == "phx_reply" and data.get("ref") == "1":
            if payload.get("status") == "ok":
                logger.info(f"Successfully joined channel: {topic}")
            else:
                logger.error(f"Failed to join channel: {payload}")

        # Handle new transcription events
        elif event == "new_transcription":
            await self._handle_transcription_event(payload)

        # Handle other transcription events
        elif event in ["connection_established", "session_started", "session_ended", "transcription_stats"]:
            logger.debug(f"Received {event}: {payload}")

        # Handle Phoenix heartbeat
        elif event == "phx_reply" and topic == "phoenix":
            logger.debug("Phoenix heartbeat received")

        else:
            logger.debug(f"Unhandled message: {data}")

    async def _handle_transcription_event(self, payload: dict):
        """Handle transcription event from Phoenix server."""
        try:
            # Create TranscriptionEvent from Phoenix payload
            # Note: Phoenix timestamps are ISO strings, need to convert to microseconds
            timestamp_str = payload.get("timestamp")
            if timestamp_str:
                try:
                    # Handle ISO format with or without Z suffix
                    if timestamp_str.endswith("Z"):
                        timestamp_str = timestamp_str[:-1] + "+00:00"

                    timestamp_dt = datetime.fromisoformat(timestamp_str)
                    timestamp_us = int(timestamp_dt.timestamp() * 1_000_000)
                except (ValueError, AttributeError) as e:
                    logger.warning(f"Failed to parse timestamp '{timestamp_str}': {e}")
                    timestamp_us = int(time.time() * 1_000_000)
            else:
                # Fallback to current time if no timestamp provided
                timestamp_us = int(time.time() * 1_000_000)

            transcription = TranscriptionEvent(
                timestamp=timestamp_us, duration=payload.get("duration", 0.0), text=payload.get("text", "")
            )

            # Call all registered handlers
            for handler in self.transcription_handlers:
                try:
                    if asyncio.iscoroutinefunction(handler):
                        await handler(transcription)
                    else:
                        handler(transcription)
                except Exception as e:
                    logger.error(f"Error in transcription handler: {e}")

        except Exception as e:
            logger.error(f"Error processing transcription event: {e}")

    async def send_ping(self):
        """Send ping to keep connection alive."""
        if self.ws and self._connected:
            try:
                ping_message = {
                    "topic": self.channel,
                    "event": "ping",
                    "payload": {},
                    "ref": str(asyncio.get_event_loop().time()),
                }
                await self.ws.send(json.dumps(ping_message))
            except Exception as e:
                logger.warning(f"Failed to send ping: {e}")

    @property
    def is_connected(self) -> bool:
        """Check if connected to Phoenix server."""
        return self._connected and self.ws is not None
