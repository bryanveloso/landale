defmodule ServerWeb.Router do
  @moduledoc "Phoenix router configuration for API endpoints."

  use ServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health check endpoints for Docker/Kubernetes
  get "/health", ServerWeb.HealthController, :check
  get "/ready", ServerWeb.HealthController, :ready

  scope "/api", ServerWeb do
    pipe_through :api

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
  end
end
