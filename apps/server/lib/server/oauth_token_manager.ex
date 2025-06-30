defmodule Server.OAuthTokenManager do
  @moduledoc """
  Reusable OAuth2 token management with DETS persistence and auto-refresh.

  Provides a standardized way to manage OAuth2 tokens with automatic refresh,
  persistent storage using DETS, and telemetry integration. Designed to be
  used by services that need OAuth2 authentication (e.g., Twitch, Discord, etc.).

  ## Features

  - Automatic token refresh before expiration
  - DETS-based persistent storage
  - Environment-aware storage paths (dev vs Docker)
  - Telemetry integration for monitoring
  - Graceful error handling and recovery

  ## Usage

      # Initialize token manager
      {:ok, manager} = OAuthTokenManager.new(
        storage_key: :twitch_tokens,
        client_id: "your_client_id",
        client_secret: "your_client_secret",
        token_url: "https://id.twitch.tv/oauth2/token",
        validate_url: "https://id.twitch.tv/oauth2/validate",
        telemetry_prefix: [:server, :twitch, :oauth]
      )
      
      # Load existing tokens
      manager = OAuthTokenManager.load_tokens(manager)
      
      # Get current valid token (auto-refreshes if needed)
      case OAuthTokenManager.get_valid_token(manager) do
        {:ok, token, updated_manager} -> 
          # Use token for API calls
        {:error, reason} -> 
          # Handle token unavailable
      end
      
      # Manually refresh token
      case OAuthTokenManager.refresh_token(manager) do
        {:ok, updated_manager} -> 
          # Token refreshed successfully
        {:error, reason} -> 
          # Refresh failed
      end
  """

  require Logger

  @type token_info :: %{
          access_token: binary(),
          refresh_token: binary() | nil,
          expires_at: DateTime.t() | nil,
          scopes: MapSet.t() | nil,
          user_id: binary() | nil
        }

  @type manager_state :: %{
          storage_key: atom(),
          storage_path: binary(),
          dets_table: atom() | nil,
          oauth_client: OAuth2.Client.t(),
          token_info: token_info() | nil,
          refresh_buffer_ms: integer(),
          telemetry_prefix: [atom()]
        }

  # Default refresh buffer: 5 minutes before expiry
  @default_refresh_buffer 300_000

  @doc """
  Creates a new OAuth token manager.

  ## Parameters
  - `opts` - Configuration options
    - `:storage_key` - Unique key for DETS storage (required)
    - `:client_id` - OAuth2 client ID (required)
    - `:client_secret` - OAuth2 client secret (required)
    - `:token_url` - OAuth2 token endpoint URL (required)
    - `:validate_url` - Token validation endpoint URL (optional)
    - `:storage_path` - Custom storage path (optional, auto-detected)
    - `:refresh_buffer_ms` - Refresh buffer time in milliseconds (default: 300000)
    - `:telemetry_prefix` - Telemetry event prefix (default: [:server, :oauth])

  ## Returns
  - `{:ok, manager}` - Manager created successfully
  - `{:error, reason}` - Creation failed
  """
  @spec new(keyword()) :: {:ok, manager_state()} | {:error, term()}
  def new(opts) do
    with {:ok, storage_key} <- validate_required_opt(opts, :storage_key),
         {:ok, client_id} <- validate_required_opt(opts, :client_id),
         {:ok, client_secret} <- validate_required_opt(opts, :client_secret),
         {:ok, token_url} <- validate_required_opt(opts, :token_url) do
      storage_path = Keyword.get(opts, :storage_path) || get_default_storage_path(storage_key)

      oauth_client =
        OAuth2.Client.new(
          strategy: OAuth2.Strategy.Refresh,
          client_id: client_id,
          client_secret: client_secret,
          token_url: token_url
        )

      manager = %{
        storage_key: storage_key,
        storage_path: storage_path,
        dets_table: nil,
        oauth_client: oauth_client,
        token_info: nil,
        refresh_buffer_ms: Keyword.get(opts, :refresh_buffer_ms, @default_refresh_buffer),
        telemetry_prefix: Keyword.get(opts, :telemetry_prefix, [:server, :oauth])
      }

      {:ok, manager}
    end
  end

  @doc """
  Opens DETS storage and loads existing tokens.

  ## Parameters
  - `manager` - Token manager state

  ## Returns
  - Updated manager with loaded tokens
  """
  @spec load_tokens(manager_state()) :: manager_state()
  def load_tokens(manager) do
    # Ensure storage directory exists
    storage_dir = Path.dirname(manager.storage_path)
    File.mkdir_p!(storage_dir)

    # Open DETS table
    case :dets.open_file(manager.storage_key, file: String.to_charlist(manager.storage_path)) do
      {:ok, table} ->
        manager = %{manager | dets_table: table}

        # Load existing token
        case :dets.lookup(table, :token) do
          [{:token, token_data}] ->
            Logger.info("Loaded existing OAuth tokens", storage_key: manager.storage_key)
            %{manager | token_info: deserialize_token(token_data)}

          [] ->
            Logger.info("No existing OAuth tokens found", storage_key: manager.storage_key)
            manager
        end

      {:error, reason} ->
        Logger.error("Failed to open OAuth token storage",
          storage_key: manager.storage_key,
          path: manager.storage_path,
          reason: reason
        )

        manager
    end
  end

  @doc """
  Saves tokens to DETS storage.

  ## Parameters
  - `manager` - Token manager state

  ## Returns
  - `:ok` - Tokens saved successfully
  - `{:error, reason}` - Save failed
  """
  @spec save_tokens(manager_state()) :: :ok | {:error, term()}
  def save_tokens(manager) do
    if manager.dets_table && manager.token_info do
      serialized = serialize_token(manager.token_info)

      case :dets.insert(manager.dets_table, {:token, serialized}) do
        :ok ->
          :dets.sync(manager.dets_table)
          Logger.debug("OAuth tokens saved to storage", storage_key: manager.storage_key)
          :ok

        {:error, reason} ->
          Logger.error("Failed to save OAuth tokens",
            storage_key: manager.storage_key,
            reason: reason
          )

          {:error, reason}
      end
    else
      {:error, "No DETS table or token info available"}
    end
  end

  @doc """
  Sets new token information.

  ## Parameters
  - `manager` - Token manager state
  - `token_info` - New token information map

  ## Returns
  - Updated manager with new token info
  """
  @spec set_token(manager_state(), map()) :: manager_state()
  def set_token(manager, token_info) do
    processed_token = %{
      access_token: token_info.access_token || token_info["access_token"],
      refresh_token: token_info.refresh_token || token_info["refresh_token"],
      expires_at: parse_expires_at(token_info),
      scopes: parse_scopes(token_info),
      user_id: token_info.user_id || token_info["user_id"]
    }

    updated_manager = %{manager | token_info: processed_token}
    save_tokens(updated_manager)
    updated_manager
  end

  @doc """
  Gets a valid access token, refreshing if necessary.

  ## Parameters
  - `manager` - Token manager state

  ## Returns
  - `{:ok, token, updated_manager}` - Valid token retrieved
  - `{:error, reason}` - No valid token available
  """
  @spec get_valid_token(manager_state()) :: {:ok, binary(), manager_state()} | {:error, term()}
  def get_valid_token(manager) do
    case manager.token_info do
      nil ->
        {:error, "No token available"}

      token_info ->
        if token_needs_refresh?(token_info, manager.refresh_buffer_ms) do
          case refresh_token(manager) do
            {:ok, updated_manager} ->
              {:ok, updated_manager.token_info.access_token, updated_manager}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:ok, token_info.access_token, manager}
        end
    end
  end

  @doc """
  Refreshes the OAuth token using the refresh token.

  ## Parameters
  - `manager` - Token manager state

  ## Returns
  - `{:ok, updated_manager}` - Token refreshed successfully
  - `{:error, reason}` - Refresh failed
  """
  @spec refresh_token(manager_state()) :: {:ok, manager_state()} | {:error, term()}
  def refresh_token(manager) do
    case manager.token_info do
      nil ->
        {:error, "No token info available for refresh"}

      %{refresh_token: nil} ->
        {:error, "No refresh token available"}

      %{refresh_token: refresh_token} ->
        Logger.info("Refreshing OAuth token", storage_key: manager.storage_key)
        emit_telemetry(manager, [:refresh, :attempt])

        # Create OAuth2 client with current refresh token
        token = %OAuth2.AccessToken{
          access_token: manager.token_info.access_token,
          refresh_token: refresh_token
        }

        client = %{manager.oauth_client | token: token}

        case OAuth2.Client.refresh_token(client) do
          {:ok, %OAuth2.Client{token: new_token}} ->
            Logger.info("OAuth token refreshed successfully", storage_key: manager.storage_key)
            emit_telemetry(manager, [:refresh, :success])

            # Update token info
            new_token_info = %{
              access_token: new_token.access_token,
              refresh_token: new_token.refresh_token || refresh_token,
              expires_at: calculate_expires_at(new_token.expires_at),
              scopes: manager.token_info.scopes,
              user_id: manager.token_info.user_id
            }

            updated_manager = %{manager | token_info: new_token_info}
            save_tokens(updated_manager)

            {:ok, updated_manager}

          {:error, reason} ->
            Logger.error("OAuth token refresh failed",
              storage_key: manager.storage_key,
              reason: inspect(reason)
            )

            emit_telemetry(manager, [:refresh, :failure], %{reason: inspect(reason)})
            {:error, reason}
        end
    end
  end

  @doc """
  Validates the current access token.

  ## Parameters
  - `manager` - Token manager state
  - `validate_url` - Token validation endpoint URL

  ## Returns
  - `{:ok, validation_data, updated_manager}` - Token is valid
  - `{:error, reason}` - Token is invalid or validation failed
  """
  @spec validate_token(manager_state(), binary()) :: {:ok, map(), manager_state()} | {:error, term()}
  def validate_token(manager, validate_url) do
    case manager.token_info do
      nil ->
        {:error, "No token available for validation"}

      %{access_token: access_token} ->
        headers = [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]

        case :httpc.request(:get, {String.to_charlist(validate_url), headers}, [], []) do
          {:ok, {{_version, 200, _reason}, _headers, body}} ->
            case Jason.decode(List.to_string(body)) do
              {:ok, data} ->
                # Update token info with validation data
                updated_token_info =
                  Map.merge(manager.token_info, %{
                    user_id: data["user_id"],
                    scopes: MapSet.new(data["scopes"] || [])
                  })

                updated_manager = %{manager | token_info: updated_token_info}
                save_tokens(updated_manager)

                {:ok, data, updated_manager}

              {:error, reason} ->
                {:error, "Failed to parse validation response: #{inspect(reason)}"}
            end

          {:ok, {{_version, status, _reason}, _headers, body}} ->
            {:error, "Token validation failed with status #{status}: #{List.to_string(body)}"}

          {:error, reason} ->
            {:error, "Token validation request failed: #{inspect(reason)}"}
        end
    end
  end

  @doc """
  Closes DETS storage.

  ## Parameters
  - `manager` - Token manager state

  ## Returns
  - `:ok`
  """
  @spec close(manager_state()) :: :ok
  def close(manager) do
    if manager.dets_table do
      :dets.close(manager.dets_table)
    end

    :ok
  end

  # Private helper functions

  defp validate_required_opt(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:error, "Missing required option: #{key}"}
      value -> {:ok, value}
    end
  end

  defp get_default_storage_path(storage_key) do
    case Mix.env() do
      :prod ->
        # Docker production environment
        "/app/data/#{storage_key}.dets"

      _ ->
        # Development environment
        data_dir = "./data"
        File.mkdir_p!(data_dir)
        Path.join(data_dir, "#{storage_key}.dets")
    end
  end

  defp serialize_token(token_info) do
    %{
      access_token: token_info.access_token,
      refresh_token: token_info.refresh_token,
      expires_at: token_info.expires_at && DateTime.to_iso8601(token_info.expires_at),
      scopes: token_info.scopes && MapSet.to_list(token_info.scopes),
      user_id: token_info.user_id
    }
  end

  defp deserialize_token(token_data) do
    %{
      access_token: token_data.access_token,
      refresh_token: token_data.refresh_token,
      expires_at: token_data.expires_at && parse_stored_datetime(token_data.expires_at),
      scopes: token_data.scopes && MapSet.new(token_data.scopes),
      user_id: token_data.user_id
    }
  end

  defp parse_expires_at(%{expires_at: expires_at}) when is_integer(expires_at) do
    DateTime.from_unix!(expires_at)
  end

  defp parse_expires_at(%{"expires_at" => expires_at}) when is_integer(expires_at) do
    DateTime.from_unix!(expires_at)
  end

  defp parse_expires_at(%{expires_in: expires_in}) when is_integer(expires_in) do
    DateTime.add(DateTime.utc_now(), expires_in, :second)
  end

  defp parse_expires_at(%{"expires_in" => expires_in}) when is_integer(expires_in) do
    DateTime.add(DateTime.utc_now(), expires_in, :second)
  end

  defp parse_expires_at(_), do: nil

  defp parse_scopes(%{scopes: scopes}) when is_list(scopes), do: MapSet.new(scopes)
  defp parse_scopes(%{"scopes" => scopes}) when is_list(scopes), do: MapSet.new(scopes)
  defp parse_scopes(%{scope: scope}) when is_binary(scope), do: MapSet.new(String.split(scope, " "))
  defp parse_scopes(%{"scope" => scope}) when is_binary(scope), do: MapSet.new(String.split(scope, " "))
  defp parse_scopes(_), do: nil

  defp calculate_expires_at(expires_at) when is_integer(expires_at) do
    DateTime.from_unix!(expires_at)
  end

  defp calculate_expires_at(_), do: nil

  defp parse_stored_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp parse_stored_datetime(_), do: nil

  defp token_needs_refresh?(token_info, buffer_ms) do
    case token_info.expires_at do
      nil ->
        false

      expires_at ->
        buffer_time = DateTime.add(DateTime.utc_now(), buffer_ms, :millisecond)
        DateTime.compare(expires_at, buffer_time) == :lt
    end
  end

  defp emit_telemetry(manager, event_suffix, metadata \\ %{}) do
    event = manager.telemetry_prefix ++ event_suffix
    :telemetry.execute(event, %{}, Map.put(metadata, :storage_key, manager.storage_key))
  end
end
