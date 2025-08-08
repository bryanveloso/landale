import Config

# Configure environment for runtime checks
config :server, env: :test

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Use DATABASE_URL if provided (CI), otherwise use local config
if database_url = System.get_env("DATABASE_URL") do
  config :server, Server.Repo,
    url: database_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
else
  config :server, Server.Repo,
    username: "Avalonstar",
    password: "",
    hostname: "localhost",
    database: "server_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :server, ServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+xWDd5KBD+68cbXwuhJhR6wnkXubwSvFC+YaDXn5euf5Jyb5+zQ/KPu4/xXhcyNl",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure mock modules for testing
config :server, :services,
  obs: Server.Mocks.OBSMock,
  twitch: Server.Mocks.TwitchMock,
  ironmon_tcp: Server.Mocks.IronmonTCPMock,
  rainwave: Server.Mocks.RainwaveMock

# Configure test Twitch credentials to allow service startup in tests
config :server, :twitch,
  client_id: "test_client_id",
  client_secret: "test_client_secret",
  client_impl: Server.Services.TwitchClientMock

# Configure test encryption key for token vault
config :server, Server.TokenVault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1", key: Base.decode64!("test1234567890abcdef1234567890abcdef1234567="), iv_length: 12
    }
  ]
