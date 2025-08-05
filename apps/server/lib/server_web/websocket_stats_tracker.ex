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
            # List of recent connection durations for averaging
            connection_durations: [],
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

    Logger.debug("WebSocket stats tracker started")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_connections: state.total_connections,
      active_channels: state.active_channels,
      channels_by_type: state.channels_by_type,
      recent_disconnects: calculate_recent_disconnects(state),
      average_connection_duration: calculate_average_duration(state),
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
  def handle_info(
        {:telemetry_event, [:landale, :websocket, :connected], _measurements, metadata},
        state
      ) do
    Logger.debug("Socket connected", socket_id: metadata[:socket_id])

    state = %{
      state
      | total_connections: state.total_connections + 1,
        total_connects: state.total_connects + 1
    }

    {:noreply, state}
  end

  # Removed to avoid double counting - handled by tracker event instead
  # @impl true
  # def handle_info({:telemetry_event, [:landale, :websocket, :disconnected], _measurements, metadata}, state) do
  #   Logger.debug("Socket disconnected", socket_id: metadata[:socket_id])

  #   state = %{
  #     state
  #     | total_connections: max(0, state.total_connections - 1),
  #       total_disconnects: state.total_disconnects + 1
  #   }

  #   {:noreply, state}
  # end

  @impl true
  def handle_info({:tracker_event, :connected, socket_id, _metadata}, state) do
    Logger.debug("Tracker: Socket connected", socket_id: socket_id)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tracker_event, :disconnected, socket_id, metadata}, state) do
    Logger.debug("Tracker: Socket disconnected",
      socket_id: socket_id,
      duration_ms: metadata[:duration_ms]
    )

    # Add duration to our list (keep last 100 for averaging)
    durations =
      [metadata[:duration_ms] | state.connection_durations]
      |> Enum.take(100)

    state = %{
      state
      | connection_durations: durations,
        total_connections: max(0, state.total_connections - 1),
        total_disconnects: state.total_disconnects + 1
    }

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:telemetry_event, [:landale, :channel, :joined], _measurements, metadata},
        state
      ) do
    channel_type = extract_channel_type(metadata[:topic])
    Logger.debug("Channel joined", topic: metadata[:topic], channel_type: channel_type)

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
      # [:landale, :websocket, :disconnected], # Removed - handled by tracker event
      [:landale, :channel, :joined],
      [:landale, :channel, :left],
      # Also listen for Phoenix's built-in socket disconnect event
      [:phoenix, :socket, :disconnect]
    ]

    case :telemetry.attach_many(
           "websocket-stats-tracker",
           events,
           &__MODULE__.handle_telemetry_event/4,
           %{}
         ) do
      :ok ->
        Logger.debug("Telemetry handlers attached for WebSocket stats tracking")
        :ok

      {:error, :already_exists} ->
        Logger.debug("Telemetry handlers already attached, re-attaching")
        :telemetry.detach("websocket-stats-tracker")

        :telemetry.attach_many(
          "websocket-stats-tracker",
          events,
          &__MODULE__.handle_telemetry_event/4,
          %{}
        )

      error ->
        Logger.error("Failed to attach telemetry handlers: #{inspect(error)}")
        error
    end
  end

  def handle_telemetry_event(event, measurements, metadata, _config) do
    # Forward telemetry events to our GenServer silently
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

  defp calculate_average_duration(state) do
    case state.connection_durations do
      [] ->
        0

      durations ->
        # Calculate average of recent connection durations
        sum = Enum.sum(durations)
        count = length(durations)
        round(sum / count)
    end
  end
end
