"""Main entry point for the SEED intelligence service."""

import asyncio
import signal

from dotenv import load_dotenv
from shared import get_global_tracker

from .config import get_config
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

# Get configuration
config = get_config()

# Configure structured JSON logging based on config
configure_json_logging(level=config.log_level, json_output=config.json_logs)
logger = get_logger(__name__)


class SeedService:
    """Main SEED intelligence service that coordinates all components."""

    def __init__(self):
        # Store config
        self.config = config

        # Log configuration on startup
        logger.info(f"Starting {self.config.service_name} with configuration:")
        logger.info(self.config.to_dict())

        # Components initialized from config
        self.transcription_client = TranscriptionWebSocketClient(self.config.get_phononmaser_url())
        self.server_client = ServerClient(self.config.get_server_events_url())
        self.lms_client = LMSClient(
            api_url=self.config.lms.api_url,
            model=self.config.lms.model,
            rate_limit=self.config.lms.rate_limit,
            rate_window=self.config.lms.rate_window,
        )
        self.context_client = ContextClient(
            self.config.websocket.server_url.replace("ws://", "http://").replace("/events", "")
        )
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

        # Initialize correlator with context client and config
        self.correlator = StreamCorrelator(
            lms_client=self.lms_client,
            context_client=self.context_client,
            context_window_seconds=self.config.correlator.context_window_seconds,
            analysis_interval_seconds=self.config.correlator.analysis_interval_seconds,
            correlation_window_seconds=self.config.correlator.correlation_window_seconds,
            max_buffer_size=self.config.correlator.max_buffer_size,
        )

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

        # Start health check endpoint with service references
        self.health_runner = await create_health_app(
            port=self.config.health.port, service=self, correlator=self.correlator
        )

        # Start listening tasks
        tracker = get_global_tracker()
        self.tasks = [
            tracker.create_task(self.transcription_client.listen(), name="seed_transcription_listener"),
            tracker.create_task(self.server_client.listen(), name="seed_server_listener"),
            tracker.create_task(self.correlator.periodic_analysis_loop(), name="seed_correlator_loop"),
            tracker.create_task(self._health_check_loop(), name="seed_health_check_loop"),
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
        logger.debug(
            "Received transcription",
            text_preview=event.text[:50] + "..." if len(event.text) > 50 else event.text,
            duration=f"{event.duration:.1f}s",
            confidence=event.confidence,
        )

        # Add to correlator for analysis
        if self.correlator:
            await self.correlator.add_transcription(event)

    async def _handle_chat_message(self, event: ChatMessage):
        """Handle chat message events from server."""
        logger.debug(
            "Received chat message",
            username=event.username,
            message_preview=event.message[:50] + "..." if len(event.message) > 50 else event.message,
            emote_count=len(event.emotes),
            is_subscriber=event.is_subscriber,
        )

        if self.correlator:
            await self.correlator.add_chat_message(event)

    async def _handle_emote(self, event: EmoteEvent):
        """Handle emote events from server."""
        logger.debug(
            "Received emote event", username=event.username, emote_name=event.emote_name, emote_id=event.emote_id
        )

        if self.correlator:
            await self.correlator.add_emote(event)

    async def _handle_viewer_interaction(self, event: ViewerInteractionEvent):
        """Handle viewer interaction events from server."""
        logger.debug(
            "Received viewer interaction",
            interaction_type=event.interaction_type,
            username=event.username,
            user_id=event.user_id,
        )

        if self.correlator:
            await self.correlator.add_viewer_interaction(event)

    async def _handle_analysis_result(self, result: AnalysisResult):
        """Handle analysis results from correlator."""
        # Log comprehensive analysis result with structured data
        analysis_data = {
            "sentiment": result.sentiment,
            "sentiment_trajectory": result.sentiment_trajectory,
            "topics": result.topics,
            "context_summary": result.context[:100] + "..." if len(result.context) > 100 else result.context,
        }

        if result.patterns:
            analysis_data.update(
                {
                    "energy_level": result.patterns.energy_level,
                    "engagement_depth": result.patterns.engagement_depth,
                    "community_sync": result.patterns.community_sync,
                    "content_focus": result.patterns.content_focus,
                    "temporal_flow": result.patterns.temporal_flow,
                }
            )

        if result.chat_velocity:
            analysis_data["chat_velocity"] = f"{result.chat_velocity:.1f} msg/min"

        if result.emote_frequency:
            analysis_data["top_emotes"] = list(result.emote_frequency.keys())[:5]

        logger.info("Analysis result received", **analysis_data)

        # Future enhancements for training data pipeline
        # - Export rich context data for training datasets
        # - Build personalized pattern detection from accumulated data
        # - Train specialized models on your streaming patterns

    async def _health_check_loop(self):
        """Periodic health check."""
        while self.running:
            await asyncio.sleep(60)  # Every minute

            # Get buffer stats if available
            health_info = {
                "status": "running",
                "uptime_minutes": int((asyncio.get_event_loop().time() - self._start_time) / 60)
                if hasattr(self, "_start_time")
                else 0,
            }

            if self.correlator:
                try:
                    buffer_stats = self.correlator.get_buffer_stats()
                    health_info["buffer_usage"] = {
                        name: f"{size}/{limit}"
                        for name, size in buffer_stats["buffer_sizes"].items()
                        for limit_name, limit in buffer_stats["buffer_limits"].items()
                        if name == limit_name
                    }
                    health_info["total_events"] = buffer_stats["total_events"]
                except Exception as e:
                    health_info["buffer_error"] = str(e)

            logger.info("Periodic health check", **health_info)


async def main():
    """Main entry point."""
    service = SeedService()

    # Handle shutdown signals
    loop = asyncio.get_event_loop()

    def handle_shutdown():
        logger.info("Received shutdown signal")
        tracker = get_global_tracker()
        tracker.create_task(service.stop(), name="seed_shutdown")

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, handle_shutdown)

    try:
        service._start_time = asyncio.get_event_loop().time()
        await service.start()

        # Keep running until stopped
        while service.running:
            await asyncio.sleep(1)

    except Exception as e:
        logger.error(f"Service error: {e}")
        await service.stop()


if __name__ == "__main__":
    asyncio.run(main())
