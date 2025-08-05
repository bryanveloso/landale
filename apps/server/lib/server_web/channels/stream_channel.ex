defmodule ServerWeb.StreamChannel do
  @moduledoc """
  Unified coordination channel for all overlay state management.

  Handles the omnibar revival with priority-based content coordination:
  - Show detection and transitions
  - Priority interrupt management (alerts > sub train > ticker)
  - Real-time content streaming to overlays
  """

  use ServerWeb.ChannelBase

  alias Server.StreamProducer

  @impl true
  def join("stream:overlays", payload, socket) do
    socket = setup_correlation_id(socket)

    Logger.info("Stream overlays channel joined",
      correlation_id: socket.assigns.correlation_id
    )

    # Track this overlay connection
    track_overlay_connection(socket, payload)

    # Subscribe to stream events
    Phoenix.PubSub.subscribe(Server.PubSub, "stream:updates")

    # Send initial state after join completes
    send_after_join(socket, :after_join)

    {:ok, socket}
  end

  @impl true
  def join("stream:queue", _payload, socket) do
    socket = setup_correlation_id(socket)

    Logger.info("Stream queue channel joined",
      correlation_id: socket.assigns.correlation_id
    )

    # Subscribe to queue events (same pubsub topic as overlays for now)
    Phoenix.PubSub.subscribe(Server.PubSub, "stream:updates")

    # Send initial queue state after join completes
    send_after_join(socket, :after_queue_join)

    {:ok, socket}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    handle_ping(payload, socket)
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
  def handle_in("remove_queue_item", payload, socket) do
    Logger.info("Queue item removal requested",
      payload: inspect(payload),
      correlation_id: socket.assigns.correlation_id
    )

    case validate_queue_item_removal(payload) do
      {:ok, item_id} ->
        # This maps to removing an interrupt by ID
        StreamProducer.remove_interrupt(item_id)
        {:reply, ResponseBuilder.success(%{operation: "item_removed", id: item_id}), socket}

      {:error, reason} ->
        Logger.warning("Invalid queue item removal payload",
          payload: inspect(payload),
          error: reason,
          correlation_id: socket.assigns.correlation_id
        )

        {:reply, ResponseBuilder.error("validation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("force_content", %{"type" => content_type, "data" => data, "duration" => duration}, socket) do
    Logger.info("Takeover requested",
      type: content_type,
      duration: duration,
      correlation_id: socket.assigns.correlation_id
    )

    # Send takeover to StreamProducer
    StreamProducer.force_content(content_type, data, duration)
    {:reply, ResponseBuilder.success(%{operation: "override_sent", type: content_type}), socket}
  end

  @impl true
  def handle_in("takeover", payload, socket) do
    Logger.info("Takeover handler called",
      payload: inspect(payload),
      correlation_id: socket.assigns.correlation_id
    )

    case validate_takeover(payload) do
      {:ok, validated_payload} ->
        %{type: takeover_type, message: message, duration: duration} = validated_payload

        Logger.info("Takeover full-screen requested",
          type: takeover_type,
          message: message,
          duration: duration,
          correlation_id: socket.assigns.correlation_id
        )

        # Broadcast takeover to all overlay clients
        Phoenix.PubSub.broadcast(
          Server.PubSub,
          "stream:updates",
          {:takeover,
           %{
             type: takeover_type,
             message: message,
             duration: duration,
             timestamp: DateTime.utc_now()
           }}
        )

        {:reply, ResponseBuilder.success(%{operation: "takeover_sent", type: takeover_type}), socket}

      {:error, reason} ->
        Logger.warning("Invalid takeover payload",
          payload: inspect(payload),
          error: reason,
          correlation_id: socket.assigns.correlation_id
        )

        {:reply, ResponseBuilder.error("validation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("takeover_clear", payload, socket) do
    Logger.info("Takeover clear handler called",
      payload: inspect(payload),
      correlation_id: socket.assigns.correlation_id
    )

    # Broadcast takeover clear to all overlay clients
    Phoenix.PubSub.broadcast(
      Server.PubSub,
      "stream:updates",
      {:takeover_clear, %{timestamp: DateTime.utc_now()}}
    )

    {:reply, ResponseBuilder.success(%{operation: "takeover_cleared"}), socket}
  end

  @impl true
  def handle_in("update_channel_info", payload, socket) do
    Logger.info("Channel info update requested",
      payload: inspect(payload),
      correlation_id: socket.assigns.correlation_id
    )

    case validate_channel_info_update(payload) do
      {:ok, channel_data} ->
        # Call Twitch API to update channel information
        case Server.Services.Twitch.ApiClient.modify_channel_information(channel_data) do
          :ok ->
            {:reply, ResponseBuilder.success(%{operation: "channel_info_updated"}), socket}

          {:error, reason} ->
            Logger.warning("Failed to update channel information",
              error: reason,
              correlation_id: socket.assigns.correlation_id
            )

            {:reply, ResponseBuilder.error("api_error", reason), socket}
        end

      {:error, reason} ->
        Logger.warning("Invalid channel info update payload",
          payload: inspect(payload),
          error: reason,
          correlation_id: socket.assigns.correlation_id
        )

        {:reply, ResponseBuilder.error("validation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("get_channel_info", _payload, socket) do
    Logger.info("Channel info requested",
      correlation_id: socket.assigns.correlation_id
    )

    case Server.Services.Twitch.ApiClient.get_channel_information() do
      {:ok, channel_info} ->
        {:reply, ResponseBuilder.success(channel_info), socket}

      {:error, reason} ->
        Logger.warning("Failed to get channel information",
          error: reason,
          correlation_id: socket.assigns.correlation_id
        )

        {:reply, ResponseBuilder.error("api_error", reason), socket}
    end
  end

  @impl true
  def handle_in("search_categories", %{"query" => query}, socket) do
    Logger.info("Category search requested",
      query: query,
      correlation_id: socket.assigns.correlation_id
    )

    case Server.Services.Twitch.ApiClient.search_categories(query) do
      {:ok, categories} ->
        {:reply, ResponseBuilder.success(categories), socket}

      {:error, reason} ->
        Logger.warning("Failed to search categories",
          query: query,
          error: reason,
          correlation_id: socket.assigns.correlation_id
        )

        {:reply, ResponseBuilder.error("api_error", reason), socket}
    end
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    log_unhandled_message(event, payload, socket)
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
        Logger.error("Failed to get StreamProducer state, using fallback", error: inspect(error))
        # Send centralized fallback state
        fallback_state = Server.ContentFallbacks.get_fallback_layer_state()
        push(socket, "stream_state", fallback_state)
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
        Logger.error("Failed to get queue state, using fallback", error: inspect(error))
        # Send centralized fallback queue state
        fallback_queue_state = Server.ContentFallbacks.get_fallback_queue_state()
        push(socket, "queue_state", fallback_queue_state)
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

  # Handle takeover overlay events
  @impl true
  def handle_info({:takeover, takeover_data}, socket) do
    push(socket, "takeover", %{
      type: takeover_data.type,
      message: takeover_data.message,
      duration: takeover_data.duration,
      timestamp: takeover_data.timestamp
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:takeover_clear, clear_data}, socket) do
    push(socket, "takeover_clear", %{
      timestamp: clear_data.timestamp
    })

    {:noreply, socket}
  end

  # Catch-all handler to prevent crashes from unexpected messages
  @impl true
  def handle_info(unhandled_msg, socket) do
    Logger.warning("Unhandled message in #{__MODULE__}",
      message: inspect(unhandled_msg),
      topic: socket.topic
    )

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
      metadata: Map.get(state, :metadata, %{last_updated: DateTime.utc_now(), state_version: state.version})
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
        last_processed: Map.get(state, :metadata, %{last_updated: DateTime.utc_now()}).last_updated
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
  defp convert_interrupt_type_to_queue_type(_type), do: "ticker"

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

  # Simple validation - just ensure required fields exist
  defp validate_takeover(%{"type" => type, "message" => message} = payload)
       when is_binary(type) and is_binary(message) do
    duration = Map.get(payload, "duration", 10_000)
    {:ok, %{type: type, message: message, duration: duration}}
  end

  defp validate_takeover(%{"type" => type} = payload) when is_binary(type) do
    # screen-cover doesn't require message
    if type == "screen-cover" do
      duration = Map.get(payload, "duration", 10_000)
      {:ok, %{type: type, message: "", duration: duration}}
    else
      {:error, "Missing required field: message"}
    end
  end

  defp validate_takeover(_), do: {:error, "Missing required field: type"}

  defp validate_queue_item_removal(%{"id" => id}) when is_binary(id) and id != "" do
    {:ok, id}
  end

  defp validate_queue_item_removal(_), do: {:error, "Missing required field: id"}

  defp validate_channel_info_update(payload) when is_map(payload) do
    valid_fields = [:game_id, :broadcaster_language, :title, :delay, :tags, :branded_content]

    # Convert string keys to atoms and filter valid fields
    channel_data =
      payload
      |> Enum.reduce([], fn {key, value}, acc ->
        atom_key = if is_binary(key), do: String.to_existing_atom(key), else: key

        if atom_key in valid_fields and not is_nil(value) do
          [{atom_key, value} | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    if Enum.empty?(channel_data) do
      {:error, "At least one valid field must be provided: #{Enum.join(valid_fields, ", ")}"}
    else
      {:ok, channel_data}
    end
  rescue
    ArgumentError ->
      {:error, "Invalid field names provided"}
  end

  defp validate_channel_info_update(_), do: {:error, "Payload must be a map"}

  # Overlay tracking functions
  defp track_overlay_connection(socket, payload) do
    table_name = :overlay_channel_tracker

    # Ensure table exists
    if :ets.whereis(table_name) == :undefined do
      :ets.new(table_name, [:set, :public, :named_table])
    end

    # Store overlay info
    overlay_info = %{
      name: Map.get(payload, "overlay_type", "Takeover"),
      joined_at: DateTime.utc_now(),
      socket_id: socket.assigns.correlation_id
    }

    :ets.insert(table_name, {socket.assigns.correlation_id, overlay_info})
  end

  @impl true
  def terminate(_reason, socket) do
    # Remove from tracking when channel terminates
    table_name = :overlay_channel_tracker

    if :ets.whereis(table_name) != :undefined do
      :ets.delete(table_name, socket.assigns.correlation_id)
    end

    :ok
  end
end
