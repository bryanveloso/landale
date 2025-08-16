"""Shared mock WebSocket connection utilities for resilience testing."""

import asyncio
import json
import time
from datetime import datetime
from typing import Any, Callable, Dict, List, Optional
from unittest.mock import AsyncMock

import pytest
import websockets
from websockets import ConnectionClosed
from shared.websockets import BaseWebSocketClient, ConnectionEvent, ConnectionState


class MockWebSocketConnection:
    """
    Production-grade mock WebSocket connection for comprehensive testing.
    
    Supports realistic network conditions, failure scenarios, and state tracking
    for testing WebSocket resilience patterns across all services.
    """
    
    def __init__(
        self,
        should_fail_connect: bool = False,
        fail_after_n_messages: Optional[int] = None,
        connection_delay: float = 0,
        message_delay: float = 0,
        fail_ping: bool = False,
        fail_heartbeat_after: Optional[int] = None,
        simulate_network_issues: bool = False,
        max_message_queue_size: int = 1000
    ):
        """
        Initialize mock WebSocket connection with configurable behaviors.
        
        Args:
            should_fail_connect: Whether initial connection should fail
            fail_after_n_messages: Fail connection after N messages sent
            connection_delay: Delay in seconds before connection succeeds
            message_delay: Delay in seconds for each message send
            fail_ping: Whether ping operations should fail
            fail_heartbeat_after: Fail heartbeat after N attempts
            simulate_network_issues: Enable random network issue simulation
            max_message_queue_size: Maximum incoming message queue size
        """
        self.should_fail_connect = should_fail_connect
        self.fail_after_n_messages = fail_after_n_messages
        self.connection_delay = connection_delay
        self.message_delay = message_delay
        self.fail_ping = fail_ping
        self.fail_heartbeat_after = fail_heartbeat_after
        self.simulate_network_issues = simulate_network_issues
        self.max_message_queue_size = max_message_queue_size
        
        # Connection state
        self.connected = False
        self.close_called = False
        
        # Message tracking
        self.messages_sent: List[str] = []
        self.messages_received = 0
        self.incoming_messages: List[str] = []
        self.current_message_index = 0
        
        # Operation tracking
        self.ping_called = False
        self.ping_count = 0
        self.heartbeat_count = 0
        
        # Callbacks for lifecycle events
        self.on_connect_callbacks: List[Callable[[], None]] = []
        self.on_disconnect_callbacks: List[Callable[[], None]] = []
        self.on_message_callbacks: List[Callable[[str], None]] = []
        
        # Performance metrics
        self.connection_start_time = 0
        self.total_bytes_sent = 0
        self.total_bytes_received = 0
        
        # Network simulation state
        self._network_issue_probability = 0.1 if simulate_network_issues else 0
        self._last_network_issue = 0
    
    async def __aenter__(self):
        """Async context manager entry."""
        if self.connection_delay > 0:
            await asyncio.sleep(self.connection_delay)
        
        if self._should_fail_connection():
            raise ConnectionClosed(None, None)
        
        self.connected = True
        self.connection_start_time = time.time()
        
        # Notify connection callbacks
        for callback in self.on_connect_callbacks:
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback()
                else:
                    callback()
            except Exception:
                pass  # Don't let callback failures break the mock
        
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.close()
    
    def _should_fail_connection(self) -> bool:
        """Determine if connection should fail based on configuration."""
        if self.should_fail_connect:
            return True
        
        if self.simulate_network_issues:
            return time.time() - self._last_network_issue < 0.1 and self._random_network_issue()
        
        return False
    
    def _random_network_issue(self) -> bool:
        """Simulate random network issues."""
        import random
        if random.random() < self._network_issue_probability:
            self._last_network_issue = time.time()
            return True
        return False
    
    async def send(self, message: str):
        """
        Send a message through the mock connection.
        
        Args:
            message: Message to send
            
        Raises:
            ConnectionClosed: If connection is closed or should fail
        """
        if not self.connected:
            raise ConnectionClosed(None, None)
        
        # Simulate network issues
        if self.simulate_network_issues and self._random_network_issue():
            self.connected = False
            await self._trigger_disconnect()
            raise ConnectionClosed(None, None)
        
        # Simulate message delay
        if self.message_delay > 0:
            await asyncio.sleep(self.message_delay)
        
        # Track the message
        self.messages_sent.append(message)
        self.messages_received += 1
        self.total_bytes_sent += len(message.encode('utf-8'))
        
        # Notify message callbacks
        for callback in self.on_message_callbacks:
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback(message)
                else:
                    callback(message)
            except Exception:
                pass
        
        # Check if should fail after N messages
        if (self.fail_after_n_messages and 
            self.messages_received >= self.fail_after_n_messages):
            self.connected = False
            await self._trigger_disconnect()
            raise ConnectionClosed(None, None)
    
    async def send_json(self, data: Dict[str, Any]):
        """Send JSON data."""
        message = json.dumps(data)
        await self.send(message)
    
    async def ping(self) -> None:
        """
        Send a ping frame.
        
        Raises:
            ConnectionClosed: If ping should fail
        """
        self.ping_called = True
        self.ping_count += 1
        
        # Check heartbeat failure condition
        if (self.fail_heartbeat_after and 
            self.ping_count >= self.fail_heartbeat_after):
            raise ConnectionClosed(None, None)
        
        if self.fail_ping:
            raise ConnectionClosed(None, None)
        
        # Simulate network issues during ping
        if self.simulate_network_issues and self._random_network_issue():
            raise ConnectionClosed(None, None)
    
    async def close(self):
        """Close the connection."""
        self.close_called = True
        if self.connected:
            self.connected = False
            await self._trigger_disconnect()
    
    async def _trigger_disconnect(self):
        """Trigger disconnect callbacks."""
        for callback in self.on_disconnect_callbacks:
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback()
                else:
                    callback()
            except Exception:
                pass
    
    def __aiter__(self):
        """Async iterator for message reception."""
        return self
    
    async def __anext__(self):
        """
        Get the next message from the queue.
        
        Returns:
            str: Next message from queue
            
        Raises:
            StopAsyncIteration: When no more messages or disconnected
        """
        if not self.connected:
            raise StopAsyncIteration
        
        # Check for available messages
        if self.current_message_index < len(self.incoming_messages):
            message = self.incoming_messages[self.current_message_index]
            self.current_message_index += 1
            self.total_bytes_received += len(message.encode('utf-8'))
            return message
        
        # Simulate waiting for messages
        await asyncio.sleep(0.01)
        
        # Check again after waiting
        if self.current_message_index < len(self.incoming_messages):
            message = self.incoming_messages[self.current_message_index]
            self.current_message_index += 1
            self.total_bytes_received += len(message.encode('utf-8'))
            return message
        
        # No messages available
        raise StopAsyncIteration
    
    def add_incoming_message(self, message: str):
        """
        Add a message to the incoming queue.
        
        Args:
            message: Message to add to queue
        """
        if len(self.incoming_messages) >= self.max_message_queue_size:
            # Remove oldest message to prevent unbounded growth
            self.incoming_messages.pop(0)
            if self.current_message_index > 0:
                self.current_message_index -= 1
        
        self.incoming_messages.append(message)
    
    def add_phoenix_message(self, topic: str, event: str, payload: Dict[str, Any], ref: str = "1"):
        """
        Add a Phoenix channel message to the incoming queue.
        
        Args:
            topic: Phoenix channel topic
            event: Event name
            payload: Event payload
            ref: Message reference
        """
        message = json.dumps({
            "topic": topic,
            "event": event,
            "payload": payload,
            "ref": ref
        })
        self.add_incoming_message(message)
    
    def add_phoenix_reply(self, topic: str, status: str = "ok", payload: Dict[str, Any] = None, ref: str = "1"):
        """
        Add a Phoenix reply message to the incoming queue.
        
        Args:
            topic: Phoenix channel topic
            status: Reply status (ok, error, timeout)
            payload: Reply payload
            ref: Message reference
        """
        reply_payload = {"status": status}
        if payload:
            reply_payload.update(payload)
        
        self.add_phoenix_message(topic, "phx_reply", reply_payload, ref)
    
    def get_sent_message(self, index: int) -> Optional[Dict[str, Any]]:
        """
        Get a sent message by index and parse as JSON.
        
        Args:
            index: Message index
            
        Returns:
            Parsed message or None if invalid
        """
        if 0 <= index < len(self.messages_sent):
            try:
                return json.loads(self.messages_sent[index])
            except json.JSONDecodeError:
                return None
        return None
    
    def get_sent_messages_by_event(self, event: str) -> List[Dict[str, Any]]:
        """
        Get all sent messages with a specific event type.
        
        Args:
            event: Event type to filter by
            
        Returns:
            List of matching messages
        """
        matching_messages = []
        for message_str in self.messages_sent:
            try:
                message = json.loads(message_str)
                if message.get('event') == event:
                    matching_messages.append(message)
            except json.JSONDecodeError:
                continue
        return matching_messages
    
    def reset(self):
        """Reset all state for reuse."""
        self.connected = False
        self.close_called = False
        self.messages_sent.clear()
        self.messages_received = 0
        self.incoming_messages.clear()
        self.current_message_index = 0
        self.ping_called = False
        self.ping_count = 0
        self.heartbeat_count = 0
        self.connection_start_time = 0
        self.total_bytes_sent = 0
        self.total_bytes_received = 0
        self._last_network_issue = 0
    
    def get_metrics(self) -> Dict[str, Any]:
        """
        Get connection metrics for analysis.
        
        Returns:
            Dictionary of metrics
        """
        return {
            "connected": self.connected,
            "messages_sent_count": len(self.messages_sent),
            "messages_received_count": self.messages_received,
            "ping_count": self.ping_count,
            "total_bytes_sent": self.total_bytes_sent,
            "total_bytes_received": self.total_bytes_received,
            "connection_duration": time.time() - self.connection_start_time if self.connection_start_time > 0 else 0,
            "queue_size": len(self.incoming_messages),
            "queue_processed": self.current_message_index
        }


