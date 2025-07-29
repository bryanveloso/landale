"""Tests for phononmaser WebSocket client."""

import asyncio
import json
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, Mock, patch

import pytest
import websockets
from websockets.exceptions import ConnectionClosed

from src.events import TranscriptionEvent
from src.websocket_client import ServerWebSocketClient


@pytest.fixture
async def client():
    """Create a test WebSocket client."""
    client = ServerWebSocketClient(server_url="ws://test:7175/socket/websocket", stream_session_id="test_session")
    yield client
    if client.ws:
        await client.disconnect()


class TestServerWebSocketClient:
    """Test ServerWebSocketClient functionality."""

    async def test_initialization(self, client):
        """Test client initialization."""
        assert client.stream_session_id == "test_session"
        assert client._phoenix_ref == 1
        assert client.state == "disconnected"

    async def test_connection_lifecycle(self, client):
        """Test connection establishment and Phoenix channel join."""
        mock_ws = AsyncMock()
        mock_ws.recv = AsyncMock()
        mock_ws.send = AsyncMock()
        mock_ws.close = AsyncMock()

        # Mock successful Phoenix connection sequence
        mock_ws.recv.side_effect = [
            # Phoenix socket connection response
            json.dumps({"topic": "phoenix", "event": "phx_reply", "payload": {"status": "ok"}, "ref": "1"}),
            # Channel join response
            json.dumps({"topic": "transcription:live", "event": "phx_reply", "payload": {"status": "ok"}, "ref": "2"}),
        ]

        with patch("websockets.connect", return_value=mock_ws):
            await client.connect()

            # Should have sent Phoenix connection message
            assert mock_ws.send.call_count >= 1
            connect_msg = json.loads(mock_ws.send.call_args_list[0][0][0])
            assert connect_msg["topic"] == "phoenix"
            assert connect_msg["event"] == "phx_join"

            # Should have joined transcription channel
            assert any(json.loads(call[0][0])["topic"] == "transcription:live" for call in mock_ws.send.call_args_list)

    async def test_send_transcription(self, client):
        """Test sending transcription through WebSocket."""
        mock_ws = AsyncMock()
        client.ws = mock_ws
        client.state = "connected"
        client.joined_transcription = True

        # Create test transcription event
        event = TranscriptionEvent(
            timestamp=datetime.now(),
            text="Test transcription",
            is_final=True,
            audio_duration=1.5,
            source_id="test_source",
        )

        await client.send_transcription(event)

        # Should have sent the transcription
        mock_ws.send.assert_called_once()
        sent_data = json.loads(mock_ws.send.call_args[0][0])

        assert sent_data["topic"] == "transcription:live"
        assert sent_data["event"] == "submit_transcription"
        assert sent_data["payload"]["text"] == "Test transcription"
        assert sent_data["payload"]["is_final"] is True
        assert sent_data["payload"]["audio_duration"] == 1.5

    async def test_send_transcription_not_connected(self, client):
        """Test sending transcription when not connected."""
        event = TranscriptionEvent(timestamp=datetime.now(), text="Test", is_final=True)

        # Should return False when not connected
        result = await client.send_transcription(event)
        assert result is False

    async def test_reconnection_logic(self, client):
        """Test automatic reconnection after disconnect."""
        # Setup initial connection
        mock_ws = AsyncMock()
        mock_ws.recv = AsyncMock()
        mock_ws.send = AsyncMock()

        connect_count = 0

        async def mock_connect(*args, **kwargs):
            nonlocal connect_count
            connect_count += 1

            if connect_count == 1:
                # First connection fails after setup
                mock_ws.recv.side_effect = ConnectionClosed(None, None)
            else:
                # Second connection succeeds
                mock_ws.recv.side_effect = [
                    json.dumps({"topic": "phoenix", "event": "phx_reply", "payload": {"status": "ok"}, "ref": "1"})
                ]

            return mock_ws

        with patch("websockets.connect", side_effect=mock_connect):
            # First connection
            await client.connect()

            # Wait for reconnection
            await asyncio.sleep(2)

            # Should have attempted reconnection
            assert connect_count >= 2

    async def test_heartbeat_mechanism(self, client):
        """Test Phoenix heartbeat messages."""
        mock_ws = AsyncMock()
        mock_ws.recv = AsyncMock()
        mock_ws.send = AsyncMock()

        heartbeat_sent = False

        async def track_heartbeat(msg):
            nonlocal heartbeat_sent
            data = json.loads(msg)
            if data.get("event") == "heartbeat":
                heartbeat_sent = True

        mock_ws.send.side_effect = track_heartbeat

        # Mock responses
        mock_ws.recv.side_effect = [
            # Connection response
            json.dumps({"topic": "phoenix", "event": "phx_reply", "payload": {"status": "ok"}, "ref": "1"}),
            # Keep connection alive
            asyncio.sleep(50),
        ]

        with patch("websockets.connect", return_value=mock_ws):
            client.heartbeat_interval = 0.1  # Fast heartbeat for testing
            await client.connect()

            # Wait for heartbeat
            await asyncio.sleep(0.5)

            assert heartbeat_sent

    async def test_error_handling(self, client):
        """Test error handling during message processing."""
        mock_ws = AsyncMock()
        client.ws = mock_ws

        # Simulate error during send
        mock_ws.send.side_effect = Exception("WebSocket error")

        event = TranscriptionEvent(timestamp=datetime.now(), text="Test", is_final=True)

        # Should handle error gracefully
        result = await client.send_transcription(event)
        assert result is False

    async def test_phoenix_channel_error_response(self, client):
        """Test handling Phoenix channel error responses."""
        mock_ws = AsyncMock()
        mock_ws.recv = AsyncMock()
        mock_ws.send = AsyncMock()

        # Mock error response from Phoenix
        mock_ws.recv.side_effect = [
            json.dumps(
                {
                    "topic": "transcription:live",
                    "event": "phx_reply",
                    "payload": {"status": "error", "response": {"reason": "unauthorized"}},
                    "ref": "2",
                }
            )
        ]

        with patch("websockets.connect", return_value=mock_ws):
            # Should handle join error
            result = await client.connect()

            # Connection should fail due to channel join error
            assert client.state != "connected"

    async def test_circuit_breaker_integration(self, client):
        """Test circuit breaker prevents excessive reconnection attempts."""
        # Configure aggressive circuit breaker for testing
        client.circuit_breaker_threshold = 2
        client.circuit_breaker_timeout = 1.0

        connect_attempts = 0

        async def failing_connect(*args, **kwargs):
            nonlocal connect_attempts
            connect_attempts += 1
            raise ConnectionClosed(None, None)

        with patch("websockets.connect", side_effect=failing_connect):
            # Should fail after threshold
            with pytest.raises(Exception):
                await client.connect()

            # Circuit should be open
            assert client._is_circuit_open()

            # Further attempts should fail fast
            initial_attempts = connect_attempts
            with pytest.raises(Exception):
                await client.connect()

            # Should not have made additional connection attempts
            assert connect_attempts == initial_attempts

    async def test_connection_state_callbacks(self, client):
        """Test connection state change callbacks."""
        states = []

        def state_callback(event):
            states.append((event.old_state.value, event.new_state.value))

        client.on_connection_change(state_callback)

        mock_ws = AsyncMock()
        mock_ws.recv = AsyncMock(
            side_effect=[
                json.dumps({"topic": "phoenix", "event": "phx_reply", "payload": {"status": "ok"}, "ref": "1"})
            ]
        )

        with patch("websockets.connect", return_value=mock_ws):
            await client.connect()

        # Should have state transitions
        assert ("disconnected", "connecting") in states
        assert ("connecting", "connected") in states


@pytest.mark.parametrize("is_final,expected_event", [(True, "final_segment"), (False, "partial_segment")])
async def test_transcription_event_types(client, is_final, expected_event):
    """Test different transcription event types."""
    mock_ws = AsyncMock()
    client.ws = mock_ws
    client.state = "connected"
    client.joined_transcription = True

    event = TranscriptionEvent(timestamp=datetime.now(), text="Test", is_final=is_final)

    await client.send_transcription(event)

    sent_data = json.loads(mock_ws.send.call_args[0][0])
    assert sent_data["payload"]["is_final"] == is_final
