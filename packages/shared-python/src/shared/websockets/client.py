"""Base WebSocket client with automatic reconnection logic."""

import asyncio
import logging
import random
import time
import weakref
from abc import ABC, abstractmethod
from collections.abc import Callable
from enum import Enum

import websockets

logger = logging.getLogger(__name__)


class ConnectionState(Enum):
    """WebSocket connection states."""

    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    RECONNECTING = "reconnecting"
    FAILED = "failed"


class ConnectionEvent:
    """Connection state change event."""

    def __init__(self, old_state: ConnectionState, new_state: ConnectionState, error: Exception | None = None):
        self.old_state = old_state
        self.new_state = new_state
        self.error = error
        self.timestamp = time.time()


class BaseWebSocketClient(ABC):
    """Base class for WebSocket clients with automatic reconnection."""

    def __init__(
        self,
        url: str,
        max_reconnect_attempts: int = 10,
        reconnect_delay_base: float = 1.0,
        reconnect_delay_cap: float = 60.0,
        heartbeat_interval: float = 30.0,
        circuit_breaker_threshold: int = 5,
        circuit_breaker_timeout: float = 300.0,
    ):
        self.url = url
        self.max_reconnect_attempts = max_reconnect_attempts
        self.reconnect_delay_base = reconnect_delay_base
        self.reconnect_delay_cap = reconnect_delay_cap
        self.heartbeat_interval = heartbeat_interval
        self.circuit_breaker_threshold = circuit_breaker_threshold
        self.circuit_breaker_timeout = circuit_breaker_timeout

        # Enhanced state management
        self._connection_state = ConnectionState.DISCONNECTED
        self._reconnect_attempts = 0
        self._reconnect_delay = reconnect_delay_base
        self._should_reconnect = True
        self._connection_callbacks: list[Callable[[ConnectionEvent], None]] = []

        # Health monitoring
        self._last_heartbeat = 0.0
        self._heartbeat_task: asyncio.Task | None = None
        self._heartbeat_failures = 0

        # Circuit breaker
        self._consecutive_failures = 0
        self._circuit_open_until = 0.0

        # Task tracking using WeakSet pattern from Phase 1.1
        self._background_tasks: weakref.WeakSet[asyncio.Task] = weakref.WeakSet()

        # Enhanced metrics
        self.total_reconnects = 0
        self.failed_reconnects = 0
        self.successful_connects = 0
        self.heartbeat_failures = 0
        self.circuit_breaker_trips = 0

        # Store main event loop for thread-safe operations
        self._main_loop: asyncio.AbstractEventLoop | None = None

        # Lock to prevent concurrent connection state changes
        self._connection_lock = asyncio.Lock()

    @abstractmethod
    async def _do_connect(self) -> bool:
        """
        Perform a single connection attempt.
        Returns True if successful, False otherwise.
        Subclasses must implement this.
        """
        pass

    @abstractmethod
    async def _do_disconnect(self):
        """
        Perform disconnection logic.
        Subclasses must implement this.
        """
        pass

    @abstractmethod
    async def _do_listen(self):
        """
        Listen for messages on the connection.
        Should raise websockets.exceptions.ConnectionClosed when disconnected.
        Subclasses must implement this.
        """
        pass

    def on_connection_change(self, callback: Callable[[ConnectionEvent], None]):
        """Register a callback for connection state changes."""
        self._connection_callbacks.append(callback)

    def _emit_connection_event(self, new_state: ConnectionState, error: Exception | None = None):
        """Emit a connection state change event."""
        if new_state != self._connection_state:
            event = ConnectionEvent(self._connection_state, new_state, error)
            self._connection_state = new_state

            for callback in self._connection_callbacks:
                try:
                    callback(event)
                except Exception as e:
                    logger.error("Error in connection callback", extra={"error": str(e)})

    def _is_circuit_open(self) -> bool:
        """Check if circuit breaker is open."""
        if self._circuit_open_until > time.time():
            return True

        # Reset if timeout passed
        if self._circuit_open_until > 0:
            logger.info("Circuit breaker timeout expired, attempting to close circuit")
            self._circuit_open_until = 0.0
            self._consecutive_failures = 0

        return False

    def _record_failure(self):
        """Record a connection failure for circuit breaker."""
        self._consecutive_failures += 1

        if self._consecutive_failures >= self.circuit_breaker_threshold:
            self._circuit_open_until = time.time() + self.circuit_breaker_timeout
            self.circuit_breaker_trips += 1
            logger.warning(
                f"Circuit breaker opened after {self._consecutive_failures} failures. "
                f"Will retry after {self.circuit_breaker_timeout}s"
            )

    def _record_success(self):
        """Record a successful connection."""
        self._consecutive_failures = 0
        self._circuit_open_until = 0.0

    async def _start_heartbeat(self):
        """Start heartbeat monitoring."""
        if self._heartbeat_task and not self._heartbeat_task.done():
            self._heartbeat_task.cancel()

        self._heartbeat_task = self.create_task(self._heartbeat_loop())

    async def _stop_heartbeat(self):
        """Stop heartbeat monitoring."""
        if self._heartbeat_task and not self._heartbeat_task.done():
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass

    async def _heartbeat_loop(self):
        """Health monitoring loop with ping/pong."""
        while self._connection_state == ConnectionState.CONNECTED:
            try:
                await asyncio.sleep(self.heartbeat_interval)

                if self._connection_state != ConnectionState.CONNECTED:
                    break

                # Send heartbeat ping (subclasses can override)
                success = await self._send_heartbeat()

                if success:
                    self._last_heartbeat = time.time()
                    self._heartbeat_failures = 0
                else:
                    self._heartbeat_failures += 1
                    self.heartbeat_failures += 1
                    logger.warning("Heartbeat failed", extra={"consecutive_failures": self._heartbeat_failures})

                    # Force reconnection after multiple heartbeat failures
                    if self._heartbeat_failures >= 3:
                        logger.error("Multiple heartbeat failures, forcing reconnection")
                        break

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Error in heartbeat loop", extra={"error": str(e)})
                break

    async def _send_heartbeat(self) -> bool:
        """
        Send heartbeat ping. Subclasses can override for protocol-specific pings.
        Default implementation always returns True (no-op).
        """
        return True

    async def connect(self) -> bool:
        """Connect to WebSocket with automatic retry logic."""
        async with self._connection_lock:
            # Store the main event loop
            self._main_loop = asyncio.get_running_loop()

            # Check circuit breaker before attempting connection
            if self._is_circuit_open():
                logger.warning("Circuit breaker open, not attempting connection", extra={"url": self.url})
                self._emit_connection_event(ConnectionState.FAILED)
                return False

            self._emit_connection_event(ConnectionState.CONNECTING)
            self._reconnect_attempts = 0
            self._reconnect_delay = self.reconnect_delay_base

            while self._reconnect_attempts < self.max_reconnect_attempts:
                try:
                    logger.info(
                        "Attempting connection",
                        extra={
                            "url": self.url,
                            "attempt": self._reconnect_attempts + 1,
                            "max_attempts": self.max_reconnect_attempts,
                        },
                    )

                    if await self._do_connect():
                        logger.info("Connection established", extra={"url": self.url})
                        self._reconnect_attempts = 0
                        self._reconnect_delay = self.reconnect_delay_base
                        self.successful_connects += 1

                        # Record success for circuit breaker
                        self._record_success()
                        self._emit_connection_event(ConnectionState.CONNECTED)

                        # Start heartbeat monitoring
                        await self._start_heartbeat()

                        return True

                except asyncio.CancelledError:
                    logger.info("Connection attempt cancelled")
                    self._emit_connection_event(ConnectionState.FAILED)
                    raise
                except Exception as e:
                    logger.error("Connection attempt failed", extra={"error": str(e)})
                    self._record_failure()

                self._reconnect_attempts += 1

                if self._reconnect_attempts >= self.max_reconnect_attempts:
                    logger.error(
                        "Failed to connect after max attempts. Giving up.",
                        extra={"max_attempts": self.max_reconnect_attempts},
                    )
                    self.failed_reconnects += 1
                    self._emit_connection_event(ConnectionState.FAILED)
                    return False

                # Exponential backoff with jitter
                jitter = random.uniform(0, 0.1) * self._reconnect_delay
                delay_with_jitter = self._reconnect_delay + jitter
                await asyncio.sleep(delay_with_jitter)
                self._reconnect_delay = min(self._reconnect_delay * 2, self.reconnect_delay_cap)

            return False

    async def listen_with_reconnect(self):
        """Listen for messages with automatic reconnection on disconnect."""
        while self._should_reconnect:
            try:
                if self._connection_state != ConnectionState.CONNECTED:
                    if not await self.connect():
                        # Max reconnection attempts reached or circuit breaker open
                        break

                # Listen for messages
                await self._do_listen()

            except websockets.exceptions.ConnectionClosed:
                logger.info("Connection lost", extra={"url": self.url})
                self.total_reconnects += 1

                # Stop heartbeat monitoring
                await self._stop_heartbeat()
                self._emit_connection_event(ConnectionState.DISCONNECTED)

                if self._should_reconnect:
                    logger.info("Attempting to reconnect...")
                    self._emit_connection_event(ConnectionState.RECONNECTING)
                    # Add exponential backoff delay before reconnecting to prevent connection storms
                    delay = min(self._reconnect_delay, self.reconnect_delay_cap)
                    await asyncio.sleep(delay)
                    self._reconnect_delay = min(self._reconnect_delay * 2, self.reconnect_delay_cap)
                    continue
                else:
                    break

            except asyncio.CancelledError:
                logger.info("Listen loop cancelled")
                await self._stop_heartbeat()
                self._emit_connection_event(ConnectionState.DISCONNECTED)
                break
            except Exception as e:
                logger.error("Unexpected error in listen loop", extra={"error": str(e)})
                await self._stop_heartbeat()
                self._emit_connection_event(ConnectionState.DISCONNECTED)

                if self._should_reconnect:
                    await asyncio.sleep(1)  # Brief pause before reconnecting
                    continue
                else:
                    break

    async def disconnect(self):
        """Disconnect and cleanup."""
        async with self._connection_lock:
            logger.info("Disconnecting", extra={"url": self.url})
            self._should_reconnect = False

            # Stop heartbeat monitoring
            await self._stop_heartbeat()

            # Cancel any background tasks
            if self._background_tasks:
                tasks = list(self._background_tasks)
                for task in tasks:
                    task.cancel()
                # Wait for cancellation with timeout
                if tasks:
                    await asyncio.wait(tasks, timeout=5.0)

            # Perform actual disconnection
            await self._do_disconnect()

            self._emit_connection_event(ConnectionState.DISCONNECTED)
            logger.info("Disconnected", extra={"url": self.url})

    def create_task(self, coro) -> asyncio.Task:
        """Create and track a background task."""
        task = asyncio.create_task(coro)
        self._background_tasks.add(task)
        task.add_done_callback(self._background_tasks.discard)
        return task

    async def health_check(self) -> bool:
        """Check if the WebSocket client is healthy."""
        try:
            # Check if connected
            if self._connection_state != ConnectionState.CONNECTED:
                return False

            # Check circuit breaker status
            if self._is_circuit_open():
                return False

            # Check if heartbeat is recent (within 2x heartbeat interval)
            if self._last_heartbeat > 0:
                time_since_heartbeat = time.time() - self._last_heartbeat
                if time_since_heartbeat > (self.heartbeat_interval * 2):
                    logger.debug("Heartbeat is stale", extra={"time_since_heartbeat": time_since_heartbeat})
                    return False

            return True

        except Exception as e:
            logger.error("Health check failed", extra={"error": str(e)})
            return False

    def get_status(self) -> dict:
        """Get connection status and metrics."""
        return {
            "connected": self._connection_state == ConnectionState.CONNECTED,
            "connection_state": self._connection_state.value,
            "url": self.url,
            "reconnect_attempts": self._reconnect_attempts,
            "total_reconnects": self.total_reconnects,
            "failed_reconnects": self.failed_reconnects,
            "successful_connects": self.successful_connects,
            "heartbeat_failures": self.heartbeat_failures,
            "circuit_breaker_trips": self.circuit_breaker_trips,
            "last_heartbeat": self._last_heartbeat,
            "circuit_open_until": self._circuit_open_until,
            "consecutive_failures": self._consecutive_failures,
            "background_tasks": len(self._background_tasks),
        }
