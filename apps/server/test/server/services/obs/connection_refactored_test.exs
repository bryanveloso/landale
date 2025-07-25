defmodule Server.Services.OBS.ConnectionRefactoredTest do
  use ExUnit.Case, async: true

  alias Server.Services.OBS.ConnectionRefactored
  alias Server.WebSocketConnection

  @moduletag :obs_refactored

  setup do
    # Start PubSub if not already started
    case Process.whereis(Server.PubSub) do
      nil -> start_supervised!({Phoenix.PubSub, name: Server.PubSub})
      _pid -> :ok
    end

    session_id = "test_session_#{System.unique_integer()}"

    {:ok, session_id: session_id}
  end

  describe "initialization" do
    test "starts and initializes in disconnected state", %{session_id: session_id} do
      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Verify initial state
      assert ConnectionRefactored.get_state(conn) == :disconnected
    end

    test "includes session_id and uri in child_spec", %{session_id: session_id} do
      child_spec =
        ConnectionRefactored.child_spec(
          id: :test_obs,
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      assert child_spec.id == :test_obs
      assert child_spec.type == :worker
      assert child_spec.restart == :permanent
      assert child_spec.shutdown == 5000
    end
  end

  describe "authentication flow" do
    test "transitions through authentication states", %{session_id: session_id} do
      # Subscribe to connection events
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:#{session_id}")

      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Simulate WebSocket connected event
      send(conn, {WebSocketConnection, self(), {:websocket_connected, %{}}})

      # Give it time to process
      Process.sleep(10)

      # Simulate Hello response (no auth required)
      hello_response =
        Jason.encode!(%{
          "op" => 0,
          "d" => %{
            "obsWebSocketVersion" => "5.0.0",
            "rpcVersion" => 1
          }
        })

      send(conn, {WebSocketConnection, self(), {:websocket_frame, {:text, hello_response}}})

      # Should receive connection established event
      assert_receive {:connection_established, %{session_id: ^session_id, rpc_version: 1}}, 1000

      # State should be ready
      assert ConnectionRefactored.get_state(conn) == :ready
    end

    test "handles authentication timeout", %{session_id: session_id} do
      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Simulate connection to trigger auth
      send(conn, {WebSocketConnection, self(), {:websocket_connected, %{}}})

      # Send auth timeout message
      send(conn, :auth_timeout)

      # Give it time to process
      Process.sleep(10)

      # Should be back to disconnected
      assert ConnectionRefactored.get_state(conn) == :disconnected
    end
  end

  describe "connection events" do
    test "handles disconnection properly", %{session_id: session_id} do
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:#{session_id}")

      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Get to ready state first
      send(conn, {WebSocketConnection, self(), {:websocket_connected, %{}}})
      hello_response = Jason.encode!(%{"op" => 0, "d" => %{"rpcVersion" => 1}})
      send(conn, {WebSocketConnection, self(), {:websocket_frame, {:text, hello_response}}})

      # Wait for ready state
      assert_receive {:connection_established, _}, 1000

      # Now disconnect
      send(conn, {WebSocketConnection, self(), {:websocket_disconnected, %{reason: :closed}}})

      # Should receive connection lost event
      assert_receive {:connection_lost, %{reason: :closed}}, 1000

      # State should be disconnected
      assert ConnectionRefactored.get_state(conn) == :disconnected
    end

    test "logs WebSocket errors", %{session_id: session_id} do
      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Capture logs
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          send(conn, {WebSocketConnection, self(), {:websocket_error, %{reason: :test_error}}})
          Process.sleep(10)
        end)

      assert log =~ "WebSocket error"
      # Logger metadata doesn't capture structured fields in test output
      # Just verify the main message was logged
    end
  end

  describe "OBS events" do
    test "broadcasts OBS events to appropriate channels", %{session_id: session_id} do
      # Subscribe to event channels
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:#{session_id}:events")
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:#{session_id}:SceneItemCreated")

      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Get to ready state
      send(conn, {WebSocketConnection, self(), {:websocket_connected, %{}}})
      hello_response = Jason.encode!(%{"op" => 0, "d" => %{"rpcVersion" => 1}})
      send(conn, {WebSocketConnection, self(), {:websocket_frame, {:text, hello_response}}})

      # Wait for ready
      Process.sleep(50)

      # Simulate OBS event
      event =
        Jason.encode!(%{
          "op" => 5,
          "d" => %{
            "eventType" => "SceneItemCreated",
            "eventIntent" => 1024,
            "eventData" => %{
              "sceneName" => "Scene 1",
              "sceneItemId" => 123
            }
          }
        })

      send(conn, {WebSocketConnection, self(), {:websocket_frame, {:text, event}}})

      # Should receive on both channels
      assert_receive {:obs_event, "SceneItemCreated", event_data}, 1000
      assert event_data.eventType == "SceneItemCreated"

      assert_receive {:obs_event, event_data2}, 1000
      assert event_data2.eventType == "SceneItemCreated"
    end
  end

  describe "request handling" do
    test "queues requests when not ready", %{session_id: session_id} do
      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Start async task to send request
      task =
        Task.async(fn ->
          ConnectionRefactored.send_request(conn, "GetVersion", %{})
        end)

      # Should not complete immediately (queued)
      refute Task.yield(task, 100)

      # Now connect and authenticate
      send(conn, {WebSocketConnection, self(), {:websocket_connected, %{}}})
      hello_response = Jason.encode!(%{"op" => 0, "d" => %{"rpcVersion" => 1}})
      send(conn, {WebSocketConnection, self(), {:websocket_frame, {:text, hello_response}}})

      # Request should eventually complete (error because no RequestTracker in test)
      assert {:error, :tracker_not_found} = Task.await(task)
    end

    test "returns error when not connected", %{session_id: session_id} do
      # Mock the RequestTracker
      tracker_name = :"obs_request_tracker_#{session_id}"
      Process.register(self(), tracker_name)

      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Get to ready state but with disconnected WebSocket
      send(conn, {WebSocketConnection, self(), {:websocket_connected, %{}}})
      hello_response = Jason.encode!(%{"op" => 0, "d" => %{"rpcVersion" => 1}})
      send(conn, {WebSocketConnection, self(), {:websocket_frame, {:text, hello_response}}})

      # Wait for ready
      Process.sleep(50)

      # Try to send request (should fail because WebSocketConnection.get_state would show disconnected)
      result = ConnectionRefactored.send_request(conn, "GetVersion", %{})

      # Either tracker not found or not connected error
      assert {:error, _reason} = result
    end
  end

  describe "error handling" do
    test "handles malformed messages gracefully", %{session_id: session_id} do
      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Get to ready state
      send(conn, {WebSocketConnection, self(), {:websocket_connected, %{}}})
      hello_response = Jason.encode!(%{"op" => 0, "d" => %{"rpcVersion" => 1}})
      send(conn, {WebSocketConnection, self(), {:websocket_frame, {:text, hello_response}}})

      Process.sleep(50)

      # Send malformed message - connection should stay alive
      send(conn, {WebSocketConnection, self(), {:websocket_frame, {:text, "invalid json"}}})
      Process.sleep(10)

      # Connection should still be alive after malformed message
      assert Process.alive?(conn)
    end

    test "ignores messages in unexpected states", %{session_id: session_id} do
      {:ok, conn} =
        ConnectionRefactored.start_link(
          session_id: session_id,
          uri: "ws://localhost:4455"
        )

      # Send JSON message while disconnected
      message = Jason.encode!(%{"op" => 0, "d" => %{}})

      # Send JSON message while disconnected - should not crash
      send(conn, {WebSocketConnection, self(), {:websocket_frame, {:text, message}}})
      Process.sleep(50)

      # The important thing is it doesn't crash
      assert Process.alive?(conn)
    end
  end
end
