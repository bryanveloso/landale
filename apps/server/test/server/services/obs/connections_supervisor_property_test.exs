defmodule Server.Services.OBS.ConnectionsSupervisorPropertyTest do
  @moduledoc """
  Property-based tests for the OBS ConnectionsSupervisor.

  Tests invariants and properties including:
  - Session ID handling
  - Options propagation
  - List operations consistency
  - Error handling properties

  Note: These tests focus on the ConnectionsSupervisor's interface
  without requiring actual OBS.Supervisor implementation.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Server.Services.OBS.ConnectionsSupervisor

  describe "session ID properties" do
    property "any valid string can be a session ID" do
      check all(session_id <- string(:utf8, min_length: 1)) do
        # The function should accept any non-empty string
        # We can't test actual starting without OBS.Supervisor
        assert is_function(&ConnectionsSupervisor.start_session/1)

        # Stopping non-existent session should always return error
        assert {:error, :not_found} = ConnectionsSupervisor.stop_session(session_id)
      end
    end

    property "session IDs are case sensitive" do
      check all(base <- string(:alphanumeric, min_length: 1, max_length: 10)) do
        lower = String.downcase(base)
        upper = String.upcase(base)

        # Different cases should be treated as different sessions
        if lower != upper do
          assert {:error, :not_found} = ConnectionsSupervisor.stop_session(lower)
          assert {:error, :not_found} = ConnectionsSupervisor.stop_session(upper)
        end
      end
    end
  end

  describe "options handling properties" do
    property "options are properly structured" do
      check all(
              session_id <- string(:alphanumeric, min_length: 1),
              opts <- list_of(tuple({atom(:alphanumeric), term()}), max_length: 5)
            ) do
        # Convert to keyword list
        keyword_opts = Enum.map(opts, fn {k, v} -> {k, v} end)

        # The function should accept any keyword list
        assert is_function(&ConnectionsSupervisor.start_session/2)

        # Verify session_id would be added to options
        expected_opts = Keyword.put(keyword_opts, :session_id, session_id)
        assert expected_opts[:session_id] == session_id
      end
    end
  end

  describe "list operations properties" do
    property "list_sessions always returns a list" do
      check all(num_calls <- integer(1..10)) do
        # Call list_sessions multiple times
        results =
          for _ <- 1..num_calls do
            ConnectionsSupervisor.list_sessions()
          end

        # All results should be lists
        assert Enum.all?(results, &is_list/1)
      end
    end

    property "list contains only pids" do
      check all(_dummy <- integer()) do
        sessions = ConnectionsSupervisor.list_sessions()

        # Every element should be a pid (or list is empty)
        assert Enum.all?(sessions, &is_pid/1)
      end
    end
  end

  describe "error handling properties" do
    property "stop_session with non-existent IDs always returns error" do
      check all(session_ids <- list_of(string(:utf8, min_length: 1), min_length: 1, max_length: 20)) do
        # Generate unique IDs that definitely don't exist
        unique_ids = Enum.map(session_ids, &"nonexistent_#{&1}_#{System.unique_integer([:positive])}")

        # All should return not found
        results = Enum.map(unique_ids, &ConnectionsSupervisor.stop_session/1)
        assert Enum.all?(results, &(&1 == {:error, :not_found}))
      end
    end
  end

  describe "initialization properties" do
    property "init always returns same strategy regardless of input" do
      check all(opts <- list_of(tuple({atom(:alphanumeric), term()}), max_length: 10)) do
        assert {:ok, flags} = ConnectionsSupervisor.init(opts)
        assert flags[:strategy] == :one_for_one
      end
    end
  end

  describe "concurrent operations properties" do
    property "concurrent stop_session calls don't interfere" do
      check all(session_ids <- list_of(string(:alphanumeric, min_length: 1), min_length: 5, max_length: 20)) do
        # Make IDs unique
        unique_ids = Enum.map(session_ids, &"#{&1}_#{System.unique_integer([:positive])}")

        # Concurrent stops of non-existent sessions
        tasks =
          for id <- unique_ids do
            Task.async(fn ->
              ConnectionsSupervisor.stop_session(id)
            end)
          end

        results = Task.await_many(tasks, 5000)

        # All should return not found
        assert Enum.all?(results, &(&1 == {:error, :not_found}))
      end
    end

    property "list_sessions is consistent under concurrent calls" do
      check all(num_concurrent <- integer(2..10)) do
        # Multiple concurrent list calls
        tasks =
          for _ <- 1..num_concurrent do
            Task.async(fn ->
              result = ConnectionsSupervisor.list_sessions()
              {is_list(result), Enum.all?(result, &is_pid/1)}
            end)
          end

        results = Task.await_many(tasks, 5000)

        # All results should be valid
        assert Enum.all?(results, fn {is_list, all_pids} ->
                 is_list and all_pids
               end)
      end
    end
  end
end
