import Config

# Configure environment for runtime checks
config :server, env: :prod

# Production logging configuration
config :logger, level: :info

# Compile out debug logs for production
config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Use custom JSON formatter for structured logging
config :logger, :console,
  format: {Server.JsonLogFormatter, :format},
  metadata: [
    :request_id,
    :correlation_id,
    :service,
    :operation,
    :user_id,
    :error,
    :duration_ms,
    :event_type,
    :stream_id,
    :channel_id,
    :overlay_id,
    :session_id,
    :module,
    :function,
    :line
  ]

# Disable Phoenix request logging to avoid duplicate JSON logs
config :server, ServerWeb.Endpoint, log: false

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
