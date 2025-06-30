defmodule ServerWeb.ControlController do
  @moduledoc """
  Basic control endpoints for dashboard and overlay management.
  """

  use ServerWeb, :controller

  def status(conn, _params) do
    # Get basic system status
    uptime_seconds = :erlang.system_info(:uptime) / 1000
    memory = :erlang.memory()

    # Get service statuses
    services = %{
      obs: get_service_status(:obs),
      twitch: get_service_status(:twitch),
      ironmon_tcp: get_service_status(:ironmon_tcp),
      database: get_service_status(:database)
    }

    # Overall health
    healthy_services = services |> Enum.count(fn {_name, status} -> status.connected end)
    total_services = map_size(services)

    status_data = %{
      status: if(healthy_services == total_services, do: "healthy", else: "degraded"),
      timestamp: System.system_time(:second),
      uptime: %{
        seconds: round(uptime_seconds),
        formatted: format_uptime(uptime_seconds)
      },
      memory: %{
        total: format_bytes(memory[:total]),
        processes: format_bytes(memory[:processes]),
        system: format_bytes(memory[:system])
      },
      services: services,
      summary: %{
        healthy_services: healthy_services,
        total_services: total_services,
        health_percentage: round(healthy_services / total_services * 100)
      }
    }

    # Could add telemetry here if needed

    json(conn, status_data)
  end

  def ping(conn, _params) do
    # Simple keep-alive endpoint for dashboard
    timestamp = System.system_time(:second)

    response = %{
      pong: true,
      timestamp: timestamp,
      server_time: DateTime.from_unix!(timestamp) |> DateTime.to_iso8601()
    }

    json(conn, response)
  end

  def services(conn, _params) do
    # Detailed service information
    services = %{
      obs: get_detailed_service_info(:obs),
      twitch: get_detailed_service_info(:twitch),
      ironmon_tcp: get_detailed_service_info(:ironmon_tcp),
      database: get_detailed_service_info(:database)
    }

    json(conn, services)
  end

  # Private helper functions

  defp get_service_status(:obs) do
    case Server.Services.OBS.get_status() do
      {:ok, status} -> %{connected: true, status: status}
      {:error, reason} -> %{connected: false, error: to_string(reason)}
    end
  rescue
    _ -> %{connected: false, error: "Service unavailable"}
  end

  defp get_service_status(:twitch) do
    case Server.Services.Twitch.get_status() do
      {:ok, status} -> %{connected: true, status: status}
      {:error, reason} -> %{connected: false, error: to_string(reason)}
    end
  rescue
    _ -> %{connected: false, error: "Service unavailable"}
  end

  defp get_service_status(:ironmon_tcp) do
    case GenServer.whereis(Server.Services.IronmonTCP) do
      pid when is_pid(pid) ->
        %{connected: true, pid: inspect(pid)}

      nil ->
        %{connected: false, error: "Service not running"}
    end
  end

  defp get_service_status(:database) do
    case Server.Repo.query("SELECT 1", []) do
      {:ok, _} -> %{connected: true, status: "healthy"}
      {:error, reason} -> %{connected: false, error: to_string(reason)}
    end
  rescue
    _ -> %{connected: false, error: "Database unavailable"}
  end

  defp get_detailed_service_info(:obs) do
    base_status = get_service_status(:obs)

    additional_info =
      if base_status.connected do
        %{service_type: "obs_websocket"}
      else
        %{}
      end

    Map.merge(base_status, additional_info)
  end

  defp get_detailed_service_info(:twitch) do
    base_status = get_service_status(:twitch)

    additional_info =
      if base_status.connected do
        %{
          subscriptions:
            Server.SubscriptionMonitor.get_health_report() |> Map.take([:total_subscriptions, :enabled_subscriptions])
        }
      else
        %{}
      end

    Map.merge(base_status, additional_info)
  end

  defp get_detailed_service_info(:ironmon_tcp) do
    base_status = get_service_status(:ironmon_tcp)

    additional_info =
      if base_status.connected do
        %{service_type: "tcp_server", port: 8080}
      else
        %{}
      end

    Map.merge(base_status, additional_info)
  end

  defp get_detailed_service_info(:database) do
    base_status = get_service_status(:database)

    additional_info =
      if base_status.connected do
        try do
          {:ok, result} = Server.Repo.query("SELECT COUNT(*) FROM seeds", [])
          [[seed_count]] = result.rows
          %{seed_count: seed_count}
        rescue
          _ -> %{seed_count: "unknown"}
        end
      else
        %{}
      end

    Map.merge(base_status, additional_info)
  end

  defp format_uptime(seconds) when is_float(seconds) do
    seconds = round(seconds)
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m #{secs}s"
      minutes > 0 -> "#{minutes}m #{secs}s"
      true -> "#{secs}s"
    end
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_bytes(_), do: "0 B"
end
