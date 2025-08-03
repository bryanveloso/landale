defmodule ServerWeb.WebSocketTracker do
  @moduledoc """
  Phoenix.Tracker implementation for WebSocket connection lifecycle tracking.

  Tracks socket processes to properly detect disconnections and calculate
  connection durations without memory leaks.
  """

  use Phoenix.Tracker
  require Logger

  @tracker_name __MODULE__
  @topic "websocket_connections"

  def start_link(opts) do
    opts = Keyword.put(opts, :name, @tracker_name)
    Phoenix.Tracker.start_link(__MODULE__, opts, opts)
  end

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :pubsub_server)
    {:ok, %{pubsub_server: server}}
  end

  @impl true
  def handle_diff(diff, state) do
    # Process joins - new connections
    for {_topic, {joins, _leaves}} <- diff do
      for {socket_id, meta} <- joins do
        Logger.debug("WebSocket connection tracked",
          socket_id: socket_id,
          connected_at: meta.connected_at
        )

        # Notify stats tracker about new connection
        notify_stats_tracker(:connected, socket_id, meta)
      end
    end

    # Process leaves - disconnections
    for {_topic, {_joins, leaves}} <- diff do
      for {socket_id, meta} <- leaves do
        duration = calculate_duration(meta.connected_at)

        Logger.debug("WebSocket disconnection tracked",
          socket_id: socket_id,
          duration_ms: duration
        )

        # Notify stats tracker about disconnection with duration
        notify_stats_tracker(:disconnected, socket_id, Map.put(meta, :duration_ms, duration))
      end
    end

    {:ok, state}
  end

  # Public API

  def track_socket(socket_id, pid \\ self()) do
    metadata = %{
      connected_at: System.system_time(:millisecond),
      pid: pid
    }

    Phoenix.Tracker.track(@tracker_name, pid, @topic, socket_id, metadata)
  end

  def untrack_socket(socket_id, pid \\ self()) do
    Phoenix.Tracker.untrack(@tracker_name, pid, @topic, socket_id)
  end

  def list_connections do
    Phoenix.Tracker.list(@tracker_name, @topic)
  end

  def get_connection(socket_id) do
    case Phoenix.Tracker.get_by_key(@tracker_name, @topic, socket_id) do
      [] -> nil
      [{_pid, meta}] -> meta
      _ -> nil
    end
  end

  # Private helpers

  defp calculate_duration(connected_at) when is_integer(connected_at) do
    System.system_time(:millisecond) - connected_at
  end

  defp calculate_duration(_), do: 0

  defp notify_stats_tracker(event, socket_id, metadata) do
    # Send event to WebSocketStatsTracker if it's running
    case Process.whereis(ServerWeb.WebSocketStatsTracker) do
      nil ->
        :ok

      pid ->
        send(pid, {:tracker_event, event, socket_id, metadata})
    end
  end
end
