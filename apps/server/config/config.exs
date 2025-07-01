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

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Cluster configuration for distributed process management
config :libcluster,
  topologies: [
    landale_cluster: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        # Define all nodes in the cluster
        hosts: [
          :server@zelan,
          :server@demi,
          :server@saya,
          :server@alys
        ],
        # Use Tailscale network range
        # This will bind to any interface in the 100.x.x.x range
        if_addr: "100.0.0.0/8",
        # Custom port for cluster communication
        port: 45892,
        # Multicast settings for node discovery
        multicast_addr: "233.252.1.32",
        multicast_ttl: 1
      ]
    ]
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
