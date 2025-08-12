defmodule Server.OAuthTokenManager do
  @moduledoc """
  Database-backed OAuth2 token management with auto-refresh.

  Uses PostgreSQL for production-ready token storage instead of DETS.
  Provides automatic token refresh, persistent storage, and telemetry integration.
  """

  require Logger

  alias Server.{Logging, OAuthAuditLog, OAuthTokenRepository, SafeTokenHandler}

  @behaviour Server.OAuthTokenManagerBehaviour

  @type token_info :: %{
          access_token: binary(),
          refresh_token: binary() | nil,
          expires_at: DateTime.t() | nil,
          scopes: MapSet.t() | nil,
          user_id: binary() | nil,
          client_id: binary() | nil
        }

  @type manager_state :: %{
          service_name: atom() | binary(),
          oauth2_client: Server.OAuth2Client.client_config(),
          token_info: token_info() | nil,
          refresh_buffer_ms: integer(),
          telemetry_prefix: [atom()]
        }

  # Default refresh buffer: 5 minutes before expiry
  @default_refresh_buffer 300_000

  @doc """
  Creates a new database-backed OAuth token manager.
  """
  @spec new(keyword()) :: {:ok, manager_state()} | {:error, term()}
  def new(opts) do
    with {:ok, service_name} <- validate_required_opt(opts, :service_name),
         {:ok, client_id} <- validate_required_opt(opts, :client_id),
         {:ok, client_secret} <- validate_required_opt(opts, :client_secret),
         {:ok, auth_url} <- validate_required_opt(opts, :auth_url),
         {:ok, token_url} <- validate_required_opt(opts, :token_url) do
      {:ok, oauth2_client} =
        Server.OAuth2Client.new(%{
          auth_url: auth_url,
          token_url: token_url,
          validate_url: Keyword.get(opts, :validate_url),
          client_id: client_id,
          client_secret: client_secret
        })

      manager = %{
        service_name: service_name,
        oauth2_client: oauth2_client,
        token_info: nil,
        refresh_buffer_ms: Keyword.get(opts, :refresh_buffer_ms, @default_refresh_buffer),
        telemetry_prefix: Keyword.get(opts, :telemetry_prefix, [:server, :oauth])
      }

      {:ok, manager}
    end
  end

  @doc """
  Loads tokens from database.
  """
  @spec load_tokens(manager_state()) :: manager_state()
  def load_tokens(manager) do
    case OAuthTokenRepository.get_token(manager.service_name) do
      {:ok, token} ->
        token_info = %{
          access_token: token.access_token,
          refresh_token: token.refresh_token,
          expires_at: token.expires_at,
          scopes: if(token.scopes, do: MapSet.new(token.scopes), else: nil),
          user_id: token.user_id,
          client_id: token.client_id || manager.oauth2_client.client_id
        }

        Logger.info("Tokens loaded from database",
          service: manager.service_name,
          has_refresh: token.refresh_token != nil
        )

        # Audit log token access
        OAuthAuditLog.log_event(:token_accessed, %{
          service: manager.service_name,
          user_id: token.user_id,
          client_id: token.client_id
        })

        %{manager | token_info: token_info}

      {:error, :not_found} ->
        Logger.info("No tokens found in database", service: manager.service_name)
        manager

      {:error, reason} ->
        Logging.log_error("Failed to load tokens from database", reason, service: manager.service_name)
        manager
    end
  end

  @doc """
  Saves tokens to database.
  """
  @spec save_tokens(manager_state()) :: :ok | {:error, term()}
  def save_tokens(manager) do
    if manager.token_info do
      token_data = %{
        access_token: manager.token_info.access_token,
        refresh_token: manager.token_info.refresh_token,
        expires_at: manager.token_info.expires_at,
        scopes: if(manager.token_info.scopes, do: MapSet.to_list(manager.token_info.scopes), else: []),
        user_id: manager.token_info.user_id,
        client_id: manager.token_info.client_id || manager.oauth2_client.client_id
      }

      case OAuthTokenRepository.save_token(manager.service_name, token_data) do
        {:ok, _token} ->
          Logger.debug("Tokens saved to database", service: manager.service_name)

          # Audit log token storage
          OAuthAuditLog.log_event(:token_stored, %{
            service: manager.service_name,
            user_id: manager.token_info.user_id,
            client_id: manager.token_info.client_id,
            has_refresh: manager.token_info.refresh_token != nil
          })

          :ok

        {:error, reason} ->
          Logger.error("Failed to save tokens to database",
            service: manager.service_name,
            error: inspect(reason)
          )

          {:error, reason}
      end
    else
      {:error, :no_token_to_save}
    end
  end

  @doc """
  Sets new token information.
  """
  @spec set_token(manager_state(), map()) :: manager_state()
  def set_token(manager, token_info) do
    processed_token = %{
      access_token: Map.get(token_info, :access_token) || Map.get(token_info, "access_token"),
      refresh_token: Map.get(token_info, :refresh_token) || Map.get(token_info, "refresh_token"),
      expires_at: parse_expires_at(token_info),
      scopes: parse_scopes(token_info),
      user_id: Map.get(token_info, :user_id) || Map.get(token_info, "user_id"),
      client_id: manager.oauth2_client.client_id
    }

    updated_manager = %{manager | token_info: processed_token}
    save_tokens(updated_manager)
    updated_manager
  end

  @doc """
  Gets a valid access token, refreshing if necessary.
  """
  @spec get_valid_token(manager_state()) :: {:ok, map(), manager_state()} | {:error, term()}
  def get_valid_token(manager) do
    case manager.token_info do
      nil ->
        Logger.debug("Token info unavailable", service: manager.service_name)
        {:error, :no_token_available}

      token_info ->
        if token_needs_refresh?(token_info, manager.refresh_buffer_ms) do
          handle_token_refresh(manager, token_info)
        else
          {:ok, token_info, manager}
        end
    end
  end

  @doc """
  Refreshes the OAuth token using the refresh token.
  """
  @spec refresh_token(manager_state()) :: {:ok, manager_state()} | {:error, term()}
  def refresh_token(manager) do
    case manager.token_info do
      nil ->
        {:error, :no_token_for_refresh}

      %{refresh_token: nil} ->
        {:error, :no_refresh_token}

      %{refresh_token: refresh_token} ->
        Logger.info("Token refresh started", service: manager.service_name)
        emit_telemetry(manager, [:refresh, :attempt])

        case Server.OAuth2Client.refresh_token(manager.oauth2_client, refresh_token) do
          {:ok, new_tokens} ->
            Logger.info("Token refresh completed", service: manager.service_name)
            emit_telemetry(manager, [:refresh, :success])

            # Audit log successful refresh
            OAuthAuditLog.log_event(:token_refreshed, %{
              service: manager.service_name,
              user_id: manager.token_info.user_id,
              client_id: manager.oauth2_client.client_id
            })

            # Normalize new tokens
            safe_tokens = SafeTokenHandler.normalize(new_tokens)

            # Update token info
            new_token_info = %{
              access_token: safe_tokens[:access_token],
              refresh_token: safe_tokens[:refresh_token] || refresh_token,
              expires_at: calculate_expires_at(safe_tokens[:expires_in]),
              scopes: manager.token_info.scopes,
              user_id: manager.token_info.user_id,
              client_id: manager.oauth2_client.client_id
            }

            updated_manager = %{manager | token_info: new_token_info}
            save_tokens(updated_manager)

            {:ok, updated_manager}

          {:error, reason} ->
            Logging.log_error("Token refresh failed", inspect(reason), service: manager.service_name)
            emit_telemetry(manager, [:refresh, :failure], %{reason: inspect(reason)})

            # Audit log refresh failure
            OAuthAuditLog.log_event(:refresh_failed, %{
              service: manager.service_name,
              user_id: manager.token_info.user_id,
              client_id: manager.oauth2_client.client_id,
              error: inspect(reason)
            })

            {:error, reason}
        end
    end
  end

  @doc """
  Validates the current access token.
  """
  @spec validate_token(manager_state(), binary()) :: {:ok, map(), manager_state()} | {:error, term()}
  def validate_token(manager, _validate_url) do
    case manager.token_info do
      nil ->
        {:error, :no_token_for_validation}

      %{access_token: access_token} ->
        case Server.OAuth2Client.validate_token(manager.oauth2_client, access_token) do
          {:ok, validation_data} ->
            # Update token info with validation data
            safe_validation = SafeTokenHandler.normalize(validation_data)

            updated_token_info =
              Map.merge(manager.token_info, %{
                user_id: safe_validation[:user_id] || manager.token_info.user_id,
                scopes:
                  if(safe_validation[:scopes],
                    do: MapSet.new(safe_validation[:scopes]),
                    else: manager.token_info.scopes
                  )
              })

            updated_manager = %{manager | token_info: updated_token_info}
            save_tokens(updated_manager)

            {:ok, validation_data, updated_manager}

          {:error, reason} ->
            Logging.log_error("Token validation failed", inspect(reason), service: manager.service_name)
            {:error, reason}
        end
    end
  end

  @doc """
  No-op for database backend (no DETS to close).
  """
  @spec close(manager_state()) :: :ok
  def close(_manager), do: :ok

  # Private helper functions

  defp validate_required_opt(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:error, {:missing_required_option, key}}
      value -> {:ok, value}
    end
  end

  defp handle_token_refresh(manager, token_info) do
    Logger.info("Token refresh required",
      service: manager.service_name,
      expires_at: token_info.expires_at
    )

    case refresh_token(manager) do
      {:ok, updated_manager} ->
        Logger.info("Token refreshed successfully",
          service: manager.service_name,
          new_expires_at: updated_manager.token_info.expires_at
        )

        {:ok, updated_manager.token_info, updated_manager}

      {:error, reason} ->
        Logger.warning("Token refresh failed, using existing token",
          error: reason,
          service: manager.service_name
        )

        # Return existing token if still valid
        if token_info.expires_at && DateTime.compare(token_info.expires_at, DateTime.utc_now()) == :gt do
          {:ok, token_info, manager}
        else
          {:error, reason}
        end
    end
  end

  defp token_needs_refresh?(token_info, buffer_ms) do
    case token_info.expires_at do
      nil ->
        false

      expires_at ->
        buffer_time = DateTime.add(DateTime.utc_now(), buffer_ms, :millisecond)
        DateTime.compare(expires_at, buffer_time) == :lt
    end
  end

  defp parse_expires_at(%{expires_at: expires_at}) when is_integer(expires_at) do
    DateTime.from_unix!(expires_at)
  end

  defp parse_expires_at(%{"expires_at" => expires_at}) when is_integer(expires_at) do
    DateTime.from_unix!(expires_at)
  end

  defp parse_expires_at(%{expires_in: expires_in}) when is_integer(expires_in) do
    calculate_expires_at(expires_in)
  end

  defp parse_expires_at(%{"expires_in" => expires_in}) when is_integer(expires_in) do
    calculate_expires_at(expires_in)
  end

  defp parse_expires_at(_), do: nil

  defp calculate_expires_at(expires_in) when is_integer(expires_in) do
    DateTime.add(DateTime.utc_now(), expires_in, :second)
  end

  defp calculate_expires_at(_), do: nil

  defp parse_scopes(%{scopes: scopes}) when is_list(scopes), do: MapSet.new(scopes)
  defp parse_scopes(%{"scopes" => scopes}) when is_list(scopes), do: MapSet.new(scopes)
  defp parse_scopes(%{scope: scope}) when is_binary(scope), do: MapSet.new(String.split(scope, " "))
  defp parse_scopes(%{"scope" => scope}) when is_binary(scope), do: MapSet.new(String.split(scope, " "))
  defp parse_scopes(_), do: nil

  defp emit_telemetry(_manager, _event_suffix, _metadata \\ %{}) do
    :ok
  end
end
