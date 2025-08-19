"""Circuit breaker pattern implementation for external service resilience."""

import time
from collections import deque
from collections.abc import Callable
from enum import Enum
from typing import Any, TypeVar

T = TypeVar("T")


class CircuitState(Enum):
    """Circuit breaker states."""

    CLOSED = "closed"  # Normal operation
    OPEN = "open"  # Failing, reject all calls
    HALF_OPEN = "half_open"  # Testing if service recovered


class CircuitBreaker:
    """
    Circuit breaker implementation for external service calls.

    States:
    - CLOSED: Normal operation, calls pass through
    - OPEN: Service is failing, calls are rejected immediately
    - HALF_OPEN: Testing if service has recovered

    Configuration:
    - failure_threshold: Number of failures before opening circuit
    - recovery_timeout: Seconds to wait before trying half-open
    - expected_exception: Exception types that count as failures
    """

    def __init__(
        self,
        name: str,
        failure_threshold: int = 5,
        recovery_timeout: float = 60.0,
        expected_exception: type[Exception] | tuple[type[Exception], ...] = Exception,
        success_threshold: int = 2,
        logger=None,
        max_recovery_timeout: float = 300.0,  # Maximum 5 minutes
        backoff_multiplier: float = 2.0,  # Exponential backoff multiplier
    ):
        self.name = name
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.initial_recovery_timeout = recovery_timeout  # Store initial value for reset
        self.max_recovery_timeout = max_recovery_timeout
        self.backoff_multiplier = backoff_multiplier
        self.expected_exception = expected_exception
        self.success_threshold = success_threshold
        self.logger = logger

        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.success_count = 0
        self.consecutive_open_count = 0  # Track consecutive transitions to OPEN
        self.last_failure_time = 0.0
        self.last_state_change = time.time()

        # Track recent response times for monitoring
        self.response_times: deque[float] = deque(maxlen=100)

        # Statistics
        self.total_calls = 0
        self.total_failures = 0
        self.total_successes = 0
        self.total_rejections = 0

    async def call(self, func: Callable[..., T], *args, **kwargs) -> T:
        """
        Execute function through circuit breaker.

        Raises:
            Exception: Original exception from function
            CircuitOpenError: If circuit is open
        """
        self.total_calls += 1

        # Check if we should transition from OPEN to HALF_OPEN
        if self.state == CircuitState.OPEN:
            if time.time() - self.last_failure_time >= self.recovery_timeout:
                self._transition_to_half_open()
            else:
                self.total_rejections += 1
                raise CircuitOpenError(
                    f"Circuit breaker '{self.name}' is OPEN. "
                    f"Waiting {self.recovery_timeout - (time.time() - self.last_failure_time):.1f}s before retry."
                )

        # Try to execute the function
        start_time = time.time()
        try:
            result = await func(*args, **kwargs)
            elapsed = time.time() - start_time
            self.response_times.append(elapsed)
            self._record_success()
            return result

        except self.expected_exception as e:
            elapsed = time.time() - start_time
            self.response_times.append(elapsed)
            self._record_failure()
            raise e

    def _record_success(self):
        """Record a successful call."""
        self.total_successes += 1
        self.failure_count = 0  # Reset failure count on success

        if self.state == CircuitState.HALF_OPEN:
            self.success_count += 1
            if self.success_count >= self.success_threshold:
                self._transition_to_closed()

    def _record_failure(self):
        """Record a failed call."""
        self.total_failures += 1
        self.failure_count += 1
        self.last_failure_time = time.time()

        if self.state == CircuitState.HALF_OPEN:
            # Any failure in half-open state reopens the circuit
            self._transition_to_open()
        elif self.state == CircuitState.CLOSED and self.failure_count >= self.failure_threshold:
            self._transition_to_open()

    def _transition_to_open(self):
        """Transition to OPEN state with exponential backoff."""
        self.state = CircuitState.OPEN
        self.last_state_change = time.time()
        self.success_count = 0
        self.consecutive_open_count += 1

        # Apply exponential backoff for recovery timeout
        if self.consecutive_open_count > 1:
            # Calculate new timeout with exponential backoff
            new_timeout = self.recovery_timeout * (self.backoff_multiplier ** (self.consecutive_open_count - 1))
            self.recovery_timeout = min(new_timeout, self.max_recovery_timeout)

        if self.logger:
            self.logger.error(
                f"Circuit breaker '{self.name}' opened after {self.failure_count} failures. "
                f"Will retry in {self.recovery_timeout:.1f}s (attempt #{self.consecutive_open_count})."
            )

    def _transition_to_half_open(self):
        """Transition to HALF_OPEN state."""
        self.state = CircuitState.HALF_OPEN
        self.last_state_change = time.time()
        self.success_count = 0
        self.failure_count = 0

        if self.logger:
            self.logger.info(f"Circuit breaker '{self.name}' entering HALF_OPEN state for testing.")

    def _transition_to_closed(self):
        """Transition to CLOSED state and reset backoff."""
        self.state = CircuitState.CLOSED
        self.last_state_change = time.time()
        self.failure_count = 0
        self.success_count = 0
        self.consecutive_open_count = 0  # Reset consecutive open count
        self.recovery_timeout = self.initial_recovery_timeout  # Reset to initial timeout

        if self.logger:
            self.logger.info(
                f"Circuit breaker '{self.name}' closed. Service recovered. "
                f"Recovery timeout reset to {self.initial_recovery_timeout}s."
            )

    def get_stats(self) -> dict[str, Any]:
        """Get circuit breaker statistics."""
        avg_response_time = sum(self.response_times) / len(self.response_times) if self.response_times else 0.0

        return {
            "name": self.name,
            "state": self.state.value,
            "failure_count": self.failure_count,
            "success_count": self.success_count,
            "consecutive_open_count": self.consecutive_open_count,
            "current_recovery_timeout": self.recovery_timeout,
            "initial_recovery_timeout": self.initial_recovery_timeout,
            "total_calls": self.total_calls,
            "total_failures": self.total_failures,
            "total_successes": self.total_successes,
            "total_rejections": self.total_rejections,
            "avg_response_time": avg_response_time,
            "last_failure_time": self.last_failure_time,
            "time_in_current_state": time.time() - self.last_state_change,
            "success_rate": (self.total_successes / self.total_calls if self.total_calls > 0 else 0.0),
        }

    def reset(self):
        """Manually reset the circuit breaker to CLOSED state and reset backoff."""
        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.success_count = 0
        self.consecutive_open_count = 0
        self.recovery_timeout = self.initial_recovery_timeout
        self.last_state_change = time.time()

        if self.logger:
            self.logger.info(
                f"Circuit breaker '{self.name}' manually reset to CLOSED with timeout {self.initial_recovery_timeout}s."
            )


