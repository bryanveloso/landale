"""
Service configuration for Python services
Reads from the shared services.json file
"""

import json
import os
from pathlib import Path
from typing import Any

from .logger import get_logger


logger = get_logger(__name__)


def load_services_config() -> dict[str, Any]:
    """Load the shared services configuration"""
    # Find the services.json file relative to this module
    # From apps/seed/src to packages/service-config
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


class ServiceConfig:
    """Service configuration matching the TypeScript service-config package"""

    @classmethod
    def get_service_config(cls, service: str) -> dict[str, Any]:
        """Get configuration for a service with environment overrides"""
        config = SERVICES.get(service, {}).copy()

        # Apply environment variable overrides
        env_host_key = f"{service.upper()}_HOST"
        if env_host_key in os.environ:
            config["host"] = os.environ[env_host_key]

        # Special handling for SEQ_PORT
        if service == "seq" and "SEQ_PORT" in os.environ:
            config["ports"]["http"] = int(os.environ["SEQ_PORT"])

        return config

    @classmethod
    def get_url(cls, service: str, port: str = "http") -> str:
        """Get HTTP URL for a service"""
        config = cls.get_service_config(service)
        if not config:
            raise ValueError(f"Unknown service: {service}")

        host = config.get("host", "localhost")
        port_number = config.get("ports", {}).get(port)

        if not port_number:
            raise ValueError(f"Unknown port {port} for service {service}")

        return f"http://{host}:{port_number}"

    @classmethod
    def get_websocket_url(cls, service: str, port: str = "ws") -> str:
        """Get WebSocket URL for a service"""
        url = cls.get_url(service, port)
        return url.replace("http://", "ws://")

    @classmethod
    def get_endpoint(cls, service: str, port: str = "tcp") -> tuple[str, int]:
        """Get host and port tuple for a service"""
        config = cls.get_service_config(service)
        if not config:
            raise ValueError(f"Unknown service: {service}")

        host = config.get("host", "localhost")
        port_number = config.get("ports", {}).get(port, config.get("ports", {}).get("tcp"))

        if not port_number:
            raise ValueError(f"No port found for {service}:{port}")

        return host, port_number


# Convenience functions
def get_phononmaser_url() -> str:
    """Get Phononmaser WebSocket URL"""
    return ServiceConfig.get_websocket_url("phononmaser")


def get_server_events_url() -> str:
    """Get Server events WebSocket URL"""
    return f"{ServiceConfig.get_websocket_url('server')}/events"


def get_lms_api_url() -> str:
    """Get LM Studio API URL"""
    return f"{ServiceConfig.get_url('lms', 'api')}/v1"
