"""WebSocket server for receiving audio and broadcasting events."""

import asyncio
import contextlib
import json
import logging
import struct
import weakref

import websockets
from shared import error_boundary, get_global_tracker, safe_handler
from websockets.server import WebSocketServerProtocol

from .audio_processor import AudioChunk, AudioFormat, AudioProcessor
from .events import TranscriptionEvent
from .logger import get_logger
from .service_config import _config as phononmaser_config

logger = get_logger(__name__)


class PhononmaserServer:
    """WebSocket server for audio streaming."""

    def __init__(self, audio_processor: AudioProcessor, port: int = 8889):
        self.audio_processor = audio_processor
        self.port = port
        self.clients: set[WebSocketServerProtocol] = set()
        self.server: websockets.WebSocketServer | None = None

        # Event queue for broadcasting with size limit to prevent memory exhaustion
        # Size of 200 allows ~20 seconds of buffer at 10 events/sec
        self.event_queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=200)
        self.broadcast_task: asyncio.Task | None = None

        # Metrics for monitoring queue health
        self.dropped_events_count = 0

        # Track background tasks to prevent silent failures
        self.background_tasks: weakref.WeakSet = weakref.WeakSet()

        # Store main event loop for thread-safe operations
        self.main_loop: asyncio.AbstractEventLoop | None = None

    async def start(self) -> None:
        """Start the WebSocket server."""
        # Store the main event loop for thread-safe operations
        self.main_loop = asyncio.get_running_loop()

        # Start broadcast task
        tracker = get_global_tracker()
        self.broadcast_task = tracker.create_task(self._broadcast_loop(), name="websocket_broadcast_loop")

        # Start WebSocket server
        host = phononmaser_config.bind_host  # Use the bind_host from shared configuration
        self.server = await websockets.serve(
            self.handle_connection,
            host,
            self.port,
            max_size=50 * 1024 * 1024,  # 50MB max message size
            process_request=self.process_request,
        )

        logger.info(f"Phononmaser WebSocket server started on {host}:{self.port}")

    async def stop(self) -> None:
        """Stop the WebSocket server."""
        if self.server:
            self.server.close()
            await self.server.wait_closed()

        if self.broadcast_task:
            self.broadcast_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.broadcast_task

        # Clean up any remaining background tasks
        if self.background_tasks:
            tasks = list(self.background_tasks)
            for task in tasks:
                task.cancel()
            # Wait for cancellation with timeout
            await asyncio.wait(tasks, timeout=5.0)

        logger.info("Phononmaser WebSocket server stopped")

    async def process_request(self, _path: str, _headers) -> tuple | None:
        """Process incoming WebSocket request to determine path."""
        # Accept all paths, we'll handle routing in handle_connection
        return None

    async def handle_connection(self, websocket: WebSocketServerProtocol) -> None:
        """Handle a new WebSocket connection."""
        path = websocket.request.path

        if path == "/events":
            # Handle event stream client
            await self._handle_event_client(websocket)
        else:
            # Default: handle as audio source
            await self._handle_audio_source(websocket)

    async def _handle_audio_source(self, websocket: WebSocketServerProtocol) -> None:
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

    async def _handle_event_client(self, websocket: WebSocketServerProtocol) -> None:
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

    @safe_handler
    async def _handle_message(self, _websocket: WebSocketServerProtocol, message: bytes | str) -> None:
        """Handle incoming WebSocket message."""
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

    @safe_handler
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
                logger.error(f"Invalid header values: {sample_rate}Hz, {channels}ch, {bit_depth}bit")
                return

            # Parse strings
            source_id = data[offset : offset + source_id_len].decode("utf-8")
            offset += source_id_len
            source_name = data[offset : offset + source_name_len].decode("utf-8")
            offset += source_name_len

            # Extract audio data
            audio_data = data[offset:]

            # Log audio chunk info periodically
            if len(audio_data) > 0 and timestamp % 10000000 < 20000:  # Log every ~10 seconds
                logger.info(f"Audio chunk: {len(audio_data)} bytes, {sample_rate}Hz, {channels}ch, {bit_depth}bit")

            # Auto-start processor if needed
            if not self.audio_processor.is_running:
                logger.info("Auto-starting audio processor")
                await self.audio_processor.start()

            # Add to processor
            chunk = AudioChunk(
                timestamp=timestamp,
                format=AudioFormat(sample_rate=sample_rate, channels=channels, bit_depth=bit_depth),
                data=audio_data,
                source_id=source_id,
            )
            self.audio_processor.add_chunk(chunk)

            # Emit chunk event
            await self._emit_event(
                {
                    "type": "audio:chunk",
                    "timestamp": timestamp,
                    "source_id": source_id,
                    "source_name": source_name,
                    "size": len(audio_data),
                }
            )

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
                bit_depth=data["format"]["bitDepth"],
            ),
            data=audio_bytes,
            source_id=data["sourceId"],
        )
        self.audio_processor.add_chunk(chunk)

        # Emit chunk event
        await self._emit_event(
            {
                "type": "audio:chunk",
                "timestamp": data["timestamp"],
                "source_id": data["sourceId"],
                "source_name": data["sourceName"],
                "size": len(audio_bytes),
            }
        )

    async def _send_status(self, websocket: WebSocketServerProtocol) -> None:
        """Send status message to client."""
        status = {
            "type": "status",
            "connected": True,
            "receiving": self.audio_processor.is_running,
            "bufferSize": self.audio_processor.buffer.total_size,
            "transcribing": self.audio_processor.is_transcribing,
            "droppedEvents": self.dropped_events_count,
            "queueSize": self.event_queue.qsize(),
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

    async def _emit_event(self, event_dict: dict) -> bool:
        """Emit event to queue with overflow protection.

        Returns True if event was queued, False if dropped.
        Uses drop-newest strategy for simplicity and thread safety.
        """
        try:
            # Try non-blocking add
            self.event_queue.put_nowait(event_dict)
            return True
        except asyncio.QueueFull:
            # Queue is full - drop the new event
            logger.warning(f"Event queue full, dropping new event: {event_dict.get('type', 'unknown')}")
            self.dropped_events_count += 1
            return False

    @error_boundary(log_level=logging.WARNING)
    def emit_transcription(self, event: TranscriptionEvent) -> None:
        """Emit transcription event for broadcasting."""
        event_dict = {
            "type": "audio:transcription",
            "timestamp": event.timestamp,
            "duration": event.duration,
            "text": event.text,
        }

        # Use async-safe emission (this is called from sync context)
        tracker = get_global_tracker()
        try:
            # Create and track the task
            task = tracker.create_task(self._emit_event(event_dict), name="emit_transcription_event")
            self.background_tasks.add(task)
            # Task removes itself from the set when done
            task.add_done_callback(self.background_tasks.discard)
        except RuntimeError:
            # Called from different thread - use thread-safe scheduling
            if hasattr(self, "main_loop") and self.main_loop and self.main_loop.is_running():
                # Schedule the event emission on the main event loop thread
                def create_emit_task():
                    task = tracker.create_task(self._emit_event(event_dict), name="emit_transcription_event_threadsafe")
                    self.background_tasks.add(task)
                    task.add_done_callback(self.background_tasks.discard)

                self.main_loop.call_soon_threadsafe(create_emit_task)
            else:
                logger.error("No main event loop running to schedule transcription event")
                self.dropped_events_count += 1

    @safe_handler
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
                await asyncio.sleep(0.1)  # Add a small delay to prevent busy-waiting
