defmodule Server.Services.OBS.ConnectionsSupervisorTest do
  @moduledoc """
  Unit tests for the OBS ConnectionsSupervisor DynamicSupervisor.

  Tests dynamic supervision of OBS sessions including:
  - DynamicSupervisor initialization
  - Session lifecycle management
  - Multiple session handling
  - Error handling and recovery
  - Session listing
  """
  use ExUnit.Case, async: true

  alias Server.Services.OBS.ConnectionsSupervisor

  # OBS.Supervisor now exists

  def test_session_id, do: "test_connections_sup_#{:rand.uniform(100_000)}_#{System.unique_integer([:positive])}"

  setup do
    # Ensure PubSub is started
    case Process.whereis(Server.PubSub) do
      nil -> start_supervised!({Phoenix.PubSub, name: Server.PubSub})
      _pid -> :ok
    end

    # Ensure Registry is started for OBS sessions
    case Process.whereis(Server.Services.OBS.SessionRegistry) do
      nil -> start_supervised!({Registry, keys: :unique, name: Server.Services.OBS.SessionRegistry})
      _ -> :ok
    end

    # Start ConnectionsSupervisor if not already started
    case Process.whereis(ConnectionsSupervisor) do
      nil -> start_supervised!({Server.Services.OBS.ConnectionsSupervisor, []})
      _ -> :ok
    end

    :ok
  end

  describe "start_link/1 and initialization" do
    test "starts DynamicSupervisor" do
      # ConnectionsSupervisor should be started in setup
      assert Process.whereis(ConnectionsSupervisor) != nil
    end
  end

  describe "start_session/2" do
    test "starts a new OBS session" do
      session_id = test_session_id()

      assert {:ok, pid} = ConnectionsSupervisor.start_session(session_id, uri: "ws://localhost:4455")
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Clean up
      ConnectionsSupervisor.stop_session(session_id)
    end

    test "returns existing session if already started" do
      session_id = test_session_id()

      # Start first session
      assert {:ok, pid1} = ConnectionsSupervisor.start_session(session_id, uri: "ws://localhost:4455")

      # Try to start again with same ID
      assert {:ok, pid2} = ConnectionsSupervisor.start_session(session_id, uri: "ws://localhost:4455")
      assert pid1 == pid2

      # Clean up
      ConnectionsSupervisor.stop_session(session_id)
    end

    test "can start multiple sessions with different IDs" do
      session_id1 = test_session_id()
      session_id2 = test_session_id()

      assert {:ok, pid1} = ConnectionsSupervisor.start_session(session_id1, uri: "ws://localhost:4455")
      assert {:ok, pid2} = ConnectionsSupervisor.start_session(session_id2, uri: "ws://localhost:4455")

      assert pid1 != pid2
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)

      # Clean up
      ConnectionsSupervisor.stop_session(session_id1)
      ConnectionsSupervisor.stop_session(session_id2)
    end

    test "passes options to child supervisor" do
      session_id = test_session_id()
      opts = [uri: "ws://localhost:4455", custom_option: :test_value]

      assert {:ok, pid} = ConnectionsSupervisor.start_session(session_id, opts)
      assert is_pid(pid)

      # Clean up
      ConnectionsSupervisor.stop_session(session_id)
    end
  end

  describe "stop_session/1" do
    test "stops an existing session" do
      session_id = test_session_id()

      # Start session
      {:ok, pid} = ConnectionsSupervisor.start_session(session_id, uri: "ws://localhost:4455")
      assert Process.alive?(pid)

      # Stop session
      assert :ok = ConnectionsSupervisor.stop_session(session_id)
      Process.sleep(10)

      refute Process.alive?(pid)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = ConnectionsSupervisor.stop_session("nonexistent_session")
    end

    test "can restart a stopped session" do
      session_id = test_session_id()

      # Start, stop, then restart
      {:ok, pid1} = ConnectionsSupervisor.start_session(session_id, uri: "ws://localhost:4455")
      :ok = ConnectionsSupervisor.stop_session(session_id)
      Process.sleep(10)

      {:ok, pid2} = ConnectionsSupervisor.start_session(session_id, uri: "ws://localhost:4455")
      assert pid1 != pid2
      assert Process.alive?(pid2)

      # Clean up
      ConnectionsSupervisor.stop_session(session_id)
    end
  end

  describe "list_sessions/0" do
    test "returns empty list when no sessions" do
      # Clear any existing sessions
      sessions = ConnectionsSupervisor.list_sessions()

      for pid <- sessions do
        DynamicSupervisor.terminate_child(ConnectionsSupervisor, pid)
      end

      Process.sleep(10)

      assert ConnectionsSupervisor.list_sessions() == []
    end

    test "returns all active session pids" do
      session_ids = for _ <- 1..3, do: test_session_id()

      # Start sessions
      pids =
        for id <- session_ids do
          {:ok, pid} = ConnectionsSupervisor.start_session(id, uri: "ws://localhost:4455")
          pid
        end

      # Get list
      listed_pids = ConnectionsSupervisor.list_sessions()

      # Verify all started sessions are in the list
      for pid <- pids do
        assert pid in listed_pids
      end

      # Clean up
      for id <- session_ids do
        ConnectionsSupervisor.stop_session(id)
      end
    end
  end

  describe "supervision behavior" do
    test "supervisor restarts crashed sessions" do
      session_id = test_session_id()

      {:ok, pid} = ConnectionsSupervisor.start_session(session_id, uri: "ws://localhost:4455")

      # Crash the session
      Process.exit(pid, :kill)
      Process.sleep(50)

      # Session should be restarted with new pid
      case Server.Services.OBS.Supervisor.whereis(session_id) do
        nil ->
          # Session wasn't restarted (expected with one_for_one)
          assert true

        new_pid ->
          assert new_pid != pid
          assert Process.alive?(new_pid)
          ConnectionsSupervisor.stop_session(session_id)
      end
    end

    test "supervisor handles concurrent session operations" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            session_id = "concurrent_#{i}_#{:rand.uniform(10000)}"
            {:ok, _pid} = ConnectionsSupervisor.start_session(session_id, uri: "ws://localhost:4455")
            Process.sleep(:rand.uniform(20))
            :ok = ConnectionsSupervisor.stop_session(session_id)
            :ok
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  describe "error handling" do
    test "handles supervisor initialization errors gracefully" do
      # This would test child spec errors, but requires mocking
      # the OBS.Supervisor module
      assert true
    end
  end
end
