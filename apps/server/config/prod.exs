import Config

# Configure environment for runtime checks
config :server, env: :prod

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
