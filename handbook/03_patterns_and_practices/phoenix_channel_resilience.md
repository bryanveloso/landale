# Phoenix Channel Resilience Patterns

> Important for future you - how WebSocket communication actually works in this system

## Problem Solved

Phoenix channels provide our real-time WebSocket communication between Elixir server and frontend clients. They include automatic reconnection, message queuing, and error handling that works reliably.

## Connection Pattern

```typescript
import { Socket } from 'phoenix'

// Standard connection with exponential backoff
const socket = new Socket('ws://localhost:7175/socket', {
  reconnectAfterMs: (tries: number) => Math.min(1000 * Math.pow(2, tries), 30000)
})

socket.connect()

// Join a channel with error handling
const channel = socket.channel('overlay:obs')
channel.join()
  .receive('ok', () => console.log('Connected'))
  .receive('error', (error) => console.error('Failed to join:', error))
```

## Channel Architecture

Our channels are organized by purpose:

### `overlay:*` - Data Consumption
- **Purpose**: Read-only streams for overlays
- **Topics**: `overlay:obs`, `overlay:twitch`, `overlay:ironmon`, `overlay:system`
- **Pattern**: Request/response + automatic event broadcasting

### `stream:*` - Content Coordination  
- **Purpose**: Priority-based omnibar coordination
- **Topics**: `stream:overlays`, `stream:queue`
- **Pattern**: State management + real-time updates

### `dashboard:*` - Control Interface
- **Purpose**: Dashboard controls and status
- **Topics**: `dashboard:{room_id}`
- **Pattern**: Command/response + status broadcasting

## Key Commands by Channel

### OBS Channel (`overlay:obs`)

```typescript
// Get current status
channel.push('obs:status', {})
  .receive('ok', (response) => {
    // { connected: boolean, streaming: boolean, recording: boolean }
  })

// Get scene information
channel.push('obs:scenes', {})
  .receive('ok', (response) => {
    console.log('Current Scene:', response.currentProgramSceneName)
  })
```

### Stream Coordination (`stream:overlays`)

```typescript
// Get overlay state
streamChannel.push('request_state', {})

// Force content (for takeovers)
streamChannel.push('force_content', {
  type: 'technical-difficulties',
  data: { message: 'Stream will return shortly' },
  duration: 30000
})
```

### System Health (`overlay:system`)

```typescript
// Monitor overall health
systemChannel.push('system:status', {})
  .receive('ok', (status) => {
    console.log(`Health: ${status.summary.health_percentage}%`)
  })
```

## Event Handling Patterns

### Standard Event Listeners

```typescript
// OBS events (scene changes, streaming status)
channel.on('obs_event', (event) => {
  console.log('OBS Event:', event.type, event.data)
})

// Stream state changes
streamChannel.on('stream_state', (state) => {
  console.log('Current Show:', state.current_show)
  console.log('Active Content:', state.active_content)
})

// Health monitoring
channel.on('health_update', (data) => {
  updateHealthIndicator(data)
})
```

### Connection Health Monitoring

```typescript
// Ping/pong for connection health
setInterval(() => {
  channel.push('ping', { timestamp: Date.now() })
    .receive('ok', (response) => {
      console.log('Connection healthy:', response.timestamp)
    })
}, 30000)
```

## Error Handling

Consistent error format across all channels:

```typescript
channel.push('some:command', {})
  .receive('error', (error) => {
    console.error('Command failed:', error.message)
    // Error format: { message: string }
  })
```

## Common Setup Pattern

This is the reliable way to set up any overlay:

```typescript
// 1. Create channel
const overlayChannel = socket.channel('overlay:obs')

// 2. Join with error handling
overlayChannel.join()
  .receive('ok', () => {
    // 3. Get initial state
    overlayChannel.push('obs:status', {})
  })
  .receive('error', (error) => {
    console.error('Failed to join overlay channel:', error)
  })

// 4. Set up event listeners
overlayChannel.on('obs_event', (event) => {
  updateOverlayDisplay(event)
})

overlayChannel.on('initial_state', (state) => {
  initializeOverlay(state.data)
})
```

## Environment Configuration

- **Development**: `ws://localhost:7175/socket`
- **Production**: `ws://zelan:7175/socket`

## Data Format Standards

All responses follow this structure:

```typescript
// Success response - varies by command
{ /* command-specific data */ }

// Error response - consistent format
{ message: string }

// Event format - consistent structure
{
  type: string,      // Event identifier
  data: object,      // Event-specific payload
  timestamp?: number // Optional timestamp
}
```

## Why This Works

- **Automatic reconnection** with exponential backoff prevents connection spam
- **Message queuing** during reconnection prevents lost commands
- **Consistent error handling** makes debugging straightforward
- **Event broadcasting** keeps all clients in sync automatically

## Code Locations

- **Socket provider**: `apps/overlays/src/providers/socket-provider.tsx`
- **Channel hooks**: `apps/overlays/src/hooks/use-*-channel.tsx`  
- **Server channels**: `apps/server/lib/server_web/channels/`

---

*This pattern is battle-tested and should not be changed lightly. Phoenix handles the hard parts of WebSocket resilience for us.*