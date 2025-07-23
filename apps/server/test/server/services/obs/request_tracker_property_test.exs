defmodule Server.Services.OBS.RequestTrackerPropertyTest do
  @moduledoc """
  Property-based tests for the OBS RequestTracker.

  Tests invariants and properties including:
  - State consistency
  - Response handling preserves state invariants
  - Concurrent operations maintain consistency
  - Message handling is robust

  Note: These tests focus on the RequestTracker's internal logic
  without requiring actual gun WebSocket connections.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Server.Services.OBS.RequestTracker

  describe "state consistency properties" do
    property "state fields maintain valid types" do
      check all(
              session_id <- session_id_gen(),
              num_operations <- integer(0..20)
            ) do
        name = :"tracker_prop_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = RequestTracker.start_link(opts)

        # Perform random operations
        for _ <- 1..num_operations do
          case :rand.uniform(3) do
            1 ->
              # Send a response for a random request ID
              response = %{
                requestId: to_string(:rand.uniform(100)),
                requestStatus: %{result: Enum.random([true, false])},
                responseData: %{}
              }

              GenServer.cast(pid, {:handle_response, response})

            2 ->
              # Send a timeout for a random request ID
              send(pid, {:request_timeout, to_string(:rand.uniform(100))})

            3 ->
              # Just check state
              state = :sys.get_state(pid)
              assert is_binary(state.session_id)
              assert is_map(state.requests)
              assert is_integer(state.next_id) and state.next_id >= 1
          end
        end

        Process.sleep(20)

        # Final state check
        final_state = :sys.get_state(pid)
        assert is_binary(final_state.session_id)
        assert is_map(final_state.requests)
        assert is_integer(final_state.next_id) and final_state.next_id >= 1

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "response handling properties" do
    property "responses for unknown requests are handled gracefully" do
      check all(
              session_id <- session_id_gen(),
              responses <- list_of(response_gen(), min_length: 1, max_length: 20)
            ) do
        name = :"tracker_response_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = RequestTracker.start_link(opts)

        # Send all responses (for non-existent requests)
        for response <- responses do
          GenServer.cast(pid, {:handle_response, response})
        end

        Process.sleep(20)

        # Process should still be alive
        assert Process.alive?(pid)

        # State should be consistent
        state = :sys.get_state(pid)
        assert is_map(state.requests)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end

    property "error responses are handled correctly" do
      check all(
              session_id <- session_id_gen(),
              error_responses <- list_of(error_response_gen(), min_length: 1, max_length: 10)
            ) do
        name = :"tracker_error_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = RequestTracker.start_link(opts)

        # Send error responses
        for {error_data, idx} <- Enum.with_index(error_responses, 1) do
          response = %{
            requestId: to_string(idx),
            requestStatus: error_data,
            responseData: nil
          }

          GenServer.cast(pid, {:handle_response, response})
        end

        Process.sleep(20)

        # Process should handle all errors gracefully
        assert Process.alive?(pid)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "timeout handling properties" do
    property "timeout messages for unknown requests are ignored" do
      check all(
              session_id <- session_id_gen(),
              timeout_ids <- list_of(string(:alphanumeric, min_length: 1), min_length: 1, max_length: 20)
            ) do
        name = :"tracker_timeout_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = RequestTracker.start_link(opts)

        # Send timeout messages for non-existent requests
        for request_id <- timeout_ids do
          send(pid, {:request_timeout, request_id})
        end

        Process.sleep(20)

        # Process should handle all gracefully
        assert Process.alive?(pid)

        # State should remain clean
        state = :sys.get_state(pid)
        assert map_size(state.requests) == 0

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "concurrent message handling properties" do
    property "concurrent messages don't corrupt state" do
      check all(
              session_id <- session_id_gen(),
              messages <- list_of(message_gen(), min_length: 5, max_length: 30)
            ) do
        name = :"tracker_concurrent_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = RequestTracker.start_link(opts)

        # Send messages concurrently
        tasks =
          for msg <- messages do
            Task.async(fn ->
              case msg do
                {:response, response} ->
                  GenServer.cast(pid, {:handle_response, response})

                {:timeout, request_id} ->
                  send(pid, {:request_timeout, request_id})
              end
            end)
          end

        Task.await_many(tasks, 5000)
        Process.sleep(50)

        # Process should still be alive and consistent
        assert Process.alive?(pid)

        state = :sys.get_state(pid)
        assert is_binary(state.session_id)
        assert is_map(state.requests)
        assert is_integer(state.next_id)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  describe "state evolution properties" do
    property "next_id never decreases" do
      check all(
              session_id <- session_id_gen(),
              num_checks <- integer(5..20)
            ) do
        name = :"tracker_id_#{session_id}_#{:rand.uniform(10000)}"
        opts = [session_id: session_id, name: name]
        {:ok, pid} = RequestTracker.start_link(opts)

        # Track next_id values
        next_ids =
          for _ <- 1..num_checks do
            # Do some random operations
            if :rand.uniform(2) == 1 do
              response = %{
                requestId: to_string(:rand.uniform(1000)),
                requestStatus: %{result: true},
                responseData: %{}
              }

              GenServer.cast(pid, {:handle_response, response})
            end

            Process.sleep(5)

            state = :sys.get_state(pid)
            state.next_id
          end

        # Verify next_id never decreases
        next_ids
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [a, b] ->
          assert a <= b
        end)

        GenServer.stop(pid)
        Process.sleep(10)
      end
    end
  end

  # Generator functions

  defp session_id_gen do
    map(string(:alphanumeric, min_length: 1, max_length: 10), fn prefix ->
      "#{prefix}_#{System.unique_integer([:positive])}_#{:erlang.phash2(make_ref())}"
    end)
  end

  defp response_gen do
    map(
      {integer(1..999), boolean(), map_of(atom(:alphanumeric), term())},
      fn {id, result, data} ->
        %{
          requestId: to_string(id),
          requestStatus: %{result: result},
          responseData: if(result, do: data, else: nil)
        }
      end
    )
  end

  defp error_response_gen do
    map({integer(400..699), string(:alphanumeric, min_length: 5)}, fn {code, comment} ->
      %{
        result: false,
        code: code,
        comment: comment
      }
    end)
  end

  defp message_gen do
    one_of([
      map(response_gen(), fn response -> {:response, response} end),
      map(string(:alphanumeric, min_length: 1, max_length: 5), fn id -> {:timeout, id} end)
    ])
  end
end
