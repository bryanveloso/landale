"""Health check endpoint for phononmaser."""

import os
import time

from aiohttp import web

from .logger import get_logger

logger = get_logger(__name__)


async def health_check(request):
    """Health check endpoint."""
    app = request.app

    health_data = {
        "status": "healthy",
        "service": "phononmaser",
        "timestamp": int(time.time()),
        "uptime_seconds": int(time.monotonic() - app["start_time"]),
    }

    # Add WebSocket connection status if available
    if "websocket_client" in app and app["websocket_client"]:
        client = app["websocket_client"]
        if hasattr(client, "get_status"):
            ws_status = client.get_status()
            health_data["websocket"] = {
                "connected": ws_status.get("connected", False),
                "state": ws_status.get("connection_state", "unknown"),
                "reconnect_attempts": ws_status.get("reconnect_attempts", 0),
                "circuit_breaker_trips": ws_status.get("circuit_breaker_trips", 0),
            }

            # Update overall health status if WebSocket is disconnected
            if not ws_status.get("connected", False):
                health_data["status"] = "degraded"
                health_data["message"] = "WebSocket connection to Phoenix server is down"

    return web.json_response(health_data)


async def create_health_app(port: int = 8890, websocket_client=None):
    """Create health check web app."""
    app = web.Application()
    app["start_time"] = time.monotonic()
    app["websocket_client"] = websocket_client
    app.router.add_get("/health", health_check)

    runner = web.AppRunner(app)
    await runner.setup()
    host = os.getenv("PHONONMASER_HOST", "0.0.0.0")
    site = web.TCPSite(runner, host, port)
    await site.start()

    logger.info(f"Health check endpoint available at http://{host}:{port}/health")
    return runner
