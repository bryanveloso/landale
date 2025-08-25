defmodule Server.Services.Twitch do
  @moduledoc """
  Main Twitch EventSub service coordinating WebSocket connection and subscription management.

  This is a refactored, streamlined version that delegates to specialized modules:
  - `TokenManager` for OAuth token management
  - `HealthChecker` for health status reporting
  - `SubscriptionCoordinator` for subscription lifecycle
  - `Server.Events` for event processing
  - `WebSocketClient` for connection handling
  """

  use Server.Service,
    service_name: "twitch",
    behaviour: Server.Services.TwitchBehaviour

  use Server.Service.StatusReporter

  require Logger

  alias Server.Services.Twitch.{
    HealthChecker,
    SubscriptionCoordinator,
    TokenManager
  }

  alias Server.WebSocketClient

  @eventsub_websocket_url "wss://eventsub.wss.twitch.tv/ws"

  defstruct [
    :session_id,
    :reconnect_timer,
    :token_refresh_timer,
    :token_validation_task,
    :token_refresh_task,
    :ws_client,
    :user_id,
    :scopes,
    :retry_subscription_timer,
    :client_id,
    :keepalive_timer,
    :keepalive_timeout,
    :last_keepalive,
    subscriptions: %{},
    cloudfront_retry_count: 0,
    default_subscriptions_created: false,
    # Connection state
    connected: false,
    connection_state: "disconnected",
    last_error: nil,
    last_connected: nil,
    # Subscription metrics
    subscription_total_cost: 0,
    subscription_max_cost: 10,
    subscription_count: 0,
    subscription_max_count: 300
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @impl Server.Services.TwitchBehaviour
  def get_state do
    Server.Cache.get_or_compute(
      :twitch_service,
      :full_state,
      fn -> GenServer.call(__MODULE__, :get_state) end,
      ttl_seconds: 2
    )
  end

  @impl true
  def get_status do
    Server.Cache.get_or_compute(
      :twitch_service,
      :connection_status,
      fn -> GenServer.call(__MODULE__, :get_service_status) end,
      ttl_seconds: 10
    )
  end

  @impl Server.Services.TwitchBehaviour
  def get_connection_state do
    Server.Cache.get_or_compute(
      :twitch_service,
      :connection_state,
      fn ->
        state = GenServer.call(__MODULE__, :get_internal_state)

        %{
          connected: state.connected,
          connection_state: state.connection_state,
          session_id: state.session_id,
          last_connected: state.last_connected,
          websocket_url: @eventsub_websocket_url
        }
      end,
      ttl_seconds: 5
    )
  end

  @impl Server.Services.TwitchBehaviour
  def get_subscription_metrics do
    Server.Cache.get_or_compute(
      :twitch_service,
      :subscription_metrics,
      fn ->
        case GenServer.call(__MODULE__, :get_internal_state) do
          %{} = state ->
            %{
              subscription_count: state.subscription_count,
              subscription_total_cost: state.subscription_total_cost,
              subscription_max_count: state.subscription_max_count,
              subscription_max_cost: state.subscription_max_cost
            }

          _ ->
            %{
              subscription_count: 0,
              subscription_total_cost: 0,
              subscription_max_count: 300,
              subscription_max_cost: 10
            }
        end
      end,
      ttl_seconds: 10
    )
  end

  @impl Server.Services.TwitchBehaviour
  def create_subscription(event_type, condition, opts \\ []) do
    GenServer.call(__MODULE__, {:create_subscription, event_type, condition, opts})
  end

  @impl Server.Services.TwitchBehaviour
  def delete_subscription(subscription_id) do
    GenServer.call(__MODULE__, {:delete_subscription, subscription_id})
  end

  @impl Server.Services.TwitchBehaviour
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end

  @impl Server.Services.TwitchBehaviour
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  @impl Server.Services.TwitchBehaviour
  def get_info do
    %{
      module: __MODULE__,
      name: "twitch",
      service: "twitch",
      description: "Twitch EventSub WebSocket service"
    }
  end

  # ============================================================================
  # Server.Service Callbacks
  # ============================================================================

  @impl Server.Service
  def do_init(opts) do
    Logger.info("Initializing Twitch EventSub service")

    state = %__MODULE__{
      subscription_max_cost: opts[:max_cost] || 10,
      subscription_max_count: opts[:max_subscriptions] || 300
    }

    # Schedule initial token validation
    # Send the message to this GenServer process
    Process.send_after(self(), :validate_token, 100)

    {:ok, state}
  end

  @impl Server.Service
  def do_terminate(reason, state) do
    Logger.info("Terminating Twitch service: #{inspect(reason)}")

    # Cleanup all resources
    SubscriptionCoordinator.cleanup_subscriptions(state.subscriptions, state)
    cleanup_websocket(state.ws_client)
    TokenManager.cleanup_tasks(state)
    cleanup_timers(state)

    :ok
  end

  # ============================================================================
  # StatusReporter Implementation
  # ============================================================================

  def service_healthy?(state), do: HealthChecker.service_healthy?(state)
  def connected?(state), do: HealthChecker.connected?(state)
  def connection_uptime(state), do: HealthChecker.connection_uptime(state)
  def do_build_status(state), do: HealthChecker.build_status(state)

  # ============================================================================
  # GenServer Callbacks - Calls
  # ============================================================================

  def handle_call(:get_state, _from, state) do
    {:reply, build_public_state(state), state}
  end

  def handle_call(:get_service_status, _from, state) do
    {:reply, {:ok, do_build_status(state)}, state}
  end

  def handle_call(:get_internal_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_health, _from, state) do
    {:reply, HealthChecker.get_health(state), state}
  end

  def handle_call({:create_subscription, event_type, condition, opts}, _from, state) do
    case SubscriptionCoordinator.create_subscription(event_type, condition, opts, state) do
      {:ok, subscription, new_state} ->
        {:reply, {:ok, subscription}, new_state}

      {:error, reason, unchanged_state} ->
        {:reply, {:error, reason}, unchanged_state}
    end
  end

  def handle_call({:delete_subscription, subscription_id}, _from, state) do
    case SubscriptionCoordinator.delete_subscription(subscription_id, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason, unchanged_state} ->
        {:reply, {:error, reason}, unchanged_state}
    end
  end

  def handle_call(:list_subscriptions, _from, state) do
    subscriptions = SubscriptionCoordinator.list_subscriptions(state)
    {:reply, {:ok, subscriptions}, state}
  end

  # ============================================================================
  # GenServer Callbacks - Info Messages
  # ============================================================================

  # Token Management
  def handle_info(:validate_token, state) do
    {:noreply, TokenManager.validate_token_async(state)}
  end

  def handle_info(:refresh_token, state) do
    {:noreply, TokenManager.refresh_token_async(state)}
  end

  def handle_info({ref, token_info}, %{token_validation_task: %Task{ref: ref}} = state) when is_map(token_info) do
    new_state = TokenManager.handle_validation_success(state, token_info)

    # Trigger subscription creation if connected
    if new_state.session_id do
      Process.send_after(self(), {:create_subscriptions_with_validated_token, new_state.session_id}, 100)
    end

    {:noreply, new_state}
  end

  def handle_info({ref, {:error, reason}}, %{token_validation_task: %Task{ref: ref}} = state) do
    {:noreply, TokenManager.handle_validation_failure(state, reason)}
  end

  def handle_info({ref, {:ok, result}}, %{token_refresh_task: %Task{ref: ref}} = state) do
    {:noreply, TokenManager.handle_refresh_success(state, result)}
  end

  def handle_info({ref, {:error, reason}}, %{token_refresh_task: %Task{ref: ref}} = state) do
    {:noreply, TokenManager.handle_refresh_failure(state, reason)}
  end

  # Task DOWN messages for cleanup
  def handle_info({:DOWN, ref, :process, _pid, :normal}, %{token_validation_task: %Task{ref: ref}} = state) do
    {:noreply, %{state | token_validation_task: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, %{token_refresh_task: %Task{ref: ref}} = state) do
    {:noreply, %{state | token_refresh_task: nil}}
  end

  # WebSocket Events
  def handle_info({:websocket_connected, client}, state) do
    Logger.info("Twitch EventSub service connected", service: :twitch)

    new_state = %{
      state
      | ws_client: client,
        connected: true,
        connection_state: "connected",
        last_connected: DateTime.utc_now(),
        last_error: nil
    }

    broadcast_status_change(new_state)
    {:noreply, new_state}
  end

  def handle_info({:websocket_disconnected, _client, reason}, state) do
    Logger.warning("WebSocket disconnected: #{inspect(reason)}")

    new_state = %{
      state
      | connected: false,
        connection_state: "disconnected",
        session_id: nil,
        last_error: inspect(reason),
        default_subscriptions_created: false
    }

    # Schedule reconnection
    if state.reconnect_timer, do: Process.cancel_timer(state.reconnect_timer)
    timer_ref = Process.send_after(self(), :connect, 5000)

    broadcast_status_change(new_state)
    {:noreply, %{new_state | reconnect_timer: timer_ref}}
  end

  def handle_info({:websocket_message, _client, message}, state) do
    Logger.info("Received WebSocket message from Twitch EventSub",
      message_size: byte_size(message),
      message_preview: String.slice(message, 0, 200)
    )

    {:noreply, handle_eventsub_message(state, message)}
  end

  # Connection Management
  def handle_info(:connect, state) do
    Logger.info("Attempting to connect to Twitch EventSub WebSocket")

    # Create a new WebSocket client instance
    client = WebSocketClient.new(@eventsub_websocket_url, self())

    case WebSocketClient.connect(client) do
      {:ok, connected_client} ->
        Logger.debug("WebSocket connection initiated")
        {:noreply, %{state | ws_client: connected_client, reconnect_timer: nil}}

      {:error, _client, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        timer_ref = Process.send_after(self(), :connect, 10_000)
        {:noreply, %{state | reconnect_timer: timer_ref}}
    end
  end

  def handle_info({:reconnect_to_url, reconnect_url}, state) do
    Logger.info("Reconnecting to new Twitch EventSub URL", url: reconnect_url)

    # Cleanup existing connection if any
    cleanup_websocket(state.ws_client)

    # Create a new WebSocket client with the provided reconnect URL
    client = WebSocketClient.new(reconnect_url, self())

    case WebSocketClient.connect(client) do
      {:ok, connected_client} ->
        Logger.info("Successfully reconnected to Twitch EventSub", url: reconnect_url)

        new_state = %{
          state
          | ws_client: connected_client,
            reconnect_timer: nil,
            connection_state: "reconnecting",
            last_error: nil
        }

        broadcast_status_change(new_state)
        {:noreply, new_state}

      {:error, _client, reason} ->
        Logger.error("Failed to reconnect to new URL: #{inspect(reason)}", url: reconnect_url)

        # Fall back to normal reconnection logic
        timer_ref = Process.send_after(self(), :connect, 5_000)

        new_state = %{
          state
          | ws_client: nil,
            reconnect_timer: timer_ref,
            connection_state: "reconnect_failed",
            last_error: "Reconnection failed: #{inspect(reason)}"
        }

        broadcast_status_change(new_state)
        {:noreply, new_state}
    end
  end

  # Subscription Creation
  def handle_info({:create_subscriptions_with_validated_token, session_id}, state) do
    {new_state, success_count, failed_count} = SubscriptionCoordinator.create_default_subscriptions(state, session_id)

    Logger.info("Default subscriptions processed",
      success: success_count,
      failed: failed_count,
      session_id: session_id
    )

    {:noreply, new_state}
  end

  def handle_info({:retry_default_subscriptions, session_id}, state) do
    {new_state, success_count, failed_count} = SubscriptionCoordinator.create_default_subscriptions(state, session_id)

    Logger.info("Default subscriptions retried",
      success: success_count,
      failed: failed_count,
      session_id: session_id
    )

    {:noreply, new_state}
  end

  # Gun WebSocket Upgrade
  def handle_info({:gun_upgrade, conn_pid, stream_ref, ["websocket"], _headers}, state) do
    if state.ws_client && state.ws_client.conn_pid == conn_pid do
      Logger.debug("Processing WebSocket upgrade", conn_pid: inspect(conn_pid), stream_ref: inspect(stream_ref))
      updated_client = WebSocketClient.handle_upgrade(state.ws_client, stream_ref)
      {:noreply, %{state | ws_client: updated_client}}
    else
      Logger.warning("Received upgrade for unknown connection",
        conn_pid: inspect(conn_pid),
        expected: inspect(state.ws_client && state.ws_client.conn_pid)
      )

      {:noreply, state}
    end
  end

  # Gun WebSocket Messages
  def handle_info({:gun_ws, conn_pid, stream_ref, frame}, state) do
    if state.ws_client && state.ws_client.conn_pid == conn_pid && state.ws_client.stream_ref == stream_ref do
      updated_client = WebSocketClient.handle_message(state.ws_client, stream_ref, frame)
      {:noreply, %{state | ws_client: updated_client}}
    else
      {:noreply, state}
    end
  end

  # Guard against redundant keepalive timeout processing
  def handle_info(:keepalive_timeout, %{connection_state: "keepalive_timeout"} = state) do
    Logger.debug("Ignoring redundant keepalive_timeout message",
      session_id: state.session_id
    )

    {:noreply, state}
  end

  # Keepalive timeout - force reconnection to prevent phantom connections
  def handle_info(:keepalive_timeout, state) do
    Logger.warning("Keepalive timeout exceeded, forcing reconnection to prevent phantom connection",
      session_id: state.session_id,
      connected: state.connected,
      last_keepalive: state.last_keepalive
    )

    # Cancel existing keepalive timer
    if state.keepalive_timer do
      Process.cancel_timer(state.keepalive_timer)
    end

    # Force disconnect and reconnect to establish fresh connection
    cleanup_websocket(state.ws_client)

    new_state = %{
      state
      | ws_client: nil,
        connected: false,
        connection_state: "keepalive_timeout",
        session_id: nil,
        keepalive_timer: nil,
        last_keepalive: nil,
        default_subscriptions_created: false,
        last_error: "Keepalive timeout - forced reconnection"
    }

    # Schedule immediate reconnection
    timer_ref = Process.send_after(self(), :connect, 1000)

    broadcast_status_change(new_state)
    {:noreply, %{new_state | reconnect_timer: timer_ref}}
  end

  # Catch-all
  def handle_info(message, state) do
    Logger.debug("Unhandled message in Twitch service: #{inspect(message)}")
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp handle_eventsub_message(state, message_json) do
    Logger.debug("Processing EventSub message",
      message_length: byte_size(message_json)
    )

    with {:ok, message} <- Jason.decode(message_json),
         metadata <- message["metadata"],
         message_type <- metadata["message_type"] do
      Logger.info("EventSub message decoded",
        message_type: message_type,
        metadata: inspect(metadata)
      )

      case message_type do
        "session_welcome" ->
          handle_session_welcome(state, message)

        "session_keepalive" ->
          handle_session_keepalive(state)

        "notification" ->
          Logger.info("Processing EventSub notification",
            event_type: get_in(message, ["payload", "subscription", "type"]),
            event_id: get_in(message, ["payload", "event", "id"])
          )

          handle_notification(state, message)

        "session_reconnect" ->
          handle_session_reconnect(state, message)

        "revocation" ->
          handle_revocation(state, message)

        _ ->
          Logger.warning("Unknown message type: #{message_type}")
          state
      end
    else
      {:error, reason} ->
        Logger.error("Failed to decode EventSub message: #{inspect(reason)}")
        state
    end
  end

  defp handle_session_welcome(state, message) do
    payload = message["payload"]
    session = payload["session"]
    session_id = session["id"]

    Logger.info("Session welcome received", session_id: session_id)

    # Create subscriptions after token validation
    if state.user_id do
      Process.send_after(self(), {:create_subscriptions_with_validated_token, session_id}, 100)
    end

    # Set up keepalive monitoring
    keepalive_timeout = session["keepalive_timeout_seconds"] || 10
    timer_ref = schedule_keepalive_timeout(keepalive_timeout * 2)

    new_state = %{
      state
      | session_id: session_id,
        connection_state: "ready",
        keepalive_timer: timer_ref,
        keepalive_timeout: keepalive_timeout
    }

    broadcast_status_change(new_state)
    new_state
  end

  defp handle_session_keepalive(state) do
    # Reset keepalive timer
    if state.keepalive_timer do
      Process.cancel_timer(state.keepalive_timer)
    end

    # Use the stored keepalive_timeout with 2x multiplier (same as session_welcome)
    keepalive_timeout = state.keepalive_timeout || 10
    timer_ref = schedule_keepalive_timeout(keepalive_timeout * 2)
    %{state | last_keepalive: DateTime.utc_now(), keepalive_timer: timer_ref}
  end

  defp handle_notification(state, message) do
    payload = message["payload"]
    subscription = payload["subscription"]
    event = payload["event"]

    Logger.info("Handling EventSub notification",
      event_type: subscription["type"],
      subscription_id: subscription["id"],
      event_id: event["id"] || event["message_id"],
      payload_keys: Map.keys(payload),
      subscription_keys: Map.keys(subscription),
      event_keys: Map.keys(event)
    )

    # Process the event through the complete pipeline (normalize, store, publish)
    case Server.Events.process_event(subscription["type"], event) do
      :ok ->
        Logger.info("EventSub notification processed successfully",
          event_type: subscription["type"],
          event_id: event["id"] || event["message_id"]
        )

      {:error, reason} ->
        Logger.error("EventSub notification processing failed",
          event_type: subscription["type"],
          event_id: event["id"] || event["message_id"],
          reason: inspect(reason)
        )
    end

    state
  end

  defp handle_session_reconnect(state, message) do
    session = message["payload"]["session"]
    reconnect_url = session["reconnect_url"]

    Logger.warning("Session reconnect requested", url: reconnect_url)

    # Connect to new URL
    Process.send_after(self(), {:reconnect_to_url, reconnect_url}, 100)

    state
  end

  defp handle_revocation(state, message) do
    subscription = message["payload"]["subscription"]
    Logger.warning("Subscription revoked", type: subscription["type"], id: subscription["id"])

    # Remove from state
    sub_id = subscription["id"]

    if Map.has_key?(state.subscriptions, sub_id) do
      cost = subscription["cost"] || 1
      new_subscriptions = Map.delete(state.subscriptions, sub_id)

      %{
        state
        | subscriptions: new_subscriptions,
          subscription_count: map_size(new_subscriptions),
          subscription_total_cost: max(0, state.subscription_total_cost - cost)
      }
    else
      state
    end
  end

  defp build_public_state(state) do
    %{
      connected: state.connected,
      session_id: state.session_id,
      user_id: state.user_id,
      subscription_count: state.subscription_count,
      subscription_total_cost: state.subscription_total_cost,
      subscription_max_count: state.subscription_max_count,
      subscription_max_cost: state.subscription_max_cost,
      connection_state: state.connection_state,
      last_error: state.last_error,
      last_connected: state.last_connected
    }
  end

  defp broadcast_status_change(state) do
    # Route through unified system ONLY
    status_data = do_build_status(state)

    case Server.Events.process_event("twitch.service_status", status_data) do
      :ok -> Logger.debug("Twitch service status routed through unified system")
      {:error, reason} -> Logger.warning("Unified routing failed", reason: reason)
    end
  end

  defp schedule_keepalive_timeout(seconds) do
    Process.send_after(self(), :keepalive_timeout, seconds * 1000)
  end

  defp cleanup_websocket(nil), do: :ok

  defp cleanup_websocket(_ws_client) do
    # WebSocketClient uses Gun internally which will clean up on process termination
    # No explicit disconnect needed
    :ok
  end

  defp cleanup_timers(state) do
    [:reconnect_timer, :keepalive_timer, :retry_subscription_timer]
    |> Enum.each(fn timer_key ->
      if timer_ref = Map.get(state, timer_key) do
        Process.cancel_timer(timer_ref)
      end
    end)
  end
end
