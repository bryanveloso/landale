defmodule Server.Services.OBS.SupervisorUnitTest do
  @moduledoc """
  Unit tests for the OBS Supervisor module that don't require child implementations.

  These tests focus on:
  - Via tuple generation
  - Registry key formatting
  - Module functions without starting the supervisor
  """
  use ExUnit.Case, async: true

  alias Server.Services.OBS.Supervisor, as: OBSSupervisor
  alias Server.Services.OBS.SessionRegistry

  describe "via_tuple/2" do
    test "generates correct Registry tuple for supervisor without process type" do
      session_id = "test_session_123"

      assert {:via, Registry, {SessionRegistry, "test_session_123"}} =
               OBSSupervisor.via_tuple(session_id)
    end

    test "generates correct Registry tuple for supervisor with nil process type" do
      session_id = "test_session_456"

      assert {:via, Registry, {SessionRegistry, "test_session_456"}} =
               OBSSupervisor.via_tuple(session_id, nil)
    end

    test "generates correct Registry tuple for specific process type" do
      session_id = "test_session_789"

      assert {:via, Registry, {SessionRegistry, {"test_session_789", :connection}}} =
               OBSSupervisor.via_tuple(session_id, :connection)

      assert {:via, Registry, {SessionRegistry, {"test_session_789", :event_handler}}} =
               OBSSupervisor.via_tuple(session_id, :event_handler)

      assert {:via, Registry, {SessionRegistry, {"test_session_789", :request_tracker}}} =
               OBSSupervisor.via_tuple(session_id, :request_tracker)

      assert {:via, Registry, {SessionRegistry, {"test_session_789", :scene_manager}}} =
               OBSSupervisor.via_tuple(session_id, :scene_manager)

      assert {:via, Registry, {SessionRegistry, {"test_session_789", :stream_manager}}} =
               OBSSupervisor.via_tuple(session_id, :stream_manager)

      assert {:via, Registry, {SessionRegistry, {"test_session_789", :stats_collector}}} =
               OBSSupervisor.via_tuple(session_id, :stats_collector)

      assert {:via, Registry, {SessionRegistry, {"test_session_789", :task_supervisor}}} =
               OBSSupervisor.via_tuple(session_id, :task_supervisor)
    end

    test "handles various session ID formats" do
      # String IDs
      assert {:via, Registry, {SessionRegistry, "simple"}} =
               OBSSupervisor.via_tuple("simple")

      assert {:via, Registry, {SessionRegistry, "with-dashes"}} =
               OBSSupervisor.via_tuple("with-dashes")

      assert {:via, Registry, {SessionRegistry, "with_underscores"}} =
               OBSSupervisor.via_tuple("with_underscores")

      assert {:via, Registry, {SessionRegistry, "with.dots"}} =
               OBSSupervisor.via_tuple("with.dots")

      assert {:via, Registry, {SessionRegistry, "MixedCase123"}} =
               OBSSupervisor.via_tuple("MixedCase123")
    end

    test "via tuple is consistent for same inputs" do
      session_id = "consistent_test"
      process_type = :connection

      tuple1 = OBSSupervisor.via_tuple(session_id, process_type)
      tuple2 = OBSSupervisor.via_tuple(session_id, process_type)
      tuple3 = OBSSupervisor.via_tuple(session_id, process_type)

      assert tuple1 == tuple2
      assert tuple2 == tuple3
    end

    test "different session IDs produce different tuples" do
      tuple1 = OBSSupervisor.via_tuple("session1", :connection)
      tuple2 = OBSSupervisor.via_tuple("session2", :connection)

      refute tuple1 == tuple2
    end

    test "different process types produce different tuples" do
      session_id = "same_session"

      tuple1 = OBSSupervisor.via_tuple(session_id, :connection)
      tuple2 = OBSSupervisor.via_tuple(session_id, :event_handler)

      refute tuple1 == tuple2
    end
  end

  describe "get_process/2 error handling" do
    setup do
      # Start a minimal Registry for testing if not already started
      case Registry.start_link(keys: :unique, name: SessionRegistry) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = OBSSupervisor.get_process("non_existent_session", :connection)
      assert {:error, :not_found} = OBSSupervisor.get_process("another_missing", :event_handler)
    end

    test "returns error for any process type when session doesn't exist" do
      session_id = "missing_session"

      process_types = [
        :connection,
        :event_handler,
        :request_tracker,
        :scene_manager,
        :stream_manager,
        :stats_collector,
        :task_supervisor
      ]

      for process_type <- process_types do
        assert {:error, :not_found} = OBSSupervisor.get_process(session_id, process_type)
      end
    end
  end

  describe "whereis/1 error handling" do
    setup do
      # Start a minimal Registry for testing if not already started
      case Registry.start_link(keys: :unique, name: SessionRegistry) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    test "returns nil for non-existent session" do
      assert nil == OBSSupervisor.whereis("non_existent_session")
      assert nil == OBSSupervisor.whereis("another_missing")
      assert nil == OBSSupervisor.whereis("")
    end
  end

  describe "module attributes and child specifications" do
    test "init/1 returns proper supervisor spec" do
      session_id = "test_init"
      opts = [uri: "ws://localhost:4455"]

      assert {:ok, {sup_flags, children}} = OBSSupervisor.init({session_id, opts})

      # Verify supervisor flags
      assert sup_flags[:strategy] == :one_for_all

      # Verify we have the expected number of children
      assert length(children) == 7

      # Verify each child spec structure
      for child <- children do
        # Child specs can be tuples or maps
        case child do
          {module, _args} ->
            assert is_atom(module)

          %{id: id, start: start} ->
            assert is_atom(id) or is_tuple(id)
            assert is_tuple(start)

          _ ->
            flunk("Unexpected child spec format: #{inspect(child)}")
        end
      end
    end

    test "child modules are in expected order" do
      session_id = "test_order"
      opts = [uri: "ws://localhost:4455"]

      {:ok, {_sup_flags, children}} = OBSSupervisor.init({session_id, opts})

      expected_modules = [
        Server.Services.OBS.Connection,
        Server.Services.OBS.EventHandler,
        Server.Services.OBS.RequestTracker,
        Server.Services.OBS.SceneManager,
        Server.Services.OBS.StreamManager,
        Server.Services.OBS.StatsCollector,
        Task.Supervisor
      ]

      # Extract module IDs from child specs
      actual_modules =
        Enum.map(children, fn
          {module, _args} -> module
          %{id: id} -> id
        end)

      # The last module might have a tuple as ID for Task.Supervisor  
      actual_modules =
        Enum.map(actual_modules, fn
          {Server.Services.OBS.SessionRegistry, {_session_id, :task_supervisor}} ->
            Task.Supervisor

          other ->
            other
        end)

      assert actual_modules == expected_modules
    end

    test "child init args contain proper configuration" do
      session_id = "test_config"
      uri = "ws://test.example.com:4455"
      opts = [uri: uri, extra_opt: "test"]

      {:ok, {_sup_flags, children}} = OBSSupervisor.init({session_id, opts})

      # Check Connection gets proper config
      conn_spec = Enum.at(children, 0)

      # Handle different child spec formats
      conn_args =
        case conn_spec do
          {_module, args} -> args
          %{start: {_module, _fun, [args]}} -> args
        end

      assert Keyword.get(conn_args, :session_id) == session_id
      assert Keyword.get(conn_args, :uri) == uri

      # Check other children get session_id
      for i <- 1..5 do
        child_spec = Enum.at(children, i)

        args =
          case child_spec do
            {_module, args} -> args
            %{start: {_module, _fun, [args]}} -> args
          end

        assert Keyword.get(args, :session_id) == session_id
      end
    end
  end
end
