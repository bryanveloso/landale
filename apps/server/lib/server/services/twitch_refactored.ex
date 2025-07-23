defmodule Server.Services.TwitchRefactored do
  @behaviour Server.Services.TwitchBehaviour

  @moduledoc """
  Refactored Twitch EventSub service using modular architecture.

  This GenServer coordinates the refactored components:
  - `ConnectionManager` for WebSocket connection management
  - `SessionManager` for EventSub session state
  - `MessageRouter` for message routing
  - `OAuthTokenManager` for token management

  ## Architecture Benefits

  - **Separation of Concerns**: Each module has a single responsibility
  - **Better Testability**: Mock any component independently  
  - **CloudFront Support**: Built-in header management for CDN compatibility
  - **Graceful Reconnection**: Automatic retry with exponential backoff
  """

  use GenServer
  require Logger

  alias Server.Services.Twitch.{ConnectionManager, SessionManager, MessageRouter, EventHandler}
  alias Server.{Logging, OAuthTokenManager}

  defstruct [
    :connection_manager,
    :session_manager,
    :message_router,
    :token_manager,
    :token_validation_task,
    :token_refresh_task,
    :token_refresh_timer,
    :user_id,
    :scopes,
    state: %{
      connection: %{
        connected: false,
        connection_state: "disconnected",
        last_error: nil,
        last_connected: nil,
        session_id: nil
      },
      subscription_total_cost: 0,
      subscription_max_cost: 10,
      subscription_count: 0,
      subscription_max_count: 300
    }
  ]

  # Token refresh configuration
  # 5 minutes
  @token_refresh_buffer 300_000

  # Client API

  @doc """
  Starts the refactored Twitch EventSub service.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current internal state of the Twitch service with caching.
  """
  @spec get_state() :: map()
  def get_state do
    Server.Cache.get_or_compute(
      :twitch_service,
      :full_state,
      fn ->
        GenServer.call(__MODULE__, :get_state)
      end,
      ttl_seconds: 2
    )
  end

  @doc """
  Gets the current status of the Twitch service with caching.
  """
  @impl true
  @spec get_status() :: {:ok, map()} | {:error, term()}
  def get_status do
    Server.Cache.get_or_compute(
      :twitch_service,
      :connection_status,
      fn ->
        GenServer.call(__MODULE__, :get_status)
      end,
      ttl_seconds: 10
    )
  end

  @doc """
  Creates a new EventSub subscription.
  """
  @spec create_subscription(binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_subscription(event_type, condition, opts \\ []) do
    GenServer.call(__MODULE__, {:create_subscription, event_type, condition, opts})
  end

  @doc """
  Deletes an EventSub subscription.
  """
  @spec delete_subscription(binary()) :: :ok | {:error, term()}
  def delete_subscription(subscription_id) do
    GenServer.call(__MODULE__, {:delete_subscription, subscription_id})
  end

  @doc """
  Lists all active Twitch EventSub subscriptions.
  """
  @spec list_subscriptions() :: {:ok, list(map())} | {:error, binary()}
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    client_id = Keyword.get(opts, :client_id) || get_client_id()
    client_secret = Keyword.get(opts, :client_secret) || get_client_secret()

    if !client_id || !client_secret do
      Logger.error("Service configuration invalid",
        error: "missing required credentials",
        has_client_id: client_id != nil,
        has_client_secret: client_secret != nil
      )
    end

    # Initialize OAuth token manager
    {:ok, token_manager} =
      OAuthTokenManager.new(
        storage_key: :twitch_tokens,
        client_id: client_id,
        client_secret: client_secret,
        auth_url: "https://id.twitch.tv/oauth2/authorize",
        token_url: "https://id.twitch.tv/oauth2/token",
        validate_url: "https://id.twitch.tv/oauth2/validate",
        telemetry_prefix: [:server, :twitch, :oauth]
      )

    # Load existing tokens
    token_manager = OAuthTokenManager.load_tokens(token_manager)

    # Initialize SessionManager
    {:ok, session_manager} =
      SessionManager.start_link(
        owner: self(),
        token_manager: token_manager
      )

    # Initialize MessageRouter
    message_router =
      MessageRouter.new(
        session_manager: session_manager,
        event_handler: EventHandler
      )

    # Initialize ConnectionManager with CloudFront support
    headers = [
      {"user-agent", "Mozilla/5.0 (compatible; TwitchEventSub/1.0)"},
      {"origin", "https://eventsub.wss.twitch.tv"}
    ]

    {:ok, connection_manager} =
      ConnectionManager.start_link(
        url: "wss://eventsub.wss.twitch.tv/ws",
        owner: self(),
        headers: headers,
        telemetry_prefix: [:server, :twitch, :websocket]
      )

    state = %__MODULE__{
      connection_manager: connection_manager,
      session_manager: session_manager,
      message_router: message_router,
      token_manager: token_manager
    }

    # Set service context for logging
    Logging.set_service_context(:twitch, user_id: System.get_env("TWITCH_USER_ID"))
    correlation_id = Logging.set_correlation_id()

    Logger.info("Refactored Twitch service starting",
      client_id: client_id,
      correlation_id: correlation_id
    )

    # Start connection process if we have tokens
    case OAuthTokenManager.get_valid_token(token_manager) do
      {:ok, _token, updated_manager} ->
        Logger.info("Token validation started")
        state = %{state | token_manager: updated_manager}
        send(self(), :validate_token)
        {:ok, state}

      {:error, reason} ->
        Logger.info("Connection retry scheduled", error: reason)
        timer = Process.send_after(self(), :retry_connection, Server.NetworkConfig.reconnect_interval_ms())
        {:ok, %{state | token_refresh_timer: timer}}
    end
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    # Combine state from all components
    session_state = SessionManager.get_state(state.session_manager)
    connection_state = ConnectionManager.get_state(state.connection_manager)
    router_metrics = MessageRouter.get_metrics(state.message_router)

    combined_state = %{
      connection: %{
        connected: connection_state.connected,
        connection_state: connection_state.state,
        session_id: session_state.session_id,
        last_error: connection_state.last_error,
        last_connected: connection_state.connected_at
      },
      subscription_total_cost: state.state.subscription_total_cost,
      subscription_max_cost: state.state.subscription_max_cost,
      subscription_count: session_state.subscription_count,
      subscription_max_count: state.state.subscription_max_count,
      user_id: state.user_id,
      scopes: state.scopes,
      router_metrics: router_metrics
    }

    {:reply, combined_state, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    session_state = SessionManager.get_state(state.session_manager)
    connection_state = ConnectionManager.get_state(state.connection_manager)

    status = %{
      connected: connection_state.connected,
      connection_state: connection_state.state,
      session_id: session_state.session_id,
      subscription_count: session_state.subscription_count,
      subscription_cost: state.state.subscription_total_cost
    }

    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call({:create_subscription, event_type, condition, opts}, _from, state) do
    case SessionManager.create_subscription(
           state.session_manager,
           event_type,
           condition,
           opts
         ) do
      {:ok, subscription} ->
        # Update local tracking
        cost = subscription["cost"] || 1

        state = %{
          state
          | state: %{
              state.state
              | subscription_total_cost: state.state.subscription_total_cost + cost,
                subscription_count: state.state.subscription_count + 1
            }
        }

        # Track in monitor
        Server.SubscriptionMonitor.track_subscription(
          subscription["id"],
          event_type,
          %{
            service: :twitch,
            user_id: state.user_id,
            cost: cost,
            condition: condition
          }
        )

        # Invalidate caches
        invalidate_twitch_caches([:subscription_metrics, :full_state, :connection_status])

        {:reply, {:ok, subscription}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:delete_subscription, _subscription_id}, _from, state) do
    # TODO: Implement subscription deletion
    {:reply, {:error, "Not yet implemented"}, state}
  end

  @impl GenServer
  def handle_call(:list_subscriptions, _from, state) do
    # TODO: Implement subscription listing
    {:reply, {:ok, []}, state}
  end

  # Handle info callbacks

  @impl GenServer
  def handle_info(:validate_token, state) do
    # Start async token validation
    task =
      Task.async(fn ->
        OAuthTokenManager.validate_token(state.token_manager, state.user_id)
      end)

    {:noreply, %{state | token_validation_task: task}}
  end

  @impl GenServer
  def handle_info(:retry_connection, state) do
    case OAuthTokenManager.get_valid_token(state.token_manager) do
      {:ok, _token, updated_manager} ->
        state = %{state | token_manager: updated_manager}
        send(self(), :validate_token)
        {:noreply, state}

      {:error, reason} ->
        Logger.info("Connection retry rescheduled", error: reason)
        timer = Process.send_after(self(), :retry_connection, Server.NetworkConfig.reconnect_interval_ms())
        {:noreply, %{state | token_refresh_timer: timer}}
    end
  end

  @impl GenServer
  def handle_info(:connect, state) do
    Logger.info("Starting WebSocket connection")
    ConnectionManager.connect(state.connection_manager)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({ref, result}, %{token_validation_task: %Task{ref: ref}} = state) do
    # Token validation task completed
    case result do
      {:ok, token_info, updated_manager} ->
        Logger.info("Token validation succeeded",
          user_id: token_info[:user_id] || token_info["user_id"],
          client_id: token_info[:client_id] || token_info["client_id"]
        )

        # Store user ID and scopes
        user_id = token_info[:user_id] || token_info["user_id"]
        scopes = updated_manager.token_info.scopes || MapSet.new()

        # Update logging context
        Logging.set_service_context(:twitch, user_id: user_id)

        state = %{
          state
          | token_manager: updated_manager,
            user_id: user_id,
            scopes: scopes,
            token_validation_task: nil
        }

        # Update SessionManager with user_id and scopes
        SessionManager.set_user_id(state.session_manager, user_id)
        SessionManager.set_token_manager(state.session_manager, updated_manager)
        SessionManager.set_scopes(state.session_manager, scopes)

        # Start API client
        start_api_client(state.token_manager, state.user_id)

        # If session is already established, subscriptions will be created automatically
        # Otherwise, start WebSocket connection
        session_state = SessionManager.get_state(state.session_manager)

        unless session_state.has_session do
          send(self(), :connect)
        end

        {:noreply, state}

      {:error, reason} ->
        Logging.log_error("Token validation failed", reason)
        state = %{state | token_validation_task: nil}
        send(self(), :refresh_token)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:refresh_token, state) do
    # Schedule token refresh
    state = schedule_token_refresh(state)
    {:noreply, state}
  end

  # Handle ConnectionManager messages
  @impl GenServer
  def handle_info({:websocket_connection, :connected}, state) do
    Logger.info("WebSocket connected")

    state =
      update_connection_state(state, %{
        connected: true,
        connection_state: "connected",
        last_connected: DateTime.utc_now()
      })

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:websocket_connection, {:disconnected, reason}}, state) do
    Logger.warning("WebSocket disconnected", reason: inspect(reason))

    # Notify SessionManager
    SessionManager.handle_session_end(state.session_manager)

    state =
      update_connection_state(state, %{
        connected: false,
        connection_state: "disconnected",
        last_error: inspect(reason)
      })

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:websocket_connection, {:message, frame}}, state) do
    # Route message through MessageRouter
    case MessageRouter.route_frame(frame, state.message_router) do
      {:ok, updated_router} ->
        {:noreply, %{state | message_router: updated_router}}

      {:error, reason, updated_router} ->
        Logger.error("Message routing failed", error: inspect(reason))
        {:noreply, %{state | message_router: updated_router}}
    end
  end

  @impl GenServer
  def handle_info({:websocket_connection, {:error, error}}, state) do
    Logger.error("WebSocket error", error: inspect(error))

    state =
      update_connection_state(state, %{
        last_error: inspect(error)
      })

    {:noreply, state}
  end

  # Handle SessionManager messages
  @impl GenServer
  def handle_info({:twitch_session, {:session_established, session_id, _session_data}}, state) do
    Logger.info("Session established", session_id: session_id)

    state =
      update_connection_state(state, %{
        session_id: session_id
      })

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:twitch_session, :session_ended}, state) do
    Logger.info("Session ended")

    state =
      update_connection_state(state, %{
        session_id: nil
      })

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:twitch_session, {:session_reconnect_requested, reconnect_url}}, state) do
    Logger.info("Session reconnect requested", url: reconnect_url)

    # Update ConnectionManager URL and reconnect
    # Disconnect current connection and connect to new URL
    ConnectionManager.disconnect(state.connection_manager)
    # Brief pause to ensure clean disconnect
    Process.sleep(100)

    # Update ConnectionManager with new URL by recreating it
    {:ok, new_connection_manager} =
      ConnectionManager.start_link(
        url: reconnect_url,
        owner: self(),
        headers: [
          {"user-agent", "Mozilla/5.0 (compatible; TwitchEventSub/1.0)"},
          {"origin", "https://eventsub.wss.twitch.tv"}
        ],
        telemetry_prefix: [:server, :twitch, :websocket]
      )

    # Stop old connection manager
    GenServer.stop(state.connection_manager)

    # Connect with new manager
    ConnectionManager.connect(new_connection_manager)

    {:noreply, %{state | connection_manager: new_connection_manager}}

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:twitch_session, {:subscriptions_created, success, failed}}, state) do
    Logger.info("Default subscriptions created", success: success, failed: failed)

    # Update metrics
    state = %{state | state: %{state.state | subscription_count: state.state.subscription_count + success}}

    # Invalidate caches
    invalidate_twitch_caches([:subscription_metrics, :full_state])

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:twitch_session, {:subscription_creation_failed, reason}}, state) do
    Logger.error("Subscription creation failed", reason: reason)
    {:noreply, state}
  end

  # Handle task DOWN messages
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{token_validation_task: %Task{ref: ref}} = state) do
    Logging.log_error("Token validation task crashed", inspect(reason))
    timer = Process.send_after(self(), :validate_token, Server.NetworkConfig.reconnect_interval_ms())
    {:noreply, %{state | token_validation_task: nil, token_refresh_timer: timer}}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{token_refresh_task: %Task{ref: ref}} = state) do
    Logging.log_error("Token refresh task crashed", inspect(reason))
    timer = Process.send_after(self(), :refresh_token, Server.NetworkConfig.reconnect_interval_ms())
    {:noreply, %{state | token_refresh_task: nil, token_refresh_timer: timer}}
  end

  # Ignore task success messages for tasks we're not tracking
  @impl GenServer
  def handle_info({_ref, _result}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("Twitch service terminating", reason: inspect(reason))

    # Clean shutdown of components
    if state.connection_manager do
      ConnectionManager.disconnect(state.connection_manager)
    end

    :ok
  end

  # Private functions

  defp get_client_id do
    System.get_env("TWITCH_CLIENT_ID")
  end

  defp get_client_secret do
    System.get_env("TWITCH_CLIENT_SECRET")
  end

  defp start_api_client(token_manager, user_id) do
    case Server.Services.Twitch.ApiClient.start_link(
           token_manager: token_manager,
           user_id: user_id
         ) do
      {:ok, _pid} ->
        Logger.info("Twitch API client started", user_id: user_id)

      {:error, {:already_started, _pid}} ->
        Logger.debug("Twitch API client already running", user_id: user_id)

      {:error, reason} ->
        Logger.error("Failed to start Twitch API client",
          user_id: user_id,
          error: inspect(reason)
        )
    end
  end

  defp schedule_token_refresh(state) do
    # Cancel existing timer
    if state.token_refresh_timer do
      Process.cancel_timer(state.token_refresh_timer)
    end

    # Schedule refresh
    timer = Process.send_after(self(), :refresh_token, @token_refresh_buffer)
    %{state | token_refresh_timer: timer}
  end

  defp update_connection_state(state, updates) do
    new_connection_state = Map.merge(state.state.connection, updates)
    put_in(state.state.connection, new_connection_state)
  end

  defp invalidate_twitch_caches(cache_keys) do
    Enum.each(cache_keys, fn key ->
      Server.Cache.invalidate(:twitch_service, key)
    end)
  end
end
