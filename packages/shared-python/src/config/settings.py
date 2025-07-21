"""Environment-based configuration for all Python services."""

import logging
import os

logger = logging.getLogger(__name__)


class CommonConfig:
    """Base configuration class for all Landale services."""

    def __init__(self):
        # Core server configuration - only what needs to be configurable
        self.server_host: str = os.getenv("SERVER_HOST", "localhost")
        self.server_ws_port: int = 7175
        self.server_tcp_port: int = 8080

        # Logging configuration
        self.log_level: str = os.getenv("LOG_LEVEL", "INFO")

    @property
    def server_url(self) -> str:
        """Get the Phoenix server WebSocket URL."""
        return f"ws://{self.server_host}:{self.server_ws_port}/socket/websocket"

    @property
    def server_events_url(self) -> str:
        """Get the Phoenix server events WebSocket URL."""
        return f"ws://{self.server_host}:{self.server_ws_port}/events"

    def get_env(self, key: str, default: str | None = None) -> str | None:
        """Get an environment variable."""
        return os.getenv(key, default)

    def get_env_int(self, key: str, default: int = 0) -> int:
        """Get an environment variable as integer."""
        value = os.getenv(key, str(default))
        try:
            return int(value)
        except ValueError:
            logger.error(f"Invalid integer value for {key}: {value}")
            return default

    def get_env_bool(self, key: str, default: bool = False) -> bool:
        """Get an environment variable as boolean."""
        value = os.getenv(key, "").lower()
        if value in ("true", "1", "yes", "on"):
            return True
        elif value in ("false", "0", "no", "off"):
            return False
        return default


class PhononmaserConfig(CommonConfig):
    """Configuration specific to Phononmaser service."""

    def __init__(self):
        super().__init__()
        self.service_name = "phononmaser"

        self.port: int = 8889
        self.health_port: int = 8890
        self.bind_host: str = "0.0.0.0"

        # Audio settings - sensible defaults
        self.sample_rate: int = 16000
        self.channels: int = 1
        self.buffer_size_mb: int = 100

        # Transcription settings
        self.transcription_enabled: bool = True
        self.transcription_model: str = "base"


class SeedConfig(CommonConfig):
    """Configuration specific to Seed service."""

    def __init__(self):
        super().__init__()
        self.service_name = "seed"

        self.port: int = 8891
        self.health_port: int = 8892

        # LLM settings - host, port, and model are configurable
        self.lms_host: str = self.get_env("LMS_HOST", "localhost")
        self.lms_port: int = self.get_env_int("LMS_PORT", 1234)  # LM Studio default
        self.lms_model: str = self.get_env("LMS_MODEL", "meta/llama-3.3-70b")

        # Phononmaser connection
        self.phononmaser_host: str = "localhost"
        self.phononmaser_port: int = 8889

    @property
    def lms_api_url(self) -> str:
        """Get the LM Studio API URL."""
        return f"http://{self.lms_host}:{self.lms_port}/v1"

    @property
    def phononmaser_url(self) -> str:
        """Get the Phononmaser WebSocket URL."""
        return f"ws://{self.phononmaser_host}:{self.phononmaser_port}"


# Factory function to get the right config based on service
def get_config(service_name: str) -> CommonConfig:
    """Get configuration for a specific service.

    Args:
        service_name: Name of the service ("phononmaser" or "seed")

    Returns:
        Configuration object for the service
    """
    if service_name == "phononmaser":
        return PhononmaserConfig()
    elif service_name == "seed":
        return SeedConfig()
    else:
        raise ValueError(f"Unknown service: {service_name}")
