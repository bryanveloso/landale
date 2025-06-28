# Service Configuration

Single source of truth for all service locations in the Landale monorepo.

## How it works

1. **services.json** - Contains all service hosts and ports
2. **TypeScript** - Reads the JSON file and provides typed access
3. **Python** - Reads the same JSON file for consistency
4. **Environment variables** - Override any host or port when needed

## Usage

### TypeScript

```typescript
import { SERVICE_CONFIG, services } from '@landale/service-config'

// Get a WebSocket URL
const obsUrl = services.getWebSocketUrl('obs')  // ws://demi:4455

// Get an HTTP URL
const serverUrl = services.getUrl('server')  // http://saya:7175

// Get raw config
const obsConfig = SERVICE_CONFIG.obs  // { host: 'demi', ports: { ws: 4455 } }
```

### Python

```python
# For analysis service
from service_config import ServiceConfig

obs_url = ServiceConfig.get_websocket_url('obs')  # ws://demi:4455
server_url = ServiceConfig.get_url('server')  # http://saya:7175

# For phononmaser
from service_config import get_server_url, get_phononmaser_port

server_events = get_server_url()  # ws://saya:7175/events
port = get_phononmaser_port()  # 8889
```

## Environment Overrides

Override any service host with environment variables:

```bash
# Override service hosts
export OBS_HOST=different-machine
export SERVER_HOST=192.168.1.100
export PHONONMASER_HOST=zelan.tail-scale.ts.net

# Special case: Seq port
export SEQ_PORT=5342
```

## Adding a New Service

1. Edit `services.json` to add your service:
```json
{
  "services": {
    "myservice": {
      "host": "saya",
      "ports": {
        "http": 3000,
        "ws": 3001
      }
    }
  }
}
```

2. Use it in TypeScript:
```typescript
const url = services.getUrl('myservice')
```

3. Use it in Python:
```python
url = ServiceConfig.get_url('myservice')
```

## Benefits

- **Single source of truth** - One file defines all service locations
- **Type safety** - TypeScript knows all valid services
- **Simple overrides** - Environment variables for deployment flexibility
- **No external dependencies** - No OAuth, no API calls, just JSON
- **Works offline** - No network required to start services
- **Version controlled** - See exactly when service locations changed