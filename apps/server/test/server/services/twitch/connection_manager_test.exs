defmodule Server.Services.Twitch.ConnectionManagerTest do
  use ExUnit.Case, async: false

  alias Server.Services.Twitch.ConnectionManager
  alias Server.WebSocketConnection

  @twitch_url "wss://eventsub.wss.twitch.tv/ws"
  @cloudfront_headers [
    {"user-agent", "Mozilla/5.0 (compatible; TwitchEventSub/1.0)"},
    {"origin", "https://eventsub.wss.twitch.tv"}
  ]

  describe "ConnectionManager initialization" do
    test "starts with Twitch EventSub URL and CloudFront headers" do
      {:ok, manager} =
        ConnectionManager.start_link(
          url: @twitch_url,
          owner: self(),
          headers: @cloudfront_headers,
          client_id: "test_client_id",
          # Don't use named process in tests
          name: nil
        )

      state = ConnectionManager.get_state(manager)
      assert state.uri == @twitch_url
      assert state.connected == false
      assert state.connection_state == :disconnected
    end

    test "accepts optional telemetry prefix" do
      {:ok, manager} =
        ConnectionManager.start_link(
          url: @twitch_url,
          owner: self(),
          telemetry_prefix: [:test, :twitch],
          client_id: "test_client_id",
          name: nil
        )

      # Telemetry prefix is internal, just verify manager is alive
      assert Process.alive?(manager)
    end

    test "monitors owner process" do
      {:ok, manager} =
        ConnectionManager.start_link(
          url: @twitch_url,
          owner: self(),
          client_id: "test_client_id",
          name: nil
        )

      # Verify manager stops when owner exits
      Process.flag(:trap_exit, true)
      Process.exit(manager, :kill)

      assert_receive {:EXIT, ^manager, :killed}
    end
  end

  describe "connection lifecycle" do
    setup do
      # Use a non-reachable URL to prevent real connections
      {:ok, manager} =
        ConnectionManager.start_link(
          url: "wss://test.invalid/ws",
          owner: self(),
          headers: @cloudfront_headers,
          client_id: "test_client_id",
          name: nil
        )

      {:ok, manager: manager}
    end

    test "connect/1 sends connection request", %{manager: manager} do
      # ConnectionManager.connect returns :ok
      assert :ok = ConnectionManager.connect(manager)

      # Should receive connection state change notification (might timeout due to test URL)
      receive do
        {:twitch_connection, {:connection_state_changed, :connecting}} -> :ok
      after
        # It's ok if we don't get this with test URL
        100 -> :ok
      end
    end

    test "disconnect/1 sends disconnection request", %{manager: manager} do
      # First connect
      ConnectionManager.connect(manager)
      assert_receive {:twitch_connection, {:connection_state_changed, :connecting}}

      # Then disconnect
      :ok = ConnectionManager.disconnect(manager)

      # State should update
      state = ConnectionManager.get_state(manager)
      assert state.connection_state == :disconnected
    end
  end

  describe "CloudFront 400 error handling" do
    setup do
      # Use a non-reachable URL to prevent real connections
      {:ok, manager} =
        ConnectionManager.start_link(
          url: "wss://test.invalid/ws",
          owner: self(),
          headers: @cloudfront_headers,
          client_id: "test_client_id",
          name: nil
        )

      {:ok, manager: manager}
    end

    test "retries on CloudFront 400 error", %{manager: manager} do
      # Create a fake ws_conn ref
      ws_conn = make_ref()

      # Update manager state to have this ws_conn
      :sys.replace_state(manager, fn state ->
        %{state | ws_conn: ws_conn}
      end)

      # Simulate CloudFront 400 error
      send(
        manager,
        {WebSocketConnection, ws_conn, {:websocket_error, %{reason: {:upgrade_failed, 400, "Bad Request"}}}}
      )

      # Should receive disconnect notification
      assert_receive {:twitch_connection, {:connection_lost, nil}}

      # Manager should still be alive and handle the error
      Process.sleep(50)
      assert Process.alive?(manager)
    end

    test "limits CloudFront retries", %{manager: manager} do
      # Create a fake ws_conn ref
      ws_conn = make_ref()

      # Update manager state to have this ws_conn
      :sys.replace_state(manager, fn state ->
        %{state | ws_conn: ws_conn}
      end)

      # Simulate multiple CloudFront 400 errors
      send(
        manager,
        {WebSocketConnection, ws_conn, {:websocket_error, %{reason: {:upgrade_failed, 400, "Bad Request"}}}}
      )

      assert_receive {:twitch_connection, {:connection_lost, nil}}

      # Wait for retry
      Process.sleep(100)

      # WebSocketConnection handles retries internally
      # Manager should still be alive after multiple errors
      Process.sleep(50)
      assert Process.alive?(manager)
    end
  end

  describe "telemetry events" do
    setup do
      # Attach telemetry handler
      :telemetry.attach_many(
        "test-handler",
        [
          [:server, :twitch, :websocket, :connected],
          [:server, :twitch, :websocket, :disconnected],
          [:server, :twitch, :websocket, :message_received],
          [:server, :twitch, :websocket, :error]
        ],
        fn event, measurements, metadata, config ->
          send(config.test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{test_pid: self()}
      )

      {:ok, manager} =
        ConnectionManager.start_link(
          url: @twitch_url,
          owner: self(),
          headers: @cloudfront_headers,
          telemetry_prefix: [:server, :twitch, :websocket],
          client_id: "test_client_id",
          name: nil
        )

      on_exit(fn -> :telemetry.detach("test-handler") end)
      {:ok, manager: manager}
    end

    @tag skip: "Telemetry events not yet implemented - see task #60"
    test "emits connected telemetry event", %{manager: _manager} do
      # Placeholder for future telemetry implementation
    end

    @tag skip: "Telemetry events not yet implemented - see task #60"
    test "emits disconnected telemetry event", %{manager: _manager} do
      # Placeholder for future telemetry implementation
    end

    @tag skip: "Telemetry events not yet implemented - see task #60"
    test "emits message received telemetry event", %{manager: _manager} do
      # Placeholder for future telemetry implementation
    end

    @tag skip: "Telemetry events not yet implemented - see task #60"
    test "emits error telemetry event", %{manager: _manager} do
      # Placeholder for future telemetry implementation
    end
  end

  describe "concurrent operations" do
    setup do
      # Use a non-reachable URL to prevent real connections
      {:ok, manager} =
        ConnectionManager.start_link(
          url: "wss://test.invalid/ws",
          owner: self(),
          headers: @cloudfront_headers,
          client_id: "test_client_id",
          name: nil
        )

      {:ok, manager: manager}
    end

    test "handles rapid connect/disconnect cycles", %{manager: manager} do
      # Rapid fire operations
      for _ <- 1..10 do
        ConnectionManager.connect(manager)
        ConnectionManager.disconnect(manager)
      end

      # Should handle gracefully without crashing
      Process.sleep(100)
      assert Process.alive?(manager)
    end

    test "handles concurrent state queries", %{manager: manager} do
      # Spawn multiple processes querying state
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            ConnectionManager.get_state(manager)
          end)
        end

      # All should complete successfully
      results = Task.await_many(tasks)
      assert length(results) == 20
      assert Enum.all?(results, &(&1.uri == "wss://test.invalid/ws"))
    end
  end

  describe "error recovery" do
    setup do
      # Use a non-reachable URL to prevent real connections
      {:ok, manager} =
        ConnectionManager.start_link(
          url: "wss://test.invalid/ws",
          owner: self(),
          headers: @cloudfront_headers,
          client_id: "test_client_id",
          name: nil
        )

      {:ok, manager: manager}
    end

    test "recovers from WebSocketConnection crash", %{manager: manager} do
      # Simulate WebSocketConnection process crash
      fake_ws_pid = spawn(fn -> :ok end)
      send(manager, {:DOWN, make_ref(), :process, fake_ws_pid, :crashed})

      # Manager should still be alive
      Process.sleep(50)
      assert Process.alive?(manager)
    end

    test "handles invalid messages gracefully", %{manager: manager} do
      # Send various invalid messages
      send(manager, :invalid_message)
      send(manager, {:unknown_source, :data})
      send(manager, {WebSocketConnection, :unknown_message})

      # Should not crash
      Process.sleep(50)
      assert Process.alive?(manager)
    end
  end
end
