defmodule ServerWeb.WebSocketStatsTracker do
  @moduledoc """
  Tracks WebSocket connection and channel statistics using Phoenix telemetry events.

  Listens to Phoenix telemetry events and maintains real-time counters for:
  - Active socket connections
  - Active channels by type
  - Connection/disconnection events
  - Channel join/leave events
  """

  use GenServer
  require Logger

  defstruct total_connections: 0,
            active_channels: 0,
            channels_by_type: %{},
            total_connects: 0,
            total_disconnects: 0,
            total_joins: 0,
            total_leaves: 0,
            connection_times: %{},
            start_time: nil

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    # Attach telemetry handlers
    attach_telemetry_handlers()

    state = %__MODULE__{
      start_time: System.monotonic_time(:millisecond)
    }

    Logger.info("WebSocket stats tracker started")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_connections: state.total_connections,
      active_channels: state.active_channels,
      channels_by_type: state.channels_by_type,
      recent_disconnects: calculate_recent_disconnects(state),
      average_connection_duration: calculate_avg_duration(state),
      totals: %{
        connects: state.total_connects,
        disconnects: state.total_disconnects,
        joins: state.total_joins,
        leaves: state.total_leaves
      }
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:telemetry_event, [:landale, :websocket, :connected], measurements, metadata}, state) do
    Logger.info("Telemetry: Socket connected", socket_id: metadata[:socket_id])

    state = %{
      state
      | total_connections: state.total_connections + 1,
        total_connects: state.total_connects + 1,
        connection_times: Map.put(state.connection_times, metadata[:socket_id], measurements[:system_time])
    }

    {:noreply, state}
  end

  @impl true
  def handle_info({:telemetry_event, [:landale, :websocket, :disconnected], _measurements, metadata}, state) do
    Logger.debug("Socket disconnected", socket_id: metadata[:socket_id])

    state = %{
      state
      | total_connections: max(0, state.total_connections - 1),
        total_disconnects: state.total_disconnects + 1,
        connection_times: Map.delete(state.connection_times, metadata[:socket_id])
    }

    {:noreply, state}
  end

  @impl true
  def handle_info({:telemetry_event, [:landale, :channel, :joined], _measurements, metadata}, state) do
    channel_type = extract_channel_type(metadata[:topic])
    Logger.info("Telemetry: Channel joined", topic: metadata[:topic], channel_type: channel_type)

    state = %{
      state
      | active_channels: state.active_channels + 1,
        total_joins: state.total_joins + 1,
        channels_by_type: Map.update(state.channels_by_type, channel_type, 1, &(&1 + 1))
    }

    {:noreply, state}
  end

  @impl true
  def handle_info({:telemetry_event, [:landale, :channel, :left], _measurements, metadata}, state) do
    channel_type = extract_channel_type(metadata[:topic])
    Logger.debug("Channel left", topic: metadata[:topic], channel_type: channel_type)

    current_count = Map.get(state.channels_by_type, channel_type, 0)
    new_count = max(0, current_count - 1)

    channels_by_type =
      if new_count == 0 do
        Map.delete(state.channels_by_type, channel_type)
      else
        Map.put(state.channels_by_type, channel_type, new_count)
      end

    state = %{
      state
      | active_channels: max(0, state.active_channels - 1),
        total_leaves: state.total_leaves + 1,
        channels_by_type: channels_by_type
    }

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in WebSocketStatsTracker", message: inspect(msg))
    {:noreply, state}
  end

  # Private functions

  defp attach_telemetry_handlers do
    events = [
      [:landale, :websocket, :connected],
      [:landale, :websocket, :disconnected],
      [:landale, :channel, :joined],
      [:landale, :channel, :left]
    ]

    case :telemetry.attach_many(
           "websocket-stats-tracker",
           events,
           &handle_telemetry_event/4,
           %{}
         ) do
      :ok ->
        Logger.info("Telemetry handlers attached successfully for events: #{inspect(events)}")
        :ok

      {:error, :already_exists} ->
        Logger.warning("Telemetry handlers already attached, detaching and re-attaching")
        :telemetry.detach("websocket-stats-tracker")

        :telemetry.attach_many(
          "websocket-stats-tracker",
          events,
          &handle_telemetry_event/4,
          %{}
        )

      error ->
        Logger.error("Failed to attach telemetry handlers: #{inspect(error)}")
        error
    end
  end

  defp handle_telemetry_event(event, measurements, metadata, _config) do
    Logger.info("Telemetry handler called", event: event, metadata: metadata)
    # Forward telemetry events to our GenServer
    send(__MODULE__, {:telemetry_event, event, measurements, metadata})
  end

  defp extract_channel_type(topic) when is_binary(topic) do
    topic
    |> String.split(":")
    |> List.first()
    |> case do
      nil -> "unknown"
      type -> type
    end
  end

  defp extract_channel_type(_), do: "unknown"

  defp calculate_recent_disconnects(state) do
    # For now, just return total disconnects
    # Could be enhanced to track disconnects in a time window
    state.total_disconnects
  end

  defp calculate_avg_duration(state) do
    # Calculate average connection duration from active connections
    if map_size(state.connection_times) == 0 do
      0
    else
      current_time = System.monotonic_time(:millisecond)

      durations =
        Enum.map(state.connection_times, fn {_socket_id, start_time} ->
          current_time - start_time
        end)

      if length(durations) > 0 do
        Enum.sum(durations) / length(durations)
      else
        0
      end
    end
  end
end
