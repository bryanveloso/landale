"""WebSocket client for consuming transcriptions from Phoenix server."""

import asyncio
import json
import time
from collections.abc import Callable
from datetime import datetime

import websockets
from shared.websockets import BaseWebSocketClient, ConnectionEvent, ConnectionState

from .events import TranscriptionEvent
from .logger import get_logger

logger = get_logger(__name__)


class TranscriptionWebSocketClient(BaseWebSocketClient):
    """WebSocket client for consuming transcriptions from Phoenix server."""

    def __init__(self, server_url: str = "ws://saya:7175", channel: str = "transcription:live"):
        # Convert to Phoenix socket endpoint format
        socket_url = f"{server_url}/socket/websocket"
        super().__init__(
            socket_url,
            heartbeat_interval=45.0,  # Phoenix channels expect less frequent pings
            circuit_breaker_threshold=5,
            circuit_breaker_timeout=300.0,
        )

        self.channel = channel
        self.ws = None
        self.transcription_handlers = []
        self._phoenix_ref = 1
        self._joined_channel = False
        self._join_timeout_task: asyncio.Task | None = None

        # Register for connection state changes
        self.on_connection_change(self._handle_connection_change)

    def on_transcription(self, handler: Callable[[TranscriptionEvent], None]):
        """Register a handler for transcription events."""
        self.transcription_handlers.append(handler)

    async def _do_connect(self) -> bool:
        """Perform a single connection attempt."""
        try:
            self.ws = await websockets.connect(self.url)
            logger.info(f"Connected to Phoenix WebSocket at {self.url}")

            # Join the transcription channel
            join_message = {"topic": self.channel, "event": "phx_join", "payload": {}, "ref": str(self._phoenix_ref)}
            self._phoenix_ref += 1

            await self.ws.send(json.dumps(join_message))
            logger.info(f"Attempting to join channel: {self.channel}")

            # Set a timeout for the join confirmation
            async def join_timeout():
                await asyncio.sleep(10)  # 10-second timeout
                if not self._joined_channel:
                    logger.warning(f"Channel join for '{self.channel}' timed out. Triggering reconnect.")
                    # Use create_task to avoid blocking the timeout task itself
                    if self._connection_state == ConnectionState.CONNECTED:
                        asyncio.create_task(self.disconnect())

            self._join_timeout_task = asyncio.create_task(join_timeout())

            # Mark as successful connection even if join is pending
            # The join confirmation will be handled in message processing
            return True

        except Exception as e:
            logger.error(f"Failed to connect to Phoenix server: {e}")
            return False

    async def _do_disconnect(self):
        """Perform disconnection logic."""
        if self._join_timeout_task and not self._join_timeout_task.done():
            self._join_timeout_task.cancel()
            self._join_timeout_task = None

        if self.ws:
            try:
                # Leave the channel if joined
                if self._joined_channel:
                    leave_message = {
                        "topic": self.channel,
                        "event": "phx_leave",
                        "payload": {},
                        "ref": str(self._phoenix_ref),
                    }
                    self._phoenix_ref += 1
                    await self.ws.send(json.dumps(leave_message))
                    logger.info("Left transcription channel")

                await self.ws.close()
                logger.info("Disconnected from Phoenix server")
            except Exception as e:
                logger.warning(f"Error during disconnect: {e}")
            finally:
                self.ws = None
                self._joined_channel = False

    async def _do_listen(self):
        """Listen for messages on the connection."""
        if not self.ws:
            raise websockets.exceptions.ConnectionClosed("No WebSocket connection")

        async for message in self.ws:
            try:
                data = json.loads(message)
                await self._handle_message(data)
            except json.JSONDecodeError:
                logger.warning(f"Invalid JSON message: {message}")
            except Exception as e:
                logger.error(f"Error processing message: {e}")

    async def _handle_message(self, data: dict):
        """Handle incoming Phoenix WebSocket messages."""
        event = data.get("event")
        topic = data.get("topic")
        payload = data.get("payload", {})

        # Handle channel join confirmation
        if event == "phx_reply" and topic == self.channel:
            if self._join_timeout_task and not self._join_timeout_task.done():
                self._join_timeout_task.cancel()
                self._join_timeout_task = None

            if payload.get("status") == "ok":
                logger.info(f"Successfully joined channel: {topic}")
                self._joined_channel = True
            else:
                logger.error(f"Failed to join channel: {payload}. Triggering reconnect.")
                # Disconnect to allow the base client's reconnect logic to take over
                asyncio.create_task(self.disconnect())

        # Handle new transcription events
        elif event == "new_transcription" and topic == self.channel:
            await self._handle_transcription_event(payload)

        # Handle other transcription events
        elif event in ["connection_established", "session_started", "session_ended", "transcription_stats"]:
            logger.debug(f"Received {event}: {payload}")

        # Handle Phoenix heartbeat reply
        elif event == "phx_reply" and topic == "phoenix":
            logger.debug("Phoenix heartbeat acknowledged")

        else:
            logger.debug(f"Unhandled message - event: {event}, topic: {topic}")

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
                        loop = asyncio.get_running_loop()
                        await loop.run_in_executor(None, handler, transcription)
                except Exception as e:
                    logger.error(f"Error in transcription handler: {e}")

        except Exception as e:
            logger.error(f"Error processing transcription event: {e}")

    async def _send_heartbeat(self) -> bool:
        """Send Phoenix channel heartbeat."""
        if not self.ws:
            return False

        try:
            # Phoenix heartbeat message format
            heartbeat_msg = {"topic": "phoenix", "event": "heartbeat", "payload": {}, "ref": str(self._phoenix_ref)}
            self._phoenix_ref += 1

            await self.ws.send(json.dumps(heartbeat_msg))
            return True
        except Exception as e:
            logger.warning(f"Phoenix heartbeat failed: {e}")
            return False

    def _handle_connection_change(self, event: ConnectionEvent):
        """Handle connection state changes."""
        logger.info(
            f"Transcription connection state changed: {event.old_state.value} -> {event.new_state.value}",
            error=str(event.error) if event.error else None,
        )

        if event.new_state == ConnectionState.CONNECTED:
            logger.info("Transcription connection established, ready for Phoenix channels")
        elif event.new_state == ConnectionState.DISCONNECTED:
            # Reset state on disconnect
            self._joined_channel = False
            self._phoenix_ref = 1
            if event.error:
                logger.warning(f"Transcription disconnected due to: {event.error}")

    @property
    def is_connected(self) -> bool:
        """Check if connected to Phoenix server."""
        return self._connection_state == ConnectionState.CONNECTED and self._joined_channel

    async def send_ping(self):
        """Legacy method for compatibility - heartbeat is handled automatically."""
        # This is now handled by the BaseWebSocketClient's heartbeat system
        logger.debug("send_ping called - heartbeat is handled automatically by BaseWebSocketClient")

    # Compatibility methods for existing code
    async def connect(self):
        """Connect to Phoenix WebSocket server."""
        return await super().connect()

    async def disconnect(self):
        """Disconnect from Phoenix WebSocket server."""
        await super().disconnect()

    async def listen(self):
        """Listen for transcription events from Phoenix server."""
        await self.listen_with_reconnect()
