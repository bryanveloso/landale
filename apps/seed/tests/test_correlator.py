"""Test correlator buffer management and event processing."""

from datetime import datetime

import pytest

from src.correlator import StreamCorrelator
from src.events import ChatMessage, EmoteEvent, TranscriptionEvent, ViewerInteractionEvent


class TestCorrelator:
    @pytest.fixture
    def correlator(self, mock_lms_client, mock_context_client):
        """Create correlator with small buffer for testing."""
        return StreamCorrelator(
            lms_client=mock_lms_client,
            context_client=mock_context_client,
            context_window_seconds=120,
            analysis_interval_seconds=30,
            max_buffer_size=10,  # Small buffer for testing overflow
        )

    @pytest.mark.asyncio
    async def test_buffer_management(self, correlator):
        """Test that buffers are properly managed with counter tracking."""
        # Add transcription
        event = TranscriptionEvent(
            timestamp=int(datetime.now().timestamp() * 1_000_000), text="Test transcription", duration=1.0
        )
        await correlator.add_transcription(event)

        # Check buffer and counter
        assert len(correlator.transcription_buffer) == 1
        assert correlator._buffer_counts["transcription"] == 1
        assert correlator.overflow_counts["transcription"] == 0

    @pytest.mark.asyncio
    async def test_buffer_overflow(self, correlator):
        """Test that buffer overflow is handled correctly."""
        # Fill buffer to capacity
        base_time = int(datetime.now().timestamp() * 1_000_000)
        for i in range(10):
            event = TranscriptionEvent(timestamp=base_time + i * 1000, text=f"Test {i}", duration=0.5)
            await correlator.add_transcription(event)

        # Verify buffer is at capacity
        assert len(correlator.transcription_buffer) == 10
        assert correlator._buffer_counts["transcription"] == 10
        assert correlator.overflow_counts["transcription"] == 0

        # Add one more to trigger overflow
        overflow_event = TranscriptionEvent(timestamp=base_time + 11000, text="Overflow", duration=0.5)
        await correlator.add_transcription(overflow_event)

        # Check overflow handling
        assert len(correlator.transcription_buffer) == 10  # Still at max
        assert correlator._buffer_counts["transcription"] == 10  # Counter doesn't increase
        assert correlator.overflow_counts["transcription"] == 1  # Overflow incremented

        # Verify oldest was removed (deque behavior)
        assert correlator.transcription_buffer[0].text == "Test 1"
        assert correlator.transcription_buffer[-1].text == "Overflow"

    @pytest.mark.asyncio
    async def test_cleanup_old_events(self, correlator):
        """Test that old events are cleaned up based on time window."""
        # Set a shorter context window for testing
        correlator.context_window = 60  # 60 seconds

        now = datetime.now()
        now_us = int(now.timestamp() * 1_000_000)
        old_time_us = int((now.timestamp() - 120) * 1_000_000)  # 2 minutes old
        recent_time_us = int((now.timestamp() - 30) * 1_000_000)  # 30 seconds old

        # Add old event - it will be cleaned up immediately
        old_event = TranscriptionEvent(timestamp=old_time_us, text="Old", duration=1.0)
        await correlator.add_transcription(old_event)

        # Old event should be removed immediately due to cleanup
        assert len(correlator.transcription_buffer) == 0
        assert correlator._buffer_counts["transcription"] == 0

        # Add recent event - should stay
        recent_event = TranscriptionEvent(timestamp=recent_time_us, text="Recent", duration=1.0)
        await correlator.add_transcription(recent_event)

        assert len(correlator.transcription_buffer) == 1
        assert correlator._buffer_counts["transcription"] == 1
        assert correlator.transcription_buffer[0].text == "Recent"

        # Add current event - both should remain
        new_event = TranscriptionEvent(timestamp=now_us, text="New", duration=1.0)
        await correlator.add_transcription(new_event)

        assert len(correlator.transcription_buffer) == 2
        assert correlator._buffer_counts["transcription"] == 2
        assert correlator.transcription_buffer[0].text == "Recent"
        assert correlator.transcription_buffer[1].text == "New"

    @pytest.mark.asyncio
    async def test_correlation_window(self, correlator):
        """Test chat correlation within window."""
        now = datetime.now().timestamp() * 1_000_000

        # Add transcription
        trans_event = TranscriptionEvent(timestamp=int(now), text="Hello chat", duration=1.0)
        await correlator.add_transcription(trans_event)

        # Add chat message within correlation window (5 seconds later)
        chat_event = ChatMessage(
            timestamp=int(now + 5_000_000),  # 5 seconds later in microseconds
            username="viewer1",
            message="Hello streamer!",
            emotes=[],
            native_emotes=[],
        )
        await correlator.add_chat_message(chat_event)

        # Verify both are in buffers
        assert len(correlator.transcription_buffer) == 1
        assert len(correlator.chat_buffer) == 1
        assert correlator._buffer_counts["transcription"] == 1
        assert correlator._buffer_counts["chat"] == 1

    @pytest.mark.asyncio
    async def test_get_buffer_stats(self, correlator):
        """Test that buffer stats are returned correctly."""
        # Add various events
        base_time = int(datetime.now().timestamp() * 1_000_000)

        await correlator.add_transcription(TranscriptionEvent(timestamp=base_time, text="Test", duration=1.0))
        await correlator.add_chat_message(
            ChatMessage(timestamp=base_time + 1000, username="user", message="Hi", emotes=[])
        )
        await correlator.add_emote(
            EmoteEvent(timestamp=base_time + 2000, username="user", emote_name="Kappa", emote_id="123")
        )
        await correlator.add_viewer_interaction(
            ViewerInteractionEvent(
                timestamp=base_time + 3000, interaction_type="follow", username="user", user_id="123"
            )
        )

        # Get stats
        stats = correlator.get_buffer_stats()

        # Verify stats
        assert stats["buffer_sizes"]["transcription"] == 1
        assert stats["buffer_sizes"]["chat"] == 1
        assert stats["buffer_sizes"]["emote"] == 1
        assert stats["buffer_sizes"]["interaction"] == 1
        assert stats["total_events"] == 4

        # Verify limits
        assert stats["buffer_limits"]["transcription"] == 10
        assert stats["buffer_limits"]["chat"] == 20  # 2x max_buffer_size
        assert stats["buffer_limits"]["emote"] == 10
        assert stats["buffer_limits"]["interaction"] == 5  # max_buffer_size // 2

    @pytest.mark.asyncio
    async def test_counter_never_negative(self, correlator):
        """Test that buffer counts never go negative."""
        # This could happen if cleanup removes more than expected
        # The max(0, ...) in cleanup should prevent this

        # Manually set a low count
        correlator._buffer_counts["transcription"] = 1

        # Add an old event that will be immediately cleaned up
        old_time = int((datetime.now().timestamp() - 200) * 1_000_000)  # Very old
        old_event = TranscriptionEvent(timestamp=old_time, text="Old", duration=1.0)

        # This should add then immediately remove
        await correlator.add_transcription(old_event)

        # Counter should not go negative
        assert correlator._buffer_counts["transcription"] >= 0
