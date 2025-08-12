defmodule Server.Services.Twitch.TokenManager do
  @moduledoc """
  Manages OAuth token validation and refresh for Twitch EventSub service.

  Handles:
  - Token validation scheduling and execution
  - Token refresh with buffer time
  - Scope verification for required permissions
  - Async task management for token operations
  """

  require Logger
  alias Server.{CircuitBreakerServer, OAuthService}

  # 5 minutes before expiry
  @token_refresh_buffer 300_000
  # 15 minutes
  @validation_interval 900_000
  # 5 seconds for validation requests
  @validation_timeout 5_000

  @doc """
  Validates the current OAuth token asynchronously.
  Returns the updated state with a validation task.
  """
  def validate_token_async(state) do
    if state.token_validation_task do
      Logger.debug("Token validation already in progress")
      state
    else
      task =
        Task.async(fn ->
          # First get the token
          case OAuthService.get_valid_token(:twitch) do
            {:ok, %{access_token: access_token}} ->
              # Then validate it with Twitch to get user_id
              validate_with_twitch(access_token)

            error ->
              error
          end
        end)

      %{state | token_validation_task: task}
    end
  end

  defp validate_with_twitch(access_token) do
    Logger.debug("Starting Twitch token validation")

    # Use circuit breaker for resilience
    CircuitBreakerServer.call("twitch_validate", fn ->
      perform_validation_request(access_token)
    end)
  end

  defp perform_validation_request(access_token) do
    uri = URI.parse("https://id.twitch.tv/oauth2/validate")
    host = uri.host |> String.to_charlist()
    port = 443
    path = uri.path || "/"

    headers = [
      {"authorization", "OAuth #{access_token}"},
      {"accept", "application/json"}
    ]

    # Allow protocol negotiation instead of forcing HTTP/2
    opts = %{protocols: [:http2, :http], transport: :tls}

    with {:ok, conn_pid} <- :gun.open(host, port, opts),
         {:ok, _protocol} <- await_connection(conn_pid),
         stream_ref <- :gun.get(conn_pid, path, headers),
         {:ok, response} <- handle_validation_response(conn_pid, stream_ref) do
      Logger.debug("Token validation successful", user_id: response[:user_id])
      response
    else
      {:error, reason} = error ->
        Logger.debug("Token validation failed", reason: inspect(reason))
        error
    end
  end

  defp await_connection(conn_pid) do
    case :gun.await_up(conn_pid, @validation_timeout) do
      {:ok, _protocol} = result ->
        result

      {:error, reason} ->
        :gun.close(conn_pid)
        {:error, "Failed to establish connection: #{inspect(reason)}"}
    end
  end

  defp handle_validation_response(conn_pid, stream_ref) do
    case :gun.await(conn_pid, stream_ref, @validation_timeout) do
      {:response, :fin, status, _headers} ->
        :gun.close(conn_pid)
        {:error, "Empty response with status #{status}"}

      {:response, :nofin, status, _headers} ->
        handle_response_body(conn_pid, stream_ref, status)

      {:error, reason} ->
        :gun.close(conn_pid)
        {:error, "Failed to get response: #{inspect(reason)}"}
    end
  end

  defp handle_response_body(conn_pid, stream_ref, status) do
    case :gun.await_body(conn_pid, stream_ref, @validation_timeout) do
      {:ok, body} ->
        :gun.close(conn_pid)

        if status == 200 do
          parse_validation_response(body)
        else
          {:error, "Validation failed with status #{status}: #{body}"}
        end

      {:error, reason} ->
        :gun.close(conn_pid)
        {:error, "Failed to read response body: #{inspect(reason)}"}
    end
  end

  defp parse_validation_response(body) do
    case Jason.decode(body) do
      {:ok, data} ->
        {:ok,
         %{
           user_id: data["user_id"],
           login: data["login"],
           client_id: data["client_id"],
           scopes: data["scopes"] || [],
           expires_in: data["expires_in"]
         }}

      {:error, _} ->
        {:error, "Failed to parse validation response"}
    end
  end

  @doc """
  Refreshes the OAuth token asynchronously.
  Returns the updated state with a refresh task.
  """
  def refresh_token_async(state) do
    if state.token_refresh_task do
      Logger.debug("Token refresh already in progress")
      state
    else
      task =
        Task.async(fn ->
          OAuthService.refresh_token(:twitch)
        end)

      %{state | token_refresh_task: task}
    end
  end

  @doc """
  Handles successful token validation result.
  """
  def handle_validation_success(state, token_info) do
    # Direct pattern matching validation for Twitch validation response
    case validate_twitch_response(token_info) do
      {:ok, validated_token} ->
        log_validation_success(validated_token)

        # Check for required scopes
        _has_user_read_chat = check_chat_scope(validated_token)

        # Schedule next validation
        Process.send_after(self(), :validate_token, @validation_interval)

        # Schedule token refresh if needed
        state = schedule_token_refresh(state, validated_token)

        # Trigger WebSocket connection after successful token validation
        Process.send_after(self(), :connect, 100)

        %{
          state
          | token_validation_task: nil,
            user_id: validated_token.user_id,
            scopes: validated_token.scopes,
            client_id: validated_token.client_id
        }

      {:error, reason} ->
        Logger.error("Token validation failed: #{inspect(reason)}")
        handle_validation_failure(state, reason)
    end
  end

  @doc """
  Handles failed token validation.
  """
  def handle_validation_failure(state, reason) do
    Logger.error("Token validation failed: #{inspect(reason)}")

    # Schedule retry
    Process.send_after(self(), :validate_token, 30_000)

    %{state | token_validation_task: nil}
  end

  @doc """
  Handles successful token refresh result.
  """
  def handle_refresh_success(state, result) do
    # Direct pattern matching validation for refresh response
    case validate_refresh_response(result) do
      {:ok, validated} ->
        expires_in = validated.expires_in
        Logger.info("Token refreshed successfully, expires in #{expires_in} seconds")

        # Schedule next refresh
        state = schedule_token_refresh(state, validated)

        # Revalidate after refresh
        Process.send_after(self(), :validate_token, 1000)

        %{state | token_refresh_task: nil}

      {:error, reason} ->
        Logger.error("Token refresh validation failed: #{inspect(reason)}")
        handle_refresh_failure(state, reason)
    end
  end

  @doc """
  Handles failed token refresh.
  """
  def handle_refresh_failure(state, reason) do
    Logger.error("Token refresh failed: #{inspect(reason)}")

    # Schedule retry with backoff
    Process.send_after(self(), :refresh_token, 60_000)

    %{state | token_refresh_task: nil}
  end

  @doc """
  Schedules token refresh based on expiry time.
  """
  def schedule_token_refresh(state, token_data) do
    expires_in = Map.get(token_data, "expires_in") || Map.get(token_data, :expires_in)
    schedule_token_refresh_with_expiry(state, expires_in)
  end

  defp schedule_token_refresh_with_expiry(state, expires_in) when is_integer(expires_in) do
    # Cancel existing timer
    if state.token_refresh_timer do
      Process.cancel_timer(state.token_refresh_timer)
    end

    # Calculate when to refresh (with buffer)
    refresh_in = max(expires_in * 1000 - @token_refresh_buffer, 60_000)

    Logger.debug("Scheduling token refresh in #{refresh_in}ms (expires in #{expires_in}s)")

    timer_ref = Process.send_after(self(), :refresh_token, refresh_in)
    %{state | token_refresh_timer: timer_ref}
  end

  defp schedule_token_refresh_with_expiry(state, _), do: state

  @doc """
  Checks if token has expired based on validation time.
  """
  def token_expired?(token_data) do
    validated_at = Map.get(token_data, "validated_at") || Map.get(token_data, :validated_at)
    expires_in = Map.get(token_data, "expires_in") || Map.get(token_data, :expires_in)
    token_expired_with_values?(validated_at, expires_in)
  end

  defp token_expired_with_values?(validated_at, expires_in) when validated_at != nil and expires_in != nil do
    validated_time = DateTime.from_iso8601(validated_at)

    case validated_time do
      {:ok, dt, _} ->
        expiry_time = DateTime.add(dt, expires_in, :second)
        DateTime.compare(DateTime.utc_now(), expiry_time) == :gt

      _ ->
        true
    end
  end

  defp token_expired_with_values?(_, _), do: true

  @doc """
  Cleanup any running token tasks.
  """
  def cleanup_tasks(state) do
    shutdown_task(state.token_validation_task, "token_validation")
    shutdown_task(state.token_refresh_task, "token_refresh")

    # Cancel timers
    if state.token_refresh_timer do
      Process.cancel_timer(state.token_refresh_timer)
    end

    %{state | token_validation_task: nil, token_refresh_task: nil, token_refresh_timer: nil}
  end

  # Private functions

  # Validates Twitch token validation response structure.
  #
  # Expected fields from Twitch /oauth2/validate endpoint:
  # - user_id (required): String user ID
  # - client_id (required): String client ID
  # - scopes (required): List of scope strings
  # - login (optional): Username string
  # - expires_in (optional): Seconds until expiry
  defp validate_twitch_response(response) when is_map(response) do
    with {:ok, user_id} <- extract_required_field(response, :user_id, "string"),
         {:ok, client_id} <- extract_required_field(response, :client_id, "string"),
         {:ok, scopes} <- extract_required_field(response, :scopes, "list"),
         {:ok, normalized_scopes} <- normalize_scope_list(scopes) do
      validated = %{
        user_id: user_id,
        client_id: client_id,
        scopes: normalized_scopes,
        login: Map.get(response, :login),
        expires_in: Map.get(response, :expires_in)
      }

      {:ok, validated}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_twitch_response(response) do
    {:error, "Expected map, got #{inspect(response)}"}
  end

  # Validates OAuth token refresh response structure.
  #
  # Expected fields from OAuth refresh endpoint:
  # - access_token (required): New access token string
  # - expires_in (required): Seconds until expiry
  # - refresh_token (optional): New refresh token
  # - token_type (optional): Token type (usually "Bearer")
  defp validate_refresh_response(response) when is_map(response) do
    with {:ok, access_token} <- extract_required_field(response, :access_token, "string"),
         {:ok, expires_in} <- extract_required_field(response, :expires_in, "integer") do
      validated = %{
        access_token: access_token,
        expires_in: expires_in,
        refresh_token: Map.get(response, :refresh_token),
        token_type: Map.get(response, :token_type, "Bearer")
      }

      {:ok, validated}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_refresh_response(response) do
    {:error, "Expected map, got #{inspect(response)}"}
  end

  defp extract_required_field(map, field, expected_type) do
    case Map.get(map, field) do
      nil ->
        {:error, "Missing required field: #{field}"}

      value when expected_type == "string" and is_binary(value) ->
        {:ok, value}

      value when expected_type == "integer" and is_integer(value) ->
        {:ok, value}

      value when expected_type == "list" and is_list(value) ->
        {:ok, value}

      value ->
        {:error, "Field #{field} expected #{expected_type}, got #{inspect(value)}"}
    end
  end

  defp normalize_scope_list(scopes) when is_list(scopes) do
    if Enum.all?(scopes, &is_binary/1) do
      {:ok, MapSet.new(scopes)}
    else
      {:error, "Scopes list contains non-string values: #{inspect(scopes)}"}
    end
  end

  defp normalize_scope_list(scopes) do
    {:error, "Expected list of scopes, got #{inspect(scopes)}"}
  end

  defp check_chat_scope(%{scopes: %MapSet{} = scopes}) do
    MapSet.member?(scopes, "user:read:chat")
  end

  defp check_chat_scope(%{scopes: scopes}) when is_list(scopes) do
    "user:read:chat" in scopes
  end

  defp check_chat_scope(%{"scopes" => scopes}) when is_list(scopes) do
    "user:read:chat" in scopes
  end

  defp check_chat_scope(_), do: false

  defp log_validation_success(token_info) do
    user_id = Map.get(token_info, :user_id) || Map.get(token_info, "user_id")
    client_id = Map.get(token_info, :client_id) || Map.get(token_info, "client_id")
    expires_in = Map.get(token_info, :expires_in) || Map.get(token_info, "expires_in")

    Logger.info("Token validation successful: user_id=#{user_id}, client_id=#{client_id}, expires_in=#{expires_in}")
  end

  defp shutdown_task(nil, _name), do: :ok

  defp shutdown_task(task, name) do
    Logger.debug("Shutting down #{name} task")
    Task.shutdown(task, :brutal_kill)
  rescue
    e -> Logger.debug("Error shutting down #{name} task: #{inspect(e)}")
  end
end
