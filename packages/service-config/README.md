# @landale/service-config

Centralized service configuration using Tailscale hostnames.

## Usage

```typescript
import { services } from '@landale/service-config'

// Get a service URL
const serverUrl = services.getUrl('server')  // http://saya:7175

// Get WebSocket URL
const wsUrl = services.getWebSocketUrl('phononmaser')  // ws://zelan:8889

// Check if service is reachable
const isHealthy = await services.healthCheck('server')
```

## Configuration

All services are defined in `services.json`:

```json
{
  "server": {
    "host": "saya",
    "ports": {
      "http": 7175,
      "ws": 7175,
      "tcp": 8080
    }
  },
  "phononmaser": {
    "host": "zelan",
    "ports": {
      "ws": 8889,
      "health": 8890
    }
  }
}
```

## Environment Variables

```bash
# Override any service host if needed
SERVER_HOST=saya-backup  # Override default host
```