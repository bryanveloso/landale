defmodule Server.WebSocketConnection do
  @moduledoc """
  Shared WebSocket connection management for services.

  This module provides common WebSocket connection functionality that can be
  composed into service-specific connection managers. It handles:

  - Connection lifecycle (connect, disconnect, reconnect)
  - Automatic reconnection with exponential backoff
  - Connection state tracking
  - Resource cleanup
  - Health monitoring

  Services like OBS and Twitch can use this module to reduce duplication
  while maintaining their specific authentication and protocol handling.
  """

  use GenServer
  require Logger

  alias Server.{ConnectionManager, CorrelationId}

  @type state :: %{
          uri: String.t(),
          conn_pid: pid() | nil,
          stream_ref: reference() | nil,
          connection_state: atom(),
          reconnect_attempt: non_neg_integer(),
          reconnect_timer: reference() | nil,
          conn_manager: ConnectionManager.connection_state(),
          owner: pid(),
          owner_ref: reference() | nil,
          opts: keyword()
        }

  @type connection_state :: :disconnected | :connecting | :connected | :reconnecting | :error

  # Configuration defaults
  @default_reconnect_base_delay 5_000
  @default_reconnect_max_delay 60_000
  @default_reconnect_factor 2

  # Client API

  @doc """
  Starts a WebSocket connection manager.

  ## Options
  - `:uri` - WebSocket URI (required)
  - `:owner` - Process to notify of connection events (defaults to caller)
  - `:auto_connect` - Whether to connect immediately (default: true)
  - `:reconnect_base_delay` - Base delay for reconnection (default: 5000ms)
  - `:reconnect_max_delay` - Maximum reconnection delay (default: 60000ms)
  - `:reconnect_factor` - Exponential backoff factor (default: 2)
  - `:headers` - Additional headers for WebSocket upgrade
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Initiates WebSocket connection.
  """
  def connect(conn), do: GenServer.call(conn, :connect)

  @doc """
  Disconnects WebSocket connection.
  """
  def disconnect(conn), do: GenServer.call(conn, :disconnect)

  @doc """
  Gets current connection state.
  """
  def get_state(conn), do: GenServer.call(conn, :get_state)

  @doc """
  Sends data through the WebSocket connection.
  """
  def send_data(conn, data), do: GenServer.call(conn, {:send_data, data})

  # GenServer callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    uri = Keyword.fetch!(opts, :uri)
    owner = Keyword.get(opts, :owner, self())

    state = %{
      uri: uri,
      conn_pid: nil,
      stream_ref: nil,
      connection_state: :disconnected,
      reconnect_attempt: 0,
      reconnect_timer: nil,
      conn_manager: ConnectionManager.init_connection_state(),
      owner: owner,
      owner_ref: Process.monitor(owner),
      opts: opts
    }

    if Keyword.get(opts, :auto_connect, true) do
      send(self(), :connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, state) do
    {:reply, :ok, do_connect(state)}
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    {:reply, :ok, do_disconnect(:manual, state)}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      connected: state.connection_state == :connected,
      connection_state: state.connection_state,
      uri: state.uri,
      reconnect_attempt: state.reconnect_attempt
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:send_data, data}, _from, %{connection_state: :connected} = state) do
    case do_send_data(state, data) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_data, _data}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_info(:connect, state) do
    {:noreply, do_connect(state)}
  end

  @impl true
  def handle_info(:reconnect, state) do
    {:noreply, do_connect(state)}
  end

  # Gun connection events
  @impl true
  def handle_info({:gun_up, conn_pid, _protocol}, %{conn_pid: conn_pid} = state) do
    Logger.debug("Gun connection established", uri: state.uri)
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_upgrade, conn_pid, stream_ref, ["websocket"], headers}, %{conn_pid: conn_pid} = state) do
    Logger.info("WebSocket upgraded successfully", uri: state.uri)

    conn_manager = ConnectionManager.add_connection(state.conn_manager, conn_pid, stream_ref, :websocket)

    state = %{
      state
      | stream_ref: stream_ref,
        connection_state: :connected,
        reconnect_attempt: 0,
        conn_manager: conn_manager
    }

    notify_owner(state, {:websocket_connected, %{uri: state.uri, headers: headers}})

    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_ws, conn_pid, stream_ref, frame}, %{conn_pid: conn_pid, stream_ref: stream_ref} = state) do
    notify_owner(state, {:websocket_frame, frame})
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_down, conn_pid, _protocol, reason, _}, %{conn_pid: conn_pid} = state) do
    Logger.warning("Connection lost", uri: state.uri, reason: inspect(reason))

    state = handle_connection_loss(state, reason)
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_error, conn_pid, reason}, %{conn_pid: conn_pid} = state) do
    Logger.error("Connection error", uri: state.uri, error: inspect(reason))

    state = handle_connection_loss(state, reason)
    {:noreply, state}
  end

  # Monitor owner process
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{owner_ref: ref} = state) do
    Logger.info("Owner process terminated, shutting down", reason: inspect(reason))
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message", message: inspect(msg))
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Terminating WebSocket connection", reason: inspect(reason))
    ConnectionManager.cleanup_all(state.conn_manager)
    :ok
  end

  # Private functions

  defp do_connect(state) do
    correlation_id = CorrelationId.generate()

    Logger.info("[#{correlation_id}] Connecting to WebSocket",
      uri: state.uri,
      attempt: state.reconnect_attempt + 1
    )

    state = %{state | connection_state: :connecting}
    notify_owner(state, {:websocket_connecting, %{uri: state.uri}})

    case connect_gun(state.uri, state.opts) do
      {:ok, conn_pid} ->
        {monitor_ref, conn_manager} = ConnectionManager.add_monitor(state.conn_manager, conn_pid, :gun_connection)

        state = %{state | conn_pid: conn_pid, conn_manager: conn_manager}

        # Now perform WebSocket upgrade
        case perform_ws_upgrade(conn_pid, state.uri, state.opts) do
          {:ok, _stream_ref} ->
            # Gun will send :gun_upgrade message when complete
            state

          {:error, reason} ->
            Logger.error("[#{correlation_id}] WebSocket upgrade failed", error: inspect(reason))
            handle_connection_failure(state, reason)
        end

      {:error, reason} ->
        Logger.error("[#{correlation_id}] Connection failed", error: inspect(reason))
        handle_connection_failure(state, reason)
    end
  end

  defp do_disconnect(reason, state) do
    Logger.info("Disconnecting WebSocket", uri: state.uri, reason: inspect(reason))

    # Cancel any pending reconnect
    state = cancel_reconnect_timer(state)

    # Close connection
    conn_manager = ConnectionManager.close_connection(state.conn_manager, :websocket)

    state = %{state | conn_pid: nil, stream_ref: nil, connection_state: :disconnected, conn_manager: conn_manager}

    notify_owner(state, {:websocket_disconnected, %{reason: reason}})

    state
  end

  defp do_send_data(%{conn_pid: conn_pid, stream_ref: stream_ref}, data) when is_binary(data) do
    :gun.ws_send(conn_pid, stream_ref, {:text, data})
  end

  defp do_send_data(%{conn_pid: conn_pid, stream_ref: stream_ref}, data) do
    :gun.ws_send(conn_pid, stream_ref, data)
  end

  defp connect_gun(uri, opts) do
    uri_map = URI.parse(uri)
    host = String.to_charlist(uri_map.host || "localhost")
    port = uri_map.port || if(uri_map.scheme == "wss", do: 443, else: 80)

    transport = if uri_map.scheme == "wss", do: :tls, else: :tcp

    gun_opts = %{
      transport: transport,
      protocols: [:http],
      # We handle retry ourselves
      retry: 0
    }

    # Add TLS options if using secure WebSocket
    gun_opts =
      if transport == :tls do
        Map.put(gun_opts, :tls_opts,
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: host
        )
      else
        gun_opts
      end

    :gun.open(host, port, gun_opts)
  end

  defp perform_ws_upgrade(conn_pid, uri, opts) do
    uri_map = URI.parse(uri)
    path = uri_map.path || "/"

    # Add query string if present
    path =
      if uri_map.query do
        "#{path}?#{uri_map.query}"
      else
        path
      end

    headers = Keyword.get(opts, :headers, [])

    stream_ref = :gun.ws_upgrade(conn_pid, path, headers)
    {:ok, stream_ref}
  end

  defp handle_connection_loss(state, reason) do
    state = do_disconnect({:connection_lost, reason}, state)

    if should_reconnect?(reason, state) do
      schedule_reconnect(state)
    else
      state
    end
  end

  defp handle_connection_failure(state, reason) do
    conn_manager = ConnectionManager.close_connection(state.conn_manager, :websocket)

    state = %{
      state
      | conn_pid: nil,
        stream_ref: nil,
        connection_state: :error,
        reconnect_attempt: state.reconnect_attempt + 1,
        conn_manager: conn_manager
    }

    notify_owner(state, {:websocket_error, %{reason: reason}})

    if should_reconnect?(reason, state) do
      schedule_reconnect(state)
    else
      state
    end
  end

  defp schedule_reconnect(state) do
    delay = calculate_reconnect_delay(state)

    Logger.info("Scheduling reconnect",
      uri: state.uri,
      delay_ms: delay,
      attempt: state.reconnect_attempt + 1
    )

    timer = Process.send_after(self(), :reconnect, delay)
    conn_manager = ConnectionManager.add_timer(state.conn_manager, timer, :reconnect)

    %{state | reconnect_timer: timer, connection_state: :reconnecting, conn_manager: conn_manager}
  end

  defp cancel_reconnect_timer(state) do
    if state.reconnect_timer do
      Process.cancel_timer(state.reconnect_timer)
      conn_manager = ConnectionManager.cancel_timer(state.conn_manager, :reconnect)
      %{state | reconnect_timer: nil, conn_manager: conn_manager}
    else
      state
    end
  end

  defp calculate_reconnect_delay(state) do
    base_delay = Keyword.get(state.opts, :reconnect_base_delay, @default_reconnect_base_delay)
    max_delay = Keyword.get(state.opts, :reconnect_max_delay, @default_reconnect_max_delay)
    factor = Keyword.get(state.opts, :reconnect_factor, @default_reconnect_factor)

    delay = base_delay * :math.pow(factor, state.reconnect_attempt)
    min(round(delay), max_delay)
  end

  defp should_reconnect?(:manual, _state), do: false
  defp should_reconnect?(_reason, _state), do: true

  defp notify_owner(state, message) do
    send(state.owner, {__MODULE__, self(), message})
  end
end
