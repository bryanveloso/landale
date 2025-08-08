defmodule ServerWeb.Router do
  @moduledoc "Phoenix router configuration for API endpoints."

  use ServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: ServerWeb.ApiSpec
  end

  # Rate limiting only - authentication handled by Tailscale network
  pipeline :protected_api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: ServerWeb.ApiSpec
    plug ServerWeb.Plugs.RateLimiter, max_requests: 100, interval_seconds: 60
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

  # Public API endpoints (health checks only)
  scope "/api", ServerWeb do
    pipe_through :api

    # Health and system status (public for monitoring)
    get "/health", HealthController, :detailed
    get "/health/subscriptions", HealthController, :subscriptions
  end

  # Protected API endpoints (Tailscale network provides security)
  scope "/api", ServerWeb do
    pipe_through :protected_api

    # OBS controls (require authentication)
    get "/obs/status", OBSController, :status
    post "/obs/streaming/start", OBSController, :start_streaming
    post "/obs/streaming/stop", OBSController, :stop_streaming
    post "/obs/recording/start", OBSController, :start_recording
    post "/obs/recording/stop", OBSController, :stop_recording
    get "/obs/scene/current", OBSController, :current_scene
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

    # Twitch EventSub webhook for CLI testing
    post "/eventsub", TwitchController, :webhook

    # IronMON data and statistics
    get "/ironmon/challenges", IronmonController, :list_challenges
    get "/ironmon/challenges/:id/checkpoints", IronmonController, :list_checkpoints
    get "/ironmon/checkpoints/:id/stats", IronmonController, :checkpoint_stats
    get "/ironmon/results/recent", IronmonController, :recent_results
    get "/ironmon/seeds/:id/challenge", IronmonController, :active_challenge

    # Rainwave music service
    get "/rainwave/status", RainwaveController, :status
    post "/rainwave/config", RainwaveController, :update_config

    # Control system
    get "/control/status", ControlController, :status
    get "/control/services", ControlController, :services
    get "/control/tokens", ControlController, :tokens
    post "/control/ping", ControlController, :ping

    # Service registry
    get "/services", ServiceController, :index
    get "/services/health", ServiceController, :health
    get "/services/system-health", ServiceController, :system_health
    get "/services/:id", ServiceController, :show
    get "/services/:id/health", ServiceController, :service_health

    # WebSocket API introspection
    get "/websocket/schema", WebSocketController, :schema
    get "/websocket/channels", WebSocketController, :channels
    get "/websocket/channels/:module", WebSocketController, :channel_details
    get "/websocket/examples", WebSocketController, :examples

    # Transcription data and real-time events
    get "/transcriptions", TranscriptionController, :index
    get "/transcriptions/search", TranscriptionController, :search
    get "/transcriptions/time-range", TranscriptionController, :by_time_range
    get "/transcriptions/recent", TranscriptionController, :recent
    get "/transcriptions/session/:session_id", TranscriptionController, :session
    get "/transcriptions/stats", TranscriptionController, :stats

    # SEED memory contexts
    post "/contexts", ContextController, :create
    get "/contexts", ContextController, :index
    get "/contexts/search", ContextController, :search
    get "/contexts/stats", ContextController, :stats

    # Activity Log events and analytics
    get "/activity/events", ActivityLogController, :events
    get "/activity/stats", ActivityLogController, :stats
  end
end
