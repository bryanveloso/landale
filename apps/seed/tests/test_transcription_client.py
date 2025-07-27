"""Test transcription client timestamp parsing and event handling."""

import pytest
import time
from datetime import datetime
from unittest.mock import AsyncMock, patch
from src.transcription_client import TranscriptionWebSocketClient
from src.events import TranscriptionEvent


class TestTranscriptionClient:
    @pytest.fixture
    def client(self):
        """Create transcription client instance."""
        return TranscriptionWebSocketClient()

    @pytest.mark.asyncio
    async def test_iso_timestamp_with_z_suffix(self, client):
        """Test parsing ISO timestamp with Z suffix."""
        # Mock handler
        handler = AsyncMock()
        client.on_transcription(handler)

        # Payload with Z suffix timestamp
        payload = {"timestamp": "2023-01-01T12:00:00.000Z", "text": "Test transcription", "duration": 1.5}

        # Handle event
        await client._handle_transcription_event(payload)

        # Verify handler was called
        handler.assert_called_once()
        event = handler.call_args[0][0]

        # Check timestamp was parsed correctly
        assert isinstance(event, TranscriptionEvent)
        assert event.text == "Test transcription"
        assert event.duration == 1.5

        # Verify timestamp (2023-01-01 12:00:00 UTC)
        from datetime import timezone

        expected_dt = datetime(2023, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
        expected_us = int(expected_dt.timestamp() * 1_000_000)
        assert event.timestamp == expected_us

    @pytest.mark.asyncio
    async def test_iso_timestamp_without_z_suffix(self, client):
        """Test parsing ISO timestamp without Z suffix."""
        handler = AsyncMock()
        client.on_transcription(handler)

        payload = {"timestamp": "2023-01-01T12:00:00", "text": "No Z suffix", "duration": 2.0}

        await client._handle_transcription_event(payload)

        handler.assert_called_once()
        event = handler.call_args[0][0]
        assert event.text == "No Z suffix"
        assert event.duration == 2.0
        assert event.timestamp > 0

    @pytest.mark.asyncio
    async def test_invalid_timestamp_fallback(self, client, mock_logger):
        """Test fallback to current time with invalid timestamp."""
        handler = AsyncMock()
        client.on_transcription(handler)

        # Mock time.time() to have predictable fallback
        with patch("time.time", return_value=1234567890.0):
            payload = {"timestamp": "invalid-timestamp", "text": "Invalid time", "duration": 1.0}

            # Patch logger to check warning
            with patch("src.transcription_client.logger", mock_logger):
                await client._handle_transcription_event(payload)

        handler.assert_called_once()
        event = handler.call_args[0][0]
        assert event.text == "Invalid time"
        assert event.timestamp == 1234567890000000  # Fallback time in microseconds

        # Check that warning was logged
        mock_logger.warning.assert_called()
        warning_msg = mock_logger.warning.call_args[0][0]
        assert "Failed to parse timestamp" in warning_msg

    @pytest.mark.asyncio
    async def test_missing_timestamp_fallback(self, client):
        """Test fallback to current time when timestamp is missing."""
        handler = AsyncMock()
        client.on_transcription(handler)

        with patch("time.time", return_value=1234567890.0):
            payload = {"text": "No timestamp", "duration": 0.5}

            await client._handle_transcription_event(payload)

        handler.assert_called_once()
        event = handler.call_args[0][0]
        assert event.text == "No timestamp"
        assert event.timestamp == 1234567890000000

    @pytest.mark.asyncio
    async def test_multiple_handlers(self, client):
        """Test that multiple handlers all get called."""
        handler1 = AsyncMock()
        handler2 = AsyncMock()
        handler3 = AsyncMock()

        client.on_transcription(handler1)
        client.on_transcription(handler2)
        client.on_transcription(handler3)

        payload = {"timestamp": "2023-01-01T12:00:00Z", "text": "Multiple handlers", "duration": 1.0}

        await client._handle_transcription_event(payload)

        # All handlers should be called with the same event
        handler1.assert_called_once()
        handler2.assert_called_once()
        handler3.assert_called_once()

        # Verify they got the same event
        event1 = handler1.call_args[0][0]
        event2 = handler2.call_args[0][0]
        event3 = handler3.call_args[0][0]

        assert event1.text == event2.text == event3.text == "Multiple handlers"
        assert event1.timestamp == event2.timestamp == event3.timestamp

    @pytest.mark.asyncio
    async def test_handler_exception_handling(self, client, mock_logger):
        """Test that exceptions in handlers don't break other handlers."""
        # Handler that raises exception
        bad_handler = AsyncMock(side_effect=Exception("Handler error"))
        good_handler = AsyncMock()

        client.on_transcription(bad_handler)
        client.on_transcription(good_handler)

        payload = {"timestamp": "2023-01-01T12:00:00Z", "text": "Exception test", "duration": 1.0}

        with patch("src.transcription_client.logger", mock_logger):
            await client._handle_transcription_event(payload)

        # Both handlers should be called
        bad_handler.assert_called_once()
        good_handler.assert_called_once()

        # Error should be logged
        mock_logger.error.assert_called()

    @pytest.mark.asyncio
    async def test_empty_payload_handling(self, client):
        """Test handling of empty or minimal payload."""
        handler = AsyncMock()
        client.on_transcription(handler)

        # Empty text should still create event
        payload = {
            "timestamp": "2023-01-01T12:00:00Z"
            # Missing text and duration
        }

        await client._handle_transcription_event(payload)

        handler.assert_called_once()
        event = handler.call_args[0][0]
        assert event.text == ""  # Default empty string
        assert event.duration == 0.0  # Default 0.0
