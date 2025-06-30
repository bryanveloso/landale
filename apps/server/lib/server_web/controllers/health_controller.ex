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
  - `GET /api/health/subscriptions` - EventSub subscription monitoring health
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
    subscription_status = get_subscription_status()

    # Determine overall health status
    overall_status = determine_overall_status([obs_status, twitch_status, database_status, subscription_status])

    health_data = %{
      status: overall_status,
      timestamp: System.system_time(:second),
      services: %{
        obs: obs_status,
        twitch: twitch_status,
        database: database_status,
        subscriptions: subscription_status,
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

  @doc """
  EventSub subscription monitoring health endpoint.

  Returns detailed subscription health information including counts,
  statuses, and recommendations for subscription management.
  """
  @spec subscriptions(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def subscriptions(conn, _params) do
    start_time = System.monotonic_time(:millisecond)

    try do
      report = Server.SubscriptionMonitor.get_health_report()

      # Determine subscription health status
      health_status =
        cond do
          report.total_subscriptions == 0 -> "no_subscriptions"
          report.failed_subscriptions > report.enabled_subscriptions -> "degraded"
          report.failed_subscriptions > 0 -> "warning"
          true -> "healthy"
        end

      # Generate recommendations
      recommendations = generate_subscription_recommendations(report)

      response = %{
        status: health_status,
        timestamp: System.system_time(:second),
        subscription_health: report,
        recommendations: recommendations,
        summary: %{
          health_score: calculate_health_score(report),
          critical_issues: count_critical_issues(report),
          last_cleanup: report.last_cleanup_at
        }
      }

      # Determine HTTP status code
      status_code =
        case health_status do
          "healthy" -> 200
          "warning" -> 200
          "no_subscriptions" -> 200
          "degraded" -> 503
          _ -> 503
        end

      # Emit telemetry
      duration = System.monotonic_time(:millisecond) - start_time
      Server.Telemetry.health_check("subscriptions", duration, health_status)

      conn
      |> put_status(status_code)
      |> json(response)
    rescue
      error ->
        # Emit telemetry for error
        duration = System.monotonic_time(:millisecond) - start_time
        Server.Telemetry.health_check("subscriptions", duration, "error")

        conn
        |> put_status(503)
        |> json(%{
          status: "error",
          timestamp: System.system_time(:second),
          error: "Failed to retrieve subscription health data",
          details: inspect(error)
        })
    end
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

  defp get_subscription_status do
    try do
      report = Server.SubscriptionMonitor.get_health_report()

      status =
        cond do
          report.total_subscriptions == 0 -> "no_subscriptions"
          report.failed_subscriptions > report.enabled_subscriptions -> "degraded"
          report.failed_subscriptions > 0 -> "warning"
          true -> "healthy"
        end

      %{
        status: status,
        total: report.total_subscriptions,
        enabled: report.enabled_subscriptions,
        failed: report.failed_subscriptions,
        orphaned: report.orphaned_subscriptions
      }
    rescue
      _ ->
        %{status: "error", error: "Subscription monitor unavailable"}
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

    # Check subscription health - degraded subscriptions impact overall health
    subscription_ok =
      service_statuses
      |> Enum.find(fn status -> Map.has_key?(status, :total) end)
      |> case do
        %{status: "degraded"} -> false
        _ -> true
      end

    cond do
      !database_ok -> "unhealthy"
      !subscription_ok -> "degraded"
      true -> "healthy"
    end
  end

  defp generate_subscription_recommendations(report) do
    recommendations = []

    recommendations =
      if report.failed_subscriptions > 0 do
        ["Review failed subscriptions and check OAuth token validity" | recommendations]
      else
        recommendations
      end

    recommendations =
      if report.orphaned_subscriptions > 0 do
        ["Clean up orphaned subscriptions that haven't received events" | recommendations]
      else
        recommendations
      end

    recommendations =
      if report.total_subscriptions == 0 do
        ["No active subscriptions found - verify EventSub setup" | recommendations]
      else
        recommendations
      end

    recommendations =
      if report.enabled_subscriptions < 3 do
        ["Consider adding more subscription types for comprehensive monitoring" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp calculate_health_score(report) do
    if report.total_subscriptions == 0 do
      0
    else
      enabled_percentage = report.enabled_subscriptions / report.total_subscriptions * 100

      # Deduct points for failures and orphaned subscriptions
      failure_penalty = report.failed_subscriptions / report.total_subscriptions * 30
      orphan_penalty = report.orphaned_subscriptions / report.total_subscriptions * 20

      max(0, round(enabled_percentage - failure_penalty - orphan_penalty))
    end
  end

  defp count_critical_issues(report) do
    # Failed subscriptions are critical
    base_count = report.failed_subscriptions

    # High orphan count is critical (more than 25% of total)
    orphan_critical =
      if report.total_subscriptions > 0 and
           report.orphaned_subscriptions / report.total_subscriptions > 0.25,
         do: 1,
         else: 0

    # No subscriptions at all is critical
    no_subs_critical = if report.total_subscriptions == 0, do: 1, else: 0

    base_count + orphan_critical + no_subs_critical
  end
end
