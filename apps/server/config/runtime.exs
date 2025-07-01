import Config

# Helper function to parse bind IP address
parse_bind_ip = fn
  ip_string when is_binary(ip_string) ->
    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, ip_tuple} -> ip_tuple
      # Fallback to localhost
      {:error, _} -> {127, 0, 0, 1}
    end

  _ ->
    {127, 0, 0, 1}
end

# Load environment variables from .env files (development) or system environment (Docker)
# This gracefully handles both scenarios:
# - Development: Loads from .env file if it exists
# - Docker: .env file won't exist, falls back to system environment variables

if File.exists?(".env") do
  File.read!(".env")
  |> String.split("\n")
  |> Enum.filter(fn line ->
    line = String.trim(line)
    line != "" and not String.starts_with?(line, "#")
  end)
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)
        System.put_env(key, value)

      _ ->
        :ok
    end
  end)
else
  # No .env file found (likely Docker environment)
  # Application will use system environment variables directly via System.get_env()
  :ok
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Twitch EventSub configuration (loaded from .env for all environments)
config :server,
  twitch_client_id: System.get_env("TWITCH_CLIENT_ID"),
  twitch_client_secret: System.get_env("TWITCH_CLIENT_SECRET"),
  twitch_user_id: System.get_env("TWITCH_USER_ID")

# OBS WebSocket configuration for all environments
config :server, :obs_websocket_url, "ws://demi:4455"

if config_env() == :prod do
  # Database is required for IronMON functionality
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :server, Server.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
    queue_target: 50,
    queue_interval: 1_000,
    timeout: 15_000,
    ownership_timeout: 20_000,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :server, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :server, ServerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: parse_bind_ip.(System.get_env("BIND_IP", "127.0.0.1")),
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :server, ServerWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :server, ServerWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
