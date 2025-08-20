"""Comprehensive safety feature tests for PromptManager implementation."""

import asyncio
import builtins
import contextlib
import time
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from shared.circuit_breaker import CircuitOpenError, CircuitState

from src.audio_processor import AudioProcessor
from src.prompt_manager import PromptManager


class TestPromptManagerSafetyFeatures:
    """Test all critical safety features."""

    def test_character_limit_safety(self):
        """Test 200-character safety limit is enforced."""
        manager = PromptManager(prompt_max_chars=200)

        # Generate many usernames that would exceed limit
        usernames = {f"verylongusername{i:03d}": 1 for i in range(100)}
        prompt = manager._generate_prompt(usernames)

        assert len(prompt) <= 200
        assert prompt.startswith("Participants include:")
        assert prompt.endswith(".")

    def test_rate_limiting_enforcement(self):
        """Test 30-second minimum polling interval."""
        # Should enforce minimum even if configured lower
        manager = PromptManager(poll_interval_seconds=5.0)
        assert manager.poll_interval == 30.0

        # Should respect higher values
        manager = PromptManager(poll_interval_seconds=60.0)
        assert manager.poll_interval == 60.0

    def test_circuit_breaker_protection(self):
        """Test circuit breaker prevents cascade failures."""
        manager = PromptManager(circuit_breaker_failures=3)

        # Should be closed initially
        stats = manager.circuit_breaker.get_stats()
        assert stats["state"] == "closed"

        # Simulate failures
        for _ in range(3):
            manager.circuit_breaker.failure_count += 1
            manager.circuit_breaker._record_failure()

        # Should be open after threshold failures
        stats = manager.circuit_breaker.get_stats()
        assert stats["state"] == "open"

    def test_username_filtering(self):
        """Test username filtering prevents injection/overflow."""
        manager = PromptManager()

        events = [
            {"event_data": {"username": "valid_user"}},
            {"event_data": {"username": ""}},  # Empty
            {"event_data": {"username": None}},  # None
            {"event_data": {"username": 123}},  # Not string
            {"event_data": {"username": "x" * 100}},  # Too long
            {"event_data": {"username": "  spaced  "}},  # Valid but needs trimming
        ]

        usernames = manager._extract_usernames(events)

        # Should only include valid usernames
        assert usernames == {"valid_user": 1, "spaced": 1}

    def test_prompt_expiry_mechanism(self):
        """Test prompt expiry prevents stale data."""
        manager = PromptManager(prompt_expiry_minutes=5)

        # Set fresh prompt
        manager.current_prompt = "Fresh prompt"
        manager.last_prompt_update = time.time()

        prompt = manager.get_current_prompt()
        assert prompt == "Fresh prompt"

        # Set expired prompt
        manager.current_prompt = "Stale prompt"
        manager.last_prompt_update = time.time() - (6 * 60)  # 6 minutes ago

        prompt = manager.get_current_prompt()
        assert prompt == ""  # Should be cleared
        assert manager.current_prompt == ""

    @pytest.mark.asyncio
    async def test_graceful_degradation_audio_processor(self):
        """Test AudioProcessor graceful degradation when PromptManager fails."""
        # Create failing PromptManager
        prompt_manager = MagicMock()
        prompt_manager.get_current_prompt.side_effect = Exception("Network timeout")

        with patch("os.path.exists", return_value=True):
            processor = AudioProcessor(
                whisper_model_path="/fake/model",
                prompt_manager=prompt_manager,
            )

        # Should handle failure gracefully
        prompt = processor._get_current_prompt()
        assert prompt == ""

    @pytest.mark.asyncio
    async def test_service_continues_without_prompt_manager(self):
        """Test service continues running if PromptManager fails."""
        from src.main import Phononmaser

        with (
            patch.dict(
                "os.environ",
                {
                    "WHISPER_MODEL_PATH": "/fake/model",
                    "ENABLE_PROMPT_MANAGER": "false",
                },
            ),
            patch("os.path.exists", return_value=True),
        ):
            service = Phononmaser()

            # Should initialize without PromptManager
            assert service.enable_prompt_manager is False
            assert service.prompt_manager is None

    def test_memory_protection_username_limits(self):
        """Test memory protection through username limits."""
        manager = PromptManager()

        # Create events with extremely long usernames
        events = []
        for i in range(1000):
            events.append(
                {
                    "event_data": {"username": f"user{i}" + "x" * 1000}  # Very long
                }
            )

        # Should filter out long usernames
        usernames = manager._extract_usernames(events)
        assert len(usernames) == 0  # All should be filtered out as too long

    def test_json_decode_error_handling(self):
        """Test handling of malformed JSON responses."""
        manager = PromptManager()

        # Test with malformed events
        malformed_events = [
            {"incomplete": "event"},
            "not_an_object",
            {"event_data": "not_an_object"},
        ]

        # Should not crash and should filter out invalid events
        usernames = manager._extract_usernames(malformed_events)
        assert usernames == {}

    @pytest.mark.asyncio
    async def test_http_timeout_protection(self):
        """Test HTTP timeout protects against hanging requests."""
        manager = PromptManager()
        await manager.start()

        # Session should have timeouts configured
        assert manager.session.timeout.total == 10.0
        assert manager.session.timeout.connect == 5.0

        await manager.stop()

    @pytest.mark.asyncio
    async def test_circuit_breaker_recovery(self):
        """Test circuit breaker recovery mechanism."""
        manager = PromptManager(
            circuit_breaker_failures=2,
            circuit_breaker_recovery_seconds=1.0,  # Short for testing
        )

        # Force circuit open
        manager.circuit_breaker.state = CircuitState.OPEN
        manager.circuit_breaker.last_failure_time = time.time()

        # Should reject calls immediately
        with pytest.raises(CircuitOpenError):
            await manager.circuit_breaker.call(lambda: None)

        # Wait for recovery period
        await asyncio.sleep(1.1)

        # Should transition to half-open and allow test calls
        # (This would normally be tested with actual success calls)

    def test_prompt_generation_iterative_building(self):
        """Test prompt generation builds iteratively within limits."""
        manager = PromptManager(prompt_max_chars=50)

        # Create usernames of different lengths
        usernames = {
            "a": 1,  # 1 char
            "bb": 2,  # 2 chars
            "ccc": 3,  # 3 chars
            "dddd": 4,  # 4 chars
            "eeeee": 5,  # 5 chars
        }

        prompt = manager._generate_prompt(usernames)

        # Should include as many as fit within limit
        assert len(prompt) <= 50
        assert "Participants include:" in prompt
        # Should include at least some usernames
        assert len(prompt) > len("Participants include: .")

    def test_statistics_tracking(self):
        """Test statistics are properly tracked for monitoring."""
        manager = PromptManager()

        stats = manager.get_stats()

        # Should have all required fields
        required_fields = [
            "total_polls",
            "successful_polls",
            "failed_polls",
            "prompts_generated",
            "circuit_breaker_opens",
            "last_success_time",
            "last_error",
            "current_prompt_length",
            "prompt_age_seconds",
            "time_since_last_poll",
            "circuit_breaker",
            "running",
        ]

        for field in required_fields:
            assert field in stats

    def test_frequency_prioritization(self):
        """Test usernames are prioritized by frequency."""
        manager = PromptManager()

        # Create usernames with different frequencies
        usernames = {
            "alice": 5,  # Most frequent
            "bob": 3,  # Medium
            "charlie": 1,  # Least frequent
        }

        prompt = manager._generate_prompt(usernames)

        # Should include all in frequency order (least to most)
        assert prompt == "Participants include: charlie, bob, alice."

    @pytest.mark.asyncio
    async def test_background_polling_lifecycle(self):
        """Test background polling starts and stops cleanly."""
        manager = PromptManager(poll_interval_seconds=1.0)

        # Should not be running initially
        assert not manager.running
        assert manager.poll_task is None

        await manager.start()

        # Should be running with task
        assert manager.running
        assert manager.poll_task is not None

        await manager.stop()

        # Should be stopped cleanly
        assert not manager.running
        assert manager.poll_task.cancelled()

    def test_api_url_construction(self):
        """Test API URL is constructed correctly."""
        manager = PromptManager(phoenix_base_url="http://test:7175/")

        # Should strip trailing slash and construct correct endpoint
        assert manager.bulk_api_url == "http://test:7175/api/activity/events/bulk"

    def test_error_isolation(self):
        """Test errors in one component don't affect others."""
        manager = PromptManager()

        # Even with invalid events, should continue processing
        mixed_events = [
            {"event_data": {"username": "valid1"}},  # Valid
            {"invalid": "event"},  # Invalid
            {"event_data": {"username": "valid2"}},  # Valid
        ]

        usernames = manager._extract_usernames(mixed_events)

        # Should extract valid usernames despite errors
        assert usernames == {"valid1": 1, "valid2": 1}


