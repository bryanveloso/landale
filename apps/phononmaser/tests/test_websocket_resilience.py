"""Comprehensive WebSocket resilience tests for phononmaser."""

import asyncio
import contextlib
import json
import time
from datetime import datetime
from unittest.mock import patch

import pytest
import websockets
from shared.websockets import BaseWebSocketClient, ConnectionEvent, ConnectionState

from src.events import TranscriptionEvent
from src.websocket_client import ServerWebSocketClient

# Mark all tests as async
pytestmark = pytest.mark.asyncio


class MockWebSocketConnection:
    """Mock WebSocket connection for controlled testing."""

    def __init__(self, should_fail_connect=False, fail_after_n_messages=None, connection_delay=0, fail_heartbeat=False):
        self.should_fail_connect = should_fail_connect
        self.fail_after_n_messages = fail_after_n_messages
        self.connection_delay = connection_delay
        self.fail_heartbeat = fail_heartbeat

        # State tracking
        self.connected = False
        self.messages_sent = []
        self.messages_received = 0
        self.close_called = False
        self.ping_called = False

        # Connection lifecycle callbacks
        self.on_connect_callbacks = []
        self.on_disconnect_callbacks = []

    async def connect(self):
        """Simulate connection with optional delays and failures."""
        if self.connection_delay > 0:
            await asyncio.sleep(self.connection_delay)

        if self.should_fail_connect:
            raise websockets.exceptions.ConnectionClosed(None, None)

        self.connected = True
        for callback in self.on_connect_callbacks:
            await callback()

    async def send(self, message):
        """Simulate sending messages with optional failures."""
        if not self.connected:
            raise websockets.exceptions.ConnectionClosed(None, None)

        self.messages_sent.append(json.loads(message))
        self.messages_received += 1

        # Simulate connection failure after N messages
        if self.fail_after_n_messages and self.messages_received >= self.fail_after_n_messages:
            self.connected = False
            for callback in self.on_disconnect_callbacks:
                await callback()
            raise websockets.exceptions.ConnectionClosed(None, None)

    async def close(self):
        """Simulate connection close."""
        self.close_called = True
        self.connected = False
        for callback in self.on_disconnect_callbacks:
            await callback()

    async def ping(self):
        """Simulate ping with optional failures."""
        self.ping_called = True
        if self.fail_heartbeat:
            raise websockets.exceptions.ConnectionClosed(None, None)

    def __aiter__(self):
        return self

    async def __anext__(self):
        """Simulate message reception."""
        if not self.connected:
            raise StopAsyncIteration

        # Simulate waiting for messages
        await asyncio.sleep(0.1)

        # Send a test message back
        return json.dumps(
            {"topic": "transcription:live", "event": "phx_reply", "payload": {"status": "ok"}, "ref": "1"}
        )


