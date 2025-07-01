defmodule ServerWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Landale streaming server API.
  """

  alias OpenApiSpex.{Components, Info, OpenApi, Paths, Server}
  alias ServerWeb.{Router, Schemas}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Landale Streaming Server API",
        description: """
        REST API for the Landale streaming overlay system.

        This API provides endpoints for:
        - OBS WebSocket integration and controls
        - Twitch EventSub subscription management  
        - IronMON Pokemon challenge data
        - Distributed process management across cluster nodes
        - System health and monitoring
        - Real-time dashboard communication

        All endpoints require API key authentication via X-API-Key header.
        All endpoints return JSON and follow RESTful conventions.
        """,
        version: "1.0.0"
      },
      servers: [
        Server.from_endpoint(ServerWeb.Endpoint)
      ],
      paths: paths(),
      components: %Components{
        schemas: schemas()
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp paths do
    Paths.from_router(Router)
  end

  defp schemas do
    %{
      # Common response schemas
      "SuccessResponse" => Schemas.SuccessResponse,
      "ErrorResponse" => Schemas.ErrorResponse,

      # Health schemas
      "HealthStatus" => Schemas.HealthStatus,
      "ServiceStatus" => Schemas.ServiceStatus,

      # OBS schemas
      "OBSStatus" => Schemas.OBSStatus,
      "OBSScenes" => Schemas.OBSScenes,
      "OBSStreamStatus" => Schemas.OBSStreamStatus,

      # Twitch schemas
      "TwitchStatus" => Schemas.TwitchStatus,
      "TwitchSubscription" => Schemas.TwitchSubscription,
      "TwitchSubscriptionTypes" => Schemas.TwitchSubscriptionTypes,

      # IronMON schemas
      "IronmonChallenge" => Schemas.IronmonChallenge,
      "IronmonCheckpoint" => Schemas.IronmonCheckpoint,
      "IronmonResult" => Schemas.IronmonResult,

      # Process management schemas
      "ProcessStatus" => Schemas.ProcessStatus,
      "ClusterStatus" => Schemas.ClusterStatus,
      "NodeProcesses" => Schemas.NodeProcesses,
      "ProcessActionResponse" => Schemas.ProcessActionResponse,

      # Request schemas
      "CreateTwitchSubscription" => Schemas.CreateTwitchSubscription
    }
  end
end
