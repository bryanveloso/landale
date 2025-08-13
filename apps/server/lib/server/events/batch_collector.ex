defmodule Server.Events.BatchCollector do
  @moduledoc """
  Collects high-volume events for batch processing.

  Events are grouped by source and flushed every 50ms (default).
  Batched events are broadcast to events:batched topic.
  """

  use GenServer
  require Logger

  alias Server.Events.Event

  # Configuration
  @default_batch_window_ms 50
  @default_max_batch_size 100
  @default_max_buffer_events 1000

  defstruct [
    :batch_window_ms,
    :max_batch_size,
    :max_buffer_events,
    :buffer,
    :flush_timer_ref,
    :stats,
    :started_at
  ]

  ## Client API

  @doc "Start the batch collector"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Adds an event to the batch collector."
  @spec add(Event.t()) :: :ok
  def add(%Event{} = event) do
    GenServer.cast(__MODULE__, {:add, event})
  end

  @doc "Force immediate flush of all pending batches"
  @spec flush_now() :: :ok
  def flush_now do
    GenServer.cast(__MODULE__, :flush_now)
  end

  @doc "Get current collector statistics"
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc "Reset collector statistics"
  @spec reset_stats() :: :ok
  def reset_stats do
    GenServer.call(__MODULE__, :reset_stats)
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    Logger.info("Event BatchCollector started", service: :batch_collector)

    batch_window_ms = Keyword.get(opts, :batch_window_ms, @default_batch_window_ms)
    max_batch_size = Keyword.get(opts, :max_batch_size, @default_max_batch_size)
    max_buffer_events = Keyword.get(opts, :max_buffer_events, @default_max_buffer_events)

    state = %__MODULE__{
      batch_window_ms: batch_window_ms,
      max_batch_size: max_batch_size,
      max_buffer_events: max_buffer_events,
      buffer: %{},
      flush_timer_ref: nil,
      stats: initialize_stats(),
      started_at: DateTime.utc_now()
    }

    # Schedule first flush
    timer_ref = schedule_next_flush(batch_window_ms)
    {:ok, %{state | flush_timer_ref: timer_ref}}
  end

  @impl true
  def handle_cast({:add, %Event{} = event}, state) do
    # Check buffer size limits
    total_buffered = count_buffered_events(state.buffer)

    if total_buffered >= state.max_buffer_events do
      Logger.warning("BatchCollector buffer full, dropping event",
        buffered_count: total_buffered,
        max_buffer: state.max_buffer_events,
        event_type: event.type,
        event_source: event.source
      )

      # Update drop statistics
      updated_stats = Map.update(state.stats, :events_dropped, 1, &(&1 + 1))
      {:noreply, %{state | stats: updated_stats}}
    else
      # Add event to appropriate buffer
      source_key = event.source

      updated_buffer =
        Map.update(
          state.buffer,
          source_key,
          [event],
          fn events -> [event | events] end
        )

      # Update statistics
      updated_stats = Map.update(state.stats, :events_added, 1, &(&1 + 1))

      {:noreply, %{state | buffer: updated_buffer, stats: updated_stats}}
    end
  end

  @impl true
  def handle_cast(:flush_now, state) do
    # Cancel current timer
    if state.flush_timer_ref do
      Process.cancel_timer(state.flush_timer_ref)
    end

    # Perform flush
    updated_state = perform_flush(state)

    # Schedule next flush
    timer_ref = schedule_next_flush(state.batch_window_ms)
    {:noreply, %{updated_state | flush_timer_ref: timer_ref}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at),
      batch_window_ms: state.batch_window_ms,
      max_batch_size: state.max_batch_size,
      max_buffer_events: state.max_buffer_events,
      current_buffered: count_buffered_events(state.buffer),
      buffer_by_source: count_buffered_by_source(state.buffer),
      events_added: state.stats.events_added,
      batches_created: state.stats.batches_created,
      events_batched: state.stats.events_batched,
      events_dropped: state.stats.events_dropped,
      empty_flushes: state.stats.empty_flushes
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    updated_state = %{state | stats: initialize_stats()}
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_info(:flush, state) do
    # Perform the flush
    updated_state = perform_flush(state)

    # Schedule next flush
    timer_ref = schedule_next_flush(state.batch_window_ms)
    {:noreply, %{updated_state | flush_timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(unhandled_msg, state) do
    Logger.warning("Unhandled message in BatchCollector",
      message: inspect(unhandled_msg, limit: 50)
    )

    {:noreply, state}
  end

  ## Private Functions

  # Perform the actual flush operation
  defp perform_flush(state) do
    if map_size(state.buffer) == 0 do
      # Nothing to flush
      updated_stats = Map.update(state.stats, :empty_flushes, 1, &(&1 + 1))
      %{state | stats: updated_stats}
    else
      # Process each source's events
      {batches_created, events_batched} = flush_all_sources(state.buffer, state.max_batch_size)

      # Update statistics
      updated_stats =
        state.stats
        |> Map.update(:batches_created, batches_created, &(&1 + batches_created))
        |> Map.update(:events_batched, events_batched, &(&1 + events_batched))

      # Clear the buffer
      %{state | buffer: %{}, stats: updated_stats}
    end
  end

  # Flush events from all sources
  defp flush_all_sources(buffer, max_batch_size) do
    {total_batches, total_events} =
      Enum.reduce(buffer, {0, 0}, fn {source, events}, {batch_count, event_count} ->
        if length(events) > 0 do
          {batches, events_in_batches} = flush_source_events(source, events, max_batch_size)
          {batch_count + batches, event_count + events_in_batches}
        else
          {batch_count, event_count}
        end
      end)

    {total_batches, total_events}
  end

  # Flush events for a specific source
  defp flush_source_events(source, events, max_batch_size) do
    # Events are stored in reverse chronological order, so reverse for correct order
    chronological_events = Enum.reverse(events)

    # Split into batches if needed
    batches = Enum.chunk_every(chronological_events, max_batch_size)

    batches_created =
      Enum.reduce(batches, 0, fn batch_events, count ->
        create_and_broadcast_batch(source, batch_events)
        count + 1
      end)

    total_events = length(chronological_events)
    {batches_created, total_events}
  end

  # Create a batch event and broadcast it
  defp create_and_broadcast_batch(source, events) when length(events) > 0 do
    batch_event = Event.create_batch(events, source: source)

    # Broadcast to the events:batched topic for the Router to pick up
    Phoenix.PubSub.broadcast(Server.PubSub, "events:batched", {:batched_event, batch_event})

    Logger.debug("Batch event created",
      source: source,
      event_count: length(events),
      batch_id: batch_event.id
    )
  end

  defp create_and_broadcast_batch(_source, []) do
    # No events to batch
    :ok
  end

  # Schedule the next flush timer
  defp schedule_next_flush(batch_window_ms) do
    Process.send_after(self(), :flush, batch_window_ms)
  end

  # Count total events in all buffers
  defp count_buffered_events(buffer) do
    buffer
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  # Count events by source
  defp count_buffered_by_source(buffer) do
    Map.new(buffer, fn {source, events} ->
      {source, length(events)}
    end)
  end

  # Initialize statistics tracking
  defp initialize_stats do
    %{
      events_added: 0,
      batches_created: 0,
      events_batched: 0,
      events_dropped: 0,
      empty_flushes: 0,
      last_reset: DateTime.utc_now()
    }
  end
end
