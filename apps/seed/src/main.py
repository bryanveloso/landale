"""Main entry point for the SEED intelligence service."""

import asyncio
import os
import signal

from dotenv import load_dotenv

from .context_client import ContextClient
from .correlator import StreamCorrelator
from .events import AnalysisResult, ChatMessage, EmoteEvent, TranscriptionEvent, ViewerInteractionEvent
from .health import create_health_app
from .lms_client import LMSClient
from .logger import configure_json_logging, get_logger
from .transcription_client import TranscriptionWebSocketClient
from .websocket_client import ServerClient

# Load environment variables
load_dotenv()

# Configure structured JSON logging
configure_json_logging()
logger = get_logger(__name__)


class SeedService:
    """Main SEED intelligence service that coordinates all components."""

    def __init__(self):
        # Configuration - hardcoded URLs for single-user setup with env overrides
        self.server_events_url = os.getenv("SERVER_URL", "http://zelan:8080")
        self.server_ws_url = os.getenv("SERVER_WS_URL", "ws://zelan:7175")
        self.lms_url = os.getenv("LMS_API_URL", "http://zelan:1234/v1")
        self.lms_model = os.getenv("LMS_MODEL", "meta/llama-3.3-70b")

        # Components
        self.transcription_client = TranscriptionWebSocketClient(self.server_ws_url)
        # Convert HTTP URL to WebSocket URL for server events
        server_ws_events_url = (
            self.server_ws_url.replace("/socket", "/socket/websocket")
            if "/socket" in self.server_ws_url
            else f"{self.server_ws_url}/socket/websocket"
        )
        self.server_client = ServerClient(server_ws_events_url)
        self.lms_client = LMSClient(self.lms_url, self.lms_model)
        self.context_client = ContextClient(self.server_events_url.replace("ws://", "http://").replace("/events", ""))
        self.correlator: StreamCorrelator | None = None

        # State
        self.running = False
        self.tasks = []
        self.health_runner = None

    async def start(self):
        """Start the SEED intelligence service."""
        logger.info("Starting SEED intelligence service...")

        # Initialize LMS client
        await self.lms_client.__aenter__()

        # Initialize context client
        await self.context_client.__aenter__()

        # Initialize correlator with context client
        self.correlator = StreamCorrelator(self.lms_client, self.context_client)

        # Register event handlers
        self.transcription_client.on_transcription(self._handle_transcription)
        self.server_client.on_chat_message(self._handle_chat_message)
        self.server_client.on_emote(self._handle_emote)
        self.server_client.on_viewer_interaction(self._handle_viewer_interaction)
        self.correlator.on_analysis(self._handle_analysis_result)

        # Connect to services
        try:
            await self.transcription_client.connect()
            logger.info("Connected to transcription service")
        except Exception as e:
            logger.error(f"Failed to connect to transcription service: {e}")
            raise

        # Try to connect to server, but don't fail if it's not available
        try:
            await self.server_client.connect()
            logger.info("Connected to server")
        except Exception as e:
            logger.warning(f"Could not connect to server (will work without chat events): {e}")

        self.running = True

        # Start health check endpoint
        health_port = 8891  # Hardcoded health port for single-user setup
        self.health_runner = await create_health_app(port=health_port)

        # Start listening tasks
        self.tasks = [
            asyncio.create_task(self.transcription_client.listen()),
            asyncio.create_task(self.server_client.listen()),
            asyncio.create_task(self.correlator.periodic_analysis_loop()),
            asyncio.create_task(self._health_check_loop()),
        ]

        logger.info("SEED intelligence service started successfully")

    async def stop(self):
        """Stop the SEED intelligence service."""
        logger.info("Stopping SEED intelligence service...")
        self.running = False

        # Cancel tasks
        for task in self.tasks:
            task.cancel()

        # Wait for tasks to complete
        await asyncio.gather(*self.tasks, return_exceptions=True)

        # Disconnect clients
        await self.transcription_client.disconnect()
        await self.server_client.disconnect()
        await self.lms_client.__aexit__(None, None, None)
        await self.context_client.__aexit__(None, None, None)

        # Cleanup health endpoint
        if self.health_runner:
            try:
                await self.health_runner.cleanup()
            except Exception as e:
                logger.warning(f"Health runner cleanup error (non-critical): {e}")

        logger.info("SEED intelligence service stopped")

    async def _handle_transcription(self, event: TranscriptionEvent):
        """Handle transcription events from Phoenix server."""
        logger.debug(f"Transcription: {event.text}")

        # Add to correlator for analysis
        if self.correlator:
            await self.correlator.add_transcription(event)

    async def _handle_chat_message(self, event: ChatMessage):
        """Handle chat message events from server."""
        logger.debug(f"Chat: {event.username}: {event.message}")

        if self.correlator:
            await self.correlator.add_chat_message(event)

    async def _handle_emote(self, event: EmoteEvent):
        """Handle emote events from server."""
        logger.debug(f"Emote: {event.username} used {event.emote_name}")

        if self.correlator:
            await self.correlator.add_emote(event)

    async def _handle_viewer_interaction(self, event: ViewerInteractionEvent):
        """Handle viewer interaction events from server."""
        logger.debug(f"Viewer interaction: {event.interaction_type} from {event.username}")

        if self.correlator:
            await self.correlator.add_viewer_interaction(event)

    async def _handle_analysis_result(self, result: AnalysisResult):
        """Handle analysis results from correlator."""
        logger.info(f"Analysis result: {result.sentiment} sentiment")

        # Log detailed results with new flexible patterns
        logger.info(f"Topics: {result.topics}")
        if result.patterns:
            logger.info(f"Energy level: {result.patterns.energy_level:.2f}")
            logger.info(f"Engagement depth: {result.patterns.engagement_depth:.2f}")
            logger.info(f"Community sync: {result.patterns.community_sync:.2f}")
            logger.info(f"Content focus: {result.patterns.content_focus}")
            logger.info(f"Temporal flow: {result.patterns.temporal_flow}")
        if result.chat_velocity:
            logger.info(f"Chat velocity: {result.chat_velocity:.1f} msg/min")
        if result.emote_frequency:
            logger.info(f"Top emotes: {list(result.emote_frequency.keys())[:5]}")

        # Future enhancements for training data pipeline
        # - Export rich context data for training datasets
        # - Build personalized pattern detection from accumulated data
        # - Train specialized models on your streaming patterns

    async def _health_check_loop(self):
        """Periodic health check."""
        while self.running:
            await asyncio.sleep(60)  # Every minute
            logger.info("Health check: Service is running")


async def main():
    """Main entry point."""
    service = SeedService()

    # Handle shutdown signals
    loop = asyncio.get_event_loop()

    def handle_shutdown():
        logger.info("Received shutdown signal")
        asyncio.create_task(service.stop())

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


if __name__ == "__main__":
    asyncio.run(main())
