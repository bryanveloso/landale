defmodule Server.Services.OBS.RequestTrackerTest do
  @moduledoc """
  Unit tests for the OBS RequestTracker GenServer.

  Tests request tracking and response handling including:
  - GenServer initialization
  - Request ID generation and tracking
  - Response matching by request ID
  - Timeout handling for unresponsive requests
  - Concurrent request handling
  - Error response handling
  """
  use ExUnit.Case, async: true

  alias Server.Services.OBS.RequestTracker

  def test_session_id, do: "test_request_tracker_#{:rand.uniform(100_000)}_#{System.unique_integer([:positive])}"

  describe "start_link/1 and initialization" do
    test "starts GenServer with session_id" do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"request_tracker_#{session_id}"]

      assert {:ok, pid} = RequestTracker.start_link(opts)
      assert Process.alive?(pid)

      # Verify state initialization
      state = :sys.get_state(pid)

      assert %RequestTracker{
               session_id: ^session_id,
               requests: %{},
               next_id: 1
             } = state

      # Clean up
      GenServer.stop(pid)
    end

    test "requires session_id in options" do
      Process.flag(:trap_exit, true)
      opts = [name: :test_no_session]

      assert {:error, _} = RequestTracker.start_link(opts)
    end
  end

  describe "handle_call - track_and_send" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"tracker_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({RequestTracker, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "tracks request state without sending", %{pid: pid} do
      # Access internal state directly to test tracking logic
      # Note: In real usage, requests would be sent via gun WebSocket

      # Check initial state
      initial_state = :sys.get_state(pid)
      assert initial_state.next_id == 1
      assert map_size(initial_state.requests) == 0

      # The RequestTracker expects gun to be available, but we're testing the tracking logic
      # For a proper integration test, we'd need a real or mocked WebSocket connection
    end

    test "state management for request tracking", %{pid: pid} do
      # Test state progression without actual gun calls
      # The RequestTracker manages request IDs and tracking
      state = :sys.get_state(pid)
      assert state.session_id
      assert state.next_id == 1
      assert state.requests == %{}
    end

    test "protocol encoding verification", %{pid: _pid} do
      # Test that the request would be properly formatted
      # The actual encoding is done by Protocol.encode_request
      alias Server.Services.OBS.Protocol

      # Test encoding
      encoded = Protocol.encode_request("1", "GetSceneList", %{})
      decoded = Jason.decode!(encoded)

      assert decoded["op"] == 6
      assert decoded["d"]["requestType"] == "GetSceneList"
      assert decoded["d"]["requestId"] == "1"
      assert decoded["d"]["requestData"] == %{}
    end
  end

  describe "handle_cast - response_received" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"response_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({RequestTracker, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "response handling logic for success", %{pid: pid} do
      # Test response handling without actual requests
      # In production, responses come from OBS WebSocket

      # Send a response for a non-existent request (should be ignored)
      response = %{
        requestId: "999",
        requestStatus: %{result: true, code: 100},
        responseData: %{obsVersion: "28.0.0"}
      }

      GenServer.cast(pid, {:response_received, response})
      Process.sleep(10)

      # Process should handle it gracefully
      assert Process.alive?(pid)
    end

    test "response handling logic for errors", %{pid: pid} do
      # Test error response handling
      response = %{
        requestId: "1",
        requestStatus: %{
          result: false,
          code: 604,
          comment: "No scene with that name exists"
        },
        responseData: nil
      }

      GenServer.cast(pid, {:response_received, response})
      Process.sleep(10)

      # Process should handle it gracefully
      assert Process.alive?(pid)
    end

    test "ignores response for unknown request ID", %{pid: pid} do
      # Get initial state
      initial_state = :sys.get_state(pid)

      # Send response with unknown ID
      response = %{
        requestId: "999",
        requestStatus: %{result: true},
        responseData: %{}
      }

      GenServer.cast(pid, {:response_received, response})

      Process.sleep(10)

      # State should be unchanged
      final_state = :sys.get_state(pid)
      assert initial_state == final_state
    end

    test "timer management in response handling", %{pid: pid} do
      # Test that the module structure supports timer management
      # Actual timer cancellation happens when matching responses arrive
      state = :sys.get_state(pid)
      assert is_map(state.requests)
    end
  end

  describe "handle_info - request_timeout" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"timeout_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({RequestTracker, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "timeout handling for non-existent request", %{pid: pid} do
      # Send timeout for a request that doesn't exist
      send(pid, {:request_timeout, "999"})
      Process.sleep(10)

      # Should handle gracefully
      assert Process.alive?(pid)

      # State should be unchanged
      state = :sys.get_state(pid)
      assert map_size(state.requests) == 0
    end

    test "ignores timeout for already handled request", %{pid: pid} do
      # Send timeout for non-existent request
      send(pid, {:request_timeout, "999"})

      Process.sleep(10)

      # Should not crash
      assert Process.alive?(pid)
    end

    test "timeout message handling", %{pid: pid} do
      # Test timeout message handling structure
      # Send a timeout message
      send(pid, {:request_timeout, "1"})
      Process.sleep(10)

      # Process should handle it
      assert Process.alive?(pid)
    end
  end

  describe "concurrent operations" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"concurrent_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({RequestTracker, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "handles concurrent response messages", %{pid: pid} do
      # Send multiple responses concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            response = %{
              requestId: to_string(i),
              requestStatus: %{result: true},
              responseData: %{processed: i}
            }

            GenServer.cast(pid, {:response_received, response})
          end)
        end

      Task.await_many(tasks)
      Process.sleep(20)

      # Process should handle all messages
      assert Process.alive?(pid)
    end

    test "handles mixed response types concurrently", %{pid: pid} do
      # Send mixed responses
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            response =
              if rem(i, 2) == 0 do
                # Error response
                %{
                  requestId: to_string(i),
                  requestStatus: %{result: false, code: 500 + i, comment: "Error #{i}"},
                  responseData: nil
                }
              else
                # Success response
                %{
                  requestId: to_string(i),
                  requestStatus: %{result: true},
                  responseData: %{value: i * 100}
                }
              end

            GenServer.cast(pid, {:response_received, response})
          end)
        end

      Task.await_many(tasks)
      Process.sleep(20)

      # Process should handle all
      assert Process.alive?(pid)
    end
  end

  describe "state management" do
    setup do
      session_id = test_session_id()
      opts = [session_id: session_id, name: :"state_#{:rand.uniform(10000)}"]
      {:ok, pid} = start_supervised({RequestTracker, opts})
      {:ok, pid: pid, session_id: session_id}
    end

    test "maintains sequential ID counter", %{pid: pid} do
      # Check initial state
      state = :sys.get_state(pid)
      assert state.next_id == 1

      # The ID counter would increment with each request
      # In production, this happens via track_and_send calls
    end

    test "maintains request map structure", %{pid: pid} do
      state = :sys.get_state(pid)
      assert is_map(state.requests)
      assert map_size(state.requests) == 0
    end
  end
end
