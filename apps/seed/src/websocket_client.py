"""WebSocket clients for connecting to phononmaser and server."""

import json
from collections.abc import Callable
from datetime import datetime

import websockets
from shared.websockets import BaseWebSocketClient
from websockets.client import WebSocketClientProtocol

from .events import ChatMessage, EmoteEvent, TranscriptionEvent, ViewerInteractionEvent
from .logger import get_logger

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

    async def _do_listen(self):
        """Listen for events from phononmaser."""
        if not self.ws:
            raise RuntimeError("Not connected to phononmaser")

        async for message in self.ws:
            try:
                data = json.loads(message)
                event_type = data.get("type")

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
                logger.error(f"Invalid JSON received: {message}")
            except Exception as e:
                logger.error(f"Error processing message: {e}")

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

    async def _do_listen(self):
        """Listen for events from server."""
        if not self.ws:
            raise RuntimeError("Not connected to server")

        async for message in self.ws:
            try:
                data = json.loads(message)

                # Handle Phoenix WebSocket messages (object format)
                if isinstance(data, dict):
                    topic = data.get("topic")
                    event = data.get("event")
                    payload = data.get("payload", {})
                    ref = data.get("ref")

                    # Handle join confirmation
                    if event == "phx_reply" and payload.get("status") == "ok":
                        logger.info(f"Joined channel: {topic}")
                        continue

                # Legacy array format handling (keep for compatibility)
                elif isinstance(data, list) and len(data) >= 5:
                    join_ref, ref, topic, event, payload = data[:5]

                    # Handle join confirmation
                    if event == "phx_reply" and payload.get("status") == "ok":
                        logger.info(f"Joined channel: {topic}")
                        continue

                    # Handle chat message events
                    if topic == "events:all" and event == "chat_message":
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
                        timestamp_raw = event_data.get("timestamp", 0)
                        timestamp_ms = 0

                        if isinstance(timestamp_raw, str):
                            try:
                                # Handle ISO format (e.g., "2023-10-27T10:00:00Z")
                                dt_obj = datetime.fromisoformat(timestamp_raw.replace("Z", "+00:00"))
                                timestamp_ms = int(dt_obj.timestamp() * 1000)
                            except ValueError:
                                logger.warning(f"Could not parse timestamp string: {timestamp_raw}")
                                timestamp_ms = 0
                        elif isinstance(timestamp_raw, int | float):
                            timestamp_ms = int(timestamp_raw)
                        else:
                            logger.warning(f"Unexpected timestamp format: {type(timestamp_raw)}")

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

                    # Handle viewer interaction events
                    if topic == "events:all" and event in [
                        "follower",
                        "subscription",
                        "gift_subscription",
                        "cheer",
                    ]:
                        event_data = payload.get("data", {})

                        interaction_event = ViewerInteractionEvent(
                            timestamp=int(event_data.get("timestamp", 0)),
                            interaction_type=event,
                            username=event_data.get("user_name", ""),
                            user_id=event_data.get("user_id", ""),
                            details=event_data,
                        )

                        for handler in self._handlers["viewer_interaction"]:
                            self.create_task(handler(interaction_event))

            except json.JSONDecodeError:
                logger.error(f"Invalid JSON received: {message}")
            except Exception as e:
                logger.error(f"Error processing message: {e}")

    async def _do_disconnect(self):
        """Disconnect from server."""
        if self.ws:
            await self.ws.close()
            self.ws = None
