defmodule Server.Services.Twitch.MessageRouter do
  @moduledoc """
  Routes Twitch EventSub messages to appropriate handlers.

  This module extracts message routing logic from the main Twitch service,
  providing a clean separation between transport, routing, and business logic.

  ## Message Flow

  1. ConnectionManager receives WebSocket frame
  2. ConnectionManager forwards to owner (Twitch service)
  3. Twitch service delegates to MessageRouter
  4. MessageRouter determines message type and routes accordingly
  5. Appropriate handler processes the message

  ## Supported Message Types

  - `session_welcome` - Routed to SessionManager
  - `session_keepalive` - Handled internally (no-op)
  - `session_reconnect` - Routed to SessionManager
  - `notification` - Routed to EventHandler
  - `revocation` - Logged and forwarded
  """

  require Logger

  alias Server.Services.Twitch.{EventHandler, Protocol, SessionManager}

  @type router_state :: %{
          session_manager: pid() | nil,
          event_handler: module() | nil,
          metrics: map()
        }

  @doc """
  Creates a new router state.

  ## Options
  - `:session_manager` - SessionManager pid
  - `:event_handler` - EventHandler module (defaults to EventHandler)
  """
  def new(opts \\ []) do
    %{
      session_manager: Keyword.get(opts, :session_manager),
      event_handler: Keyword.get(opts, :event_handler, EventHandler),
      metrics: %{
        messages_routed: 0,
        messages_by_type: %{},
        errors: 0
      }
    }
  end

  @doc """
  Routes a WebSocket frame to the appropriate handler.

  Returns updated router state with metrics.
  """
  @spec route_frame(binary(), router_state()) :: {:ok, router_state()} | {:error, term(), router_state()}
  def route_frame(frame, router_state) when is_binary(frame) do
    case Protocol.decode_message(frame) do
      {:ok, message} ->
        route_message(message, router_state)

      {:error, reason} ->
        Logger.error("Failed to decode Twitch message",
          error: inspect(reason),
          frame_preview: String.slice(frame, 0..100)
        )

        updated_state = update_metrics(router_state, :decode_error)
        {:error, {:decode_error, reason}, updated_state}
    end
  end

  @doc """
  Routes a decoded message to the appropriate handler.
  """
  @spec route_message(map(), router_state()) :: {:ok, router_state()}
  def route_message(message, router_state) do
    message_type = Protocol.get_message_type(message)

    Logger.debug("Routing Twitch message",
      message_type: message_type,
      message_id: get_in(message, ["metadata", "message_id"])
    )

    result =
      case message_type do
        "session_welcome" ->
          handle_session_welcome(message, router_state)

        "session_keepalive" ->
          handle_session_keepalive(message, router_state)

        "session_reconnect" ->
          handle_session_reconnect(message, router_state)

        "notification" ->
          handle_notification(message, router_state)

        "revocation" ->
          handle_revocation(message, router_state)

        other ->
          handle_unknown(other, message, router_state)
      end

    updated_state = update_metrics(router_state, message_type)

    case result do
      :ok -> {:ok, updated_state}
      {:error, reason} -> {:error, reason, updated_state}
    end
  end

  # Message handlers

  defp handle_session_welcome(_message, %{session_manager: nil}) do
    Logger.error("Cannot handle session_welcome - no SessionManager configured")
    {:error, :no_session_manager}
  end

  defp handle_session_welcome(message, %{session_manager: session_manager}) do
    session = message["payload"]["session"]
    session_id = Protocol.get_session_id(message)

    Logger.info("Routing session_welcome to SessionManager",
      session_id: session_id,
      status: session["status"]
    )

    SessionManager.handle_session_welcome(session_manager, session_id, session)
    :ok
  end

  defp handle_session_keepalive(_message, _router_state) do
    # Keepalive messages require no action beyond connection-level handling
    Logger.debug("Session keepalive received")
    :ok
  end

  defp handle_session_reconnect(_message, %{session_manager: nil}) do
    Logger.error("Cannot handle session_reconnect - no SessionManager configured")
    {:error, :no_session_manager}
  end

  defp handle_session_reconnect(message, %{session_manager: session_manager}) do
    reconnect_url = get_in(message, ["payload", "session", "reconnect_url"])

    Logger.info("Routing session_reconnect to SessionManager",
      reconnect_url: reconnect_url
    )

    SessionManager.handle_session_reconnect(session_manager, reconnect_url)
    :ok
  end

  defp handle_notification(message, %{event_handler: event_handler}) do
    event_type = get_in(message, ["metadata", "subscription_type"])
    event_data = message["payload"]["event"]

    Logger.debug("Routing notification to EventHandler",
      event_type: event_type,
      event_id: event_data["id"] || get_in(message, ["metadata", "message_id"])
    )

    # Process event through EventHandler
    case event_handler.process_event(event_type, event_data) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("EventHandler failed to process event",
          event_type: event_type,
          error: inspect(reason)
        )

        {:error, {:event_processing_failed, reason}}
    end
  end

  defp handle_revocation(message, router_state) do
    subscription = message["payload"]["subscription"]

    Logger.warning("Subscription revoked",
      subscription_type: subscription["type"],
      subscription_id: subscription["id"],
      status: subscription["status"],
      condition: subscription["condition"]
    )

    # Notify SessionManager to remove subscription from tracking
    if router_state.session_manager do
      SessionManager.handle_subscription_revoked(
        router_state.session_manager,
        subscription["id"],
        subscription
      )
    end

    :ok
  end

  defp handle_unknown(message_type, message, _router_state) do
    Logger.warning("Unknown Twitch message type",
      message_type: message_type,
      message_id: get_in(message, ["metadata", "message_id"]),
      subscription_type: get_in(message, ["metadata", "subscription_type"])
    )

    :ok
  end

  # Metrics tracking

  defp update_metrics(router_state, message_type) when is_binary(message_type) do
    metrics = router_state.metrics

    updated_metrics = %{
      metrics
      | messages_routed: metrics.messages_routed + 1,
        messages_by_type:
          Map.update(
            metrics.messages_by_type,
            message_type,
            1,
            &(&1 + 1)
          )
    }

    %{router_state | metrics: updated_metrics}
  end

  defp update_metrics(router_state, :decode_error) do
    metrics = router_state.metrics
    updated_metrics = %{metrics | errors: metrics.errors + 1}
    %{router_state | metrics: updated_metrics}
  end

  @doc """
  Gets current routing metrics.
  """
  def get_metrics(router_state) do
    router_state.metrics
  end

  @doc """
  Resets routing metrics.
  """
  def reset_metrics(router_state) do
    %{
      router_state
      | metrics: %{
          messages_routed: 0,
          messages_by_type: %{},
          errors: 0
        }
    }
  end
end
