import Config

# Runtime configuration for Nurvus releases
# This file is executed when the release starts

# HTTP server port
port = System.get_env("NURVUS_PORT", "4001") |> String.to_integer()

# Configuration file path
config_file = System.get_env("NURVUS_CONFIG_FILE", "processes.json")

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

config :nurvus,
  http_port: port,
  config_file: config_file

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
