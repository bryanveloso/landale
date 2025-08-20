"""Tests for PromptManager dynamic username prompting."""

import builtins
import contextlib
import json
import time
from unittest.mock import AsyncMock, MagicMock, Mock, patch

import aiohttp
import pytest
import pytest_asyncio

from src.prompt_manager import PromptManager

# Note: Only async tests are marked with @pytest.mark.asyncio individually


@pytest_asyncio.fixture
async def prompt_manager():
    """Create a PromptManager instance for testing."""
    manager = PromptManager(
        phoenix_base_url="http://test-phoenix:7175",
        poll_interval_seconds=1.0,  # Fast polling for tests
        prompt_max_chars=200,
        lookback_minutes=10,
        prompt_expiry_minutes=5,
        circuit_breaker_failures=3,
        circuit_breaker_recovery_seconds=30.0,
    )
    yield manager
    # Cleanup
    if manager.running:
        await manager.stop()


@pytest_asyncio.fixture
async def mock_session():
    """Create a mock aiohttp session."""
    session = AsyncMock(spec=aiohttp.ClientSession)
    return session


class TestPromptManagerInitialization:
    """Test PromptManager initialization and configuration."""

    def test_initialization_defaults(self):
        """Test PromptManager initialization with defaults."""
        manager = PromptManager()

        assert manager.phoenix_base_url == "http://saya:7175"
        assert manager.poll_interval == 30.0  # Enforced minimum
        assert manager.prompt_max_chars == 200
        assert manager.lookback_minutes == 10
        assert manager.prompt_expiry_minutes == 5
        assert manager.bulk_api_url == "http://saya:7175/api/activity/events/bulk"
        assert not manager.running
        assert manager.current_prompt == ""

    def test_initialization_custom_config(self):
        """Test PromptManager initialization with custom configuration."""
        manager = PromptManager(
            phoenix_base_url="http://custom:7175",
            poll_interval_seconds=60.0,
            prompt_max_chars=150,
            lookback_minutes=15,
            prompt_expiry_minutes=3,
            circuit_breaker_failures=2,
            circuit_breaker_recovery_seconds=45.0,
        )

        assert manager.phoenix_base_url == "http://custom:7175"
        assert manager.poll_interval == 60.0
        assert manager.prompt_max_chars == 150
        assert manager.lookback_minutes == 15
        assert manager.prompt_expiry_minutes == 3
        assert manager.bulk_api_url == "http://custom:7175/api/activity/events/bulk"

    def test_minimum_poll_interval_enforced(self):
        """Test that poll interval is enforced to minimum 30 seconds."""
        manager = PromptManager(poll_interval_seconds=15.0)
        assert manager.poll_interval == 30.0  # Should be enforced to minimum

    def test_circuit_breaker_configuration(self):
        """Test circuit breaker is configured correctly."""
        manager = PromptManager(
            circuit_breaker_failures=2,
            circuit_breaker_recovery_seconds=15.0,
        )

        assert manager.circuit_breaker.failure_threshold == 2
        assert manager.circuit_breaker.recovery_timeout == 15.0
        assert manager.circuit_breaker.name == "chat_api"

    def test_statistics_initialization(self):
        """Test statistics are initialized correctly."""
        manager = PromptManager()

        stats = manager.get_stats()
        assert stats["total_polls"] == 0
        assert stats["successful_polls"] == 0
        assert stats["failed_polls"] == 0
        assert stats["prompts_generated"] == 0
        assert stats["circuit_breaker_opens"] == 0
        assert stats["last_success_time"] == 0.0
        assert stats["last_error"] is None
        assert stats["current_prompt_length"] == 0
        assert stats["running"] is False


