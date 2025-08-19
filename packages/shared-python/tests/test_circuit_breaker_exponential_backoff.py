"""Tests for Circuit Breaker exponential backoff functionality."""

import asyncio
import time

import pytest

from shared.circuit_breaker import CircuitBreaker, CircuitOpenError, CircuitState

# Mark all tests in this module as async
pytestmark = pytest.mark.asyncio


class TestExponentialBackoff:
    """Test exponential backoff functionality in CircuitBreaker."""

    def test_exponential_backoff_configuration(self):
        """Test circuit breaker can be configured with exponential backoff parameters."""
        circuit_breaker = CircuitBreaker(
            name="test_exponential",
            failure_threshold=3,
            recovery_timeout=60.0,
            max_recovery_timeout=300.0,
            backoff_multiplier=1.5,
        )

        assert circuit_breaker.failure_threshold == 3
        assert circuit_breaker.recovery_timeout == 60.0
        assert circuit_breaker.initial_recovery_timeout == 60.0
        assert circuit_breaker.max_recovery_timeout == 300.0
        assert circuit_breaker.backoff_multiplier == 1.5
        assert circuit_breaker.consecutive_open_count == 0

    @pytest.mark.parametrize(
        "backoff_multiplier,initial_timeout,expected_progression",
        [
            (1.5, 60.0, [60.0, 90.0, 135.0, 202.5, 300.0, 300.0]),  # 1.5x multiplier with 300s cap
            (2.0, 30.0, [30.0, 60.0, 120.0, 240.0, 300.0, 300.0]),  # 2.0x multiplier with 300s cap
            (1.2, 100.0, [100.0, 120.0, 144.0, 172.8, 207.36, 248.83]),  # 1.2x multiplier no cap hit
        ],
    )
    async def test_exponential_backoff_progression(self, backoff_multiplier, initial_timeout, expected_progression):
        """Test exponential backoff timeout progression with different multipliers."""
        circuit_breaker = CircuitBreaker(
            name="test_progression",
            failure_threshold=1,  # Fail fast for testing
            recovery_timeout=initial_timeout,
            max_recovery_timeout=300.0,
            backoff_multiplier=backoff_multiplier,
        )

        # Mock function that always fails
        async def failing_function():
            raise Exception("Always fails")

        actual_timeouts = []

        # Trigger multiple circuit openings to test progression
        for _i in range(len(expected_progression)):
            # Force failure to open circuit
            try:
                await circuit_breaker.call(failing_function)
            except Exception:
                pass

            # Record current timeout
            actual_timeouts.append(circuit_breaker.recovery_timeout)

            # Reset for next iteration (simulate passage of time)
            circuit_breaker._consecutive_failures = circuit_breaker.failure_threshold
            circuit_breaker._transition_to_open()

        # Verify progression matches expected values (with small tolerance for floating point)
        for i, (actual, expected) in enumerate(zip(actual_timeouts, expected_progression, strict=False)):
            assert abs(actual - expected) < 0.01, f"Step {i}: expected {expected}, got {actual}"

    async def test_backoff_reset_on_successful_connection(self):
        """Test that exponential backoff resets when circuit closes successfully."""
        circuit_breaker = CircuitBreaker(
            name="test_reset",
            failure_threshold=1,
            recovery_timeout=60.0,
            max_recovery_timeout=300.0,
            backoff_multiplier=1.5,
        )

        # Mock function that fails then succeeds
        call_count = 0

        async def intermittent_function():
            nonlocal call_count
            call_count += 1
            if call_count <= 3:
                raise Exception("Initial failures")
            return "success"

        # Trigger multiple failures to build up backoff
        for _ in range(3):
            try:
                await circuit_breaker.call(intermittent_function)
            except Exception:
                pass

        # Should have increased timeout and consecutive open count
        assert circuit_breaker.recovery_timeout > circuit_breaker.initial_recovery_timeout
        assert circuit_breaker.consecutive_open_count > 0

        # Wait for circuit to allow retry (simulate timeout)
        circuit_breaker._circuit_open_until = time.time() - 1

        # Successful call should reset backoff
        result = await circuit_breaker.call(intermittent_function)

        assert result == "success"
        assert circuit_breaker.recovery_timeout == circuit_breaker.initial_recovery_timeout
        assert circuit_breaker.consecutive_open_count == 0
        assert circuit_breaker.state == CircuitState.CLOSED

    async def test_maximum_timeout_enforcement(self):
        """Test that recovery timeout is capped at maximum value."""
        circuit_breaker = CircuitBreaker(
            name="test_max_timeout",
            failure_threshold=1,
            recovery_timeout=100.0,
            max_recovery_timeout=200.0,
            backoff_multiplier=3.0,  # Aggressive multiplier to hit max quickly
        )

        async def failing_function():
            raise Exception("Always fails")

        # Trigger multiple failures to exceed maximum timeout
        for _ in range(5):
            try:
                await circuit_breaker.call(failing_function)
            except Exception:
                pass

            # Force state to trigger backoff calculation
            circuit_breaker._consecutive_failures = circuit_breaker.failure_threshold
            circuit_breaker._transition_to_open()

        # Should be capped at maximum
        assert circuit_breaker.recovery_timeout == 200.0
        assert circuit_breaker.recovery_timeout <= circuit_breaker.max_recovery_timeout

    async def test_backoff_preserves_initial_timeout(self):
        """Test that initial timeout is preserved for reset purposes."""
        initial_timeout = 45.0
        circuit_breaker = CircuitBreaker(
            name="test_preserve_initial",
            failure_threshold=1,
            recovery_timeout=initial_timeout,
            max_recovery_timeout=300.0,
            backoff_multiplier=2.0,
        )

        # Verify initial state
        assert circuit_breaker.initial_recovery_timeout == initial_timeout
        assert circuit_breaker.recovery_timeout == initial_timeout

        # Trigger failure to increase timeout
        async def failing_function():
            raise Exception("Fails")

        try:
            await circuit_breaker.call(failing_function)
        except Exception:
            pass

        # Should have increased current timeout but preserved initial
        assert circuit_breaker.recovery_timeout > initial_timeout
        assert circuit_breaker.initial_recovery_timeout == initial_timeout

        # Reset should restore initial timeout
        circuit_breaker.reset()
        assert circuit_breaker.recovery_timeout == initial_timeout

    async def test_consecutive_open_count_tracking(self):
        """Test that consecutive open count is properly tracked."""
        circuit_breaker = CircuitBreaker(
            name="test_consecutive_count",
            failure_threshold=2,
            recovery_timeout=30.0,
            backoff_multiplier=1.5,
        )

        async def failing_function():
            raise Exception("Fails")

        # Initial state
        assert circuit_breaker.consecutive_open_count == 0

        # First circuit opening
        for _ in range(2):  # failure_threshold = 2
            try:
                await circuit_breaker.call(failing_function)
            except Exception:
                pass

        assert circuit_breaker.state == CircuitState.OPEN
        assert circuit_breaker.consecutive_open_count == 1

        # Trigger second opening (simulate time passing and retry)
        circuit_breaker._circuit_open_until = time.time() - 1  # Allow retry
        circuit_breaker.state = CircuitState.HALF_OPEN
        circuit_breaker._consecutive_failures = 0

        try:
            await circuit_breaker.call(failing_function)
        except Exception:
            pass

        assert circuit_breaker.state == CircuitState.OPEN
        assert circuit_breaker.consecutive_open_count == 2

    async def test_statistics_include_backoff_information(self):
        """Test that circuit breaker statistics include backoff information."""
        circuit_breaker = CircuitBreaker(
            name="test_stats",
            failure_threshold=1,
            recovery_timeout=60.0,
            max_recovery_timeout=300.0,
            backoff_multiplier=1.5,
        )

        # Initial statistics
        stats = circuit_breaker.get_stats()
        assert stats["consecutive_open_count"] == 0
        assert stats["current_recovery_timeout"] == 60.0
        assert stats["initial_recovery_timeout"] == 60.0

        # Trigger failure and check updated stats
        async def failing_function():
            raise Exception("Fails")

        try:
            await circuit_breaker.call(failing_function)
        except Exception:
            pass

        stats = circuit_breaker.get_stats()
        assert stats["consecutive_open_count"] == 1
        assert stats["current_recovery_timeout"] == 90.0  # 60.0 * 1.5
        assert stats["initial_recovery_timeout"] == 60.0

    async def test_backoff_with_real_timing(self):
        """Test exponential backoff with actual timing (integration test)."""
        circuit_breaker = CircuitBreaker(
            name="test_timing",
            failure_threshold=1,
            recovery_timeout=0.1,  # 100ms for fast testing
            max_recovery_timeout=0.5,  # 500ms max
            backoff_multiplier=2.0,
        )

        async def failing_function():
            raise Exception("Fails")

        # First failure - should open circuit
        time.time()
        try:
            await circuit_breaker.call(failing_function)
        except Exception:
            pass

        assert circuit_breaker.state == CircuitState.OPEN
        first_timeout = circuit_breaker.recovery_timeout
        assert first_timeout == 0.2  # 0.1 * 2.0

        # Should reject calls immediately
        with pytest.raises(CircuitOpenError):
            await circuit_breaker.call(failing_function)

        # Wait for timeout and trigger another failure
        await asyncio.sleep(first_timeout + 0.01)

        try:
            await circuit_breaker.call(failing_function)
        except Exception:
            pass

        # Should have increased timeout again
        second_timeout = circuit_breaker.recovery_timeout
        assert second_timeout == 0.4  # 0.2 * 2.0

        # Third failure should hit the maximum
        await asyncio.sleep(second_timeout + 0.01)

        try:
            await circuit_breaker.call(failing_function)
        except Exception:
            pass

        third_timeout = circuit_breaker.recovery_timeout
        assert third_timeout == 0.5  # Capped at max_recovery_timeout

    def test_manual_reset_clears_backoff(self):
        """Test that manual reset clears exponential backoff state."""
        circuit_breaker = CircuitBreaker(
            name="test_manual_reset",
            failure_threshold=1,
            recovery_timeout=60.0,
            backoff_multiplier=2.0,
        )

        # Build up some backoff state
        circuit_breaker.consecutive_open_count = 3
        circuit_breaker.recovery_timeout = 240.0
        circuit_breaker.state = CircuitState.OPEN

        # Manual reset should clear everything
        circuit_breaker.reset()

        assert circuit_breaker.state == CircuitState.CLOSED
        assert circuit_breaker.consecutive_open_count == 0
        assert circuit_breaker.recovery_timeout == 60.0
        assert circuit_breaker._consecutive_failures == 0


