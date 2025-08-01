"""Task tracking utilities for debugging async operations."""

import asyncio
import logging
import weakref
from collections.abc import Coroutine
from typing import Any, TypeVar

# Use a specific logger for task tracking
logger = logging.getLogger("landale.task_tracker")

T = TypeVar("T")


class TaskTracker:
    """Track and debug async tasks using WeakSet pattern."""

    def __init__(self, name: str = "default"):
        self.name = name
        self._active_tasks: weakref.WeakSet = weakref.WeakSet()
        self._task_counter = 0
        self._completed_count = 0
        self._failed_count = 0
        self._cancelled_count = 0
        logger.info(f"TaskTracker '{self.name}' initialized")

    def create_task(
        self, coro: Coroutine[Any, Any, T], *, name: str | None = None, log_errors: bool = True
    ) -> asyncio.Task[T]:
        """
        Create and track an asyncio task.

        Args:
            coro: Coroutine to run
            name: Optional name for the task (recommended for debugging)
            log_errors: Whether to log errors when task fails

        Returns:
            The created asyncio.Task
        """
        # Generate a name if not provided
        if name is None:
            func_name = getattr(coro, "__name__", "unknown")
            self._task_counter += 1
            name = f"{func_name}_{self._task_counter}"

        # Create the task
        task = asyncio.create_task(coro, name=name)
        self._active_tasks.add(task)

        logger.debug(f"Task '{task.get_name()}' created. Active tasks: {len(self._active_tasks)}")

        # Add completion callback
        def _on_done(t: asyncio.Task):
            try:
                if t.cancelled():
                    self._cancelled_count += 1
                    logger.info(f"Task '{t.get_name()}' cancelled")
                elif t.exception():
                    self._failed_count += 1
                    if log_errors:
                        logger.error(f"Task '{t.get_name()}' failed: {t.exception()}", exc_info=t.exception())
                else:
                    self._completed_count += 1
                    logger.debug(f"Task '{t.get_name()}' completed successfully")
            except Exception as e:
                logger.warning(f"Error in task done callback: {e}")
            finally:
                # WeakSet automatically removes the task, but log the count
                logger.debug(f"Active tasks remaining: {len(self._active_tasks)}")

        task.add_done_callback(_on_done)
        return task

    def get_status(self) -> dict[str, Any]:
        """
        Get current task tracking status.

        Returns:
            Dict with task statistics and active task details
        """
        active_tasks = []

        # Create a snapshot to avoid iteration issues
        for task in list(self._active_tasks):
            try:
                task_info = {
                    "name": task.get_name(),
                    "done": task.done(),
                    "cancelled": task.cancelled(),
                }

                if task.done():
                    try:
                        exc = task.exception()
                        if exc:
                            task_info["error"] = str(exc)
                            task_info["state"] = "failed"
                        else:
                            task_info["state"] = "completed"
                    except asyncio.CancelledError:
                        task_info["state"] = "cancelled"
                    except asyncio.InvalidStateError:
                        task_info["state"] = "done"
                else:
                    task_info["state"] = "running"

                active_tasks.append(task_info)

            except ReferenceError:
                # Task was garbage collected
                logger.debug("Skipped GC'd task in status collection")
            except Exception as e:
                logger.warning(f"Error getting task info: {e}")

        return {
            "tracker_name": self.name,
            "active_count": len(self._active_tasks),
            "completed_count": self._completed_count,
            "failed_count": self._failed_count,
            "cancelled_count": self._cancelled_count,
            "total_created": self._task_counter,
            "active_tasks": active_tasks,
        }

    async def shutdown(self, timeout: float = 5.0) -> None:
        """
        Cancel all tracked tasks and wait for completion.

        Args:
            timeout: Maximum time to wait for tasks to complete
        """
        if not self._active_tasks:
            logger.info(f"TaskTracker '{self.name}' shutdown: no active tasks")
            return

        tasks = list(self._active_tasks)
        logger.info(f"TaskTracker '{self.name}' shutdown: cancelling {len(tasks)} tasks")

        # Cancel all tasks
        for task in tasks:
            if not task.done():
                task.cancel()

        # Wait for cancellation with timeout
        try:
            await asyncio.wait_for(asyncio.gather(*tasks, return_exceptions=True), timeout=timeout)
            logger.info(f"TaskTracker '{self.name}' shutdown complete")
        except TimeoutError:
            logger.warning(
                f"TaskTracker '{self.name}' shutdown: "
                f"{sum(1 for t in tasks if not t.done())} tasks didn't complete in {timeout}s"
            )


# Global tracker instance for convenience
_global_tracker = TaskTracker("global")


def get_global_tracker() -> TaskTracker:
    """Get the global task tracker instance."""
    return _global_tracker


# Convenience function for simple task creation
def create_tracked_task(
    coro: Coroutine[Any, Any, T], *, name: str | None = None, log_errors: bool = True
) -> asyncio.Task[T]:
    """Create a tracked task using the global tracker."""
    return _global_tracker.create_task(coro, name=name, log_errors=log_errors)
