# WebSocket Resilience Patterns

The Landale system uses standardized WebSocket patterns across all Phoenix channels to ensure consistent behavior, resilience, and maintainability. These patterns are implemented in the `ServerWeb.ChannelBase` module.

## Core Pattern: ChannelBase Module

All Phoenix channels inherit from `ServerWeb.ChannelBase`, which provides:

```elixir
defmodule ServerWeb.MyChannel do
  use ServerWeb.ChannelBase
  
  @impl true
  def join(topic, payload, socket) do
    socket = setup_correlation_id(socket)
    # Channel-specific logic
    {:ok, socket}
  end
end
```

## Key Patterns

### 1. Correlation ID Management

Every WebSocket connection gets a correlation ID for request tracing:

```elixir
def join(topic, _payload, socket) do
  socket = setup_correlation_id(socket)
  # Sets correlation_id in socket assigns and logger metadata
  {:ok, socket}
end
```

This enables tracking requests across services in logs:
```
[info] correlation_id=a1b2c3d4 Channel joined channel=DashboardChannel topic=dashboard:lobby
```

### 2. Standard Ping/Pong Health Checks

All channels support connection health monitoring:

```elixir
@impl true
def handle_in("ping", payload, socket) do
  handle_ping(payload, socket)
  # Returns: {:reply, {:ok, %{pong: true, timestamp: unix_time, ...payload}}, socket}
end
```

Clients can send periodic pings to verify connection health.

### 3. Unified Error Handling

Consistent error reporting across channels:

```elixir
push_error(socket, "event_name", :error_type, "Human readable message")
# Logs error with correlation ID and pushes to client
```

### 4. PubSub Topic Management

Batch subscription to multiple topics:

```elixir
subscribe_to_topics(["obs:events", "twitch:events", "system:events"])
```

### 5. After Join Pattern

Delayed initial state sending to ensure client is ready:

```elixir
def join(topic, _payload, socket) do
  socket = setup_correlation_id(socket)
  send_after_join(socket, :after_join)
  {:ok, socket}
end

def handle_info(:after_join, socket) do
  push(socket, "initial_state", get_current_state())
  {:noreply, socket}
end
```

### 6. Fallback Pattern

Graceful degradation when services fail:

```elixir
def handle_info(:after_join, socket) do
  with_fallback(socket, "get_initial_state",
    fn -> StreamProducer.get_current_state() end,
    fn -> Server.ContentFallbacks.get_fallback_state() end
  )
  {:noreply, socket}
end
```

### 7. Event Batching

Performance optimization for high-frequency events:

```elixir
{:ok, batcher} = ChannelBase.EventBatcher.start_link(
  socket: socket,
  event_name: "batch_updates",
  batch_size: 50,
  flush_interval: 100  # ms
)

# Events are accumulated and sent in batches
ChannelBase.EventBatcher.add_event(batcher, event_data)
```

## Channel Implementations

### Dashboard Channel
- **Purpose**: Control interface updates
- **Topics**: `dashboard:lobby`
- **Special patterns**: Request/response for control operations

### Events Channel  
- **Purpose**: Real-time event streaming
- **Topics**: `events:all`, `events:chat`, `events:twitch`, etc.
- **Special patterns**: Topic-based filtering of event subscriptions

### Stream Channel
- **Purpose**: Overlay state management
- **Topics**: `stream:overlays`, `stream:queue`
- **Special patterns**: Fallback states when StreamProducer fails

### Overlay Channel
- **Purpose**: Overlay communication with HTTP API parity
- **Topics**: `overlay:obs`, `overlay:twitch`, `overlay:system`, etc.
- **Special patterns**: Service command execution with consistent error handling

### Transcription Channel
- **Purpose**: Real-time transcription broadcasting
- **Topics**: `transcription:live`, `transcription:session:{id}`
- **Special patterns**: Session-specific channels

## Best Practices

1. **Always use correlation IDs**: Call `setup_correlation_id/1` in every join
2. **Handle unhandled messages**: Use `log_unhandled_message/3` in catch-all clauses
3. **Provide health checks**: Implement ping/pong in all channels
4. **Use after_join pattern**: Send initial state after join completes
5. **Implement fallbacks**: Use `with_fallback/4` for external service calls
6. **Batch high-frequency events**: Use EventBatcher for performance

## Personal Scale Considerations

These patterns are designed for a single-user system on Tailscale:
- No complex authentication needed (Tailscale handles security)
- Correlation IDs for debugging, not multi-tenant isolation
- Batching tuned for single client, not thousands
- Simple fallbacks, not complex circuit breakers

## Future Improvements

1. **Master timeline for animations**: Consider GSAP master timeline
2. **Circuit breaker with GenServer**: Stateful circuit breaker implementation
3. **WebSocket compression**: For bandwidth optimization
4. **Selective event filtering**: Client-specified event filters