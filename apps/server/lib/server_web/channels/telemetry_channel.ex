defmodule ServerWeb.TelemetryChannel do
  @moduledoc """
  Phoenix Channel for real-time telemetry and service metrics.

  Provides detailed connection statistics, service health metrics,
  and performance data for the Dashboard's enhanced monitoring.

  ## Events Broadcast
  - `health_update` - Service health status changes
  - `websocket_metrics` - WebSocket connection statistics
  - `performance_metrics` - System performance data
  - `service_telemetry` - Individual service telemetry

  ## Incoming Commands
  - `get_telemetry` - Request current telemetry snapshot
  - `get_service_health` - Request specific service health
  """

  use ServerWeb.ChannelBase

  @impl true
  def join("dashboard:telemetry", _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:subscribed, true)

    # Subscribe to telemetry topics
    subscribe_to_topics([
      "telemetry:health",
      "telemetry:websocket",
      "telemetry:performance",
      "telemetry:services"
    ])

    # Send initial telemetry snapshot
    send_after_join(socket, :send_initial_telemetry)

    {:ok, socket}
  end

  @impl true
  def handle_info(:send_initial_telemetry, socket) do
    # Gather current telemetry data
    telemetry_data = gather_telemetry_snapshot()

    push(socket, "telemetry_snapshot", telemetry_data)

    # Start periodic telemetry updates
    schedule_telemetry_update()

    {:noreply, socket}
  end

  @impl true
  def handle_info(:periodic_telemetry_update, socket) do
    # Only send updates if there are significant changes
    telemetry_data = gather_telemetry_snapshot()

    # Compare with last sent data (could store in socket assigns)
    if telemetry_changed?(socket, telemetry_data) do
      push(socket, "telemetry_update", telemetry_data)
    end

    # Schedule next update
    schedule_telemetry_update()

    {:noreply, assign(socket, :last_telemetry, telemetry_data)}
  end

  @impl true
  def handle_info({:telemetry_event, event_type, data}, socket) do
    # Forward telemetry events to client
    push(socket, event_type, data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:service_health, service_name, health_data}, socket) do
    # Broadcast service-specific health updates
    push(socket, "service_health_update", %{
      service: service_name,
      health: health_data,
      timestamp: System.system_time(:second)
    })

    {:noreply, socket}
  end

  # Client commands

  @impl true
  def handle_in("get_telemetry", _params, socket) do
    telemetry_data = gather_telemetry_snapshot()
    {:reply, {:ok, telemetry_data}, socket}
  end

  @impl true
  def handle_in("get_service_health", %{"service" => service_name}, socket) do
    health_data = get_service_health(service_name)
    {:reply, {:ok, health_data}, socket}
  end

  # Private functions

  defp gather_telemetry_snapshot do
    %{
      timestamp: System.system_time(:second),
      websocket: gather_websocket_metrics(),
      services: gather_service_metrics(),
      performance: gather_performance_metrics()
    }
  end

  defp gather_websocket_metrics do
    # Get WebSocket connection statistics
    # TODO: Implement channel registry stats when available
    %{
      total_connections: 0,
      active_channels: 0,
      channels_by_type: %{},
      recent_disconnects: 0,
      average_connection_duration: 0,
      status: "Stats collection pending implementation"
    }
  end

  defp gather_service_metrics do
    %{
      phononmaser: get_python_service_metrics("phononmaser"),
      seed: get_python_service_metrics("seed"),
      obs: get_obs_metrics(),
      twitch: get_twitch_metrics()
    }
  end

  defp get_python_service_metrics(service_name) do
    # Fetch metrics from Python service health endpoints
    health_url =
      case service_name do
        "phononmaser" -> "http://localhost:8890/health"
        "seed" -> "http://localhost:8891/health"
        _ -> nil
      end

    if health_url do
      case HTTPoison.get(health_url, [], timeout: 2000, recv_timeout: 2000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} ->
              %{
                connected: true,
                status: data["status"],
                uptime: data["uptime"],
                websocket_state: data["websocket"]["state"],
                reconnect_attempts: data["websocket"]["reconnect_attempts"],
                circuit_breaker_trips: data["websocket"]["circuit_breaker_trips"]
              }

            _ ->
              %{connected: false, error: "Invalid response"}
          end

        _ ->
          %{connected: false, error: "Service unreachable"}
      end
    else
      %{connected: false, error: "Unknown service"}
    end
  end

  defp get_obs_metrics do
    case Server.Services.OBS.get_status() do
      {:ok, status} -> Map.merge(%{connected: true}, status)
      {:error, _} -> %{connected: false}
    end
  end

  defp get_twitch_metrics do
    case Server.Services.Twitch.get_status() do
      {:ok, status} -> Map.merge(%{connected: true}, status)
      {:error, _} -> %{connected: false}
    end
  end

  defp gather_performance_metrics do
    %{
      memory: get_memory_metrics(),
      cpu: get_cpu_metrics(),
      message_queue: get_message_queue_metrics()
    }
  end

  defp get_memory_metrics do
    memory = :erlang.memory()

    %{
      total_mb: memory[:total] / 1_048_576,
      processes_mb: memory[:processes] / 1_048_576,
      binary_mb: memory[:binary] / 1_048_576,
      ets_mb: memory[:ets] / 1_048_576
    }
  end

  defp get_cpu_metrics do
    # Basic CPU metrics from scheduler utilization
    schedulers = :erlang.system_info(:schedulers_online)

    %{
      schedulers: schedulers,
      run_queue: :erlang.statistics(:run_queue)
    }
  end

  defp get_message_queue_metrics do
    # Get message queue lengths for key processes
    processes = [
      {:obs_service, Server.Services.OBS},
      {:twitch_service, Server.Services.Twitch},
      {:channel_registry, ServerWeb.ChannelRegistry}
    ]

    Enum.reduce(processes, %{}, fn {name, module}, acc ->
      case Process.whereis(module) do
        nil ->
          acc

        pid ->
          {:message_queue_len, len} = Process.info(pid, :message_queue_len)
          Map.put(acc, name, len)
      end
    end)
  end

  defp get_service_health(service_name) do
    case service_name do
      "phononmaser" -> get_python_service_metrics("phononmaser")
      "seed" -> get_python_service_metrics("seed")
      "obs" -> get_obs_metrics()
      "twitch" -> get_twitch_metrics()
      _ -> %{error: "Unknown service"}
    end
  end

  defp telemetry_changed?(socket, new_data) do
    # Simple change detection - could be more sophisticated
    case socket.assigns[:last_telemetry] do
      nil ->
        true

      last_data ->
        # Check if any metrics have significantly changed
        websocket_changed?(last_data.websocket, new_data.websocket) ||
          services_changed?(last_data.services, new_data.services)
    end
  end

  defp websocket_changed?(old, new) do
    old[:total_connections] != new[:total_connections] ||
      old[:active_channels] != new[:active_channels]
  end

  defp services_changed?(old, new) do
    # Check if any service connection status changed
    Enum.any?([:phononmaser, :seed, :obs, :twitch], fn service ->
      old[service][:connected] != new[service][:connected]
    end)
  end

  defp schedule_telemetry_update do
    # Send updates every 10 seconds
    Process.send_after(self(), :periodic_telemetry_update, 10_000)
  end
end
