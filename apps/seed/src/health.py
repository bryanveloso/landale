"""Simple HTTP health check endpoint."""

import os
import time

from aiohttp import web

from .logger import get_logger

logger = get_logger(__name__)


async def health_check(request):
    """Health check endpoint."""
    return web.json_response(
        {"status": "healthy", "service": "landale-seed", "timestamp": int(request.app["start_time"])}
    )


async def create_health_app(port: int = 8891):
    """Create health check web app."""
    app = web.Application()
    app["start_time"] = int(time.time())
    app.router.add_get("/health", health_check)

    runner = web.AppRunner(app)
    await runner.setup()
    host = os.getenv("SEED_HOST", "0.0.0.0")
    site = web.TCPSite(runner, host, port)
    await site.start()

    logger.info(f"Health check endpoint available at http://{host}:{port}/health")
    return runner
