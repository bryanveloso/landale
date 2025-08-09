defmodule Server.Config do
  @moduledoc """
  Provides validated access to application configuration.

  All functions will raise clear errors if essential configuration is missing,
  ensuring the application fails fast on startup rather than at runtime.

  This prevents the "worked in dev, failed in prod" class of configuration errors.
  """

  @doc """
  Gets Twitch client ID - REQUIRED for EventSub subscriptions
  """
  def twitch_client_id do
    Application.fetch_env!(:server, :twitch_client_id)
  rescue
    _e in ArgumentError ->
      reraise """
              Missing required environment variable: TWITCH_CLIENT_ID

              This is required for Twitch EventSub subscriptions to work.
              Set it in your environment or config files.
              """,
              __STACKTRACE__
  end

  @doc """
  Gets Twitch client secret - REQUIRED for OAuth token refresh
  """
  def twitch_client_secret do
    Application.fetch_env!(:server, :twitch_client_secret)
  rescue
    _e in ArgumentError ->
      reraise """
              Missing required environment variable: TWITCH_CLIENT_SECRET

              This is required for OAuth token refresh to work.
              Set it in your environment or config files.
              """,
              __STACKTRACE__
  end

  @doc """
  Gets OBS WebSocket password - optional, defaults to empty string
  """
  def obs_websocket_password do
    Application.get_env(:server, :obs_websocket_password, "")
  end

  @doc """
  Gets database URL - REQUIRED for PostgreSQL connection
  """
  def database_url do
    Application.fetch_env!(:server, :database_url)
  rescue
    _e in ArgumentError ->
      reraise """
              Missing required environment variable: DATABASE_URL

              This is required for PostgreSQL database connection.
              Example: postgres://user:password@localhost:5432/database
              """,
              __STACKTRACE__
  end

  # Optional configuration with sensible defaults

  @doc """
  Gets OBS WebSocket host - defaults to localhost
  """
  def obs_websocket_host do
    Application.get_env(:server, :obs_websocket_host, "localhost")
  end

  @doc """
  Gets OBS WebSocket port - defaults to 4455
  """
  def obs_websocket_port do
    Application.get_env(:server, :obs_websocket_port, 4455)
  end

  @doc """
  Gets HTTP timeout in milliseconds - defaults to 10 seconds
  """
  def http_timeout_ms do
    Application.get_env(:server, :http_timeout_ms, 10_000)
  end

  @doc """
  Gets WebSocket reconnect interval in milliseconds - defaults to 5 seconds
  """
  def reconnect_interval_ms do
    Application.get_env(:server, :reconnect_interval_ms, 5_000)
  end

  @doc """
  Gets Phoenix secret key base - REQUIRED for session security
  """
  def secret_key_base do
    Application.fetch_env!(:server, ServerWeb.Endpoint)[:secret_key_base]
  rescue
    _e in ArgumentError ->
      reraise """
              Missing required configuration: secret_key_base

              This is required for Phoenix session security.
              Generate one with: mix phx.gen.secret
              """,
              __STACKTRACE__
  end

  @doc """
  Validates database connectivity on startup.

  Tests the database connection and verifies TimescaleDB extension is available.
  """
  def validate_database! do
    require Logger

    try do
      # Test basic connectivity
      case Ecto.Adapters.SQL.query(Server.Repo, "SELECT 1", []) do
        {:ok, _result} ->
          Logger.info("Database connectivity validated")

          # Check for TimescaleDB extension (non-critical)
          case Ecto.Adapters.SQL.query(Server.Repo, "SELECT * FROM pg_extension WHERE extname = 'timescaledb'", []) do
            {:ok, %{rows: []}} ->
              Logger.warning("TimescaleDB extension not found - time-series features may not work")

            {:ok, _result} ->
              Logger.info("TimescaleDB extension available")

            {:error, reason} ->
              Logger.warning("Could not check TimescaleDB extension: #{inspect(reason)}")
          end

          :ok

        {:error, reason} ->
          raise RuntimeError, """
          Database connectivity check failed: #{inspect(reason)}

          Ensure PostgreSQL is running and accessible at the configured DATABASE_URL.
          Check your connection settings and database server status.
          """
      end
    rescue
      error ->
        reraise RuntimeError,
                """
                Database validation failed: #{inspect(error)}

                This could indicate:
                1. PostgreSQL server is not running
                2. Database credentials are incorrect
                3. Database does not exist
                4. Network connectivity issues

                Check your DATABASE_URL configuration and database server status.
                """,
                __STACKTRACE__
    end
  end

  @doc """
  Validates all required configuration is present.

  Call this during application startup to fail fast if config is missing.
  """
  def validate_all! do
    # Call all required config functions to trigger validation
    twitch_client_id()
    twitch_client_secret()
    secret_key_base()

    # Validate database connectivity (only after repo is started)
    if Process.whereis(Server.Repo) do
      validate_database!()
    end

    :ok
  end
end
