"""Tests for phononmaser WebSocket client."""

from datetime import datetime

import pytest
import pytest_asyncio

from src.events import TranscriptionEvent
from tests.test_websocket_client_factory import create_test_client

# Mark all tests in this module as async
pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def client():
    """Create a test WebSocket client."""
    # Use the test-specific client that doesn't create background tasks
    client = create_test_client()
    yield client
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
        await client.connect()

        # Should have connected
        assert client.connect_called
        assert client.state == "connected"

    async def test_send_transcription(self, client):
        """Test sending transcription through WebSocket."""
        # Setup client as connected
        await client.connect()
        client.joined_transcription = True

        # Create test transcription event
        event = TranscriptionEvent(
            timestamp=int(datetime.now().timestamp() * 1_000_000),
            text="Test transcription",
            duration=1.5,
        )

        result = await client.send_transcription(event)
        assert result is True

        # Check the sent message
        assert len(client.sent_messages) == 1
        sent_data = client.sent_messages[0]

        assert sent_data["topic"] == "transcription:live"
        assert sent_data["event"] == "submit_transcription"
        assert sent_data["payload"]["text"] == "Test transcription"

    async def test_send_transcription_not_connected(self, client):
        """Test sending transcription when not connected."""
        event = TranscriptionEvent(timestamp=int(datetime.now().timestamp() * 1_000_000), text="Test", duration=0.5)

        # Should return False when not connected
        result = await client.send_transcription(event)
        assert result is False

    async def test_reconnection_logic(self, client):
        """Test connection state management."""
        # Test initial connection
        await client.connect()
        assert client.state == "connected"

        # Test disconnection
        await client.disconnect()
        assert client.state == "disconnected"

        # Test reconnection
        await client.connect()
        assert client.state == "connected"

    async def test_heartbeat_configuration(self, client):
        """Test heartbeat interval configuration."""
        # Test that heartbeat interval can be configured
        assert client.heartbeat_interval == 30  # Default

        client.heartbeat_interval = 60
        assert client.heartbeat_interval == 60

    async def test_error_handling(self, client):
        """Test error handling when not connected."""
        # Try to send without connection
        event = TranscriptionEvent(timestamp=int(datetime.now().timestamp() * 1_000_000), text="Test", duration=0.5)

        # Should return False when not connected
        result = await client.send_transcription(event)
        assert result is False

    async def test_channel_join_required(self, client):
        """Test that transcription requires channel join."""
        # Connect but don't join channel
        await client.connect()
        client.joined_transcription = False

        event = TranscriptionEvent(timestamp=int(datetime.now().timestamp() * 1_000_000), text="Test", duration=0.5)

        # Should return False when channel not joined
        result = await client.send_transcription(event)
        assert result is False

    async def test_circuit_breaker_configuration(self, client):
        """Test circuit breaker configuration."""
        # Test default configuration
        assert client.circuit_breaker_threshold == 5
        assert client.circuit_breaker_timeout == 30.0

        # Test that circuit breaker state can be checked
        assert not client._is_circuit_open()

    async def test_connection_state_callbacks(self, client):
        """Test connection state change callbacks."""
        states = []

        def state_callback(event):
            states.append((event.old_state.value, event.new_state.value))

        client.on_connection_change(state_callback)

        # Connect
        await client.connect()

        # Disconnect
        await client.disconnect()

        # Should have state transitions
        assert ("disconnected", "connected") in states
        assert ("connected", "disconnected") in states


@pytest.mark.parametrize("duration", [0.5, 1.0])
async def test_transcription_event_durations(duration):
    """Test different transcription event durations."""
    # Create a fresh client for this test
    client = create_test_client()

    # Setup
    await client.connect()
    client.joined_transcription = True

    event = TranscriptionEvent(timestamp=int(datetime.now().timestamp() * 1_000_000), text="Test", duration=duration)

    result = await client.send_transcription(event)
    assert result is True

    sent_data = client.sent_messages[0]
    assert sent_data["payload"]["text"] == "Test"

    await client.disconnect()


async def test_context_manager():
    """Test using client as a context manager."""
    async with create_test_client() as client:
        assert client.state == "connected"
        assert client.connect_called

    # After exiting context, should be disconnected
    assert client.state == "disconnected"
    assert client.disconnect_called
