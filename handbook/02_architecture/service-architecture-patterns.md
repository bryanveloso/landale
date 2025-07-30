# Service Architecture Patterns

This document describes the two primary service architecture patterns used in the Landale project and provides guidance on when to use each pattern.

## Overview

Landale uses two distinct patterns for implementing services:

1. **Simple Service Pattern** - For straightforward services with single-responsibility
2. **Complex Service Pattern** - For services requiring multi-process coordination

All services, regardless of pattern, implement the `Server.ServiceBehaviour` interface to ensure consistency at the API level.

## Pattern 1: Simple Service Pattern

### When to Use

Use the Simple Service pattern when:

- Service has a single, well-defined responsibility
- State management is straightforward
- No complex process coordination required
- Service primarily does one type of operation (polling, TCP server, etc.)

### Architecture

```elixir
defmodule Server.Services.MyService do
  use Server.Service,
    service_name: "my-service",
    behaviour: Server.Services.MyServiceBehaviour

  use Server.Service.StatusReporter

  @behaviour Server.ServiceBehaviour

  # Service implementation...
end
```

### Examples

**Rainwave Service**

- Single responsibility: Poll music API and broadcast updates
- Simple state: current song, API credentials, health metrics
- Uses `Server.Service` abstraction for common functionality

**IronmonTCP Service**

- Single responsibility: TCP server for game state updates
- Simple state: connections, listen socket
- Handles TCP protocol and broadcasts events

### Benefits

- Reduced boilerplate code
- Standardized lifecycle management
- Built-in health checking and status reporting
- Automatic correlation ID propagation
- Simplified testing with mocks

## Pattern 2: Complex Service Pattern

### When to Use

Use the Complex Service pattern when:

- Service requires multiple coordinated processes
- Complex state machines are needed (gen_statem)
- Service manages sub-services or child processes
- Different components have different lifecycles
- Service acts as a facade for multiple subsystems

### Architecture

```
┌─────────────────────────────────────┐
│        Service Facade               │
│    (implements ServiceBehaviour)    │
└────────────┬───────────────────────┘
             │
    ┌────────┴────────┐
    │   Supervisor    │
    └────────┬────────┘
             │
    ┌────────┼────────┬─────────┐
    │        │        │         │
┌───▼──┐ ┌──▼───┐ ┌──▼───┐ ┌──▼───┐
│Conn  │ │Scene │ │Stream│ │Event │
│Mgr   │ │Mgr   │ │Mgr   │ │Handler│
└──────┘ └──────┘ └──────┘ └──────┘
```

### Examples

**OBS Service**

- Multiple responsibilities: WebSocket connection, scene management, stream control
- Complex state machine: Uses gen_statem for connection states
- Sub-services: Connection, SceneManager, StreamManager, EventHandler
- Facade provides unified interface while delegating to specialists

**Twitch Service**

- Multiple responsibilities: WebSocket, OAuth, EventSub subscriptions
- Decomposed architecture: Separate processes for each concern
- Complex initialization: OAuth flow before WebSocket connection
- Facade maintains backward compatibility

### Implementation

```elixir
defmodule Server.Services.ComplexService do
  @behaviour Server.ServiceBehaviour

  # Facade implementation
  def start_link(opts) do
    children = [
      {Registry, keys: :unique, name: __MODULE__.Registry},
      {__MODULE__.Supervisor, opts}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  # ServiceBehaviour implementation
  @impl Server.ServiceBehaviour
  def get_health do
    # Aggregate health from all sub-components
  end

  @impl Server.ServiceBehaviour
  def get_info do
    %{
      name: "complex-service",
      version: "1.0.0",
      capabilities: [:multi_process, :complex_state],
      description: "Complex service with multiple subsystems"
    }
  end
end
```

### Benefits

- Separation of concerns
- Independent scaling of components
- Fault isolation between subsystems
- Flexible process supervision strategies
- Can use different OTP behaviours (GenServer, gen_statem, etc.)

## Choosing the Right Pattern

### Use Simple Service When:

1. **Single Responsibility**
   - Service does one main thing
   - Clear input/output boundaries
   - Limited external dependencies

2. **Simple State**
   - State fits in a single process
   - No complex state transitions
   - State updates are atomic

3. **Predictable Lifecycle**
   - Start → Run → Stop
   - No complex initialization sequences
   - Cleanup is straightforward

### Use Complex Service When:

1. **Multiple Responsibilities**
   - Service coordinates multiple operations
   - Different concerns need isolation
   - Components have different performance characteristics

2. **Complex State Management**
   - State machines with multiple transitions
   - State spread across multiple processes
   - Need for state consistency guarantees

3. **Advanced Requirements**
   - Hot code reloading for specific components
   - Different supervision strategies per component
   - Complex error recovery scenarios

## Migration Path

If a service outgrows the Simple pattern:

1. Keep the existing service module as a facade
2. Implement `Server.ServiceBehaviour` on the facade
3. Decompose internals into supervised child processes
4. Maintain backward compatibility at the API level

## Best Practices

### For All Services:

1. **Always implement `Server.ServiceBehaviour`**
   - Ensures consistent health checking
   - Enables service discovery
   - Provides standard introspection

2. **Use Correlation IDs**
   - Propagate through all operations
   - Include in all log messages
   - Pass to event emissions

3. **Implement Comprehensive Health Checks**
   - Check all critical dependencies
   - Provide detailed health information
   - Use standard health status values

### For Simple Services:

1. **Keep It Simple**
   - Resist adding multiple responsibilities
   - Extract complex logic to separate modules
   - Use the provided abstractions

2. **Leverage Built-in Features**
   - Use `Server.Service.StatusReporter`
   - Let the framework handle boilerplate
   - Focus on business logic

### For Complex Services:

1. **Clear Boundaries**
   - Each sub-process has one responsibility
   - Define clear interfaces between components
   - Document component interactions

2. **Proper Supervision**
   - Choose appropriate restart strategies
   - Consider failure scenarios
   - Test supervision tree behavior

3. **Consistent Interface**
   - Facade hides internal complexity
   - Public API remains stable
   - Health aggregates all components

## Testing Strategies

### Simple Services

```elixir
# Use Mox for external dependencies
Mox.defmock(MyServiceClientMock, for: MyServiceClientBehaviour)

# Test the service directly
test "service handles API errors gracefully" do
  expect(MyServiceClientMock, :fetch_data, fn ->
    {:error, :timeout}
  end)

  assert {:ok, %{status: :degraded}} = MyService.get_health()
end
```

### Complex Services

```elixir
# Test components individually
test "connection manager handles reconnection" do
  # Test specific component behavior
end

# Integration test through facade
test "service aggregates health from all components" do
  # Start service and verify health aggregation
end
```

## Conclusion

Both patterns serve important roles in the Landale architecture:

- **Simple Services** provide straightforward implementation for focused functionality
- **Complex Services** enable sophisticated multi-process coordination when needed

The key is choosing the right pattern for the service's requirements and maintaining consistency through the `Server.ServiceBehaviour` interface regardless of internal implementation.
