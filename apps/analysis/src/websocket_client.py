"""WebSocket clients for connecting to phononmaser and server."""
import asyncio
import json
import logging
from typing import Callable, Optional
import websockets
from websockets.client import WebSocketClientProtocol

from .events import TranscriptionEvent, ChatMessage, EmoteEvent

logger = logging.getLogger(__name__)


class PhononmaserClient:
    """WebSocket client for phononmaser audio events."""

    def __init__(self, url: str = "ws://localhost:8889"):
        self.url = url
        self.ws: Optional[WebSocketClientProtocol] = None
        self._handlers = {
            "audio:transcription": []
        }

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
                            confidence=data.get("confidence")
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

    def __init__(self, url: str = "ws://saya:7175/events"):
        self.url = url
        self.ws: Optional[WebSocketClientProtocol] = None
        self._handlers = {
            "chat:message": [],
            "chat:emote": []
        }

    def on_chat_message(self, handler: Callable[[ChatMessage], None]):
        """Register a handler for chat messages."""
        self._handlers["chat:message"].append(handler)

    def on_emote(self, handler: Callable[[EmoteEvent], None]):
        """Register a handler for emote events."""
        self._handlers["chat:emote"].append(handler)

    async def connect(self):
        """Connect to server WebSocket."""
        try:
            self.ws = await websockets.connect(self.url)
            logger.info(f"Connected to server at {self.url}")

            # Subscribe to chat events
            await self.ws.send(json.dumps({
                "type": "subscribe",
                "channels": ["chat:message", "chat:emote"]
            }))
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
                    msg_type = data.get("type")

                    # Handle connection confirmation
                    if msg_type == "connected":
                        logger.info(f"Server confirmed connection: {data.get('id')}")
                        continue

                    # Handle subscription confirmation
                    if msg_type == "subscribed":
                        logger.info(f"Subscribed to channels: {data.get('channels')}")
                        continue

                    # Handle events
                    if msg_type == "event":
                        channel = data.get("channel")
                        event_data = data.get("event")

                        if channel == "chat:message":
                            event = ChatMessage(
                                timestamp=event_data["timestamp"],
                                username=event_data["username"],
                                message=event_data["message"],
                                emotes=event_data.get("emotes", []),
                                is_subscriber=event_data.get("is_subscriber", False),
                                is_moderator=event_data.get("is_moderator", False)
                            )

                            for handler in self._handlers["chat:message"]:
                                await asyncio.create_task(handler(event))

                        elif channel == "chat:emote":
                            event = EmoteEvent(
                                timestamp=event_data["timestamp"],
                                username=event_data["username"],
                                emote_name=event_data["emote_name"],
                                emote_id=event_data.get("emote_id")
                            )

                            for handler in self._handlers["chat:emote"]:
                                await asyncio.create_task(handler(event))

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
