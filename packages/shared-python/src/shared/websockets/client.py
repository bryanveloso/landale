"""Base WebSocket client with automatic reconnection logic."""

import asyncio
import logging
import weakref
from abc import ABC, abstractmethod

import websockets

logger = logging.getLogger(__name__)


class BaseWebSocketClient(ABC):
    """Base class for WebSocket clients with automatic reconnection."""

    def __init__(
        self,
        url: str,
        max_reconnect_attempts: int = 10,
        reconnect_delay_base: float = 1.0,
        reconnect_delay_cap: float = 60.0,
    ):
        self.url = url
        self.max_reconnect_attempts = max_reconnect_attempts
        self.reconnect_delay_base = reconnect_delay_base
        self.reconnect_delay_cap = reconnect_delay_cap

        # State management
        self._reconnect_attempts = 0
        self._reconnect_delay = reconnect_delay_base
        self._is_connected = False
        self._should_reconnect = True

        # Task tracking using WeakSet pattern from Phase 1.1
        self._background_tasks: weakref.WeakSet[asyncio.Task] = weakref.WeakSet()

        # Metrics
        self.total_reconnects = 0
        self.failed_reconnects = 0
        self.successful_connects = 0

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

    async def connect(self) -> bool:
        """Connect to WebSocket with automatic retry logic."""
        async with self._connection_lock:
            # Store the main event loop
            self._main_loop = asyncio.get_running_loop()

            self._reconnect_attempts = 0
            self._reconnect_delay = self.reconnect_delay_base

            while self._reconnect_attempts < self.max_reconnect_attempts:
                try:
                    logger.info(
                        f"Attempting to connect to {self.url} "
                        f"(attempt {self._reconnect_attempts + 1}/{self.max_reconnect_attempts})"
                    )

                    if await self._do_connect():
                        logger.info(f"Successfully connected to {self.url}")
                        self._is_connected = True
                        self._reconnect_attempts = 0
                        self._reconnect_delay = self.reconnect_delay_base
                        self.successful_connects += 1
                        return True

                except asyncio.CancelledError:
                    logger.info("Connection attempt cancelled")
                    raise
                except Exception as e:
                    logger.error(f"Connection attempt failed: {e}")

                self._reconnect_attempts += 1

                if self._reconnect_attempts >= self.max_reconnect_attempts:
                    logger.error(f"Failed to connect after {self.max_reconnect_attempts} attempts. Giving up.")
                    self.failed_reconnects += 1
                    self._is_connected = False
                    return False

                # Exponential backoff with cap
                await asyncio.sleep(self._reconnect_delay)
                self._reconnect_delay = min(self._reconnect_delay * 2, self.reconnect_delay_cap)

            return False

    async def listen_with_reconnect(self):
        """Listen for messages with automatic reconnection on disconnect."""
        while self._should_reconnect:
            try:
                if not self._is_connected:
                    if not await self.connect():
                        # Max reconnection attempts reached
                        break

                # Listen for messages
                await self._do_listen()

            except websockets.exceptions.ConnectionClosed:
                logger.info(f"Connection to {self.url} lost")
                self._is_connected = False
                self.total_reconnects += 1

                if self._should_reconnect:
                    logger.info("Attempting to reconnect...")
                    continue
                else:
                    break

            except asyncio.CancelledError:
                logger.info("Listen loop cancelled")
                break
            except Exception as e:
                logger.error(f"Unexpected error in listen loop: {e}")
                self._is_connected = False

                if self._should_reconnect:
                    await asyncio.sleep(1)  # Brief pause before reconnecting
                    continue
                else:
                    break

    async def disconnect(self):
        """Disconnect and cleanup."""
        async with self._connection_lock:
            logger.info(f"Disconnecting from {self.url}")
            self._should_reconnect = False
            self._is_connected = False

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

            logger.info(f"Disconnected from {self.url}")

    def create_task(self, coro) -> asyncio.Task:
        """Create and track a background task."""
        task = asyncio.create_task(coro)
        self._background_tasks.add(task)
        task.add_done_callback(self._background_tasks.discard)
        return task

    def get_status(self) -> dict:
        """Get connection status and metrics."""
        return {
            "connected": self._is_connected,
            "url": self.url,
            "reconnect_attempts": self._reconnect_attempts,
            "total_reconnects": self.total_reconnects,
            "failed_reconnects": self.failed_reconnects,
            "successful_connects": self.successful_connects,
            "background_tasks": len(self._background_tasks),
        }
