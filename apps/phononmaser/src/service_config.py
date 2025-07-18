"""
Service configuration for Python services
Reads from the shared services.json file
"""

import json
import os
from pathlib import Path

from .logger import get_logger

logger = get_logger(__name__)


def load_services_config():
    """Load the shared services configuration"""
    # Find the services.json file relative to this module
    # From apps/phononmaser/src to packages/service-config
    config_path = Path(__file__).parent.parent.parent.parent / "packages" / "service-config" / "services.json"

    try:
        with open(config_path) as f:
            config = json.load(f)
            return config["services"]
    except Exception as e:
        logger.warning("Could not load services.json", error=str(e))
        return {}


# Load configuration once at module import
SERVICES = load_services_config()


def get_service_host(service: str) -> str:
    """Get the host for a service with environment override"""
    env_key = f"{service.upper()}_HOST"
    return os.getenv(env_key, SERVICES.get(service, {}).get("host", "localhost"))


def get_service_port(service: str, port_type: str = "http") -> int:
    """Get the port for a service"""
    default_port = SERVICES.get(service, {}).get("ports", {}).get(port_type, 0)

    # Special handling for SEQ_PORT environment variable
    if service == "seq" and port_type == "http":
        return int(os.getenv("SEQ_PORT", str(default_port)))

    return default_port


def get_server_url() -> str:
    """Get the main server WebSocket URL"""
    host = get_service_host("server")
    port = get_service_port("server", "ws")
    return f"ws://{host}:{port}/events"


def get_phononmaser_port() -> int:
    """Get the Phononmaser WebSocket port"""
    # Check environment variable first, then fall back to service config
    port = os.getenv("PORT")
    if port:
        return int(port)
    return get_service_port("phononmaser", "ws") or 8889


def get_phononmaser_health_port() -> int:
    """Get the Phononmaser health check port"""
    # Check environment variable first, then fall back to service config
    port = os.getenv("HEALTH_PORT")
    if port:
        return int(port)
    return get_service_port("phononmaser", "health") or 8890


def get_host() -> str:
    """Get the host to bind to"""
    return os.getenv("PHONONMASER_BIND_HOST", "0.0.0.0")