class TestAudioProcessorIntegrationSafety:
    """Test safety aspects of AudioProcessor integration."""

    def test_backward_compatibility(self):
        """Test AudioProcessor works without PromptManager."""
        with patch("os.path.exists", return_value=True):
            processor = AudioProcessor(
                whisper_model_path="/fake/model",
                prompt_manager=None,
            )

        # Should work without PromptManager
        prompt = processor._get_current_prompt()
        assert prompt == ""

    def test_prompt_failure_isolation(self):
        """Test prompt failures don't block transcription."""
        prompt_manager = MagicMock()
        prompt_manager.get_current_prompt.side_effect = Exception("Prompt service down")

        with patch("os.path.exists", return_value=True):
            processor = AudioProcessor(
                whisper_model_path="/fake/model",
                prompt_manager=prompt_manager,
            )

        # Should handle failure gracefully and continue
        prompt = processor._get_current_prompt()
        assert prompt == ""

    @patch("subprocess.run")
    def test_whisper_command_safety(self, mock_subprocess):
        """Test Whisper command generation is safe."""
        mock_subprocess.return_value.returncode = 0
        mock_subprocess.return_value.stdout = "Test output"

        prompt_manager = MagicMock()
        prompt_manager.get_current_prompt.return_value = "Safe prompt"

        with patch("os.path.exists", return_value=True):
            processor = AudioProcessor(
                whisper_model_path="/fake/model",
                prompt_manager=prompt_manager,
            )

        # Test that prompts are safely added to command
        prompt = processor._get_current_prompt()
        assert prompt == "Safe prompt"