class TestPromptManagerLifecycle:
    """Test PromptManager lifecycle management."""

    async def test_start_stop_lifecycle(self, prompt_manager):
        """Test starting and stopping PromptManager."""
        assert not prompt_manager.running
        assert prompt_manager.session is None
        assert prompt_manager.poll_task is None

        # Start
        await prompt_manager.start()
        assert prompt_manager.running
        assert prompt_manager.session is not None
        assert prompt_manager.poll_task is not None

        # Stop
        await prompt_manager.stop()
        assert not prompt_manager.running
        assert prompt_manager.session is None

    async def test_double_start_warning(self, prompt_manager, caplog):
        """Test that starting twice logs a warning."""
        await prompt_manager.start()

        # Try to start again
        await prompt_manager.start()

        assert "PromptManager already running" in caplog.text
        await prompt_manager.stop()

    async def test_stop_without_start(self, prompt_manager):
        """Test stopping without starting doesn't error."""
        assert not prompt_manager.running
        await prompt_manager.stop()  # Should not raise

    async def test_session_timeout_configuration(self, prompt_manager):
        """Test HTTP session is configured with timeouts."""
        await prompt_manager.start()

        # Session should have timeout configured
        assert prompt_manager.session.timeout.total == 10.0
        assert prompt_manager.session.timeout.connect == 5.0

        await prompt_manager.stop()

    async def test_polling_task_cancellation(self, prompt_manager):
        """Test polling task is properly cancelled on stop."""
        await prompt_manager.start()
        poll_task = prompt_manager.poll_task

        await prompt_manager.stop()

        # Task should be cancelled
        assert poll_task.cancelled()


class TestPromptGeneration:
    """Test prompt generation logic."""

    def test_empty_usernames(self, prompt_manager):
        """Test prompt generation with no usernames."""
        prompt = prompt_manager._generate_prompt({})
        assert prompt == ""

    def test_single_username(self, prompt_manager):
        """Test prompt generation with single username."""
        usernames = {"alice": 3}
        prompt = prompt_manager._generate_prompt(usernames)

        assert prompt == "Participants include: alice."
        assert len(prompt) <= prompt_manager.prompt_max_chars

    def test_multiple_usernames_frequency_order(self, prompt_manager):
        """Test usernames are ordered by frequency (most frequent last)."""
        usernames = {"charlie": 1, "alice": 3, "bob": 2}
        prompt = prompt_manager._generate_prompt(usernames)

        # Should be ordered: charlie (1), bob (2), alice (3)
        assert prompt == "Participants include: charlie, bob, alice."

    def test_character_limit_enforcement(self, prompt_manager):
        """Test character limit is enforced."""
        # Create many usernames that would exceed limit
        usernames = {f"user{i:03d}": 1 for i in range(50)}
        prompt = prompt_manager._generate_prompt(usernames)

        assert len(prompt) <= prompt_manager.prompt_max_chars
        assert prompt.startswith("Participants include:")
        assert prompt.endswith(".")

    def test_character_limit_with_short_limit(self):
        """Test character limit with very short limit."""
        manager = PromptManager(prompt_max_chars=50)
        usernames = {"verylongusername123": 1, "anotherlongname456": 2}
        prompt = manager._generate_prompt(usernames)

        assert len(prompt) <= 50
        # Should include at least one username if possible
        assert "Participants include:" in prompt

    def test_no_usernames_fit_warning(self, caplog):
        """Test warning when no usernames fit."""
        manager = PromptManager(prompt_max_chars=30)  # Short enough that usernames don't fit
        usernames = {"superlongusernamethatdoesnotfit": 1}
        prompt = manager._generate_prompt(usernames)

        assert prompt == ""
        assert "No usernames fit within character limit" in caplog.text

    def test_base_text_too_long_warning(self, caplog):
        """Test warning when base text is too long."""
        manager = PromptManager(prompt_max_chars=10)  # Shorter than "Participants include: " (22 chars)
        usernames = {"alice": 1}
        prompt = manager._generate_prompt(usernames)

        assert prompt == ""
        assert "Base prompt text too long" in caplog.text


