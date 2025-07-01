defmodule ServerWeb.Router do
  @moduledoc "Phoenix router configuration for API endpoints."

  use ServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: ServerWeb.ApiSpec
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug ServerWeb.Plugs.ApiAuth
    plug OpenApiSpex.Plug.PutApiSpec, module: ServerWeb.ApiSpec
  end

  pipeline :browser do
    plug :accepts, ["html"]
  end

  # Health check endpoints for Docker/Kubernetes
  get "/health", ServerWeb.HealthController, :check
  get "/ready", ServerWeb.HealthController, :ready

  # API Documentation
  scope "/docs" do
    pipe_through :browser
    get "/", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  scope "/api" do
    pipe_through :api
    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api", ServerWeb do
    pipe_through :authenticated_api

    # Health and system status
    get "/health", HealthController, :detailed
    get "/health/subscriptions", HealthController, :subscriptions

    # OBS controls
    get "/obs/status", OBSController, :status
    post "/obs/streaming/start", OBSController, :start_streaming
    post "/obs/streaming/stop", OBSController, :stop_streaming
    post "/obs/recording/start", OBSController, :start_recording
    post "/obs/recording/stop", OBSController, :stop_recording
    post "/obs/scene/:scene_name", OBSController, :set_scene

    # Enhanced OBS endpoints for dashboard metrics
    get "/obs/scenes", OBSController, :scenes
    get "/obs/stream-status", OBSController, :stream_status
    get "/obs/record-status", OBSController, :record_status
    get "/obs/stats", OBSController, :stats
    get "/obs/version", OBSController, :version
    get "/obs/virtual-cam", OBSController, :virtual_cam
    get "/obs/outputs", OBSController, :outputs

    # Twitch EventSub management
    get "/twitch/status", TwitchController, :status
    get "/twitch/subscriptions", TwitchController, :subscriptions
    post "/twitch/subscriptions", TwitchController, :create_subscription
    delete "/twitch/subscriptions/:id", TwitchController, :delete_subscription
    get "/twitch/subscription-types", TwitchController, :subscription_types

    # IronMON data and statistics
    get "/ironmon/challenges", IronmonController, :list_challenges
    get "/ironmon/challenges/:id/checkpoints", IronmonController, :list_checkpoints
    get "/ironmon/checkpoints/:id/stats", IronmonController, :checkpoint_stats
    get "/ironmon/results/recent", IronmonController, :recent_results
    get "/ironmon/seeds/:id/challenge", IronmonController, :active_challenge

    # Control system
    get "/control/status", ControlController, :status
    get "/control/services", ControlController, :services
    post "/control/ping", ControlController, :ping

    # Distributed process management
    get "/processes/cluster", ProcessController, :cluster_status
    get "/processes/:node", ProcessController, :node_processes
    get "/processes/:node/:process", ProcessController, :process_status
    post "/processes/:node/:process/start", ProcessController, :start_process
    post "/processes/:node/:process/stop", ProcessController, :stop_process
    post "/processes/:node/:process/restart", ProcessController, :restart_process
  end
end
