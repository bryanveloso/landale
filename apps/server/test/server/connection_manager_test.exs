defmodule Server.ConnectionManagerTest do
  use ExUnit.Case, async: true

  alias Server.ConnectionManager

  describe "connection state initialization" do
    test "initializes empty connection state" do
      state = ConnectionManager.init_connection_state()

      assert state.monitors == %{}
      assert state.timers == %{}
      assert state.connections == %{}
      assert state.metadata == %{}
    end
  end

  describe "monitor management" do
    test "adds and removes monitors" do
      state = ConnectionManager.init_connection_state()
      test_pid = spawn(fn -> Process.sleep(1000) end)

      # Add monitor
      {monitor_ref, updated_state} = ConnectionManager.add_monitor(state, test_pid, :test_process)

      assert is_reference(monitor_ref)
      assert Map.has_key?(updated_state.monitors, monitor_ref)
      assert updated_state.monitors[monitor_ref] == {test_pid, :test_process}

      # Remove monitor
      final_state = ConnectionManager.remove_monitor(updated_state, monitor_ref)

      assert final_state.monitors == %{}

      # Clean up test process
      Process.exit(test_pid, :kill)
    end

    test "handles monitor DOWN messages" do
      state = ConnectionManager.init_connection_state()
      test_pid = spawn(fn -> Process.sleep(100) end)

      {monitor_ref, updated_state} = ConnectionManager.add_monitor(state, test_pid, :test_process)

      # Simulate process death
      Process.exit(test_pid, :test_reason)

      # Handle DOWN message
      final_state =
        ConnectionManager.handle_monitor_down(
          updated_state,
          monitor_ref,
          test_pid,
          :test_reason
        )

      assert final_state.monitors == %{}
    end

    test "handles unknown monitor references gracefully" do
      state = ConnectionManager.init_connection_state()
      fake_ref = make_ref()
      fake_pid = spawn(fn -> :ok end)

      # Should not crash and should return unchanged state
      result_state = ConnectionManager.remove_monitor(state, fake_ref)
      assert result_state == state

      result_state = ConnectionManager.handle_monitor_down(state, fake_ref, fake_pid, :reason)
      assert result_state == state

      Process.exit(fake_pid, :kill)
    end
  end

  describe "timer management" do
    test "adds and cancels timers" do
      state = ConnectionManager.init_connection_state()

      # Add timer
      timer_ref = Process.send_after(self(), :test_message, 5000)
      updated_state = ConnectionManager.add_timer(state, timer_ref, :test_timer)

      assert Map.has_key?(updated_state.timers, :test_timer)
      assert updated_state.timers[:test_timer] == timer_ref

      # Cancel timer
      final_state = ConnectionManager.cancel_timer(updated_state, :test_timer)

      assert final_state.timers == %{}

      # Verify message was not received
      refute_receive :test_message, 100
    end

    test "replaces existing timers with same label" do
      state = ConnectionManager.init_connection_state()

      # Add first timer
      timer1 = Process.send_after(self(), :first_message, 5000)
      state_with_timer1 = ConnectionManager.add_timer(state, timer1, :test_timer)

      # Add second timer with same label
      timer2 = Process.send_after(self(), :second_message, 5000)
      state_with_timer2 = ConnectionManager.add_timer(state_with_timer1, timer2, :test_timer)

      assert map_size(state_with_timer2.timers) == 1
      assert state_with_timer2.timers[:test_timer] == timer2

      # Clean up
      ConnectionManager.cancel_timer(state_with_timer2, :test_timer)
    end

    test "handles cancelling non-existent timers gracefully" do
      state = ConnectionManager.init_connection_state()

      # Should not crash
      result_state = ConnectionManager.cancel_timer(state, :non_existent_timer)
      assert result_state == state
    end
  end

  describe "connection management" do
    setup do
      # Create a mock Gun connection process
      mock_conn_pid =
        spawn(fn ->
          receive do
            :close -> :ok
          after
            5000 -> :ok
          end
        end)

      mock_stream_ref = make_ref()

      %{mock_conn_pid: mock_conn_pid, mock_stream_ref: mock_stream_ref}
    end

    test "adds and closes connections", %{mock_conn_pid: conn_pid, mock_stream_ref: stream_ref} do
      state = ConnectionManager.init_connection_state()

      # Add connection
      updated_state = ConnectionManager.add_connection(state, conn_pid, stream_ref, :websocket)

      assert Map.has_key?(updated_state.connections, :websocket)
      assert updated_state.connections[:websocket] == {conn_pid, stream_ref}

      # Check connection is alive
      assert ConnectionManager.connection_alive?(updated_state, :websocket)

      # Get connection
      {:ok, {retrieved_pid, retrieved_ref}} = ConnectionManager.get_connection(updated_state, :websocket)
      assert retrieved_pid == conn_pid
      assert retrieved_ref == stream_ref

      # Close connection
      final_state = ConnectionManager.close_connection(updated_state, :websocket)

      assert final_state.connections == %{}
      refute ConnectionManager.connection_alive?(final_state, :websocket)
      assert ConnectionManager.get_connection(final_state, :websocket) == :error
    end

    test "replaces existing connections with same label", %{mock_conn_pid: conn_pid1, mock_stream_ref: stream_ref1} do
      state = ConnectionManager.init_connection_state()

      # Create second mock connection
      conn_pid2 =
        spawn(fn ->
          receive do
            :close -> :ok
          after
            5000 -> :ok
          end
        end)

      stream_ref2 = make_ref()

      # Add first connection
      state_with_conn1 = ConnectionManager.add_connection(state, conn_pid1, stream_ref1, :websocket)

      # Add second connection with same label
      state_with_conn2 = ConnectionManager.add_connection(state_with_conn1, conn_pid2, stream_ref2, :websocket)

      assert map_size(state_with_conn2.connections) == 1
      assert state_with_conn2.connections[:websocket] == {conn_pid2, stream_ref2}

      # Clean up
      ConnectionManager.close_connection(state_with_conn2, :websocket)
    end
  end

  describe "metadata management" do
    test "sets and gets metadata" do
      state = ConnectionManager.init_connection_state()

      # Set metadata
      updated_state = ConnectionManager.set_metadata(state, :service_name, "twitch")
      assert ConnectionManager.get_metadata(updated_state, :service_name) == "twitch"

      # Get with default
      assert ConnectionManager.get_metadata(updated_state, :unknown_key, "default") == "default"
      assert ConnectionManager.get_metadata(updated_state, :unknown_key) == nil
    end
  end

  describe "resource summary" do
    test "provides accurate resource summary" do
      state = ConnectionManager.init_connection_state()

      # Add some resources
      test_pid = spawn(fn -> Process.sleep(1000) end)
      {_monitor_ref, state} = ConnectionManager.add_monitor(state, test_pid, :test)

      timer_ref = Process.send_after(self(), :test, 5000)
      state = ConnectionManager.add_timer(state, timer_ref, :test_timer)

      mock_conn = spawn(fn -> Process.sleep(1000) end)
      mock_stream = make_ref()
      state = ConnectionManager.add_connection(state, mock_conn, mock_stream, :test_conn)

      state = ConnectionManager.set_metadata(state, :test_key, "test_value")

      summary = ConnectionManager.get_resource_summary(state)

      assert summary.monitors == 1
      assert summary.timers == 1
      assert summary.connections == 1
      assert summary.active_connections == 1
      assert :test_key in summary.metadata_keys

      # Clean up
      ConnectionManager.cleanup_all(state)
      Process.exit(test_pid, :kill)
      Process.exit(mock_conn, :kill)
    end
  end

  describe "complete cleanup" do
    test "cleans up all resources" do
      state = ConnectionManager.init_connection_state()

      # Add various resources
      test_pid = spawn(fn -> Process.sleep(1000) end)
      {_monitor_ref, state} = ConnectionManager.add_monitor(state, test_pid, :test)

      timer_ref = Process.send_after(self(), :test_message, 5000)
      state = ConnectionManager.add_timer(state, timer_ref, :test_timer)

      mock_conn =
        spawn(fn ->
          receive do
            :close -> :ok
          after
            5000 -> :ok
          end
        end)

      mock_stream = make_ref()
      state = ConnectionManager.add_connection(state, mock_conn, mock_stream, :test_conn)

      # Cleanup all
      assert :ok = ConnectionManager.cleanup_all(state)

      # Verify timer was cancelled
      refute_receive :test_message, 100

      # Clean up test processes
      Process.exit(test_pid, :kill)
    end
  end

  describe "error handling" do
    test "handles dead processes in connection cleanup" do
      state = ConnectionManager.init_connection_state()

      # Create and kill a process
      dead_pid = spawn(fn -> :ok end)
      Process.exit(dead_pid, :kill)
      # Ensure process is dead
      :timer.sleep(10)

      mock_stream = make_ref()
      state = ConnectionManager.add_connection(state, dead_pid, mock_stream, :dead_conn)

      # Should not crash during cleanup
      assert :ok = ConnectionManager.cleanup_all(state)

      # Should handle connection alive check gracefully
      refute ConnectionManager.connection_alive?(state, :dead_conn)
    end

    test "handles monitor reference mismatches" do
      state = ConnectionManager.init_connection_state()

      pid1 = spawn(fn -> Process.sleep(1000) end)
      pid2 = spawn(fn -> Process.sleep(1000) end)

      {monitor_ref, state} = ConnectionManager.add_monitor(state, pid1, :test)

      # Simulate DOWN message with wrong PID
      result_state = ConnectionManager.handle_monitor_down(state, monitor_ref, pid2, :reason)

      # Should still clean up the monitor reference
      assert result_state.monitors == %{}

      # Clean up
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end
end