class CircuitOpenError(Exception):
    """Raised when circuit breaker is open and rejecting calls."""

    pass


# Decorator version for easier use
def circuit_breaker(
    name: str | None = None,
    failure_threshold: int = 5,
    recovery_timeout: float = 60.0,
    expected_exception: type[Exception] | tuple[type[Exception], ...] = Exception,
    success_threshold: int = 2,
    logger=None,
    max_recovery_timeout: float = 300.0,
    backoff_multiplier: float = 2.0,
):
    """
    Decorator to apply circuit breaker pattern to async functions with exponential backoff.

    Example:
        @circuit_breaker(name="external_api", failure_threshold=3, backoff_multiplier=1.5)
        async def call_external_api():
            ...
    """

    def decorator(func: Callable) -> Callable:
        breaker_name = name or f"{func.__module__}.{func.__name__}"
        breaker = CircuitBreaker(
            name=breaker_name,
            failure_threshold=failure_threshold,
            recovery_timeout=recovery_timeout,
            expected_exception=expected_exception,
            success_threshold=success_threshold,
            logger=logger,
            max_recovery_timeout=max_recovery_timeout,
            backoff_multiplier=backoff_multiplier,
        )

        async def wrapper(*args, **kwargs):
            return await breaker.call(func, *args, **kwargs)

        # Attach breaker instance for monitoring
        wrapper.circuit_breaker = breaker
        wrapper.__name__ = func.__name__
        wrapper.__doc__ = func.__doc__

        return wrapper

    return decorator
