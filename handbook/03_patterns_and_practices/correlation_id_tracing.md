# Correlation ID Tracing

Correlation IDs provide request tracing across services in the Landale system, enabling debugging and observability for the streaming overlay infrastructure. This is a technical logging feature - not to be confused with stream correlation which combines audio/chat/interactions.

## Purpose

Correlation IDs solve the distributed tracing problem:
- Track a single request as it flows through multiple services
- Debug issues by following the correlation ID in logs
- Understand request flow and timing across service boundaries
- Identify bottlenecks and failures in complex workflows

## Implementation

### Core Module (apps/server)

The `Server.CorrelationId` module provides the foundation:

```elixir
# apps/server/lib/server/correlation_id.ex
defmodule Server.CorrelationId do
  @moduledoc """
  Generates and manages correlation IDs for request tracing across services.
  """

  @doc """
  Generates a new correlation ID.
  Uses a short UUID format suitable for logging without being
  too verbose for single-user system logs.
  """
  def generate do
    UUID.uuid4()
    |> String.replace("-", "")
    |> String.slice(0, 8)
  end

  @doc """
  Extracts correlation ID from various sources with fallback generation.
  """
  def from_context(opts \\ []) do
    # Check multiple sources in order:
    # 1. Phoenix socket/conn assigns
    # 2. HTTP headers (x-correlation-id)
    # 3. Logger metadata
    # 4. Default value if provided
    # 5. Generate new ID as fallback
  end

  @doc """
  Adds correlation ID to Logger metadata for automatic inclusion in logs.
  """
  def put_logger_metadata(correlation_id) do
    Logger.metadata(correlation_id: correlation_id)
  end
end
```

### Design Decisions

#### 8-Character IDs
For a personal-scale system, full UUIDs are overkill. 8 characters provide:
- Sufficient uniqueness for single-user context
- Readable logs without excessive verbosity
- Easy to grep and search in terminals

#### Automatic Propagation
The module checks multiple sources to find existing IDs:
1. **Phoenix assigns** - For WebSocket/HTTP contexts
2. **HTTP headers** - For service-to-service calls
3. **Logger metadata** - For async operations
4. **Generate new** - When starting fresh flows

### Usage Patterns

#### Phoenix Channels

```elixir
def join("events:all", _payload, socket) do
  correlation_id = Server.CorrelationId.generate()
  socket = assign(socket, :correlation_id, correlation_id)
  
  Logger.info("Events channel joined",
    topic: "all",
    correlation_id: correlation_id
  )
  
  {:ok, socket}
end
```

#### HTTP Controllers

```elixir
def create(conn, params) do
  correlation_id = Server.CorrelationId.from_context(
    headers: conn.req_headers
  )
  
  Server.CorrelationId.put_logger_metadata(correlation_id)
  
  # All subsequent logs will include correlation_id
  Logger.info("Processing request")
  
  # Pass to other services
  OtherService.call(params, correlation_id: correlation_id)
end
```

#### Async Operations

```elixir
def process_event_async(event_attrs, event_type) do
  # Capture correlation ID in closure
  correlation_id = event_attrs[:correlation_id]
  
  Task.start(fn ->
    # Re-establish in new process
    Server.CorrelationId.put_logger_metadata(correlation_id)
    
    Logger.debug("Processing event",
      event_type: event_type,
      correlation_id: correlation_id
    )
    
    # Do work...
  end)
end
```

### Cross-Service Propagation

#### HTTP Headers
When making HTTP requests between services:

```elixir
headers = [{"x-correlation-id", correlation_id}]
HTTPoison.post(url, body, headers)
```

#### WebSocket Messages
Include in message payloads:

```elixir
push(socket, "event", %{
  type: "audio:transcription",
  correlation_id: socket.assigns.correlation_id,
  data: event_data
})
```

#### Phoenix PubSub
Include in broadcast metadata:

```elixir
Phoenix.PubSub.broadcast(Server.PubSub, "events", %{
  event: event_data,
  correlation_id: correlation_id
})
```

## Real-World Example

Following a subscription event through the system:

```
1. Twitch EventSub → Phoenix Server
   [a1b2c3d4] Received channel.subscribe event

2. Event Handler Processing
   [a1b2c3d4] Normalizing event data
   [a1b2c3d4] Storing in ActivityLog
   [a1b2c3d4] Publishing to PubSub

3. EventsChannel Distribution
   [a1b2c3d4] Broadcasting to events:all subscribers
   [a1b2c3d4] Pushed subscription event to 3 clients

4. Overlay Animation
   [a1b2c3d4] Received subscription event
   [a1b2c3d4] Triggering celebration animation

5. Analysis Service
   [a1b2c3d4] Correlating subscription with audio context
   [a1b2c3d4] Building LLM context for analysis
```

## Unused Components

### Correlation ID Pool

The codebase includes `correlation_id_pool.ex` which isn't currently used:

```elixir
# apps/server/lib/server/correlation_id_pool.ex
# Implements ID pooling/reuse for efficiency
```

For personal scale, generating new IDs is fine. The pool could be activated if:
- ID generation becomes a bottleneck
- You want to limit the ID space for easier searching
- You need deterministic IDs for testing

## Best Practices

1. **Always propagate**: When spawning tasks or making calls, pass the ID
2. **Log early**: Include correlation ID in the first log of any operation
3. **Cross boundaries**: Ensure IDs cross service/process boundaries
4. **Async safety**: Capture IDs in closures for async operations
5. **Fallback gracefully**: Always generate new ID if none exists

## Debugging with Correlation IDs

### Find all logs for a request
```bash
grep "a1b2c3d4" logs/*.log
```

### Follow request flow
```bash
grep "a1b2c3d4" logs/*.log | sort -k2,2
```

### Find failed requests
```bash
grep -B2 -A2 "error.*correlation_id" logs/*.log
```

## Integration Guidelines

When adding new services or features:

1. **Accept correlation IDs** in your service interface
2. **Extract or generate** IDs at service boundaries  
3. **Include in all logs** via Logger metadata
4. **Pass to dependencies** when making calls
5. **Document the flow** for complex operations

## Key Differences from Stream Correlation

- **Correlation IDs**: Technical feature for request tracing in logs
- **Stream Correlation**: Feature for combining audio/chat/interactions for AI context
- **Correlation IDs**: Single request lifecycle (seconds)
- **Stream Correlation**: Stream session analysis (hours)
- **Correlation IDs**: For debugging and ops
- **Stream Correlation**: For AI companion understanding

The correlation ID system provides the technical foundation for observability in a distributed system, while stream correlation provides the semantic understanding for the AI companion vision.
