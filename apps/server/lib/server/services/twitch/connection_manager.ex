defmodule Server.Services.Twitch.ConnectionManager do
  @moduledoc """
  Manages Twitch EventSub WebSocket connections with CloudFront CDN support.

  This module handles the transport layer for Twitch EventSub, including:
  - WebSocket connection lifecycle with CloudFront compatibility
  - Session management and welcome message handling
  - Message routing to the parent Twitch service
  - Automatic reconnection with exponential backoff
  - CloudFront 400 error retry with user-agent rotation

  ## Architecture

  The ConnectionManager uses WebSocketConnection as a child process for the
  actual WebSocket transport, while this module handles Twitch-specific
  protocol details and session management.

  ## Session Lifecycle

  1. Connect to EventSub WebSocket endpoint
  2. Receive session_welcome message with session_id
  3. Parent service creates subscriptions using session_id
  4. Handle incoming events and notifications
  5. Reconnect on session_keepalive timeout or connection loss

  ## CloudFront Compatibility

  Twitch uses CloudFront CDN which requires specific headers and retry logic
  for 400 errors. The WebSocketConnection module handles this automatically
  when retry_config is enabled.
  """

  use GenServer
  require Logger

  alias Server.{CorrelationId, WebSocketConnection}
  alias Server.Services.Twitch.Protocol

  @type state :: %{
          uri: String.t(),
          ws_conn: pid() | nil,
          session_id: String.t() | nil,
          connection_state: connection_state(),
          owner: pid(),
          owner_ref: reference() | nil,
          keepalive_timer: reference() | nil,
          correlation_id: String.t()
        }

  @type connection_state :: :disconnected | :connecting | :connected | :ready

  # Twitch EventSub WebSocket endpoint
  @eventsub_uri "wss://eventsub.wss.twitch.tv/ws"

  # Session keepalive timeout (10 seconds as per Twitch docs)
  @keepalive_timeout 10_000

  # Client API

  @doc """
  Starts the Twitch ConnectionManager.

  ## Options
  - `:owner` - Process to notify of connection events (defaults to caller)
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initiates connection to Twitch EventSub.
  """
  def connect(manager \\ __MODULE__) do
    GenServer.call(manager, :connect)
  end

  @doc """
  Disconnects from Twitch EventSub.
  """
  def disconnect(manager \\ __MODULE__) do
    GenServer.call(manager, :disconnect)
  end

  @doc """
  Gets current connection state.
  """
  def get_state(manager \\ __MODULE__) do
    GenServer.call(manager, :get_state)
  end

  @doc """
  Sends a message through the WebSocket connection.
  """
  def send_message(manager \\ __MODULE__, message) do
    GenServer.call(manager, {:send_message, message})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    owner = Keyword.get(opts, :owner, self())
    correlation_id = CorrelationId.generate()

    # Accept optional parameters for testing
    uri = Keyword.get(opts, :url, @eventsub_uri)
    client_id = Keyword.get(opts, :client_id)

    state = %{
      uri: uri,
      ws_conn: nil,
      session_id: nil,
      connection_state: :disconnected,
      owner: owner,
      owner_ref: Process.monitor(owner),
      keepalive_timer: nil,
      correlation_id: correlation_id,
      client_id: client_id
    }

    Logger.info("[#{correlation_id}] Twitch ConnectionManager initialized",
      uri: @eventsub_uri,
      owner: inspect(owner)
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, state) do
    new_state = do_connect(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    new_state = do_disconnect(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      connected: state.connection_state == :ready,
      connection_state: state.connection_state,
      session_id: state.session_id,
      uri: state.uri
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:send_message, message}, _from, %{ws_conn: ws_conn} = state) when not is_nil(ws_conn) do
    case WebSocketConnection.send_data(ws_conn, message) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:send_message, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  # WebSocketConnection events

  @impl true
  def handle_info({WebSocketConnection, ws_conn, {:websocket_connecting, _}}, %{ws_conn: ws_conn} = state) do
    Logger.info("[#{state.correlation_id}] Connecting to Twitch EventSub")

    state = %{state | connection_state: :connecting}
    notify_owner(state, {:connection_state_changed, :connecting})

    {:noreply, state}
  end

  @impl true
  def handle_info({WebSocketConnection, ws_conn, {:websocket_connected, _}}, %{ws_conn: ws_conn} = state) do
    Logger.info("[#{state.correlation_id}] WebSocket connected to Twitch EventSub")

    state = %{state | connection_state: :connected}
    # Wait for session_welcome to transition to :ready

    {:noreply, state}
  end

  @impl true
  def handle_info({WebSocketConnection, ws_conn, {:websocket_frame, {:text, frame}}}, %{ws_conn: ws_conn} = state) do
    state = handle_frame(frame, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {WebSocketConnection, ws_conn, {:websocket_disconnected, %{reason: reason}}},
        %{ws_conn: ws_conn} = state
      ) do
    Logger.warning("[#{state.correlation_id}] WebSocket disconnected",
      reason: inspect(reason),
      session_id: state.session_id
    )

    state = handle_disconnect(reason, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({WebSocketConnection, ws_conn, {:websocket_error, %{reason: reason}}}, %{ws_conn: ws_conn} = state) do
    Logger.error("[#{state.correlation_id}] WebSocket error",
      error: inspect(reason),
      session_id: state.session_id
    )

    state = handle_disconnect(reason, state)
    {:noreply, state}
  end

  # Keepalive timeout
  @impl true
  def handle_info(:keepalive_timeout, state) do
    Logger.warning("[#{state.correlation_id}] Keepalive timeout, reconnecting",
      session_id: state.session_id
    )

    state =
      state
      |> do_disconnect()
      |> do_connect()

    {:noreply, state}
  end

  # Monitor owner process
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{owner_ref: ref} = state) do
    Logger.info("[#{state.correlation_id}] Owner process terminated, shutting down",
      reason: inspect(reason)
    )

    {:stop, :normal, state}
  end

  # Catch-all for WebSocketConnection messages with mismatched ws_conn
  @impl true
  def handle_info({WebSocketConnection, _ws_conn, {:websocket_frame, {:text, frame}}} = msg, state) do
    Logger.debug("[#{state.correlation_id}] Received frame from different ws_conn, processing anyway",
      message: inspect(msg),
      state_ws_conn: inspect(state.ws_conn)
    )

    state = handle_frame(frame, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({WebSocketConnection, _ws_conn, {:websocket_error, %{reason: reason}}} = msg, state) do
    Logger.debug("[#{state.correlation_id}] Received error from different ws_conn, processing anyway",
      message: inspect(msg),
      state_ws_conn: inspect(state.ws_conn),
      reason: inspect(reason)
    )

    state = handle_disconnect(reason, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({WebSocketConnection, _ws_conn, {:websocket_disconnected, %{reason: reason}}} = msg, state) do
    Logger.debug("[#{state.correlation_id}] Received disconnect from different ws_conn, processing anyway",
      message: inspect(msg),
      state_ws_conn: inspect(state.ws_conn),
      reason: inspect(reason)
    )

    state = handle_disconnect(reason, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({WebSocketConnection, _ws_conn, {:websocket_connected, _data}} = msg, state) do
    Logger.debug("[#{state.correlation_id}] Received connected from different ws_conn, processing anyway",
      message: inspect(msg),
      state_ws_conn: inspect(state.ws_conn)
    )

    state = %{state | connection_state: :connected}
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[#{state.correlation_id}] Unhandled message",
      message: inspect(msg)
    )

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[#{state.correlation_id}] Terminating ConnectionManager",
      reason: inspect(reason)
    )

    if state.ws_conn && is_pid(state.ws_conn) do
      WebSocketConnection.disconnect(state.ws_conn)
    end

    :ok
  end

  # Private functions

  defp do_connect(%{ws_conn: nil} = state) do
    Logger.info("[#{state.correlation_id}] Starting WebSocket connection to Twitch")

    # CloudFront-specific headers for Twitch
    headers = [
      {"client-id", get_client_id(state)},
      {"sec-websocket-protocol", "wss"}
    ]

    {:ok, ws_conn} =
      WebSocketConnection.start_link(
        uri: state.uri,
        owner: self(),
        auto_connect: true,
        headers: headers,
        retry_config: [
          enabled: true,
          max_retries: 3
        ],
        reconnect_base_delay: 1_000,
        reconnect_max_delay: 30_000
      )

    %{state | ws_conn: ws_conn}
  end

  defp do_connect(state), do: state

  defp do_disconnect(state) do
    Logger.info("[#{state.correlation_id}] Disconnecting from Twitch")

    # Cancel keepalive timer
    state = cancel_keepalive_timer(state)

    # Disconnect WebSocket
    if state.ws_conn do
      WebSocketConnection.disconnect(state.ws_conn)
    end

    # Notify owner
    if state.session_id do
      notify_owner(state, {:session_ended, state.session_id})
    end

    notify_owner(state, {:connection_state_changed, :disconnected})

    %{state | ws_conn: nil, session_id: nil, connection_state: :disconnected}
  end

  defp handle_frame(frame, state) do
    case Protocol.decode_message(frame) do
      {:ok, message} ->
        handle_message(message, state)

      {:error, reason} ->
        Logger.error("[#{state.correlation_id}] Failed to decode message",
          error: inspect(reason),
          frame: frame
        )

        state
    end
  end

  defp handle_message(%{"metadata" => %{"message_type" => "session_welcome"}} = message, state) do
    session = message["payload"]["session"]
    session_id = session["id"]
    keepalive_timeout = session["keepalive_timeout_seconds"] * 1_000

    Logger.info("[#{state.correlation_id}] Session welcome received",
      session_id: session_id,
      keepalive_timeout_seconds: session["keepalive_timeout_seconds"],
      status: session["status"]
    )

    # Start keepalive timer
    state = reset_keepalive_timer(state, keepalive_timeout)

    # Update state
    state = %{state | session_id: session_id, connection_state: :ready}

    # Notify owner - CRITICAL: subscriptions must be created immediately
    notify_owner(state, {:session_welcome, session_id, session})
    notify_owner(state, {:connection_state_changed, :ready})

    state
  end

  defp handle_message(%{"metadata" => %{"message_type" => "session_keepalive"}} = _message, state) do
    Logger.debug("[#{state.correlation_id}] Keepalive received",
      session_id: state.session_id
    )

    # Reset keepalive timer
    reset_keepalive_timer(state, @keepalive_timeout)
  end

  defp handle_message(%{"metadata" => %{"message_type" => "notification"}} = message, state) do
    # Forward notification to owner
    notify_owner(state, {:notification, message})

    # Reset keepalive timer
    reset_keepalive_timer(state, @keepalive_timeout)
  end

  defp handle_message(%{"metadata" => %{"message_type" => "session_reconnect"}} = message, state) do
    session = message["payload"]["session"]
    reconnect_url = session["reconnect_url"]

    Logger.info("[#{state.correlation_id}] Session reconnect requested",
      session_id: state.session_id,
      reconnect_url: reconnect_url
    )

    # Notify owner
    notify_owner(state, {:session_reconnect, reconnect_url})

    # TODO: Implement reconnection to new URL
    state
  end

  defp handle_message(%{"metadata" => %{"message_type" => "revocation"}} = message, state) do
    Logger.warning("[#{state.correlation_id}] Subscription revoked",
      subscription: message["payload"]["subscription"]
    )

    # Forward to owner
    notify_owner(state, {:revocation, message})
    state
  end

  defp handle_message(message, state) do
    Logger.warning("[#{state.correlation_id}] Unknown message type",
      message_type: get_in(message, ["metadata", "message_type"]),
      message: inspect(message)
    )

    state
  end

  defp handle_disconnect(_reason, state) do
    # Cancel keepalive timer
    state = cancel_keepalive_timer(state)

    # Update state
    state = %{state | session_id: nil, connection_state: :disconnected}

    # Notify owner
    notify_owner(state, {:connection_lost, state.session_id})
    notify_owner(state, {:connection_state_changed, :disconnected})

    # WebSocketConnection will handle reconnection
    state
  end

  defp reset_keepalive_timer(state, timeout) do
    state = cancel_keepalive_timer(state)
    timer = Process.send_after(self(), :keepalive_timeout, timeout)
    %{state | keepalive_timer: timer}
  end

  defp cancel_keepalive_timer(%{keepalive_timer: nil} = state), do: state

  defp cancel_keepalive_timer(state) do
    Process.cancel_timer(state.keepalive_timer)
    %{state | keepalive_timer: nil}
  end

  defp notify_owner(state, message) do
    send(state.owner, {:twitch_connection, message})
  end

  defp get_client_id(state) do
    # Use client_id from state if available (for testing), otherwise from config
    state[:client_id] ||
      Application.get_env(:server, :twitch)[:client_id] ||
      raise "Twitch client_id not configured"
  end
end
