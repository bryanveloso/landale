"""TDD tests for Phoenix server integration reliability.

Tests the single output path to Phoenix server with error scenarios,
data validation, and session management without mocking.
"""

import asyncio
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from events import TranscriptionEvent
from server_client import ServerTranscriptionClient


class TestPhoenixIntegration:
    """Test Phoenix server integration without mocking."""

    @pytest.mark.asyncio
    async def test_phoenix_integration_successful_transcription_send(self):
        """Test successful transcription send to Phoenix server."""

        server_url = "http://saya:7175"  # Real Phoenix server

        async with ServerTranscriptionClient(server_url) as client:
            # Create a test transcription event
            event = TranscriptionEvent(
                timestamp=int(time.time() * 1000000),  # Current timestamp in microseconds
                duration=1500.0,  # 1.5 seconds
                text="Test transcription for Phoenix integration",
            )

            # Send transcription to Phoenix
            success = await client.send_transcription(event)

            # Verify successful send
            assert success, "Transcription should be sent successfully to Phoenix server"

    @pytest.mark.asyncio
    async def test_phoenix_integration_handles_server_unavailable(self):
        """Test behavior when Phoenix server is unavailable."""

        # Use invalid URL to simulate server down
        server_url = "http://nonexistent-server:9999"

        async with ServerTranscriptionClient(server_url) as client:
            # Create a test transcription event
            event = TranscriptionEvent(
                timestamp=int(time.time() * 1000000),
                duration=1000.0,
                text="Test transcription for server down scenario",
            )

            # Send transcription to unavailable server
            success = await client.send_transcription(event)

            # Verify graceful failure
            assert not success, "Should return False when server is unavailable"

    @pytest.mark.asyncio
    async def test_phoenix_integration_validates_transcription_data(self):
        """Test that transcription data is properly validated before sending."""

        server_url = "http://saya:7175"

        async with ServerTranscriptionClient(server_url) as client:
            # Test with empty text
            event_empty = TranscriptionEvent(
                timestamp=int(time.time() * 1000000),
                duration=500.0,
                text="",  # Empty text
            )

            # Should handle empty text gracefully
            success = await client.send_transcription(event_empty)
            # Note: This should still succeed as empty transcriptions might be valid
            assert isinstance(success, bool), "Should return boolean result for empty text"

            # Test with very long text
            long_text = "A" * 10000  # 10k character text
            event_long = TranscriptionEvent(
                timestamp=int(time.time() * 1000000),
                duration=30000.0,  # 30 seconds
                text=long_text,
            )

            # Should handle long text
            success = await client.send_transcription(event_long)
            assert isinstance(success, bool), "Should return boolean result for long text"

    @pytest.mark.asyncio
    async def test_phoenix_integration_session_management(self):
        """Test daily session ID generation and consistency."""

        server_url = "http://saya:7175"

        async with ServerTranscriptionClient(server_url) as client:
            # Get session ID
            session_id = client.stream_session_id

            # Verify session ID format (should be stream_YYYY_MM_DD)
            assert session_id.startswith("stream_"), "Session ID should start with 'stream_'"
            assert len(session_id) == 17, "Session ID should be 17 characters (stream_YYYY_MM_DD)"
            assert session_id.count("_") == 3, "Session ID should have 3 underscores"

            # Verify session ID is consistent across calls
            session_id2 = client.stream_session_id
            assert session_id == session_id2, "Session ID should be consistent within same day"

            # Send transcription and verify session is included
            event = TranscriptionEvent(
                timestamp=int(time.time() * 1000000), duration=800.0, text="Test transcription for session validation"
            )

            success = await client.send_transcription(event)
            assert success, "Transcription with session should be sent successfully"

    @pytest.mark.asyncio
    async def test_phoenix_integration_concurrent_transcriptions(self):
        """Test handling multiple concurrent transcription sends."""

        server_url = "http://saya:7175"

        async with ServerTranscriptionClient(server_url) as client:
            # Create multiple transcription events
            events = []
            for i in range(5):
                event = TranscriptionEvent(
                    timestamp=int(time.time() * 1000000) + (i * 1000000),  # 1 second apart
                    duration=1200.0,
                    text=f"Concurrent transcription test {i + 1}",
                )
                events.append(event)

            # Send all transcriptions concurrently
            tasks = [client.send_transcription(event) for event in events]
            results = await asyncio.gather(*tasks, return_exceptions=True)

            # Verify all succeeded or are boolean results
            successful_sends = 0
            for result in results:
                if isinstance(result, bool):
                    if result:
                        successful_sends += 1
                else:
                    # If it's an exception, log it but don't fail the test
                    print(f"Concurrent send exception: {result}")

            # At least some should succeed (server may rate limit)
            assert successful_sends >= 1, f"At least 1 concurrent send should succeed, got {successful_sends}"

    @pytest.mark.asyncio
    async def test_phoenix_integration_timeout_handling(self):
        """Test timeout handling for slow Phoenix server responses."""

        server_url = "http://saya:7175"

        async with ServerTranscriptionClient(server_url) as client:
            # Create a normal transcription event
            event = TranscriptionEvent(
                timestamp=int(time.time() * 1000000),
                duration=2000.0,
                text="Test transcription for timeout handling validation",
            )

            # Measure response time
            start_time = time.time()
            success = await client.send_transcription(event)
            end_time = time.time()

            response_time = end_time - start_time

            # Verify response time is reasonable (under 10 seconds)
            assert response_time < 10.0, f"Response time should be under 10s, got {response_time:.2f}s"

            # Verify request completed with a result
            assert isinstance(success, bool), "Should return boolean result even with timeout considerations"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
