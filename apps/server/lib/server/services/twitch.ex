defmodule Server.Services.Twitch do
  @moduledoc """
  Main Twitch EventSub service coordinating WebSocket connection and subscription management.

  This GenServer focuses on connection lifecycle and delegates to specialized modules:
  - `Server.Services.Twitch.EventSubManager` for subscription management
  - `Server.Services.Twitch.EventHandler` for event processing
  - `Server.OAuthService` for centralized token management
  - `Server.WebSocketClient` for WebSocket connection handling
  """

  use Server.Service,
    service_name: "twitch",
    behaviour: Server.Services.TwitchBehaviour

  use Server.Service.StatusReporter

  require Logger

  alias Server.Services.Twitch.{EventHandler, EventSubManager}
  alias Server.{Logging, WebSocketClient}

  # Twitch EventSub constants
  @eventsub_websocket_url "wss://eventsub.wss.twitch.tv/ws"
  # Network configuration is now handled by Server.NetworkConfig
  @token_refresh_buffer 300_000

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
    subscriptions: %{},
    cloudfront_retry_count: 0,
    default_subscriptions_created: false,
    # Connection fields (was state.connection)
    connected: false,
    connection_state: "disconnected",
    last_error: nil,
    last_connected: nil,
    # Subscription fields (was state.subscription_*)
    subscription_total_cost: 0,
    subscription_max_cost: 10,
    subscription_count: 0,
    subscription_max_count: 300
  ]

  # Client API

  @doc """
  Gets the current internal state of the Twitch service with caching.

  Uses ETS cache to reduce GenServer load. Cache TTL is 2 seconds for detailed state.

  ## Returns
  - Map containing connection, subscriptions, and EventSub state
  """
  @spec get_state() :: map()
  @impl Server.Services.TwitchBehaviour
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

  Uses caching (10 seconds TTL) for connection status since this is called frequently
  by dashboard and health checks but changes infrequently.

  ## Returns
  - `{:ok, status}` where status contains connection and subscription information
  - `{:error, reason}` if service is unavailable
  """
  @spec get_status() :: {:ok, map()} | {:error, binary()}
  @impl true
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
  Gets Twitch connection state with aggressive caching.

  ## Returns
  - Map with connection details
  """
  @spec get_connection_state() :: map()
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
      ttl_seconds: 10
    )
  end

  @doc """
  Gets subscription metrics with caching.

  ## Returns
  - Map with subscription counts and costs
  """
  @spec get_subscription_metrics() :: map()
  @impl Server.Services.TwitchBehaviour
  def get_subscription_metrics do
    Server.Cache.get_or_compute(
      :twitch_service,
      :subscription_metrics,
      fn ->
        state = GenServer.call(__MODULE__, :get_internal_state)

        %{
          subscription_count: state.subscription_count,
          subscription_total_cost: state.subscription_total_cost,
          subscription_max_count: state.subscription_max_count,
          subscription_max_cost: state.subscription_max_cost
        }
      end,
      ttl_seconds: 30
    )
  end

  @doc """
  Creates a new Twitch EventSub subscription.

  ## Parameters
  - `event_type` - The EventSub event type (e.g. "channel.update")
  - `condition` - Map of conditions for the subscription
  - `opts` - Additional options (optional)

  ## Returns
  - `{:ok, subscription}` on success
  - `{:error, reason}` if creation fails or limits exceeded
  """
  @spec create_subscription(binary(), map(), keyword()) :: {:ok, map()} | {:error, binary()}
  @impl Server.Services.TwitchBehaviour
  def create_subscription(event_type, condition, opts \\ []) do
    GenServer.call(__MODULE__, {:create_subscription, event_type, condition, opts})
  end

  @doc """
  Deletes an existing Twitch EventSub subscription.

  ## Parameters
  - `subscription_id` - The ID of the subscription to delete

  ## Returns
  - `:ok` on success
  - `{:error, reason}` if deletion fails
  """
  @spec delete_subscription(binary()) :: :ok | {:error, binary()}
  @impl Server.Services.TwitchBehaviour
  def delete_subscription(subscription_id) do
    GenServer.call(__MODULE__, {:delete_subscription, subscription_id})
  end

  @doc """
  Lists all active Twitch EventSub subscriptions.

  ## Returns
  - `{:ok, subscriptions}` where subscriptions is a list of subscription maps
  - `{:error, reason}` if service is unavailable
  """
  @spec list_subscriptions() :: {:ok, list(map())} | {:error, binary()}
  @impl Server.Services.TwitchBehaviour
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end

  # ServiceBehaviour implementation

  @impl true
  def get_health do
    state = get_state()

    ws_connection_status = check_websocket_connection(state)
    oauth_status = check_oauth_status(state)
    subscription_status = check_subscription_status(state)
    details = build_health_details(state)
    health_status = determine_overall_health(ws_connection_status, oauth_status, subscription_status)

    {:ok,
     %{
       status: health_status,
       checks: %{
         websocket_connection: ws_connection_status,
         oauth_token: oauth_status,
         eventsub_subscriptions: subscription_status
       },
       details: details
     }}
  end

  defp check_websocket_connection(state) do
    case state.connected do
      true -> :pass
      false -> :fail
      nil -> :unknown
    end
  end

  defp check_oauth_status(_state) do
    # Check OAuth status via centralized service
    case Server.OAuthService.get_token_info(:twitch) do
      {:ok, token_info} ->
        if token_expired?(token_info) do
          :warn
        else
          :pass
        end

      {:error, :no_tokens} ->
        :fail

      {:error, _} ->
        :fail
    end
  end

  defp token_expired?(token_info) do
    case token_info.expires_at do
      nil ->
        false

      expires_at ->
        DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  defp check_subscription_status(state) do
    case state.subscriptions do
      subs when is_map(subs) and map_size(subs) > 0 -> :pass
      subs when is_map(subs) -> :warn
      _ -> :fail
    end
  end

  defp build_health_details(state) do
    %{
      connection_state: state.connection_state,
      session_id: state.session_id,
      subscription_count: map_size(state.subscriptions || %{}),
      subscription_cost: state.subscription_total_cost || 0,
      user_id: state.user_id,
      default_subscriptions_created: state.default_subscriptions_created || false
    }
  end

  defp determine_overall_health(ws_status, oauth_status, subscription_status) do
    cond do
      ws_status == :fail or oauth_status == :fail -> :unhealthy
      subscription_status == :fail -> :degraded
      ws_status == :unknown or oauth_status == :warn -> :degraded
      true -> :healthy
    end
  end

  @impl true
  def get_info do
    %{
      name: "twitch",
      version: "2.0.0",
      capabilities: [:eventsub, :oauth, :webhooks, :cloudfront_compatible],
      description: "Twitch EventSub WebSocket integration for real-time stream events"
    }
  end

  # Server.Service callbacks
  @impl Server.Service
  def do_init(opts) do
    client_id = Keyword.get(opts, :client_id) || get_client_id()
    client_secret = Keyword.get(opts, :client_secret) || get_client_secret()

    # Ensure we have required credentials
    if !client_id || !client_secret do
      Logger.error("Service configuration invalid",
        error: "missing required credentials",
        has_client_id: client_id != nil,
        has_client_secret: client_secret != nil
      )
    end

    # Register with centralized OAuth service
    oauth_config = %{
      client_id: client_id,
      client_secret: client_secret,
      auth_url: "https://id.twitch.tv/oauth2/authorize",
      token_url: "https://id.twitch.tv/oauth2/token",
      validate_url: "https://id.twitch.tv/oauth2/validate"
    }

    case Server.OAuthService.register_service(:twitch, oauth_config) do
      :ok ->
        Logger.info("Registered with OAuth service")

      {:error, reason} ->
        Logger.error("Failed to register with OAuth service", error: reason)
    end

    # Initialize WebSocket client
    ws_client =
      WebSocketClient.new(
        @eventsub_websocket_url,
        self(),
        telemetry_prefix: [:server, :twitch, :websocket]
      )

    state = %__MODULE__{
      ws_client: ws_client,
      subscriptions: %{},
      token_validation_task: nil,
      token_refresh_task: nil
    }

    # Set service context for all log messages from this process
    Logging.set_service_context(:twitch, user_id: System.get_env("TWITCH_USER_ID"))
    correlation_id = Logging.set_correlation_id()

    Logger.info("Service starting", client_id: client_id, correlation_id: correlation_id)

    # Start connection process if we have tokens
    case Server.OAuthService.get_valid_token(:twitch) do
      {:ok, token} ->
        Logger.info("Token validation started")
        # Update state with token info
        state = %{
          state
          | user_id: Map.get(token, :user_id, state.user_id),
            scopes: Map.get(token, :scopes, state.scopes)
        }

        send(self(), :validate_token)
        {:ok, state}

      {:error, reason} ->
        Logger.info("Connection retry scheduled", error: reason)
        timer = Process.send_after(self(), :retry_connection, Server.NetworkConfig.reconnect_interval_ms())
        {:ok, %{state | reconnect_timer: timer}}
    end
  end

  @impl Server.Service
  def do_terminate(reason, state) do
    Logger.info("Service terminating", reason: reason)

    cleanup_subscriptions(state.subscriptions)
    cleanup_websocket(state.ws_client)
    cleanup_tasks(state)
    cleanup_timers(state)

    :ok
  end

  # StatusReporter implementation

  def service_healthy?(state) do
    state.connected && state.session_id != nil
  end

  def connected?(state) do
    state.connected
  end

  def connection_uptime(state) do
    case state.last_connected do
      nil -> 0
      last_connected -> DateTime.diff(DateTime.utc_now(), last_connected)
    end
  end

  @impl Server.Service.StatusReporter
  def do_build_status(state) do
    %{
      websocket_connected: state.connected,
      connection_state: state.connection_state,
      session_id: state.session_id,
      subscription_count: map_size(state.subscriptions),
      subscription_cost: state.subscription_total_cost,
      user_id: state.user_id,
      scopes_count: if(state.scopes, do: MapSet.size(state.scopes), else: 0)
    }
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    # Return the full state structure (no longer nested)
    {:reply, state, state}
  end

  @impl GenServer
  def handle_call(:get_service_status, _from, state) do
    status = %{
      connected: state.connected,
      connection_state: state.connection_state,
      session_id: state.session_id,
      subscription_count: map_size(state.subscriptions),
      subscription_cost: state.subscription_total_cost
    }

    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call(:get_token_info, _from, state) do
    token_info =
      case Server.OAuthService.get_token_info(:twitch) do
        {:ok, token} ->
          %{
            valid: true,
            expires_at: token.expires_at,
            scopes: token.scopes,
            last_validated: token.last_validated || "unknown"
          }

        {:error, _} ->
          %{valid: false}
      end

    {:reply, {:ok, token_info}, state}
  end

  @impl GenServer
  def handle_call(:get_internal_state, _from, state) do
    # Return the entire state structure for internal inspection
    {:reply, state, state}
  end

  @impl GenServer
  def handle_call({:create_subscription, event_type, condition, opts}, _from, state) do
    cond do
      not (state.connected && state.session_id) ->
        {:reply, {:error, "WebSocket not connected"}, state}

      state.subscription_count >= state.subscription_max_count ->
        {:reply, {:error, "Subscription count limit exceeded (#{state.subscription_max_count})"}, state}

      true ->
        handle_subscription_creation(event_type, condition, opts, state)
    end
  end

  @impl GenServer
  def handle_call({:delete_subscription, subscription_id}, _from, state) do
    # Create manager state for EventSubManager (using centralized OAuth)
    manager_state = %{
      service_name: :twitch,
      session_id: state.session_id,
      user_id: state.user_id,
      scopes: state.scopes
    }

    case EventSubManager.delete_subscription(manager_state, subscription_id) do
      :ok ->
        # Remove from local state and update counters
        deleted_subscription = Map.get(state.subscriptions, subscription_id)
        cost = if deleted_subscription, do: deleted_subscription["cost"] || 1, else: 0

        # Untrack subscription from monitor
        Server.SubscriptionMonitor.untrack_subscription(subscription_id)

        new_subscriptions = Map.delete(state.subscriptions, subscription_id)

        new_state = %{
          state
          | subscriptions: new_subscriptions,
            subscription_total_cost: max(0, state.subscription_total_cost - cost),
            subscription_count: max(0, state.subscription_count - 1)
        }

        # Invalidate subscription-related caches
        invalidate_twitch_caches([:subscription_metrics, :full_state, :connection_status])

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_subscriptions, _from, state) do
    subscriptions = Map.values(state.subscriptions)
    {:reply, {:ok, subscriptions}, state}
  end

  defp handle_subscription_creation(event_type, condition, opts, state) do
    # Check for duplicate subscription
    existing_key = EventSubManager.generate_subscription_key(event_type, condition)

    existing_subscription =
      Enum.find(state.subscriptions, fn {_id, sub} ->
        EventSubManager.generate_subscription_key(sub["type"], sub["condition"]) == existing_key
      end)

    case existing_subscription do
      {id, subscription} ->
        Logger.warning("Subscription creation skipped",
          error: "duplicate detected",
          event_type: event_type,
          existing_id: id,
          condition: condition
        )

        {:reply, {:ok, subscription}, state}

      nil ->
        create_new_subscription(event_type, condition, opts, state)
    end
  end

  defp create_new_subscription(event_type, condition, opts, state) do
    # Create subscription using EventSubManager
    manager_state = %{
      session_id: state.session_id,
      oauth2_client: state.token_manager.oauth2_client,
      scopes: state.scopes,
      user_id: state.user_id
    }

    case EventSubManager.create_subscription(manager_state, event_type, condition, opts) do
      {:ok, subscription} ->
        add_subscription_to_state(subscription, event_type, condition, state)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp add_subscription_to_state(subscription, event_type, condition, state) do
    # Store the subscription and update counters
    new_subscriptions = Map.put(state.subscriptions, subscription["id"], subscription)
    cost = subscription["cost"] || 1

    # Track subscription in monitor
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

    new_state = %{
      state
      | subscriptions: new_subscriptions,
        subscription_total_cost: state.subscription_total_cost + cost,
        subscription_count: state.subscription_count + 1
    }

    # Invalidate subscription-related caches
    invalidate_twitch_caches([:subscription_metrics, :full_state, :connection_status])

    {:reply, {:ok, subscription}, new_state}
  end

  @impl GenServer
  def handle_info(:retry_connection, state) do
    case Server.OAuthService.get_valid_token(:twitch) do
      {:ok, token} ->
        # Update state with token info if available
        state = %{
          state
          | user_id: Map.get(token, :user_id, state.user_id),
            scopes: Map.get(token, :scopes, state.scopes)
        }

        send(self(), :validate_token)
        {:noreply, state}

      {:error, reason} ->
        Logger.info("Connection retry rescheduled", error: reason)
        timer = Process.send_after(self(), :retry_connection, Server.NetworkConfig.reconnect_interval_ms())
        {:noreply, %{state | reconnect_timer: timer}}
    end
  end

  @impl GenServer
  def handle_info(:connect, state) do
    Logger.info("WebSocket connection started")

    # Add CloudFront-compatible headers to fix 400 errors
    websocket_key = :base64.encode(:crypto.strong_rand_bytes(16))

    headers = [
      {"user-agent", "Mozilla/5.0 (compatible; TwitchEventSub/1.0)"},
      {"origin", "https://eventsub.wss.twitch.tv"},
      {"sec-websocket-key", websocket_key},
      {"sec-websocket-version", "13"}
    ]

    case WebSocketClient.connect(state.ws_client, headers: headers) do
      {:ok, updated_client} ->
        state = %{state | ws_client: updated_client}

        state =
          update_connection_state(state, %{
            connection_state: "connecting"
          })

        {:noreply, state}

      {:error, updated_client, reason} ->
        Logger.error("WebSocket connection failed", error: reason)
        state = %{state | ws_client: updated_client}

        state =
          update_connection_state(state, %{
            connected: false,
            connection_state: "error",
            last_error: inspect(reason)
          })

        # Schedule reconnect
        timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval_ms())
        state = %{state | reconnect_timer: timer}
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:validate_token, state) do
    Logger.info("Token validation started", service: :twitch)

    # Cancel any existing validation task first
    state =
      if state.token_validation_task do
        case Task.shutdown(state.token_validation_task, 5_000) do
          :ok ->
            state

          nil ->
            Logger.warning("Token validation task timeout during shutdown")
            state
        end
      else
        state
      end

    # Start async token validation with supervisor
    task =
      Task.Supervisor.async_nolink(Server.TaskSupervisor, fn ->
        Server.OAuthService.validate_token(:twitch)
      end)

    {:noreply, %{state | token_validation_task: task}}
  end

  @impl GenServer
  def handle_info(:refresh_token, state) do
    # Cancel any existing refresh task gracefully
    state =
      if state.token_refresh_task do
        case Task.shutdown(state.token_refresh_task, 5_000) do
          :ok ->
            state

          nil ->
            Logger.warning("Token refresh task timeout during shutdown")
            state
        end
      else
        state
      end

    # Start async token refresh with supervisor
    task =
      Task.Supervisor.async_nolink(Server.TaskSupervisor, fn ->
        Server.OAuthService.refresh_token(:twitch)
      end)

    {:noreply, %{state | token_refresh_task: task}}
  end

  # Async task result handlers
  @impl GenServer
  def handle_info({ref, result}, %{token_validation_task: %Task{ref: ref}} = state) do
    # Token validation task completed
    case result do
      {:ok, token_info} ->
        scopes_list = token_info[:scopes] || token_info["scopes"] || []
        has_user_read_chat = "user:read:chat" in scopes_list

        Logger.info("Token validation completed",
          user_id: token_info[:user_id] || token_info["user_id"],
          client_id: token_info[:client_id] || token_info["client_id"],
          scopes: length(scopes_list),
          has_chat_scope: has_user_read_chat
        )

        # Log missing chat scope as error since it's critical for the data loss issue
        unless has_user_read_chat do
          Logger.error("Missing required chat scope",
            user_id: token_info[:user_id] || token_info["user_id"],
            missing_scope: "user:read:chat",
            available_scopes: scopes_list
          )
        end

        # Store user ID and scopes in state
        user_id = token_info[:user_id] || token_info["user_id"]
        # Convert scopes to MapSet if they're a list
        scopes =
          case token_info[:scopes] || token_info["scopes"] do
            list when is_list(list) -> MapSet.new(list)
            set -> set || MapSet.new()
          end

        # Update logging context immediately with user_id
        Logging.set_service_context(:twitch, user_id: user_id)

        state = %{
          state
          | user_id: user_id,
            scopes: scopes,
            token_validation_task: nil
        }

        Logger.info("State updated with user_id after token validation",
          user_id: state.user_id,
          has_session: state.session_id != nil
        )

        # API client start removed - OAuth service handles token management

        # If we already have a session established but deferred subscriptions, trigger them now
        if state.session_id do
          Logger.info("Token validation completed with active session",
            user_id: state.user_id,
            session_id: state.session_id
          )

          # Trigger immediately - no delay for critical timing
          send(self(), {:create_subscriptions_with_validated_token, state.session_id})
        else
          # Token validation completed, now start WebSocket connection
          Logger.info("Token validation completed, starting WebSocket connection",
            user_id: state.user_id
          )

          send(self(), :connect)
        end

        {:noreply, state}

      {:error, reason} ->
        Logging.log_error("Token validation failed", reason)

        # Try to refresh the token first
        state = %{state | token_validation_task: nil}
        send(self(), :refresh_token)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({ref, result}, %{token_refresh_task: %Task{ref: ref}} = state) do
    # Token refresh task completed
    case result do
      {:ok, token_info} ->
        Logger.info("Token refresh completed")
        # Update state with new token info if available
        state = %{
          state
          | user_id: Map.get(token_info, :user_id, state.user_id),
            scopes: Map.get(token_info, :scopes, state.scopes),
            token_refresh_task: nil
        }

        state = schedule_token_refresh(state)
        # Validate new token after successful refresh
        send(self(), :validate_token)
        {:noreply, state}

      {:error, reason} ->
        Logging.log_error("Token refresh failed", reason)
        # Try again in a shorter interval
        timer = Process.send_after(self(), :refresh_token, Server.NetworkConfig.reconnect_interval_ms())
        state = %{state | token_refresh_timer: timer, token_refresh_task: nil}
        {:noreply, state}
    end
  end

  # Handle task DOWN messages (task crashed)
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{token_validation_task: %Task{ref: ref}} = state) do
    Logging.log_error("Token validation task crashed", inspect(reason))
    # Retry validation after a delay
    timer = Process.send_after(self(), :validate_token, Server.NetworkConfig.reconnect_interval_ms())
    {:noreply, %{state | token_validation_task: nil, reconnect_timer: timer}}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{token_refresh_task: %Task{ref: ref}} = state) do
    Logging.log_error("Token refresh task crashed", inspect(reason))
    # Retry refresh after a delay
    timer = Process.send_after(self(), :refresh_token, Server.NetworkConfig.reconnect_interval_ms())
    {:noreply, %{state | token_refresh_task: nil, token_refresh_timer: timer}}
  end

  # WebSocketClient event handlers
  @impl GenServer
  def handle_info({:websocket_connected, client}, state) do
    Logger.info("WebSocket connection established")

    state = %{state | ws_client: client, cloudfront_retry_count: 0}

    state =
      update_connection_state(state, %{
        connected: true,
        connection_state: "connected",
        last_connected: DateTime.utc_now()
      })

    # Publish connection event
    Phoenix.PubSub.broadcast(Server.PubSub, "dashboard", {:twitch_connected, %{}})

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:websocket_disconnected, client, reason}, state) do
    Logger.warning("WebSocket connection lost", error: reason)

    state = %{state | ws_client: client}

    state =
      update_connection_state(state, %{
        connected: false,
        connection_state: "disconnected",
        last_error: inspect(reason)
      })

    # Clean up subscriptions from monitor before clearing local state
    Enum.each(state.subscriptions, fn {subscription_id, _subscription} ->
      Server.SubscriptionMonitor.untrack_subscription(subscription_id)
    end)

    # Clear session and subscriptions on disconnect
    state = %{state | session_id: nil, subscriptions: %{}}

    # Publish disconnection event
    Phoenix.PubSub.broadcast(Server.PubSub, "dashboard", {:twitch_disconnected, %{reason: reason}})

    # Schedule reconnect
    timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval_ms())
    state = %{state | reconnect_timer: timer}

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:websocket_message, client, message}, state) do
    state = %{state | ws_client: client}
    state = handle_eventsub_message(state, message)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:websocket_reconnect, client}, state) do
    Logger.info("WebSocket reconnection started")
    state = %{state | ws_client: client}
    send(self(), :connect)
    {:noreply, state}
  end

  def handle_info({:reconnect_to_url, url}, state) do
    Logger.info("EventSub reconnection requested", url: url)

    # Create new WebSocket client with the new URL
    new_client = WebSocketClient.new(url, self())

    # Add CloudFront-compatible headers for reconnection
    websocket_key = :base64.encode(:crypto.strong_rand_bytes(16))

    headers = [
      {"user-agent", "Mozilla/5.0 (compatible; TwitchEventSub/1.0)"},
      {"origin", "https://eventsub.wss.twitch.tv"},
      {"sec-websocket-key", websocket_key},
      {"sec-websocket-version", "13"}
    ]

    # Initiate connection
    WebSocketClient.connect(new_client, headers: headers)

    state = %{state | ws_client: new_client, session_id: nil}
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:gun_response, conn_pid, stream_ref, is_fin, status, headers}, state) do
    case status do
      400 ->
        # CloudFront 400 error - check retry count to prevent infinite loops
        retry_count = state.cloudfront_retry_count

        if retry_count < 2 do
          Logger.error("CloudFront rejected WebSocket upgrade request",
            status: status,
            error: "CloudFront 400 error, attempting retry #{retry_count + 1}/2",
            headers: inspect(headers, limit: 200)
          )

          # Schedule retry with enhanced headers
          Process.send_after(self(), {:retry_with_enhanced_headers, retry_count + 1}, 1000)
          {:noreply, state}
        else
          Logger.error("CloudFront continues rejecting after retries",
            status: status,
            error: "Max retries reached, falling back to normal reconnect",
            retry_count: retry_count
          )

          # Fall back to normal reconnect cycle
          timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval_ms())
          new_state = %{state | reconnect_timer: timer, cloudfront_retry_count: 0}
          {:noreply, new_state}
        end

      403 ->
        Logger.error("WebSocket upgrade forbidden",
          status: status,
          error: "CloudFront/Twitch rejected connection - check authentication",
          headers: inspect(headers, limit: 200)
        )

        # For 403, retry after token refresh
        send(self(), :refresh_token)
        {:noreply, state}

      401 ->
        Logger.error("WebSocket upgrade unauthorized",
          status: status,
          error: "Invalid or expired token",
          headers: inspect(headers, limit: 200)
        )

        # For 401, refresh token immediately
        send(self(), :refresh_token)
        {:noreply, state}

      _ ->
        Logger.error("WebSocket HTTP error response",
          status: status,
          is_fin: is_fin,
          headers: inspect(headers, limit: 200),
          conn_pid: inspect(conn_pid),
          stream_ref: inspect(stream_ref),
          error: "Expected WebSocket upgrade but got HTTP response"
        )

        # For other errors, retry with backoff
        timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval_ms())
        new_state = %{state | reconnect_timer: timer}
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_info({:gun_data, conn_pid, stream_ref, is_fin, data}, state) do
    # Extract CloudFront error details for debugging
    cloudfront_error =
      if String.contains?(data, "CloudFront") do
        # Try to extract specific error from CloudFront response
        cond do
          String.contains?(data, "Bad request") -> "CloudFront Bad Request - invalid request format"
          String.contains?(data, "403 ERROR") -> "CloudFront 403 - request forbidden"
          String.contains?(data, "404 ERROR") -> "CloudFront 404 - endpoint not found"
          String.contains?(data, "502 ERROR") -> "CloudFront 502 - bad gateway from origin"
          true -> "CloudFront generic error"
        end
      else
        "Non-CloudFront HTTP error"
      end

    Logger.error("WebSocket HTTP error data",
      data_preview: String.slice(data, 0, 400),
      cloudfront_error: cloudfront_error,
      is_fin: is_fin,
      conn_pid: inspect(conn_pid),
      stream_ref: inspect(stream_ref),
      error: "Received HTTP error page instead of WebSocket data"
    )

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:gun_error, conn_pid, stream_ref, reason}, state) do
    Logger.error("WebSocket stream error",
      error: inspect(reason),
      conn_pid: inspect(conn_pid),
      stream_ref: inspect(stream_ref)
    )

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:retry_with_enhanced_headers, retry_count}, state) do
    Logger.info("Retrying WebSocket connection with enhanced headers", retry_count: retry_count)

    # Close existing connection first
    _closed_client = WebSocketClient.close(state.ws_client)

    # Create new client for retry
    new_client = WebSocketClient.new(@eventsub_websocket_url, self(), telemetry_prefix: [:server, :twitch, :websocket])

    # Try different header combinations based on retry count
    websocket_key = :base64.encode(:crypto.strong_rand_bytes(16))

    headers =
      case retry_count do
        1 ->
          # First retry: curl user agent with complete WebSocket headers
          [
            {"user-agent", "curl/7.68.0"},
            {"origin", "https://eventsub.wss.twitch.tv"},
            {"sec-websocket-key", websocket_key},
            {"sec-websocket-version", "13"},
            {"connection", "upgrade"},
            {"upgrade", "websocket"}
          ]

        2 ->
          # Second retry: different browser user agent with complete headers
          [
            {"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"},
            {"origin", "https://eventsub.wss.twitch.tv"},
            {"sec-websocket-key", websocket_key},
            {"sec-websocket-version", "13"},
            {"connection", "upgrade"},
            {"upgrade", "websocket"},
            {"cache-control", "no-cache"},
            {"pragma", "no-cache"}
          ]
      end

    case WebSocketClient.connect(new_client, headers: headers) do
      {:ok, updated_client} ->
        state = %{state | ws_client: updated_client, cloudfront_retry_count: retry_count}

        state =
          update_connection_state(state, %{
            connection_state: "connecting"
          })

        {:noreply, state}

      {:error, updated_client, reason} ->
        Logger.error("WebSocket connection failed with enhanced headers",
          error: reason,
          retry_count: retry_count
        )

        state = %{state | ws_client: updated_client, cloudfront_retry_count: retry_count}

        state =
          update_connection_state(state, %{
            connected: false,
            connection_state: "error",
            last_error: inspect(reason)
          })

        # Schedule normal reconnect after enhanced retry fails
        timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval_ms())
        state = %{state | reconnect_timer: timer, cloudfront_retry_count: 0}
        {:noreply, state}
    end
  end

  # Gun WebSocket upgrade success
  @impl GenServer
  def handle_info({:gun_upgrade, _conn_pid, stream_ref, protocols, headers}, state) do
    Logger.debug("WebSocket upgrade successful",
      protocols: protocols,
      headers: inspect(headers, limit: 300)
    )

    # Handle the upgrade with WebSocketClient
    updated_client = WebSocketClient.handle_upgrade(state.ws_client, stream_ref)
    {:noreply, %{state | ws_client: updated_client}}
  end

  # Gun WebSocket messages
  @impl GenServer
  def handle_info({:gun_ws, _conn_pid, stream_ref, frame}, state) do
    # Handle the message with WebSocketClient
    updated_client = WebSocketClient.handle_message(state.ws_client, stream_ref, frame)
    {:noreply, %{state | ws_client: updated_client}}
  end

  # Create subscriptions immediately after token validation completes
  @impl GenServer
  def handle_info({:create_subscriptions_with_validated_token, session_id}, state) do
    Logger.info("Creating subscriptions with validated token",
      user_id: state.user_id,
      session_id: session_id,
      has_scopes: state.scopes != nil
    )

    if state.user_id && state.session_id == session_id do
      manager_state = %{
        session_id: session_id,
        token_manager: state.token_manager,
        oauth2_client: state.token_manager.oauth2_client,
        scopes: state.scopes,
        user_id: state.user_id
      }

      if state.default_subscriptions_created do
        Logger.debug("Skipping subscription creation - already created")
        {:noreply, state}
      else
        {success_count, failed_count} = EventSubManager.create_default_subscriptions(manager_state)

        Logger.info("Default subscriptions created after token validation",
          success: success_count,
          failed: failed_count
        )

        # Only mark as created if we had some success
        state =
          if success_count > 0 do
            # Clear retry timer since we succeeded
            if state.retry_subscription_timer do
              Process.cancel_timer(state.retry_subscription_timer)
            end

            %{state | default_subscriptions_created: true, retry_subscription_timer: nil}
          else
            state
          end

        {:noreply, state}
      end
    else
      Logger.warning("Subscription creation skipped",
        reason: "invalid state",
        has_user_id: state.user_id != nil,
        session_matches: state.session_id == session_id
      )

      {:noreply, state}
    end
  end

  # Retry default subscriptions when user_id becomes available
  @impl GenServer
  def handle_info({:retry_default_subscriptions, session_id}, state) do
    Logger.info("Retry default subscriptions check",
      has_user_id: state.user_id != nil,
      user_id: inspect(state.user_id),
      has_session_id: state.session_id != nil,
      session_id: inspect(state.session_id),
      expected_session_id: inspect(session_id),
      session_matches: state.session_id == session_id
    )

    if state.user_id && state.session_id == session_id do
      Logger.info("Retrying default subscriptions creation",
        user_id: state.user_id,
        session_id: session_id
      )

      manager_state = %{
        session_id: session_id,
        token_manager: state.token_manager,
        oauth2_client: state.token_manager.oauth2_client,
        scopes: state.scopes,
        user_id: state.user_id
      }

      if state.default_subscriptions_created do
        Logger.debug("Skipping subscription creation - already created")
        {:noreply, state}
      else
        {success_count, failed_count} = EventSubManager.create_default_subscriptions(manager_state)

        Logger.info("Default subscriptions created",
          success: success_count,
          failed: failed_count
        )

        # Only mark as created if we had some success
        state =
          if success_count > 0 do
            # Clear retry timer since we succeeded
            if state.retry_subscription_timer do
              Process.cancel_timer(state.retry_subscription_timer)
            end

            %{state | default_subscriptions_created: true, retry_subscription_timer: nil}
          else
            state
          end

        {:noreply, state}
      end
    else
      if state.session_id == session_id do
        # Still no user_id, retry again after a longer delay
        Logger.info("Default subscriptions retry deferred",
          reason: "user_id still not available, will retry again"
        )

        # Cancel any existing retry timer
        if state.retry_subscription_timer do
          Process.cancel_timer(state.retry_subscription_timer)
        end

        timer = Process.send_after(self(), {:retry_default_subscriptions, session_id}, 2000)
        {:noreply, %{state | retry_subscription_timer: timer}}
      else
        # Session ID changed, abandon this retry
        Logger.info("Default subscriptions retry abandoned",
          reason: "session changed",
          old_session: session_id,
          current_session: state.session_id
        )

        {:noreply, state}
      end
    end
  end

  # Catch-all for unhandled messages
  @impl GenServer
  def handle_info(message, state) do
    case message do
      {ref, _result} when is_reference(ref) ->
        Logger.debug("Task result ignored",
          task_ref: inspect(ref),
          has_validation_task: state.token_validation_task != nil,
          has_refresh_task: state.token_refresh_task != nil,
          reason: "task completed but not tracked"
        )

      {:DOWN, ref, :process, pid, reason} ->
        # Check if this is for one of our tracked tasks
        task_info =
          cond do
            state.token_validation_task && state.token_validation_task.ref == ref ->
              "validation_task"

            state.token_refresh_task && state.token_refresh_task.ref == ref ->
              "refresh_task"

            true ->
              "untracked_process"
          end

        Logger.debug("Process monitor notification",
          task_type: task_info,
          monitor_ref: inspect(ref),
          pid: inspect(pid),
          reason: inspect(reason),
          action: if(task_info == "untracked_process", do: "ignored", else: "should_be_handled_elsewhere")
        )

      other ->
        # Simple logging to avoid metadata issues
        Logger.debug("UNHANDLED MESSAGE: #{inspect(other, limit: 500)}")
        Logger.debug("Message type classification: #{message_type(other)}")
    end

    {:noreply, state}
  end

  defp cleanup_subscriptions(subscriptions) do
    Enum.each(subscriptions, fn {subscription_id, _subscription} ->
      Server.SubscriptionMonitor.untrack_subscription(subscription_id)
    end)
  end

  defp cleanup_websocket(nil), do: :ok

  defp cleanup_websocket(ws_client) do
    WebSocketClient.close(ws_client)
  end

  defp cleanup_tasks(state) do
    shutdown_task(state.token_validation_task, "Token validation")
    shutdown_task(state.token_refresh_task, "Token refresh")
  end

  defp shutdown_task(nil, _name), do: :ok

  defp shutdown_task(task, name) do
    case Task.shutdown(task, 5_000) do
      :ok -> :ok
      {:exit, :normal} -> :ok
      nil -> Logger.warning("#{name} task timeout during termination")
    end
  end

  defp cleanup_timers(state) do
    cancel_timer(state.reconnect_timer, "reconnect")
    cancel_timer(state.token_refresh_timer, "token_refresh")
    cancel_timer(state.retry_subscription_timer, "retry_subscription")
  end

  defp cancel_timer(nil, _name), do: :ok

  defp cancel_timer(timer_ref, name) do
    case Process.cancel_timer(timer_ref) do
      false -> Logger.debug("Timer cleanup skipped", timer: name, reason: "already expired")
      _time_left -> Logger.debug("Timer cleanup completed", timer: name)
    end
  end

  # Private functions

  defp handle_eventsub_message(state, message_json) do
    # DEBUG: Log all incoming EventSub messages

    case JSON.decode(message_json) do
      {:ok, message} ->
        # DEBUG: Log the decoded message structure

        handle_eventsub_protocol_message(state, message)

      {:error, reason} ->
        Logger.error("EventSub message decode failed", error: reason, message: message_json)
        state
    end
  end

  defp handle_eventsub_protocol_message(
         state,
         %{"metadata" => %{"message_type" => "session_welcome"}} = message
       ) do
    session_data = message["payload"]["session"]
    session_id = session_data["id"]

    Logger.info("EventSub session established", session_id: session_id)

    state =
      update_connection_state(state, %{
        connected: true,
        connection_state: "connected",
        session_id: session_id,
        last_connected: DateTime.utc_now()
      })
      |> Map.put(:session_id, session_id)

    # Create default subscriptions using EventSubManager
    # Check if user_id is available from token validation or OAuth service
    {user_id, scopes} =
      case {state.user_id, state.scopes} do
        {nil, nil} ->
          # Try to get from OAuth service
          case Server.OAuthService.get_token_info(:twitch) do
            {:ok, %{user_id: uid, scopes: sc}} -> {uid, sc}
            _ -> {nil, nil}
          end

        {uid, sc} ->
          {uid, sc}
      end

    Logger.info("Session welcome subscription check",
      has_user_id: user_id != nil,
      user_id: inspect(user_id),
      session_id: inspect(session_id),
      has_scopes: scopes != nil,
      scope_count: if(scopes, do: MapSet.size(scopes), else: 0),
      source: if(state.user_id, do: "state", else: "oauth_service")
    )

    if user_id do
      manager_state = %{
        session_id: session_id,
        token_manager: state.token_manager,
        oauth2_client: state.token_manager.oauth2_client,
        scopes: scopes,
        user_id: user_id
      }

      if state.default_subscriptions_created do
        Logger.debug("Skipping subscription creation - already created")
        state
      else
        {success_count, failed_count} = EventSubManager.create_default_subscriptions(manager_state)

        Logger.info("Default subscriptions created",
          success: success_count,
          failed: failed_count
        )

        # Only mark as created if we had some success
        if success_count > 0 do
          # Clear retry timer since we succeeded
          if state.retry_subscription_timer do
            Process.cancel_timer(state.retry_subscription_timer)
          end

          %{state | default_subscriptions_created: true, retry_subscription_timer: nil}
        else
          state
        end
      end
    else
      # user_id not available yet, schedule retry after token validation completes
      Logger.info("Default subscriptions deferred",
        reason: "user_id not available, will retry after token validation"
      )

      # Cancel any existing retry timer
      state =
        if state.retry_subscription_timer do
          Process.cancel_timer(state.retry_subscription_timer)
          %{state | retry_subscription_timer: nil}
        else
          state
        end

      # Reduced delay for faster subscription creation
      timer = Process.send_after(self(), {:retry_default_subscriptions, session_id}, 500)
      %{state | retry_subscription_timer: timer}
    end
  end

  defp handle_eventsub_protocol_message(state, %{
         "metadata" => %{"message_type" => "session_keepalive"}
       }) do
    state
  end

  defp handle_eventsub_protocol_message(
         state,
         %{"metadata" => %{"message_type" => "notification"}} = message
       ) do
    event_type = get_in(message, ["metadata", "subscription_type"])
    event_data = message["payload"]["event"]
    subscription_id = get_in(message, ["metadata", "subscription_id"])
    message_id = get_in(message, ["metadata", "message_id"])
    message_timestamp = get_in(message, ["metadata", "message_timestamp"])

    Logger.info("EventSub notification received",
      event_type: event_type,
      subscription_id: subscription_id,
      message_id: message_id,
      message_timestamp: message_timestamp,
      event_data_keys: Map.keys(event_data || %{}),
      raw_message_size: byte_size(:erlang.term_to_binary(message))
    )

    # Additional debug logging for chat messages specifically
    if event_type == "channel.chat.message" do
      Logger.debug("Processing chat message",
        event_type: event_type,
        user_id: event_data["broadcaster_user_id"],
        user_login: event_data["broadcaster_user_login"],
        user_name: event_data["broadcaster_user_name"],
        chatter_user_id: event_data["chatter_user_id"],
        chatter_user_login: event_data["chatter_user_login"],
        chatter_user_name: event_data["chatter_user_name"],
        message_text: event_data["message"]["text"],
        message_id: event_data["message_id"],
        full_event_data: inspect(event_data, limit: :infinity)
      )
    end

    # Record event reception in subscription monitor
    if subscription_id do
      Server.SubscriptionMonitor.record_event_received(subscription_id)
    end

    # Process the event using EventHandler module
    EventHandler.process_event(event_type, event_data)

    state
  end

  defp handle_eventsub_protocol_message(
         state,
         %{"metadata" => %{"message_type" => "session_reconnect"}} = message
       ) do
    reconnect_url = get_in(message, ["payload", "session", "reconnect_url"])
    Logger.info("EventSub reconnection requested", reconnect_url: reconnect_url)

    # Initiate reconnection to new URL
    case reconnect_url do
      nil ->
        Logger.error("EventSub reconnection failed", error: "no URL provided")
        state

      url when is_binary(url) ->
        Logger.info("EventSub reconnection initiated", url: url)
        # Close current connection and reconnect to new URL
        _result = WebSocketClient.close(state.ws_client)
        new_state = %{state | session_id: nil}
        # Start reconnection process
        send(self(), {:reconnect_to_url, url})
        new_state
    end
  end

  defp handle_eventsub_protocol_message(state, message) do
    message_type = get_in(message, ["metadata", "message_type"])
    subscription_type = get_in(message, ["metadata", "subscription_type"])

    Logger.debug("EventSub message unhandled",
      message_type: message_type,
      subscription_type: subscription_type,
      has_payload: Map.has_key?(message, "payload"),
      metadata_keys: Map.keys(message["metadata"] || %{}),
      reason: "no handler implemented"
    )

    state
  end

  # State update helpers
  defp update_connection_state(state, updates) do
    # Merge updates directly into state (no more nested connection)
    new_state = Map.merge(state, updates)

    # Invalidate relevant caches
    invalidate_twitch_caches([:connection_state, :connection_status, :full_state])

    # Publish connection state changes with connection-specific fields
    connection_fields = %{
      connected: new_state.connected,
      connection_state: new_state.connection_state,
      last_error: new_state.last_error,
      last_connected: new_state.last_connected,
      session_id: new_state.session_id
    }

    Phoenix.PubSub.broadcast(Server.PubSub, "dashboard", {:twitch_connection_changed, connection_fields})

    new_state
  end

  # Cache invalidation helper
  defp invalidate_twitch_caches(cache_keys) do
    Enum.each(cache_keys, fn key ->
      Server.Cache.invalidate(:twitch_service, key)
    end)
  end

  defp schedule_token_refresh(state) do
    # Cancel existing timer
    if state.token_refresh_timer do
      Process.cancel_timer(state.token_refresh_timer)
    end

    # Check if token needs refresh using OAuth service
    case Server.OAuthService.get_valid_token(:twitch) do
      {:ok, %{access_token: _token}} ->
        # Token is still valid, check again in 5 minutes
        timer = Process.send_after(self(), :refresh_token, @token_refresh_buffer)
        %{state | token_refresh_timer: timer}

      {:error, _reason} ->
        # Token needs refresh now
        timer = Process.send_after(self(), :refresh_token, 1000)
        %{state | token_refresh_timer: timer}
    end
  end

  # Helper functions for configuration
  defp get_client_id do
    case Application.get_env(:server, :twitch) do
      nil -> System.get_env("TWITCH_CLIENT_ID")
      twitch_config -> Keyword.get(twitch_config, :client_id) || System.get_env("TWITCH_CLIENT_ID")
    end
  end

  defp get_client_secret do
    case Application.get_env(:server, :twitch) do
      nil -> System.get_env("TWITCH_CLIENT_SECRET")
      twitch_config -> Keyword.get(twitch_config, :client_secret) || System.get_env("TWITCH_CLIENT_SECRET")
    end
  end

  # Helper to identify message types for better debugging
  defp message_type({:websocket_connected, _}), do: "websocket_connected"
  defp message_type({:websocket_disconnected, _, _}), do: "websocket_disconnected"
  defp message_type({:websocket_message, _, _}), do: "websocket_message"
  defp message_type({:websocket_reconnect, _}), do: "websocket_reconnect"
  defp message_type({:reconnect_to_url, _}), do: "reconnect_to_url"
  defp message_type({ref, _}) when is_reference(ref), do: "task_result"
  defp message_type({:DOWN, _, _, _, _}), do: "process_down"
  defp message_type(atom) when is_atom(atom), do: to_string(atom)
  defp message_type(tuple) when is_tuple(tuple), do: "tuple(#{tuple_size(tuple)})"
  defp message_type(other), do: "#{inspect(other.__struct__ || :unknown)}"
end