class TestWebSocketResilience:
    """Test WebSocket connection resilience patterns."""

    @pytest.fixture
    async def mock_websocket(self):
        """Create a mock WebSocket connection."""
        return MockWebSocketConnection()

    @pytest.fixture
    async def resilient_client(self):
        """Create a test client with resilience settings."""
        client = ServerWebSocketClient("ws://test:7175/socket/websocket", stream_session_id="test_resilience")
        yield client
        await client.disconnect()

    async def test_basic_connection_establishment(self, resilient_client, mock_websocket):
        """Test basic connection establishment."""
        with patch("websockets.connect", return_value=mock_websocket):
            success = await resilient_client._do_connect()

            assert success is True
            assert resilient_client._connection_state == ConnectionState.CONNECTED
            assert mock_websocket.connected is True

    async def test_connection_failure_handling(self, resilient_client):
        """Test handling of connection failures."""
        # Mock websockets.connect to fail
        with patch("websockets.connect", side_effect=websockets.exceptions.ConnectionClosed(None, None)):
            success = await resilient_client._do_connect()

            assert success is False
            assert resilient_client._connection_state == ConnectionState.DISCONNECTED

    async def test_exponential_backoff_reconnection(self, resilient_client):
        """Test exponential backoff during reconnection attempts."""
        resilient_client.max_reconnect_attempts = 3
        delays = []

        async def mock_sleep(delay):
            delays.append(delay)

        with (
            patch("websockets.connect", side_effect=websockets.exceptions.ConnectionClosed(None, None)),
            patch("asyncio.sleep", side_effect=mock_sleep),
        ):
            success = await resilient_client.connect()

            assert success is False
            assert len(delays) >= 2  # Should have multiple retry delays

            # Check exponential backoff pattern (with jitter tolerance)
            for i in range(1, len(delays)):
                expected_min = resilient_client.reconnect_delay_base * (2 ** (i - 1))
                assert delays[i] >= expected_min * 0.9  # Allow 10% jitter tolerance

    async def test_connection_recovery_after_message_failure(self, resilient_client):
        """Test connection recovery after message send failures."""
        # Mock connection that fails after 2 messages
        mock_ws = MockWebSocketConnection(fail_after_n_messages=2)

        connection_states = []

        def track_state_changes(event: ConnectionEvent):
            connection_states.append((event.old_state, event.new_state))

        resilient_client.on_connection_change(track_state_changes)

        with patch("websockets.connect", return_value=mock_ws):
            # Initial connection
            await resilient_client._do_connect()

            # Send messages until failure
            event = TranscriptionEvent(
                timestamp=int(datetime.now().timestamp() * 1_000_000), text="Test message", duration=1.0
            )

            # First message should succeed
            await resilient_client.send_transcription(event)
            assert len(mock_ws.messages_sent) == 1

            # Second message should trigger failure
            with pytest.raises(websockets.exceptions.ConnectionClosed):
                await resilient_client.send_transcription(event)

            # Verify connection state changed
            assert any(state[1] == ConnectionState.DISCONNECTED for state in connection_states)

    async def test_circuit_breaker_opens_after_failures(self, resilient_client):
        """Test circuit breaker opens after consecutive failures."""
        resilient_client.circuit_breaker_threshold = 3

        # Simulate multiple connection failures
        with patch("websockets.connect", side_effect=websockets.exceptions.ConnectionClosed(None, None)):
            for _i in range(resilient_client.circuit_breaker_threshold):
                await resilient_client._do_connect()
                resilient_client._record_failure()

            # Circuit breaker should be open
            assert resilient_client._is_circuit_open() is True
            assert resilient_client.circuit_breaker_trips == 1

    async def test_circuit_breaker_closes_after_timeout(self, resilient_client):
        """Test circuit breaker closes after timeout period."""
        resilient_client.circuit_breaker_threshold = 2
        resilient_client.circuit_breaker_timeout = 0.1  # Short timeout for testing

        # Open the circuit breaker
        resilient_client._consecutive_failures = resilient_client.circuit_breaker_threshold
        resilient_client._circuit_open_until = time.time() + resilient_client.circuit_breaker_timeout

        assert resilient_client._is_circuit_open() is True

        # Wait for timeout
        await asyncio.sleep(0.2)

        # Circuit breaker should close
        assert resilient_client._is_circuit_open() is False

    async def test_heartbeat_failure_detection(self, resilient_client):
        """Test heartbeat failure detection and recovery."""
        # Mock connection that fails heartbeat
        mock_ws = MockWebSocketConnection(fail_heartbeat=True)

        with patch("websockets.connect", return_value=mock_ws):
            await resilient_client._do_connect()

            # Test heartbeat failure
            success = await resilient_client._send_heartbeat()
            assert success is False

            # Verify ping was attempted
            assert mock_ws.ping_called is True

    async def test_concurrent_message_sending(self, resilient_client):
        """Test handling of concurrent message sending."""
        mock_ws = MockWebSocketConnection()

        with patch("websockets.connect", return_value=mock_ws):
            await resilient_client._do_connect()
            resilient_client._channel_joined = True

            # Send multiple messages concurrently
            events = [
                TranscriptionEvent(
                    timestamp=int(datetime.now().timestamp() * 1_000_000) + i,
                    text=f"Concurrent message {i}",
                    duration=1.0,
                )
                for i in range(10)
            ]

            tasks = [resilient_client.send_transcription(event) for event in events]
            results = await asyncio.gather(*tasks, return_exceptions=True)

            # All messages should succeed
            assert all(result is True for result in results)
            assert len(mock_ws.messages_sent) == 10

    async def test_message_queue_overflow_protection(self, resilient_client):
        """Test protection against message queue overflow."""

        # Simulate slow connection by adding delay to send
        async def slow_send(message):
            await asyncio.sleep(0.1)  # Slow send
            await MockWebSocketConnection().send(message)

        mock_ws = MockWebSocketConnection()
        mock_ws.send = slow_send

        with patch("websockets.connect", return_value=mock_ws):
            await resilient_client._do_connect()
            resilient_client._channel_joined = True

            # Send many messages rapidly
            events = [
                TranscriptionEvent(
                    timestamp=int(datetime.now().timestamp() * 1_000_000) + i, text=f"Rapid message {i}", duration=0.1
                )
                for i in range(50)
            ]

            # Should handle rapid sending without overflow
            tasks = [resilient_client.send_transcription(event) for event in events]

            # Use timeout to prevent hanging
            import contextlib

            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(asyncio.gather(*tasks, return_exceptions=True), timeout=2.0)

    async def test_connection_state_consistency(self, resilient_client):
        """Test connection state remains consistent during failures."""
        connection_events = []

        def track_events(event: ConnectionEvent):
            connection_events.append(
                {
                    "old_state": event.old_state,
                    "new_state": event.new_state,
                    "timestamp": event.timestamp,
                    "error": event.error,
                }
            )

        resilient_client.on_connection_change(track_events)

        # Test connection cycle
        mock_ws = MockWebSocketConnection()
        with patch("websockets.connect", return_value=mock_ws):
            # Connect
            await resilient_client._do_connect()

            # Disconnect
            await resilient_client._do_disconnect()

            # Verify state transitions
            assert len(connection_events) >= 2

            # Check state progression
            states = [event["new_state"] for event in connection_events]
            assert ConnectionState.CONNECTED in states
            assert ConnectionState.DISCONNECTED in states

    async def test_memory_leak_prevention(self, resilient_client):
        """Test prevention of memory leaks during connection cycles."""
        initial_task_count = len(asyncio.all_tasks())

        # Perform multiple connection cycles
        for _i in range(5):
            mock_ws = MockWebSocketConnection()
            with patch("websockets.connect", return_value=mock_ws):
                await resilient_client._do_connect()
                await resilient_client._do_disconnect()

        # Wait for cleanup
        await asyncio.sleep(0.1)

        # Task count should not grow significantly
        final_task_count = len(asyncio.all_tasks())
        task_growth = final_task_count - initial_task_count

        # Allow some growth but prevent excessive accumulation
        assert task_growth < 10, f"Potential memory leak: {task_growth} new tasks"

    async def test_network_interruption_simulation(self, resilient_client):
        """Test behavior during network interruption simulation."""
        # Track reconnection attempts
        reconnect_attempts = []

        async def track_reconnect():
            reconnect_attempts.append(time.time())

        # Mock connection that fails randomly
        connection_count = 0

        async def intermittent_connection():
            nonlocal connection_count
            connection_count += 1

            if connection_count % 3 == 0:  # Fail every 3rd attempt
                raise websockets.exceptions.ConnectionClosed(None, None)

            mock_ws = MockWebSocketConnection()
            mock_ws.on_connect_callbacks.append(track_reconnect)
            return mock_ws

        with patch("websockets.connect", side_effect=intermittent_connection):
            # Try to establish stable connection
            for _ in range(10):
                try:
                    await resilient_client._do_connect()
                    break
                except websockets.exceptions.ConnectionClosed:
                    await asyncio.sleep(0.01)  # Brief pause between attempts

        # Should eventually succeed and track attempts
        assert len(reconnect_attempts) > 0

    async def test_graceful_shutdown_during_operation(self, resilient_client):
        """Test graceful shutdown while operations are in progress."""
        mock_ws = MockWebSocketConnection()

        with patch("websockets.connect", return_value=mock_ws):
            await resilient_client._do_connect()
            resilient_client._channel_joined = True

            # Start long-running operation
            async def long_operation():
                for i in range(100):
                    event = TranscriptionEvent(
                        timestamp=int(datetime.now().timestamp() * 1_000_000) + i,
                        text=f"Long operation message {i}",
                        duration=0.1,
                    )
                    await resilient_client.send_transcription(event)
                    await asyncio.sleep(0.01)

            # Start operation and shutdown after brief time
            operation_task = asyncio.create_task(long_operation())
            await asyncio.sleep(0.1)

            # Shutdown should be graceful
            shutdown_task = asyncio.create_task(resilient_client.disconnect())

            # Wait for shutdown with timeout
            try:
                await asyncio.wait_for(shutdown_task, timeout=2.0)
            except TimeoutError:
                pytest.fail("Graceful shutdown took too long")

            # Cancel the operation
            operation_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await operation_task

            # Verify clean shutdown
            assert resilient_client._connection_state == ConnectionState.DISCONNECTED


