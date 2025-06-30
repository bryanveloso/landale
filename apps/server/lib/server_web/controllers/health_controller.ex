defmodule ServerWeb.HealthController do
  @moduledoc """
  Health check endpoints for monitoring system status.

  Provides HTTP endpoints for Docker health checks, Kubernetes probes,
  and general system monitoring. Includes both simple and detailed
  health reporting.

  ## Endpoints
  - `GET /health` - Basic health check (always returns 200)
  - `GET /ready` - Readiness probe (503 if database unavailable)
  - `GET /api/health` - Detailed health with all service statuses
  """

  use ServerWeb, :controller

  @doc """
  Basic health check endpoint.

  Always returns 200 OK with minimal response for simple uptime monitoring.
  """
  @spec check(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def check(conn, _params) do
    start_time = System.monotonic_time(:millisecond)

    # Basic health check
    response = json(conn, %{status: "ok", timestamp: System.system_time(:second)})

    # Emit telemetry
    duration = System.monotonic_time(:millisecond) - start_time
    Server.Telemetry.health_check("basic", duration, "healthy")

    response
  end

  @doc """
  Detailed health check with service status information.

  Returns comprehensive health data including all services and system metrics.
  Returns HTTP 503 if any critical services are unhealthy.
  """
  @spec detailed(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def detailed(conn, _params) do
    start_time = System.monotonic_time(:millisecond)
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

    # Emit telemetry
    duration = System.monotonic_time(:millisecond) - start_time
    Server.Telemetry.health_check("detailed", duration, overall_status)

    conn
    |> put_status(status_code)
    |> json(health_data)
  end

  @doc """
  Kubernetes-style readiness probe.

  Returns 200 if service is ready to accept traffic, 503 otherwise.
  Currently only checks database connectivity.
  """
  @spec ready(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ready(conn, _params) do
    start_time = System.monotonic_time(:millisecond)
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

    # Emit telemetry
    duration = System.monotonic_time(:millisecond) - start_time
    status_string = if ready, do: "ready", else: "not_ready"
    Server.Telemetry.health_check("readiness", duration, status_string)

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
