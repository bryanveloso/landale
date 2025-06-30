defmodule ServerWeb.DashboardChannel do
  @moduledoc """
  Phoenix Channel for real-time dashboard communication.

  Handles WebSocket connections from the React dashboard frontend,
  providing real-time updates for OBS status, system health, and
  performance metrics.

  ## Events Subscribed To
  - `obs:events` - OBS WebSocket state changes and events
  - `system:health` - System health status updates
  - `system:performance` - Performance metrics updates

  ## Events Sent to Client
  - `initial_state` - Current system state on connection
  - `obs_event` - OBS-related events (streaming, recording, scenes)
  - `health_update` - System health status changes
  - `performance_update` - Performance metrics updates

  ## Incoming Commands
  - `obs:get_status` - Request current OBS status
  - `obs:start_streaming` - Start OBS streaming
  - `obs:stop_streaming` - Stop OBS streaming
  - `obs:start_recording` - Start OBS recording
  - `obs:stop_recording` - Stop OBS recording
  - `obs:set_current_scene` - Change OBS scene
  """

  use ServerWeb, :channel

  require Logger

  alias Server.CorrelationId

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

  # Handle incoming messages from client
  @impl true
  def handle_in("obs:get_status", _payload, socket) do
    correlation_id = socket.assigns.correlation_id

    CorrelationId.with_context(correlation_id, fn ->
      Logger.debug("Handling OBS status request")

      # Forward request to OBS service
      case Server.Services.OBS.get_status() do
        {:ok, status} ->
          Logger.debug("OBS status request successful")
          {:reply, {:ok, status}, socket}

        {:error, %Server.ServiceError{} = error} ->
          Logger.warning("OBS status request failed",
            reason: error.reason,
            message: error.message
          )

          {:reply, {:error, %{message: error.message}}, socket}

        {:error, reason} ->
          Logger.warning("OBS status request failed", reason: inspect(reason))
          {:reply, {:error, %{message: inspect(reason)}}, socket}
      end
    end)
  end

  @impl true
  def handle_in("obs:start_streaming", _payload, socket) do
    case Server.Services.OBS.start_streaming() do
      :ok ->
        {:reply, {:ok, %{success: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: reason}}, socket}
    end
  end

  @impl true
  def handle_in("obs:stop_streaming", _payload, socket) do
    case Server.Services.OBS.stop_streaming() do
      :ok ->
        {:reply, {:ok, %{success: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: reason}}, socket}
    end
  end

  @impl true
  def handle_in("obs:start_recording", _payload, socket) do
    case Server.Services.OBS.start_recording() do
      :ok ->
        {:reply, {:ok, %{success: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: reason}}, socket}
    end
  end

  @impl true
  def handle_in("obs:stop_recording", _payload, socket) do
    case Server.Services.OBS.stop_recording() do
      :ok ->
        {:reply, {:ok, %{success: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: reason}}, socket}
    end
  end

  @impl true
  def handle_in("obs:set_current_scene", %{"scene_name" => scene_name}, socket) do
    case Server.Services.OBS.set_current_scene(scene_name) do
      :ok ->
        {:reply, {:ok, %{success: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: reason}}, socket}
    end
  end

  # Test event handlers
  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
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

    {:reply, {:error, %{message: "Unknown event: #{event}"}}, socket}
  end
end
