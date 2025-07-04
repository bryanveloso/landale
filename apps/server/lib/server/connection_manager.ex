defmodule Server.ConnectionManager do
  @moduledoc """
  Centralized connection and resource management for WebSocket services.

  Provides utilities for proper connection lifecycle management, resource cleanup,
  and state synchronization across WebSocket-based services. Handles common
  patterns for monitor references, timers, and connection state tracking.

  ## Features

  - Centralized monitor reference management
  - Timer lifecycle management with error handling
  - Connection state validation and cleanup
  - Resource leak prevention
  - State synchronization helpers for reconnections

  ## Usage

      # In a GenServer that manages WebSocket connections
      defmodule MyService do
        use GenServer
        alias Server.ConnectionManager

        def init(_opts) do
          state = %{
            connection_state: ConnectionManager.init_connection_state(),
            # ... other state
          }
          {:ok, state}
        end

        def handle_info({:DOWN, ref, :process, pid, reason}, state) do
          updated_connection_state = ConnectionManager.handle_monitor_down(
            state.connection_state, 
            ref, 
            pid, 
            reason
          )
          
          state = %{state | connection_state: updated_connection_state}
          {:noreply, state}
        end

        @impl true
        def terminate(reason, state) do
          ConnectionManager.cleanup_all(state.connection_state)
          :ok
        end
      end
  """

  require Logger

  @type connection_state :: %{
          monitors: %{reference() => {pid(), atom()}},
          timers: %{atom() => reference()},
          connections: %{atom() => {pid(), reference()}},
          metadata: map()
        }

  @doc """
  Initializes a new connection state for tracking resources.

  ## Returns
  - Empty connection state ready for resource tracking
  """
  @spec init_connection_state() :: connection_state()
  def init_connection_state do
    %{
      monitors: %{},
      timers: %{},
      connections: %{},
      metadata: %{}
    }
  end

  @doc """
  Adds a monitor reference to the connection state.

  ## Parameters
  - `state` - Current connection state
  - `pid` - Process to monitor
  - `label` - Label for the monitor (for tracking)

  ## Returns
  - `{monitor_ref, updated_state}` - Monitor reference and updated state
  """
  @spec add_monitor(connection_state(), pid(), atom()) :: {reference(), connection_state()}
  def add_monitor(state, pid, label \\ :default) when is_pid(pid) do
    monitor_ref = Process.monitor(pid)

    updated_monitors = Map.put(state.monitors, monitor_ref, {pid, label})
    updated_state = %{state | monitors: updated_monitors}

    Logger.debug("Added monitor", pid: inspect(pid), label: label, ref: inspect(monitor_ref))

    {monitor_ref, updated_state}
  end

  @doc """
  Removes a monitor reference and demonitors the process.

  ## Parameters
  - `state` - Current connection state
  - `monitor_ref` - Monitor reference to remove

  ## Returns
  - Updated connection state without the monitor
  """
  @spec remove_monitor(connection_state(), reference()) :: connection_state()
  def remove_monitor(state, monitor_ref) when is_reference(monitor_ref) do
    case Map.get(state.monitors, monitor_ref) do
      {pid, label} ->
        case Process.demonitor(monitor_ref, [:flush]) do
          true ->
            Logger.debug("Removed monitor", pid: inspect(pid), label: label, ref: inspect(monitor_ref))

          false ->
            Logger.debug("Monitor already removed or expired", ref: inspect(monitor_ref))
        end

        updated_monitors = Map.delete(state.monitors, monitor_ref)
        %{state | monitors: updated_monitors}

      nil ->
        Logger.warning("Attempted to remove unknown monitor", ref: inspect(monitor_ref))
        state
    end
  end

  @doc """
  Handles a monitor DOWN message and cleans up the reference.

  ## Parameters
  - `state` - Current connection state
  - `monitor_ref` - Monitor reference from DOWN message
  - `pid` - Process that went down
  - `reason` - Reason for process termination

  ## Returns
  - Updated connection state with monitor removed
  """
  @spec handle_monitor_down(connection_state(), reference(), pid(), term()) :: connection_state()
  def handle_monitor_down(state, monitor_ref, pid, reason) do
    case Map.get(state.monitors, monitor_ref) do
      {^pid, label} ->
        Logger.info("Monitored process terminated",
          pid: inspect(pid),
          label: label,
          reason: inspect(reason)
        )

        updated_monitors = Map.delete(state.monitors, monitor_ref)
        %{state | monitors: updated_monitors}

      {other_pid, label} ->
        Logger.warning("Monitor reference mismatch",
          expected_pid: inspect(other_pid),
          actual_pid: inspect(pid),
          label: label
        )

        updated_monitors = Map.delete(state.monitors, monitor_ref)
        %{state | monitors: updated_monitors}

      nil ->
        Logger.debug("Received DOWN for unknown monitor",
          ref: inspect(monitor_ref),
          pid: inspect(pid)
        )

        state
    end
  end

  @doc """
  Adds a timer reference to the connection state.

  ## Parameters
  - `state` - Current connection state
  - `timer_ref` - Timer reference
  - `label` - Label for the timer

  ## Returns
  - Updated connection state with timer tracked
  """
  @spec add_timer(connection_state(), reference(), atom()) :: connection_state()
  def add_timer(state, timer_ref, label) when is_reference(timer_ref) do
    # Cancel existing timer with same label if it exists
    state = cancel_timer(state, label)

    updated_timers = Map.put(state.timers, label, timer_ref)
    updated_state = %{state | timers: updated_timers}

    Logger.debug("Added timer", label: label, ref: inspect(timer_ref))
    updated_state
  end

  @doc """
  Cancels a timer and removes it from tracking.

  ## Parameters
  - `state` - Current connection state
  - `label` - Label of timer to cancel

  ## Returns
  - Updated connection state without the timer
  """
  @spec cancel_timer(connection_state(), atom()) :: connection_state()
  def cancel_timer(state, label) do
    case Map.get(state.timers, label) do
      nil ->
        state

      timer_ref ->
        case Process.cancel_timer(timer_ref) do
          false ->
            Logger.debug("Timer already expired or cancelled", label: label, ref: inspect(timer_ref))

          time_left when is_integer(time_left) ->
            Logger.debug("Cancelled timer", label: label, time_left: time_left)
        end

        updated_timers = Map.delete(state.timers, label)
        %{state | timers: updated_timers}
    end
  end

  @doc """
  Adds a connection (Gun process + stream ref) to tracking.

  ## Parameters
  - `state` - Current connection state
  - `conn_pid` - Gun connection process
  - `stream_ref` - WebSocket stream reference
  - `label` - Label for the connection

  ## Returns
  - Updated connection state with connection tracked
  """
  @spec add_connection(connection_state(), pid(), reference(), atom()) :: connection_state()
  def add_connection(state, conn_pid, stream_ref, label \\ :default)
      when is_pid(conn_pid) and is_reference(stream_ref) do
    # Close existing connection with same label if it exists
    state = close_connection(state, label)

    updated_connections = Map.put(state.connections, label, {conn_pid, stream_ref})
    updated_state = %{state | connections: updated_connections}

    Logger.debug("Added connection",
      label: label,
      conn_pid: inspect(conn_pid),
      stream_ref: inspect(stream_ref)
    )

    updated_state
  end

  @doc """
  Closes a connection and removes it from tracking.

  ## Parameters
  - `state` - Current connection state
  - `label` - Label of connection to close

  ## Returns
  - Updated connection state without the connection
  """
  @spec close_connection(connection_state(), atom()) :: connection_state()
  def close_connection(state, label) do
    case Map.get(state.connections, label) do
      nil ->
        state

      {conn_pid, _stream_ref} ->
        if Process.alive?(conn_pid) do
          try do
            :gun.close(conn_pid)
            Logger.debug("Closed connection", label: label, conn_pid: inspect(conn_pid))
          rescue
            error ->
              Logger.warning("Error closing connection",
                label: label,
                conn_pid: inspect(conn_pid),
                error: inspect(error)
              )
          end
        else
          Logger.debug("Connection process already dead",
            label: label,
            conn_pid: inspect(conn_pid)
          )
        end

        updated_connections = Map.delete(state.connections, label)
        %{state | connections: updated_connections}
    end
  end

  @doc """
  Gets connection information by label.

  ## Parameters
  - `state` - Current connection state
  - `label` - Label of connection to retrieve

  ## Returns
  - `{:ok, {conn_pid, stream_ref}}` - Connection found
  - `:error` - Connection not found
  """
  @spec get_connection(connection_state(), atom()) :: {:ok, {pid(), reference()}} | :error
  def get_connection(state, label) do
    case Map.get(state.connections, label) do
      nil -> :error
      connection -> {:ok, connection}
    end
  end

  @doc """
  Checks if a connection is alive and valid.

  ## Parameters
  - `state` - Current connection state
  - `label` - Label of connection to check

  ## Returns
  - `true` - Connection is alive
  - `false` - Connection is dead or not found
  """
  @spec connection_alive?(connection_state(), atom()) :: boolean()
  def connection_alive?(state, label) do
    case get_connection(state, label) do
      {:ok, {conn_pid, _stream_ref}} -> Process.alive?(conn_pid)
      :error -> false
    end
  end

  @doc """
  Performs complete cleanup of all tracked resources.

  This should be called from the terminate/2 callback to ensure
  all resources are properly cleaned up.

  ## Parameters
  - `state` - Current connection state

  ## Returns
  - `:ok`
  """
  @spec cleanup_all(connection_state()) :: :ok
  def cleanup_all(state) do
    Logger.debug("Starting complete resource cleanup",
      monitors: map_size(state.monitors),
      timers: map_size(state.timers),
      connections: map_size(state.connections)
    )

    # Create immutable snapshots to prevent race conditions during iteration
    timers_snapshot = Map.to_list(state.timers)
    connections_snapshot = Map.to_list(state.connections)
    monitors_snapshot = Map.to_list(state.monitors)

    # Cancel all timers atomically
    cleanup_timers(timers_snapshot)

    # Close all connections with timeout protection
    cleanup_connections(connections_snapshot)

    # Demonitor all processes atomically
    cleanup_monitors(monitors_snapshot)

    Logger.debug("Resource cleanup completed")
    :ok
  end

  # Private cleanup functions with atomic operations

  defp cleanup_timers(timers_list) do
    Enum.each(timers_list, fn {label, timer_ref} ->
      case Process.cancel_timer(timer_ref) do
        false ->
          Logger.debug("Timer already expired during cleanup", label: label)

        time_left when is_integer(time_left) ->
          Logger.debug("Cancelled timer during cleanup", label: label, time_left: time_left)
      end
    end)
  end

  defp cleanup_connections(connections_list) do
    # Use Task.async_stream with timeout for parallel cleanup with bounded time
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
  end

  defp cleanup_single_connection(label, conn_pid) do
    # Direct call without Process.alive? check - Gun handles dead processes gracefully
    :gun.close(conn_pid)
    Logger.debug("Closed connection during cleanup", label: label)
  rescue
    error ->
      Logger.warning("Error closing connection during cleanup",
        label: label,
        error: inspect(error)
      )
  end

  defp cleanup_monitors(monitors_list) do
    Enum.each(monitors_list, fn {monitor_ref, {pid, label}} ->
      case Process.demonitor(monitor_ref, [:flush]) do
        true ->
          Logger.debug("Removed monitor during cleanup", label: label, pid: inspect(pid))

        false ->
          Logger.debug("Monitor already removed during cleanup", label: label)
      end
    end)
  end

  @doc """
  Sets metadata for the connection state.

  ## Parameters
  - `state` - Current connection state
  - `key` - Metadata key
  - `value` - Metadata value

  ## Returns
  - Updated connection state with metadata
  """
  @spec set_metadata(connection_state(), atom(), term()) :: connection_state()
  def set_metadata(state, key, value) do
    updated_metadata = Map.put(state.metadata, key, value)
    %{state | metadata: updated_metadata}
  end

  @doc """
  Gets metadata from the connection state.

  ## Parameters
  - `state` - Current connection state
  - `key` - Metadata key
  - `default` - Default value if key not found

  ## Returns
  - Metadata value or default
  """
  @spec get_metadata(connection_state(), atom(), term()) :: term()
  def get_metadata(state, key, default \\ nil) do
    Map.get(state.metadata, key, default)
  end

  @doc """
  Gets a summary of all tracked resources.

  ## Parameters
  - `state` - Current connection state

  ## Returns
  - Summary map with counts and details
  """
  @spec get_resource_summary(connection_state()) :: map()
  def get_resource_summary(state) do
    active_connections =
      state.connections
      |> Enum.filter(fn {_label, {conn_pid, _}} -> Process.alive?(conn_pid) end)
      |> length()

    %{
      monitors: map_size(state.monitors),
      timers: map_size(state.timers),
      connections: map_size(state.connections),
      active_connections: active_connections,
      metadata_keys: Map.keys(state.metadata)
    }
  end
end
