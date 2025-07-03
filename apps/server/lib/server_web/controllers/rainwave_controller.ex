defmodule ServerWeb.RainwaveController do
  @moduledoc """
  Controller for Rainwave music service management.
  """

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Server.Services.Rainwave
  alias ServerWeb.Schemas

  action_fallback ServerWeb.FallbackController

  operation(:status,
    summary: "Get Rainwave service status",
    description:
      "Returns current Rainwave service status including listening state, current song, and station information",
    responses: %{
      200 => {"Success", "application/json", Schemas.RainwaveStatus},
      503 => {"Service Unavailable", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Get current Rainwave service status.
  """
  def status(conn, _params) do
    case Rainwave.get_status() do
      {:ok, status} ->
        json(conn, %{
          success: true,
          data: %{
            rainwave: status,
            timestamp: DateTime.utc_now()
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          success: false,
          error: "Failed to get Rainwave status",
          details: inspect(reason)
        })
    end
  end

  operation(:update_config,
    summary: "Update Rainwave configuration",
    description: "Updates Rainwave service configuration including enabled state and active station",
    request_body: {"Configuration", "application/json", Schemas.RainwaveConfig},
    responses: %{
      200 => {"Success", "application/json", Schemas.SuccessResponse},
      400 => {"Bad Request", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Update Rainwave service configuration.
  """
  def update_config(conn, params) do
    config = %{}
    config = if Map.has_key?(params, "enabled"), do: Map.put(config, "enabled", params["enabled"]), else: config

    config =
      if Map.has_key?(params, "station_id"), do: Map.put(config, "station_id", params["station_id"]), else: config

    Rainwave.update_config(config)

    json(conn, %{
      success: true,
      message: "Configuration updated successfully"
    })
  end
end
