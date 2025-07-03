import Config

# Configure environment for runtime checks
config :server, env: :prod

# Production logging configuration
config :logger, level: :info

# Disable Phoenix request logging to avoid duplicate JSON logs
config :server, ServerWeb.Endpoint, log: false

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
