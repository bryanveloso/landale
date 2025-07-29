"""Main entry point for phononmaser."""

import asyncio
import os
import signal

from dotenv import load_dotenv
from shared import get_global_tracker

from .audio_processor import AudioProcessor
from .health import create_health_app
from .logger import configure_json_logging, get_logger
from .websocket_client import ServerWebSocketClient
from .websocket_server import PhononmaserServer

# Load environment variables
load_dotenv()

# Configure structured JSON logging
configure_json_logging()
logger = get_logger(__name__)


class Phononmaser:
    """Main phononmaser service."""

    def __init__(self):
        # Configuration from environment variables
        self.port = int(os.getenv("PHONONMASER_PORT", "8889"))  # Phononmaser WebSocket port
        self.health_port = int(os.getenv("PHONONMASER_HEALTH_PORT", "8890"))  # Health check port
        self.whisper_model_path = os.getenv("WHISPER_MODEL_PATH", "")
        self.whisper_threads = int(os.getenv("WHISPER_THREADS", "8"))
        self.whisper_language = os.getenv("WHISPER_LANGUAGE", "en")
        self.server_websocket_url = os.getenv("SERVER_WS_URL", "ws://saya:7175/socket/websocket")

        # Validate configuration
        if not self.whisper_model_path:
            raise ValueError("WHISPER_MODEL_PATH environment variable is required")

        # Components
        self.audio_processor: AudioProcessor | None = None
        self.websocket_server: PhononmaserServer | None = None
        self.transcription_client: ServerWebSocketClient | None = None
        self.health_runner = None

        # State
        self.running = False

    async def start(self):
        """Start the phononmaser service."""
        logger.info("Starting phononmaser...")

        # Initialize WebSocket transcription client
        logger.info("Using WebSocket transport for transcription events")
        self.transcription_client = ServerWebSocketClient(self.server_websocket_url)
        await self.transcription_client.connect()

        # Initialize audio processor
        self.audio_processor = AudioProcessor(
            whisper_model_path=self.whisper_model_path,
            whisper_threads=self.whisper_threads,
            whisper_language=self.whisper_language,
        )

        # Initialize WebSocket server
        self.websocket_server = PhononmaserServer(audio_processor=self.audio_processor, port=self.port)

        # Wire up transcription events
        self.audio_processor.transcription_callback = self._handle_transcription

        # Start components
        await self.websocket_server.start()

        # Start health check endpoint
        self.health_runner = await create_health_app(self.health_port)

        self.running = True
        logger.info(f"Phononmaser started on port {self.port}")

    async def stop(self):
        """Stop the phononmaser service."""
        logger.info("Stopping phononmaser...")
        self.running = False

        # Stop components
        if self.audio_processor:
            await self.audio_processor.stop()

        if self.websocket_server:
            await self.websocket_server.stop()

        if self.transcription_client:
            await self.transcription_client.disconnect()

        if self.health_runner:
            await self.health_runner.cleanup()

        logger.info("Phononmaser stopped")

    async def _handle_transcription(self, event):
        """Handle transcription events from audio processor."""
        logger.info(f"Transcription received: {event.text[:50] if event.text else 'empty'}...")

        # Send to Phoenix server for storage and transcription:live channel broadcasting
        if self.transcription_client:
            try:
                success = await self.transcription_client.send_transcription(event)
                if success:
                    logger.debug("Transcription sent via WebSocket successfully")
                else:
                    logger.warning("Failed to send transcription via WebSocket")
            except Exception as e:
                logger.error(f"Error sending transcription via WebSocket: {e}")

        # Emit to local event stream clients for real-time dashboard updates
        if self.websocket_server:
            self.websocket_server.emit_transcription(event)


async def main():
    """Main entry point."""
    service = Phononmaser()

    # Handle shutdown signals
    loop = asyncio.get_event_loop()

    def handle_shutdown():
        logger.info("Received shutdown signal")
        tracker = get_global_tracker()
        tracker.create_task(service.stop(), name="phononmaser_shutdown")

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, handle_shutdown)

    try:
        await service.start()

        # Keep running until stopped
        while service.running:
            await asyncio.sleep(1)

    except Exception as e:
        logger.error(f"Service error: {e}")
        await service.stop()
        raise


if __name__ == "__main__":
    asyncio.run(main())