class MockWebSocketFactory:
    """Factory for creating configured mock WebSocket connections."""
    
    @staticmethod
    def create_stable_connection() -> MockWebSocketConnection:
        """Create a stable, reliable connection for basic testing."""
        return MockWebSocketConnection()
    
    @staticmethod
    def create_failing_connection() -> MockWebSocketConnection:
        """Create a connection that fails to establish."""
        return MockWebSocketConnection(should_fail_connect=True)
    
    @staticmethod
    def create_unstable_connection() -> MockWebSocketConnection:
        """Create an unstable connection with network issues."""
        return MockWebSocketConnection(
            simulate_network_issues=True,
            fail_after_n_messages=5
        )
    
    @staticmethod
    def create_slow_connection() -> MockWebSocketConnection:
        """Create a slow connection with high latency."""
        return MockWebSocketConnection(
            connection_delay=0.2,
            message_delay=0.05
        )
    
    @staticmethod
    def create_heartbeat_failing_connection() -> MockWebSocketConnection:
        """Create a connection that fails heartbeat checks."""
        return MockWebSocketConnection(
            fail_ping=True,
            fail_heartbeat_after=3
        )


# Test utilities
def create_phoenix_chat_message(username: str, message: str, **kwargs) -> str:
    """Create a Phoenix chat message for testing."""
    data = {
        "user_name": username,
        "message": message,
        "timestamp": kwargs.get("timestamp", "2023-01-01T12:00:00Z"),
        "fragments": kwargs.get("fragments", []),
        "badges": kwargs.get("badges", [])
    }
    
    return json.dumps({
        "topic": "events:all",
        "event": "chat_message",
        "payload": {"data": data}
    })


