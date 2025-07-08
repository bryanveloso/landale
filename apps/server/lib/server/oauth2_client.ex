defmodule Server.OAuth2Client do
  @moduledoc """
  Extensible OAuth2 client using Gun HTTP client.

  Provides a clean, provider-agnostic interface for OAuth2 authentication flows
  including authorization code exchange, token refresh, and token validation.
  Designed to work with any OAuth2 provider (Twitch, Discord, GitHub, etc.).

  ## Usage

      # Initialize client for any OAuth2 provider
      client = OAuth2Client.new(%{
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        validate_url: "https://id.twitch.tv/oauth2/validate",
        client_id: "your_client_id",
        client_secret: "your_client_secret"
      })

      # Exchange authorization code for tokens
      case OAuth2Client.exchange_code(client, code, redirect_uri) do
        {:ok, tokens} -> 
          # tokens contains access_token, refresh_token, expires_in, scope
        {:error, reason} ->
          # Handle error
      end

      # Refresh access token
      case OAuth2Client.refresh_token(client, refresh_token) do
        {:ok, new_tokens} ->
          # Use new tokens
        {:error, reason} ->
          # Handle refresh failure  
      end

      # Validate token
      case OAuth2Client.validate_token(client, access_token) do
        {:ok, user_info} ->
          # Token is valid, user_info contains user details
        {:error, reason} ->
          # Token is invalid or validation failed
      end

  ## Configuration

  The client requires these configuration parameters:

  - `:auth_url` - OAuth2 authorization endpoint URL
  - `:token_url` - OAuth2 token endpoint URL  
  - `:validate_url` - Token validation endpoint URL (optional)
  - `:client_id` - OAuth2 client ID
  - `:client_secret` - OAuth2 client secret
  - `:timeout` - HTTP request timeout in milliseconds (default: 10000)
  - `:telemetry_prefix` - Telemetry event prefix (default: [:server, :oauth2])

  ## Error Handling

  All functions return `{:ok, result}` or `{:error, reason}` tuples.
  Common error reasons include:

  - `:timeout` - Request timed out
  - `:invalid_grant` - Authorization code or refresh token is invalid
  - `:unauthorized` - Client credentials are invalid
  - `{:http_error, status, body}` - HTTP error response
  - `{:network_error, reason}` - Network connectivity issue
  """

  require Logger
  
  alias Server.ExternalCall

  @type client_config :: %{
          auth_url: binary(),
          token_url: binary(),
          validate_url: binary() | nil,
          client_id: binary(),
          client_secret: binary(),
          timeout: integer(),
          telemetry_prefix: [atom()]
        }

  @type token_response :: %{
          access_token: binary(),
          refresh_token: binary() | nil,
          expires_in: integer() | nil,
          scope: [binary()] | nil,
          token_type: binary()
        }

  @type validation_response :: %{
          user_id: binary() | nil,
          client_id: binary() | nil,
          scopes: [binary()] | nil,
          expires_in: integer() | nil
        }

  @default_timeout 10_000
  @default_telemetry_prefix [:server, :oauth2]

  @doc """
  Creates a new OAuth2 client with the given configuration.

  ## Parameters
  - `config` - Map containing OAuth2 provider configuration

  ## Returns
  - `{:ok, client}` - Client created successfully
  - `{:error, reason}` - Configuration invalid

  ## Example
      {:ok, client} = OAuth2Client.new(%{
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        validate_url: "https://id.twitch.tv/oauth2/validate",
        client_id: "your_client_id",
        client_secret: "your_client_secret"
      })
  """
  @spec new(map()) :: {:ok, client_config()} | {:error, term()}
  def new(config) do
    with {:ok, auth_url} <- validate_required(config, :auth_url),
         {:ok, token_url} <- validate_required(config, :token_url),
         {:ok, client_id} <- validate_required(config, :client_id),
         {:ok, client_secret} <- validate_required(config, :client_secret) do
      client = %{
        auth_url: auth_url,
        token_url: token_url,
        validate_url: Map.get(config, :validate_url),
        client_id: client_id,
        client_secret: client_secret,
        timeout: Map.get(config, :timeout, @default_timeout),
        telemetry_prefix: Map.get(config, :telemetry_prefix, @default_telemetry_prefix)
      }

      {:ok, client}
    end
  end

  @doc """
  Exchanges an authorization code for access and refresh tokens.

  ## Parameters
  - `client` - OAuth2 client configuration
  - `code` - Authorization code from OAuth2 authorization flow
  - `redirect_uri` - Redirect URI used in authorization request

  ## Returns
  - `{:ok, tokens}` - Token exchange successful
  - `{:error, reason}` - Exchange failed

  ## Example
      case OAuth2Client.exchange_code(client, "auth_code_123", "http://localhost:8008/callback") do
        {:ok, %{access_token: token, refresh_token: refresh}} ->
          # Store tokens
        {:error, reason} ->
          # Handle error
      end
  """
  @spec exchange_code(client_config(), binary(), binary()) :: {:ok, token_response()} | {:error, term()}
  def exchange_code(client, code, redirect_uri) do
    params = %{
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri,
      client_id: client.client_id,
      client_secret: client.client_secret
    }

    emit_telemetry(client, [:exchange, :attempt])

    case make_token_request(client, params) do
      {:ok, tokens} ->
        emit_telemetry(client, [:exchange, :success])
        {:ok, tokens}

      {:error, reason} = error ->
        emit_telemetry(client, [:exchange, :failure], %{reason: inspect(reason)})
        error
    end
  end

  @doc """
  Refreshes an access token using a refresh token.

  ## Parameters
  - `client` - OAuth2 client configuration
  - `refresh_token` - Refresh token to exchange for new access token

  ## Returns
  - `{:ok, tokens}` - Token refresh successful
  - `{:error, reason}` - Refresh failed

  ## Example
      case OAuth2Client.refresh_token(client, refresh_token) do
        {:ok, %{access_token: new_token}} ->
          # Use new access token
        {:error, reason} ->
          # Handle refresh failure
      end
  """
  @spec refresh_token(client_config(), binary()) :: {:ok, token_response()} | {:error, term()}
  def refresh_token(client, refresh_token) do
    params = %{
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: client.client_id,
      client_secret: client.client_secret
    }

    emit_telemetry(client, [:refresh, :attempt])

    case make_token_request(client, params) do
      {:ok, tokens} ->
        emit_telemetry(client, [:refresh, :success])
        {:ok, tokens}

      {:error, reason} = error ->
        emit_telemetry(client, [:refresh, :failure], %{reason: inspect(reason)})
        error
    end
  end

  @doc """
  Validates an access token against the OAuth2 provider.

  ## Parameters
  - `client` - OAuth2 client configuration
  - `access_token` - Access token to validate

  ## Returns
  - `{:ok, user_info}` - Token is valid
  - `{:error, reason}` - Token is invalid or validation failed

  ## Example
      case OAuth2Client.validate_token(client, access_token) do
        {:ok, %{user_id: user_id, scopes: scopes}} ->
          # Token is valid
        {:error, reason} ->
          # Token is invalid
      end
  """
  @spec validate_token(client_config(), binary()) :: {:ok, validation_response()} | {:error, term()}
  def validate_token(client, access_token) do
    case client.validate_url do
      nil ->
        {:error, :no_validation_url}

      validate_url ->
        emit_telemetry(client, [:validate, :attempt])

        case make_validation_request(client, validate_url, access_token) do
          {:ok, user_info} ->
            emit_telemetry(client, [:validate, :success])
            {:ok, user_info}

          {:error, reason} = error ->
            emit_telemetry(client, [:validate, :failure], %{reason: inspect(reason)})
            error
        end
    end
  end

  # Private functions

  defp validate_required(config, key) do
    case Map.get(config, key) do
      nil -> {:error, {:missing_required_config, key}}
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_config, key, "must be non-empty string"}}
    end
  end

  defp make_token_request(client, params) do
    # Extract service name from URL for circuit breaker
    uri = URI.parse(client.token_url)
    service_name = "oauth2-#{uri.host}"
    
    # Use circuit breaker for token requests
    case ExternalCall.http_request(service_name, fn ->
      execute_token_request(client, params)
    end, %{failure_threshold: 3, timeout_ms: 30_000}) do
      {:ok, result} -> result
      {:error, :circuit_open} -> {:error, {:service_unavailable, "OAuth2 service circuit breaker is open"}}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_token_request(client, params) do
    uri = URI.parse(client.token_url)

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"accept", "application/json"}
    ]

    body = URI.encode_query(params)

    with {:ok, conn_pid} <- :gun.open(String.to_charlist(uri.host), uri.port, gun_opts(uri)),
         {:ok, protocol} when protocol in [:http, :http2] <- :gun.await_up(conn_pid, client.timeout),
         stream_ref <- :gun.post(conn_pid, String.to_charlist(uri.path), headers, body),
         {:ok, response} <- await_response(conn_pid, stream_ref, client.timeout) do
      :gun.close(conn_pid)
      parse_token_response(response)
    else
      {:error, reason} ->
        Logger.error("OAuth2 token request failed", reason: inspect(reason))
        {:error, {:network_error, reason}}
    end
  end

  defp make_validation_request(client, validate_url, access_token) do
    # Extract service name from URL for circuit breaker
    uri = URI.parse(validate_url)
    service_name = "oauth2-#{uri.host}"
    
    # Use circuit breaker for validation requests
    case ExternalCall.http_request(service_name, fn ->
      execute_validation_request(client, validate_url, access_token)
    end, %{failure_threshold: 3, timeout_ms: 30_000}) do
      {:ok, result} -> result
      {:error, :circuit_open} -> {:error, {:service_unavailable, "OAuth2 service circuit breaker is open"}}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_validation_request(client, validate_url, access_token) do
    uri = URI.parse(validate_url)

    headers = [
      {"authorization", "Bearer #{access_token}"},
      {"accept", "application/json"}
    ]

    with {:ok, conn_pid} <- :gun.open(String.to_charlist(uri.host), uri.port, gun_opts(uri)),
         {:ok, protocol} when protocol in [:http, :http2] <- :gun.await_up(conn_pid, client.timeout),
         stream_ref <- :gun.get(conn_pid, String.to_charlist(uri.path), headers),
         {:ok, response} <- await_response(conn_pid, stream_ref, client.timeout) do
      :gun.close(conn_pid)
      parse_validation_response(response)
    else
      {:error, reason} ->
        Logger.error("OAuth2 validation request failed", reason: inspect(reason))
        {:error, {:network_error, reason}}
    end
  end

  defp gun_opts(%URI{scheme: "https"}), do: %{transport: :tls}
  defp gun_opts(_), do: %{}

  defp await_response(conn_pid, stream_ref, timeout) do
    case :gun.await(conn_pid, stream_ref, timeout) do
      {:response, :fin, status, headers} ->
        {:ok, {status, headers, ""}}

      {:response, :nofin, status, headers} ->
        case :gun.await_body(conn_pid, stream_ref, timeout) do
          {:ok, body} -> {:ok, {status, headers, body}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_token_response({200, _headers, body}) do
    case JSON.decode(body) do
      {:ok, data} ->
        tokens = %{
          access_token: data["access_token"],
          refresh_token: data["refresh_token"],
          expires_in: data["expires_in"],
          scope: parse_scope(data["scope"]),
          token_type: data["token_type"] || "bearer"
        }

        {:ok, tokens}

      {:error, reason} ->
        {:error, {:json_decode_error, reason}}
    end
  end

  defp parse_token_response({status, _headers, body}) when status >= 400 do
    case JSON.decode(body) do
      {:ok, %{"error" => error}} ->
        {:error, String.to_atom(error)}

      {:ok, data} ->
        {:error, {:http_error, status, data}}

      {:error, _} ->
        {:error, {:http_error, status, body}}
    end
  end

  defp parse_validation_response({200, _headers, body}) do
    case JSON.decode(body) do
      {:ok, data} ->
        user_info = %{
          user_id: data["user_id"],
          client_id: data["client_id"],
          scopes: data["scopes"],
          expires_in: data["expires_in"]
        }

        {:ok, user_info}

      {:error, reason} ->
        {:error, {:json_decode_error, reason}}
    end
  end

  defp parse_validation_response({status, _headers, body}) when status >= 400 do
    case JSON.decode(body) do
      {:ok, %{"error" => error}} ->
        {:error, String.to_atom(error)}

      {:ok, data} ->
        {:error, {:http_error, status, data}}

      {:error, _} ->
        {:error, {:http_error, status, body}}
    end
  end

  defp parse_scope(scope) when is_binary(scope), do: String.split(scope, " ")
  defp parse_scope(scope) when is_list(scope), do: scope
  defp parse_scope(_), do: nil

  defp emit_telemetry(client, event_suffix, metadata \\ %{}) do
    event = client.telemetry_prefix ++ event_suffix
    :telemetry.execute(event, %{}, metadata)
  end
end
