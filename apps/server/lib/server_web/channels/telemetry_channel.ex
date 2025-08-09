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
  alias ServerWeb.ResponseBuilder

  @impl true
  def join("dashboard:telemetry", _payload, socket) do
    socket =
      socket
      |> setup_correlation_id()
      |> assign(:subscribed, true)
      |> assign(:join_time, System.system_time(:second))

    # Subscribe to telemetry topics
    subscribe_to_topics([
      "telemetry:health",
      "telemetry:websocket",
      "telemetry:performance",
      "telemetry:services",
      "system:health"
    ])

    # Emit telemetry for this channel join
    emit_joined_telemetry("dashboard:telemetry", socket)

    # Send current health status immediately if available
    # Handle test environment where HealthMonitorServer may not be started
    try do
      case Server.Health.HealthMonitorServer.get_current_status() do
        nil -> :ok
        status -> push(socket, "health_update", %{status: status, timestamp: System.system_time(:second)})
      end
    catch
      # HealthMonitorServer not started (test environment)
      :exit, {:noproc, _} -> :ok
    end

    # Start periodic telemetry updates (every 2 seconds)
    Process.send_after(self(), :broadcast_telemetry, 2_000)

    {:ok, socket}
  end

  # Removed unreliable timer-based initial snapshot
  # Client explicitly requests data via push("get_telemetry")

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

  @impl true
  def handle_info({:telemetry_health_event, event}, socket) do
    push(socket, "health_update", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:telemetry_websocket_event, event}, socket) do
    push(socket, "websocket_metrics", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:telemetry_metrics_event, event}, socket) do
    push(socket, "performance_metrics", event)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:broadcast_telemetry, socket) do
    # Push current telemetry snapshot
    telemetry_data = gather_telemetry_snapshot()
    push(socket, "telemetry_update", telemetry_data)

    # Schedule next broadcast
    Process.send_after(self(), :broadcast_telemetry, 2_000)

    {:noreply, socket}
  end

  # Catch-all handler to prevent crashes from unexpected messages
  @impl true
  def handle_info(unhandled_msg, socket) do
    Logger.warning("Unhandled message in #{__MODULE__}",
      message: inspect(unhandled_msg)
    )

    {:noreply, socket}
  end

  # Client commands

  @impl true
  def handle_in("get_telemetry", params, socket) do
    Logger.debug("Processing telemetry request")

    # Extract environment filter if provided
    environment_filter = Map.get(params, "environment", nil)

    telemetry_data = gather_telemetry_snapshot(environment_filter)

    {:reply, ResponseBuilder.success(telemetry_data), socket}
  end

  @impl true
  def handle_in("get_service_health", %{"service" => service_name}, socket) do
    health_data = get_service_health(service_name)
    {:reply, ResponseBuilder.success(health_data), socket}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    handle_ping(payload, socket)
  end

  # Catch-all for unhandled client messages
  @impl true
  def handle_in(event, payload, socket) do
    log_unhandled_message(event, payload, socket)
    {:reply, ResponseBuilder.error("unknown_command", "Unknown command: #{event}"), socket}
  end

  # Private functions

  defp gather_telemetry_snapshot(environment_filter \\ nil) do
    %{
      timestamp: System.system_time(:second),
      websocket: gather_websocket_metrics(),
      services: gather_service_metrics(),
      performance: gather_performance_metrics(),
      system: gather_system_metrics(),
      overlays: gather_overlay_health(environment_filter),
      environment_filter: environment_filter
    }
  end

  defp gather_websocket_metrics do
    # WebSocket stats tracking has been removed in favor of direct Phoenix connections
    # Always return basic info since get_websocket_stats/0 always returns {:ok, _}
    {:ok, stats} = get_websocket_stats()
    stats
  end

  defp get_websocket_stats do
    # WebSocket stats tracking has been removed in favor of direct Phoenix connections
    # Return basic connection info instead
    {:ok,
     %{
       status: "Direct Phoenix connections",
       message: "Using direct Phoenix sockets without telemetry wrapper"
     }}
  end

  defp gather_service_metrics do
    services = [
      {:obs, Server.Services.OBS},
      {:twitch, Server.Services.Twitch},
      {:phononmaser, {Server.HTTPServiceAdapter, get_service_health_url(:phononmaser)}},
      {:seed, {Server.HTTPServiceAdapter, get_service_health_url(:seed)}}
    ]

    Map.new(services, fn {name, service_spec} ->
      status =
        case service_spec do
          {_adapter_module, nil} ->
            # Handle missing configuration
            {:error, "Service URL not configured"}

          {adapter_module, url} ->
            adapter_module.get_status(url)

          service_module ->
            # Add timeout protection for service calls
            try do
              GenServer.call(service_module, :get_service_status, 5000)
            rescue
              _ ->
                {:error, "Service unavailable"}
            catch
              :exit, {:noproc, _} ->
                Logger.debug("Service not started", service: name)
                {:error, "Service not started"}

              :exit, {:timeout, _} ->
                Logger.warning("Service status timeout", service: name)
                {:error, "Service status timeout"}

              :exit, _ ->
                {:error, "Service error"}
            end
        end

      formatted_status =
        case status do
          {:ok, data} ->
            Map.merge(%{connected: true, phoenix_reachable: true}, data)

          {:error, reason} ->
            # Determine if this is a Phoenix connectivity issue
            phoenix_issue = reason in [:econnrefused, :timeout, "Connection timed out", "Service unreachable"]

            %{
              connected: false,
              error: sanitize_error(reason),
              phoenix_reachable: not phoenix_issue
            }
        end

      {name, formatted_status}
    end)
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
    services = gather_service_metrics()

    case service_name do
      "phononmaser" -> Map.get(services, :phononmaser, %{error: "Service not found"})
      "seed" -> Map.get(services, :seed, %{error: "Service not found"})
      "obs" -> Map.get(services, :obs, %{error: "Service not found"})
      "twitch" -> Map.get(services, :twitch, %{error: "Service not found"})
      _ -> %{error: "Unknown service"}
    end
  end

  defp gather_system_metrics do
    # Get server uptime and system info
    {uptime_microseconds, _} = :erlang.statistics(:wall_clock)
    uptime_seconds = div(uptime_microseconds, 1_000_000)

    %{
      uptime: uptime_seconds,
      version: Application.spec(:server, :vsn) |> to_string(),
      environment: Application.get_env(:server, :environment, "production"),
      status: get_health_status()
    }
  end

  # Helper to safely get health status (handles test environment)
  defp get_health_status do
    try do
      Server.Health.HealthMonitorServer.get_current_status() || "unknown"
    catch
      # HealthMonitorServer not started (test environment)
      :exit, {:noproc, _} -> "unknown"
    end
  end

  # Helper to get service health URL from configuration
  defp get_service_health_url(service_name) do
    Application.get_env(:server, :services)
    |> get_in([service_name, :health_url])
    |> case do
      nil ->
        Logger.warning("No health URL configured for service #{service_name}")
        nil

      url ->
        url
    end
  end

  # Helper to sanitize error messages before sending to client
  defp sanitize_error(:timeout), do: "Connection timed out"
  defp sanitize_error(:econnrefused), do: "Service unreachable"
  defp sanitize_error("Invalid JSON response"), do: "Invalid response from service"
  defp sanitize_error("Service unreachable"), do: "Service unreachable"
  defp sanitize_error("Service URL not configured"), do: "Service not configured"
  defp sanitize_error(reason) when is_binary(reason), do: reason
  defp sanitize_error(_), do: "An unknown error occurred"

  defp gather_overlay_health(environment_filter) do
    # Use ETS to track overlay channel joins
    # Create table if it doesn't exist
    table_name = :overlay_channel_tracker

    if :ets.whereis(table_name) == :undefined do
      # Using :protected - only telemetry channel needs access to this tracking data
      :ets.new(table_name, [:set, :protected, :named_table])
    end

    # Get all entries from the tracking table
    overlays =
      :ets.tab2list(table_name)
      |> Enum.map(fn {_socket_id, info} ->
        %{
          name: Map.get(info, :name, "Takeover"),
          connected: true,
          lastSeen: Map.get(info, :joined_at, DateTime.utc_now()) |> format_datetime(),
          channelState: "joined",
          environment: Map.get(info, :environment, "unknown")
        }
      end)
      |> filter_by_environment(environment_filter)

    overlays
  end

  defp filter_by_environment(items, nil), do: items

  defp filter_by_environment(items, environment) do
    Enum.filter(items, fn item ->
      Map.get(item, :environment) == environment
    end)
  end

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(_), do: DateTime.utc_now() |> DateTime.to_iso8601()
end
