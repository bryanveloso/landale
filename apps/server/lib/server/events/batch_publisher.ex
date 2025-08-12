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
    :stats,
    event_buffer: %{}
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
  - `opts` - Options including :priority (:critical or :normal), :wrapper (event wrapper atom)
  """
  @spec publish(binary(), map(), keyword()) :: :ok
  def publish(topic, event, opts \\ []) do
    priority = Keyword.get(opts, :priority, :normal)
    wrapper = Keyword.get(opts, :wrapper)

    case should_batch?(event, priority) do
      true ->
        GenServer.cast(__MODULE__, {:batch_event, topic, event, wrapper})

      false ->
        # Publish immediately for critical events with proper wrapper
        wrapped_event = if wrapper, do: {wrapper, event}, else: event
        Phoenix.PubSub.broadcast(Server.PubSub, topic, wrapped_event)
        GenServer.cast(__MODULE__, :increment_immediate_events)
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
       },
       event_buffer: %{}
     }}
  end

  @impl true
  def handle_cast({:batch_event, topic, event, wrapper}, state) do
    # Add event to internal buffer with timestamp and wrapper info
    timestamp = System.monotonic_time(:millisecond)
    event_with_meta = {event, timestamp, wrapper}

    # Update event buffer - append new event to topic's event list
    current_events = Map.get(state.event_buffer, topic, [])
    new_buffer = Map.put(state.event_buffer, topic, [event_with_meta | current_events])

    # Update stats
    new_stats = Map.update!(state.stats, :events_batched, &(&1 + 1))

    {:noreply, %{state | event_buffer: new_buffer, stats: new_stats}}
  end

  @impl true
  def handle_cast(:force_flush, state) do
    new_state = flush_batched_events(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:increment_immediate_events, state) do
    new_stats = Map.update!(state.stats, :events_immediate, &(&1 + 1))
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # Include current buffer size in stats - count total events across all topics
    buffer_size =
      state.event_buffer
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.sum()

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

  defp prepare_event_for_batch({event_map, timestamp, _wrapper}) when is_map(event_map) do
    Map.put(event_map, :batch_timestamp, timestamp)
  end

  defp flush_batched_events(state) do
    # Get all events from internal buffer
    events_by_topic = state.event_buffer

    if map_size(events_by_topic) > 0 do
      # Process each topic's events
      processed_topics =
        events_by_topic
        |> Enum.map(fn {topic, events} ->
          # Events are in reverse order (newest first), so reverse for chronological order
          event_data =
            events
            |> Enum.reverse()
            |> Enum.map(&prepare_event_for_batch/1)

          {topic, event_data}
        end)

      # Publish batches
      Enum.each(processed_topics, fn {topic, event_data} ->
        batch_event = %{
          type: :event_batch,
          events: event_data,
          batch_size: length(event_data),
          batch_id: Server.CorrelationIdPool.get(),
          timestamp: System.system_time(:second)
        }

        Phoenix.PubSub.broadcast(Server.PubSub, topic, {:event_batch, batch_event})

        Logger.debug("Published event batch",
          topic: topic,
          size: length(event_data),
          batch_id: batch_event.batch_id,
          event_types: event_data |> Enum.map(&Map.get(&1, :type, "unknown")) |> Enum.uniq()
        )
      end)

      # Update stats - count total events across all topics
      total_events =
        events_by_topic
        |> Map.values()
        |> Enum.map(&length/1)
        |> Enum.sum()

      batch_count = map_size(events_by_topic)

      new_stats =
        state.stats
        |> Map.update!(:batches_sent, &(&1 + batch_count))
        |> Map.put(:last_batch_size, total_events)

      # Clear the event buffer for next batch
      %{state | stats: new_stats, event_buffer: %{}}
    else
      # No events to flush
      state
    end
  end
end
