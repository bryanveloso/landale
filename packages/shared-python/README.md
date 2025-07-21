# Shared Python

Shared utilities and base classes for Landale Python services.

## Installation

From the monorepo root:

```bash
cd packages/shared-python
uv pip install -e .
```

## Components

- **config**: Simple configuration for personal use
- **websockets**: Base WebSocket client with automatic reconnection
- **tasks**: Background task management utilities
- **utils**: Common utilities

## Usage

```python
from shared.config import get_config
from shared.websockets import BaseWebSocketClient

# Get service-specific configuration
config = get_config("phononmaser")
```

## Configuration

Most settings are fixed for personal use. Only these are configurable:

- `SERVER_HOST` - Phoenix server hostname (default: localhost)
- `LOG_LEVEL` - Logging level (default: INFO)
- `LMS_HOST` - LM Studio host (default: localhost)
- `LMS_MODEL` - LM Studio model (default: local-model)