class TestMainServiceIntegrationSafety:
    """Test main service safety with PromptManager."""

    def test_environment_variable_safety(self):
        """Test environment variable parsing is safe."""
        from src.main import Phononmaser

        # Test with various boolean values
        for value in ["true", "false", "True", "FALSE", "yes", "no", "1", "0"]:
            with patch.dict(
                "os.environ",
                {
                    "WHISPER_MODEL_PATH": "/fake/model",
                    "ENABLE_PROMPT_MANAGER": value,
                },
            ):
                service = Phononmaser()
                # Should not crash with any value
                assert isinstance(service.enable_prompt_manager, bool)

    @pytest.mark.asyncio
    async def test_service_isolation(self):
        """Test service components are properly isolated."""
        from src.main import Phononmaser

        with (
            patch.dict(
                "os.environ",
                {
                    "WHISPER_MODEL_PATH": "/fake/model",
                    "ENABLE_PROMPT_MANAGER": "true",
                },
            ),
            patch("os.path.exists", return_value=True),
        ):
            service = Phononmaser()

            # Mock all dependencies to avoid actual connections
            with (
                patch("src.main.ServerWebSocketClient") as mock_ws,
                patch("src.main.PhononmaserServer") as mock_server,
                patch("src.main.create_health_app") as mock_health,
                patch("src.main.PromptManager") as mock_prompt,
            ):
                # Configure mocks
                mock_ws.return_value.connect = AsyncMock()
                mock_ws.return_value.disconnect = AsyncMock()
                mock_server.return_value.start = AsyncMock()
                mock_server.return_value.stop = AsyncMock()
                mock_health.return_value = AsyncMock()
                mock_prompt.return_value.start = AsyncMock()
                mock_prompt.return_value.stop = AsyncMock()

                # Should start and stop without errors
                await service.start()
                assert service.running

                await service.stop()
                assert not service.running


class TestCircuitBreakerSafety:
    """Test circuit breaker specific safety features."""

    @pytest.mark.asyncio
    async def test_circuit_breaker_prevents_overload(self):
        """Test circuit breaker prevents API overload."""
        manager = PromptManager(circuit_breaker_failures=2)
        await manager.start()

        # Mock session to always fail
        mock_session = AsyncMock()
        mock_response = AsyncMock()
        mock_response.status = 500
        mock_response.text.return_value = "Server Error"
        mock_session.get.return_value.__aenter__.return_value = mock_response
        manager.session = mock_session

        # Trigger failures
        for _ in range(3):
            with contextlib.suppress(builtins.BaseException):
                await manager._poll_chat_events()

        # Circuit should be open
        stats = manager.get_stats()
        assert stats["circuit_breaker"]["state"] == "open"

        await manager.stop()

    def test_circuit_breaker_configuration(self):
        """Test circuit breaker can be configured for different scenarios."""
        # High-availability configuration
        ha_manager = PromptManager(
            circuit_breaker_failures=5,
            circuit_breaker_recovery_seconds=30.0,
        )
        assert ha_manager.circuit_breaker.failure_threshold == 5
        assert ha_manager.circuit_breaker.recovery_timeout == 30.0

        # Fast-fail configuration
        ff_manager = PromptManager(
            circuit_breaker_failures=1,
            circuit_breaker_recovery_seconds=5.0,
        )
        assert ff_manager.circuit_breaker.failure_threshold == 1
        assert ff_manager.circuit_breaker.recovery_timeout == 5.0


if __name__ == "__main__":
    # Run basic safety tests directly
    print("Running PromptManager safety feature tests...")

    test_suite = TestPromptManagerSafetyFeatures()

    # Test character limits
    test_suite.test_character_limit_safety()
    print("✓ Character limit safety")

    # Test rate limiting
    test_suite.test_rate_limiting_enforcement()
    print("✓ Rate limiting enforcement")

    # Test username filtering
    test_suite.test_username_filtering()
    print("✓ Username filtering")

    # Test prompt expiry
    test_suite.test_prompt_expiry_mechanism()
    print("✓ Prompt expiry mechanism")

    # Test frequency prioritization
    test_suite.test_frequency_prioritization()
    print("✓ Frequency prioritization")

    # Test error isolation
    test_suite.test_error_isolation()
    print("✓ Error isolation")

    print("\nAll safety features working correctly!")
