"""Shared Python utilities for Landale services."""

__version__ = "0.1.0-uv"

# Export circuit breaker utilities
from .circuit_breaker import CircuitBreaker, CircuitOpenError, circuit_breaker

# Export error boundary utilities
from .error_boundary import critical_operation, error_boundary, retriable_network_call, safe_handler

# Export supervisor utilities
from .supervisor import (
    ProcessSupervisor,
    RestartStrategy,
    ServiceConfig,
    ServiceState,
    ServiceSupervisor,
    SupervisedService,
    run_with_supervisor,
)

# Export task tracking utilities
from .task_tracker import TaskTracker, create_tracked_task, get_global_tracker

__all__ = [
    # Circuit breaker
    "CircuitBreaker",
    "CircuitOpenError",
    "circuit_breaker",
    # Error boundaries
    "error_boundary",
    "safe_handler",
    "retriable_network_call",
    "critical_operation",
    # Task tracking
    "TaskTracker",
    "get_global_tracker",
    "create_tracked_task",
    # Supervisor patterns
    "SupervisedService",
    "ServiceConfig",
    "RestartStrategy",
    "ServiceState",
    "ServiceSupervisor",
    "ProcessSupervisor",
    "run_with_supervisor",
]