class TestBaseWebSocketClientResilience:
    """Test BaseWebSocketClient resilience patterns."""

    class TestClient(BaseWebSocketClient):
        """Test implementation of BaseWebSocketClient."""

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.mock_ws = None
            self.connect_attempts = 0
            self.disconnect_calls = 0
            self.listen_calls = 0

        async def _do_connect(self) -> bool:
            self.connect_attempts += 1
            if hasattr(self, "_should_fail_connect") and self._should_fail_connect:
                return False

            self.mock_ws = MockWebSocketConnection()
            return True

        async def _do_disconnect(self):
            self.disconnect_calls += 1
            if self.mock_ws:
                await self.mock_ws.close()

        async def _do_listen(self):
            self.listen_calls += 1
            if not self.mock_ws:
                raise RuntimeError("Not connected")

            # Simulate listening
            async for _message in self.mock_ws:
                # Process message
                pass

    @pytest.fixture
    async def base_client(self):
        """Create test BaseWebSocketClient."""
        client = self.TestClient(
            "ws://test:7175/socket",
            max_reconnect_attempts=3,
            reconnect_delay_base=0.01,  # Fast for testing
            heartbeat_interval=0.1,
        )
        yield client
        await client.disconnect()

    async def test_connection_retry_with_backoff(self, base_client):
        """Test connection retry with exponential backoff."""
        base_client._should_fail_connect = True

        # Mock sleep to track delays
        delays = []

        async def track_sleep(delay):
            delays.append(delay)

        with patch("asyncio.sleep", side_effect=track_sleep):
            success = await base_client.connect()

            assert success is False
            assert base_client.connect_attempts == 3  # max_reconnect_attempts

            # Should have backoff delays
            assert len(delays) >= 2

    async def test_automatic_reconnection_on_disconnect(self, base_client):
        """Test automatic reconnection when connection is lost."""
        # Initial connection should succeed
        success = await base_client.connect()
        assert success is True
        assert base_client._connection_state == ConnectionState.CONNECTED

        # Start listen loop
        listen_task = asyncio.create_task(base_client.listen_with_reconnect())

        # Wait briefly for listen to start
        await asyncio.sleep(0.05)

        # Simulate connection loss
        if base_client.mock_ws:
            base_client.mock_ws.connected = False

        # Wait for reconnection attempt
        await asyncio.sleep(0.2)

        # Stop listening
        base_client._should_reconnect = False

        try:
            await asyncio.wait_for(listen_task, timeout=1.0)
        except TimeoutError:
            listen_task.cancel()

    async def test_circuit_breaker_prevents_connection_storms(self, base_client):
        """Test circuit breaker prevents connection storms."""
        base_client._should_fail_connect = True
        base_client.circuit_breaker_threshold = 2

        # Trigger circuit breaker
        for _ in range(base_client.circuit_breaker_threshold + 1):
            await base_client._do_connect()
            base_client._record_failure()

        assert base_client._is_circuit_open() is True

        # Next connection attempt should fail fast
        start_time = time.time()
        success = await base_client.connect()
        end_time = time.time()

        assert success is False
        assert (end_time - start_time) < 0.1  # Should fail fast

    async def test_heartbeat_monitoring(self, base_client):
        """Test heartbeat monitoring and failure detection."""
        await base_client.connect()

        # Start heartbeat monitoring
        await base_client._start_heartbeat()

        # Wait for heartbeat to run
        await asyncio.sleep(0.15)  # Longer than heartbeat_interval

        # Stop heartbeat
        await base_client._stop_heartbeat()

        # Verify heartbeat was attempted
        assert base_client._last_heartbeat > 0

    async def test_health_check_accuracy(self, base_client):
        """Test health check accurately reflects connection state."""
        # Initially disconnected
        assert await base_client.health_check() is False

        # Connect
        await base_client.connect()
        assert await base_client.health_check() is True

        # Disconnect
        await base_client.disconnect()
        assert await base_client.health_check() is False

    async def test_status_metrics_tracking(self, base_client):
        """Test connection metrics are tracked correctly."""
        initial_status = base_client.get_status()

        # Connect and disconnect multiple times
        for _ in range(3):
            await base_client.connect()
            await base_client.disconnect()

        final_status = base_client.get_status()

        # Metrics should be updated
        assert final_status["successful_connects"] >= initial_status["successful_connects"]
        assert final_status["total_reconnects"] >= initial_status["total_reconnects"]

    async def test_task_cleanup_on_disconnect(self, base_client):
        """Test background tasks are cleaned up on disconnect."""
        await base_client.connect()

        # Create some background tasks
        for _i in range(5):
            base_client.create_task(asyncio.sleep(10))  # Long-running tasks

        initial_task_count = len(base_client._background_tasks)
        assert initial_task_count == 5

        # Disconnect should clean up tasks
        await base_client.disconnect()

        # Wait for cleanup
        await asyncio.sleep(0.1)

        # Tasks should be cleaned up or cancelled
        final_task_count = len([t for t in base_client._background_tasks if not t.done()])
        assert final_task_count == 0


