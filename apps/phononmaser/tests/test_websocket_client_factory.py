"""Test-specific WebSocket client for dependency injection."""

import asyncio
from collections.abc import Callable

from src.websocket_client import ServerWebSocketClient


class TestWebSocketClient(ServerWebSocketClient):
    """Test implementation of ServerWebSocketClient that doesn't create background tasks."""

    def __init__(self, server_url: str, stream_session_id: str):
        # Don't call super().__init__ to avoid BaseWebSocketClient initialization
        self.server_url = server_url
        self.stream_session_id = stream_session_id
        self._phoenix_ref = 1
        self.state = "disconnected"
        self.joined_transcription = False
        self.ws = None
        self._listen_task = None
        self._heartbeat_task = None

        # Test helpers
        self.sent_messages = []
        self.connect_called = False
        self.disconnect_called = False

        # Circuit breaker attributes for tests
        self.circuit_breaker_threshold = 5
        self.circuit_breaker_timeout = 30.0
        self._circuit_failures = 0
        self._circuit_last_failure = None

        # Connection state callbacks
        self._connection_callbacks = []

        # Heartbeat interval
        self.heartbeat_interval = 30

    async def connect(self) -> None:
        """Simulate connection without creating background tasks."""
        self.connect_called = True
        self.state = "connecting"

        # Simulate successful connection
        await asyncio.sleep(0)  # Yield control
        self.state = "connected"

        # Notify callbacks
        for callback in self._connection_callbacks:
            callback(
                type(
                    "Event",
                    (),
                    {
                        "old_state": type("State", (), {"value": "disconnected"}),
                        "new_state": type("State", (), {"value": "connected"}),
                    },
                )
            )

    async def disconnect(self) -> None:
        """Simulate disconnection."""
        self.disconnect_called = True
        old_state = self.state
        self.state = "disconnected"

        # Notify callbacks
        for callback in self._connection_callbacks:
            callback(
                type(
                    "Event",
                    (),
                    {
                        "old_state": type("State", (), {"value": old_state}),
                        "new_state": type("State", (), {"value": "disconnected"}),
                    },
                )
            )

    async def send_transcription(self, event) -> bool:
        """Capture sent transcriptions for testing."""
        if self.state != "connected" or not self.joined_transcription:
            return False

        message = {
            "topic": "transcription:live",
            "event": "submit_transcription",
            "payload": {
                "text": event.text,
                "duration": event.duration,
                "timestamp": event.timestamp,
                "stream_session_id": self.stream_session_id,
            },
            "ref": str(self._phoenix_ref),
        }

        self.sent_messages.append(message)
        self._phoenix_ref += 1
        return True

    def on_connection_change(self, callback: Callable) -> None:
        """Register connection state change callback."""
        self._connection_callbacks.append(callback)

    def _is_circuit_open(self) -> bool:
        """Check if circuit breaker is open."""
        if self._circuit_failures >= self.circuit_breaker_threshold and self._circuit_last_failure:
            import time

            if time.time() - self._circuit_last_failure < self.circuit_breaker_timeout:
                return True
            else:
                # Reset circuit breaker
                self._circuit_failures = 0
                self._circuit_last_failure = None
        return False

    async def __aenter__(self):
        """Context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        await self.disconnect()


def create_test_client(
    server_url: str = "ws://test:7175/socket/websocket", stream_session_id: str = "test_session"
) -> TestWebSocketClient:
    """Factory function to create test WebSocket clients."""
    return TestWebSocketClient(server_url, stream_session_id)
