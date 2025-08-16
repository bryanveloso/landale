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

    # Subscribe to unified events topic and filter for stream events
    Phoenix.PubSub.subscribe(Server.PubSub, "events")

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

    # Subscribe to unified events topic and filter for stream events
    Phoenix.PubSub.subscribe(Server.PubSub, "events")

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
    current_state = get_stream_producer_state()

    if current_state do
      push(socket, "stream_state", format_state_for_client(current_state))
    else
      fallback_state = Server.ContentFallbacks.get_fallback_layer_state()
      push(socket, "stream_state", fallback_state)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("request_queue_state", _payload, socket) do
    current_state = get_stream_producer_state()

    if current_state do
      push(socket, "queue_state", format_queue_state_for_client(current_state))
    else
      push(socket, "queue_state", %{queue: [], current: nil})
    end

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
        try do
          GenServer.call(StreamProducer, {:remove_interrupt, item_id}, 5000)
          {:ok, response} = ResponseBuilder.success(%{operation: "item_removed", id: item_id})
          {:reply, {:ok, response}, socket}
        rescue
          _ ->
            {:error, response} =
              ResponseBuilder.error("stream_producer_unavailable", "StreamProducer service is not available")

            {:reply, {:error, response}, socket}
        catch
          :exit, {:noproc, _} ->
            {:error, response} =
              ResponseBuilder.error("stream_producer_not_started", "StreamProducer service is not started")

            {:reply, {:error, response}, socket}
        end

      {:error, reason} ->
        Logger.warning("Invalid queue item removal payload",
          payload: inspect(payload),
          error: reason,
          correlation_id: socket.assigns.correlation_id
        )

        {:error, response} = ResponseBuilder.error("validation_failed", reason)
        {:reply, {:error, response}, socket}
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
    {:ok, response} = ResponseBuilder.success(%{operation: "override_sent", type: content_type})
    {:reply, {:ok, response}, socket}
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

        # Process takeover through unified event system
        Server.Events.process_event("stream.takeover_started", %{
          takeover_type: takeover_type,
          message: message,
          duration: duration,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

        {:ok, response} = ResponseBuilder.success(%{operation: "takeover_sent", type: takeover_type})
        {:reply, {:ok, response}, socket}

      {:error, reason} ->
        Logger.warning("Invalid takeover payload",
          payload: inspect(payload),
          error: reason,
          correlation_id: socket.assigns.correlation_id
        )

        {:error, response} = ResponseBuilder.error("validation_failed", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("takeover_clear", payload, socket) do
    Logger.info("Takeover clear handler called",
      payload: inspect(payload),
      correlation_id: socket.assigns.correlation_id
    )

    # Process takeover clear through unified event system
    Server.Events.process_event("stream.takeover_cleared", %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:ok, response} = ResponseBuilder.success(%{operation: "takeover_cleared"})
    {:reply, {:ok, response}, socket}
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
            {:ok, response} = ResponseBuilder.success(%{operation: "channel_info_updated"})
            {:reply, {:ok, response}, socket}

          {:error, reason} ->
            Logger.warning("Failed to update channel information",
              error: inspect(reason),
              correlation_id: socket.assigns.correlation_id
            )

            {:error, response} = ResponseBuilder.error("api_error", inspect(reason))
            {:reply, {:error, response}, socket}
        end

      {:error, reason} ->
        Logger.warning("Invalid channel info update payload",
          payload: inspect(payload),
          error: reason,
          correlation_id: socket.assigns.correlation_id
        )

        {:error, response} = ResponseBuilder.error("validation_failed", reason)
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("get_channel_info", _payload, socket) do
    Logger.info("Channel info requested",
      correlation_id: socket.assigns.correlation_id
    )

    case Server.Services.Twitch.ApiClient.get_channel_information() do
      {:ok, %{"data" => [channel_info | _]}} ->
        # Extract first channel info from Twitch API response array
        {:ok, response} = ResponseBuilder.success(channel_info)
        {:reply, {:ok, response}, socket}

      {:ok, %{"data" => []}} ->
        Logger.warning("No channel information found",
          correlation_id: socket.assigns.correlation_id
        )

        {:error, response} = ResponseBuilder.error("no_data", "No channel information available")
        {:reply, {:error, response}, socket}

      {:ok, unexpected_response} ->
        Logger.warning("DEBUG: Unexpected API response format",
          correlation_id: socket.assigns.correlation_id,
          response: inspect(unexpected_response, limit: :infinity)
        )

        {:error, response} = ResponseBuilder.error("unexpected_format", "Unexpected API response format")
        {:reply, {:error, response}, socket}

      {:error, reason} ->
        Logger.warning("Failed to get channel information",
          error: inspect(reason),
          correlation_id: socket.assigns.correlation_id
        )

        {:error, response} = ResponseBuilder.error("api_error", inspect(reason))
        {:reply, {:error, response}, socket}
    end
  end

  @impl true
  def handle_in("search_categories", %{"query" => query}, socket) do
    Logger.info("Category search requested",
      query: query,
      correlation_id: socket.assigns.correlation_id
    )

    case Server.Services.Twitch.ApiClient.search_categories(query) do
      {:ok, %{"data" => categories}} when is_list(categories) ->
        # Extract categories array from Twitch API response
        {:ok, response} = ResponseBuilder.success(categories)
        {:reply, {:ok, response}, socket}

      {:ok, %{"data" => []}} ->
        # Return empty array for no results
        {:ok, response} = ResponseBuilder.success([])
        {:reply, {:ok, response}, socket}

      {:error, reason} ->
        Logger.warning("Failed to search categories",
          query: query,
          error: reason,
          correlation_id: socket.assigns.correlation_id
        )

        {:error, response} = ResponseBuilder.error("api_error", inspect(reason))
        {:reply, {:error, response}, socket}
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
    current_state = get_stream_producer_state()

    if current_state do
      push(socket, "stream_state", format_state_for_client(current_state))
    else
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

  # Handle unified events from Server.Events
  @impl true
  def handle_info({:event, %{type: "stream.state_updated"} = event}, socket) do
    # Extract state data from unified event format
    state_data = %{
      current_show: event.current_show,
      active_content: event.active_content,
      interrupt_stack: event.interrupt_stack,
      ticker_rotation: event.ticker_rotation,
      version: event.version,
      metadata: event.metadata
    }

    # Send overlay state to stream:overlays channels
    if socket.topic == "stream:overlays" do
      push(socket, "stream_state", format_state_for_client(state_data))
    end

    # Send queue state to stream:queue channels
    if socket.topic == "stream:queue" do
      push(socket, "queue_state", format_queue_state_for_client(state_data))
    end

    {:noreply, socket}
  end

  # Handle show changes from unified events
  @impl true
  def handle_info({:event, %{type: "stream.show_changed"} = event}, socket) do
    push(socket, "show_changed", %{
      show: event.show,
      game: %{
        id: event.game_id,
        name: event.game_name
      },
      title: event.title,
      changed_at: event.changed_at
    })

    {:noreply, socket}
  end

  # Handle emote increments from unified events
  @impl true
  def handle_info({:event, %{type: "stream.emote_increment"} = event}, socket) do
    push(socket, "content_update", %{
      type: "emote_increment",
      data: %{
        emotes: event.emotes,
        native_emotes: event.native_emotes,
        username: event.user_name
      },
      timestamp: event.timestamp
    })

    {:noreply, socket}
  end

  # Handle takeover events from unified events
  @impl true
  def handle_info({:event, %{type: "stream.takeover_started"} = event}, socket) do
    push(socket, "takeover", %{
      type: event.takeover_type,
      message: event.message,
      duration: event.duration,
      timestamp: event.timestamp
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:event, %{type: "stream.takeover_cleared"} = event}, socket) do
    push(socket, "takeover_clear", %{
      timestamp: event.timestamp
    })

    {:noreply, socket}
  end

  # Handle interrupt removal events from unified events
  @impl true
  def handle_info({:event, %{type: "stream.interrupt_removed"} = _event}, socket) do
    # For now, we'll trigger a state refresh when interrupts are removed
    # This ensures the UI stays in sync
    current_state = get_stream_producer_state()

    if current_state do
      if socket.topic == "stream:overlays" do
        push(socket, "stream_state", format_state_for_client(current_state))
      end

      if socket.topic == "stream:queue" do
        push(socket, "queue_state", format_queue_state_for_client(current_state))
      end
    end

    {:noreply, socket}
  end

  # Filter out non-stream events from unified events topic
  @impl true
  def handle_info({:event, %{type: event_type}}, socket) when not is_nil(event_type) do
    # Ignore events that aren't stream-related
    if String.starts_with?(event_type, "stream.") do
      # Log unhandled stream events for debugging
      Logger.debug("Unhandled stream event in StreamChannel",
        event_type: event_type,
        topic: socket.topic
      )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
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

  defp get_stream_producer_state do
    try do
      GenServer.call(StreamProducer, :get_state, 5000)
    rescue
      _ -> nil
    catch
      :exit, {:noproc, _} -> nil
      :exit, _ -> nil
    end
  end

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
    # Use centralized overlay tracker
    overlay_info = %{
      name: Map.get(payload, "overlay_type", "Takeover"),
      joined_at: DateTime.utc_now(),
      socket_id: socket.assigns.correlation_id,
      environment: Map.get(socket.assigns, :environment, "unknown")
    }

    Server.OverlayTracker.track_overlay(socket.assigns.correlation_id, overlay_info)
  end

  @impl true
  def terminate(_reason, socket) do
    # Remove from tracking when channel terminates
    Server.OverlayTracker.untrack_overlay(socket.assigns.correlation_id)
    :ok
  end
end
