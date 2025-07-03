import Config

# Configure environment for runtime checks
config :server, env: :prod

# Production logging configuration with structured JSON
config :logger, level: :info

# Configure JSON logging for production
config :logger, :console,
  format: {LoggerJSON.Formatters.BasicLogger, :format},
  metadata: [:request_id, :correlation_id, :service, :event_type]

# Disable Phoenix request logging to avoid duplicate JSON logs
config :server, ServerWeb.Endpoint, log: false

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
