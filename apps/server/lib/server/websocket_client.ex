defmodule Server.WebSocketClient do
  @moduledoc """
  Shared WebSocket client behavior using Gun HTTP client.

  Provides common WebSocket connection management patterns used by both
  OBS and Twitch services, including connection lifecycle, error handling,
  and telemetry integration.

  ## Usage

      defmodule MyService do
        use GenServer
        alias Server.WebSocketClient

        # In your GenServer
        def init(_opts) do
          state = %{
            ws_client: WebSocketClient.new("ws://localhost:4455", self()),
            # ... other state
          }
          {:ok, state}
        end

        def handle_info({:websocket_connected, client}, state) do
          # Handle successful connection
          {:noreply, %{state | ws_client: client}}
        end

        def handle_info({:websocket_disconnected, client, reason}, state) do
          # Handle disconnection
          {:noreply, %{state | ws_client: client}}
        end

        def handle_info({:websocket_message, client, message}, state) do
          # Handle incoming messages
          {:noreply, %{state | ws_client: client}}
        end
      end
  """

  require Logger

  alias Server.Logging

  @type client_state :: %{
          url: binary(),
          uri: URI.t(),
          owner_pid: pid(),
          conn_pid: pid() | nil,
          stream_ref: reference() | nil,
          monitor_ref: reference() | nil,
          connection_start_time: integer() | nil,
          reconnect_timer: reference() | nil,
          reconnect_interval: Duration.t(),
          connection_timeout: Duration.t(),
          telemetry_prefix: [atom()],
          connection_manager: Server.ConnectionManager.connection_state()
        }

  # Network configuration is now handled by Server.NetworkConfig

  @doc """
  Creates a new WebSocket client state.

  ## Parameters
  - `url` - WebSocket URL to connect to
  - `owner_pid` - Process that will receive WebSocket events
  - `opts` - Optional configuration
    - `:reconnect_interval` - Time between reconnection attempts (default: 5 seconds)
    - `:connection_timeout` - Connection timeout (default: 10 seconds)
    - `:telemetry_prefix` - Telemetry event prefix (default: [:server, :websocket])

  ## Returns
  - WebSocket client state map
  """
  @spec new(binary(), pid(), keyword()) :: client_state()
  def new(url, owner_pid, opts \\ []) do
    uri = URI.parse(url)

    %{
      url: url,
      uri: uri,
      owner_pid: owner_pid,
      conn_pid: nil,
      stream_ref: nil,
      monitor_ref: nil,
      connection_start_time: nil,
      reconnect_timer: nil,
      reconnect_interval: Keyword.get(opts, :reconnect_interval, Server.NetworkConfig.reconnect_interval()),
      connection_timeout: Keyword.get(opts, :connection_timeout, Server.NetworkConfig.connection_timeout()),
      telemetry_prefix: Keyword.get(opts, :telemetry_prefix, [:server, :websocket]),
      connection_manager: Server.ConnectionManager.init_connection_state()
    }
  end

  @doc """
  Initiates a WebSocket connection.

  ## Parameters
  - `client` - WebSocket client state
  - `opts` - Optional connection options
    - `:headers` - Additional headers for the WebSocket upgrade
    - `:protocols` - WebSocket sub-protocols

  ## Returns
  - `{:ok, updated_client}` - Connection initiated successfully
  - `{:error, updated_client, reason}` - Connection failed
  """
  @spec connect(client_state(), keyword()) :: {:ok, client_state()} | {:error, client_state(), term()}
  def connect(client, opts \\ []) do
    if client.conn_pid do
      Logger.warning("Connection already established", url: client.url)
      {:ok, client}
    else
      perform_connection(client, opts)
    end
  end

  defp perform_connection(client, opts) do
    Logger.info("Connection initiated", url: client.url)

    # Emit telemetry for connection attempt
    emit_telemetry(client, [:connection, :attempt], %{})

    host = to_charlist(client.uri.host)
    port = client.uri.port || default_port(client.uri.scheme)
    path = client.uri.path || "/"

    connection_start_time = System.monotonic_time(:millisecond)
    client = %{client | connection_start_time: connection_start_time}

    case :gun.open(host, port, gun_opts(client.uri.scheme)) do
      {:ok, conn_pid} ->
        establish_websocket_connection(client, conn_pid, path, opts)

      {:error, reason} ->
        Logging.log_error("Connection failed during open", reason, url: client.url)

        emit_connection_failure(client, reason)
        {:error, client, reason}
    end
  end

  defp establish_websocket_connection(client, conn_pid, path, opts) do
    # Use ConnectionManager to track monitor and connection
    {monitor_ref, updated_connection_manager} =
      Server.ConnectionManager.add_monitor(
        client.connection_manager,
        conn_pid,
        :websocket_connection
      )

    websocket_config = Server.NetworkConfig.websocket_config()
    timeout_ms = System.convert_time_unit(websocket_config.timeout.second, :second, :millisecond)

    case :gun.await_up(conn_pid, timeout_ms) do
      {:ok, _protocol} ->
        complete_websocket_setup(client, conn_pid, monitor_ref, updated_connection_manager, path, opts)

      {:error, reason} ->
        Logging.log_error("Connection failed during await_up", reason, url: client.url)

        :gun.close(conn_pid)
        emit_connection_failure(client, reason)

        {:error, client, reason}
    end
  end

  defp complete_websocket_setup(client, conn_pid, monitor_ref, updated_connection_manager, path, opts) do
    headers = Keyword.get(opts, :headers, [])
    protocols = Keyword.get(opts, :protocols, [])

    ws_opts = if protocols != [], do: %{protocols: protocols}, else: %{}

    Logger.debug("WebSocket upgrade request details",
      url: client.url,
      host: client.uri.host,
      port: client.uri.port,
      path: path,
      headers: inspect(headers),
      ws_opts: inspect(ws_opts),
      headers_count: length(headers)
    )

    stream_ref = :gun.ws_upgrade(conn_pid, path, headers, ws_opts)

    Logger.debug("WebSocket upgrade initiated",
      url: client.url,
      conn_pid: inspect(conn_pid),
      stream_ref: inspect(stream_ref)
    )

    # Track connection and update client state
    final_connection_manager =
      Server.ConnectionManager.add_connection(
        updated_connection_manager,
        conn_pid,
        stream_ref,
        :websocket
      )

    updated_client = %{
      client
      | conn_pid: conn_pid,
        stream_ref: stream_ref,
        monitor_ref: monitor_ref,
        connection_manager: final_connection_manager
    }

    {:ok, updated_client}
  end

  @doc """
  Sends a message over the WebSocket connection.

  ## Parameters
  - `client` - WebSocket client state
  - `message` - Message to send (binary or map that will be JSON encoded)

  ## Returns
  - `:ok` - Message sent successfully
  - `{:error, reason}` - Send failed
  """
  @spec send_message(client_state(), binary() | map()) :: :ok | {:error, term()}
  def send_message(client, message) do
    if client.conn_pid && client.stream_ref do
      frame =
        case message do
          binary when is_binary(binary) -> {:text, binary}
          data -> {:text, JSON.encode!(data)}
        end

      :gun.ws_send(client.conn_pid, client.stream_ref, frame)
    else
      {:error, "WebSocket not connected"}
    end
  end

  @doc """
  Closes the WebSocket connection.

  ## Parameters
  - `client` - WebSocket client state

  ## Returns
  - Updated client state with connection cleared
  """
  @spec close(client_state()) :: client_state()
  def close(client) do
    # Cancel reconnect timer if active
    client = cancel_reconnect_timer(client)

    # Use ConnectionManager for proper cleanup
    Server.ConnectionManager.cleanup_all(client.connection_manager)

    %{client | conn_pid: nil, stream_ref: nil, monitor_ref: nil, connection_start_time: nil}
  end

  @doc """
  Schedules a reconnection attempt.

  ## Parameters
  - `client` - WebSocket client state

  ## Returns
  - Updated client state with reconnect timer
  """
  @spec schedule_reconnect(client_state()) :: client_state()
  def schedule_reconnect(client) do
    client = cancel_reconnect_timer(client)

    interval_ms = System.convert_time_unit(client.reconnect_interval.second, :second, :millisecond)

    Logger.info("Reconnection scheduled",
      url: client.url,
      interval: interval_ms
    )

    timer = Process.send_after(client.owner_pid, {:websocket_reconnect, client}, interval_ms)

    # Track timer with ConnectionManager
    updated_connection_manager =
      Server.ConnectionManager.add_timer(
        client.connection_manager,
        timer,
        :reconnect
      )

    %{client | reconnect_timer: timer, connection_manager: updated_connection_manager}
  end

  @doc """
  Handles Gun WebSocket upgrade success.

  Should be called from the owning process when receiving `:gun_upgrade` messages.
  """
  @spec handle_upgrade(client_state(), reference()) :: client_state()
  def handle_upgrade(client, stream_ref) do
    if stream_ref == client.stream_ref do
      Logger.info("Connection established", url: client.url)

      # Emit telemetry for successful connection
      if client.connection_start_time do
        duration = System.monotonic_time(:millisecond) - client.connection_start_time
        emit_telemetry(client, [:connection, :success], %{duration: duration})
      end

      # Notify owner process
      send(client.owner_pid, {:websocket_connected, client})

      client
    else
      Logger.warning("Upgrade for unknown stream",
        error: "stream mismatch",
        url: client.url,
        expected: client.stream_ref,
        received: stream_ref
      )

      client
    end
  end

  @doc """
  Handles incoming WebSocket messages.

  Should be called from the owning process when receiving `:gun_ws` messages.
  """
  @spec handle_message(client_state(), reference(), term()) :: client_state()
  def handle_message(client, stream_ref, frame) do
    if stream_ref == client.stream_ref do
      case frame do
        {:text, message} ->
          send(client.owner_pid, {:websocket_message, client, message})

        {:binary, data} ->
          send(client.owner_pid, {:websocket_binary, client, data})

        {:close, code, reason} ->
          Logger.info("Connection closed by remote",
            url: client.url,
            code: code,
            reason: reason
          )

          send(client.owner_pid, {:websocket_closed, client, {code, reason}})

        other ->
          Logger.debug("Frame unhandled",
            url: client.url,
            frame: inspect(other)
          )
      end

      client
    else
      client
    end
  end

  @doc """
  Handles Gun connection failures.

  Should be called from the owning process when receiving `:gun_down` or `:gun_error` messages.
  """
  @spec handle_connection_failure(client_state(), term()) :: client_state()
  def handle_connection_failure(client, reason) do
    Logger.warning("Connection lost", error: reason, url: client.url)

    # Emit telemetry for connection failure
    if client.connection_start_time do
      duration = System.monotonic_time(:millisecond) - client.connection_start_time
      emit_telemetry(client, [:connection, :failure], %{duration: duration, reason: inspect(reason)})
    end

    # Clean up connection state
    client = %{client | conn_pid: nil, stream_ref: nil, monitor_ref: nil, connection_start_time: nil}

    # Notify owner process
    send(client.owner_pid, {:websocket_disconnected, client, reason})

    client
  end

  # Private helper functions

  defp default_port("ws"), do: 80
  defp default_port("wss"), do: 443
  defp default_port(_), do: 80

  defp gun_opts("wss"), do: %{transport: :tls, protocols: [:http]}
  defp gun_opts(_), do: %{protocols: [:http]}

  defp cancel_reconnect_timer(client) do
    # Use ConnectionManager to cancel timer properly
    updated_connection_manager =
      Server.ConnectionManager.cancel_timer(
        client.connection_manager,
        :reconnect
      )

    %{client | reconnect_timer: nil, connection_manager: updated_connection_manager}
  end

  defp emit_connection_failure(client, reason) do
    if client.connection_start_time do
      duration = System.monotonic_time(:millisecond) - client.connection_start_time
      emit_telemetry(client, [:connection, :failure], %{duration: duration, reason: inspect(reason)})
    end
  end

  defp emit_telemetry(client, event_suffix, measurements, metadata \\ %{}) do
    event = client.telemetry_prefix ++ event_suffix
    :telemetry.execute(event, measurements, Map.put(metadata, :url, client.url))
  end
end
