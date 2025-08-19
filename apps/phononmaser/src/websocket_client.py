"""WebSocket client for sending transcriptions to Phoenix server."""

import asyncio
import contextlib
import json
from datetime import datetime
from zoneinfo import ZoneInfo

import websockets
from shared import safe_handler
from shared.logger import get_logger
from shared.websockets import BaseWebSocketClient, ConnectionEvent, ConnectionState
from websockets.client import WebSocketClientProtocol

from .events import TranscriptionEvent
from .timestamp_utils import convert_timestamp_to_iso

logger = get_logger(__name__)


class ServerWebSocketClient(BaseWebSocketClient):
    """WebSocket client for sending transcription events to Phoenix server."""

    def __init__(
        self,
        server_url: str = "ws://saya:7175/socket/websocket",
        stream_session_id: str = None,
    ):
        super().__init__(
            server_url,
            heartbeat_interval=45.0,  # Phoenix channels expect less frequent pings
            circuit_breaker_threshold=5,
            circuit_breaker_timeout=300.0,
        )

        self.ws: WebSocketClientProtocol | None = None
        self._phoenix_ref = 1
        self._listen_task: asyncio.Task | None = None

        # Generate daily session ID if not provided
        if stream_session_id is None:
            la_tz = ZoneInfo("America/Los_Angeles")
            today = datetime.now(la_tz).strftime("%Y_%m_%d")
            self.stream_session_id = f"stream_{today}"
        else:
            self.stream_session_id = stream_session_id

        # Register for connection state changes
        self.on_connection_change(self._handle_connection_change)

        # Connection state
        self._channel_joined = False

    async def _do_connect(self) -> bool:
        """Perform a single connection attempt."""
        try:
            self.ws = await websockets.connect(self.url)
            logger.info(f"Connected to Phoenix server at {self.url}")

            # Start listening for messages
            self._listen_task = asyncio.create_task(self._do_listen())

            # Join transcription channel
            await self._join_transcription_channel()

            # Wait a moment for join confirmation
            await asyncio.sleep(0.5)

            return True
        except Exception as e:
            logger.error(f"Failed to connect to Phoenix server: {e}")
            return False

    async def _join_transcription_channel(self):
        """Join the transcription:live channel."""
        join_message = {
            "topic": "transcription:live",
            "event": "phx_join",
            "payload": {"source": "phononmaser", "stream_session_id": self.stream_session_id},
            "ref": str(self._phoenix_ref),
        }
        self._phoenix_ref += 1

        await self.ws.send(json.dumps(join_message))
        logger.info("Sent join request for transcription:live channel")

    @safe_handler
    async def _do_listen(self):
        """Listen for messages from Phoenix server."""
        if not self.ws:
            raise RuntimeError("Not connected to Phoenix server")

        async for message in self.ws:
            await self._handle_phoenix_message(message)

    @safe_handler
    async def _handle_phoenix_message(self, message: str):
        """Handle Phoenix channel messages."""
        try:
            data = json.loads(message)
            logger.debug(f"Phoenix message received: {data}")

            # Handle Phoenix channel message format
            if isinstance(data, dict):
                topic = data.get("topic")
                event = data.get("event")
                payload = data.get("payload", {})

                if event == "phx_reply" and payload.get("status") == "ok":
                    if topic == "transcription:live":
                        self._channel_joined = True
                        logger.info("Successfully joined transcription:live channel")
                elif event == "phx_error":
                    logger.error(f"Phoenix channel error: {payload}")
                elif event == "connection_established":
                    logger.info(f"Channel connection established: {payload}")

        except json.JSONDecodeError:
            logger.error("Invalid JSON received from Phoenix server", message_preview=message[:100])
        except Exception as e:
            logger.error("Error processing Phoenix message", error=str(e), exc_info=True)

    def _handle_connection_change(self, event: ConnectionEvent):
        """Handle connection state changes."""
        logger.info(
            f"Phoenix connection state changed: {event.old_state.value} -> {event.new_state.value}",
            error=str(event.error) if event.error else None,
        )

        if event.new_state == ConnectionState.CONNECTED:
            logger.info("Phoenix connection established, ready for transcription events")
        elif event.new_state == ConnectionState.DISCONNECTED and event.error:
            logger.warning(f"Phoenix disconnected due to: {event.error}")
            # Reset state on disconnect
            self._phoenix_ref = 1
            self._channel_joined = False

    async def _send_heartbeat(self) -> bool:
        """Send Phoenix channel heartbeat."""
        if not self.ws:
            return False

        try:
            heartbeat_msg = {"topic": "phoenix", "event": "heartbeat", "payload": {}, "ref": str(self._phoenix_ref)}
            self._phoenix_ref += 1

            await self.ws.send(json.dumps(heartbeat_msg))
            return True
        except Exception as e:
            logger.warning(f"Phoenix heartbeat failed: {e}")
            return False

    async def send_transcription(self, event: TranscriptionEvent) -> bool:
        """
        Send transcription event to Phoenix server via WebSocket channel.

        Args:
            event: TranscriptionEvent from phononmaser

        Returns:
            bool: True if successfully sent, False otherwise
        """
        if not self.ws or not self._channel_joined:
            logger.error("Not connected to transcription channel")
            return False

        try:
            # Format transcription data for Phoenix channel
            transcription_msg = {
                "topic": "transcription:live",
                "event": "submit_transcription",
                "payload": {
                    "timestamp": convert_timestamp_to_iso(event.timestamp),
                    "duration": event.duration,
                    "text": event.text,
                    "source_id": "phononmaser",
                    "stream_session_id": self.stream_session_id,
                    "confidence": None,  # whisper.cpp doesn't provide confidence scores
                    "metadata": {"original_timestamp_us": event.timestamp, "source": "whisper_cpp", "language": "en"},
                },
                "ref": str(self._phoenix_ref),
            }
            self._phoenix_ref += 1

            await self.ws.send(json.dumps(transcription_msg))
            logger.debug(f"Transcription sent via WebSocket: {event.text[:50]}...")
            return True

        except Exception as e:
            logger.error(f"Failed to send transcription via WebSocket: {e}")
            return False

    async def _do_disconnect(self):
        """Disconnect from Phoenix server."""
        if self._listen_task and not self._listen_task.done():
            self._listen_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._listen_task

        if self.ws:
            await self.ws.close()
            self.ws = None
            self._channel_joined = False

    async def health_check(self) -> bool:
        """
        Check if the Phoenix server connection is healthy.

        Returns:
            bool: True if connection is healthy, False otherwise
        """
        return self._connection_state == ConnectionState.CONNECTED and self._channel_joined and self.ws is not None
