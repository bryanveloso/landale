"""Tests for BaseWebSocketClient."""

import asyncio
import json
from unittest.mock import AsyncMock, patch

import pytest
from aiohttp import ClientConnectionError, WSMsgType, WSServerHandshakeError

from shared.websockets import BaseWebSocketClient

# Mock ResilientWebSocketClient as it doesn't exist
ResilientWebSocketClient = BaseWebSocketClient


class TestWebSocketClient(BaseWebSocketClient):
    """Concrete implementation for testing."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.received_messages = []
        self.error_count = 0

    async def on_message(self, message: dict) -> None:
        """Handle incoming messages."""
        self.received_messages.append(message)

    async def on_error(self, error: Exception) -> None:
        """Handle errors."""
        self.error_count += 1
        await super().on_error(error)


class MockWSMessage:
    """Mock WebSocket message."""

    def __init__(self, type_, data=None, extra=None):
        self.type = type_
        self.data = data
        self.extra = extra


@pytest.fixture
def mock_session():
    """Create a mock aiohttp session."""
    session = AsyncMock()
    return session


@pytest.fixture
def mock_ws():
    """Create a mock WebSocket connection."""
    ws = AsyncMock()
    ws.closed = False
    ws.__aiter__ = AsyncMock(return_value=ws)
    ws.__anext__ = AsyncMock()
    return ws


@pytest.fixture
async def client(mock_session):
    """Create a test client."""
    client = ResilientWebSocketClient(url="ws://test.example.com", session=mock_session)
    yield client
    await client.disconnect()


class TestResilientWebSocketClient:
    """Test ResilientWebSocketClient functionality."""

    async def test_connect_success(self, client, mock_session, mock_ws):
        """Test successful connection."""
        mock_session.ws_connect.return_value.__aenter__.return_value = mock_ws

        await client.connect()

        assert client.is_connected()
        mock_session.ws_connect.assert_called_once_with("ws://test.example.com", heartbeat=30, timeout=10)

    async def test_connect_with_retry(self, client, mock_session, mock_ws):
        """Test connection with retry on failure."""
        # First attempt fails, second succeeds
        mock_session.ws_connect.side_effect = [
            ClientConnectionError("Connection failed"),
            AsyncMock(__aenter__=AsyncMock(return_value=mock_ws)),
        ]

        await client.connect()

        assert client.is_connected()
        assert mock_session.ws_connect.call_count == 2

    async def test_exponential_backoff(self, client, mock_session):
        """Test exponential backoff during retries."""
        mock_session.ws_connect.side_effect = ClientConnectionError("Connection failed")

        # Mock sleep to track delays
        delays = []

        async def mock_sleep(delay):
            delays.append(delay)

        with patch("asyncio.sleep", mock_sleep):
            # Try to connect (will fail after max retries)
            with pytest.raises(ClientConnectionError):
                await client.connect()

        # Check exponential backoff pattern
        assert len(delays) == 5  # max_retries
        assert delays[0] == 1
        assert delays[1] == 2
        assert delays[2] == 4
        assert delays[3] == 8
        assert delays[4] == 16

    async def test_send_json_success(self, client, mock_session, mock_ws):
        """Test sending JSON data."""
        mock_session.ws_connect.return_value.__aenter__.return_value = mock_ws
        await client.connect()

        data = {"type": "test", "payload": "data"}
        await client.send_json(data)

        mock_ws.send_json.assert_called_once_with(data)

    async def test_send_json_not_connected(self, client):
        """Test sending JSON when not connected."""
        with pytest.raises(RuntimeError, match="WebSocket is not connected"):
            await client.send_json({"test": "data"})

    async def test_receive_message(self, client, mock_session, mock_ws):
        """Test receiving messages."""
        mock_session.ws_connect.return_value.__aenter__.return_value = mock_ws

        # Setup message stream
        test_data = {"type": "test_message", "data": "test"}
        messages = [MockWSMessage(WSMsgType.TEXT, json.dumps(test_data))]
        mock_ws.__anext__.side_effect = messages

        await client.connect()

        # Process one message
        received_messages = []

        async def message_handler(msg):
            received_messages.append(msg)
            client._running = False  # Stop after one message

        client._message_handler = message_handler

        # Run message loop briefly
        listen_task = asyncio.create_task(client._listen())
        await asyncio.sleep(0.1)
        client._running = False

        try:
            await asyncio.wait_for(listen_task, timeout=1.0)
        except TimeoutError:
            pass

        assert len(received_messages) == 1
        assert received_messages[0] == test_data

    async def test_reconnect_on_connection_lost(self, client, mock_session, mock_ws):
        """Test automatic reconnection when connection is lost."""
        mock_session.ws_connect.return_value.__aenter__.return_value = mock_ws
        await client.connect()

        # Simulate connection loss
        mock_ws.closed = True
        mock_ws.__anext__.side_effect = ConnectionResetError()

        # Setup reconnection to succeed
        new_ws = AsyncMock()
        new_ws.closed = False
        new_ws.__aiter__ = AsyncMock(return_value=new_ws)
        new_ws.__anext__ = AsyncMock(side_effect=StopAsyncIteration)
        mock_session.ws_connect.return_value.__aenter__.return_value = new_ws

        # Trigger reconnection
        listen_task = asyncio.create_task(client._listen())
        await asyncio.sleep(0.1)
        client._running = False

        try:
            await asyncio.wait_for(listen_task, timeout=2.0)
        except TimeoutError:
            pass

        # Should have reconnected
        assert mock_session.ws_connect.call_count >= 2

    async def test_health_check(self, client, mock_session, mock_ws):
        """Test health check functionality."""
        mock_session.ws_connect.return_value.__aenter__.return_value = mock_ws
        await client.connect()

        # Test healthy connection
        mock_ws.ping = AsyncMock()
        mock_ws.pong = AsyncMock()

        health_task = asyncio.create_task(client._health_check_loop())
        await asyncio.sleep(0.1)
        client._running = False

        try:
            await asyncio.wait_for(health_task, timeout=1.0)
        except TimeoutError:
            pass

        mock_ws.ping.assert_called()

    async def test_disconnect(self, client, mock_session, mock_ws):
        """Test clean disconnect."""
        mock_session.ws_connect.return_value.__aenter__.return_value = mock_ws
        await client.connect()

        assert client.is_connected()

        await client.disconnect()

        assert not client.is_connected()
        mock_ws.close.assert_called_once()

    async def test_context_manager(self, mock_session, mock_ws):
        """Test using client as context manager."""
        mock_session.ws_connect.return_value.__aenter__.return_value = mock_ws

        async with ResilientWebSocketClient("ws://test.example.com", session=mock_session) as client:
            assert client.is_connected()

        assert not client.is_connected()
        mock_ws.close.assert_called_once()

    async def test_max_retries_exceeded(self, client, mock_session):
        """Test behavior when max retries is exceeded."""
        mock_session.ws_connect.side_effect = ClientConnectionError("Connection failed")

        with pytest.raises(ClientConnectionError):
            await client.connect()

        assert not client.is_connected()
        assert mock_session.ws_connect.call_count == 5  # max_retries

    async def test_circuit_breaker_integration(self, client, mock_session):
        """Test circuit breaker opens after repeated failures."""
        # Simulate repeated connection failures
        mock_session.ws_connect.side_effect = ClientConnectionError("Connection failed")

        # First few attempts
        for _ in range(3):
            with pytest.raises(ClientConnectionError):
                await client.connect()

        # Circuit breaker should be open now
        # Next attempt should fail fast
        with patch("asyncio.sleep") as mock_sleep:
            with pytest.raises(Exception, match="Circuit breaker is OPEN"):
                await client.connect()

            # Should not have slept (failed fast)
            mock_sleep.assert_not_called()

    async def test_error_callback(self, client, mock_session, mock_ws):
        """Test error callback is called on errors."""
        errors = []

        async def error_handler(error):
            errors.append(error)

        client.on_error = error_handler

        # Simulate connection error
        mock_session.ws_connect.side_effect = ClientConnectionError("Test error")

        with pytest.raises(ClientConnectionError):
            await client.connect()

        assert len(errors) > 0
        assert isinstance(errors[0], ClientConnectionError)

    async def test_message_handler_error(self, client, mock_session, mock_ws):
        """Test handling of errors in message handler."""
        mock_session.ws_connect.return_value.__aenter__.return_value = mock_ws

        # Setup message that will cause handler error
        messages = [MockWSMessage(WSMsgType.TEXT, json.dumps({"type": "test"}))]
        mock_ws.__anext__.side_effect = messages

        await client.connect()

        # Handler that raises error
        async def failing_handler(msg):
            raise ValueError("Handler error")

        client._message_handler = failing_handler

        # Should handle error gracefully
        listen_task = asyncio.create_task(client._listen())
        await asyncio.sleep(0.1)
        client._running = False

        try:
            await asyncio.wait_for(listen_task, timeout=1.0)
        except TimeoutError:
            pass

        # Should still be connected despite handler error
        assert client.is_connected()

    async def test_websocket_error_types(self, client, mock_session, mock_ws):
        """Test handling of different WebSocket error types."""
        mock_session.ws_connect.return_value.__aenter__.return_value = mock_ws
        await client.connect()

        # Test different error message types
        error_messages = [
            MockWSMessage(WSMsgType.ERROR, None, "WebSocket error"),
            MockWSMessage(WSMsgType.CLOSE, None, "Connection closed"),
        ]

        for error_msg in error_messages:
            mock_ws.__anext__.return_value = error_msg

            # Should handle error and attempt reconnection
            listen_task = asyncio.create_task(client._listen())
            await asyncio.sleep(0.1)
            client._running = False

            try:
                await asyncio.wait_for(listen_task, timeout=1.0)
            except TimeoutError:
                pass


@pytest.mark.parametrize(
    "error_type,expected_retry",
    [
        (ClientConnectionError, True),
        (WSServerHandshakeError, True),
        (asyncio.TimeoutError, True),
        (ValueError, False),  # Non-retryable error
    ],
)
async def test_retry_behavior(mock_session, error_type, expected_retry):
    """Test retry behavior for different error types."""
    client = ResilientWebSocketClient("ws://test.example.com", session=mock_session)

    mock_session.ws_connect.side_effect = error_type("Test error")

    try:
        await client.connect()
    except Exception:
        pass

    if expected_retry:
        assert mock_session.ws_connect.call_count > 1
    else:
        assert mock_session.ws_connect.call_count == 1

    await client.disconnect()
