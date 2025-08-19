"""Supervisor patterns for Python service crash resilience."""

import asyncio
import logging
import signal
import time
import weakref
from abc import ABC, abstractmethod
from collections.abc import Callable
from enum import Enum
from typing import Any

logger = logging.getLogger(__name__)


class RestartStrategy(Enum):
    """Restart strategies for supervised services."""

    NONE = "none"  # Never restart
    ALWAYS = "always"  # Always restart
    ON_FAILURE = "on_failure"  # Only restart on non-zero exit


class ServiceState(Enum):
    """Service states."""

    STOPPED = "stopped"
    STARTING = "starting"
    RUNNING = "running"
    STOPPING = "stopping"
    FAILED = "failed"
    RESTARTING = "restarting"


class SupervisedService(ABC):
    """Base class for services that can be supervised."""

    @abstractmethod
    async def start(self) -> None:
        """Start the service."""
        pass

    @abstractmethod
    async def stop(self) -> None:
        """Stop the service gracefully."""
        pass

    @abstractmethod
    async def health_check(self) -> bool:
        """Check if service is healthy. Return True if healthy."""
        pass


class ServiceConfig:
    """Configuration for a supervised service."""

    def __init__(
        self,
        name: str,
        restart_strategy: RestartStrategy = RestartStrategy.ON_FAILURE,
        max_restarts: int = 10,
        restart_window_seconds: int = 300,  # 5 minutes
        restart_delay_seconds: float = 1.0,
        restart_delay_max: float = 60.0,
        health_check_interval: float = 30.0,
        shutdown_timeout: float = 30.0,
    ):
        self.name = name
        self.restart_strategy = restart_strategy
        self.max_restarts = max_restarts
        self.restart_window_seconds = restart_window_seconds
        self.restart_delay_seconds = restart_delay_seconds
        self.restart_delay_max = restart_delay_max
        self.health_check_interval = health_check_interval
        self.shutdown_timeout = shutdown_timeout


