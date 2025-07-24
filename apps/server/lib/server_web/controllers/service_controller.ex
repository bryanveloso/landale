defmodule ServerWeb.ServiceController do
  @moduledoc """
  Controller for service registry operations.

  Provides REST endpoints for service discovery, health checks,
  and service introspection.
  """

  use ServerWeb, :controller

  @doc """
  List all registered services.
  """
  def index(conn, _params) do
    services = Server.ServiceRegistry.list_services()
    json(conn, %{services: services})
  end

  @doc """
  Get details about a specific service.
  """
  def show(conn, %{"id" => service_name}) do
    case find_service_by_name(service_name) do
      {:ok, service_module} ->
        case Server.ServiceRegistry.get_service(service_module) do
          {:ok, service} ->
            json(conn, %{service: service})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Service not found"})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Service not found"})
    end
  end

  @doc """
  Get health status for all services.
  """
  def health(conn, _params) do
    health_data = Server.ServiceRegistry.get_all_health()
    json(conn, %{health: health_data})
  end

  @doc """
  Get health status for a specific service.
  """
  def service_health(conn, %{"id" => service_name}) do
    case find_service_by_name(service_name) do
      {:ok, service_module} ->
        case Server.ServiceRegistry.get_service_health(service_module) do
          {:ok, health} ->
            json(conn, %{health: health})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Service not found"})

          {:error, reason} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{error: "Health check failed", reason: inspect(reason)})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Service not found"})
    end
  end

  @doc """
  Get overall system health.
  """
  def system_health(conn, _params) do
    system_health = Server.ServiceRegistry.get_system_health()

    # Set appropriate HTTP status based on system health
    status =
      case system_health.status do
        :healthy -> :ok
        # Still return 200 for degraded
        :degraded -> :ok
        :unhealthy -> :service_unavailable
      end

    conn
    |> put_status(status)
    |> json(%{system_health: system_health})
  end

  # Private helper functions

  @valid_service_names ["obs", "twitch", "ironmon_tcp", "rainwave"]

  defp find_service_by_name(service_name) when service_name in @valid_service_names do
    service_module =
      case service_name do
        "obs" -> Server.Services.OBS
        "twitch" -> Server.Services.Twitch
        "ironmon_tcp" -> Server.Services.IronmonTCP
        "rainwave" -> Server.Services.Rainwave
      end

    {:ok, service_module}
  end

  defp find_service_by_name(_service_name) do
    {:error, :not_found}
  end
end
