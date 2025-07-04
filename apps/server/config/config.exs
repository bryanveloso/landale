# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :server,
  ecto_repos: [Server.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :server, ServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Server.PubSub,
  live_view: [signing_salt: "er5AtYWV"]

# Configures Elixir's Logger - will be overridden to JSON in production
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :correlation_id, :service, :event_type]

# Use native JSON module for JSON parsing in Phoenix (Elixir 1.18+)
config :phoenix, :json_library, JSON

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
