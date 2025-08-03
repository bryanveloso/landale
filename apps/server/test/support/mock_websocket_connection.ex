defmodule MockWebSocketConnection do
  @moduledoc """
  Mock WebSocket connection for testing ConnectionManager behavior.

  This mock allows tests to control WebSocket events and verify
  ConnectionManager's response without actual network connections.
  """

  use GenServer

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def send_frame(conn, frame) do
    GenServer.call(conn, {:send_frame, frame})
  end

  def disconnect(conn) do
    GenServer.call(conn, :disconnect)
  end

  # Test control API

  def simulate_connected(mock) do
    GenServer.cast(mock, :simulate_connected)
  end

  def simulate_disconnected(mock, reason \\ :normal) do
    GenServer.cast(mock, {:simulate_disconnected, reason})
  end

  def simulate_frame_received(mock, frame) do
    GenServer.cast(mock, {:simulate_frame, frame})
  end

  def simulate_error(mock, error) do
    GenServer.cast(mock, {:simulate_error, error})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      owner: Keyword.get(opts, :owner),
      connected: false,
      frames_sent: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_frame, frame}, _from, state) do
    if state.connected do
      {:reply, :ok, %{state | frames_sent: [frame | state.frames_sent]}}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    if state.owner, do: send(state.owner, {:websocket_disconnected, self(), :normal})
    {:reply, :ok, %{state | connected: false}}
  end

  @impl true
  def handle_cast(:simulate_connected, state) do
    if state.owner do
      # Send in the format ConnectionManager expects
      send(state.owner, {Server.WebSocketConnection, self(), {:websocket_connected, %{uri: "test", headers: []}}})
    end

    {:noreply, %{state | connected: true}}
  end

  @impl true
  def handle_cast({:simulate_disconnected, reason}, state) do
    if state.owner do
      send(state.owner, {Server.WebSocketConnection, self(), {:websocket_disconnected, %{reason: reason}}})
    end

    {:noreply, %{state | connected: false}}
  end

  @impl true
  def handle_cast({:simulate_frame, frame}, state) do
    if state.owner do
      send(state.owner, {Server.WebSocketConnection, self(), {:websocket_frame, frame}})
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:simulate_error, error}, state) do
    if state.owner do
      send(state.owner, {Server.WebSocketConnection, self(), {:websocket_error, %{reason: error}}})
    end

    {:noreply, state}
  end
end
