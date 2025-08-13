defmodule Server.Events.Router do
  @moduledoc """
  Central event routing system.

  ALL unified events flow through this router after transformation.
  This provides a single point for event distribution, batching decisions,
  and handler routing throughout the Landale system.

  ## Architecture

  The router operates as a GenServer that:
  1. Receives unified events from system boundaries
  2. Decides whether to batch or broadcast immediately
  3. Routes events to specific handlers based on type
  4. Stores events in activity log (async)

  ## Event Flow

      Transformer.from_*() → Router.route() → [BatchCollector | Immediate Broadcast] → Handlers

  ## Batching Logic

  Events are batched when:
  - They are not critical priority
  - They are high-volume types (chat messages, follows)
  - System is under normal load

  Critical events bypass batching for immediate processing.

  ## Usage

      # Route an event
      event = Event.new("channel.follow", :twitch, user_data)
      Router.route(event)

  """

  use GenServer
  require Logger

  alias Server.ActivityLog
  alias Server.Events.{BatchCollector, Event, Transformer}

  # Configurable batching settings
  @default_batch_types [
    "channel.chat.message",
    "channel.follow",
    "channel.cheer"
  ]

  # Critical events that bypass batching
  @critical_events [
    "system.startup",
    "system.shutdown",
    "system.error",
    "stream.online",
    "stream.offline",
    "obs.stream_started",
    "obs.stream_stopped"
  ]

  defstruct [
    :batch_types,
    :stats,
    :started_at
  ]

  ## Client API

  @doc "Start the event router"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Routes a unified event through the system.

  This is the main entry point for all events after transformation.
  Events are processed asynchronously to avoid blocking the caller.
  """
  @spec route(Event.t()) :: :ok
  def route(%Event{} = event) do
    GenServer.cast(__MODULE__, {:route, event})
  end

  @doc "Get current router statistics"
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc "Reset router statistics"
  @spec reset_stats() :: :ok
  def reset_stats do
    GenServer.call(__MODULE__, :reset_stats)
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    Logger.info("Event Router started", service: :event_router)

    # Subscribe to batch events from BatchCollector
    Phoenix.PubSub.subscribe(Server.PubSub, "events:batched")

    batch_types =
      Keyword.get(opts, :batch_types, @default_batch_types)

    state = %__MODULE__{
      batch_types: MapSet.new(batch_types),
      stats: initialize_stats(),
      started_at: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:route, %Event{} = event}, state) do
    # Update statistics
    updated_stats = update_route_stats(state.stats, event)

    # Route the event based on its characteristics
    handle_event_routing(event)

    {:noreply, %{state | stats: updated_stats}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at),
      events_routed: state.stats.total_events,
      events_batched: state.stats.batched_events,
      events_immediate: state.stats.immediate_events,
      critical_events: state.stats.critical_events,
      event_types: state.stats.event_type_counts,
      source_distribution: state.stats.source_counts,
      batch_types: MapSet.to_list(state.batch_types)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    updated_state = %{state | stats: initialize_stats()}
    {:reply, :ok, updated_state}
  end

  # Handle batched events coming back from BatchCollector
  @impl true
  def handle_info({:batched_event, batch_event}, state) do
    # Broadcast the batch event
    broadcast_immediate(batch_event)

    # Update batch statistics
    batch_count = get_in(batch_event.data, [:count]) || 0
    updated_stats = Map.update(state.stats, :batch_broadcasts, 1, &(&1 + 1))
    updated_stats = Map.update(updated_stats, :events_in_batches, batch_count, &(&1 + batch_count))

    {:noreply, %{state | stats: updated_stats}}
  end

  @impl true
  def handle_info(unhandled_msg, state) do
    Logger.warning("Unhandled message in EventRouter",
      message: inspect(unhandled_msg, limit: 50)
    )

    {:noreply, state}
  end

  ## Private Functions

  # Route event based on its type and priority
  defp handle_event_routing(%Event{} = event) do
    # 1. Store in activity log (async, non-blocking)
    Task.start(fn -> store_event_async(event) end)

    # 2. Determine routing strategy
    if should_batch?(event) do
      # Send to batch collector
      BatchCollector.add(event)
    else
      # Broadcast immediately
      broadcast_immediate(event)
    end

    # 3. Route to specific handlers based on event type
    route_to_specific_handlers(event)
  end

  # Determine if event should be batched
  defp should_batch?(%Event{meta: %{priority: :critical}}), do: false
  defp should_batch?(%Event{type: type}) when type in @critical_events, do: false

  defp should_batch?(%Event{type: type}) do
    # Check if this event type is configured for batching
    batch_types = get_batch_types()
    type in batch_types
  end

  # Get current batch types (could be made configurable)
  defp get_batch_types do
    @default_batch_types
  end

  # Broadcast event immediately to all subscribers
  defp broadcast_immediate(%Event{} = event) do
    # Broadcast to general events topic
    Phoenix.PubSub.broadcast(Server.PubSub, "events:all", {:unified_event, event})

    # Broadcast to source-specific topic
    Phoenix.PubSub.broadcast(Server.PubSub, "events:#{event.source}", {:unified_event, event})
  end

  # Route to specific handlers that need immediate notification
  defp route_to_specific_handlers(%Event{type: "channel.chat.message"} = event) do
    # Route to StreamProducer for emote stats and content updates
    send_to_stream_producer({:chat_message, event})
  end

  defp route_to_specific_handlers(%Event{type: "channel.subscribe"} = event) do
    # Route to StreamProducer for subscription celebrations
    send_to_stream_producer({:subscription, event})
  end

  defp route_to_specific_handlers(%Event{type: "channel.follow"} = event) do
    # Route to StreamProducer for follow notifications
    send_to_stream_producer({:follow, event})
  end

  defp route_to_specific_handlers(%Event{type: "channel.update"} = event) do
    # Route to StreamProducer for show detection
    send_to_stream_producer({:channel_update, event})
  end

  defp route_to_specific_handlers(%Event{type: "ironmon." <> _} = event) do
    # Route to StreamProducer for IronMON events
    send_to_stream_producer({:ironmon_event, event})
  end

  defp route_to_specific_handlers(_event) do
    # No specific routing needed
    :ok
  end

  # Send event to StreamProducer if it's running
  defp send_to_stream_producer(message) do
    case Process.whereis(Server.StreamProducer) do
      nil ->
        Logger.debug("StreamProducer not running, skipping specific routing")

      pid ->
        send(pid, message)
    end
  end

  # Store event in activity log asynchronously
  defp store_event_async(%Event{} = event) do
    # Check if ActivityLog module exists before trying to store
    if Code.ensure_loaded?(Server.ActivityLog) do
      try do
        # Convert Event struct to format expected by ActivityLog
        activity_log_event = Transformer.for_activity_log(event)
        ActivityLog.store_event(activity_log_event)
      rescue
        error ->
          Logger.error("Failed to store event in activity log",
            event_id: event.id,
            event_type: event.type,
            error: inspect(error)
          )
      end
    else
      # ActivityLog module not available - this is expected during testing
      Logger.debug("ActivityLog module not available, skipping event storage",
        event_id: event.id,
        event_type: event.type
      )
    end
  end

  # Statistics management
  defp initialize_stats do
    %{
      total_events: 0,
      batched_events: 0,
      immediate_events: 0,
      critical_events: 0,
      batch_broadcasts: 0,
      events_in_batches: 0,
      event_type_counts: %{},
      source_counts: %{},
      last_reset: DateTime.utc_now()
    }
  end

  defp update_route_stats(stats, %Event{} = event) do
    stats
    |> Map.update(:total_events, 1, &(&1 + 1))
    |> update_event_type_count(event.type)
    |> update_source_count(event.source)
    |> update_priority_stats(event)
    |> update_batching_stats(event)
  end

  defp update_event_type_count(stats, event_type) do
    Map.update(stats, :event_type_counts, %{event_type => 1}, fn counts ->
      Map.update(counts, event_type, 1, &(&1 + 1))
    end)
  end

  defp update_source_count(stats, source) do
    Map.update(stats, :source_counts, %{source => 1}, fn counts ->
      Map.update(counts, source, 1, &(&1 + 1))
    end)
  end

  defp update_priority_stats(stats, %Event{meta: %{priority: :critical}}) do
    Map.update(stats, :critical_events, 1, &(&1 + 1))
  end

  defp update_priority_stats(stats, _event), do: stats

  defp update_batching_stats(stats, event) do
    if should_batch?(event) do
      Map.update(stats, :batched_events, 1, &(&1 + 1))
    else
      Map.update(stats, :immediate_events, 1, &(&1 + 1))
    end
  end
end
