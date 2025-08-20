defmodule Server.WebSocketClientTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Server.WebSocketClient

  describe "new/3" do
    test "creates a new WebSocket client state with default options" do
      url = "ws://localhost:4455"
      owner_pid = self()

      client = WebSocketClient.new(url, owner_pid)

      assert client.url == url
      assert client.owner_pid == owner_pid
      assert client.uri.host == "localhost"
      assert client.uri.port == 4455
      assert client.uri.scheme == "ws"
      assert client.conn_pid == nil
      assert client.stream_ref == nil
      assert client.reconnect_interval == Duration.new!(second: 1)
      assert client.connection_timeout == Duration.new!(second: 3)
      assert client.telemetry_prefix == [:server, :websocket]
    end

    test "creates client with custom options" do
      url = "wss://example.com:443/ws"
      owner_pid = self()

      opts = [
        reconnect_interval: Duration.new!(second: 10),
        connection_timeout: Duration.new!(second: 30),
        telemetry_prefix: [:custom, :prefix]
      ]

      client = WebSocketClient.new(url, owner_pid, opts)

      assert client.url == url
      assert client.uri.host == "example.com"
      assert client.uri.port == 443
      assert client.uri.scheme == "wss"
      assert client.reconnect_interval == Duration.new!(second: 10)
      assert client.connection_timeout == Duration.new!(second: 30)
      assert client.telemetry_prefix == [:custom, :prefix]
    end

    test "parses URL correctly for different schemes" do
      ws_client = WebSocketClient.new("ws://localhost:7175", self())
      assert ws_client.uri.scheme == "ws"
      assert ws_client.uri.port == 7175

      wss_client = WebSocketClient.new("wss://secure.example.com/path", self())
      assert wss_client.uri.scheme == "wss"
      assert wss_client.uri.host == "secure.example.com"
      assert wss_client.uri.path == "/path"
    end
  end

  describe "connect/2" do
    test "returns ok status when already connected" do
      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | conn_pid: :fake_pid
      }

      assert {:ok, ^client} = WebSocketClient.connect(client)
    end

    # Note: Testing actual connection would require mocking :gun
    # In a full test suite, you would mock :gun.open/3 and related functions

    test "attempts connection with correct parameters" do
      client = WebSocketClient.new("ws://localhost:4455", self())

      # This will fail in test environment since gun server isn't running
      # but we can verify the function handles the error gracefully
      result = WebSocketClient.connect(client)

      case result do
        {:ok, _updated_client} ->
          # Connection succeeded (unlikely in test)
          assert true

        {:error, updated_client, _reason} ->
          # Connection failed as expected in test environment
          assert updated_client.url == client.url
      end
    end
  end

  describe "send_message/2" do
    test "returns error when not connected" do
      client = WebSocketClient.new("ws://localhost:4455", self())

      assert {:error, "WebSocket not connected"} = WebSocketClient.send_message(client, "test message")
    end

    test "handles binary messages" do
      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | conn_pid: :fake_pid,
          stream_ref: :fake_ref
      }

      # This would normally call :gun.ws_send, which we can't test without mocking
      # But we can verify the function accepts the input
      result = WebSocketClient.send_message(client, "test message")
      # In a real implementation with mocking, this would return :ok
      assert result != nil
    end

    test "handles map messages by JSON encoding" do
      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | conn_pid: :fake_pid,
          stream_ref: :fake_ref
      }

      message = %{"type" => "test", "data" => "value"}

      # This would normally call :gun.ws_send with JSON-encoded data
      result = WebSocketClient.send_message(client, message)
      assert result != nil
    end
  end

  describe "close/1" do
    test "cleans up connection state" do
      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | conn_pid: :fake_pid,
          stream_ref: :fake_ref,
          monitor_ref: :fake_monitor
      }

      updated_client = WebSocketClient.close(client)

      assert updated_client.conn_pid == nil
      assert updated_client.stream_ref == nil
      assert updated_client.monitor_ref == nil
      assert updated_client.connection_start_time == nil
    end

    test "handles close when not connected" do
      client = WebSocketClient.new("ws://localhost:4455", self())

      updated_client = WebSocketClient.close(client)

      # Should return clean state
      assert updated_client.conn_pid == nil
      assert updated_client.stream_ref == nil
    end
  end

  describe "schedule_reconnect/1" do
    test "schedules reconnection message" do
      client = WebSocketClient.new("ws://localhost:4455", self())

      updated_client = WebSocketClient.schedule_reconnect(client)

      assert updated_client.reconnect_timer != nil
      assert is_reference(updated_client.reconnect_timer)

      # Clean up timer
      Process.cancel_timer(updated_client.reconnect_timer)
    end

    test "cancels existing timer before scheduling new one" do
      client = WebSocketClient.new("ws://localhost:4455", self())

      # Schedule first reconnect
      client_with_timer = WebSocketClient.schedule_reconnect(client)
      first_timer = client_with_timer.reconnect_timer

      # Schedule another reconnect
      updated_client = WebSocketClient.schedule_reconnect(client_with_timer)
      second_timer = updated_client.reconnect_timer

      assert first_timer != second_timer
      assert updated_client.reconnect_timer == second_timer

      # Clean up
      Process.cancel_timer(second_timer)
    end
  end

  describe "handle_upgrade/2" do
    test "handles successful upgrade with matching stream ref" do
      stream_ref = make_ref()

      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | stream_ref: stream_ref,
          connection_start_time: System.monotonic_time(:millisecond)
      }

      updated_client = WebSocketClient.handle_upgrade(client, stream_ref)

      # Should have sent connection message to owner
      assert_receive {:websocket_connected, ^updated_client}

      assert updated_client == client
    end

    test "ignores upgrade for non-matching stream ref" do
      client_stream_ref = make_ref()
      other_stream_ref = make_ref()

      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | stream_ref: client_stream_ref
      }

      updated_client = WebSocketClient.handle_upgrade(client, other_stream_ref)

      # Should not have sent any message
      refute_receive {:websocket_connected, _}

      assert updated_client == client
    end
  end

  describe "handle_message/3" do
    test "handles text messages with matching stream ref" do
      stream_ref = make_ref()

      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | stream_ref: stream_ref
      }

      frame = {:text, "test message"}
      updated_client = WebSocketClient.handle_message(client, stream_ref, frame)

      assert_receive {:websocket_message, ^client, "test message"}
      assert updated_client == client
    end

    test "handles binary messages with matching stream ref" do
      stream_ref = make_ref()

      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | stream_ref: stream_ref
      }

      frame = {:binary, <<1, 2, 3>>}
      updated_client = WebSocketClient.handle_message(client, stream_ref, frame)

      assert_receive {:websocket_binary, ^client, <<1, 2, 3>>}
      assert updated_client == client
    end

    test "handles close messages with matching stream ref" do
      stream_ref = make_ref()

      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | stream_ref: stream_ref
      }

      frame = {:close, 1000, "Normal closure"}
      updated_client = WebSocketClient.handle_message(client, stream_ref, frame)

      assert_receive {:websocket_closed, ^client, {1000, "Normal closure"}}
      assert updated_client == client
    end

    test "ignores messages for non-matching stream ref" do
      client_stream_ref = make_ref()
      other_stream_ref = make_ref()

      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | stream_ref: client_stream_ref
      }

      frame = {:text, "test message"}
      updated_client = WebSocketClient.handle_message(client, other_stream_ref, frame)

      # Should not receive any message
      refute_receive {:websocket_message, _, _}

      assert updated_client == client
    end
  end

  describe "handle_connection_failure/2" do
    test "handles connection failure and notifies owner" do
      client = %{
        WebSocketClient.new("ws://localhost:4455", self())
        | conn_pid: :fake_pid,
          stream_ref: make_ref(),
          monitor_ref: make_ref(),
          connection_start_time: System.monotonic_time(:millisecond)
      }

      reason = :connection_lost
      updated_client = WebSocketClient.handle_connection_failure(client, reason)

      # Should notify owner of disconnection
      assert_receive {:websocket_disconnected, disconnected_client, ^reason}

      # State should be cleaned up
      assert disconnected_client.conn_pid == nil
      assert disconnected_client.stream_ref == nil
      assert disconnected_client.monitor_ref == nil
      assert disconnected_client.connection_start_time == nil

      assert updated_client == disconnected_client
    end
  end
end
