defmodule ServerWeb.HealthController do
  use ServerWeb, :controller

  def check(conn, _params) do
    # Basic health check
    json(conn, %{status: "ok", timestamp: System.system_time(:second)})
  end

  def detailed(conn, _params) do
    # Detailed system health including all services
    obs_status =
      case Server.Services.OBS.get_status() do
        {:ok, status} -> status
        {:error, _} -> %{connected: false, error: "Service unavailable"}
      end

    twitch_status =
      case Server.Services.Twitch.get_status() do
        {:ok, status} -> status
        {:error, _} -> %{connected: false, error: "Service unavailable"}
      end

    database_status = get_database_status()

    # Determine overall health status
    overall_status = determine_overall_status([obs_status, twitch_status, database_status])

    health_data = %{
      status: overall_status,
      timestamp: System.system_time(:second),
      services: %{
        obs: obs_status,
        twitch: twitch_status,
        database: database_status,
        # Assuming WebSocket is healthy if we're responding
        websocket: %{connected: true}
      },
      system: %{
        uptime:
          System.system_time(:second) -
            Application.get_env(:server, :start_time, System.system_time(:second)),
        version: Application.spec(:server, :vsn) |> to_string(),
        environment: Mix.env() |> to_string()
      }
    }

    # Return appropriate HTTP status for Docker health checks
    status_code = if overall_status == "healthy", do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(health_data)
  end

  def ready(conn, _params) do
    # Kubernetes-style readiness probe
    # Service is ready if critical services are available
    database_status = get_database_status()
    
    ready = database_status[:connected] == true
    
    status_data = %{
      status: if(ready, do: "ready", else: "not_ready"),
      timestamp: System.system_time(:second),
      checks: %{
        database: database_status
      }
    }
    
    status_code = if ready, do: 200, else: 503
    
    conn
    |> put_status(status_code)
    |> json(status_data)
  end

  defp get_database_status do
    try do
      case Server.Repo.query("SELECT 1", []) do
        {:ok, _} -> %{connected: true, status: "healthy"}
        {:error, reason} -> %{connected: false, error: to_string(reason)}
      end
    rescue
      _ -> %{connected: false, error: "Database unavailable"}
    end
  end

  defp determine_overall_status(service_statuses) do
    # Service is healthy if database is connected
    # OBS and Twitch are considered optional for basic functionality
    database_ok = 
      service_statuses
      |> Enum.find(fn status -> Map.has_key?(status, :status) end)
      |> case do
        %{status: "healthy"} -> true
        _ -> false
      end

    if database_ok, do: "healthy", else: "unhealthy"
  end
end
