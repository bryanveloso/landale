defmodule ServerWeb.HealthController do
  use ServerWeb, :controller

  def check(conn, _params) do
    # Basic health check
    json(conn, %{status: "ok", timestamp: System.system_time(:second)})
  end

  def detailed(conn, _params) do
    # Detailed system health including OBS status
    obs_status = case Server.Services.OBS.get_status() do
      {:ok, status} -> status
      {:error, _} -> %{connected: false, error: "Service unavailable"}
    end

    health_data = %{
      status: "ok",
      timestamp: System.system_time(:second),
      services: %{
        obs: obs_status,
        database: get_database_status(),
        websocket: %{connected: true}  # Assuming WebSocket is healthy if we're responding
      },
      system: %{
        uptime: System.system_time(:second) - Application.get_env(:server, :start_time, System.system_time(:second)),
        version: Application.spec(:server, :vsn) |> to_string()
      }
    }

    json(conn, health_data)
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
end