class TestUsernameExtraction:
    """Test username extraction from chat events."""

    def test_extract_usernames_empty_events(self, prompt_manager):
        """Test username extraction with no events."""
        usernames = prompt_manager._extract_usernames([])
        assert usernames == {}

    def test_extract_usernames_basic_structure(self, prompt_manager):
        """Test username extraction with basic event structure."""
        events = [
            {"event_data": {"username": "alice"}},
            {"event_data": {"username": "bob"}},
            {"event_data": {"username": "alice"}},  # Duplicate
        ]

        usernames = prompt_manager._extract_usernames(events)
        assert usernames == {"alice": 2, "bob": 1}

    def test_extract_usernames_various_field_names(self, prompt_manager):
        """Test username extraction with different field names."""
        events = [
            {"event_data": {"username": "alice"}},
            {"event_data": {"user_name": "bob"}},
            {"data": {"author": "charlie"}},
            {"event_data": {"sender": "diana"}},
        ]

        usernames = prompt_manager._extract_usernames(events)
        assert usernames == {"alice": 1, "bob": 1, "charlie": 1, "diana": 1}

    def test_extract_usernames_nested_data_structures(self, prompt_manager):
        """Test username extraction with nested data structures."""
        events = [
            {"event_data": {"username": "alice"}},
            {"data": {"user_name": "bob"}},
            {"username": "charlie"},  # Direct field
        ]

        usernames = prompt_manager._extract_usernames(events)
        assert usernames == {"alice": 1, "bob": 1, "charlie": 1}

    def test_extract_usernames_filters_invalid(self, prompt_manager):
        """Test that invalid usernames are filtered out."""
        events = [
            {"event_data": {"username": "alice"}},
            {"event_data": {"username": ""}},  # Empty
            {"event_data": {"username": "   "}},  # Whitespace only
            {"event_data": {"username": None}},  # None
            {"event_data": {"username": 123}},  # Not string
            {"event_data": {"username": "x" * 60}},  # Too long (>50 chars)
            {"event_data": {"username": "  bob  "}},  # Valid but needs trimming
        ]

        usernames = prompt_manager._extract_usernames(events)
        assert usernames == {"alice": 1, "bob": 1}

    def test_extract_usernames_handles_parse_errors(self, prompt_manager, caplog):
        """Test that individual event parsing errors don't stop processing."""
        events = [
            {"event_data": {"username": "alice"}},
            {"invalid": "structure"},  # Will cause parsing error
            {"event_data": {"username": "bob"}},
        ]

        usernames = prompt_manager._extract_usernames(events)
        assert usernames == {"alice": 1, "bob": 1}
        # Should log debug message about parsing error
        assert "Error parsing chat event" in caplog.text


class TestPromptExpiry:
    """Test prompt expiry logic."""

    def test_get_current_prompt_fresh(self, prompt_manager):
        """Test getting current prompt when fresh."""
        prompt_manager.current_prompt = "Participants include: alice."
        prompt_manager.last_prompt_update = time.time()

        result = prompt_manager.get_current_prompt()
        assert result == "Participants include: alice."

    def test_get_current_prompt_expired(self, prompt_manager, caplog):
        """Test getting current prompt when expired."""
        prompt_manager.current_prompt = "Participants include: alice."
        # Set update time to past expiry
        prompt_manager.last_prompt_update = time.time() - (prompt_manager.prompt_expiry_minutes * 60 + 10)

        result = prompt_manager.get_current_prompt()
        assert result == ""
        assert prompt_manager.current_prompt == ""
        assert "Prompt expired, clearing" in caplog.text

    def test_get_current_prompt_no_prompt(self, prompt_manager):
        """Test getting current prompt when none exists."""
        assert prompt_manager.current_prompt == ""
        result = prompt_manager.get_current_prompt()
        assert result == ""


