defmodule Server.Services.Twitch.HealthChecker do
  @moduledoc """
  Health check functionality for Twitch EventSub service.

  Provides detailed health status including:
  - WebSocket connection health
  - OAuth token validity
  - Subscription status and metrics
  - Overall service health determination
  """

  require Logger
  alias Server.Services.Twitch.TokenManager

  @doc """
  Gets comprehensive health status of the Twitch service.
  """
  def get_health(state) do
    ws_status = check_websocket_connection(state)
    oauth_status = check_oauth_status(state)
    subscription_status = check_subscription_status(state)

    overall_health = determine_overall_health(ws_status, oauth_status, subscription_status)

    %{
      status: overall_health,
      websocket: ws_status,
      oauth: oauth_status,
      subscriptions: subscription_status,
      details: build_health_details(state)
    }
  end

  @doc """
  Determines if the service is healthy enough to operate.
  """
  def service_healthy?(state) do
    state.connected && state.session_id != nil
  end

  @doc """
  Checks if the service is connected to Twitch EventSub.
  """
  def connected?(state) do
    state.connected
  end

  @doc """
  Calculates connection uptime in seconds.
  """
  def connection_uptime(state) do
    if state.connected && state.last_connected do
      DateTime.diff(DateTime.utc_now(), state.last_connected)
    else
      0
    end
  end

  @doc """
  Builds standardized status report for the service.
  """
  def build_status(state) do
    %{
      service: "twitch",
      status: determine_service_status(state),
      connected: state.connected,
      websocket_connected: state.connected,
      connection_state: state.connection_state,
      session_id: state.session_id,
      uptime: connection_uptime(state),
      subscription_count: state.subscription_count,
      metadata: %{
        session_id: state.session_id,
        connection_state: state.connection_state,
        subscription_count: state.subscription_count,
        subscription_cost: state.subscription_total_cost
      }
    }
  end

  @doc """
  Determines standardized service status.
  """
  def determine_service_status(state) do
    cond do
      state.connected && state.session_id != nil ->
        "healthy"

      state.connected ->
        "degraded"

      true ->
        "unhealthy"
    end
  end

  # Private functions

  defp check_websocket_connection(state) do
    if state.connected && state.session_id do
      "healthy"
    else
      "unhealthy"
    end
  end

  defp check_oauth_status(_state) do
    # Check if we have valid OAuth token
    case Server.OAuthService.get_token_info("twitch") do
      {:ok, token_info} when is_map(token_info) ->
        if TokenManager.token_expired?(token_info) do
          "expired"
        else
          "valid"
        end

      _ ->
        "missing"
    end
  end

  defp check_subscription_status(state) do
    if state.subscription_count > 0 do
      "active"
    else
      "none"
    end
  end

  defp build_health_details(state) do
    %{
      session_id: state.session_id,
      connected_at: state.last_connected,
      subscription_count: state.subscription_count,
      subscription_cost: state.subscription_total_cost,
      last_error: state.last_error
    }
  end

  defp determine_overall_health(ws_status, oauth_status, subscription_status) do
    cond do
      ws_status == "healthy" && oauth_status == "valid" && subscription_status == "active" ->
        "healthy"

      ws_status == "healthy" && oauth_status == "valid" ->
        "degraded"

      true ->
        "unhealthy"
    end
  end
end
