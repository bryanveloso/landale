defmodule Server.Events.BatchPublisher do
  @moduledoc """
  Event batching system for high-frequency dashboard updates.

  Accumulates events in 50ms windows and publishes them as batches to reduce
  WebSocket message overhead for dashboard clients. Critical events bypass
  batching for immediate delivery.

  Optimized for single-user streaming system with moderate event throughput.
  """

  use GenServer
  require Logger

  @batch_window_ms 50
  @batch_table_name :event_batch_buffer
  @critical_events [
    # Connection events
    "connection_lost",
    "connection_failed",
    "websocket_disconnected",
    "authentication_failed",
    # Streaming events
    "stream_stopped",
    "recording_stopped",
    "stream_started",
    "recording_started",
    # Service events
    "service_error",
    "service_unavailable",
    "startup",
    "shutdown",
    # Health events
    "unhealthy",
    "degraded",
    "service_down"
  ]

  defstruct [
    :flush_timer,
    :stats
  ]

  ## Client API

  @doc """
  Starts the batch publisher.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Publishes an event, either immediately (critical) or batched (regular).

  ## Parameters
  - `topic` - PubSub topic
  - `event` - Event data
  - `opts` - Options including :priority (:critical or :normal)
  """
  @spec publish(binary(), map(), keyword()) :: :ok
  def publish(topic, event, opts \\ []) do
    priority = Keyword.get(opts, :priority, :normal)

    case should_batch?(event, priority) do
      true ->
        GenServer.cast(__MODULE__, {:batch_event, topic, event})

      false ->
        # Publish immediately for critical events
        Phoenix.PubSub.broadcast(Server.PubSub, topic, event)
        :ok
    end
  end

  @doc """
  Gets batching statistics for monitoring.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Forces immediate flush of all batched events.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.cast(__MODULE__, :force_flush)
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for event batching
    :ets.new(@batch_table_name, [:named_table, :bag, :public])

    # Schedule first flush
    timer_ref = schedule_flush()

    Logger.info("Event batch publisher started", window_ms: @batch_window_ms)

    {:ok,
     %__MODULE__{
       flush_timer: timer_ref,
       stats: %{
         batches_sent: 0,
         events_batched: 0,
         events_immediate: 0,
         last_batch_size: 0
       }
     }}
  end

  @impl true
  def handle_cast({:batch_event, topic, event}, state) do
    # Add event to ETS buffer
    :ets.insert(@batch_table_name, {topic, event, System.monotonic_time(:millisecond)})

    # Update stats
    new_stats = Map.update!(state.stats, :events_batched, &(&1 + 1))

    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_cast(:force_flush, state) do
    new_state = flush_batched_events(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # Include current buffer size in stats
    buffer_size = :ets.info(@batch_table_name, :size)
    stats_with_buffer = Map.put(state.stats, :current_buffer_size, buffer_size)

    {:reply, stats_with_buffer, state}
  end

  @impl true
  def handle_info(:flush_events, state) do
    # Flush batched events and schedule next flush
    new_state = flush_batched_events(state)
    timer_ref = schedule_flush()

    {:noreply, %{new_state | flush_timer: timer_ref}}
  end

  ## Private Functions

  defp should_batch?(event, priority) do
    case priority do
      :critical -> false
      :normal -> not critical_event?(event)
    end
  end

  defp critical_event?(%{type: event_type}) when is_binary(event_type) do
    event_type in @critical_events
  end

  defp critical_event?(_), do: false

  defp schedule_flush do
    Process.send_after(self(), :flush_events, @batch_window_ms)
  end

  defp prepare_event_for_batch({_topic, event, timestamp}) do
    # Extract the actual event data from the tuple if needed
    case event do
      {event_type, event_map} when is_non_struct_map(event_map) ->
        Map.put(event_map, :event_type, event_type)
        |> Map.put(:batch_timestamp, timestamp)

      event_map when is_non_struct_map(event_map) ->
        Map.put(event_map, :batch_timestamp, timestamp)

      _ ->
        %{event: event, batch_timestamp: timestamp}
    end
  end

  defp flush_batched_events(state) do
    # Get all events from ETS buffer
    all_events = :ets.tab2list(@batch_table_name)
    :ets.delete_all_objects(@batch_table_name)

    if length(all_events) > 0 do
      # Group events by topic
      events_by_topic =
        all_events
        |> Enum.group_by(fn {topic, _event, _timestamp} -> topic end)
        |> Enum.map(fn {topic, events} ->
          event_data = Enum.map(events, &prepare_event_for_batch/1)
          {topic, event_data}
        end)

      # Publish batches
      Enum.each(events_by_topic, fn {topic, events} ->
        batch_event = %{
          type: :event_batch,
          events: events,
          batch_size: length(events),
          batch_id: Server.CorrelationIdPool.get(),
          timestamp: System.system_time(:second)
        }

        Phoenix.PubSub.broadcast(Server.PubSub, topic, {:event_batch, batch_event})

        Logger.debug("Published event batch",
          topic: topic,
          size: length(events),
          batch_id: batch_event.batch_id,
          event_types: events |> Enum.map(&Map.get(&1, :type, "unknown")) |> Enum.uniq()
        )
      end)

      # Update stats
      total_events = length(all_events)
      batch_count = length(events_by_topic)

      new_stats =
        state.stats
        |> Map.update!(:batches_sent, &(&1 + batch_count))
        |> Map.put(:last_batch_size, total_events)

      %{state | stats: new_stats}
    else
      # No events to flush
      state
    end
  end
end
