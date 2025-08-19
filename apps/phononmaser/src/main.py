"""Main entry point for phononmaser."""

import asyncio
import os
import sys

from dotenv import load_dotenv
from shared.config import PhononmaserConfig
from shared.supervisor import RestartStrategy, ServiceConfig, SupervisedService, run_with_supervisor

from .audio_processor import AudioProcessor
from .health import create_health_app
from .logger import configure_json_logging, get_logger
from .prompt_manager import PromptManager
from .websocket_client import ServerWebSocketClient
from .websocket_server import PhononmaserServer

# Load environment variables
load_dotenv()

# Configure structured JSON logging
configure_json_logging()
logger = get_logger(__name__)


class Phononmaser(SupervisedService):
    """Main phononmaser service with supervisor support."""

    def __init__(self):
        # Load configuration with validation
        self.config = PhononmaserConfig()

        # Validate configuration
        validation_errors = self.config.validate()
        if validation_errors:
            for error in validation_errors:
                logger.error(f"Configuration error: {error}")
            sys.exit(1)

        # Configuration from environment variables (backward compatibility)
        self.port = self.config.get_env_int("PHONONMASER_PORT", self.config.port)
        self.health_port = self.config.get_env_int("PHONONMASER_HEALTH_PORT", self.config.health_port)
        self.whisper_model_path = os.getenv("WHISPER_MODEL_PATH", "")
        self.whisper_threads = self.config.get_env_int("WHISPER_THREADS", 8)
        self.whisper_language = os.getenv("WHISPER_LANGUAGE", "en")
        self.server_websocket_url = os.getenv("SERVER_WS_URL", self.config.server_url)

        # PromptManager configuration (optional)
        self.enable_prompt_manager = self.config.get_env_bool("ENABLE_PROMPT_MANAGER", True)
        self.phoenix_base_url = os.getenv(
            "PHOENIX_BASE_URL", f"http://{self.config.server_host}:{self.config.server_tcp_port}"
        )

        # Validate required configuration
        if not self.whisper_model_path:
            logger.error(
                "WHISPER_MODEL_PATH environment variable is required. "
                "Set it to the path of your Whisper model file (e.g., /path/to/ggml-base.bin)"
            )
            sys.exit(1)

        # Validate whisper model path exists
        if not os.path.exists(self.whisper_model_path):
            logger.error(
                f"Whisper model file not found at: {self.whisper_model_path}. "
                "Please check the WHISPER_MODEL_PATH environment variable."
            )
            sys.exit(1)

        # Components
        self.audio_processor: AudioProcessor | None = None
        self.websocket_server: PhononmaserServer | None = None
        self.transcription_client: ServerWebSocketClient | None = None
        self.prompt_manager: PromptManager | None = None
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

        # Initialize PromptManager if enabled
        if self.enable_prompt_manager:
            logger.info("Initializing PromptManager for dynamic prompting")
            self.prompt_manager = PromptManager(phoenix_base_url=self.phoenix_base_url)
            await self.prompt_manager.start()
        else:
            logger.info("PromptManager disabled - using basic transcription")

        # Initialize audio processor
        self.audio_processor = AudioProcessor(
            whisper_model_path=self.whisper_model_path,
            whisper_threads=self.whisper_threads,
            whisper_language=self.whisper_language,
            prompt_manager=self.prompt_manager,
        )

        # Initialize WebSocket server
        self.websocket_server = PhononmaserServer(audio_processor=self.audio_processor, port=self.port)

        # Wire up transcription events
        self.audio_processor.transcription_callback = self._handle_transcription

        # Start components
        await self.websocket_server.start()

        # Start health check endpoint
        self.health_runner = await create_health_app(self.health_port, self.transcription_client)

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

        if self.prompt_manager:
            await self.prompt_manager.stop()

        if self.transcription_client:
            await self.transcription_client.disconnect()

        if self.health_runner:
            await self.health_runner.cleanup()

        logger.info("Phononmaser stopped")

    async def health_check(self) -> bool:
        """Check if the phononmaser service is healthy."""
        try:
            # Check if components are running
            if not self.running:
                return False

            # Check WebSocket server
            if not self.websocket_server or not hasattr(self.websocket_server, "server"):
                return False

            # Check transcription client connection
            if self.transcription_client:
                is_connected = await self.transcription_client.health_check()
                if not is_connected:
                    logger.warning("Transcription client connection unhealthy")
                    return False

            # Check audio processor
            return bool(self.audio_processor)

        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return False

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
    """Main entry point with supervisor pattern."""
    logger.info("Starting Phononmaser with supervisor...")

    # Create service instance
    service = Phononmaser()

    # Create service configuration with restart policy
    config = ServiceConfig(
        name="phononmaser",
        restart_strategy=RestartStrategy.ON_FAILURE,
        max_restarts=5,
        restart_window_seconds=300,  # 5 minutes
        restart_delay_seconds=2.0,
        restart_delay_max=30.0,
        health_check_interval=30.0,
        shutdown_timeout=15.0,
    )

    # Run with supervisor
    await run_with_supervisor([(service, config)])


if __name__ == "__main__":
    asyncio.run(main())
