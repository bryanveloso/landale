# Task Concurrency Patterns

_Last Updated: 2025-07-22_

This document describes the task concurrency patterns used in Landale to prevent resource exhaustion and ensure system stability.

## Overview

Unbounded concurrent operations can exhaust system resources, especially when dealing with:

- Database writes
- External API calls
- File system operations
- CPU-intensive computations

## Implemented Patterns

### 1. DynamicSupervisor for Database Writes

**Location**: `Server.DBTaskSupervisor` in `application.ex`

```elixir
# Configuration in application.ex
{DynamicSupervisor,
  name: Server.DBTaskSupervisor,
  strategy: :one_for_one,
  max_children: 10}
```

**Usage**: `event_handler.ex` for async event storage

```elixir
case DynamicSupervisor.start_child(Server.DBTaskSupervisor, {Task, fn ->
  store_event_async(event_attrs, event_type, normalized_event)
end}) do
  {:ok, _pid} ->
    :ok
  {:error, :max_children} ->
    Logger.warning("Max concurrent DB writes reached, dropping event")
  {:error, reason} ->
    Logger.error("Failed to start DB write task", reason: inspect(reason))
end
```

**Benefits**:

- Limits concurrent database operations to 10
- Prevents database connection pool exhaustion
- Provides clear feedback when limit is reached
- Supervised tasks for proper cleanup
- Atomic database operations (event + user upsert in transaction)

### 2. Task.async_stream with max_concurrency

**Location**: `ConnectionManager.cleanup_connections/1`

```elixir
connections_list
|> Task.async_stream(
  fn {label, {conn_pid, _stream_ref}} ->
    cleanup_single_connection(label, conn_pid)
  end,
  timeout: 5_000,
  on_timeout: :kill_task,
  max_concurrency: System.schedulers_online()
)
|> Stream.run()
```

**Benefits**:

- Limits parallelism to available CPU cores
- Prevents process explosion during cleanup
- Includes timeout protection

### 3. Task.Supervisor for OAuth Operations

**Location**: `Twitch` service for token validation/refresh

```elixir
Task.Supervisor.async_nolink(Server.TaskSupervisor, fn ->
  OAuthTokenManager.validate_token(state.token_manager, validation_url)
end)
```

**Benefits**:

- Supervised async operations
- Crash isolation from main service
- Proper cleanup on termination

## Concurrency Limits Guide

### Choosing max_children Values

- **Database operations**: 10 (conservative for personal project)
- **API calls**: 5-20 depending on rate limits
- **CPU-intensive**: `System.schedulers_online()`
- **I/O operations**: 50-100 (I/O doesn't block schedulers)

### Error Handling Strategies

1. **Drop and log** (current approach for events):
   - Suitable for non-critical data
   - Simple implementation
   - No retry complexity

2. **Queue and retry** (future enhancement if needed):

   ```elixir
   # Could use GenServer with queue
   # Or persistent job queue like Oban
   ```

3. **Backpressure** (for producer-consumer pipelines):
   - Use GenStage for complex flows
   - Not needed for current simple patterns

## Testing Patterns

```elixir
# Verify concurrency limits
test "respects max_children limit" do
  results = for i <- 1..15 do
    DynamicSupervisor.start_child(Server.DBTaskSupervisor, task_spec)
  end

  successful = Enum.count(results, &match?({:ok, _}, &1))
  assert successful <= 10
end
```

## When to Add Concurrency Controls

Add controls when you see:

- Unbounded `Task.async` or `Task.start` calls
- Loops creating tasks without limits
- Event handlers spawning processes per event
- Batch operations without chunking

## Monitoring

Monitor these metrics:

- `DynamicSupervisor.count_children(Server.DBTaskSupervisor)`
- Frequency of `:max_children` errors in logs
- Database connection pool usage
- System process count

## References

- [Elixir School: Supervisors](https://elixirschool.com/en/lessons/advanced/otp_supervisors)
- [DynamicSupervisor docs](https://hexdocs.pm/elixir/DynamicSupervisor.html)
- [Task.async_stream docs](https://hexdocs.pm/elixir/Task.html#async_stream/3)
