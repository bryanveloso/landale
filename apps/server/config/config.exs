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

# Game ID to show mapping configuration (migrated from root config)
config :server, :game_show_mapping, %{
  # Pokemon FireRed/LeafGreen for IronMON
  "13332" => :ironmon,
  # Software and Game Development
  "1469308723" => :coding,
  # Just Chatting
  "509658" => :variety
}

# StreamProducer timing configuration (milliseconds) (migrated from root config)
config :server,
  ticker_interval: 15_000,        # 15 seconds - ticker rotation
  sub_train_duration: 300_000,    # 5 minutes - sub train duration
  cleanup_interval: 600_000,      # 10 minutes - cleanup stale data
  max_timers: 100,                # Maximum active timers
  alert_duration: 10_000,         # 10 seconds - alert display time
  manual_override_duration: 30_000, # 30 seconds - manual override time
  default_show: :variety          # Default show when game mapping fails

# StreamProducer cleanup configuration (migrated from root config)
config :server, :cleanup_settings,
  max_interrupt_stack_size: 50,        # Max interrupts before cleanup
  interrupt_stack_keep_count: 25       # How many to keep after cleanup

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
