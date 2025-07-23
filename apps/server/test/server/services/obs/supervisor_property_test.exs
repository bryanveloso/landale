defmodule Server.Services.OBS.SupervisorPropertyTest do
  @moduledoc """
  Property-based tests for the OBS WebSocket session supervisor.

  Tests invariants and properties including:
  - Supervision tree consistency
  - Registry integrity under concurrent operations
  - Process discovery reliability
  - Restart behavior properties
  - Resource cleanup guarantees
  """
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Server.Services.OBS.Supervisor, as: OBSSupervisor
  alias Server.Services.OBS.SessionRegistry

  # Skip these tests until child modules are implemented
  @moduletag :skip

  setup do
    # Ensure Registry is started
    case Registry.start_link(keys: :unique, name: SessionRegistry) do
      {:ok, registry} ->
        on_exit(fn -> Process.exit(registry, :shutdown) end)
        :ok

      {:error, {:already_started, _}} ->
        :ok
    end
  end

  describe "session management properties" do
    property "unique session IDs always create separate supervisors" do
      check all(
              session_ids <- uniq_list_of(session_id_gen(), min_length: 1, max_length: 5),
              uri <- uri_gen()
            ) do
        # Start supervisors
        supervisors =
          for session_id <- session_ids do
            {:ok, pid} = OBSSupervisor.start_link({session_id, uri: uri})
            {session_id, pid}
          end

        # All supervisors should be different processes
        pids = Enum.map(supervisors, fn {_, pid} -> pid end)
        assert length(pids) == length(Enum.uniq(pids))

        # Each should be findable by its session_id
        for {session_id, expected_pid} <- supervisors do
          assert ^expected_pid = OBSSupervisor.whereis(session_id)
        end

        # Clean up
        for {_, pid} <- supervisors do
          Supervisor.stop(pid, :shutdown)
        end
      end
    end

    property "process types are consistently registered" do
      check all(
              session_id <- session_id_gen(),
              uri <- uri_gen()
            ) do
        {:ok, sup_pid} = OBSSupervisor.start_link({session_id, uri: uri})

        process_types = [
          :connection,
          :event_handler,
          :request_tracker,
          :scene_manager,
          :stream_manager,
          :stats_collector,
          :task_supervisor
        ]

        # All process types should be findable
        for process_type <- process_types do
          assert {:ok, pid} = OBSSupervisor.get_process(session_id, process_type)
          assert Process.alive?(pid)
        end

        # Clean up
        Supervisor.stop(sup_pid, :shutdown)
      end
    end
  end

  describe "via tuple properties" do
    property "via tuples are deterministic" do
      check all(
              session_id <- session_id_gen(),
              process_type <- process_type_gen()
            ) do
        # Same inputs always produce same via tuple
        tuple1 = OBSSupervisor.via_tuple(session_id, process_type)
        tuple2 = OBSSupervisor.via_tuple(session_id, process_type)
        assert tuple1 == tuple2

        # Structure is always consistent
        assert {:via, Registry, {SessionRegistry, _name}} = tuple1
      end
    end

    property "via tuples preserve session_id and process_type" do
      check all(
              session_id <- session_id_gen(),
              process_type <- process_type_gen()
            ) do
        {:via, Registry, {SessionRegistry, name}} = OBSSupervisor.via_tuple(session_id, process_type)

        # Name should contain both session_id and process_type when process_type is provided
        if process_type do
          assert {^session_id, ^process_type} = name
        else
          assert ^session_id = name
        end
      end
    end
  end

  describe "concurrent access properties" do
    property "concurrent process lookups return consistent results" do
      check all(
              session_id <- session_id_gen(),
              uri <- uri_gen(),
              num_lookups <- integer(10..50)
            ) do
        {:ok, _sup_pid} = OBSSupervisor.start_link({session_id, uri: uri})

        # Get expected PIDs
        expected_pids =
          for process_type <- [:connection, :event_handler, :scene_manager] do
            {:ok, pid} = OBSSupervisor.get_process(session_id, process_type)
            {process_type, pid}
          end
          |> Map.new()

        # Perform concurrent lookups
        tasks =
          for _ <- 1..num_lookups do
            process_type = Enum.random([:connection, :event_handler, :scene_manager])

            Task.async(fn ->
              {:ok, pid} = OBSSupervisor.get_process(session_id, process_type)
              {process_type, pid}
            end)
          end

        results = Task.await_many(tasks)

        # All lookups should return the same PID for each process type
        for {process_type, pid} <- results do
          assert pid == expected_pids[process_type]
        end

        # Clean up
        Supervisor.stop(OBSSupervisor.whereis(session_id), :shutdown)
      end
    end

    property "Registry entries remain consistent under concurrent operations" do
      check all(
              session_ids <- uniq_list_of(session_id_gen(), min_length: 2, max_length: 5),
              uri <- uri_gen()
            ) do
        # Start multiple supervisors
        for session_id <- session_ids do
          {:ok, _} = OBSSupervisor.start_link({session_id, uri: uri})
        end

        # Concurrent operations
        tasks =
          for _ <- 1..50 do
            session_id = Enum.random(session_ids)
            operation = Enum.random([:whereis, :get_process])

            Task.async(fn ->
              case operation do
                :whereis ->
                  pid = OBSSupervisor.whereis(session_id)
                  {session_id, :whereis, pid}

                :get_process ->
                  result = OBSSupervisor.get_process(session_id, :connection)
                  {session_id, :get_process, result}
              end
            end)
          end

        results = Task.await_many(tasks)

        # Group results by session_id
        by_session =
          Enum.group_by(results, fn {session_id, _, _} -> session_id end)

        # Verify consistency within each session
        for {session_id, session_results} <- by_session do
          whereis_pids =
            session_results
            |> Enum.filter(fn {_, op, _} -> op == :whereis end)
            |> Enum.map(fn {_, _, pid} -> pid end)
            |> Enum.uniq()

          # All whereis calls should return the same PID
          assert length(whereis_pids) == 1
          assert Enum.all?(whereis_pids, &Process.alive?/1)
        end

        # Clean up
        for session_id <- session_ids do
          if pid = OBSSupervisor.whereis(session_id) do
            Supervisor.stop(pid, :shutdown)
          end
        end
      end
    end
  end

  describe "lifecycle properties" do
    property "stopping supervisor cleans up all Registry entries" do
      check all(
              session_id <- session_id_gen(),
              uri <- uri_gen()
            ) do
        {:ok, sup_pid} = OBSSupervisor.start_link({session_id, uri: uri})

        # Collect all Registry entries for this session
        process_types = [:connection, :event_handler, :scene_manager, :stream_manager]

        initial_entries =
          for process_type <- process_types do
            case Registry.lookup(SessionRegistry, {session_id, process_type}) do
              [{pid, _}] -> {process_type, pid}
              [] -> nil
            end
          end
          |> Enum.reject(&is_nil/1)

        # Should have entries for all process types
        assert length(initial_entries) == length(process_types)

        # Stop supervisor
        Supervisor.stop(sup_pid, :shutdown)
        Process.sleep(50)

        # All Registry entries should be cleaned up
        for process_type <- process_types do
          assert [] = Registry.lookup(SessionRegistry, {session_id, process_type})
        end

        # Main supervisor entry should also be gone
        assert [] = Registry.lookup(SessionRegistry, session_id)
      end
    end

    property "restart behavior maintains process relationships" do
      check all(
              session_id <- session_id_gen(),
              uri <- uri_gen(),
              process_to_kill <- process_type_gen()
            ) do
        # Skip if we would kill the task supervisor
        if process_to_kill == :task_supervisor do
          :ok
        else
          {:ok, _sup_pid} = OBSSupervisor.start_link({session_id, uri: uri})

          # Get initial PIDs
          {:ok, initial_killed} = OBSSupervisor.get_process(session_id, process_to_kill)
          {:ok, initial_other} = OBSSupervisor.get_process(session_id, :connection)

          # Kill one process
          Process.exit(initial_killed, :kill)
          Process.sleep(100)

          # Due to one_for_all strategy, all processes should have restarted
          {:ok, new_killed} = OBSSupervisor.get_process(session_id, process_to_kill)
          {:ok, new_other} = OBSSupervisor.get_process(session_id, :connection)

          # Both should have new PIDs
          assert initial_killed != new_killed
          assert initial_other != new_other

          # Both should be alive
          assert Process.alive?(new_killed)
          assert Process.alive?(new_other)

          # Clean up
          Supervisor.stop(OBSSupervisor.whereis(session_id), :shutdown)
        end
      end
    end
  end

  describe "error handling properties" do
    property "invalid session lookups always return consistent errors" do
      check all(
              invalid_session <- session_id_gen(),
              process_type <- process_type_gen()
            ) do
        # Without starting a supervisor, lookups should fail consistently
        assert {:error, :not_found} = OBSSupervisor.get_process(invalid_session, process_type)
        assert nil == OBSSupervisor.whereis(invalid_session)
      end
    end

    property "duplicate session starts are handled gracefully" do
      check all(
              session_id <- session_id_gen(),
              uri <- uri_gen()
            ) do
        {:ok, pid1} = OBSSupervisor.start_link({session_id, uri: uri})

        # Second start should fail
        result = OBSSupervisor.start_link({session_id, uri: uri})
        assert {:error, {:already_started, _}} = result

        # Original should still be running
        assert Process.alive?(pid1)
        assert ^pid1 = OBSSupervisor.whereis(session_id)

        # Clean up
        Supervisor.stop(pid1, :shutdown)
      end
    end
  end

  # Generator functions

  defp session_id_gen do
    map({string(:alphanumeric, min_length: 1), integer(1..10000)}, fn {prefix, num} ->
      "#{prefix}_#{num}"
    end)
  end

  defp uri_gen do
    one_of([
      constant("ws://localhost:4455"),
      constant("ws://127.0.0.1:4455"),
      constant("ws://obs-server:4455")
    ])
  end

  defp process_type_gen do
    one_of([
      constant(:connection),
      constant(:event_handler),
      constant(:request_tracker),
      constant(:scene_manager),
      constant(:stream_manager),
      constant(:stats_collector),
      constant(:task_supervisor),
      constant(nil)
    ])
  end
end
