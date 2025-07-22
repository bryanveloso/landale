"""Shared Python utilities for Landale services."""

__version__ = "0.1.0"

# Export error boundary utilities
from .shared.error_boundary import critical_operation, error_boundary, retriable_network_call, safe_handler

__all__ = ["error_boundary", "safe_handler", "retriable_network_call", "critical_operation"]