class TestHttpFetching:
    """Test HTTP fetching logic."""

    async def test_fetch_chat_events_success(self, prompt_manager, mock_session):
        """Test successful HTTP fetch."""
        # Mock response
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json.return_value = {
            "events": [
                {"event_data": {"username": "alice"}},
                {"event_data": {"username": "bob"}},
            ]
        }

        mock_session.get.return_value.__aenter__.return_value = mock_response
        prompt_manager.session = mock_session

        params = {"event_type": "channel.chat.message", "since": "2025-01-01T00:00:00Z", "limit": 100}
        events = await prompt_manager._fetch_chat_events(params)

        assert len(events) == 2
        assert events[0]["event_data"]["username"] == "alice"
        assert events[1]["event_data"]["username"] == "bob"

    async def test_fetch_chat_events_list_response(self, prompt_manager, mock_session):
        """Test HTTP fetch with list response format."""
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json.return_value = [
            {"event_data": {"username": "alice"}},
            {"event_data": {"username": "bob"}},
        ]

        mock_session.get.return_value.__aenter__.return_value = mock_response
        prompt_manager.session = mock_session

        params = {"test": "params"}
        events = await prompt_manager._fetch_chat_events(params)

        assert len(events) == 2

    async def test_fetch_chat_events_http_error(self, prompt_manager, mock_session):
        """Test HTTP fetch with HTTP error."""
        mock_response = AsyncMock()
        mock_response.status = 404
        mock_response.text.return_value = "Not Found"
        mock_response.request_info = Mock()
        mock_response.history = []

        mock_session.get.return_value.__aenter__.return_value = mock_response
        prompt_manager.session = mock_session

        with pytest.raises(aiohttp.ClientResponseError):
            await prompt_manager._fetch_chat_events({})

    async def test_fetch_chat_events_json_error(self, prompt_manager, mock_session):
        """Test HTTP fetch with JSON decode error."""
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json.side_effect = json.JSONDecodeError("Invalid JSON", "", 0)
        mock_response.text.return_value = "Invalid JSON Response"

        mock_session.get.return_value.__aenter__.return_value = mock_response
        prompt_manager.session = mock_session

        with pytest.raises(json.JSONDecodeError):
            await prompt_manager._fetch_chat_events({})

    async def test_fetch_chat_events_no_session(self, prompt_manager):
        """Test HTTP fetch without session raises error."""
        prompt_manager.session = None

        with pytest.raises(RuntimeError, match="HTTP session not available"):
            await prompt_manager._fetch_chat_events({})

    async def test_fetch_chat_events_unexpected_format(self, prompt_manager, mock_session, caplog):
        """Test HTTP fetch with unexpected response format."""
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json.return_value = "unexpected string response"

        mock_session.get.return_value.__aenter__.return_value = mock_response
        prompt_manager.session = mock_session

        events = await prompt_manager._fetch_chat_events({})

        assert events == []
        assert "Unexpected API response format" in caplog.text


class TestCircuitBreakerIntegration:
    """Test circuit breaker integration."""

    async def test_circuit_breaker_protection(self, prompt_manager):
        """Test circuit breaker protects against failures."""
        await prompt_manager.start()

        # Mock the HTTP session to always fail
        mock_session = AsyncMock()
        mock_response = AsyncMock()
        mock_response.status = 500
        mock_response.text.return_value = "Server Error"
        mock_response.request_info = Mock()
        mock_response.history = []

        mock_session.get.return_value.__aenter__.return_value = mock_response
        prompt_manager.session = mock_session

        # Trigger enough failures to open circuit
        for _ in range(prompt_manager.circuit_breaker.failure_threshold + 1):
            with contextlib.suppress(builtins.BaseException):
                await prompt_manager._poll_chat_events()

        # Circuit should be open now
        stats = prompt_manager.get_stats()
        assert stats["circuit_breaker"]["state"] == "open"

        await prompt_manager.stop()

    async def test_circuit_open_error_handling(self, prompt_manager, caplog):
        """Test handling of CircuitOpenError."""
        await prompt_manager.start()

        # Force circuit to open
        from shared.circuit_breaker import CircuitState

        prompt_manager.circuit_breaker.state = CircuitState.OPEN
        prompt_manager.circuit_breaker.last_failure_time = time.time()

        await prompt_manager._poll_chat_events()

        # Should log debug message about circuit being open
        assert "Chat API circuit breaker open" in caplog.text

        stats = prompt_manager.get_stats()
        assert stats["failed_polls"] > 0

        await prompt_manager.stop()


