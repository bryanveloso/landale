"""Health check endpoint for phononmaser."""
from aiohttp import web
import logging
import os
import time

logger = logging.getLogger(__name__)


async def health_check(request):
    """Health check endpoint."""
    return web.json_response({
        "status": "healthy",
        "service": "phononmaser",
        "timestamp": int(request.app["start_time"])
    })


async def create_health_app(port: int = 8890):
    """Create health check web app."""
    app = web.Application()
    app["start_time"] = int(time.time() * 1000)
    app.router.add_get("/health", health_check)
    
    runner = web.AppRunner(app)
    await runner.setup()
    host = os.getenv("PHONONMASER_HOST", "0.0.0.0")
    site = web.TCPSite(runner, host, port)
    await site.start()
    
    logger.info(f"Health check endpoint available at http://{host}:{port}/health")
    return runner