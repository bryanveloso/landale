defmodule ServerWeb.StreamChannel do
  @moduledoc """
  Unified coordination channel for all overlay state management.

  Handles the omnibar revival with priority-based content coordination:
  - Show detection and transitions
  - Priority interrupt management (alerts > sub train > ticker)
  - Real-time content streaming to overlays
  """

  use ServerWeb, :channel

  require Logger

  alias Server.StreamProducer

  @impl true
  def join("stream:overlays", _payload, socket) do
    Logger.info("Stream overlays channel joined",
      correlation_id: socket.assigns.correlation_id
    )

    # Subscribe to stream events
    Phoenix.PubSub.subscribe(Server.PubSub, "stream:updates")

    # Send initial state after join completes
    send(self(), :after_join)

    {:ok, socket}
  end

  @impl true
  def join("stream:queue", _payload, socket) do
    Logger.info("Stream queue channel joined",
      correlation_id: socket.assigns.correlation_id
    )

    # Subscribe to queue events (same pubsub topic as overlays for now)
    Phoenix.PubSub.subscribe(Server.PubSub, "stream:updates")

    # Send initial queue state after join completes
    send(self(), :after_queue_join)

    {:ok, socket}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: true, timestamp: System.system_time(:second)}}, socket}
  end

  @impl true
  def handle_in("request_state", _payload, socket) do
    current_state = StreamProducer.get_current_state()
    push(socket, "stream_state", format_state_for_client(current_state))
    {:noreply, socket}
  end

  @impl true
  def handle_in("request_queue_state", _payload, socket) do
    current_state = StreamProducer.get_current_state()
    push(socket, "queue_state", format_queue_state_for_client(current_state))
    {:noreply, socket}
  end

  @impl true
  def handle_in("clear_queue", _payload, socket) do
    Logger.info("Queue clear requested", correlation_id: socket.assigns.correlation_id)
    # For now, don't implement this as it doesn't align with interrupt model
    # Clearing all interrupts could be dangerous in a production stream
    {:reply, {:error, %{reason: "queue_clear_not_supported"}}, socket}
  end

  @impl true
  def handle_in("remove_queue_item", %{"id" => item_id}, socket) do
    Logger.info("Queue item removal requested",
      item_id: item_id,
      correlation_id: socket.assigns.correlation_id
    )

    # This maps to removing an interrupt by ID
    StreamProducer.remove_interrupt(item_id)
    {:reply, {:ok, %{status: "item_removed", id: item_id}}, socket}
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    Logger.warning("Unhandled stream channel message",
      event: event,
      payload: payload,
      correlation_id: socket.assigns.correlation_id
    )

    {:noreply, socket}
  end

  # Handle after join to send initial state
  @impl true
  def handle_info(:after_join, socket) do
    try do
      current_state = StreamProducer.get_current_state()
      push(socket, "stream_state", format_state_for_client(current_state))
    rescue
      error ->
        Logger.error("Failed to get StreamProducer state", error: inspect(error))
        # Send default state
        push(socket, "stream_state", %{
          current_show: :variety,
          active_content: nil,
          priority_level: :ticker,
          interrupt_stack: [],
          ticker_rotation: [],
          metadata: %{
            last_updated: DateTime.utc_now(),
            state_version: 0
          }
        })
    end

    {:noreply, socket}
  end

  # Handle after queue join to send initial queue state
  @impl true
  def handle_info(:after_queue_join, socket) do
    try do
      current_state = StreamProducer.get_current_state()
      queue_state = format_queue_state_for_client(current_state)
      push(socket, "queue_state", queue_state)
    rescue
      error ->
        Logger.error("Failed to get queue state", error: inspect(error))
        # Send default queue state
        push(socket, "queue_state", %{
          queue: [],
          active_content: nil,
          metrics: %{
            total_items: 0,
            active_items: 0,
            pending_items: 0,
            average_wait_time: 0,
            last_processed: nil
          },
          is_processing: false
        })
    end

    {:noreply, socket}
  end

  # Handle stream updates from StreamProducer
  @impl true
  def handle_info({:stream_update, state}, socket) do
    # Send overlay state to stream:overlays channels
    if socket.topic == "stream:overlays" do
      push(socket, "stream_state", format_state_for_client(state))
    end

    # Send queue state to stream:queue channels
    if socket.topic == "stream:queue" do
      push(socket, "queue_state", format_queue_state_for_client(state))
    end

    {:noreply, socket}
  end

  # Handle show changes from Twitch EventSub
  @impl true
  def handle_info({:show_change, show_data}, socket) do
    push(socket, "show_changed", %{
      show: show_data.show,
      game: show_data.game,
      changed_at: show_data.changed_at
    })

    {:noreply, socket}
  end

  # Handle priority interrupts (alerts, sub trains, etc.)
  @impl true
  def handle_info({:priority_interrupt, interrupt_data}, socket) do
    push(socket, "interrupt", %{
      type: interrupt_data.type,
      priority: interrupt_data.priority,
      data: interrupt_data.data,
      duration: interrupt_data.duration,
      id: interrupt_data.id
    })

    {:noreply, socket}
  end

  # Handle real-time content updates (emote increments, etc.)
  @impl true
  def handle_info({:content_update, update_data}, socket) do
    push(socket, "content_update", %{
      type: update_data.type,
      data: update_data.data,
      timestamp: update_data.timestamp
    })

    {:noreply, socket}
  end

  # Private helper functions

  defp format_state_for_client(state) do
    %{
      current_show: state.current_show,
      active_content: format_active_content(state.active_content),
      priority_level: get_priority_level(state),
      interrupt_stack: format_interrupt_stack(state.interrupt_stack),
      ticker_rotation: state.ticker_rotation,
      metadata: %{
        last_updated: DateTime.utc_now(),
        state_version: state.version
      }
    }
  end

  defp format_queue_state_for_client(state) do
    # Transform interrupt_stack to queue items format
    queue_items =
      Enum.with_index(state.interrupt_stack, fn interrupt, position ->
        %{
          id: interrupt.id,
          type: convert_interrupt_type_to_queue_type(interrupt.type),
          priority: interrupt.priority,
          content_type: interrupt.type,
          data: interrupt.data,
          duration: Map.get(interrupt, :duration),
          started_at: interrupt.started_at,
          status: determine_queue_item_status(interrupt, state.active_content),
          position: position
        }
      end)

    %{
      queue: queue_items,
      active_content: format_active_content(state.active_content),
      metrics: %{
        total_items: length(state.interrupt_stack) + if(state.active_content, do: 1, else: 0),
        active_items: if(state.active_content, do: 1, else: 0),
        pending_items: length(state.interrupt_stack),
        average_wait_time: calculate_average_wait_time(state.interrupt_stack),
        last_processed: state.metadata.last_updated
      },
      is_processing: state.active_content != nil
    }
  end

  defp format_active_content(nil), do: nil

  defp format_active_content(content) do
    %{
      type: content.type,
      data: content.data,
      priority: content.priority,
      duration: Map.get(content, :duration),
      started_at: content.started_at
    }
  end

  defp format_interrupt_stack(stack) do
    Enum.map(stack, fn interrupt ->
      %{
        type: interrupt.type,
        priority: interrupt.priority,
        id: interrupt.id,
        started_at: interrupt.started_at,
        duration: interrupt.duration
      }
    end)
  end

  defp get_priority_level(state) do
    cond do
      has_alerts?(state.interrupt_stack) -> :alert
      has_sub_train?(state.interrupt_stack) -> :sub_train
      true -> :ticker
    end
  end

  defp has_alerts?(stack) do
    Enum.any?(stack, fn interrupt -> interrupt.type == :alert end)
  end

  defp has_sub_train?(stack) do
    Enum.any?(stack, fn interrupt -> interrupt.type == :sub_train end)
  end

  # Queue-specific helper functions

  defp convert_interrupt_type_to_queue_type(:alert), do: "alert"
  defp convert_interrupt_type_to_queue_type(:sub_train), do: "sub_train"
  defp convert_interrupt_type_to_queue_type(:manual_override), do: "manual_override"
  defp convert_interrupt_type_to_queue_type(type), do: "ticker"

  defp determine_queue_item_status(interrupt, active_content) do
    if active_content && active_content.id == interrupt.id do
      "active"
    else
      "pending"
    end
  end

  defp calculate_average_wait_time(interrupt_stack) do
    if Enum.empty?(interrupt_stack) do
      0
    else
      now = DateTime.utc_now()

      total_wait_time =
        interrupt_stack
        |> Enum.map(fn interrupt ->
          DateTime.diff(now, interrupt.started_at, :millisecond)
        end)
        |> Enum.sum()

      div(total_wait_time, length(interrupt_stack))
    end
  end
end
