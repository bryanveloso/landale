# WebSocket Resilience Implementation

## Overview

We've implemented resilient WebSocket patterns across the frontend TypeScript/SolidJS applications to match the robustness of the Python services.

## Features

### 1. Socket Class

Located at `packages/shared/src/websocket/socket.ts`, this class wraps the Phoenix Socket with:

- **Exponential Backoff with Jitter**: Prevents thundering herd on reconnection
- **Circuit Breaker Pattern**: Prevents cascading failures after multiple connection failures
- **Connection State Management**: Clear state transitions (DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, FAILED)
- **Health Monitoring**: Tracks heartbeat failures and connection metrics
- **Graceful Degradation**: Continues operating with degraded functionality when disconnected

### 2. Connection Health Metrics

```typescript
interface HealthMetrics {
  connectionState: ConnectionState
  reconnectAttempts: number
  totalReconnects: number
  failedReconnects: number
  successfulConnects: number
  heartbeatFailures: number
  circuitBreakerTrips: number
  lastHeartbeat: number
  isCircuitOpen: boolean
}
```

### 3. Updated Components

#### Overlays (`apps/overlays`)

- `src/providers/socket-provider.tsx`: Now uses Socket
- `src/components/connection-indicator.tsx`: Visual health indicator (shows in debug mode or when issues occur)
- Added debug helpers at `window.landale_socket` for testing

#### Dashboard (`apps/dashboard`)

- `src/services/stream-service.tsx`: Updated to use resilient patterns
- Health metrics available via `getHealthMetrics()`

## Configuration

Default settings (all configurable):

- Max reconnect attempts: 10
- Base reconnect delay: 1 second
- Max reconnect delay: 60 seconds (30s for overlays)
- Heartbeat interval: 30 seconds
- Circuit breaker threshold: 5 failures
- Circuit breaker timeout: 5 minutes

## Debug Features

### Browser Console Helpers

In overlays, access `window.landale_socket`:

```javascript
// Get current health metrics
window.landale_socket.getMetrics()

// Get connection state
window.landale_socket.getState()

// Force reconnection
window.landale_socket.reconnect()

// Disconnect
window.landale_socket.disconnect()
```

### Connection Indicator

Add `?debug=true` to overlay URLs to always show connection health.

## Testing

Run the test script:

```bash
bun run scripts/test-resilient-websocket.ts
```

This tests:

- Connection establishment
- Automatic reconnection
- Circuit breaker activation
- Health metric tracking

## Migration Notes

The resilient client maintains backward compatibility with Phoenix channels. Existing code using channels continues to work, but now benefits from:

- Automatic reconnection
- Better error handling
- Connection state visibility
- Health monitoring

## Next Steps

1. Add centralized monitoring dashboard to visualize WebSocket health across all services
2. Implement alert queue system for overlays
3. Add debug console functions for easier testing
