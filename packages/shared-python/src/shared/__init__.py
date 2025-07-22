"""Shared Python utilities for Landale services."""

__version__ = "0.1.0-uv"

# Export error boundary utilities
from .error_boundary import (
    error_boundary,
    safe_handler,
    retriable_network_call,
    critical_operation
)

__all__ = [
    "error_boundary",
    "safe_handler", 
    "retriable_network_call",
    "critical_operation"
]