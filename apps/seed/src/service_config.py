"""
Service configuration for Python services.
Migrated to environment-based configuration.
"""

from typing import Any

from shared.config import SeedConfig

# Create a singleton config instance
_config = SeedConfig()


class ServiceConfig:
    """Service configuration matching the TypeScript service-config package."""

    @classmethod
    def get_service_config(cls, service: str) -> dict[str, Any]:
        """Get configuration for a service with environment overrides."""
        service_configs = {
            "server": {
                "host": _config.server_host,
                "ports": {
                    "ws": _config.server_ws_port,
                    "tcp": _config.server_tcp_port,
                },
            },
            "phononmaser": {
                "host": _config.phononmaser_host,
                "ports": {
                    "ws": _config.phononmaser_port,
                },
            },
            "lms": {
                "host": _config.lms_host,
                "ports": {
                    "api": _config.lms_port,
                },
            },
        }
        return service_configs.get(service, {})

    @classmethod
    def get_url(cls, service: str, port: str = "http") -> str:
        """Get HTTP URL for a service."""
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
        """Get WebSocket URL for a service."""
        url = cls.get_url(service, port)
        return url.replace("http://", "ws://")

    @classmethod
    def get_endpoint(cls, service: str, port: str = "tcp") -> tuple[str, int]:
        """Get host and port tuple for a service."""
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
    """Get Phononmaser WebSocket URL."""
    return _config.phononmaser_url


def get_server_events_url() -> str:
    """Get Server events WebSocket URL."""
    return _config.server_events_url


def get_lms_api_url() -> str:
    """Get LM Studio API URL."""
    return _config.lms_api_url