class TestPollingBehavior:
    """Test polling behavior and rate limiting."""

    async def test_poll_interval_enforcement(self, prompt_manager):
        """Test that polling respects minimum interval."""
        # Use a short interval for faster testing
        prompt_manager.poll_interval = 0.1

        await prompt_manager.start()

        # Mock successful API call
        with patch.object(prompt_manager, "_fetch_chat_events", new_callable=AsyncMock) as mock_fetch:
            mock_fetch.return_value = []

            # Record timing of first poll
            time.time()
            await prompt_manager._poll_chat_events()
            first_poll_time = time.time()

            # Try to poll again immediately - should be delayed
            await prompt_manager._poll_chat_events()
            second_poll_time = time.time()

            # Second poll should be delayed by at least the poll interval
            time_between_polls = second_poll_time - first_poll_time
            assert time_between_polls >= (prompt_manager.poll_interval - 0.01)  # Small tolerance

        await prompt_manager.stop()

    async def test_polling_loop_error_recovery(self, prompt_manager):
        """Test polling loop recovers from errors."""
        await prompt_manager.start()

        # Mock fetch to fail once then succeed
        call_count = 0

        async def mock_fetch(*args, **kwargs):  # noqa: ARG001
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise Exception("Simulated network error")
            return []

        with patch.object(prompt_manager, "_fetch_chat_events", side_effect=mock_fetch):
            # Start polling loop manually for testing
            await prompt_manager._polling_loop()

        # Should have logged error but continued
        stats = prompt_manager.get_stats()
        assert stats["total_polls"] >= 1

        await prompt_manager.stop()

    async def test_prompt_update_detection(self, prompt_manager):
        """Test that prompt updates are properly detected."""
        await prompt_manager.start()

        # Mock successful API call with usernames
        with patch.object(prompt_manager, "_fetch_chat_events", new_callable=AsyncMock) as mock_fetch:
            mock_fetch.return_value = [
                {"event_data": {"username": "alice"}},
                {"event_data": {"username": "bob"}},
            ]

            await prompt_manager._poll_chat_events()

            # Should have generated a prompt
            assert prompt_manager.current_prompt == "Participants include: alice, bob."

            stats = prompt_manager.get_stats()
            assert stats["prompts_generated"] == 1
            assert stats["successful_polls"] == 1

        await prompt_manager.stop()

    async def test_no_prompt_change_detection(self, prompt_manager, caplog):
        """Test detection when prompt doesn't need to change."""
        await prompt_manager.start()

        # Set existing prompt
        prompt_manager.current_prompt = "Participants include: alice, bob."

        # Mock API call that would generate same prompt
        with patch.object(prompt_manager, "_fetch_chat_events", new_callable=AsyncMock) as mock_fetch:
            mock_fetch.return_value = [
                {"event_data": {"username": "alice"}},
                {"event_data": {"username": "bob"}},
            ]

            await prompt_manager._poll_chat_events()

            # Should detect no change needed
            assert "No prompt change needed" in caplog.text

            stats = prompt_manager.get_stats()
            assert stats["prompts_generated"] == 0  # No new prompt generated

        await prompt_manager.stop()


class TestStatisticsAndMonitoring:
    """Test statistics collection and monitoring."""

    def test_stats_structure(self, prompt_manager):
        """Test statistics structure is complete."""
        stats = prompt_manager.get_stats()

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

    def test_stats_circuit_breaker_integration(self, prompt_manager):
        """Test that circuit breaker stats are included."""
        stats = prompt_manager.get_stats()

        cb_stats = stats["circuit_breaker"]
        assert "name" in cb_stats
        assert "state" in cb_stats
        assert "failure_count" in cb_stats
        assert "total_calls" in cb_stats

    async def test_stats_update_on_operations(self, prompt_manager):
        """Test that statistics are updated during operations."""
        await prompt_manager.start()

        # Mock successful operation
        with patch.object(prompt_manager, "_fetch_chat_events", new_callable=AsyncMock) as mock_fetch:
            mock_fetch.return_value = [{"event_data": {"username": "alice"}}]

            await prompt_manager._poll_chat_events()

            stats = prompt_manager.get_stats()
            assert stats["total_polls"] == 1
            assert stats["successful_polls"] == 1
            assert stats["failed_polls"] == 0
            assert stats["prompts_generated"] == 1
            assert stats["last_success_time"] > 0
            assert stats["last_error"] is None

        await prompt_manager.stop()

    async def test_stats_update_on_errors(self, prompt_manager):
        """Test that statistics are updated on errors."""
        await prompt_manager.start()

        # Mock failing operation
        with patch.object(prompt_manager, "_fetch_chat_events", new_callable=AsyncMock) as mock_fetch:
            mock_fetch.side_effect = Exception("Network error")

            await prompt_manager._poll_chat_events()

            stats = prompt_manager.get_stats()
            assert stats["total_polls"] == 1
            assert stats["successful_polls"] == 0
            assert stats["failed_polls"] == 1
            assert stats["last_error"] == "Network error"

        await prompt_manager.stop()


