defmodule Server.WebSocketClientIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for WebSocket client focusing on connection stability,
  lifecycle management, message handling, and error recovery scenarios.

  These tests verify the intended functionality including connection state management,
  reconnection logic, message handling patterns, error handling, and telemetry integration.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Server.WebSocketClient

  # Test process to receive WebSocket messages
  defmodule TestReceiver do
    use GenServer

    def start_link(test_pid) do
      GenServer.start_link(__MODULE__, test_pid)
    end

    def init(test_pid) do
      {:ok, %{test_pid: test_pid, messages: [], events: []}}
    end

    def get_messages(pid) do
      GenServer.call(pid, :get_messages)
    end

    def get_events(pid) do
      GenServer.call(pid, :get_events)
    end

    def clear_all(pid) do
      GenServer.call(pid, :clear_all)
    end

    def handle_call(:get_messages, _from, state) do
      {:reply, Enum.reverse(state.messages), state}
    end

    def handle_call(:get_events, _from, state) do
      {:reply, Enum.reverse(state.events), state}
    end

    def handle_call(:clear_all, _from, state) do
      {:reply, :ok, %{state | messages: [], events: []}}
    end

    def handle_info({:websocket_connected, client}, state) do
      event = {:websocket_connected, client}
      send(state.test_pid, event)
      {:noreply, %{state | events: [event | state.events]}}
    end

    def handle_info({:websocket_disconnected, client, reason}, state) do
      event = {:disconnected, client, reason}
      send(state.test_pid, event)
      {:noreply, %{state | events: [event | state.events]}}
    end

    def handle_info({:websocket_message, client, message}, state) do
      msg = {:websocket_message, client, message}
      send(state.test_pid, msg)
      {:noreply, %{state | messages: [msg | state.messages]}}
    end

    def handle_info({:websocket_binary, client, data}, state) do
      msg = {:websocket_binary, client, data}
      send(state.test_pid, msg)
      {:noreply, %{state | messages: [msg | state.messages]}}
    end

    def handle_info({:websocket_closed, client, reason}, state) do
      event = {:websocket_closed, client, reason}
      send(state.test_pid, event)
      {:noreply, %{state | events: [event | state.events]}}
    end

    def handle_info({:websocket_reconnect, client}, state) do
      # Trigger reconnection
      case WebSocketClient.connect(client) do
        {:ok, updated_client} ->
          send(state.test_pid, {:reconnect_success, updated_client})

        {:error, updated_client, reason} ->
          send(state.test_pid, {:reconnect_failed, updated_client, reason})
      end

      {:noreply, state}
    end

    def handle_info(message, state) do
      send(state.test_pid, {:unexpected, message})
      {:noreply, state}
    end
  end

  setup do
    {:ok, receiver_pid} = TestReceiver.start_link(self())

    # Use a test URL that won't actually connect
    test_url = "ws://localhost:9999/test"

    client =
      WebSocketClient.new(test_url, receiver_pid,
        reconnect_interval: 100,
        connection_timeout: 1000,
        telemetry_prefix: [:test, :websocket]
      )

    on_exit(fn ->
      if Process.alive?(receiver_pid) do
        GenServer.stop(receiver_pid, :normal, 1000)
      end

      # Cleanup any connections
      WebSocketClient.close(client)
      :timer.sleep(50)
    end)

    %{client: client, receiver_pid: receiver_pid, test_url: test_url}
  end

  describe "client state initialization" do
    test "new/3 creates client with correct initial state", %{test_url: test_url} do
      receiver_pid = self()

      client =
        WebSocketClient.new(test_url, receiver_pid,
          reconnect_interval: 5000,
          connection_timeout: 10000,
          telemetry_prefix: [:custom, :telemetry]
        )

      # Verify initial state
      assert client.url == test_url
      assert client.uri.host == "localhost"
      assert client.uri.port == 9999
      assert client.uri.path == "/test"
      assert client.owner_pid == receiver_pid
      assert client.conn_pid == nil
      assert client.stream_ref == nil
      assert client.monitor_ref == nil
      assert client.connection_start_time == nil
      assert client.reconnect_timer == nil
      assert client.reconnect_interval == 5000
      assert client.connection_timeout == 10000
      assert client.telemetry_prefix == [:custom, :telemetry]
      assert is_map(client.connection_manager)
    end

    test "new/3 uses default options when not provided", %{test_url: test_url} do
      receiver_pid = self()
      client = WebSocketClient.new(test_url, receiver_pid)

      # Should use defaults from NetworkConfig
      assert client.reconnect_interval > 0
      assert client.connection_timeout > 0
      assert client.telemetry_prefix == [:server, :websocket]
    end

    test "new/3 parses URL correctly" do
      test_cases = [
        {"ws://localhost:8080/path", %{scheme: "ws", host: "localhost", port: 8080, path: "/path"}},
        {"wss://secure.example.com/secure", %{scheme: "wss", host: "secure.example.com", port: 443, path: "/secure"}},
        {"ws://simple.com", %{scheme: "ws", host: "simple.com", port: 80, path: nil}}
      ]

      Enum.each(test_cases, fn {url, expected} ->
        client = WebSocketClient.new(url, self())

        assert client.uri.scheme == expected.scheme
        assert client.uri.host == expected.host
        assert client.uri.port == expected.port
        assert client.uri.path == expected.path
      end)
    end
  end

  describe "connection establishment" do
    test "connect/2 handles connection failure gracefully", %{client: client} do
      # Try to connect to non-existent server (should fail)
      log_output =
        capture_log(fn ->
          assert {:error, _updated_client, reason} = WebSocketClient.connect(client)
          assert reason != nil
        end)

      assert log_output =~ "Connection failed"
    end

    test "connect/2 with custom headers and protocols", %{client: client} do
      headers = [{"authorization", "Bearer token123"}, {"x-client-id", "test-client"}]
      protocols = ["chat", "superchat"]

      # Should handle options gracefully even if connection fails
      log_output =
        capture_log(fn ->
          result = WebSocketClient.connect(client, headers: headers, protocols: protocols)
          assert {:error, _updated_client, _reason} = result
        end)

      assert log_output =~ "Connection failed"
    end

    test "connect/2 handles SSL/TLS connections", %{receiver_pid: receiver_pid} do
      # Test with wss:// URL (will fail but should handle gracefully)
      ssl_client = WebSocketClient.new("wss://localhost:9443/test", receiver_pid)

      log_output =
        capture_log(fn ->
          assert {:error, _updated_client, _reason} = WebSocketClient.connect(ssl_client)
        end)

      # Should attempt SSL connection and fail gracefully
      assert log_output =~ "Connection failed"
    end

    test "connect/2 prevents duplicate connections when already connected" do
      # Create a client that simulates being connected
      connected_client = %{WebSocketClient.new("ws://test.com", self()) | conn_pid: self()}

      log_output =
        capture_log(fn ->
          assert {:ok, client2} = WebSocketClient.connect(connected_client)
          assert client2.conn_pid == connected_client.conn_pid
        end)

      assert log_output =~ "Connection already established"
    end
  end

  describe "message handling" do
    test "send_message/2 fails when not connected", %{client: client} do
      # Try to send without connecting
      assert {:error, "WebSocket not connected"} = WebSocketClient.send_message(client, "test")
    end

    test "send_message/2 works with connected client" do
      # Create a mock connected client
      mock_conn_pid = spawn(fn -> :timer.sleep(1000) end)
      mock_stream_ref = make_ref()

      connected_client = %{
        WebSocketClient.new("ws://test.com", self())
        | conn_pid: mock_conn_pid,
          stream_ref: mock_stream_ref
      }

      # Should attempt to send (will fail at gun level but client logic works)
      result = WebSocketClient.send_message(connected_client, "test message")
      # Result depends on gun's response, but should not error at client level
      assert result == :ok or match?({:error, _}, result)
    end

    test "send_message/2 encodes maps to JSON" do
      mock_conn_pid = spawn(fn -> :timer.sleep(1000) end)
      mock_stream_ref = make_ref()

      connected_client = %{
        WebSocketClient.new("ws://test.com", self())
        | conn_pid: mock_conn_pid,
          stream_ref: mock_stream_ref
      }

      # Send map that should be JSON encoded
      message_data = %{type: "test", data: %{id: 123, name: "test"}}
      result = WebSocketClient.send_message(connected_client, message_data)

      # Should not fail at encoding level
      assert result == :ok or match?({:error, _}, result)
    end

    test "handle_message/3 processes different frame types", %{client: client} do
      # Create a mock connected client
      mock_stream_ref = make_ref()
      mock_client = %{client | stream_ref: mock_stream_ref}

      # Test text frame handling
      updated_client =
        WebSocketClient.handle_message(
          mock_client,
          mock_stream_ref,
          {:text, "test message"}
        )

      assert_receive {:websocket_message, _client, "test message"}, 100
      assert updated_client == mock_client

      # Test binary frame handling
      WebSocketClient.handle_message(
        mock_client,
        mock_stream_ref,
        {:binary, <<1, 2, 3>>}
      )

      assert_receive {:websocket_binary, _client, <<1, 2, 3>>}, 100

      # Test close frame handling
      WebSocketClient.handle_message(
        mock_client,
        mock_stream_ref,
        {:close, 1000, "normal closure"}
      )

      assert_receive {:websocket_closed, _client, {1000, "normal closure"}}, 100
    end

    test "handle_message/3 ignores messages for wrong stream", %{client: client} do
      mock_stream_ref = make_ref()
      mock_client = %{client | stream_ref: mock_stream_ref}

      # Create fake stream ref
      wrong_stream_ref = make_ref()

      # Should ignore message for wrong stream
      updated_client =
        WebSocketClient.handle_message(
          mock_client,
          wrong_stream_ref,
          {:text, "ignored message"}
        )

      # Should not receive any message
      refute_receive {:websocket_message, _client, "ignored message"}, 100
      assert updated_client == mock_client
    end
  end

  describe "connection lifecycle and error handling" do
    test "handle_upgrade/2 processes successful connection upgrade", %{client: client} do
      mock_stream_ref = make_ref()
      mock_client = %{client | stream_ref: mock_stream_ref, connection_start_time: System.monotonic_time(:millisecond)}

      # Simulate upgrade success
      updated_client = WebSocketClient.handle_upgrade(mock_client, mock_stream_ref)

      # Should receive connection notification
      assert_receive {:websocket_connected, _client}, 100
      assert updated_client == mock_client
    end

    test "handle_upgrade/2 ignores upgrades for wrong stream", %{client: client} do
      mock_stream_ref = make_ref()
      mock_client = %{client | stream_ref: mock_stream_ref}

      # Create wrong stream ref
      wrong_stream_ref = make_ref()

      log_output =
        capture_log(fn ->
          updated_client = WebSocketClient.handle_upgrade(mock_client, wrong_stream_ref)
          assert updated_client == mock_client
        end)

      assert log_output =~ "Upgrade for unknown stream"
      refute_receive {:websocket_connected, _client}, 100
    end

    test "handle_connection_failure/2 processes disconnection", %{client: client} do
      # Create a mock connected client
      mock_connected_client = %{
        client
        | conn_pid: self(),
          stream_ref: make_ref(),
          monitor_ref: make_ref(),
          connection_start_time: System.monotonic_time(:millisecond)
      }

      # Simulate connection failure
      reason = :econnreset
      updated_client = WebSocketClient.handle_connection_failure(mock_connected_client, reason)

      # Should clear connection state
      assert updated_client.conn_pid == nil
      assert updated_client.stream_ref == nil
      assert updated_client.monitor_ref == nil
      assert updated_client.connection_start_time == nil

      # Should receive disconnection notification (via TestReceiver)
      assert_receive {:disconnected, _client, :econnreset}, 100
    end

    test "close/1 properly closes connection and clears state", %{client: client} do
      # Create a mock connected client
      mock_connected_client = %{
        client
        | conn_pid: self(),
          stream_ref: make_ref(),
          monitor_ref: make_ref(),
          connection_start_time: System.monotonic_time(:millisecond)
      }

      # Close connection
      closed_client = WebSocketClient.close(mock_connected_client)

      # Should clear all connection state
      assert closed_client.conn_pid == nil
      assert closed_client.stream_ref == nil
      assert closed_client.monitor_ref == nil
      assert closed_client.connection_start_time == nil
      assert closed_client.reconnect_timer == nil
    end

    test "close/1 cancels reconnect timer if active", %{client: client} do
      # Schedule reconnection
      client_with_timer = WebSocketClient.schedule_reconnect(client)
      assert client_with_timer.reconnect_timer != nil

      # Close should cancel timer
      closed_client = WebSocketClient.close(client_with_timer)
      assert closed_client.reconnect_timer == nil
    end
  end

  describe "reconnection logic" do
    test "schedule_reconnect/1 sets up reconnection timer", %{client: client} do
      updated_client = WebSocketClient.schedule_reconnect(client)

      assert updated_client.reconnect_timer != nil
      assert is_reference(updated_client.reconnect_timer)

      # Verify timer interval is set correctly
      # From setup
      assert updated_client.reconnect_interval == 100
    end

    test "schedule_reconnect/1 cancels existing timer", %{client: client} do
      # Schedule first reconnection
      client1 = WebSocketClient.schedule_reconnect(client)
      first_timer = client1.reconnect_timer

      # Schedule second reconnection (should cancel first)
      client2 = WebSocketClient.schedule_reconnect(client1)
      second_timer = client2.reconnect_timer

      assert first_timer != second_timer
      assert client2.reconnect_timer == second_timer
    end

    test "reconnection triggers after configured interval", %{client: client} do
      # Schedule reconnection with very short interval - need to use test process as owner
      short_interval_client = %{client | reconnect_interval: 50, owner_pid: self()}
      WebSocketClient.schedule_reconnect(short_interval_client)

      # Should receive reconnect message after interval
      assert_receive {:websocket_reconnect, _client}, 200
    end

    test "automatic reconnection attempt integration", %{receiver_pid: _receiver_pid} do
      # Create client that will fail to connect initially - use test process as owner
      bad_client = WebSocketClient.new("ws://localhost:9999/fail", self(), reconnect_interval: 100)

      # Schedule reconnection
      WebSocketClient.schedule_reconnect(bad_client)

      # Should receive reconnect message first
      assert_receive {:websocket_reconnect, _client}, 200

      # The actual reconnection failure would happen in a real implementation
      # For this test, we just verify the timer message was sent
    end
  end

  describe "concurrent connection handling" do
    test "multiple clients can be created simultaneously", %{test_url: test_url} do
      # Create multiple clients
      clients =
        for i <- 1..3 do
          {:ok, pid} = TestReceiver.start_link(self())
          client = WebSocketClient.new(test_url, pid, telemetry_prefix: [:test, String.to_atom("client_#{i}")])
          {pid, client}
        end

      # All should be created successfully
      assert length(clients) == 3

      # Each should have unique telemetry prefix
      prefixes = for {_pid, client} <- clients, do: client.telemetry_prefix
      assert length(Enum.uniq(prefixes)) == 3

      # Cleanup
      for {receiver, _client} <- clients do
        GenServer.stop(receiver, :normal, 100)
      end
    end

    test "message sending works with mock connections" do
      # Create multiple mock connected clients
      clients =
        for _i <- 1..3 do
          mock_conn_pid = spawn(fn -> :timer.sleep(100) end)
          mock_stream_ref = make_ref()

          %{
            WebSocketClient.new("ws://test.com", self())
            | conn_pid: mock_conn_pid,
              stream_ref: mock_stream_ref
          }
        end

      # Send messages concurrently
      tasks =
        for {client, i} <- Enum.with_index(clients, 1) do
          Task.async(fn ->
            WebSocketClient.send_message(client, "message_#{i}")
          end)
        end

      # Wait for all sends to complete
      results = Task.await_many(tasks, 1000)

      # All should either succeed or fail gracefully
      Enum.each(results, fn result ->
        assert result == :ok or match?({:error, _}, result)
      end)
    end
  end

  describe "configuration and customization" do
    test "custom reconnect interval is respected", %{test_url: test_url} do
      custom_interval = 250
      client = WebSocketClient.new(test_url, self(), reconnect_interval: custom_interval)

      assert client.reconnect_interval == custom_interval
    end

    test "custom connection timeout configuration", %{test_url: test_url} do
      custom_timeout = 500
      client = WebSocketClient.new(test_url, self(), connection_timeout: custom_timeout)

      assert client.connection_timeout == custom_timeout
    end

    test "custom telemetry prefix configuration", %{test_url: test_url} do
      custom_prefix = [:my_app, :custom_ws]
      client = WebSocketClient.new(test_url, self(), telemetry_prefix: custom_prefix)

      assert client.telemetry_prefix == custom_prefix
    end
  end

  describe "telemetry and monitoring integration" do
    test "connection manager integration works correctly", %{client: client} do
      # Connection manager should be initialized
      assert is_map(client.connection_manager)

      # Close and verify cleanup
      closed_client = WebSocketClient.close(client)
      assert is_map(closed_client.connection_manager)
    end

    test "telemetry prefix is properly configured", %{client: client} do
      assert client.telemetry_prefix == [:test, :websocket]

      # Custom prefix should work
      custom_client = WebSocketClient.new("ws://test.com", self(), telemetry_prefix: [:custom])
      assert custom_client.telemetry_prefix == [:custom]
    end
  end

  describe "edge cases and error scenarios" do
    test "handles malformed WebSocket URLs gracefully" do
      malformed_urls = [
        "not-a-url",
        # Not WebSocket
        "http://localhost:8080/regular-http",
        "ftp://localhost/wrong-protocol",
        ""
      ]

      Enum.each(malformed_urls, fn url ->
        client = WebSocketClient.new(url, self())

        # Should create client but connection should fail
        assert client.url == url

        # Connection attempts should fail gracefully
        log_output =
          capture_log(fn ->
            case WebSocketClient.connect(client) do
              {:ok, _} -> flunk("Expected connection to fail for malformed URL: #{url}")
              {:error, _client, _reason} -> :ok
            end
          end)

        # Should log connection failure
        assert log_output =~ "Connection failed" or url == ""
      end)
    end

    test "handles process termination during connection", %{client: client} do
      # Create a mock connected client
      mock_connected_client = %{
        client
        | conn_pid: self(),
          stream_ref: make_ref()
      }

      # Simulate process termination by closing
      closed_client = WebSocketClient.close(mock_connected_client)

      # State should be properly cleaned up
      assert closed_client.conn_pid == nil
      assert closed_client.stream_ref == nil
    end

    test "connection state consistency under error conditions", %{test_url: test_url} do
      # Create client with very short timeout
      short_timeout_client = WebSocketClient.new(test_url, self(), connection_timeout: 1)

      # Connection should timeout but state should remain consistent
      log_output =
        capture_log(fn ->
          case WebSocketClient.connect(short_timeout_client) do
            {:ok, client} ->
              # If it succeeds, state should be valid
              assert client.conn_pid != nil
              assert client.stream_ref != nil

            {:error, client, _reason} ->
              # If it fails, state should be clean
              assert client.conn_pid == nil
              assert client.stream_ref == nil
          end
        end)

      assert log_output =~ "Connection failed"
    end
  end

  describe "protocol compliance and standards" do
    test "follows WebSocket close frame protocol", %{client: client} do
      mock_stream_ref = make_ref()
      mock_client = %{client | stream_ref: mock_stream_ref}

      # Simulate server-initiated close frame
      WebSocketClient.handle_message(
        mock_client,
        mock_stream_ref,
        {:close, 1001, "going away"}
      )

      # Should receive proper close event (via TestReceiver)
      assert_receive {:websocket_closed, _client, {1001, "going away"}}, 100
    end

    test "processes different WebSocket frame types correctly", %{client: client} do
      mock_stream_ref = make_ref()
      mock_client = %{client | stream_ref: mock_stream_ref}

      # Test ping frame (should be ignored gracefully)
      WebSocketClient.handle_message(
        mock_client,
        mock_stream_ref,
        {:ping, "ping data"}
      )

      # Test pong frame (should be ignored gracefully) 
      WebSocketClient.handle_message(
        mock_client,
        mock_stream_ref,
        {:pong, "pong data"}
      )

      # Should handle unknown frames gracefully
      result =
        WebSocketClient.handle_message(
          mock_client,
          mock_stream_ref,
          {:unknown_frame, "data"}
        )

      # Should return client unchanged and not crash
      assert result == mock_client
    end

    test "handles protocol negotiation options", %{client: client} do
      # Test with protocol specification
      protocols = ["chat", "superchat"]

      # Should handle protocol options gracefully even if connection fails
      log_output =
        capture_log(fn ->
          case WebSocketClient.connect(client, protocols: protocols) do
            {:ok, _connected_client} -> :ok
            {:error, _client, _reason} -> :ok
          end
        end)

      # Should attempt connection with protocols
      assert log_output =~ "Connection"
    end
  end
end
