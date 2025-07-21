"""
Service configuration for Python services.
Migrated to environment-based configuration.
"""

from shared.config import PhononmaserConfig

# Create a singleton config instance
_config = PhononmaserConfig()


# Expose functions for backward compatibility
def get_service_host(service: str) -> str:
    """Get the host for a service."""
    if service == "server":
        return _config.server_host
    return "localhost"


def get_service_port(service: str, port_type: str = "http") -> int:
    """Get the port for a service."""
    if service == "server":
        if port_type == "ws":
            return _config.server_ws_port
        elif port_type == "tcp" or port_type == "http":
            return _config.server_tcp_port
    return 0


def get_server_url() -> str:
    """Get the main server WebSocket URL."""
    return _config.server_events_url


def get_phononmaser_port() -> int:
    """Get the Phononmaser WebSocket port."""
    return _config.port


def get_phononmaser_health_port() -> int:
    """Get the Phononmaser health check port."""
    return _config.health_port


def get_host() -> str:
    """Get the host to bind to."""
    return _config.bind_host
