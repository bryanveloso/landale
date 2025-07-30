# Phoenix Channels Data Consumption Guide

> Real-time data streams for Landale overlays and dashboard

## Overview

Phoenix channels provide real-time WebSocket communication between the Elixir server and frontend clients (overlays, dashboard). All channels use Phoenix.js for JavaScript clients and include automatic reconnection, message queuing, and error handling.

## Connection Setup

```typescript
import { Socket } from 'phoenix'

// Connect to WebSocket endpoint
const socket = new Socket('ws://localhost:7175/socket', {
  reconnectAfterMs: (tries: number) => Math.min(1000 * Math.pow(2, tries), 30000)
})

socket.connect()

// Join a channel
const channel = socket.channel('overlay:obs')
channel
  .join()
  .receive('ok', () => console.log('Connected to OBS overlay'))
  .receive('error', (error) => console.error('Failed to join:', error))
```

## Available Channels

### 1. `overlay:*` - Overlay Data Streams

**Purpose**: Read-only data consumption for streaming overlays  
**Topics**: `overlay:obs`, `overlay:twitch`, `overlay:ironmon`, `overlay:music`, `overlay:system`

#### Commands (Request/Response)

##### OBS Commands

- `obs:status` - Current OBS connection and streaming status
- `obs:scenes` - Scene list and current scene
- `obs:stream_status` - Streaming status (bitrate, duration, frames)
- `obs:record_status` - Recording status and file info
- `obs:stats` - Performance metrics (CPU, memory, FPS)
- `obs:version` - OBS version information
- `obs:virtual_cam` - Virtual camera status
- `obs:outputs` - Output configurations

```typescript
// Get OBS status
channel.push('obs:status', {}).receive('ok', (response) => {
  console.log('OBS Status:', response)
  // Response: { connected: boolean, streaming: boolean, recording: boolean, ... }
})

// Get current scene
channel.push('obs:scenes', {}).receive('ok', (response) => {
  console.log('Current Scene:', response.currentProgramSceneName)
  console.log('Available Scenes:', response.scenes)
})
```

##### Twitch Commands

- `twitch:status` - EventSub connection status and subscription health

```typescript
channel.push('twitch:status', {}).receive('ok', (response) => {
  console.log('Twitch Status:', response)
  // Response: { connected: boolean, subscriptions: {...}, webhook_url: string }
})
```

##### IronMON Commands

- `ironmon:challenges` - List available challenges
- `ironmon:checkpoints` - Get checkpoints for a challenge (requires `challenge_id`)
- `ironmon:checkpoint_stats` - Get statistics for a checkpoint (requires `checkpoint_id`)
- `ironmon:recent_results` - Get recent run results (optional `limit` 1-100, default 10)
- `ironmon:active_challenge` - Get current active challenge (requires `seed_id`)

```typescript
// Get challenges list
channel.push('ironmon:challenges', {}).receive('ok', (challenges) => console.log(challenges))

// Get checkpoints for challenge ID 1
channel.push('ironmon:checkpoints', { challenge_id: 1 }).receive('ok', (checkpoints) => console.log(checkpoints))

// Get recent results (last 10)
channel.push('ironmon:recent_results', { limit: 10 }).receive('ok', (results) => console.log(results))
```

##### Music Commands

- `rainwave:status` - Current music status and station info

##### System Commands

- `system:status` - Overall system health and service status
- `system:services` - Detailed service information

```typescript
// Get system health overview
channel.push('system:status', {}).receive('ok', (status) => {
  console.log('System Health:', status.summary.health_percentage)
  console.log('Services:', status.services)
})
```

#### Events (Server → Client)

All overlay channels automatically receive relevant events:

```typescript
// OBS events
channel.on('obs_event', (event) => {
  console.log('OBS Event:', event.type, event.data)
})

// Twitch events (follows, subs, cheers, etc.)
channel.on('twitch_event', (event) => {
  console.log('Twitch Event:', event.type, event.data)
})

// IronMON run updates
channel.on('ironmon_event', (event) => {
  console.log('IronMON Event:', event.type, event.data)
})

// Music changes
channel.on('music_event', (event) => {
  console.log('Music Event:', event.type, event.data)
})

// System health updates
channel.on('health_update', (data) => {
  console.log('Health Update:', data)
})

// Initial state on connection
channel.on('initial_state', (state) => {
  console.log('Initial State:', state.type, state.data)
})
```

### 2. `stream:*` - Overlay Coordination

**Purpose**: Priority-based content coordination for omnibar and overlay layers  
**Topics**: `stream:overlays`, `stream:queue`

#### Commands

##### State Management

- `ping` - Connection health check
- `request_state` - Get current overlay state
- `request_queue_state` - Get current queue state

##### Queue Management

- `remove_queue_item` - Remove item from queue (requires `id`)
- `force_content` - Force takeover content (requires `type`, `data`, `duration`)

```typescript
const streamChannel = socket.channel('stream:overlays')

// Get current overlay state
streamChannel.push('request_state', {})

// Remove queue item
streamChannel
  .push('remove_queue_item', { id: 'alert_123' })
  .receive('ok', (response) => console.log('Item removed:', response))

// Force takeover content
streamChannel.push('force_content', {
  type: 'technical-difficulties',
  data: { message: 'Stream will return shortly' },
  duration: 30000 // 30 seconds
})
```

