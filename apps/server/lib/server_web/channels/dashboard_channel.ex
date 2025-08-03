defmodule ServerWeb.DashboardChannel do
  @moduledoc """
  Phoenix Channel for real-time dashboard communication.

  Handles WebSocket connections from the React dashboard frontend,
  providing real-time updates for OBS status, system health, and
  performance metrics.

  ## Events Subscribed To
  - `dashboard` - Twitch connection and event updates
  - `obs:events` - OBS WebSocket state changes and events
  - `rainwave:events` - Rainwave music service updates
  - `system:health` - System health status updates
  - `system:performance` - Performance metrics updates

  ## Events Sent to Client
  - `initial_state` - Current system state on connection
  - `obs_event` - OBS-related events (streaming, recording, scenes)
  - `rainwave_event` - Rainwave music updates (song changes, station changes)
  - `health_update` - System health status changes
  - `performance_update` - Performance metrics updates
  - `twitch_connected` - Twitch EventSub connection established
  - `twitch_disconnected` - Twitch EventSub connection lost
  - `twitch_connection_changed` - Twitch connection state changes
  - `twitch_event` - General Twitch events (follows, subs, etc.)

  ## Incoming Commands
  - `obs:get_status` - Request current OBS status
  - `obs:start_streaming` - Start OBS streaming
  - `obs:stop_streaming` - Stop OBS streaming
  - `obs:start_recording` - Start OBS recording
  - `obs:stop_recording` - Stop OBS recording
  - `obs:set_current_scene` - Change OBS scene
  - `rainwave:get_status` - Request current Rainwave status
  - `rainwave:set_enabled` - Enable/disable Rainwave service
  - `rainwave:set_station` - Change active Rainwave station
  """

  use ServerWeb.ChannelBase

  @impl true
  def join("dashboard:" <> room_id, _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:room_id, room_id)

    # Subscribe to relevant PubSub topics for real-time updates
    subscribe_to_topics([
      # For Twitch connection events
      "dashboard",
      "obs:events",
      "rainwave:events",
      "system:health",
      "system:performance"
    ])

    # Send initial state after join
    send_after_join(socket, :send_initial_state)

    # Emit telemetry for channel join
    emit_joined_telemetry("dashboard:#{room_id}", socket)

    {:ok, socket}
  end

  @impl true
  def handle_info(:send_initial_state, socket) do
    # Send current system state to the newly connected client
    push(socket, "initial_state", %{
      connected: true,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:obs_event, event}, socket) do
    push(socket, "obs_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:health_update, data}, socket) do
    push(socket, "health_update", data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:performance_update, data}, socket) do
    push(socket, "performance_update", data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:rainwave_event, event}, socket) do
    push(socket, "rainwave_event", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:event_batch, batch}, socket) do
    # Handle batched events efficiently
    push(socket, "event_batch", batch)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_connected, event}, socket) do
    push(socket, "twitch_connected", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_disconnected, event}, socket) do
    push(socket, "twitch_disconnected", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_connection_changed, event}, socket) do
    push(socket, "twitch_connection_changed", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:twitch_event, event}, socket) do
    push(socket, "twitch_event", event)
    {:noreply, socket}
  end

  # Catch-all handler to prevent crashes from unexpected messages
  @impl true
  def handle_info(unhandled_msg, socket) do
    Logger.warning("Unhandled message in #{__MODULE__}",
      message: inspect(unhandled_msg),
      room_id: socket.assigns[:room_id]
    )

    {:noreply, socket}
  end

  # Handle incoming messages from client
  @impl true
  def handle_in("ping", payload, socket) do
    handle_ping(payload, socket)
  end

  @impl true
  def handle_in("obs:get_status", _payload, socket) do
    correlation_id = socket.assigns.correlation_id

    CorrelationId.with_context(correlation_id, fn ->
      # Forward request to OBS service
      case Server.Services.OBS.get_status() do
        {:ok, status} ->
          {:reply, ResponseBuilder.success(status), socket}

        {:error, %Server.ServiceError{} = error} ->
          Logger.warning("OBS status request failed",
            reason: error.reason,
            message: error.message
          )

          {:reply, ResponseBuilder.error("service_error", error.message), socket}

        {:error, reason} ->
          Logger.warning("OBS status request failed", reason: inspect(reason))
          {:reply, ResponseBuilder.error("service_error", inspect(reason)), socket}
      end
    end)
  end

  @impl true
  def handle_in("obs:start_streaming", _payload, socket) do
    case Server.Services.OBS.start_streaming() do
      :ok ->
        {:reply, ResponseBuilder.success(%{operation: "start_streaming"}), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("operation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("obs:stop_streaming", _payload, socket) do
    case Server.Services.OBS.stop_streaming() do
      :ok ->
        {:reply, ResponseBuilder.success(%{operation: "stop_streaming"}), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("operation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("obs:start_recording", _payload, socket) do
    case Server.Services.OBS.start_recording() do
      :ok ->
        {:reply, ResponseBuilder.success(%{operation: "start_recording"}), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("operation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("obs:stop_recording", _payload, socket) do
    case Server.Services.OBS.stop_recording() do
      :ok ->
        {:reply, ResponseBuilder.success(%{operation: "stop_recording"}), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("operation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("obs:set_current_scene", %{"scene_name" => scene_name}, socket) do
    case Server.Services.OBS.set_current_scene(scene_name) do
      :ok ->
        {:reply, ResponseBuilder.success(%{operation: "set_current_scene"}), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("operation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("rainwave:get_status", _payload, socket) do
    correlation_id = socket.assigns.correlation_id

    CorrelationId.with_context(correlation_id, fn ->
      case Server.Services.Rainwave.get_status() do
        {:ok, status} ->
          {:reply, ResponseBuilder.success(status), socket}

        {:error, reason} ->
          Logger.warning("Rainwave status request failed", reason: inspect(reason))
          {:reply, ResponseBuilder.error("service_error", inspect(reason)), socket}
      end
    end)
  end

  @impl true
  def handle_in("rainwave:set_enabled", %{"enabled" => enabled}, socket) do
    Server.Services.Rainwave.set_enabled(enabled)
    {:reply, ResponseBuilder.success(%{operation: "set_enabled", enabled: enabled}), socket}
  end

  @impl true
  def handle_in("rainwave:set_station", %{"station_id" => station_id}, socket) do
    Server.Services.Rainwave.set_station(station_id)
    {:reply, ResponseBuilder.success(%{operation: "set_station", station_id: station_id}), socket}
  end

  # Test event handlers
  @impl true
  def handle_in("shout", payload, socket) do
    broadcast!(socket, "shout", payload)
    {:noreply, socket}
  end

  # Catch-all for unhandled events
  @impl true
  def handle_in(event, payload, socket) do
    log_unhandled_message(event, payload, socket)
    {:reply, ResponseBuilder.error("unknown_event", "Unknown event: #{event}"), socket}
  end
end
