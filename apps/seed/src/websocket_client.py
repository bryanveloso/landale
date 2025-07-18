"""WebSocket clients for connecting to phononmaser and server."""

import asyncio
import json
import logging
from collections.abc import Callable

import websockets
from websockets.client import WebSocketClientProtocol

from .events import ChatMessage, EmoteEvent, TranscriptionEvent, ViewerInteractionEvent

logger = logging.getLogger(__name__)


class PhononmaserClient:
    """WebSocket client for phononmaser audio events."""

    def __init__(self, url: str = "ws://localhost:8889"):
        self.url = url
        self.ws: WebSocketClientProtocol | None = None
        self._handlers = {"audio:transcription": []}

    def on_transcription(self, handler: Callable[[TranscriptionEvent], None]):
        """Register a handler for transcription events."""
        self._handlers["audio:transcription"].append(handler)

    async def connect(self):
        """Connect to phononmaser WebSocket."""
        try:
            self.ws = await websockets.connect(self.url)
            logger.info(f"Connected to phononmaser at {self.url}")
        except Exception as e:
            logger.error(f"Failed to connect to phononmaser: {e}")
            raise

    async def listen(self):
        """Listen for events from phononmaser."""
        if not self.ws:
            raise RuntimeError("Not connected to phononmaser")

        try:
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
                            await asyncio.create_task(handler(event))

                except json.JSONDecodeError:
                    logger.error(f"Invalid JSON received: {message}")
                except Exception as e:
                    logger.error(f"Error processing message: {e}")

        except websockets.exceptions.ConnectionClosed:
            logger.info("Connection to phononmaser closed")

    async def disconnect(self):
        """Disconnect from phononmaser."""
        if self.ws:
            await self.ws.close()


class ServerClient:
    """WebSocket client for server chat/emote events."""

    def __init__(self, url: str = "ws://saya:7175/socket/websocket"):
        self.url = url
        self.ws: WebSocketClientProtocol | None = None
        self._handlers = {"chat_message": [], "chat_emote": [], "viewer_interaction": []}

    def on_chat_message(self, handler: Callable[[ChatMessage], None]):
        """Register a handler for chat messages."""
        self._handlers["chat_message"].append(handler)

    def on_emote(self, handler: Callable[[EmoteEvent], None]):
        """Register a handler for emote events."""
        self._handlers["chat_emote"].append(handler)

    def on_viewer_interaction(self, handler: Callable[[ViewerInteractionEvent], None]):
        """Register a handler for viewer interaction events."""
        self._handlers["viewer_interaction"].append(handler)

    async def connect(self):
        """Connect to server WebSocket."""
        try:
            self.ws = await websockets.connect(self.url)
            logger.info(f"Connected to server at {self.url}")

            # Join events channel for all events including viewer interactions
            join_message = {"topic": "events:all", "event": "phx_join", "payload": {}, "ref": "1"}
            await self.ws.send(json.dumps(join_message))
        except Exception as e:
            logger.error(f"Failed to connect to server: {e}")
            raise

    async def listen(self):
        """Listen for events from server."""
        if not self.ws:
            raise RuntimeError("Not connected to server")

        try:
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

                            chat_event = ChatMessage(
                                timestamp=int(event_data["timestamp"].timestamp() * 1000)
                                if isinstance(event_data.get("timestamp"), dict)
                                else int(data.get("timestamp", 0)),
                                username=event_data.get("user_name", ""),
                                message=event_data.get("message", ""),
                                emotes=emotes,
                                native_emotes=native_emotes,
                                is_subscriber=is_subscriber,
                                is_moderator=is_moderator,
                            )

                            for handler in self._handlers["chat_message"]:
                                await asyncio.create_task(handler(chat_event))

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
                                await asyncio.create_task(handler(interaction_event))

                except json.JSONDecodeError:
                    logger.error(f"Invalid JSON received: {message}")
                except Exception as e:
                    logger.error(f"Error processing message: {e}")

        except websockets.exceptions.ConnectionClosed:
            logger.info("Connection to server closed")

    async def disconnect(self):
        """Disconnect from server."""
        if self.ws:
            await self.ws.close()
