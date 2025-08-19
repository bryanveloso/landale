"""Main entry point for the SEED intelligence service."""

import asyncio

from dotenv import load_dotenv
from shared import get_global_tracker
from shared.logger import configure_json_logging, get_logger
from shared.supervisor import RestartStrategy, ServiceConfig, SupervisedService, run_with_supervisor

from .config import get_config
from .context_client import ContextClient
from .correlator import StreamCorrelator
from .events import AnalysisResult, ChatMessage, EmoteEvent, TranscriptionEvent, ViewerInteractionEvent
from .health import create_health_app
from .lms_client import LMSClient
from .rag_handler import RAGHandler
from .rag_websocket import setup_rag_websocket_handlers
from .transcription_client import TranscriptionWebSocketClient
from .websocket_client import ServerClient

# Load environment variables
load_dotenv()

# Get configuration
config = get_config()

# Configure structured JSON logging
configure_json_logging(
    service_name="seed", level=config.log_level, json_output=config.json_logs, component="intelligence"
)
logger = get_logger(__name__)


class SeedService(SupervisedService):
    """Main SEED intelligence service that coordinates all components."""

    def __init__(self):
        # Store config
        self.config = config

        # Log configuration on startup
        logger.info(f"Starting {self.config.service_name} with configuration:")
        logger.info(self.config.to_dict())

        # Components initialized from config
        self.transcription_client = TranscriptionWebSocketClient(self.config.websocket.server_ws_url)
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
        self.rag_handler: RAGHandler | None = None

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

        # Initialize RAG handler for query interface
        self.rag_handler = RAGHandler(
            context_client=self.context_client,
            server_url=self.config.websocket.server_url.replace("ws://", "http://").replace("/events", ""),
        )
        await self.rag_handler.__aenter__()

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

        # Start health check endpoint with service references and RAG handler
        self.health_runner = await create_health_app(
            port=self.config.health.port, service=self, correlator=self.correlator, rag_handler=self.rag_handler
        )

        # Set up WebSocket handlers for RAG queries if server is connected
        if self.rag_handler and (hasattr(self.server_client, "connected") and self.server_client.connected):
            setup_rag_websocket_handlers(self.server_client, self.rag_handler)
            logger.info("RAG WebSocket handlers registered")

        # Start listening tasks
        tracker = get_global_tracker()
        self.tasks = [
            tracker.create_task(self.transcription_client.listen_with_reconnect(), name="seed_transcription_listener"),
            tracker.create_task(self.server_client.listen_with_reconnect(), name="seed_server_listener"),
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

        # Cleanup RAG handler
        if self.rag_handler:
            await self.rag_handler.__aexit__(None, None, None)

        # Cleanup health endpoint
        if self.health_runner:
            try:
                await self.health_runner.cleanup()
            except Exception as e:
                logger.warning(f"Health runner cleanup error (non-critical): {e}")

        logger.info("SEED intelligence service stopped")

    async def health_check(self) -> bool:
        """Check if the SEED service is healthy."""
        try:
            # Check if service is running
            if not self.running:
                return False

            # Check transcription client connection
            if self.transcription_client and not await self.transcription_client.health_check():
                logger.warning("Transcription client connection unhealthy")
                return False

            # Check server client connection (optional, non-critical)
            if self.server_client:
                server_healthy = await self.server_client.health_check()
                if not server_healthy:
                    logger.debug("Server client connection unhealthy (non-critical)")

            # Check LMS client
            if not self.lms_client:
                return False

            # Check correlator
            if not self.correlator:
                return False

            # Check buffer health if available
            if hasattr(self.correlator, "get_buffer_stats"):
                try:
                    stats = self.correlator.get_buffer_stats()
                    # Check for buffer overflow or other issues
                    for buffer_name, size in stats.get("buffer_sizes", {}).items():
                        limit = stats.get("buffer_limits", {}).get(buffer_name, 1000)
                        if size > limit * 0.9:  # 90% full
                            logger.warning(f"Buffer {buffer_name} nearly full: {size}/{limit}")
                except Exception as e:
                    logger.debug(f"Could not check buffer stats: {e}")

            return True

        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return False

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
    """Main entry point with supervisor pattern."""
    logger.info("Starting SEED service with supervisor...")

    # Create service instance
    service = SeedService()

    # Create service configuration with restart policy
    config = ServiceConfig(
        name="seed",
        restart_strategy=RestartStrategy.ON_FAILURE,
        max_restarts=5,
        restart_window_seconds=300,  # 5 minutes
        restart_delay_seconds=5.0,  # Longer delay for AI service
        restart_delay_max=60.0,
        health_check_interval=45.0,  # Less frequent for AI service
        shutdown_timeout=30.0,  # More time for AI cleanup
    )

    # Run with supervisor
    await run_with_supervisor([(service, config)])


if __name__ == "__main__":
    asyncio.run(main())
