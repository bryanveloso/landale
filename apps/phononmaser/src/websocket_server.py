"""WebSocket server for receiving audio and broadcasting events."""
import asyncio
import json
import logging
import os
import struct
from typing import Set, Optional

import websockets
from websockets.server import WebSocketServerProtocol

from .audio_processor import AudioProcessor, AudioChunk, AudioFormat
from .events import TranscriptionEvent

logger = logging.getLogger(__name__)


class PhononmaserServer:
    """WebSocket server for audio streaming."""

    def __init__(
        self,
        audio_processor: AudioProcessor,
        port: int = 8889
    ):
        self.audio_processor = audio_processor
        self.port = port
        self.clients: Set[WebSocketServerProtocol] = set()
        self.server: Optional[websockets.WebSocketServer] = None

        # Event queue for broadcasting
        self.event_queue: asyncio.Queue[dict] = asyncio.Queue()
        self.broadcast_task: Optional[asyncio.Task] = None

        # Caption clients (for OBS plugin)
        self.caption_clients: Set[WebSocketServerProtocol] = set()

    async def start(self) -> None:
        """Start the WebSocket server."""
        # Start broadcast task
        self.broadcast_task = asyncio.create_task(self._broadcast_loop())

        # Start WebSocket server
        host = os.getenv("PHONONMASER_HOST", "0.0.0.0")  # Listen on all interfaces by default
        self.server = await websockets.serve(
            self.handle_connection,
            host,
            self.port,
            max_size=50 * 1024 * 1024,  # 50MB max message size
            process_request=self.process_request
        )

        logger.info(f"Phononmaser WebSocket server started on {host}:{self.port}")

    async def stop(self) -> None:
        """Stop the WebSocket server."""
        if self.server:
            self.server.close()
            await self.server.wait_closed()

        if self.broadcast_task:
            self.broadcast_task.cancel()
            try:
                await self.broadcast_task
            except asyncio.CancelledError:
                pass

        logger.info("Phononmaser WebSocket server stopped")

    async def process_request(self, path: str, headers) -> Optional[tuple]:
        """Process incoming WebSocket request to determine path."""
        # Accept all paths, we'll handle routing in handle_connection
        return None

    async def handle_connection(
        self,
        websocket: WebSocketServerProtocol
    ) -> None:
        """Handle a new WebSocket connection."""
        path = websocket.path

        if path == "/captions":
            # Handle caption client (OBS plugin)
            await self._handle_caption_client(websocket)
        elif path == "/events":
            # Handle event stream client
            await self._handle_event_client(websocket)
        else:
            # Default: handle as audio source
            await self._handle_audio_source(websocket)

    async def _handle_audio_source(
        self,
        websocket: WebSocketServerProtocol
    ) -> None:
        """Handle audio source connection (OBS WebSocket plugin)."""
        logger.info(f"New audio source connected from {websocket.remote_address}")
        self.clients.add(websocket)

        # Send initial status
        await self._send_status(websocket)

        try:
            async for message in websocket:
                await self._handle_message(websocket, message)
        except websockets.exceptions.ConnectionClosed:
            logger.info("Audio source disconnected")
        except Exception as e:
            logger.error(f"Error handling connection: {e}")
        finally:
            self.clients.discard(websocket)

    async def _handle_event_client(
        self,
        websocket: WebSocketServerProtocol
    ) -> None:
        """Handle event stream client."""
        logger.info(f"New event client connected from {websocket.remote_address}")
        self.clients.add(websocket)

        try:
            # Just keep connection alive, events are broadcast automatically
            await websocket.wait_closed()
        except Exception as e:
            logger.error(f"Error handling event client: {e}")
        finally:
            self.clients.discard(websocket)

    async def _handle_caption_client(
        self,
        websocket: WebSocketServerProtocol
    ) -> None:
        """Handle caption client (OBS caption plugin)."""
        logger.info(f"New caption client connected from {websocket.remote_address}")
        self.caption_clients.add(websocket)

        try:
            # Just keep connection alive, captions are broadcast automatically
            await websocket.wait_closed()
        except Exception as e:
            logger.error(f"Error handling caption client: {e}")
        finally:
            self.caption_clients.discard(websocket)

    async def _handle_message(
        self,
        websocket: WebSocketServerProtocol,
        message: bytes | str
    ) -> None:
        """Handle incoming WebSocket message."""
        try:
            # Handle binary audio data
            if isinstance(message, bytes):
                await self._handle_binary_audio(message)
                return

            # Handle JSON messages
            data = json.loads(message)
            message_type = data.get("type")

            if message_type == "audio_data":
                await self._handle_json_audio(data)
            elif message_type == "start":
                logger.info("Audio streaming started")
                await self.audio_processor.start()
            elif message_type == "stop":
                logger.info("Audio streaming stopped")
                await self.audio_processor.stop()
            elif message_type == "heartbeat":
                # Keep connection alive
                pass

        except json.JSONDecodeError:
            logger.error("Invalid JSON message")
        except Exception as e:
            logger.error(f"Error processing message: {e}")

    async def _handle_binary_audio(self, data: bytes) -> None:
        """Handle binary audio data from OBS plugin."""
        # Minimum size check (header is 28 bytes)
        if len(data) < 28:
            logger.error(f"Binary message too small for header: {len(data)} bytes")
            return

        try:
            # Parse header
            offset = 0
            timestamp_ns = struct.unpack_from("<Q", data, offset)[0]
            timestamp = timestamp_ns // 1000  # Convert nanoseconds to microseconds
            offset += 8
            sample_rate = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            channels = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            bit_depth = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            source_id_len = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            source_name_len = struct.unpack_from("<I", data, offset)[0]
            offset += 4

            # Validate header values
            if sample_rate > 192000 or channels > 8 or bit_depth > 32:
                logger.error(
                    f"Invalid header values: {sample_rate}Hz, "
                    f"{channels}ch, {bit_depth}bit"
                )
                return

            # Parse strings
            source_id = data[offset:offset + source_id_len].decode("utf-8")
            offset += source_id_len
            source_name = data[offset:offset + source_name_len].decode("utf-8")
            offset += source_name_len

            # Extract audio data
            audio_data = data[offset:]

            # Log audio chunk info periodically
            if len(audio_data) > 0 and timestamp % 10000000 < 20000:  # Log every ~10 seconds
                logger.info(
                    f"Audio chunk: {len(audio_data)} bytes, "
                    f"{sample_rate}Hz, {channels}ch, {bit_depth}bit"
                )

            # Auto-start processor if needed
            if not self.audio_processor.is_running:
                logger.info("Auto-starting audio processor")
                await self.audio_processor.start()

            # Add to processor
            chunk = AudioChunk(
                timestamp=timestamp,
                format=AudioFormat(
                    sample_rate=sample_rate,
                    channels=channels,
                    bit_depth=bit_depth
                ),
                data=audio_data,
                source_id=source_id
            )
            self.audio_processor.add_chunk(chunk)

            # Emit chunk event
            await self.event_queue.put({
                "type": "audio:chunk",
                "timestamp": timestamp,
                "source_id": source_id,
                "source_name": source_name,
                "size": len(audio_data)
            })

        except struct.error as e:
            logger.error(f"Error parsing binary header: {e}")

    async def _handle_json_audio(self, data: dict) -> None:
        """Handle JSON audio data."""
        # Decode base64 audio
        audio_bytes = bytes.fromhex(data["data"])

        # Add to processor
        chunk = AudioChunk(
            timestamp=data["timestamp"],
            format=AudioFormat(
                sample_rate=data["format"]["sampleRate"],
                channels=data["format"]["channels"],
                bit_depth=data["format"]["bitDepth"]
            ),
            data=audio_bytes,
            source_id=data["sourceId"]
        )
        self.audio_processor.add_chunk(chunk)

        # Emit chunk event
        await self.event_queue.put({
            "type": "audio:chunk",
            "timestamp": data["timestamp"],
            "source_id": data["sourceId"],
            "source_name": data["sourceName"],
            "size": len(audio_bytes)
        })

    async def _send_status(self, websocket: WebSocketServerProtocol) -> None:
        """Send status message to client."""
        status = {
            "type": "status",
            "connected": True,
            "receiving": self.audio_processor.is_running,
            "bufferSize": self.audio_processor.buffer.total_size,
            "transcribing": self.audio_processor.is_transcribing
        }
        await websocket.send(json.dumps(status))

    async def broadcast_status(self) -> None:
        """Broadcast status to all clients."""
        disconnected = []
        for client in self.clients:
            try:
                await self._send_status(client)
            except websockets.exceptions.ConnectionClosed:
                disconnected.append(client)

        # Remove disconnected clients
        for client in disconnected:
            self.clients.discard(client)

    def emit_transcription(self, event: TranscriptionEvent) -> None:
        """Emit transcription event for broadcasting."""
        try:
            # Emit to general event stream (with duration)
            self.event_queue.put_nowait({
                "type": "audio:transcription",
                "timestamp": event.timestamp,
                "duration": event.duration,
                "text": event.text
            })

            # Also broadcast directly to caption clients (OBS format)
            asyncio.create_task(self._broadcast_caption({
                "type": "audio:transcription",
                "timestamp": event.timestamp,
                "text": event.text,
                "is_final": True  # Always final since we're using whisper.cpp
            }))

        except asyncio.QueueFull:
            logger.warning("Event queue full, dropping transcription event")

    async def _broadcast_caption(self, caption_data: dict) -> None:
        """Broadcast caption data to all caption clients."""
        if not self.caption_clients:
            return

        message = json.dumps(caption_data)
        disconnected = []

        for client in self.caption_clients:
            try:
                await client.send(message)
            except websockets.exceptions.ConnectionClosed:
                disconnected.append(client)
            except Exception as e:
                logger.error(f"Error sending caption to client: {e}")
                disconnected.append(client)

        # Remove disconnected clients
        for client in disconnected:
            self.caption_clients.discard(client)

    async def _broadcast_loop(self) -> None:
        """Broadcast events to all connected clients."""
        while True:
            try:
                event = await self.event_queue.get()
                message = json.dumps(event)

                # Send to all clients
                disconnected = []
                for client in self.clients:
                    try:
                        await client.send(message)
                    except websockets.exceptions.ConnectionClosed:
                        disconnected.append(client)

                # Remove disconnected clients
                for client in disconnected:
                    self.clients.discard(client)

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in broadcast loop: {e}")
