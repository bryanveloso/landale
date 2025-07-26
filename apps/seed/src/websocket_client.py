"""WebSocket clients for connecting to phononmaser and server."""

import json
from collections.abc import Callable
from datetime import datetime

import websockets
from shared import safe_handler
from shared.websockets import BaseWebSocketClient
from websockets.client import WebSocketClientProtocol

from .events import ChatMessage, EmoteEvent, TranscriptionEvent, ViewerInteractionEvent
from .logger import bind_correlation_context, clear_context, get_logger

logger = get_logger(__name__)


class PhononmaserClient(BaseWebSocketClient):
    """WebSocket client for phononmaser audio events."""

    def __init__(self, url: str = "ws://localhost:8889"):
        super().__init__(url)
        self.ws: WebSocketClientProtocol | None = None
        self._handlers = {"audio:transcription": []}

    def on_transcription(self, handler: Callable[[TranscriptionEvent], None]):
        """Register a handler for transcription events."""
        if not callable(handler):
            raise TypeError("Handler must be a callable function or method")
        self._handlers["audio:transcription"].append(handler)

    async def _do_connect(self) -> bool:
        """Perform a single connection attempt."""
        try:
            self.ws = await websockets.connect(self.url)
            logger.info(f"Connected to phononmaser at {self.url}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to phononmaser: {e}")
            return False

    @safe_handler
    async def _do_listen(self):
        """Listen for events from phononmaser."""
        if not self.ws:
            raise RuntimeError("Not connected to phononmaser")

        async for message in self.ws:
            await self._handle_phononmaser_message(message)

    @safe_handler
    async def _handle_phononmaser_message(self, message: str):
        """Handle individual message from phononmaser."""
        try:
            data = json.loads(message)
            event_type = data.get("type")

            # Extract correlation ID if present
            correlation_id = data.get("correlation_id") or f"phono_{data.get('timestamp', 'unknown')}"
            bind_correlation_context(correlation_id=correlation_id)

            if event_type == "audio:transcription":
                event = TranscriptionEvent(
                    timestamp=data["timestamp"],
                    text=data["text"],
                    duration=data["duration"],
                    confidence=data.get("confidence"),
                )

                for handler in self._handlers["audio:transcription"]:
                    self.create_task(handler(event))

        except json.JSONDecodeError:
            logger.error("Invalid JSON received", message_preview=message[:100])
        except Exception as e:
            logger.error("Error processing phononmaser message", error=str(e), exc_info=True)
        finally:
            clear_context()

    async def _do_disconnect(self):
        """Disconnect from phononmaser."""
        if self.ws:
            await self.ws.close()
            self.ws = None


