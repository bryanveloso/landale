"""Simple HTTP health check endpoint."""

import os
import time
from typing import TYPE_CHECKING

from aiohttp import web

from .logger import get_logger

if TYPE_CHECKING:
    from .correlator import StreamCorrelator

logger = get_logger(__name__)


async def health_check(request):
    """Health check endpoint."""
    app = request.app

    # Basic health info
    health_data = {
        "status": "healthy",
        "service": "landale-seed",
        "uptime_seconds": int(time.monotonic() - app["start_time"]),
        "timestamp": int(time.time()),
    }

    # Add buffer stats if correlator is available
    if "correlator" in app and app["correlator"]:
        try:
            buffer_stats = app["correlator"].get_buffer_stats()
            health_data["buffers"] = buffer_stats

            # Check if buffers are near capacity
            buffer_warnings = []
            for buffer_type, size in buffer_stats["buffer_sizes"].items():
                limit = buffer_stats["buffer_limits"][buffer_type]
                if size >= limit * 0.8:  # 80% full
                    buffer_warnings.append(f"{buffer_type} buffer at {size}/{limit}")

            if buffer_warnings:
                health_data["warnings"] = buffer_warnings
                health_data["status"] = "warning"
        except Exception as e:
            logger.error(f"Failed to get buffer stats: {e}")
            health_data["buffer_error"] = str(e)

    # Add connection status if available
    if "connections" in app:
        health_data["connections"] = app["connections"]

    return web.json_response(health_data)


async def detailed_status(request):
    """Detailed status endpoint with component health."""
    app = request.app

    status = {
        "service": "landale-seed",
        "version": "0.1.0",
        "uptime_seconds": int(time.monotonic() - app["start_time"]),
        "timestamp": int(time.time()),
        "components": {},
    }

    # Check each component
    if "service" in app and app["service"]:
        service = app["service"]

        # Transcription client status
        if hasattr(service.transcription_client, "get_status"):
            trans_status = service.transcription_client.get_status()
            status["components"]["transcription_client"] = {
                "connected": trans_status.get("connected", False),
                "state": trans_status.get("connection_state", "unknown"),
                "url": trans_status.get("url", "unknown"),
                "reconnect_attempts": trans_status.get("reconnect_attempts", 0),
                "circuit_breaker_trips": trans_status.get("circuit_breaker_trips", 0),
            }
        else:
            status["components"]["transcription_client"] = {
                "connected": service.transcription_client.is_connected
                if hasattr(service.transcription_client, "is_connected")
                else False,
                "url": service.transcription_client.url if hasattr(service.transcription_client, "url") else "unknown",
            }

        # Server client status
        if hasattr(service.server_client, "get_status"):
            server_status = service.server_client.get_status()
            status["components"]["server_client"] = {
                "connected": server_status.get("connected", False),
                "state": server_status.get("connection_state", "unknown"),
                "url": server_status.get("url", "unknown"),
                "reconnect_attempts": server_status.get("reconnect_attempts", 0),
                "circuit_breaker_trips": server_status.get("circuit_breaker_trips", 0),
            }
        else:
            status["components"]["server_client"] = {
                "connected": service.server_client.connected if hasattr(service.server_client, "connected") else False,
                "url": service.server_client.url if hasattr(service.server_client, "url") else "unknown",
            }

        # LMS client status
        lms_status = {
            "available": service.lms_client.session is not None if hasattr(service.lms_client, "session") else False,
            "url": service.lms_client.api_url if hasattr(service.lms_client, "api_url") else "unknown",
            "model": service.lms_client.model if hasattr(service.lms_client, "model") else "unknown",
        }

        # Add circuit breaker stats
        if hasattr(service.lms_client, "get_circuit_stats"):
            try:
                circuit_stats = service.lms_client.get_circuit_stats()
                lms_status["circuit_breaker"] = circuit_stats

                # Warn if circuit is open
                if circuit_stats.get("state") == "open":
                    lms_status["warning"] = "Circuit breaker is OPEN - LMS calls are being rejected"
            except Exception as e:
                lms_status["circuit_error"] = str(e)

        status["components"]["lms_client"] = lms_status

        # Context client status
        status["components"]["context_client"] = {
            "available": service.context_client.session is not None
            if hasattr(service.context_client, "session")
            else False,
            "url": service.context_client.base_url if hasattr(service.context_client, "base_url") else "unknown",
        }

    # Add correlator stats if available
    if "correlator" in app and app["correlator"]:
        try:
            buffer_stats = app["correlator"].get_buffer_stats()
            status["correlator"] = buffer_stats
        except Exception as e:
            status["correlator"] = {"error": str(e)}

    # Determine overall health
    all_healthy = all(
        component.get("connected", True) or component.get("available", True)
        for component in status["components"].values()
    )
    status["overall_status"] = "healthy" if all_healthy else "degraded"

    return web.json_response(status)


async def create_health_app(
    port: int = 8891, service=None, correlator: "StreamCorrelator | None" = None, rag_handler=None
):
    """Create health check web app."""
    app = web.Application()
    app["start_time"] = time.monotonic()
    app["service"] = service
    app["correlator"] = correlator
    app["connections"] = {}

    # Add routes
    app.router.add_get("/health", health_check)
    app.router.add_get("/status", detailed_status)

    # Add RAG endpoints if handler provided
    if rag_handler:
        from .rag_handler import create_rag_endpoints

        await create_rag_endpoints(app, rag_handler)

    # Disable access logging to prevent broken pipe errors when managed by Nurvus
    runner = web.AppRunner(app, access_log=None)
    await runner.setup()
    host = os.getenv("SEED_HOST", "0.0.0.0")
    site = web.TCPSite(runner, host, port)
    await site.start()

    logger.info(f"Health check endpoints available at http://{host}:{port}/health and /status")
    return runner
