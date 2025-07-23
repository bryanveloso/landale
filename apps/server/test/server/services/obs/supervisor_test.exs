defmodule Server.Services.OBS.SupervisorTest do
  @moduledoc """
  Unit tests for the OBS WebSocket session supervisor.

  Tests the supervisor implementation including:
  - Child spec generation and supervision tree
  - Process registration in Registry
  - Process lookup functionality
  - Restart strategies (one_for_all)
  - Via tuple generation
  - Graceful shutdown
  """
  use ExUnit.Case, async: false

  alias Server.Services.OBS.Supervisor, as: OBSSupervisor
  alias Server.Services.OBS.SessionRegistry

  @test_session_id "test_session_#{:rand.uniform(10000)}"
  @test_uri "ws://localhost:4455"

  # Skip these tests until child modules are implemented
  @moduletag :skip

  setup do
    # Ensure Registry is started (usually done in application supervision tree)
    # In tests, we might need to start it manually
    case Registry.start_link(keys: :unique, name: SessionRegistry) do
      {:ok, registry} ->
        on_exit(fn -> Process.exit(registry, :shutdown) end)
        :ok

      {:error, {:already_started, _}} ->
        :ok
    end

    on_exit(fn ->
      # Clean up any test supervisor that might be running
      if pid = OBSSupervisor.whereis(@test_session_id) do
        Supervisor.stop(pid, :shutdown)
      end
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts supervisor with all required children" do
      assert {:ok, sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})
      assert Process.alive?(sup_pid)

      # Verify all children are started
      children = Supervisor.which_children(sup_pid)
      assert length(children) == 7

      # Verify each child by ID
      child_ids = Enum.map(children, fn {id, _, _, _} -> id end)

      assert Server.Services.OBS.Connection in child_ids
      assert Server.Services.OBS.EventHandler in child_ids
      assert Server.Services.OBS.RequestTracker in child_ids
      assert Server.Services.OBS.SceneManager in child_ids
      assert Server.Services.OBS.StreamManager in child_ids
      assert Server.Services.OBS.StatsCollector in child_ids
      assert Task.Supervisor in child_ids
    end

    test "registers supervisor in Registry with session_id" do
      assert {:ok, sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})

      # Supervisor should be findable by session_id
      assert [{^sup_pid, _}] = Registry.lookup(SessionRegistry, @test_session_id)
    end

    test "passes options to child processes" do
      opts = [uri: @test_uri, additional_opt: "test_value"]
      assert {:ok, sup_pid} = OBSSupervisor.start_link({@test_session_id, opts})

      # Verify Connection process received the URI
      assert {:ok, conn_pid} = OBSSupervisor.get_process(@test_session_id, :connection)
      assert Process.alive?(conn_pid)
    end

    test "handles duplicate session_id by returning error" do
      assert {:ok, _sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})

      # Starting another supervisor with same session_id should fail
      assert {:error, {:already_started, _}} =
               OBSSupervisor.start_link({@test_session_id, uri: @test_uri})
    end
  end

  describe "via_tuple/2" do
    test "generates Registry via tuple for supervisor" do
      assert {:via, Registry, {SessionRegistry, "session_123"}} =
               OBSSupervisor.via_tuple("session_123")
    end

    test "generates Registry via tuple for specific process type" do
      assert {:via, Registry, {SessionRegistry, {"session_123", :connection}}} =
               OBSSupervisor.via_tuple("session_123", :connection)

      assert {:via, Registry, {SessionRegistry, {"session_123", :event_handler}}} =
               OBSSupervisor.via_tuple("session_123", :event_handler)
    end
  end

  describe "get_process/2" do
    setup do
      {:ok, _sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})
      :ok
    end

    test "finds registered process by type" do
      # All child processes should be findable
      assert {:ok, conn_pid} = OBSSupervisor.get_process(@test_session_id, :connection)
      assert Process.alive?(conn_pid)

      assert {:ok, event_pid} = OBSSupervisor.get_process(@test_session_id, :event_handler)
      assert Process.alive?(event_pid)

      assert {:ok, tracker_pid} = OBSSupervisor.get_process(@test_session_id, :request_tracker)
      assert Process.alive?(tracker_pid)

      assert {:ok, scene_pid} = OBSSupervisor.get_process(@test_session_id, :scene_manager)
      assert Process.alive?(scene_pid)

      assert {:ok, stream_pid} = OBSSupervisor.get_process(@test_session_id, :stream_manager)
      assert Process.alive?(stream_pid)

      assert {:ok, stats_pid} = OBSSupervisor.get_process(@test_session_id, :stats_collector)
      assert Process.alive?(stats_pid)

      assert {:ok, task_sup_pid} = OBSSupervisor.get_process(@test_session_id, :task_supervisor)
      assert Process.alive?(task_sup_pid)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = OBSSupervisor.get_process("non_existent", :connection)
    end

    test "returns error for non-existent process type" do
      assert {:error, :not_found} = OBSSupervisor.get_process(@test_session_id, :invalid_type)
    end
  end

  describe "whereis/1" do
    test "finds supervisor by session_id" do
      assert {:ok, sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})
      assert ^sup_pid = OBSSupervisor.whereis(@test_session_id)
    end

    test "returns nil for non-existent session" do
      assert nil == OBSSupervisor.whereis("non_existent_session")
    end
  end

  describe "supervision strategy" do
    setup do
      {:ok, sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})
      {:ok, sup_pid: sup_pid}
    end

    test "uses one_for_all strategy", %{sup_pid: sup_pid} do
      # Get initial PIDs
      {:ok, initial_conn_pid} = OBSSupervisor.get_process(@test_session_id, :connection)
      {:ok, initial_event_pid} = OBSSupervisor.get_process(@test_session_id, :event_handler)
      {:ok, initial_scene_pid} = OBSSupervisor.get_process(@test_session_id, :scene_manager)

      # Kill the connection process
      Process.exit(initial_conn_pid, :kill)

      # Wait for supervision tree to restart
      Process.sleep(100)

      # All processes should have restarted with new PIDs
      {:ok, new_conn_pid} = OBSSupervisor.get_process(@test_session_id, :connection)
      {:ok, new_event_pid} = OBSSupervisor.get_process(@test_session_id, :event_handler)
      {:ok, new_scene_pid} = OBSSupervisor.get_process(@test_session_id, :scene_manager)

      # Verify all PIDs changed (one_for_all restart)
      refute initial_conn_pid == new_conn_pid
      refute initial_event_pid == new_event_pid
      refute initial_scene_pid == new_scene_pid

      # Verify all new processes are alive
      assert Process.alive?(new_conn_pid)
      assert Process.alive?(new_event_pid)
      assert Process.alive?(new_scene_pid)
    end

    test "restarts maintain Registry entries", %{sup_pid: sup_pid} do
      # Get initial connection PID
      {:ok, initial_pid} = OBSSupervisor.get_process(@test_session_id, :connection)

      # Kill it
      Process.exit(initial_pid, :kill)

      # Wait for restart
      Process.sleep(100)

      # Should still be findable in Registry
      assert {:ok, new_pid} = OBSSupervisor.get_process(@test_session_id, :connection)
      assert new_pid != initial_pid
      assert Process.alive?(new_pid)
    end
  end

  describe "graceful shutdown" do
    test "stops all children when supervisor stops" do
      {:ok, sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})

      # Get all child PIDs
      {:ok, conn_pid} = OBSSupervisor.get_process(@test_session_id, :connection)
      {:ok, event_pid} = OBSSupervisor.get_process(@test_session_id, :event_handler)
      {:ok, scene_pid} = OBSSupervisor.get_process(@test_session_id, :scene_manager)

      # Monitor children
      conn_ref = Process.monitor(conn_pid)
      event_ref = Process.monitor(event_pid)
      scene_ref = Process.monitor(scene_pid)

      # Stop supervisor
      Supervisor.stop(sup_pid, :shutdown)

      # All children should receive DOWN messages
      assert_receive {:DOWN, ^conn_ref, :process, ^conn_pid, :shutdown}
      assert_receive {:DOWN, ^event_ref, :process, ^event_pid, :shutdown}
      assert_receive {:DOWN, ^scene_ref, :process, ^scene_pid, :shutdown}
    end

    test "cleans up Registry entries on shutdown" do
      {:ok, sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})

      # Verify entries exist
      assert [{^sup_pid, _}] = Registry.lookup(SessionRegistry, @test_session_id)
      assert {:ok, _} = OBSSupervisor.get_process(@test_session_id, :connection)

      # Stop supervisor
      Supervisor.stop(sup_pid, :shutdown)

      # Give Registry time to clean up
      Process.sleep(50)

      # All entries should be gone
      assert [] = Registry.lookup(SessionRegistry, @test_session_id)
      assert {:error, :not_found} = OBSSupervisor.get_process(@test_session_id, :connection)
    end
  end

  describe "child specifications" do
    test "all children have proper restart values" do
      {:ok, sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})

      children = Supervisor.which_children(sup_pid)

      # All children should be permanent workers (except Task.Supervisor)
      for {id, _pid, type, modules} <- children do
        case id do
          Task.Supervisor ->
            assert type == :supervisor
            assert modules == [Task.Supervisor]

          _ ->
            assert type == :worker
            assert length(modules) == 1
        end
      end
    end
  end

  describe "concurrent operations" do
    test "handles concurrent process lookups" do
      {:ok, _sup_pid} = OBSSupervisor.start_link({@test_session_id, uri: @test_uri})

      # Spawn multiple concurrent lookups
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            process_type = Enum.random([:connection, :event_handler, :scene_manager])
            OBSSupervisor.get_process(@test_session_id, process_type)
          end)
        end

      # All lookups should succeed
      results = Task.await_many(tasks)
      assert Enum.all?(results, fn {:ok, pid} -> Process.alive?(pid) end)
    end
  end
end
