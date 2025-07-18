import Config

# Runtime configuration for Nurvus releases
# This file is executed when the release starts

# HTTP server port
port = System.get_env("NURVUS_PORT", "4001") |> String.to_integer()

# Configuration file path - use XDG Base Directory by default
config_file = System.get_env("NURVUS_CONFIG_FILE")

# Logging configuration
log_level =
  case System.get_env("NURVUS_LOG_LEVEL", "info") do
    "debug" -> :debug
    "info" -> :info
    "warn" -> :warning
    "error" -> :error
    _ -> :info
  end

config :logger, level: log_level

# Only set config_file if explicitly provided via environment variable
# Otherwise let the application use its XDG default
if config_file do
  config :nurvus,
    http_port: port,
    config_file: config_file
else
  config :nurvus,
    http_port: port
end

# Production-specific configuration
if config_env() == :prod do
  # Disable debug logging in production unless explicitly set
  if System.get_env("NURVUS_LOG_LEVEL") == nil do
    config :logger, level: :info
  end

  # Production telemetry configuration
  config :telemetry,
    metrics_enabled: System.get_env("NURVUS_METRICS_ENABLED", "true") == "true"
end
