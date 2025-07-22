defmodule ServerWeb.EventBatcher do
  @moduledoc """
  GenServer for batching events to reduce message frequency.

  Accumulates events and flushes them when batch size is reached
  or after a timeout period. This improves performance for high-frequency
  event streams by reducing the number of WebSocket messages sent.
  """

  use GenServer

  @default_batch_size 50
  @default_flush_interval 100  # milliseconds

  defstruct [:socket, :event_name, :events, :batch_size, :flush_interval, :flush_timer]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def add_event(batcher, event) do
    GenServer.cast(batcher, {:add_event, event})
  end

  def flush(batcher) do
    GenServer.cast(batcher, :flush)
  end

  @impl true
  def init(opts) do
    socket = Keyword.fetch!(opts, :socket)
    event_name = Keyword.get(opts, :event_name, "event_batch")
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    flush_interval = Keyword.get(opts, :flush_interval, @default_flush_interval)

    state = %__MODULE__{
      socket: socket,
      event_name: event_name,
      events: [],
      batch_size: batch_size,
      flush_interval: flush_interval,
      flush_timer: schedule_flush(flush_interval)
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:add_event, event}, state) do
    events = [event | state.events]

    if length(events) >= state.batch_size do
      Process.cancel_timer(state.flush_timer)
      flush_events(state.socket, state.event_name, Enum.reverse(events))
      
      new_timer = schedule_flush(state.flush_interval)
      {:noreply, %{state | events: [], flush_timer: new_timer}}
    else
      {:noreply, %{state | events: events}}
    end
  end

  def handle_cast(:flush, state) do
    if state.events != [] do
      flush_events(state.socket, state.event_name, Enum.reverse(state.events))
    end
    
    Process.cancel_timer(state.flush_timer)
    new_timer = schedule_flush(state.flush_interval)
    {:noreply, %{state | events: [], flush_timer: new_timer}}
  end

  @impl true
  def handle_info(:flush, state) do
    if state.events != [] do
      flush_events(state.socket, state.event_name, Enum.reverse(state.events))
    end
    
    new_timer = schedule_flush(state.flush_interval)
    {:noreply, %{state | events: [], flush_timer: new_timer}}
  end

  defp flush_events(socket, event_name, events) do
    Phoenix.Channel.push(socket, event_name, %{
      events: events,
      count: length(events),
      timestamp: System.system_time(:millisecond)
    })
  end

  defp schedule_flush(interval) do
    Process.send_after(self(), :flush, interval)
  end
end