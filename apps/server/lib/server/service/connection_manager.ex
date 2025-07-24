defmodule Server.Service.ConnectionManager do
  @moduledoc """
  Common connection management functionality for services.

  Provides helpers for managing connections, reconnection timers,
  and connection state transitions.

  ## Usage

      defmodule MyService do
        use Server.Service
        use Server.Service.ConnectionManager
        
        # Your service implementation
      end
  """

  defmacro __using__(_opts) do
    quote do
      alias Server.{ConnectionManager, NetworkConfig}

      # Connection state management

      @doc """
      Updates connection state and triggers change handlers if the state changed.
      """
      def update_connection_state(state, updates) do
        old_connection_state = get_in(state, [:connection, :state])
        new_connection = Map.merge(state.connection || %{}, updates)
        new_state = put_in(state, [:connection], new_connection)

        # Notify about connection changes if we implement the callback
        if old_connection_state != new_connection.state &&
             function_exported?(__MODULE__, :handle_connection_change, 3) do
          handle_connection_change(old_connection_state, new_connection.state, new_state)
        else
          new_state
        end
      end

      @doc """
      Schedules a reconnection attempt after the specified delay.
      Cancels any existing reconnection timer.
      """
      def schedule_reconnect(state, delay \\ nil) do
        delay = delay || NetworkConfig.reconnect_interval_ms()
        state = cancel_reconnect_timer(state)

        timer = Process.send_after(self(), :reconnect, delay)
        Map.put(state, :reconnect_timer, timer)
      end

      @doc """
      Cancels any pending reconnection timer.
      """
      def cancel_reconnect_timer(%{reconnect_timer: nil} = state), do: state

      def cancel_reconnect_timer(%{reconnect_timer: timer} = state) do
        Process.cancel_timer(timer)
        Map.put(state, :reconnect_timer, nil)
      end

      @doc """
      Ensures connection structure exists in state.
      """
      def ensure_connection_state(state) do
        Map.put_new(state, :connection, %{
          state: :disconnected,
          conn_pid: nil,
          stream_ref: nil,
          connected_at: nil
        })
      end

      @doc """
      Marks the connection as established and updates metadata.
      """
      def mark_connected(state, conn_pid, stream_ref \\ nil) do
        update_connection_state(state, %{
          state: :connected,
          conn_pid: conn_pid,
          stream_ref: stream_ref,
          connected_at: DateTime.utc_now()
        })
      end

      @doc """
      Marks the connection as disconnected and clears metadata.
      """
      def mark_disconnected(state) do
        update_connection_state(state, %{
          state: :disconnected,
          conn_pid: nil,
          stream_ref: nil,
          connected_at: nil
        })
      end

      @doc """
      Checks if the service is currently connected.
      """
      def connected?(state) do
        get_in(state, [:connection, :state]) == :connected
      end

      @doc """
      Gets the connection uptime in seconds, or 0 if not connected.
      """
      def connection_uptime(state) do
        case get_in(state, [:connection, :connected_at]) do
          nil -> 0
          connected_at -> DateTime.diff(DateTime.utc_now(), connected_at)
        end
      end

      # WebSocket connection management

      @doc """
      Initializes WebSocket connection tracking in state.
      """
      def init_websocket_state(state) do
        connection_state = Map.get(state, :connection_manager) || ConnectionManager.init_connection_state()

        state
        |> Map.put(:connection_manager, connection_state)
        |> ensure_connection_state()
      end

      @doc """
      Adds a monitor for a WebSocket connection process.
      """
      def monitor_connection(state, conn_pid, label \\ :websocket) do
        {monitor_ref, connection_state} =
          ConnectionManager.add_monitor(
            state.connection_manager,
            conn_pid,
            label
          )

        state
        |> Map.put(:connection_manager, connection_state)
        |> Map.put(:monitor_ref, monitor_ref)
      end

      @doc """
      Handles process DOWN messages for monitored connections.
      """
      def handle_connection_down(state, monitor_ref, pid, reason) do
        connection_state =
          ConnectionManager.handle_monitor_down(
            state.connection_manager,
            monitor_ref,
            pid,
            reason
          )

        Map.put(state, :connection_manager, connection_state)
      end

      @doc """
      Cleans up all connection resources.
      """
      def cleanup_connections(state) do
        if Map.has_key?(state, :connection_manager) do
          ConnectionManager.cleanup_all(state.connection_manager)
        end

        :ok
      end
    end
  end
end