class ServerClient(BaseWebSocketClient):
    """WebSocket client for server chat/emote events."""

    def __init__(self, url: str = "ws://saya:7175/socket/websocket"):
        super().__init__(url)
        self.ws: WebSocketClientProtocol | None = None
        self._handlers = {"chat_message": [], "chat_emote": [], "viewer_interaction": []}

    def on_chat_message(self, handler: Callable[[ChatMessage], None]):
        """Register a handler for chat messages."""
        if not callable(handler):
            raise TypeError("Handler must be a callable function or method")
        self._handlers["chat_message"].append(handler)

    def on_emote(self, handler: Callable[[EmoteEvent], None]):
        """Register a handler for emote events."""
        if not callable(handler):
            raise TypeError("Handler must be a callable function or method")
        self._handlers["chat_emote"].append(handler)

    def on_viewer_interaction(self, handler: Callable[[ViewerInteractionEvent], None]):
        """Register a handler for viewer interaction events."""
        if not callable(handler):
            raise TypeError("Handler must be a callable function or method")
        self._handlers["viewer_interaction"].append(handler)

    async def _do_connect(self) -> bool:
        """Perform a single connection attempt."""
        try:
            self.ws = await websockets.connect(self.url)
            logger.info(f"Connected to server at {self.url}")

            # Join events channel for all events including viewer interactions
            join_message = {"topic": "events:all", "event": "phx_join", "payload": {}, "ref": "1"}
            await self.ws.send(json.dumps(join_message))
            return True
        except Exception as e:
            logger.error(f"Failed to connect to server: {e}")
            return False

    @safe_handler
    async def _do_listen(self):
        """Listen for events from server."""
        if not self.ws:
            raise RuntimeError("Not connected to server")

        async for message in self.ws:
            await self._handle_server_message(message)

    @safe_handler
    async def _handle_server_message(self, message: str):
        """Handle individual message from server."""
        correlation_id = None
        try:
            data = json.loads(message)

            # Extract correlation ID from Phoenix messages
            if isinstance(data, dict):
                correlation_id = data.get("correlation_id") or data.get("ref")
            elif isinstance(data, list) and len(data) >= 2:
                correlation_id = data[1]  # ref field in array format

            if correlation_id:
                bind_correlation_context(correlation_id=str(correlation_id))

        except json.JSONDecodeError:
            logger.error("Invalid JSON received from server", message_preview=message[:100])
            return
        finally:
            if correlation_id:
                clear_context()

        # Handle Phoenix WebSocket messages (object format)
        if isinstance(data, dict):
            topic = data.get("topic")
            event = data.get("event")
            payload = data.get("payload", {})

            # Handle join confirmation
            if event == "phx_reply" and payload.get("status") == "ok":
                logger.info(f"Joined channel: {topic}")
                return

        # Legacy array format handling (keep for compatibility)
        elif isinstance(data, list) and len(data) >= 5:
            join_ref, ref, topic, event, payload = data[:5]

            # Handle join confirmation
            if event == "phx_reply" and payload.get("status") == "ok":
                logger.info("Joined Phoenix channel", topic=topic)
                return

            # Handle specific event types
            if topic == "events:all":
                if event == "chat_message":
                    await self._handle_chat_message(payload)
                elif event in ["follower", "subscription", "gift_subscription", "cheer"]:
                    await self._handle_viewer_interaction(event, payload)

    @safe_handler
    async def _handle_chat_message(self, payload: dict):
        """Process chat message event."""
        event_data = payload.get("data", {})

        # Extract emotes from structured fragment data
        emotes = []
        native_emotes = []
        for fragment in event_data.get("fragments", []):
            if fragment.get("type") == "emote":
                emote_name = fragment.get("text", "")
                emotes.append(emote_name)
                # Track native avalon-prefixed emotes specifically
                if emote_name.startswith("avalon"):
                    native_emotes.append(emote_name)

        # Check if user is subscriber/moderator from badges
        badges = event_data.get("badges", [])
        is_subscriber = any(badge.get("set_id") == "subscriber" for badge in badges)
        is_moderator = any(badge.get("set_id") == "moderator" for badge in badges)

        # Parse timestamp
        timestamp_ms = self._parse_timestamp(event_data.get("timestamp", 0))

        chat_event = ChatMessage(
            timestamp=timestamp_ms,
            username=event_data.get("user_name", ""),
            message=event_data.get("message", ""),
            emotes=emotes,
            native_emotes=native_emotes,
            is_subscriber=is_subscriber,
            is_moderator=is_moderator,
        )

        for handler in self._handlers["chat_message"]:
            self.create_task(handler(chat_event))

    @safe_handler
    async def _handle_viewer_interaction(self, event_type: str, payload: dict):
        """Process viewer interaction event."""
        event_data = payload.get("data", {})

        interaction_event = ViewerInteractionEvent(
            timestamp=int(event_data.get("timestamp", 0)),
            interaction_type=event_type,
            username=event_data.get("user_name", ""),
            user_id=event_data.get("user_id", ""),
            details=event_data,
        )

        for handler in self._handlers["viewer_interaction"]:
            self.create_task(handler(interaction_event))

    def _parse_timestamp(self, timestamp_raw) -> int:
        """Parse timestamp from various formats."""
        if isinstance(timestamp_raw, str):
            try:
                # Handle ISO format (e.g., "2023-10-27T10:00:00Z")
                dt_obj = datetime.fromisoformat(timestamp_raw.replace("Z", "+00:00"))
                return int(dt_obj.timestamp() * 1000)
            except ValueError:
                logger.warning(f"Could not parse timestamp string: {timestamp_raw}")
                return 0
        elif isinstance(timestamp_raw, int | float):
            return int(timestamp_raw)
        else:
            logger.warning(f"Unexpected timestamp format: {type(timestamp_raw)}")
            return 0

    async def _do_disconnect(self):
        """Disconnect from server."""
        if self.ws:
            await self.ws.close()
            self.ws = None
