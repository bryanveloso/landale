# Async Operation Lifecycle Patterns

> How we properly manage timers, WebSockets, and cleanup to prevent memory leaks

## Problem Solved

Async operations (timers, WebSocket connections, promises) that continue running after component unmount or service shutdown cause memory leaks and unpredictable behavior. This documents the patterns that actually work in our codebase.

## Timer Management Pattern

**From `takeover.tsx` - the reference implementation:**

```typescript
let hideTimer: ReturnType<typeof setTimeout> | null = null

// Setting timer with cleanup of previous timer
if (payload.duration) {
  if (hideTimer) clearTimeout(hideTimer) // Clear existing timer first
  hideTimer = setTimeout(() => {
    hideTakeover()
  }, payload.duration)
}

// Component cleanup
onCleanup(() => {
  if (hideTimer) {
    clearTimeout(hideTimer) // Clean up on unmount
    hideTimer = null // Clear reference for GC
  }
})
```

**Key principles:**

- Store timer references with proper TypeScript typing
- Clear existing timers before setting new ones (prevents accumulation)
- Always clean up in `onCleanup()` for SolidJS components
- Null the reference after clearing for garbage collection

## Phoenix WebSocket Management

**Channel lifecycle pattern from `use-stream-channel.tsx`:**

```typescript
let channel: Channel | null = null

const joinChannel = () => {
  channel = currentSocket.channel('stream:overlays', {})
  // Set up event handlers
  channel.join()
}

const leaveChannel = () => {
  if (channel) {
    channel.leave() // Cancels all pending operations automatically
    channel = null
  }
}

// Automatic cleanup
onCleanup(() => {
  leaveChannel()
})
```

**Phoenix benefits:**

- `channel.leave()` automatically cancels all pending channel operations
- Phoenix handles reconnection and queuing during disconnects
- Socket disconnection automatically cleans up all associated channels

## Socket-Level Management

**From `socket-provider.tsx`:**

```typescript
onCleanup(() => {
  const currentSocket = socket()
  if (currentSocket) {
    currentSocket.disconnect() // Closes socket and ALL channels
  }
})
```

## SolidJS Reactive Effects

**Connection state management:**

```typescript
createEffect(() => {
  const connected = isConnected()
  if (connected && !channel) {
    joinChannel()
  } else if (!connected && channel) {
    leaveChannel() // Clean up when disconnected
  }
})
```

**Key principles:**

- Use `createEffect()` to reactively manage async operations
- Always provide cleanup logic for state changes
- Handle both connection and disconnection scenarios

## Architecture Benefits

Our WebSocket-first architecture provides inherent cancellation benefits:

- **No HTTP `fetch` calls** that could continue after component unmount
- **Automatic cleanup** when WebSocket connections terminate
- **Built-in lifecycle management** through Phoenix Channel protocol
- **Memory-safe operations** that don't outlive their components

## Audit Results (2025-07-22)

Comprehensive codebase audit found excellent async management:

- **Timers**: Only 1 production usage, properly managed in `takeover.tsx`
- **HTTP Requests**: None found - all communication via WebSocket
- **Phoenix Operations**: All properly managed with cleanup in `onCleanup()`
- **Background Tasks**: None found that could outlive components

**Conclusion**: No async operation memory leaks or orphaned operations identified.

## Development Guidelines

When adding new async operations:

### For Timers

Follow the `takeover.tsx` pattern:

```typescript
let timer: ReturnType<typeof setTimeout> | null = null

// Clear existing, set new
if (timer) clearTimeout(timer)
timer = setTimeout(callback, delay)

// Cleanup
onCleanup(() => {
  if (timer) {
    clearTimeout(timer)
    timer = null
  }
})
```

### For Phoenix Channels

Follow the `use-stream-channel.tsx` pattern:

```typescript
let channel: Channel | null = null

const cleanup = () => {
  if (channel) {
    channel.leave()
    channel = null
  }
}

onCleanup(cleanup)
```

### For Socket Connections

Follow the `socket-provider.tsx` pattern:

```typescript
onCleanup(() => {
  if (socket) {
    socket.disconnect()
  }
})
```

### For SolidJS Effects

Always include cleanup logic:

```typescript
createEffect(() => {
  const resource = createResource()

  onCleanup(() => {
    resource.cleanup()
  })
})
```

## Why This Architecture Works

1. **WebSocket-centric design** eliminates most async operation complexity
2. **Phoenix protocol** handles lifecycle management automatically
3. **SolidJS `onCleanup()`** provides reliable component cleanup hooks
4. **Single-user deployment** eliminates complex connection pooling needs

## Code Locations

- **Timer patterns**: `apps/overlays/src/routes/takeover.tsx`
- **Channel patterns**: `apps/overlays/src/hooks/use-stream-channel.tsx`
- **Socket patterns**: `apps/overlays/src/providers/socket-provider.tsx`

---

_These patterns ensure operations are properly cancelled when components unmount or connections terminate. The WebSocket-first architecture makes async lifecycle management much simpler than traditional HTTP-based systems._