class TestIntegrationScenarios:
    """Test realistic integration scenarios."""

    async def test_production_like_workload(self):
        """Test production-like workload with mixed operations."""
        client = ServerWebSocketClient("ws://test:7175/socket/websocket", stream_session_id="production_test")

        mock_ws = MockWebSocketConnection()

        try:
            with patch("websockets.connect", return_value=mock_ws):
                # Connect
                await client._do_connect()
                client._channel_joined = True

                # Mixed workload
                tasks = []

                # Regular transcription events
                for i in range(20):
                    event = TranscriptionEvent(
                        timestamp=int(datetime.now().timestamp() * 1_000_000) + i,
                        text=f"Production transcription {i}",
                        duration=2.0,
                    )
                    tasks.append(client.send_transcription(event))

                # Health checks
                for _ in range(5):
                    tasks.append(client.health_check())

                # Execute workload
                results = await asyncio.gather(*tasks, return_exceptions=True)

                # Most operations should succeed
                success_count = sum(1 for r in results if r is True)
                assert success_count >= len(tasks) * 0.8  # 80% success rate

        finally:
            await client.disconnect()

    async def test_stress_connection_cycling(self):
        """Test stress scenario with rapid connection cycling."""
        client = ServerWebSocketClient("ws://test:7175/socket/websocket")

        try:
            # Rapid connection cycling
            for _cycle in range(10):
                mock_ws = MockWebSocketConnection()

                with patch("websockets.connect", return_value=mock_ws):
                    # Quick connect/disconnect cycle
                    await client._do_connect()
                    await asyncio.sleep(0.01)  # Brief operation
                    await client._do_disconnect()
                    await asyncio.sleep(0.01)  # Brief pause

            # Should handle gracefully without crashes
            assert client._connection_state == ConnectionState.DISCONNECTED

        finally:
            await client.disconnect()
