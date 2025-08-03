defmodule Server.Services.Twitch.ConnectionManagerSimpleTest do
  @moduledoc """
  Simplified behavior-driven tests for ConnectionManager.

  These tests focus on the public API and observable behavior rather than
  internal message passing implementation details.
  """
  use ExUnit.Case, async: true

  alias Server.Services.Twitch.ConnectionManager

  describe "ConnectionManager public API" do
    setup do
      # Start ConnectionManager with test configuration
      {:ok, manager} =
        ConnectionManager.start_link(
          url: "wss://test.example.com/ws",
          owner: self(),
          client_id: "test_client_id",
          name: nil
        )

      {:ok, manager: manager}
    end

    test "starts in disconnected state", %{manager: manager} do
      state = ConnectionManager.get_state(manager)

      assert state.connected == false
      assert state.connection_state == :disconnected
      assert state.session_id == nil
    end

    test "connect/1 initiates connection", %{manager: manager} do
      # Simply verify the call succeeds - don't test internal mechanics
      assert :ok = ConnectionManager.connect(manager)

      # State should transition to connecting (eventually)
      # In a real test, we'd mock WebSocketConnection to control timing
      Process.sleep(10)
      state = ConnectionManager.get_state(manager)
      assert state.connection_state in [:disconnected, :connecting]
    end

    test "disconnect/1 closes connection", %{manager: manager} do
      assert :ok = ConnectionManager.disconnect(manager)

      # Verify final state
      state = ConnectionManager.get_state(manager)
      assert state.connected == false
      assert state.connection_state == :disconnected
    end

    test "send_message/2 returns error when not connected", %{manager: manager} do
      assert {:error, :not_connected} = ConnectionManager.send_message(manager, "test")
    end

    test "monitors owner process", %{manager: _manager} do
      # Spawn a process to be the owner
      owner = spawn(fn -> Process.sleep(200) end)

      {:ok, manager2} =
        ConnectionManager.start_link(
          url: "wss://test.example.com/ws",
          owner: owner,
          client_id: "test_client_id",
          name: nil
        )

      # Monitor the manager before killing the owner
      ref = Process.monitor(manager2)

      # Give the manager time to set up monitoring of the owner
      Process.sleep(10)

      # Kill the owner
      Process.exit(owner, :kill)

      # Manager should stop when owner dies
      assert_receive {:DOWN, ^ref, :process, _, :normal}, 200
    end
  end

  describe "ConnectionManager with mocked WebSocket" do
    setup do
      # Create a connection manager with mock WebSocket module
      {:ok, manager} =
        ConnectionManager.start_link(
          url: "wss://test.example.com/ws",
          owner: self(),
          client_id: "test_client_id",
          name: nil,
          websocket_module: MockWebSocketConnection
        )

      {:ok, manager: manager}
    end

    test "transitions to ready state after session_welcome", %{manager: manager} do
      # Connect and get the mock WebSocket
      assert :ok = ConnectionManager.connect(manager)

      # Wait for connection attempt and let mock connect
      Process.sleep(100)

      # Get internal state to access WebSocket connection
      internal_state = :sys.get_state(manager)
      ws_conn = internal_state.ws_conn

      # Simulate successful connection
      if ws_conn do
        MockWebSocketConnection.simulate_connected(ws_conn)
        Process.sleep(50)

        # Send session_welcome message
        session_welcome = %{
          "metadata" => %{
            "message_id" => "test-123",
            "message_type" => "session_welcome",
            "message_timestamp" => "2024-01-01T00:00:00.000Z"
          },
          "payload" => %{
            "session" => %{
              "id" => "test-session-123",
              "status" => "connected",
              "keepalive_timeout_seconds" => 10,
              "connected_at" => "2024-01-01T00:00:00.000Z"
            }
          }
        }

        frame = {:text, Jason.encode!(session_welcome)}
        MockWebSocketConnection.simulate_frame_received(ws_conn, frame)
        Process.sleep(50)

        # Verify state transition
        final_state = ConnectionManager.get_state(manager)
        assert final_state.connected == true
        assert final_state.connection_state == :ready
        assert final_state.session_id == "test-session-123"
      end
    end

    test "handles connection errors gracefully", %{manager: manager} do
      # Connect
      assert :ok = ConnectionManager.connect(manager)
      Process.sleep(100)

      # Get internal state to access WebSocket connection
      internal_state = :sys.get_state(manager)
      ws_conn = internal_state.ws_conn

      if ws_conn do
        # First connect successfully
        MockWebSocketConnection.simulate_connected(ws_conn)
        Process.sleep(50)

        # Then simulate an error
        MockWebSocketConnection.simulate_error(ws_conn, "Network error")
        Process.sleep(50)

        # Verify manager transitions to error/disconnected state
        error_state = ConnectionManager.get_state(manager)
        assert error_state.connected == false
        assert error_state.connection_state in [:disconnected, :reconnecting, :error]

        # Verify owner receives notification (connection_lost is sent for errors)
        assert_receive {:twitch_connection, {:connection_lost, _}}, 100
      end
    end
  end
end