#### Events

```typescript
// Stream state updates
streamChannel.on('stream_state', (state) => {
  console.log('Current Show:', state.current_show)
  console.log('Active Content:', state.active_content)
  console.log('Priority Level:', state.priority_level)
})

// Queue state updates
streamChannel.on('queue_state', (queue) => {
  console.log('Queue Items:', queue.queue)
  console.log('Active Content:', queue.active_content)
  console.log('Processing:', queue.is_processing)
})
```

### 3. `dashboard:*` - Dashboard Communication

**Purpose**: Real-time dashboard updates and control commands  
**Topics**: `dashboard:{room_id}`

#### Available Commands

##### OBS Control

- `obs:get_status` - Request current OBS status
- `obs:start_streaming` - Start streaming
- `obs:stop_streaming` - Stop streaming
- `obs:start_recording` - Start recording
- `obs:stop_recording` - Stop recording
- `obs:set_current_scene` - Change scene (requires `scene_name`)

##### Rainwave Control

- `rainwave:get_status` - Get music service status
- `rainwave:set_enabled` - Enable/disable service (requires `enabled: boolean`)
- `rainwave:set_station` - Change station (requires `station_id`)

```typescript
const dashboardChannel = socket.channel('dashboard:main')

// Start streaming
dashboardChannel
  .push('obs:start_streaming', {})
  .receive('ok', () => console.log('Streaming started'))
  .receive('error', (error) => console.error('Failed to start:', error))

// Change OBS scene
dashboardChannel.push('obs:set_current_scene', { scene_name: 'Coding Scene' })
```

#### Events

```typescript
// Real-time OBS updates
dashboardChannel.on('obs_event', (event) => {
  if (event.type === 'streaming_started') {
    console.log('Stream is now live!')
  }
})

// System health updates
dashboardChannel.on('health_update', (data) => {
  console.log('System Health:', data)
})

// Performance metrics
dashboardChannel.on('performance_update', (data) => {
  console.log('Performance:', data)
})

// Music service updates
dashboardChannel.on('rainwave_event', (event) => {
  console.log('Music Event:', event)
})

// Initial connection state
dashboardChannel.on('initial_state', (state) => {
  console.log('Dashboard connected:', state)
})
```

### 4. `events:*` - Event Broadcasting

**Purpose**: General event distribution and logging  
**Topics**: `events:general`

Real-time event stream for activity logging and debugging.

### 5. `transcription:*` - Audio Transcription

**Purpose**: Real-time audio transcription from phononmaser service  
**Topics**: `transcription:live`

Real-time transcription updates for speech-to-text overlays.

## Error Handling

All channels use consistent error response format:

```typescript
channel.push('some:command', {}).receive('error', (error) => {
  console.error('Command failed:', error.message)
  // Error object: { message: string }
})
```

## Connection Health

Use ping/pong for connection monitoring:

```typescript
// Send ping every 30 seconds
setInterval(() => {
  channel.push('ping', { timestamp: Date.now() }).receive('ok', (response) => {
    console.log('Pong received:', response.timestamp)
  })
}, 30000)
```

## Common Patterns

### Overlay State Management

```typescript
// Typical overlay setup
const overlayChannel = socket.channel('overlay:obs')

// 1. Join channel
overlayChannel.join().receive('ok', () => {
  // 2. Get initial state
  overlayChannel.push('obs:status', {})
})

// 3. Listen for real-time updates
overlayChannel.on('obs_event', (event) => {
  updateOverlayDisplay(event)
})

// 4. Listen for initial state
overlayChannel.on('initial_state', (state) => {
  initializeOverlay(state.data)
})
```

### Service Health Monitoring

```typescript
const systemChannel = socket.channel('overlay:system')

systemChannel.join().receive('ok', () => {
  // Get overall system status
  systemChannel.push('system:status', {}).receive('ok', (status) => {
    console.log(`System Health: ${status.summary.health_percentage}%`)
    console.log(`Services: ${status.summary.healthy_services}/${status.summary.total_services}`)
  })
})

// Monitor health changes
systemChannel.on('health_update', (data) => {
  updateHealthIndicator(data)
})
```

### Queue Management

```typescript
const queueChannel = socket.channel('stream:queue')

// Monitor queue state
queueChannel.on('queue_state', (queue) => {
  updateQueueDisplay(queue.queue)
  showActiveContent(queue.active_content)
})

// Remove items from queue
function removeQueueItem(itemId) {
  queueChannel
    .push('remove_queue_item', { id: itemId })
    .receive('ok', () => console.log('Item removed'))
    .receive('error', (error) => console.error('Remove failed:', error))
}
```

## WebSocket URL Configuration

- **Development**: `ws://localhost:7175/socket`
- **Production**: `ws://zelan:7175/socket` (or your server hostname)

## Data Formats

All responses follow consistent JSON structure:

```typescript
// Success response
{
  // Response data varies by command
}

// Error response
{
  message: string  // Human-readable error message
}

// Event format
{
  type: string,    // Event type identifier
  data: object,    // Event-specific data
  timestamp?: number
}
```

This guide covers the complete Phoenix channels API for consuming real-time data in Landale overlays and dashboard components.
