defmodule Server.Services.Twitch do
  @moduledoc """
  Main Twitch EventSub service coordinating WebSocket connection and subscription management.

  This GenServer focuses on connection lifecycle and delegates to specialized modules:
  - `Server.Services.Twitch.EventSubManager` for subscription management
  - `Server.Services.Twitch.EventHandler` for event processing
  - `Server.OAuthTokenManager` for token management
  - `Server.WebSocketClient` for WebSocket connection handling
  """

  use GenServer
  require Logger

  alias Server.Services.Twitch.{EventHandler, EventSubManager}
  alias Server.{OAuthTokenManager, WebSocketClient}

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
    :token_manager,
    :ws_client,
    :user_id,
    :scopes,
    subscriptions: %{},
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

  # Client API

  @doc """
  Starts the Twitch EventSub service GenServer.

  ## Parameters
  - `opts` - Keyword list of options (optional)
    - `:client_id` - Twitch application client ID
    - `:client_secret` - Twitch application client secret

  ## Returns
  - `{:ok, pid}` on success
  - `{:error, reason}` on failure
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current internal state of the Twitch service.

  ## Returns
  - Map containing connection, subscriptions, and EventSub state
  """
  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Gets the current status of the Twitch service.

  ## Returns
  - `{:ok, status}` where status contains connection and subscription information
  - `{:error, reason}` if service is unavailable
  """
  @spec get_status() :: {:ok, map()} | {:error, binary()}
  def get_status do
    GenServer.call(__MODULE__, :get_status)
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
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end

  # GenServer callbacks
  @impl GenServer
  def init(opts) do
    client_id = Keyword.get(opts, :client_id) || get_client_id()
    client_secret = Keyword.get(opts, :client_secret) || get_client_secret()

    # Ensure we have required credentials
    if !client_id || !client_secret do
      Logger.error("Twitch service missing required credentials",
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

    # Initialize WebSocket client
    ws_client =
      WebSocketClient.new(
        @eventsub_websocket_url,
        self(),
        telemetry_prefix: [:server, :twitch, :websocket]
      )

    state = %__MODULE__{
      token_manager: token_manager,
      ws_client: ws_client,
      subscriptions: %{},
      token_validation_task: nil,
      token_refresh_task: nil
    }

    Logger.info("Twitch service starting", client_id: client_id)

    # Start connection process if we have tokens
    case OAuthTokenManager.get_valid_token(token_manager) do
      {:ok, _token, updated_manager} ->
        Logger.info("Valid OAuth tokens found, starting connection")
        state = %{state | token_manager: updated_manager}
        send(self(), :validate_token)
        {:ok, state}

      {:error, reason} ->
        Logger.info("No valid tokens available, will retry connection later", reason: reason)
        timer = Process.send_after(self(), :retry_connection, Server.NetworkConfig.reconnect_interval())
        {:ok, %{state | reconnect_timer: timer}}
    end
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      connected: state.state.connection.connected,
      connection_state: state.state.connection.connection_state,
      session_id: state.state.connection.session_id,
      subscription_count: map_size(state.subscriptions),
      subscription_cost: state.state.subscription_total_cost
    }

    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call({:create_subscription, event_type, condition, opts}, _from, state) do
    cond do
      not (state.state.connection.connected && state.session_id) ->
        {:reply, {:error, "WebSocket not connected"}, state}

      state.state.subscription_count >= state.state.subscription_max_count ->
        {:reply, {:error, "Subscription count limit exceeded (#{state.state.subscription_max_count})"}, state}

      true ->
        handle_subscription_creation(event_type, condition, opts, state)
    end
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
        Logger.warning("Duplicate subscription attempt",
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
        state: %{
          state.state
          | subscription_total_cost: state.state.subscription_total_cost + cost,
            subscription_count: state.state.subscription_count + 1
        }
    }

    {:reply, {:ok, subscription}, new_state}
  end

  @impl GenServer
  def handle_call({:delete_subscription, subscription_id}, _from, state) do
    # Create manager state for EventSubManager
    manager_state = %{
      oauth2_client: state.token_manager.oauth2_client
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
            state: %{
              state.state
              | subscription_total_cost: max(0, state.state.subscription_total_cost - cost),
                subscription_count: max(0, state.state.subscription_count - 1)
            }
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_subscriptions, _from, state) do
    {:reply, {:ok, state.subscriptions}, state}
  end

  @impl GenServer
  def handle_info(:retry_connection, state) do
    case OAuthTokenManager.get_valid_token(state.token_manager) do
      {:ok, _token, updated_manager} ->
        state = %{state | token_manager: updated_manager}
        send(self(), :validate_token)
        {:noreply, state}

      {:error, reason} ->
        Logger.info("Still no valid tokens available", reason: reason)
        timer = Process.send_after(self(), :retry_connection, Server.NetworkConfig.reconnect_interval())
        {:noreply, %{state | reconnect_timer: timer}}
    end
  end

  @impl GenServer
  def handle_info(:connect, state) do
    Logger.info("Initiating Twitch WebSocket connection")

    case WebSocketClient.connect(state.ws_client) do
      {:ok, updated_client} ->
        state = %{state | ws_client: updated_client}

        state =
          update_connection_state(state, %{
            connection_state: "connecting"
          })

        {:noreply, state}

      {:error, updated_client, reason} ->
        Logger.error("Twitch WebSocket connection failed", reason: reason)
        state = %{state | ws_client: updated_client}

        state =
          update_connection_state(state, %{
            connected: false,
            connection_state: "error",
            last_error: inspect(reason)
          })

        # Schedule reconnect
        timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())
        state = %{state | reconnect_timer: timer}
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:validate_token, state) do
    # Cancel any existing validation task
    if state.token_validation_task do
      Task.shutdown(state.token_validation_task, :brutal_kill)
    end

    # Start async token validation
    task =
      Task.async(fn ->
        OAuthTokenManager.validate_token(state.token_manager, "https://id.twitch.tv/oauth2/validate")
      end)

    {:noreply, %{state | token_validation_task: task}}
  end

  @impl GenServer
  def handle_info(:refresh_token, state) do
    # Cancel any existing refresh task
    if state.token_refresh_task do
      Task.shutdown(state.token_refresh_task, :brutal_kill)
    end

    # Start async token refresh
    task =
      Task.async(fn ->
        OAuthTokenManager.refresh_token(state.token_manager)
      end)

    {:noreply, %{state | token_refresh_task: task}}
  end

  # Async task result handlers
  @impl GenServer
  def handle_info({ref, result}, %{token_validation_task: %Task{ref: ref}} = state) do
    # Token validation task completed
    case result do
      {:ok, token_info, updated_manager} ->
        Logger.info("Twitch token validation successful",
          user_id: token_info["user_id"],
          client_id: token_info["client_id"],
          scopes: length(token_info["scopes"] || [])
        )

        # Store user ID and scopes in state
        state = %{
          state
          | token_manager: updated_manager,
            user_id: token_info["user_id"],
            scopes: MapSet.new(token_info["scopes"] || []),
            token_validation_task: nil
        }

        send(self(), :connect)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Twitch token validation failed", error: reason)

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
      {:ok, updated_manager} ->
        Logger.info("Twitch OAuth tokens refreshed")
        state = %{state | token_manager: updated_manager, token_refresh_task: nil}
        state = schedule_token_refresh(state)
        # Validate new token after successful refresh
        send(self(), :validate_token)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Twitch OAuth token refresh failed", error: reason)
        # Try again in a shorter interval
        timer = Process.send_after(self(), :refresh_token, Server.NetworkConfig.reconnect_interval())
        state = %{state | token_refresh_timer: timer, token_refresh_task: nil}
        {:noreply, state}
    end
  end

  # Handle task DOWN messages (task crashed)
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{token_validation_task: %Task{ref: ref}} = state) do
    Logger.error("Token validation task crashed", reason: inspect(reason))
    # Retry validation after a delay
    timer = Process.send_after(self(), :validate_token, Server.NetworkConfig.reconnect_interval())
    {:noreply, %{state | token_validation_task: nil, reconnect_timer: timer}}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{token_refresh_task: %Task{ref: ref}} = state) do
    Logger.error("Token refresh task crashed", reason: inspect(reason))
    # Retry refresh after a delay
    timer = Process.send_after(self(), :refresh_token, Server.NetworkConfig.reconnect_interval())
    {:noreply, %{state | token_refresh_task: nil, token_refresh_timer: timer}}
  end

  # WebSocketClient event handlers
  @impl GenServer
  def handle_info({:websocket_connected, client}, state) do
    Logger.info("Twitch WebSocket connection established")

    state = %{state | ws_client: client}

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
    Logger.warning("Twitch WebSocket disconnected", reason: reason)

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
    timer = Process.send_after(self(), :connect, Server.NetworkConfig.reconnect_interval())
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
    Logger.info("Attempting Twitch WebSocket reconnection")
    state = %{state | ws_client: client}
    send(self(), :connect)
    {:noreply, state}
  end

  def handle_info({:reconnect_to_url, url}, state) do
    Logger.info("Reconnecting to new Twitch EventSub URL", url: url)

    # Create new WebSocket client with the new URL
    new_client = WebSocketClient.new(url, self())

    # Initiate connection
    WebSocketClient.connect(new_client)

    state = %{state | ws_client: new_client, session_id: nil}
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("Twitch service terminating", reason: reason)

    # Clean up all tracked subscriptions from monitor
    Enum.each(state.subscriptions, fn {subscription_id, _subscription} ->
      Server.SubscriptionMonitor.untrack_subscription(subscription_id)
    end)

    # Close WebSocket connection
    if state.ws_client do
      WebSocketClient.close(state.ws_client)
    end

    # Close OAuth token manager with error handling
    if state.token_manager do
      try do
        OAuthTokenManager.close(state.token_manager)
      rescue
        error ->
          Logger.warning("Error closing OAuth token manager", error: inspect(error))
      end
    end

    # Cancel async tasks
    if state.token_validation_task do
      Task.shutdown(state.token_validation_task, :brutal_kill)
    end

    if state.token_refresh_task do
      Task.shutdown(state.token_refresh_task, :brutal_kill)
    end

    # Cancel timers with validation
    if state.reconnect_timer do
      case Process.cancel_timer(state.reconnect_timer) do
        false -> Logger.debug("Reconnect timer already expired")
        _time_left -> Logger.debug("Cancelled reconnect timer")
      end
    end

    if state.token_refresh_timer do
      case Process.cancel_timer(state.token_refresh_timer) do
        false -> Logger.debug("Token refresh timer already expired")
        _time_left -> Logger.debug("Cancelled token refresh timer")
      end
    end

    :ok
  end

  # Private functions

  defp handle_eventsub_message(state, message_json) do
    case Jason.decode(message_json) do
      {:ok, message} ->
        handle_eventsub_protocol_message(state, message)

      {:error, reason} ->
        Logger.error("Twitch message decode failed", error: reason, message: message_json)
        state
    end
  end

  defp handle_eventsub_protocol_message(
         state,
         %{"metadata" => %{"message_type" => "session_welcome"}} = message
       ) do
    session_data = message["payload"]["session"]
    session_id = session_data["id"]

    Logger.info("Twitch session welcome received", session_id: session_id)

    state =
      update_connection_state(state, %{
        connected: true,
        connection_state: "connected",
        session_id: session_id,
        last_connected: DateTime.utc_now()
      })
      |> Map.put(:session_id, session_id)

    # Create default subscriptions using EventSubManager
    manager_state = %{
      session_id: session_id,
      oauth2_client: state.token_manager.oauth2_client,
      scopes: state.scopes,
      user_id: state.user_id
    }

    {success_count, failed_count} = EventSubManager.create_default_subscriptions(manager_state)

    Logger.info("Twitch default subscriptions created",
      success: success_count,
      failed: failed_count
    )

    state
  end

  defp handle_eventsub_protocol_message(state, %{
         "metadata" => %{"message_type" => "session_keepalive"}
       }) do
    Logger.debug("Twitch keepalive received")
    state
  end

  defp handle_eventsub_protocol_message(
         state,
         %{"metadata" => %{"message_type" => "notification"}} = message
       ) do
    event_type = get_in(message, ["metadata", "subscription_type"])
    event_data = message["payload"]["event"]
    subscription_id = get_in(message, ["metadata", "subscription_id"])

    Logger.info("Twitch event received",
      event_type: event_type,
      subscription_id: subscription_id
    )

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
    Logger.info("Twitch session reconnect requested", reconnect_url: reconnect_url)

    # Initiate reconnection to new URL
    case reconnect_url do
      nil ->
        Logger.error("No reconnect URL provided in session_reconnect message")
        state

      url when is_binary(url) ->
        Logger.info("Initiating reconnection to new URL", url: url)
        # Close current connection and reconnect to new URL
        :ok = WebSocketClient.close(state.ws_client)
        new_state = %{state | session_id: nil}
        # Start reconnection process
        send(self(), {:reconnect_to_url, url})
        new_state
    end
  end

  defp handle_eventsub_protocol_message(state, message) do
    Logger.debug("Twitch message unhandled", message: message)
    state
  end

  # State update helpers
  defp update_connection_state(state, updates) do
    connection = Map.merge(state.state.connection, updates)
    new_state = put_in(state.state.connection, connection)

    # Publish connection state changes
    Phoenix.PubSub.broadcast(Server.PubSub, "dashboard", {:twitch_connection_changed, connection})

    new_state
  end

  defp schedule_token_refresh(state) do
    # Cancel existing timer
    if state.token_refresh_timer do
      Process.cancel_timer(state.token_refresh_timer)
    end

    # Use OAuthTokenManager's built-in refresh timing
    case OAuthTokenManager.get_valid_token(state.token_manager) do
      {:ok, _token, updated_manager} ->
        # Token is still valid, check again in 5 minutes
        timer = Process.send_after(self(), :refresh_token, @token_refresh_buffer)
        %{state | token_manager: updated_manager, token_refresh_timer: timer}

      {:error, _reason} ->
        # Token needs refresh now
        timer = Process.send_after(self(), :refresh_token, 1000)
        %{state | token_refresh_timer: timer}
    end
  end

  # Catch-all for unhandled messages
  @impl GenServer
  def handle_info(message, state) do
    Logger.debug("Unhandled message in Twitch service", message: inspect(message))
    {:noreply, state}
  end

  # Helper functions for configuration
  defp get_client_id do
    System.get_env("TWITCH_CLIENT_ID")
  end

  defp get_client_secret do
    System.get_env("TWITCH_CLIENT_SECRET")
  end
end
