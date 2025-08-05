"""Structured JSON logging configuration for Phononmaser audio service."""

import logging
import os
import sys
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any

import structlog


def configure_json_logging() -> None:
    """Configure structured JSON logging for Phononmaser service."""
    # Determine if we're running under Nurvus based on environment
    is_managed = os.getenv("NURVUS_MANAGED", "false").lower() == "true"
    log_to_file = is_managed or os.getenv("LOG_TO_FILE", "false").lower() == "true"

    # Configure handler based on environment
    if log_to_file:
        # Get log directory from environment (must be set by Nurvus)
        log_dir = os.getenv("LOG_DIR")
        if not log_dir:
            raise ValueError("LOG_DIR environment variable must be set when running under Nurvus")

        log_dir = Path(log_dir).resolve()
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / "phononmaser.log"

        # Use rotating file handler to manage log size
        handler = RotatingFileHandler(
            log_file,
            maxBytes=10 * 1024 * 1024,  # 10MB
            backupCount=5,
            encoding="utf-8",
        )
    else:
        # Use standard stream handler for development
        handler = logging.StreamHandler(sys.stdout)

    handler.setFormatter(logging.Formatter("%(message)s"))

    logging.basicConfig(
        handlers=[handler],
        level=logging.INFO,
    )

    # Configure structlog for production JSON logging
    structlog.configure(
        processors=[
            # Add context variables (request IDs, correlation IDs, etc.)
            structlog.contextvars.merge_contextvars,
            # Add log level to event dict
            structlog.processors.add_log_level,
            # Add timestamp in ISO 8601 format
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            # Add service metadata
            add_service_metadata,
            # Handle exceptions with structured tracebacks
            structlog.processors.format_exc_info,
            # Render as JSON
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )


def add_service_metadata(_logger: Any, _method_name: str, event_dict: dict[str, Any]) -> dict[str, Any]:
    """Add Phononmaser service metadata to log entries."""
    event_dict.update(
        {
            "service": "phononmaser",
            "component": "audio_processing",
            "version": "1.0.0",
        }
    )
    return event_dict


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    """Get a structured logger instance.

    Args:
        name: Logger name (optional)

    Returns:
        Configured structlog logger
    """
    return structlog.get_logger(name)


def bind_audio_context(
    session_id: str | None = None, audio_format: str | None = None, sample_rate: int | None = None
) -> None:
    """Bind audio processing context for tracking.

    Args:
        session_id: Audio session identifier
        audio_format: Audio format (e.g., 'wav', 'mp3')
        sample_rate: Audio sample rate in Hz
    """
    context = {}
    if session_id:
        context["audio_session_id"] = session_id
    if audio_format:
        context["audio_format"] = audio_format
    if sample_rate:
        context["sample_rate"] = sample_rate

    if context:
        structlog.contextvars.bind_contextvars(**context)


def clear_context() -> None:
    """Clear all context variables."""
    structlog.contextvars.clear_contextvars()