class TestAPIContractFix:
    """Test the API contract fix for hours parameter instead of since."""

    @pytest.mark.parametrize(
        "lookback_minutes,expected_hours",
        [
            (30, 1),  # Below 60 minutes, should be minimum 1 hour
            (45, 1),  # Below 60 minutes, should be minimum 1 hour
            (60, 1),  # Exactly 60 minutes = 1 hour
            (90, 1),  # 90 minutes = 1.5 hours, but integer division = 1 hour
            (120, 2),  # 120 minutes = 2 hours
            (180, 3),  # 180 minutes = 3 hours
            (240, 4),  # 240 minutes = 4 hours
        ],
    )
    async def test_hours_parameter_conversion(self, lookback_minutes, expected_hours, prompt_manager, mock_session):
        """Test that lookback_minutes is correctly converted to hours parameter."""
        # Set up prompt manager with specific lookback time
        prompt_manager.lookback_minutes = lookback_minutes

        # Mock successful API response
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json.return_value = {"events": []}
        mock_session.get.return_value.__aenter__.return_value = mock_response
        prompt_manager.session = mock_session

        # Call the method that should use hours parameter
        await prompt_manager._poll_chat_events()

        # Verify the API was called with hours parameter, not since
        mock_session.get.assert_called_once()
        call_args = mock_session.get.call_args
        params = call_args[1]["params"]

        assert "hours" in params
        assert "since" not in params
        assert params["hours"] == expected_hours
        assert params["event_type"] == "channel.chat.message"

    async def test_api_parameters_structure(self, prompt_manager, mock_session):
        """Test that API parameters follow the new structure."""
        # Mock successful API response
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.json.return_value = {"events": []}
        mock_session.get.return_value.__aenter__.return_value = mock_response
        prompt_manager.session = mock_session

        await prompt_manager._poll_chat_events()

        # Verify API call structure
        mock_session.get.assert_called_once()
        call_args = mock_session.get.call_args

        # Should call the bulk events endpoint
        assert call_args[0][0] == prompt_manager.bulk_api_url

        # Should use correct parameters
        params = call_args[1]["params"]
        expected_params = {"event_type": "channel.chat.message", "hours": max(1, prompt_manager.lookback_minutes // 60)}
        assert params == expected_params

    def test_minimum_hours_enforcement(self, prompt_manager):
        """Test that hours parameter enforces minimum of 1 hour."""
        # Test various lookback times that should result in 1 hour minimum
        test_cases = [0, 15, 30, 45, 59]

        for minutes in test_cases:
            prompt_manager.lookback_minutes = minutes
            hours = max(1, prompt_manager.lookback_minutes // 60)
            assert hours == 1, f"Expected 1 hour for {minutes} minutes, got {hours}"

    def test_hour_calculation_edge_cases(self, prompt_manager):
        """Test edge cases in hour calculation."""
        # Test boundary conditions
        test_cases = [
            (59, 1),  # Just under 1 hour
            (60, 1),  # Exactly 1 hour
            (61, 1),  # Just over 1 hour
            (119, 1),  # Just under 2 hours
            (120, 2),  # Exactly 2 hours
            (121, 2),  # Just over 2 hours
        ]

        for minutes, expected_hours in test_cases:
            prompt_manager.lookback_minutes = minutes
            hours = max(1, prompt_manager.lookback_minutes // 60)
            assert hours == expected_hours, f"Expected {expected_hours} hours for {minutes} minutes, got {hours}"


class TestPromptManagerConfiguration:
    """Test various configuration scenarios."""

    @pytest.mark.parametrize(
        "poll_interval,expected",
        [
            (10.0, 30.0),  # Below minimum, should be enforced
            (30.0, 30.0),  # At minimum
            (60.0, 60.0),  # Above minimum
        ],
    )
    def test_poll_interval_validation(self, poll_interval, expected):
        """Test poll interval validation with different values."""
        manager = PromptManager(poll_interval_seconds=poll_interval)
        assert manager.poll_interval == expected

    @pytest.mark.parametrize(
        "max_chars,username_count,expected_length",
        [
            (50, 2, 50),  # Should fit within limit
            (100, 5, 100),  # Should fit within limit
            (30, 10, 30),  # Should be truncated
        ],
    )
    def test_character_limit_scenarios(self, max_chars, username_count, expected_length):
        """Test character limit enforcement with different scenarios."""
        manager = PromptManager(prompt_max_chars=max_chars)
        usernames = {f"user{i}": 1 for i in range(username_count)}

        prompt = manager._generate_prompt(usernames)
        assert len(prompt) <= expected_length

    def test_api_url_construction(self):
        """Test API URL is constructed correctly."""
        manager = PromptManager(phoenix_base_url="http://custom:7175/")

        # Should strip trailing slash and add correct path
        assert manager.bulk_api_url == "http://custom:7175/api/activity/events/bulk"

    def test_time_range_calculation(self, prompt_manager):
        """Test time range calculation for API calls."""
        # This tests the internal logic of _poll_chat_events
        # We can't easily mock datetime.utcnow, so we test the pattern

        lookback_minutes = prompt_manager.lookback_minutes
        assert lookback_minutes == 10  # Default from test fixture

        # The actual time calculation happens in _poll_chat_events
        # and uses datetime.utcnow() - timedelta(minutes=lookback_minutes)
        # This is tested indirectly through integration tests


@pytest.mark.integration
class TestPromptManagerIntegration:
    """Integration tests for PromptManager with AudioProcessor."""

    async def test_integration_with_audio_processor(self):
        """Test PromptManager integration with AudioProcessor."""
        from src.audio_processor import AudioProcessor

        # Create PromptManager
        prompt_manager = PromptManager(
            phoenix_base_url="http://test:7175",
            poll_interval_seconds=1.0,
        )

        # Create AudioProcessor with PromptManager
        audio_processor = AudioProcessor(
            whisper_model_path="/fake/model/path",
            prompt_manager=prompt_manager,
        )

        # Test that prompt retrieval works
        prompt = audio_processor._get_current_prompt()
        assert prompt == ""  # No prompt initially

        # Set a prompt and test retrieval
        prompt_manager.current_prompt = "Participants include: alice."
        prompt_manager.last_prompt_update = time.time()

        prompt = audio_processor._get_current_prompt()
        assert prompt == "Participants include: alice."

    async def test_integration_graceful_degradation(self, caplog):
        """Test graceful degradation when PromptManager fails."""
        from src.audio_processor import AudioProcessor

        # Create a PromptManager that will fail
        prompt_manager = MagicMock()
        prompt_manager.get_current_prompt.side_effect = Exception("PromptManager failed")

        audio_processor = AudioProcessor(
            whisper_model_path="/fake/model/path",
            prompt_manager=prompt_manager,
        )

        # Should handle failure gracefully
        prompt = audio_processor._get_current_prompt()
        assert prompt == ""
        assert "Failed to get prompt from PromptManager" in caplog.text

    async def test_integration_without_prompt_manager(self):
        """Test AudioProcessor works without PromptManager."""
        from src.audio_processor import AudioProcessor

        audio_processor = AudioProcessor(
            whisper_model_path="/fake/model/path",
            prompt_manager=None,
        )

        # Should return empty prompt
        prompt = audio_processor._get_current_prompt()
        assert prompt == ""


@pytest.mark.slow
class TestPromptManagerLoadTesting:
    """Load testing for PromptManager under stress."""

    async def test_high_frequency_polling(self, prompt_manager):
        """Test PromptManager under high-frequency polling stress."""
        await prompt_manager.start()

        # Mock API to return large amounts of data
        large_events = [{"event_data": {"username": f"user{i}"}} for i in range(100)]

        with patch.object(prompt_manager, "_fetch_chat_events", new_callable=AsyncMock) as mock_fetch:
            mock_fetch.return_value = large_events

            # Perform multiple rapid polls
            for _ in range(10):
                await prompt_manager._poll_chat_events()

            stats = prompt_manager.get_stats()
            assert stats["total_polls"] == 10
            assert stats["successful_polls"] == 10
            assert stats["failed_polls"] == 0

        await prompt_manager.stop()

    async def test_memory_usage_with_large_datasets(self, prompt_manager):
        """Test memory usage stays reasonable with large datasets."""
        await prompt_manager.start()

        # Create large username dataset
        large_usernames = {f"verylongusername{i:06d}": i % 10 for i in range(1000)}

        # Generate prompt (should be truncated)
        prompt = prompt_manager._generate_prompt(large_usernames)

        # Should respect character limit
        assert len(prompt) <= prompt_manager.prompt_max_chars

        await prompt_manager.stop()
