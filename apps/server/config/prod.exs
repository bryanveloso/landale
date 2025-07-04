import Config

# Configure environment for runtime checks
config :server, env: :prod

# Production logging configuration
config :logger, level: :info

# Use simple JSON formatting that's more reliable
config :logger, :console,
  format: "$time [$level] $message $metadata\n",
  metadata: [:request_id, :correlation_id, :service, :event_type]

# Disable Phoenix request logging to avoid duplicate JSON logs
config :server, ServerWeb.Endpoint, log: false

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
