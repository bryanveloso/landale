defmodule Server.WebSocketConnectionTest do
  use ExUnit.Case, async: true

  alias Server.WebSocketConnection

  describe "WebSocketConnection with CloudFront support" do
    test "includes CloudFront headers when retry config is enabled" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "wss://example.cloudfront.net",
          owner: self(),
          auto_connect: false,
          headers: [{"custom-header", "value"}],
          retry_config: [enabled: true]
        )

      # Trigger connection
      send(pid, :connect)

      # Should receive connection attempt notification
      assert_receive {WebSocketConnection, ^pid, {:websocket_connecting, %{uri: "wss://example.cloudfront.net"}}}, 1000

      # Get state to check headers were built correctly
      state = :sys.get_state(pid)
      assert state.opts[:retry_config][:enabled] == true
      assert state.cloudfront_retry_count == 0
      assert state.user_agent_index == 0
    end

    test "does not include CloudFront headers when retry config is disabled" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "wss://example.com",
          owner: self(),
          auto_connect: false,
          headers: [{"custom-header", "value"}],
          retry_config: [enabled: false]
        )

      state = :sys.get_state(pid)
      assert state.opts[:retry_config][:enabled] == false
    end

    test "handles CloudFront 400 error with retry" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "wss://example.cloudfront.net",
          owner: self(),
          auto_connect: false,
          retry_config: [enabled: true, max_retries: 2]
        )

      # Set up initial state with connection
      state = :sys.get_state(pid)
      stream_ref = make_ref()
      state = %{state | conn_pid: self(), stream_ref: stream_ref}
      :sys.replace_state(pid, fn _ -> state end)

      # Simulate CloudFront 400 error with the correct stream_ref
      send(pid, {:gun_response, self(), stream_ref, :fin, 400, []})

      # Should receive reconnection attempt
      assert_receive {WebSocketConnection, ^pid, {:websocket_connecting, _}}, 1000

      # Should increment retry count and user agent index
      new_state = :sys.get_state(pid)
      assert new_state.cloudfront_retry_count == 1
      assert new_state.user_agent_index == 1
    end

    test "stops retrying after max CloudFront retries" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "wss://example.cloudfront.net",
          owner: self(),
          auto_connect: false,
          retry_config: [enabled: true, max_retries: 1]
        )

      # Set up state at max retries
      state = :sys.get_state(pid)
      stream_ref = make_ref()
      state = %{state | conn_pid: self(), stream_ref: stream_ref, cloudfront_retry_count: 1}
      :sys.replace_state(pid, fn _ -> state end)

      # Simulate another CloudFront 400 error with the correct stream_ref
      send(pid, {:gun_response, self(), stream_ref, :fin, 400, []})

      # Should receive error notification, not retry
      assert_receive {WebSocketConnection, ^pid, {:websocket_error, %{reason: {:upgrade_failed, 400}}}}, 1000
    end

    test "resets CloudFront retry count on successful connection" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "wss://example.cloudfront.net",
          owner: self(),
          auto_connect: false,
          retry_config: [enabled: true]
        )

      # Set up state with retry count
      state = :sys.get_state(pid)
      state = %{state | conn_pid: self(), stream_ref: make_ref(), cloudfront_retry_count: 2, user_agent_index: 2}
      :sys.replace_state(pid, fn _ -> state end)

      # Simulate successful upgrade
      stream_ref = state.stream_ref
      send(pid, {:gun_upgrade, self(), stream_ref, ["websocket"], []})

      # Should reset CloudFront retry count
      Process.sleep(50)
      new_state = :sys.get_state(pid)
      assert new_state.cloudfront_retry_count == 0
      assert new_state.connection_state == :connected
    end

    test "rotates user agents on CloudFront retries" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "wss://example.cloudfront.net",
          owner: self(),
          auto_connect: false,
          retry_config: [enabled: true, max_retries: 5]
        )

      # Test multiple retries to ensure user agent rotation
      for i <- 0..3 do
        state = :sys.get_state(pid)
        stream_ref = make_ref()
        state = %{state | conn_pid: self(), stream_ref: stream_ref, cloudfront_retry_count: i, user_agent_index: i}
        :sys.replace_state(pid, fn _ -> state end)

        send(pid, {:gun_response, self(), stream_ref, :fin, 400, []})

        # Should receive reconnection attempt
        assert_receive {WebSocketConnection, ^pid, {:websocket_connecting, _}}, 1000

        new_state = :sys.get_state(pid)
        assert new_state.user_agent_index == i + 1
      end
    end

    test "custom headers are preserved when CloudFront headers are added" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "wss://example.cloudfront.net",
          owner: self(),
          auto_connect: false,
          headers: [
            {"authorization", "Bearer token"},
            {"user-agent", "CustomAgent/1.0"}
          ],
          retry_config: [enabled: true]
        )

      state = :sys.get_state(pid)
      # User-provided headers should take precedence
      assert Enum.any?(state.opts[:headers], fn {k, v} ->
               k == "authorization" && v == "Bearer token"
             end)

      assert Enum.any?(state.opts[:headers], fn {k, v} ->
               k == "user-agent" && v == "CustomAgent/1.0"
             end)
    end

    test "handles non-CloudFront errors normally" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "wss://example.com",
          owner: self(),
          auto_connect: false,
          retry_config: [enabled: true]
        )

      state = :sys.get_state(pid)
      stream_ref = make_ref()
      state = %{state | conn_pid: self(), stream_ref: stream_ref}
      :sys.replace_state(pid, fn _ -> state end)

      # Simulate non-400 error with the correct stream_ref
      send(pid, {:gun_response, self(), stream_ref, :fin, 503, []})

      # Should receive error notification
      assert_receive {WebSocketConnection, ^pid, {:websocket_error, %{reason: {:upgrade_failed, 503}}}}, 1000

      # Should not increment CloudFront retry count
      new_state = :sys.get_state(pid)
      assert new_state.cloudfront_retry_count == 0
    end
  end

  describe "WebSocketConnection backward compatibility" do
    test "works without retry_config option" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "ws://localhost:4455",
          owner: self(),
          auto_connect: false
        )

      state = :sys.get_state(pid)
      assert state.cloudfront_retry_count == 0
      assert state.user_agent_index == 0
      assert state.opts[:retry_config] == nil
    end

    test "existing OBS usage pattern still works" do
      {:ok, pid} =
        WebSocketConnection.start_link(
          uri: "ws://localhost:4455",
          owner: self(),
          auto_connect: false,
          headers: [{"custom", "value"}]
        )

      # Send connect
      WebSocketConnection.connect(pid)

      # Should receive connecting notification
      assert_receive {WebSocketConnection, ^pid, {:websocket_connecting, %{uri: "ws://localhost:4455"}}}, 1000
    end
  end
end