class TestBackoffIntegrationWithPromptManager:
    """Test exponential backoff integration with PromptManager use case."""

    async def test_prompt_manager_circuit_breaker_backoff(self):
        """Test that PromptManager benefits from exponential backoff on API failures."""
        # This tests the actual configuration used in PromptManager
        circuit_breaker = CircuitBreaker(
            name="chat_api",
            failure_threshold=3,
            recovery_timeout=60.0,
            max_recovery_timeout=300.0,  # Max 5 minutes
            backoff_multiplier=1.5,  # Gentler backoff (1.5x instead of 2x)
        )

        # Mock API function that fails
        async def mock_api_call():
            raise Exception("API temporarily unavailable")

        # Trigger multiple failures to test backoff progression
        timeouts = []

        for _attempt in range(5):
            try:
                await circuit_breaker.call(mock_api_call)
            except Exception:
                pass

            timeouts.append(circuit_breaker.recovery_timeout)

            # Simulate time passing to allow retry
            circuit_breaker._circuit_open_until = time.time() - 1
            circuit_breaker.state = CircuitState.HALF_OPEN
            circuit_breaker._consecutive_failures = 0

        # Verify progression: 60, 90, 135, 202.5, 300 (capped)
        expected_timeouts = [90.0, 135.0, 202.5, 303.75, 300.0]  # After each failure

        for i, (actual, expected) in enumerate(zip(timeouts, expected_timeouts, strict=False)):
            if expected > 300.0:
                expected = 300.0  # Should be capped
            assert abs(actual - expected) < 1.0, f"Attempt {i}: expected ~{expected}, got {actual}"


