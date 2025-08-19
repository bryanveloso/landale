"""Environment-based configuration for all Python services."""

import logging
import os

logger = logging.getLogger(__name__)


class CommonConfig:
    """Base configuration class for all Landale services."""

    def __init__(self):
        # Core server configuration - only what needs to be configurable
        self.server_host: str = os.getenv("SERVER_HOST", "saya")
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
        """Get an environment variable as integer with validation."""
        value = os.getenv(key, str(default))
        try:
            parsed = int(value)
            # Validate reasonable ranges for common config values
            if parsed < 0:
                logger.warning(f"Negative value for {key}: {parsed}, using default: {default}")
                return default
            return parsed
        except ValueError:
            logger.error(
                f"Invalid integer value for environment variable '{key}': '{value}'. "
                f"Expected a valid integer, using default: {default}"
            )
            return default

    def get_env_bool(self, key: str, default: bool = False) -> bool:
        """Get an environment variable as boolean with clear parsing."""
        value = os.getenv(key, "").lower().strip()
        if not value:
            return default
        if value in ("true", "1", "yes", "on", "enabled"):
            return True
        elif value in ("false", "0", "no", "off", "disabled"):
            return False
        logger.warning(
            f"Ambiguous boolean value for environment variable '{key}': '{value}'. "
            f"Expected true/false, yes/no, 1/0, on/off, or enabled/disabled. "
            f"Using default: {default}"
        )
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

    def validate(self) -> list[str]:
        """
        Validate configuration and return list of errors.

        Returns:
            list[str]: List of validation error messages, empty if valid
        """
        errors = []

        # Port validation
        if not (1024 <= self.port <= 65535):
            errors.append(f"Phononmaser port {self.port} is out of valid range (1024-65535)")
        if not (1024 <= self.health_port <= 65535):
            errors.append(f"Health check port {self.health_port} is out of valid range (1024-65535)")
        if self.port == self.health_port:
            errors.append(f"Phononmaser port and health port cannot be the same ({self.port})")

        # Audio settings validation
        if self.sample_rate not in [8000, 16000, 22050, 44100, 48000]:
            logger.warning(f"Non-standard sample rate: {self.sample_rate}Hz")
        if self.channels not in [1, 2]:
            errors.append(f"Invalid channel count: {self.channels} (must be 1 or 2)")
        if not (1 <= self.buffer_size_mb <= 1000):
            errors.append(f"Buffer size {self.buffer_size_mb}MB out of reasonable range (1-1000MB)")

        return errors


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

    def validate(self) -> list[str]:
        """
        Validate configuration and return list of errors.

        Returns:
            list[str]: List of validation error messages, empty if valid
        """
        errors = []

        # Port validation
        if not (1024 <= self.port <= 65535):
            errors.append(f"Seed port {self.port} is out of valid range (1024-65535)")
        if not (1024 <= self.health_port <= 65535):
            errors.append(f"Health check port {self.health_port} is out of valid range (1024-65535)")
        if self.port == self.health_port:
            errors.append(f"Seed port and health port cannot be the same ({self.port})")

        # LMS settings validation
        if not (1 <= self.lms_port <= 65535):
            errors.append(f"LM Studio port {self.lms_port} is out of valid range (1-65535)")
        if not self.lms_model:
            errors.append("LMS_MODEL environment variable cannot be empty")

        # Phononmaser connection validation
        if not (1024 <= self.phononmaser_port <= 65535):
            errors.append(f"Phononmaser port {self.phononmaser_port} is out of valid range (1024-65535)")

        return errors

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
