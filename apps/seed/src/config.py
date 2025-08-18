"""Configuration management for Seed service using Pydantic."""

import os

from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class LMSConfig(BaseModel):
    """LM Studio configuration."""

    api_url: str = Field(default="http://zelan:1234/v1", description="LM Studio API endpoint URL")
    model: str = Field(default="deepseek/deepseek-r1-0528-qwen3-8b", description="LLM model to use for analysis")
    rate_limit: int = Field(default=10, ge=1, le=100, description="Maximum API requests per time window")
    rate_window: int = Field(default=60, ge=10, le=300, description="Rate limit time window in seconds")
    timeout: float = Field(default=30.0, ge=5.0, le=120.0, description="API request timeout in seconds")


class WebSocketConfig(BaseModel):
    """WebSocket connection configuration."""

    server_url: str = Field(default="http://saya:7175", description="Phoenix server HTTP URL")
    server_ws_url: str = Field(default="ws://saya:7175", description="Phoenix server WebSocket URL")
    reconnect_interval: float = Field(
        default=5.0, ge=1.0, le=60.0, description="WebSocket reconnection interval in seconds"
    )
    max_reconnect_attempts: int = Field(default=0, ge=0, description="Maximum reconnection attempts (0 = infinite)")


class CorrelatorConfig(BaseModel):
    """Stream correlator configuration."""

    context_window_seconds: int = Field(default=120, ge=30, le=600, description="Context window size in seconds")
    analysis_interval_seconds: int = Field(
        default=30, ge=10, le=120, description="Periodic analysis interval in seconds"
    )
    correlation_window_seconds: int = Field(default=10, ge=2, le=30, description="Chat correlation window in seconds")
    max_buffer_size: int = Field(default=1000, ge=100, le=10000, description="Maximum events per buffer")


class HealthConfig(BaseModel):
    """Health monitoring configuration."""

    port: int = Field(default=8891, ge=1024, le=65535, description="Health check endpoint port")
    host: str = Field(default="0.0.0.0", description="Health check endpoint host")


class CircuitBreakerConfig(BaseModel):
    """Circuit breaker configuration."""

    failure_threshold: int = Field(default=5, ge=1, le=20, description="Failures before opening circuit")
    recovery_timeout: float = Field(default=120.0, ge=10.0, le=600.0, description="Recovery timeout in seconds")
    success_threshold: int = Field(default=3, ge=1, le=10, description="Successes required to close circuit")


class SeedConfig(BaseSettings):
    """Main Seed service configuration."""

    model_config = SettingsConfigDict(
        env_prefix="SEED_",
        env_nested_delimiter="__",
        case_sensitive=False,
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Service identification
    service_name: str = Field(default="landale-seed", description="Service name for logging and monitoring")

    # Component configurations
    lms: LMSConfig = Field(default_factory=LMSConfig)
    websocket: WebSocketConfig = Field(default_factory=WebSocketConfig)
    correlator: CorrelatorConfig = Field(default_factory=CorrelatorConfig)
    health: HealthConfig = Field(default_factory=HealthConfig)
    circuit_breaker: CircuitBreakerConfig = Field(default_factory=CircuitBreakerConfig)

    # Logging configuration
    log_level: str = Field(default="INFO", pattern="^(DEBUG|INFO|WARNING|ERROR|CRITICAL)$", description="Logging level")
    json_logs: bool = Field(default=True, description="Enable JSON structured logging")

    @field_validator("websocket")
    @classmethod
    def validate_websocket_urls(cls, v: WebSocketConfig) -> WebSocketConfig:
        """Ensure WebSocket URLs are properly formatted."""
        # Convert HTTP to WS URL if needed
        if v.server_url.startswith("http://"):
            v.server_ws_url = v.server_url.replace("http://", "ws://")
        elif v.server_url.startswith("https://"):
            v.server_ws_url = v.server_url.replace("https://", "wss://")
        return v

    def get_phononmaser_url(self) -> str:
        """Get phononmaser WebSocket URL."""
        # Default to localhost if not specified
        return os.getenv("PHONONMASER_URL", "ws://localhost:8889")

    def get_server_events_url(self) -> str:
        """Get server events WebSocket URL."""
        base_url = self.websocket.server_ws_url
        if "/socket" in base_url:
            return base_url.replace("/socket", "/socket/websocket")
        else:
            return f"{base_url}/socket/websocket"

    def validate_config(self) -> None:
        """Validate configuration and fail fast on errors."""
        errors = []

        # Check LMS URL is reachable format
        if not self.lms.api_url.startswith(("http://", "https://")):
            errors.append(f"Invalid LMS API URL: {self.lms.api_url}")

        # Check WebSocket URLs
        if not self.websocket.server_ws_url.startswith(("ws://", "wss://")):
            errors.append(f"Invalid WebSocket URL: {self.websocket.server_ws_url}")

        # Check port ranges
        if not 1024 <= self.health.port <= 65535:
            errors.append(f"Invalid health port: {self.health.port}")

        if errors:
            error_msg = "Configuration validation failed:\n" + "\n".join(f"  - {e}" for e in errors)
            raise ValueError(error_msg)

    def to_dict(self) -> dict:
        """Convert configuration to dictionary for logging."""
        return {
            "service_name": self.service_name,
            "lms": {
                "api_url": self.lms.api_url,
                "model": self.lms.model,
                "rate_limit": f"{self.lms.rate_limit} req/{self.lms.rate_window}s",
            },
            "websocket": {"server_url": self.websocket.server_url, "server_ws_url": self.websocket.server_ws_url},
            "correlator": {
                "context_window": f"{self.correlator.context_window_seconds}s",
                "analysis_interval": f"{self.correlator.analysis_interval_seconds}s",
                "max_buffer_size": self.correlator.max_buffer_size,
            },
            "health": {"endpoint": f"http://{self.health.host}:{self.health.port}/health"},
            "circuit_breaker": {
                "failure_threshold": self.circuit_breaker.failure_threshold,
                "recovery_timeout": f"{self.circuit_breaker.recovery_timeout}s",
            },
            "logging": {"level": self.log_level, "json": self.json_logs},
        }


# Global config instance
_config: SeedConfig | None = None


def get_config() -> SeedConfig:
    """Get or create the global configuration instance."""
    global _config
    if _config is None:
        _config = SeedConfig()
        _config.validate_config()
    return _config


def reload_config() -> SeedConfig:
    """Reload configuration from environment."""
    global _config
    _config = SeedConfig()
    _config.validate_config()
    return _config