class TestEdgeCases:
    """Test edge cases and boundary conditions for exponential backoff."""

    def test_zero_backoff_multiplier(self):
        """Test behavior with edge case backoff multiplier values."""
        # Should handle edge case gracefully
        circuit_breaker = CircuitBreaker(
            name="test_zero_backoff",
            backoff_multiplier=0.0,
            recovery_timeout=60.0,
        )

        # Force transition to test backoff calculation
        circuit_breaker._consecutive_failures = circuit_breaker.failure_threshold
        circuit_breaker._transition_to_open()

        # With 0 multiplier, timeout should remain unchanged or become 0
        assert circuit_breaker.recovery_timeout >= 0

    def test_very_large_backoff_multiplier(self):
        """Test behavior with very large backoff multiplier."""
        circuit_breaker = CircuitBreaker(
            name="test_large_backoff",
            backoff_multiplier=10.0,
            recovery_timeout=10.0,
            max_recovery_timeout=100.0,
        )

        # Should quickly hit maximum with large multiplier
        circuit_breaker._consecutive_failures = circuit_breaker.failure_threshold
        circuit_breaker._transition_to_open()  # 1st opening: 10 * 10^0 = 10
        circuit_breaker._transition_to_open()  # 2nd opening: 10 * 10^1 = 100 (at max)

        assert circuit_breaker.recovery_timeout == 100.0

    def test_minimum_timeout_handling(self):
        """Test behavior with very small initial timeout."""
        circuit_breaker = CircuitBreaker(
            name="test_minimum",
            recovery_timeout=0.001,  # 1ms
            backoff_multiplier=2.0,
            max_recovery_timeout=1.0,
        )

        # Should handle small timeouts correctly
        circuit_breaker._consecutive_failures = circuit_breaker.failure_threshold
        circuit_breaker._transition_to_open()

        # Should have doubled the timeout
        assert circuit_breaker.recovery_timeout == 0.002
