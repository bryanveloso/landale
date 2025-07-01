import Config

# Worker node configuration
# This config is loaded at runtime for worker nodes

# Database configuration - workers only need minimal database access for cluster state
# Most workers may not need database access at all
database_url = System.get_env("DATABASE_URL")

if database_url do
  config :server, Server.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    socket_options: []
else
  # No database for pure worker nodes
  config :server, ecto_repos: []
end

# Disable Phoenix server for workers
config :server, ServerWeb.Endpoint, server: false

# Set worker-specific logging
config :logger,
  level: String.to_existing_atom(System.get_env("LOG_LEVEL") || "info"),
  metadata: [:node, :process, :platform]

# Cluster node name
node_name = System.get_env("RELEASE_NODE") || "server@#{System.get_env("HOSTNAME") || "worker"}"
config :server, node_name: node_name