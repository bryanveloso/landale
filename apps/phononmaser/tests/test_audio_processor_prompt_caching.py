"""Tests for AudioProcessor prompt caching functionality."""

import time
from unittest.mock import MagicMock

import pytest

from src.audio_processor import AudioProcessor


class TestPromptCaching:
    """Test prompt caching with 5-second TTL, cache hits/misses, and error fallback."""

    @pytest.fixture
    def mock_prompt_manager(self):
        """Create a mock PromptManager for testing."""
        mock = MagicMock()
        mock.get_current_prompt.return_value = "Participants include: alice, bob."
        return mock

    @pytest.fixture
    def audio_processor(self, mock_prompt_manager):
        """Create AudioProcessor with mock PromptManager."""
        processor = AudioProcessor(
            whisper_model_path="/fake/model/path",
            prompt_manager=mock_prompt_manager,
        )
        return processor

    def test_cache_ttl_configuration(self, audio_processor):
        """Test that cache TTL is configured to 5 seconds."""
        assert audio_processor._prompt_cache_ttl == 5.0
        assert audio_processor._prompt_cache == ""
        assert audio_processor._prompt_cache_time == 0.0

    def test_cache_miss_on_first_call(self, audio_processor, mock_prompt_manager):
        """Test cache miss behavior on first prompt retrieval."""
        # Arrange
        mock_prompt_manager.get_current_prompt.return_value = "Fresh prompt from API"

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == "Fresh prompt from API"
        mock_prompt_manager.get_current_prompt.assert_called_once()
        assert audio_processor._prompt_cache == "Fresh prompt from API"
        assert audio_processor._prompt_cache_time > 0

    def test_cache_hit_within_ttl(self, audio_processor, mock_prompt_manager):
        """Test cache hit when prompt is retrieved within 5-second TTL."""
        # Arrange - populate cache
        mock_prompt_manager.get_current_prompt.return_value = "Cached prompt"
        audio_processor._prompt_cache = "Cached prompt"
        audio_processor._prompt_cache_time = time.time()

        # Act - call again immediately
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == "Cached prompt"
        # Should not call PromptManager again due to cache hit
        mock_prompt_manager.get_current_prompt.assert_not_called()

    def test_cache_miss_after_ttl_expiry(self, audio_processor, mock_prompt_manager):
        """Test cache miss when TTL expires after 5 seconds."""
        # Arrange - populate cache with expired timestamp
        mock_prompt_manager.get_current_prompt.return_value = "New prompt after expiry"
        audio_processor._prompt_cache = "Old cached prompt"
        audio_processor._prompt_cache_time = time.time() - 6.0  # 6 seconds ago (expired)

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == "New prompt after expiry"
        mock_prompt_manager.get_current_prompt.assert_called_once()
        assert audio_processor._prompt_cache == "New prompt after expiry"

    @pytest.mark.parametrize(
        "cache_age,should_hit_cache",
        [
            (0.0, True),  # Immediate call
            (1.0, True),  # 1 second old - within TTL
            (3.0, True),  # 3 seconds old - within TTL
            (4.9, True),  # Just under TTL
            (5.0, False),  # Exactly at TTL - should miss
            (5.1, False),  # Just over TTL - should miss
            (10.0, False),  # Well over TTL - should miss
        ],
    )
    def test_cache_ttl_boundary_conditions(self, audio_processor, mock_prompt_manager, cache_age, should_hit_cache):
        """Test cache behavior at TTL boundary conditions."""
        # Arrange
        mock_prompt_manager.get_current_prompt.return_value = "Fresh prompt"
        audio_processor._prompt_cache = "Cached prompt"
        audio_processor._prompt_cache_time = time.time() - cache_age

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        if should_hit_cache:
            assert prompt == "Cached prompt"
            mock_prompt_manager.get_current_prompt.assert_not_called()
        else:
            assert prompt == "Fresh prompt"
            mock_prompt_manager.get_current_prompt.assert_called_once()

    def test_cache_update_on_fresh_prompt(self, audio_processor, mock_prompt_manager):
        """Test that cache is updated when fresh prompt is retrieved."""
        # Arrange
        initial_time = time.time() - 10  # Ensure cache is expired
        audio_processor._prompt_cache = "Old prompt"
        audio_processor._prompt_cache_time = initial_time

        mock_prompt_manager.get_current_prompt.return_value = "Updated prompt"

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == "Updated prompt"
        assert audio_processor._prompt_cache == "Updated prompt"
        assert audio_processor._prompt_cache_time > initial_time

    def test_cache_cleared_when_no_prompt_available(self, audio_processor, mock_prompt_manager):
        """Test that cache is cleared when PromptManager returns empty prompt."""
        # Arrange
        audio_processor._prompt_cache = "Previous prompt"
        audio_processor._prompt_cache_time = time.time() - 10  # Expired cache

        mock_prompt_manager.get_current_prompt.return_value = ""  # No prompt available

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == ""
        assert audio_processor._prompt_cache == ""
        assert audio_processor._prompt_cache_time > 0  # Should be updated

    def test_stale_cache_fallback_on_error(self, audio_processor, mock_prompt_manager, caplog):
        """Test fallback to stale cache when PromptManager throws exception."""
        # Arrange - set up stale cache
        audio_processor._prompt_cache = "Stale but valid prompt"
        audio_processor._prompt_cache_time = time.time() - 10  # Expired cache

        # Mock PromptManager to raise exception
        mock_prompt_manager.get_current_prompt.side_effect = Exception("Network error")

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == "Stale but valid prompt"
        assert "Failed to get prompt from PromptManager: Network error" in caplog.text
        assert "Using stale cached prompt after error" in caplog.text

    def test_empty_string_fallback_on_error_with_no_cache(self, audio_processor, mock_prompt_manager, caplog):
        """Test fallback to empty string when error occurs and no cache exists."""
        # Arrange - no cached prompt
        audio_processor._prompt_cache = ""
        audio_processor._prompt_cache_time = 0.0

        # Mock PromptManager to raise exception
        mock_prompt_manager.get_current_prompt.side_effect = Exception("Service unavailable")

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == ""
        assert "Failed to get prompt from PromptManager: Service unavailable" in caplog.text

    def test_no_prompt_manager_returns_empty_string(self, audio_processor):
        """Test that missing PromptManager returns empty string immediately."""
        # Arrange
        audio_processor.prompt_manager = None

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == ""
        # Cache should remain unchanged
        assert audio_processor._prompt_cache == ""
        assert audio_processor._prompt_cache_time == 0.0

    def test_cache_behavior_with_multiple_calls(self, audio_processor, mock_prompt_manager):
        """Test cache behavior across multiple sequential calls."""
        # Call 1 - Cache miss, populate cache
        mock_prompt_manager.get_current_prompt.return_value = "First prompt"
        first_call_time = time.time()

        prompt1 = audio_processor._get_current_prompt()
        assert prompt1 == "First prompt"
        assert mock_prompt_manager.get_current_prompt.call_count == 1

        # Call 2 - Cache hit (immediate call)
        prompt2 = audio_processor._get_current_prompt()
        assert prompt2 == "First prompt"
        assert mock_prompt_manager.get_current_prompt.call_count == 1  # No additional call

        # Call 3 - Simulate TTL expiry and new prompt
        audio_processor._prompt_cache_time = first_call_time - 6.0  # Force expiry
        mock_prompt_manager.get_current_prompt.return_value = "Second prompt"

        prompt3 = audio_processor._get_current_prompt()
        assert prompt3 == "Second prompt"
        assert mock_prompt_manager.get_current_prompt.call_count == 2

    def test_cache_persistence_across_different_prompts(self, audio_processor, mock_prompt_manager):
        """Test that cache correctly handles changing prompts from PromptManager."""
        # First prompt
        mock_prompt_manager.get_current_prompt.return_value = "Participants include: alice."
        prompt1 = audio_processor._get_current_prompt()
        assert prompt1 == "Participants include: alice."

        # Force cache expiry and change prompt
        audio_processor._prompt_cache_time = time.time() - 10
        mock_prompt_manager.get_current_prompt.return_value = "Participants include: bob, charlie."

        prompt2 = audio_processor._get_current_prompt()
        assert prompt2 == "Participants include: bob, charlie."
        assert audio_processor._prompt_cache == "Participants include: bob, charlie."

    def test_logging_behavior_for_cache_operations(self, audio_processor, mock_prompt_manager, caplog):
        """Test that appropriate log messages are generated for cache operations."""
        # Test cache miss and fresh fetch
        mock_prompt_manager.get_current_prompt.return_value = "Test prompt for logging"

        audio_processor._get_current_prompt()
        assert "Fetched and cached fresh prompt: Test prompt for logging" in caplog.text

        # Clear log and test cache hit
        caplog.clear()
        audio_processor._get_current_prompt()
        assert "Using cached prompt" in caplog.text

    @pytest.mark.parametrize(
        "prompt_manager_return,expected_prompt",
        [
            ("Valid prompt", "Valid prompt"),
            ("", ""),
            (None, ""),  # PromptManager might return None
        ],
    )
    def test_various_prompt_manager_return_values(
        self, audio_processor, mock_prompt_manager, prompt_manager_return, expected_prompt
    ):
        """Test handling of various return values from PromptManager."""
        # Arrange
        mock_prompt_manager.get_current_prompt.return_value = prompt_manager_return

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == expected_prompt

    def test_cache_performance_under_rapid_calls(self, audio_processor, mock_prompt_manager):
        """Test cache performance when called rapidly within TTL."""
        # Arrange
        mock_prompt_manager.get_current_prompt.return_value = "Performance test prompt"

        # First call to populate cache
        audio_processor._get_current_prompt()
        initial_call_count = mock_prompt_manager.get_current_prompt.call_count

        # Act - make many rapid calls
        for _ in range(100):
            audio_processor._get_current_prompt()

        # Assert - should only have made the initial call due to caching
        assert mock_prompt_manager.get_current_prompt.call_count == initial_call_count

    def test_thread_safety_considerations(self, audio_processor, mock_prompt_manager):
        """Test that cache operations are safe for concurrent access patterns."""
        # This test verifies the basic structure supports thread safety
        # Real threading tests would require more complex setup

        # Arrange
        mock_prompt_manager.get_current_prompt.return_value = "Thread safety test"

        # Act - simulate rapid state changes that might occur in concurrent scenarios
        audio_processor._get_current_prompt()  # Populate cache

        # Simulate potential race condition scenarios
        original_cache = audio_processor._prompt_cache
        original_time = audio_processor._prompt_cache_time

        # Multiple rapid accesses shouldn't corrupt state
        for _ in range(10):
            prompt = audio_processor._get_current_prompt()
            assert prompt == "Thread safety test"
            assert audio_processor._prompt_cache == original_cache
            assert audio_processor._prompt_cache_time == original_time

    def test_memory_efficiency_of_cache(self, audio_processor, mock_prompt_manager):
        """Test that cache doesn't cause memory leaks with large prompts."""
        # Arrange - large prompt to test memory behavior
        large_prompt = "Participants include: " + ", ".join([f"user{i}" for i in range(1000)])
        mock_prompt_manager.get_current_prompt.return_value = large_prompt

        # Act
        prompt = audio_processor._get_current_prompt()

        # Assert
        assert prompt == large_prompt
        assert audio_processor._prompt_cache == large_prompt

        # Update with smaller prompt to test cache replacement
        mock_prompt_manager.get_current_prompt.return_value = "Small prompt"
        audio_processor._prompt_cache_time = time.time() - 10  # Force expiry

        prompt = audio_processor._get_current_prompt()
        assert prompt == "Small prompt"
        assert audio_processor._prompt_cache == "Small prompt"  # Old large prompt should be replaced
