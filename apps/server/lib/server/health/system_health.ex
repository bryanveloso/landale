defmodule Server.Health.SystemHealth do
  @moduledoc """
  System health assessment logic for Landale streaming platform.

  Determines overall system status by checking:
  - Critical internal processes
  - External service connectivity (Phononmaser, Seed, OBS, Twitch)
  - Phoenix connectivity issues (when multiple services report unreachability)

  Returns: "healthy", "degraded", or "unhealthy"
  """

  require Logger

  @doc """
  Determines the current system status based on service health checks.

  SERVICE HEALTH CASCADE: Phoenix is the central hub.
  If Phoenix is down, ALL services should be marked as degraded
  because they can't communicate even if individually healthy.
  """
  @spec determine_system_status() :: String.t()
  def determine_system_status do
    # Check critical internal processes
    critical_processes = []

    # Check internal processes
    process_count =
      Enum.count(critical_processes, fn module ->
        Process.whereis(module) != nil
      end)

    # Check external services (from gather_service_metrics results)
    services = gather_service_metrics()

    # If any service can't reach Phoenix, that's a connectivity issue
    # Check if services are reporting connection errors
    services_with_errors =
      Enum.count([:phononmaser, :seed, :obs, :twitch], fn service ->
        case services[service] do
          %{connected: false, error: "Service unreachable"} -> true
          %{connected: false, error: "Connection timed out"} -> true
          _ -> false
        end
      end)

    # If multiple services can't connect, Phoenix might appear up but be unreachable
    phoenix_unreachable = services_with_errors >= 3

    connected_services =
      Enum.count([:phononmaser, :seed, :obs, :twitch], fn service ->
        services[service][:connected] == true
      end)

    # 4 external services
    total_critical = length(critical_processes) + 4
    total_running = process_count + connected_services

    cond do
      # If Phoenix appears unreachable to services, system is degraded
      phoenix_unreachable -> "degraded"
      # All services running
      total_running == total_critical -> "healthy"
      # At least half working
      total_running >= div(total_critical, 2) -> "degraded"
      # Less than half working
      true -> "unhealthy"
    end
  end

  @doc """
  Gathers transcription analytics for telemetry.
  """
  @spec gather_transcription_analytics() :: map()
  def gather_transcription_analytics do
    try do
      Server.Transcription.Analytics.gather_analytics()
    rescue
      error ->
        Logger.warning("Failed to gather transcription analytics", error: inspect(error))

        %{
          timestamp: System.system_time(:millisecond),
          total_transcriptions_24h: 0,
          confidence: %{average: 0.0, min: 0.0, max: 0.0, distribution: %{high: 0, medium: 0, low: 0}},
          duration: %{total_seconds: 0.0, average_duration: 0.0, total_text_length: 0},
          trends: %{confidence_trend: "unknown", hourly_volume: [], quality_trend: "unknown"},
          error: "Analytics unavailable"
        }
    end
  end

  @doc """
  Gathers metrics from all services for status reporting.
  """
  @spec gather_service_metrics() :: map()
  def gather_service_metrics do
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
            # Add timeout and error protection for service calls
            try do
              service_module.get_status()
            rescue
              error ->
                Logger.warning("Service call exception", service: name, error: inspect(error))
                {:error, "Service exception: #{inspect(error)}"}
            catch
              :exit, {:timeout, _} ->
                Logger.warning("Service status timeout", service: name)
                {:error, "Service status timeout"}

              :exit, {:noproc, _} ->
                Logger.warning("Service not running", service: name)
                {:error, "Service not running"}

              :exit, reason ->
                Logger.warning("Service call failed", service: name, reason: inspect(reason))
                {:error, "Service call failed: #{inspect(reason)}"}
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
end
