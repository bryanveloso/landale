"""Error boundary decorator for preventing cascade failures in services.

This module provides a decorator pattern for wrapping functions with error handling
to prevent single failures from crashing entire services. Designed for personal-scale
streaming project with focus on simplicity and reliability.
"""

import asyncio
import functools
import logging
from typing import Any, Callable, Optional, Tuple, Type, TypeVar, Union

T = TypeVar('T')
logger = logging.getLogger(__name__)


def error_boundary(
    *,
    log_level: int = logging.ERROR,
    reraise: bool = False,
    default_return: Any = None,
    retry_attempts: int = 0,
    retry_delay: float = 0.1,
    catch_exceptions: Tuple[Type[Exception], ...] = (Exception,),
    ignore_exceptions: Tuple[Type[Exception], ...] = (asyncio.CancelledError,)
) -> Callable:
    """Decorator to add error boundary to async functions.
    
    Prevents cascade failures by catching and handling exceptions gracefully.
    Default behavior is to log errors and continue execution.
    
    Args:
        log_level: Logging level for errors (default: ERROR)
        reraise: Whether to re-raise exceptions after logging (default: False)
        default_return: Value to return on error (default: None)
        retry_attempts: Number of retry attempts for transient errors (default: 0)
        retry_delay: Base delay between retries in seconds (default: 0.1)
        catch_exceptions: Tuple of exceptions to catch (default: all Exceptions)
        ignore_exceptions: Tuple of exceptions to let propagate (default: CancelledError)
    
    Example:
        @error_boundary()
        async def risky_operation():
            # This won't crash the service if it fails
            await external_api_call()
            
        @error_boundary(retry_attempts=3, retry_delay=1.0)
        async def network_operation():
            # This will retry up to 3 times with exponential backoff
            return await fetch_data()
    """
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        # Determine if the function is async
        is_async = asyncio.iscoroutinefunction(func)
        
        if is_async:
            @functools.wraps(func)
            async def async_wrapper(*args, **kwargs) -> T:
                attempts = 0
                
                while attempts <= retry_attempts:
                    try:
                        return await func(*args, **kwargs)
                    except ignore_exceptions:
                        # Let these exceptions propagate (e.g., CancelledError)
                        raise
                    except catch_exceptions as e:
                        # Log the error with context
                        logger.log(
                            log_level,
                            f"Error in {func.__module__}.{func.__name__}: {type(e).__name__}: {e}",
                            exc_info=True,
                            extra={
                                "function": func.__name__,
                                "module": func.__module__,
                                "attempt": attempts + 1,
                                "max_attempts": retry_attempts + 1
                            }
                        )
                        
                        if attempts < retry_attempts:
                            attempts += 1
                            # Exponential backoff
                            delay = retry_delay * (2 ** (attempts - 1))
                            logger.info(
                                f"Retrying {func.__name__} in {delay:.1f}s "
                                f"(attempt {attempts}/{retry_attempts})"
                            )
                            await asyncio.sleep(delay)
                            continue
                        
                        # Max retries reached or no retries configured
                        if reraise:
                            raise
                        return default_return
                
                # Should never reach here, but for completeness
                return default_return
            
            return async_wrapper
        else:
            @functools.wraps(func)
            def sync_wrapper(*args, **kwargs) -> T:
                attempts = 0
                
                while attempts <= retry_attempts:
                    try:
                        return func(*args, **kwargs)
                    except ignore_exceptions:
                        # Let these exceptions propagate
                        raise
                    except catch_exceptions as e:
                        # Log the error with context
                        logger.log(
                            log_level,
                            f"Error in {func.__module__}.{func.__name__}: {type(e).__name__}: {e}",
                            exc_info=True,
                            extra={
                                "function": func.__name__,
                                "module": func.__module__,
                                "attempt": attempts + 1,
                                "max_attempts": retry_attempts + 1
                            }
                        )
                        
                        if attempts < retry_attempts:
                            attempts += 1
                            # For sync functions, we can't use asyncio.sleep
                            # This is a limitation - sync functions with retries should be rare
                            logger.warning(
                                f"Retry logic for sync function {func.__name__} "
                                "doesn't support delays"
                            )
                            continue
                        
                        # Max retries reached or no retries configured
                        if reraise:
                            raise
                        return default_return
                
                # Should never reach here, but for completeness
                return default_return
            
            return sync_wrapper
    
    return decorator


# Convenience decorators for common patterns

def safe_handler(func: Callable) -> Callable:
    """Decorator for event handlers that should never crash the service.
    
    Logs errors but continues execution. Perfect for WebSocket message handlers,
    event processors, and other fire-and-forget operations.
    """
    return error_boundary(
        log_level=logging.WARNING,
        reraise=False,
        default_return=None
    )(func)


def retriable_network_call(
    max_attempts: int = 3,
    base_delay: float = 1.0
) -> Callable:
    """Decorator for network operations that may fail transiently.
    
    Retries with exponential backoff. Good for API calls, database operations,
    and other network-dependent functions.
    
    Args:
        max_attempts: Total number of attempts (including first try)
        base_delay: Initial delay between retries in seconds
    """
    return error_boundary(
        retry_attempts=max_attempts - 1,  # Convert to retry count
        retry_delay=base_delay,
        reraise=False,
        default_return=None,
        catch_exceptions=(
            # Common network-related exceptions
            ConnectionError,
            TimeoutError,
            OSError,  # Covers many socket errors
            Exception,  # Catch-all for library-specific errors
        )
    )


def critical_operation(func: Callable) -> Callable:
    """Decorator for operations that should log but still raise on failure.
    
    Use this when the calling code needs to know about failures but you still
    want comprehensive logging.
    """
    return error_boundary(
        log_level=logging.ERROR,
        reraise=True
    )(func)