class ServiceSupervisor:
    """Supervisor for a single service with restart logic."""

    def __init__(self, service: SupervisedService, config: ServiceConfig):
        self.service = service
        self.config = config

        # State tracking
        self.state = ServiceState.STOPPED
        self.restart_count = 0
        self.restart_history: list[float] = []
        self.last_start_time = 0.0
        self.last_failure_time = 0.0

        # Tasks
        self.service_task: asyncio.Task | None = None
        self.health_task: asyncio.Task | None = None
        self.supervisor_task: asyncio.Task | None = None

        # Callbacks
        self.state_callbacks: list[Callable[[ServiceState, ServiceState], None]] = []
        self.failure_callbacks: list[Callable[[Exception], None]] = []

    def on_state_change(self, callback: Callable[[ServiceState, ServiceState], None]) -> None:
        """Register callback for state changes."""
        self.state_callbacks.append(callback)

    def on_failure(self, callback: Callable[[Exception], None]) -> None:
        """Register callback for service failures."""
        self.failure_callbacks.append(callback)

    def _emit_state_change(self, new_state: ServiceState) -> None:
        """Emit state change event."""
        if new_state != self.state:
            old_state = self.state
            self.state = new_state

            logger.info(
                "Service state changed",
                extra={"service": self.config.name, "old_state": old_state.value, "new_state": new_state.value},
            )

            for callback in self.state_callbacks:
                try:
                    callback(old_state, new_state)
                except Exception as e:
                    logger.error("Error in state change callback", extra={"error": str(e)})

    def _emit_failure(self, error: Exception) -> None:
        """Emit failure event."""
        for callback in self.failure_callbacks:
            try:
                callback(error)
            except Exception as e:
                logger.error("Error in failure callback", extra={"error": str(e)})

    async def start_supervised(self) -> None:
        """Start supervising the service."""
        if self.supervisor_task and not self.supervisor_task.done():
            logger.warning("Service already being supervised", extra={"service": self.config.name})
            return

        self.supervisor_task = asyncio.create_task(self._supervision_loop())

    async def stop_supervised(self) -> None:
        """Stop supervising the service."""
        if self.supervisor_task and not self.supervisor_task.done():
            self.supervisor_task.cancel()
            try:
                await self.supervisor_task
            except asyncio.CancelledError:
                pass

        await self._stop_service()

    async def _supervision_loop(self) -> None:
        """Main supervision loop."""
        try:
            while True:
                try:
                    await self._start_service()
                    await self._monitor_service()

                except asyncio.CancelledError:
                    logger.info("Supervision cancelled", extra={"service": self.config.name})
                    break

                except Exception as e:
                    logger.error("Service failed", extra={"service": self.config.name, "error": str(e)})
                    self.last_failure_time = time.time()
                    self._emit_failure(e)

                    # Check restart strategy
                    if not self._should_restart():
                        logger.info("Not restarting service due to restart policy", extra={"service": self.config.name})
                        break

                    # Calculate restart delay
                    delay = self._calculate_restart_delay()
                    if delay > 0:
                        logger.info(
                            "Waiting before restarting service",
                            extra={"service": self.config.name, "delay_seconds": delay},
                        )
                        self._emit_state_change(ServiceState.RESTARTING)
                        await asyncio.sleep(delay)

        finally:
            await self._stop_service()

    async def _start_service(self) -> None:
        """Start the service."""
        logger.info("Starting service", extra={"service": self.config.name})
        self._emit_state_change(ServiceState.STARTING)

        self.last_start_time = time.time()

        try:
            # Start the service
            await self.service.start()

            # Start health monitoring
            self.health_task = asyncio.create_task(self._health_monitor_loop())

            self._emit_state_change(ServiceState.RUNNING)
            logger.info("Service started successfully", extra={"service": self.config.name})

        except Exception:
            self._emit_state_change(ServiceState.FAILED)
            raise

    async def _stop_service(self) -> None:
        """Stop the service."""
        if self.state in (ServiceState.STOPPED, ServiceState.STOPPING):
            return

        logger.info("Stopping service", extra={"service": self.config.name})
        self._emit_state_change(ServiceState.STOPPING)

        # Cancel health monitoring
        if self.health_task and not self.health_task.done():
            self.health_task.cancel()
            try:
                await self.health_task
            except asyncio.CancelledError:
                pass

        # Stop the service with timeout
        try:
            await asyncio.wait_for(self.service.stop(), timeout=self.config.shutdown_timeout)
        except TimeoutError:
            logger.warning("Service did not stop gracefully within timeout", extra={"service": self.config.name})
        except Exception as e:
            logger.error("Error stopping service", extra={"service": self.config.name, "error": str(e)})

        self._emit_state_change(ServiceState.STOPPED)

    async def _monitor_service(self) -> None:
        """Monitor the service and wait for completion or failure."""
        # Wait for the health monitor to complete (indicates service stopped)
        if self.health_task:
            await self.health_task

    async def _health_monitor_loop(self) -> None:
        """Monitor service health."""
        consecutive_failures = 0
        max_consecutive_failures = 3

        while self.state == ServiceState.RUNNING:
            try:
                # Wait for health check interval
                await asyncio.sleep(self.config.health_check_interval)

                if self.state != ServiceState.RUNNING:
                    break

                # Perform health check
                is_healthy = await self.service.health_check()

                if is_healthy:
                    consecutive_failures = 0
                else:
                    consecutive_failures += 1
                    logger.warning(
                        f"Health check failed for {self.config.name} "
                        f"({consecutive_failures}/{max_consecutive_failures})"
                    )

                    if consecutive_failures >= max_consecutive_failures:
                        raise RuntimeError(f"Service {self.config.name} failed health checks")

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Health check error", extra={"service": self.config.name, "error": str(e)})
                raise

    def _should_restart(self) -> bool:
        """Check if service should be restarted based on strategy and limits."""
        if self.config.restart_strategy == RestartStrategy.NONE:
            return False

        if self.config.restart_strategy == RestartStrategy.ALWAYS:
            pass  # Always restart, check limits below
        elif self.config.restart_strategy == RestartStrategy.ON_FAILURE:
            pass  # Restart on failure, check limits below

        # Check restart limits
        current_time = time.time()

        # Clean old restart history
        self.restart_history = [
            restart_time
            for restart_time in self.restart_history
            if current_time - restart_time < self.config.restart_window_seconds
        ]

        if len(self.restart_history) >= self.config.max_restarts:
            logger.error(
                f"Service {self.config.name} reached max restarts "
                f"({self.config.max_restarts}) in {self.config.restart_window_seconds}s"
            )
            return False

        # Record this restart attempt
        self.restart_history.append(current_time)
        self.restart_count += 1

        return True

    def _calculate_restart_delay(self) -> float:
        """Calculate delay before restart with exponential backoff."""
        # Exponential backoff based on recent restart count
        recent_restarts = len(self.restart_history)
        delay = self.config.restart_delay_seconds * (2 ** min(recent_restarts, 6))
        return min(delay, self.config.restart_delay_max)

    def get_status(self) -> dict[str, Any]:
        """Get supervisor status."""
        return {
            "name": self.config.name,
            "state": self.state.value,
            "restart_count": self.restart_count,
            "recent_restarts": len(self.restart_history),
            "last_start_time": self.last_start_time,
            "last_failure_time": self.last_failure_time,
            "uptime_seconds": time.time() - self.last_start_time if self.state == ServiceState.RUNNING else 0,
        }


