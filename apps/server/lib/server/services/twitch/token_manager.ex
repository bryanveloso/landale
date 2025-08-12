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
  alias Server.OAuthService

  # 5 minutes before expiry
  @token_refresh_buffer 300_000
  # 15 minutes
  @validation_interval 900_000

  @doc """
  Schedules initial token validation after a delay.
  """
  def schedule_initial_validation do
    Process.send_after(self(), :validate_token, 100)
  end

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
          # Use get_valid_token which handles refresh automatically
          OAuthService.get_valid_token(:twitch)
        end)

      %{state | token_validation_task: task}
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
    # Use DataAccessGuard to validate and normalize token data
    case Server.DataAccessGuard.validate_with_mode(token_info, Server.Schemas.TokenSchema, :warn) do
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
            scopes: validated_token.scopes || MapSet.new(),
            client_id: validated_token.client_id
        }

      {:error, reason} ->
        Logger.error("Token validation schema error: #{inspect(reason)}")
        # Fall back to original behavior in case of schema error
        %{
          state
          | token_validation_task: nil,
            user_id: Map.get(token_info, "user_id"),
            scopes: normalize_scopes(Map.get(token_info, "scopes")),
            client_id: Map.get(token_info, "client_id")
        }
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
    # Use DataAccessGuard to validate refresh result
    case Server.DataAccessGuard.validate_with_mode(result, Server.Schemas.TokenSchema, :warn) do
      {:ok, validated} ->
        expires_in = validated.expires_in || 3600
        Logger.info("Token refreshed successfully, expires in #{expires_in} seconds")

      {:error, _} ->
        # Fall back to direct access
        expires_in = Map.get(result, "expires_in", 3600)
        Logger.info("Token refreshed successfully, expires in #{expires_in} seconds")
    end

    # Schedule next refresh
    expires_map = %{"expires_in" => Map.get(result, "expires_in", 3600)}
    schedule_token_refresh(state, expires_map)

    # Revalidate after refresh
    Process.send_after(self(), :validate_token, 1000)

    %{state | token_refresh_task: nil}
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

  defp normalize_scopes(list) when is_list(list), do: MapSet.new(list)
  defp normalize_scopes(_), do: MapSet.new()

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
