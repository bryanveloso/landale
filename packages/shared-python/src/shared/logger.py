"""Shared structured JSON logging configuration for Landale Python services."""

import logging
import os
import sys
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any

import structlog


def configure_json_logging(
    service_name: str,
    level: str = "INFO",
    json_output: bool = True,
    component: str | None = None,
    version: str = "1.0.0",
) -> None:
    """Configure structured JSON logging for Landale services.

    Args:
        service_name: Name of the service (e.g., 'seed', 'phononmaser', 'supervisor')
        level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        json_output: Whether to output JSON format (True) or human-readable (False)
        component: Component name within the service (optional)
        version: Service version for logging metadata
    """
    # Convert string level to logging constant
    log_level = getattr(logging, level.upper(), logging.INFO)

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
        log_file = log_dir / f"{service_name}.log"

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
        _create_service_metadata_processor(service_name, component, version),
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


def _create_service_metadata_processor(service_name: str, component: str | None, version: str) -> Any:
    """Create a processor that adds service metadata to log entries."""

    def add_service_metadata(_logger: Any, _method_name: str, event_dict: dict[str, Any]) -> dict[str, Any]:
        """Add service metadata to log entries."""
        metadata = {
            "service": service_name,
            "version": version,
        }
        if component:
            metadata["component"] = component

        event_dict.update(metadata)
        return event_dict

    return add_service_metadata


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


def configure_logging_from_env(service_name: str, component: str | None = None) -> None:
    """Configure logging using environment variables for level and format.

    This is a convenience function that reads LOG_LEVEL and JSON_LOGS
    environment variables to configure logging.

    Args:
        service_name: Name of the service (e.g., 'seed', 'phononmaser', 'supervisor')
        component: Component name within the service (optional)
    """
    log_level = os.getenv("LOG_LEVEL", "INFO")
    json_output = os.getenv("JSON_LOGS", "true").lower() in ("true", "1", "yes", "on")

    configure_json_logging(service_name=service_name, level=log_level, json_output=json_output, component=component)
