"""Structured JSON logging configuration for Phononmaser audio service."""

import logging
import sys
from typing import Any, Dict

import structlog


def configure_json_logging() -> None:
    """Configure structured JSON logging for Phononmaser service."""

    # Configure standard library logging to output to stdout
    logging.basicConfig(
        format="%(message)s",  # structlog will handle formatting
        stream=sys.stdout,
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


def add_service_metadata(logger: Any, method_name: str, event_dict: Dict[str, Any]) -> Dict[str, Any]:
    """Add Phononmaser service metadata to log entries."""
    event_dict.update(
        {
            "service": "phononmaser",
            "component": "audio_processing",
            "version": "1.0.0",
        }
    )
    return event_dict


def get_logger(name: str = None) -> structlog.stdlib.BoundLogger:
    """Get a structured logger instance.

    Args:
        name: Logger name (optional)

    Returns:
        Configured structlog logger
    """
    return structlog.get_logger(name)


def bind_audio_context(session_id: str = None, audio_format: str = None, sample_rate: int = None) -> None:
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
