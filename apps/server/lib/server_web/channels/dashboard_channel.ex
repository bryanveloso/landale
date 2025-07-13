defmodule ServerWeb.DashboardChannel do
  @moduledoc """
  Phoenix Channel for real-time dashboard communication.

  Handles WebSocket connections from the React dashboard frontend,
  providing real-time updates for OBS status, system health, and
  performance metrics.

  ## Events Subscribed To
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

  use ServerWeb, :channel

  require Logger

  alias Server.CorrelationId
  alias ServerWeb.ResponseBuilder

  @impl true
  def join("dashboard:" <> room_id, _payload, socket) do
    # Generate correlation ID for this session
    correlation_id = CorrelationId.from_context(assigns: socket.assigns)
    CorrelationId.put_logger_metadata(correlation_id)

    Logger.info("Dashboard channel joined", room_id: room_id)

    socket =
      socket
      |> assign(:room_id, room_id)
      |> assign(:correlation_id, correlation_id)

    # Subscribe to relevant PubSub topics for real-time updates
    Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")
    Phoenix.PubSub.subscribe(Server.PubSub, "rainwave:events")
    Phoenix.PubSub.subscribe(Server.PubSub, "system:health")
    Phoenix.PubSub.subscribe(Server.PubSub, "system:performance")

    # Send initial state
    send(self(), :send_initial_state)

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

  # Handle incoming messages from client
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
        {:reply, ResponseBuilder.success(%{operation: "start_streaming"}), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("operation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("obs:start_recording", _payload, socket) do
    case Server.Services.OBS.start_recording() do
      :ok ->
        {:reply, ResponseBuilder.success(%{operation: "start_streaming"}), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("operation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("obs:stop_recording", _payload, socket) do
    case Server.Services.OBS.stop_recording() do
      :ok ->
        {:reply, ResponseBuilder.success(%{operation: "start_streaming"}), socket}

      {:error, reason} ->
        {:reply, ResponseBuilder.error("operation_failed", reason), socket}
    end
  end

  @impl true
  def handle_in("obs:set_current_scene", %{"scene_name" => scene_name}, socket) do
    case Server.Services.OBS.set_current_scene(scene_name) do
      :ok ->
        {:reply, ResponseBuilder.success(%{operation: "start_streaming"}), socket}

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
  def handle_in("ping", payload, socket) do
    {:reply, ResponseBuilder.success(payload), socket}
  end

  @impl true
  def handle_in("shout", payload, socket) do
    broadcast!(socket, "shout", payload)
    {:noreply, socket}
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    Logger.warning("Unhandled dashboard channel message",
      event: event,
      payload: payload,
      correlation_id: Map.get(socket.assigns, :correlation_id, "test")
    )

    {:reply, ResponseBuilder.error("unknown_event", "Unknown event: #{event}"), socket}
  end
end
