defmodule ServerWeb.Router do
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

    # OBS controls
    get "/obs/status", OBSController, :status
    post "/obs/streaming/start", OBSController, :start_streaming
    post "/obs/streaming/stop", OBSController, :stop_streaming
    post "/obs/recording/start", OBSController, :start_recording
    post "/obs/recording/stop", OBSController, :stop_recording
    post "/obs/scene/:scene_name", OBSController, :set_scene
  end
end
