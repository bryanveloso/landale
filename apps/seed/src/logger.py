"""Structured JSON logging configuration for SEED intelligence service."""

import logging
import sys
from typing import Any

import structlog


def configure_json_logging(level: str = "INFO", json_output: bool = True) -> None:
    """Configure structured JSON logging for SEED service.

    Args:
        level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        json_output: Whether to output JSON format (True) or human-readable (False)
    """
    # Convert string level to logging constant
    log_level = getattr(logging, level.upper(), logging.INFO)

    # Configure standard library logging to output to stdout
    logging.basicConfig(
        format="%(message)s",  # structlog will handle formatting
        stream=sys.stdout,
        level=log_level,
    )

    # Choose processors based on output format
    processors = [
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
    ]

    # Add appropriate renderer
    if json_output:
        processors.append(structlog.processors.JSONRenderer())
    else:
        processors.append(structlog.dev.ConsoleRenderer())

    # Configure structlog
    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(log_level),
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )


def add_service_metadata(_logger: Any, _method_name: str, event_dict: dict[str, Any]) -> dict[str, Any]:
    """Add SEED service metadata to log entries."""
    event_dict.update(
        {
            "service": "seed",
            "component": "intelligence",
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


def bind_correlation_context(correlation_id: str | None = None, session_id: str | None = None) -> None:
    """Bind correlation context for request tracking.

    Args:
        correlation_id: Unique correlation ID for tracking requests
        session_id: Session identifier for user tracking
    """
    context = {}
    if correlation_id:
        context["correlation_id"] = correlation_id
    if session_id:
        context["session_id"] = session_id

    if context:
        structlog.contextvars.bind_contextvars(**context)


def clear_context() -> None:
    """Clear all context variables."""
    structlog.contextvars.clear_contextvars()
