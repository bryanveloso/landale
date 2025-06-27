"""Simple HTTP health check endpoint."""
from aiohttp import web
import logging
import time

logger = logging.getLogger(__name__)


async def health_check(request):
    """Health check endpoint."""
    return web.json_response({
        "status": "healthy",
        "service": "landale-analysis",
        "timestamp": int(request.app["start_time"])
    })


async def create_health_app(port: int = 8891):
    """Create health check web app."""
    app = web.Application()
    app["start_time"] = int(time.time())
    app.router.add_get("/health", health_check)
    
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "localhost", port)
    await site.start()
    
    logger.info(f"Health check endpoint available at http://localhost:{port}/health")
    return runner