def create_transcription_message(text: str, **kwargs) -> str:
    """Create a transcription message for testing."""
    data = {
        "type": "audio:transcription",
        "timestamp": kwargs.get("timestamp", int(datetime.now().timestamp() * 1_000_000)),
        "text": text,
        "duration": kwargs.get("duration", 1.0),
        "confidence": kwargs.get("confidence", 0.95),
        "correlation_id": kwargs.get("correlation_id", "test_correlation")
    }
    
    return json.dumps(data)


# Test fixtures
@pytest.fixture
def mock_websocket():
    """Provide a basic mock WebSocket connection."""
    return MockWebSocketFactory.create_stable_connection()


@pytest.fixture  
def failing_websocket():
    """Provide a failing mock WebSocket connection."""
    return MockWebSocketFactory.create_failing_connection()


@pytest.fixture
def unstable_websocket():
    """Provide an unstable mock WebSocket connection."""
    return MockWebSocketFactory.create_unstable_connection()


@pytest.fixture
def slow_websocket():
    """Provide a slow mock WebSocket connection."""
    return MockWebSocketFactory.create_slow_connection()


# Test the mock itself
class TestMockWebSocketConnection:
    """Test the mock WebSocket connection utilities."""
    
    @pytest.mark.asyncio
    async def test_basic_connection_lifecycle(self, mock_websocket):
        """Test basic connection lifecycle."""
        assert not mock_websocket.connected
        
        async with mock_websocket:
            assert mock_websocket.connected
        
        assert not mock_websocket.connected
        assert mock_websocket.close_called
    
    @pytest.mark.asyncio
    async def test_message_sending_and_tracking(self, mock_websocket):
        """Test message sending and tracking."""
        async with mock_websocket:
            await mock_websocket.send("test message")
            await mock_websocket.send_json({"type": "test", "data": "value"})
        
        assert len(mock_websocket.messages_sent) == 2
        assert mock_websocket.messages_sent[0] == "test message"
        
        json_msg = mock_websocket.get_sent_message(1)
        assert json_msg["type"] == "test"
        assert json_msg["data"] == "value"
    
    @pytest.mark.asyncio
    async def test_incoming_message_queue(self, mock_websocket):
        """Test incoming message queue."""
        mock_websocket.add_incoming_message("message 1")
        mock_websocket.add_incoming_message("message 2")
        
        messages = []
        async with mock_websocket:
            async for message in mock_websocket:
                messages.append(message)
        
        assert messages == ["message 1", "message 2"]
    
    @pytest.mark.asyncio
    async def test_phoenix_message_helpers(self, mock_websocket):
        """Test Phoenix message helper methods."""
        mock_websocket.add_phoenix_message(
            "test:channel", 
            "test_event", 
            {"data": "test"}, 
            "ref1"
        )
        mock_websocket.add_phoenix_reply("test:channel", "ok", {"result": "success"}, "ref2")
        
        messages = []
        async with mock_websocket:
            async for message in mock_websocket:
                messages.append(json.loads(message))
        
        assert len(messages) == 2
        assert messages[0]["event"] == "test_event"
        assert messages[1]["event"] == "phx_reply"
        assert messages[1]["payload"]["status"] == "ok"
    
    @pytest.mark.asyncio
    async def test_connection_failure_simulation(self, failing_websocket):
        """Test connection failure simulation."""
        with pytest.raises(ConnectionClosed):
            async with failing_websocket:
                pass
    
    @pytest.mark.asyncio
    async def test_message_failure_after_limit(self, mock_websocket):
        """Test message failure after limit."""
        mock_websocket.fail_after_n_messages = 2
        
        async with mock_websocket:
            await mock_websocket.send("message 1")
            
            # Second message should fail since fail_after_n_messages=2
            with pytest.raises(ConnectionClosed):
                await mock_websocket.send("message 2")
    
    @pytest.mark.asyncio
    async def test_ping_failure_simulation(self, mock_websocket):
        """Test ping failure simulation."""
        mock_websocket.fail_ping = True
        
        async with mock_websocket:
            with pytest.raises(ConnectionClosed):
                await mock_websocket.ping()
    
    @pytest.mark.asyncio
    async def test_metrics_collection(self, mock_websocket):
        """Test metrics collection."""
        async with mock_websocket:
            await mock_websocket.send("test message")
            await mock_websocket.ping()
        
        metrics = mock_websocket.get_metrics()
        assert metrics["messages_sent_count"] == 1
        assert metrics["ping_count"] == 1
        assert metrics["total_bytes_sent"] > 0
        assert metrics["connection_duration"] > 0
    
    @pytest.mark.asyncio
    async def test_queue_overflow_protection(self, mock_websocket):
        """Test message queue overflow protection."""
        mock_websocket.max_message_queue_size = 5
        
        # Add more messages than limit
        for i in range(10):
            mock_websocket.add_incoming_message(f"message {i}")
        
        # Should only keep the latest messages
        assert len(mock_websocket.incoming_messages) == 5
        assert "message 9" in mock_websocket.incoming_messages
        assert "message 0" not in mock_websocket.incoming_messages
    
    @pytest.mark.asyncio
    async def test_reset_functionality(self, mock_websocket):
        """Test reset functionality."""
        async with mock_websocket:
            await mock_websocket.send("test")
            await mock_websocket.ping()
        
        mock_websocket.reset()
        
        assert not mock_websocket.connected
        assert len(mock_websocket.messages_sent) == 0
        assert mock_websocket.ping_count == 0
        assert mock_websocket.total_bytes_sent == 0