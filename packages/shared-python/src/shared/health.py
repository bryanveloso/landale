"""Shared health endpoint utilities for Landale services."""

import time
from typing import TYPE_CHECKING

from aiohttp import web

from .logger import get_logger

if TYPE_CHECKING:
    pass

logger = get_logger(__name__)


class HealthRunner:
    """Health endpoint runner with proper cleanup."""

    def __init__(self, runner: web.AppRunner, site: web.TCPSite):
        self.runner = runner
        self.site = site

    async def cleanup(self):
        """Clean up both site and runner."""
        try:
            # Stop the TCP site first
            await self.site.stop()
        except Exception as e:
            logger.warning(f"Site stop error (non-critical): {e}")

        try:
            # Clean up the runner
            await self.runner.cleanup()
        except Exception as e:
            logger.warning(f"Runner cleanup error (non-critical): {e}")


async def create_basic_health_app(port: int, service_name: str, host: str = None, additional_data: dict = None):
    """Create basic health check web app with proper cleanup."""

    async def health_check(request):
        """Basic health check endpoint."""
        app = request.app

        health_data = {
            "status": "healthy",
            "service": service_name,
            "timestamp": int(time.time()),
            "uptime_seconds": int(time.monotonic() - app["start_time"]),
        }

        # Add additional data if provided
        if additional_data:
            health_data.update(additional_data)

        return web.json_response(health_data)

    app = web.Application()
    app["start_time"] = time.monotonic()
    app.router.add_get("/health", health_check)

    # Disable access logging to prevent broken pipe errors when managed by Nurvus
    runner = web.AppRunner(app, access_log=None)
    await runner.setup()

    if host is None:
        host = "0.0.0.0"

    site = web.TCPSite(runner, host, port)
    await site.start()

    logger.info(f"Health check endpoint available at http://{host}:{port}/health")
    return HealthRunner(runner, site)