class ProcessSupervisor:
    """Process-level supervisor that manages multiple services."""

    def __init__(self):
        self.service_supervisors: dict[str, ServiceSupervisor] = {}
        self.shutdown_event = asyncio.Event()
        self.signal_handlers_registered = False

        # Task tracking using WeakSet pattern
        self._background_tasks: weakref.WeakSet[asyncio.Task] = weakref.WeakSet()

    def add_service(self, service: SupervisedService, config: ServiceConfig) -> ServiceSupervisor:
        """Add a service to supervision."""
        if config.name in self.service_supervisors:
            raise ValueError(f"Service {config.name} already exists")

        supervisor = ServiceSupervisor(service, config)

        # Log state changes
        supervisor.on_state_change(
            lambda old, new: logger.info(
                "Service state transition",
                extra={"service": config.name, "old_state": old.value, "new_state": new.value},
            )
        )

        # Log failures
        supervisor.on_failure(
            lambda error: logger.error("Service failure", extra={"service": config.name, "error": str(error)})
        )

        self.service_supervisors[config.name] = supervisor
        return supervisor

    def register_signal_handlers(self) -> None:
        """Register signal handlers for graceful shutdown."""
        if self.signal_handlers_registered:
            return

        def handle_shutdown():
            logger.info("Received shutdown signal")
            self.shutdown_event.set()

        try:
            loop = asyncio.get_event_loop()
            for sig in (signal.SIGTERM, signal.SIGINT):
                loop.add_signal_handler(sig, handle_shutdown)
            self.signal_handlers_registered = True
        except NotImplementedError:
            # Signal handlers not supported on this platform (e.g., Windows)
            logger.warning("Signal handlers not supported on this platform")

    async def start_all(self) -> None:
        """Start all supervised services."""
        logger.info("Starting services", extra={"service_count": len(self.service_supervisors)})

        tasks = []
        for supervisor in self.service_supervisors.values():
            task = self.create_task(supervisor.start_supervised())
            tasks.append(task)

        # Wait a moment for services to start
        await asyncio.sleep(1)
        logger.info("All services started")

    async def stop_all(self) -> None:
        """Stop all supervised services."""
        logger.info("Stopping services", extra={"service_count": len(self.service_supervisors)})

        tasks = []
        for supervisor in self.service_supervisors.values():
            task = self.create_task(supervisor.stop_supervised())
            tasks.append(task)

        # Wait for all to stop
        await asyncio.gather(*tasks, return_exceptions=True)

        # Cancel any remaining background tasks
        if self._background_tasks:
            remaining_tasks = list(self._background_tasks)
            for task in remaining_tasks:
                task.cancel()
            if remaining_tasks:
                await asyncio.gather(*remaining_tasks, return_exceptions=True)

        logger.info("All services stopped")

    async def wait_for_shutdown(self) -> None:
        """Wait for shutdown signal."""
        await self.shutdown_event.wait()

    def create_task(self, coro) -> asyncio.Task:
        """Create and track a background task."""
        task = asyncio.create_task(coro)
        self._background_tasks.add(task)
        task.add_done_callback(self._background_tasks.discard)
        return task

    def get_status(self) -> dict[str, Any]:
        """Get status of all supervised services."""
        return {
            "services": {name: supervisor.get_status() for name, supervisor in self.service_supervisors.items()},
            "total_services": len(self.service_supervisors),
            "running_services": sum(
                1 for supervisor in self.service_supervisors.values() if supervisor.state == ServiceState.RUNNING
            ),
            "background_tasks": len(self._background_tasks),
        }


# Utility functions for common patterns


async def run_with_supervisor(
    services: list[tuple[SupervisedService, ServiceConfig]], register_signals: bool = True
) -> None:
    """
    Run multiple services under supervision with signal handling.

    Args:
        services: List of (service, config) tuples
        register_signals: Whether to register signal handlers
    """
    supervisor = ProcessSupervisor()

    # Add all services
    for service, config in services:
        supervisor.add_service(service, config)

    # Register signal handlers
    if register_signals:
        supervisor.register_signal_handlers()

    try:
        # Start all services
        await supervisor.start_all()

        # Wait for shutdown signal
        await supervisor.wait_for_shutdown()

    finally:
        # Stop all services
        await supervisor.stop_all()
