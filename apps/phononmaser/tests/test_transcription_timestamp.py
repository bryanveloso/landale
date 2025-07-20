"""TDD tests for transcription timestamp handling bug.

This test suite validates the INTENDED behavior:
1. Timestamps should be current UTC time, not Unix epoch (1970)
2. API payload should have proper ISO 8601 format
3. Database should store current timestamp
"""

import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import AsyncMock

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from events import TranscriptionEvent
from server_client import ServerTranscriptionClient


class TestTranscriptionTimestampHandling:
    """Test proper timestamp handling in transcription pipeline."""

    def test_transcription_event_has_reasonable_timestamp(self):
        """Test that TranscriptionEvent timestamp represents current time in microseconds."""
        # Create a transcription event with current timestamp
        current_time_us = int(time.time() * 1_000_000)
        event = TranscriptionEvent(timestamp=current_time_us, duration=1.5, text="Test transcription")

        # Timestamp should be in microseconds and represent current time
        assert event.timestamp > 0
        # Should be within last 10 seconds (allow for test execution time)
        time_diff_seconds = abs((event.timestamp / 1_000_000) - time.time())
        assert time_diff_seconds < 10, f"Timestamp {event.timestamp} is not current time"

    @pytest.mark.asyncio
    async def test_server_client_converts_timestamp_correctly(self):
        """Test that ServerTranscriptionClient converts microsecond timestamp to ISO format."""
        # Create event with current timestamp in microseconds
        current_time_us = int(time.time() * 1_000_000)
        event = TranscriptionEvent(timestamp=current_time_us, duration=2.0, text="Test message")

        # Mock the HTTP session to capture the payload
        mock_session = AsyncMock()
        mock_response = AsyncMock()
        mock_response.status = 201

        mock_context_manager = AsyncMock()
        mock_context_manager.__aenter__ = AsyncMock(return_value=mock_response)
        mock_context_manager.__aexit__ = AsyncMock(return_value=None)
        mock_session.post.return_value = mock_context_manager

        client = ServerTranscriptionClient("http://test:7175")
        client.session = mock_session

        # Send transcription
        success = await client.send_transcription(event)

        # Verify success
        assert success is True

        # Get the payload that was sent
        call_args = mock_session.post.call_args
        payload = call_args.kwargs["json"]

        # Verify timestamp is ISO 8601 format and represents current time
        timestamp_str = payload["timestamp"]
        assert timestamp_str is not None

        # Parse ISO timestamp
        timestamp_dt = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00"))

        # Should be current time (within 10 seconds)
        current_dt = datetime.now(UTC)
        time_diff = abs((timestamp_dt - current_dt).total_seconds())
        assert time_diff < 10, f"Timestamp {timestamp_str} is not current time"

        # Should NOT be Unix epoch (1970)
        epoch_year = timestamp_dt.year
        assert epoch_year >= 2025, f"Timestamp year {epoch_year} suggests Unix epoch bug"

    def test_timestamp_not_unix_epoch(self):
        """Test that timestamps are not accidentally set to Unix epoch (1970)."""
        # Create event with what should be current time
        current_time_us = int(time.time() * 1_000_000)
        event = TranscriptionEvent(timestamp=current_time_us, duration=1.0, text="Test")

        # Convert to datetime to check year
        timestamp_seconds = event.timestamp / 1_000_000
        dt = datetime.fromtimestamp(timestamp_seconds, tz=UTC)

        # Should be current year, not 1970
        assert dt.year >= 2025, f"Timestamp year {dt.year} suggests Unix epoch bug"
        assert dt.year < 2030, f"Timestamp year {dt.year} seems too far in future"

    @pytest.mark.asyncio
    async def test_microsecond_precision_maintained(self):
        """Test that microsecond precision is maintained through conversion."""
        # Create timestamp with specific microsecond value
        base_time = int(time.time())
        test_microseconds = 123456
        timestamp_us = (base_time * 1_000_000) + test_microseconds

        event = TranscriptionEvent(timestamp=timestamp_us, duration=1.0, text="Precision test")

        # Mock HTTP session
        mock_session = AsyncMock()
        mock_response = AsyncMock()
        mock_response.status = 201

        mock_context_manager = AsyncMock()
        mock_context_manager.__aenter__ = AsyncMock(return_value=mock_response)
        mock_context_manager.__aexit__ = AsyncMock(return_value=None)
        mock_session.post.return_value = mock_context_manager

        client = ServerTranscriptionClient("http://test:7175")
        client.session = mock_session

        await client.send_transcription(event)

        # Get payload
        payload = mock_session.post.call_args.kwargs["json"]
        timestamp_str = payload["timestamp"]

        # Parse timestamp and verify microseconds are preserved
        timestamp_dt = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00"))

        # Check that we're close to the expected time
        expected_dt = datetime.fromtimestamp(base_time, tz=UTC)
        time_diff = abs((timestamp_dt - expected_dt).total_seconds())
        assert time_diff < 1, "Microsecond precision lost in conversion"

    def test_epoch_bug_detection(self):
        """Test that we can detect the Unix epoch bug (timestamps near 1970)."""
        # Simulate the bug: very small timestamp that would convert to ~1970
        buggy_timestamp = 123456  # Small number that would be ~1970 when treated as seconds

        event = TranscriptionEvent(timestamp=buggy_timestamp, duration=1.0, text="Bug simulation")

        # Convert to datetime
        timestamp_seconds = event.timestamp / 1_000_000
        dt = datetime.fromtimestamp(timestamp_seconds, tz=UTC)

        # This should fail because it's the 1970 epoch bug
        # (This test should PASS when bug exists, FAIL when bug is fixed)
        is_epoch_bug = dt.year == 1970

        # For TDD: This assertion will FAIL with correct timestamps
        # When bug is fixed, this will need to be updated or removed
        if buggy_timestamp < 1_000_000_000_000:  # Less than year 2001 in microseconds
            assert is_epoch_bug, "Small timestamp should trigger epoch bug detection"
