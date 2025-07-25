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
    ArgumentError ->
      raise """
      Missing required environment variable: TWITCH_CLIENT_ID

      This is required for Twitch EventSub subscriptions to work.
      Set it in your environment or config files.
      """
  end

  @doc """
  Gets Twitch client secret - REQUIRED for OAuth token refresh
  """
  def twitch_client_secret do
    Application.fetch_env!(:server, :twitch_client_secret)
  rescue
    ArgumentError ->
      raise """
      Missing required environment variable: TWITCH_CLIENT_SECRET

      This is required for OAuth token refresh to work.
      Set it in your environment or config files.
      """
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
    ArgumentError ->
      raise """
      Missing required environment variable: DATABASE_URL

      This is required for PostgreSQL database connection.
      Example: postgres://user:password@localhost:5432/database
      """
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
    Application.fetch_env!(:server, Server.Endpoint)[:secret_key_base]
  rescue
    ArgumentError ->
      raise """
      Missing required configuration: secret_key_base

      This is required for Phoenix session security.
      Generate one with: mix phx.gen.secret
      """
  end

  @doc """
  Validates all required configuration is present.

  Call this during application startup to fail fast if config is missing.
  """
  def validate_all! do
    # Call all required config functions to trigger validation
    twitch_client_id()
    twitch_client_secret()
    database_url()
    secret_key_base()

    :ok
  end
end
