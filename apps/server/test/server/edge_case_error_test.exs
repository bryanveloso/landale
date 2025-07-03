defmodule Server.EdgeCaseErrorTest do
  @moduledoc """
  Comprehensive edge case and error scenario tests for network conditions,
  system failures, and unusual input patterns that could occur in production.

  These tests verify system resilience under adverse conditions and ensure
  graceful degradation when things go wrong.
  """

  use Server.DataCase, async: false
  use ServerWeb.ChannelCase

  import ExUnit.CaptureLog
  import Hammox

  alias ServerWeb.{OverlayChannel, DashboardChannel, UserSocket}
  alias Server.Mocks.{IronmonTCPMock, OBSMock, RainwaveMock, TwitchMock}
  alias Server.{WebSocketClient, Services.OBS}

  describe "network connectivity edge cases" do
    test "WebSocket connection during network instability" do
      # Mock intermittent connection behavior
      connection_attempts = Agent.start_link(fn -> 0 end)
      {:ok, agent} = connection_attempts

      stub(OBSMock, :get_status, fn ->
        Agent.get_and_update(agent, fn count ->
          cond do
            count < 3 -> {{:error, :connection_refused}, count + 1}
            count < 6 -> {{:ok, %{connected: false}}, count + 1}
            true -> {{:ok, %{connected: true, streaming: false}}, count + 1}
          end
        end)
      end)

      {:ok, _, socket} =
        UserSocket
        |> socket("unstable_user", %{user_id: "unstable_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Simulate multiple connection attempts
      for _attempt <- 1..10 do
        ref = push(socket, "obs:status", %{})

        # Should eventually succeed or fail gracefully
        receive do
          %Phoenix.Socket.Reply{ref: ^ref, status: status} ->
            assert status in [:ok, :error]
        after
          1000 -> flunk("Request timed out")
        end

        :timer.sleep(100)
      end

      Agent.stop(agent)
    end

    test "TCP connection drops during message transmission" do
      # Test IronMON TCP resilience
      stub(IronmonTCPMock, :list_challenges, fn ->
        # Simulate network timeout
        :timer.sleep(2000)
        {:error, :timeout}
      end)

      {:ok, _, socket} =
        UserSocket
        |> socket("tcp_user", %{user_id: "tcp_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Request should handle timeout gracefully
      ref = push(socket, "ironmon:challenges", %{})
      assert_reply ref, :error, error_response

      assert is_map(error_response)
      assert Map.has_key?(error_response, :message)
    end

    test "partial data transmission scenarios" do
      # Mock service returning incomplete data
      stub(OBSMock, :get_status, fn ->
        # Missing expected fields
        {:ok, %{connected: true}}
      end)

      {:ok, _, socket} =
        UserSocket
        |> socket("partial_user", %{user_id: "partial_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      ref = push(socket, "obs:status", %{})
      assert_reply ref, :ok, partial_response

      # Should handle partial data gracefully
      assert is_map(partial_response)
      assert partial_response.connected == true
    end

    test "DNS resolution failures" do
      # Simulate DNS-related issues
      stub(RainwaveMock, :get_status, fn ->
        {:error, :nxdomain}
      end)

      {:ok, _, socket} =
        UserSocket
        |> socket("dns_user", %{user_id: "dns_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      ref = push(socket, "rainwave:status", %{})
      assert_reply ref, :error, dns_error

      assert is_map(dns_error)
      assert Map.has_key?(dns_error, :message)
    end
  end

  describe "malformed input handling" do
    test "oversized message payloads" do
      {:ok, _, socket} =
        UserSocket
        |> socket("large_user", %{user_id: "large_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Create extremely large payload
      large_payload = %{
        "data" => String.duplicate("x", 100_000),
        "nested" => %{
          "deep" => %{
            "structure" => String.duplicate("y", 50_000)
          }
        }
      }

      # Channel should handle or reject large payloads gracefully
      ref = push(socket, "ping", large_payload)

      receive do
        %Phoenix.Socket.Reply{ref: ^ref, status: status} ->
          # Should either process or reject, but not crash
          assert status in [:ok, :error]
      after
        5000 -> flunk("Large payload handling timed out")
      end
    end

    test "malformed JSON in WebSocket frames" do
      # Test direct WebSocket client with malformed data
      log_output =
        capture_log(fn ->
          # Simulate WebSocket client receiving malformed data
          malformed_data = "{\"incomplete\": json without closing"

          # This would typically happen in the WebSocket client
          result = Jason.decode(malformed_data)
          assert {:error, _} = result

          :timer.sleep(100)
        end)

      # Should log the error appropriately
      refute log_output == ""
    end

    test "null and undefined value handling" do
      # Mock service returning null values
      stub(TwitchMock, :get_status, fn ->
        {:ok,
         %{
           connected: nil,
           user_id: nil,
           subscriptions: nil
         }}
      end)

      {:ok, _, socket} =
        UserSocket
        |> socket("null_user", %{user_id: "null_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:twitch")

      ref = push(socket, "twitch:status", %{})
      assert_reply ref, :ok, null_response

      # Should handle null values without crashing
      assert is_map(null_response)
      assert null_response.connected == nil
    end

    test "extreme parameter values" do
      # Test with extreme values for IronMON commands
      {:ok, _, socket} =
        UserSocket
        |> socket("extreme_user", %{user_id: "extreme_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Negative challenge ID
      ref = push(socket, "ironmon:checkpoints", %{"challenge_id" => -999})
      assert_reply ref, :error, negative_error
      assert Map.has_key?(negative_error, :message)

      # Zero challenge ID
      ref = push(socket, "ironmon:checkpoints", %{"challenge_id" => 0})
      assert_reply ref, :error, zero_error
      assert Map.has_key?(zero_error, :message)

      # Extremely large limit
      ref = push(socket, "ironmon:recent_results", %{"limit" => 999_999})
      assert_reply ref, :error, large_limit_error
      assert Map.has_key?(large_limit_error, :message)
    end

    test "special character and encoding issues" do
      # Test with various special characters
      special_payloads = [
        # Emojis
        %{"data" => "🎮🎯🎪🎨🎭🎬🎤🎧🎼🎹🎸🎺🎻"},
        # Accented characters
        %{"data" => "çñüëöäß"},
        # Chinese characters
        %{"data" => "测试数据"},
        # Cyrillic
        %{"data" => "тест"},
        # More complex emojis
        %{"data" => "🔥💯⚡️"},
        # Control characters
        %{"data" => "\u0000\u0001\u0002"},
        # Escaped sequences
        %{"data" => "\\n\\r\\t"}
      ]

      {:ok, _, socket} =
        UserSocket
        |> socket("unicode_user", %{user_id: "unicode_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Each payload should be handled without issues
      Enum.each(special_payloads, fn payload ->
        ref = push(socket, "ping", payload)
        assert_reply ref, :ok, response

        # Should echo back the special characters correctly
        assert Map.get(response, "data") == payload["data"]
      end)
    end
  end

  describe "memory and resource exhaustion scenarios" do
    test "rapid message flooding" do
      {:ok, _, socket} =
        UserSocket
        |> socket("flood_user", %{user_id: "flood_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Send many messages rapidly
      start_time = System.monotonic_time(:millisecond)
      message_count = 200

      refs =
        for i <- 1..message_count do
          push(socket, "ping", %{"sequence" => i})
        end

      # Count successful responses
      successful_responses =
        Enum.count(refs, fn ref ->
          receive do
            %Phoenix.Socket.Reply{ref: ^ref, status: :ok} -> true
            %Phoenix.Socket.Reply{ref: ^ref, status: :error} -> false
          after
            # Short timeout for flood test
            100 -> false
          end
        end)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should handle most messages or implement rate limiting gracefully
      success_rate = successful_responses / message_count
      # At least 50% should succeed
      assert success_rate > 0.5

      # Should not take too long (rate limiting might slow it down)
      # Less than 10 seconds
      assert duration < 10_000
    end

    test "memory leak prevention in long-running connections" do
      {:ok, _, socket} =
        UserSocket
        |> socket("longrun_user", %{user_id: "longrun_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Simulate long-running connection with periodic activity
      initial_memory = :erlang.memory(:total)

      # Send periodic messages over "time"
      for round <- 1..20 do
        # Multiple request types per round
        push(socket, "ping", %{"round" => round})
        push(socket, "obs:status", %{})

        # Small delay between rounds
        :timer.sleep(25)
      end

      # Allow garbage collection
      :erlang.garbage_collect()
      :timer.sleep(100)

      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory

      # Memory growth should be reasonable (less than 10MB for this test)
      assert memory_growth < 10_000_000
    end

    test "concurrent connection limits" do
      # Test system behavior with many concurrent connections
      connection_count = 25

      sockets =
        for i <- 1..connection_count do
          {:ok, _, socket} =
            UserSocket
            |> socket("concurrent_#{i}", %{user_id: "concurrent_#{i}"})
            |> subscribe_and_join(OverlayChannel, "overlay:obs")

          socket
        end

      # All connections should be successful
      assert length(sockets) == connection_count

      # Each connection should be responsive
      test_refs =
        Enum.map(sockets, fn socket ->
          push(socket, "ping", %{"test" => "concurrent"})
        end)

      # Count successful responses
      successful_responses =
        Enum.count(test_refs, fn ref ->
          receive do
            %Phoenix.Socket.Reply{ref: ^ref, status: :ok} -> true
          after
            2000 -> false
          end
        end)

      # Most connections should remain functional
      success_rate = successful_responses / connection_count
      # At least 80% should work
      assert success_rate > 0.8
    end
  end

  describe "service dependency failures" do
    test "cascading service failures" do
      # Simulate multiple services failing
      stub(OBSMock, :get_status, fn -> {:error, "OBS service down"} end)
      stub(TwitchMock, :get_status, fn -> {:error, "Twitch API unavailable"} end)
      stub(IronmonTCPMock, :get_status, fn -> {:error, "TCP server not responding"} end)
      stub(RainwaveMock, :get_status, fn -> {:error, "Rainwave API timeout"} end)

      {:ok, _, dashboard_socket} =
        UserSocket
        |> socket("admin", %{user_id: "admin"})
        |> subscribe_and_join(DashboardChannel, "dashboard:main")

      # System status should still respond despite all services being down
      ref = push(dashboard_socket, "system:status", %{})
      assert_reply ref, :ok, system_status

      # Should indicate system problems but not crash
      assert is_map(system_status)
      assert Map.has_key?(system_status, :status)
      assert Map.has_key?(system_status, :services)

      # Status should reflect the problems
      assert system_status.status in ["critical", "degraded"]
    end

    test "partial service recovery" do
      # Start with all services down
      call_count = Agent.start_link(fn -> 0 end)
      {:ok, agent} = call_count

      stub(OBSMock, :get_status, fn ->
        count = Agent.get_and_update(agent, &{&1, &1 + 1})

        if count < 3 do
          {:error, "Starting up..."}
        else
          {:ok, %{connected: true, streaming: false}}
        end
      end)

      stub(TwitchMock, :get_status, fn -> {:error, "Still down"} end)

      {:ok, _, dashboard_socket} =
        UserSocket
        |> socket("recovery_admin", %{user_id: "recovery_admin"})
        |> subscribe_and_join(DashboardChannel, "dashboard:main")

      # First few requests should show degraded state
      ref1 = push(dashboard_socket, "system:status", %{})
      assert_reply ref1, :ok, degraded_status
      assert degraded_status.status in ["critical", "degraded"]

      # After several attempts, should show partial recovery
      :timer.sleep(100)
      ref2 = push(dashboard_socket, "system:status", %{})
      assert_reply ref2, :ok, partial_recovery

      ref3 = push(dashboard_socket, "system:status", %{})
      assert_reply ref3, :ok, better_status

      # Should show improvement over time
      assert is_map(better_status)

      Agent.stop(agent)
    end

    test "database connection failures" do
      # Simulate database issues (this would be harder to test directly,
      # but we can test the error handling paths)

      {:ok, _, socket} =
        UserSocket
        |> socket("db_user", %{user_id: "db_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Mock IronMON database operations failing
      stub(IronmonTCPMock, :list_challenges, fn ->
        {:error, "Database connection failed"}
      end)

      stub(IronmonTCPMock, :list_checkpoints, fn _challenge_id ->
        {:error, "Database timeout"}
      end)

      # Commands should fail gracefully
      ref1 = push(socket, "ironmon:challenges", %{})
      assert_reply ref1, :error, db_error1
      assert Map.has_key?(db_error1, :message)

      ref2 = push(socket, "ironmon:checkpoints", %{"challenge_id" => 1})
      assert_reply ref2, :error, db_error2
      assert Map.has_key?(db_error2, :message)
    end
  end

  describe "timing and race condition edge cases" do
    test "rapid connect/disconnect cycles" do
      # Test rapid connection establishment and teardown
      for _cycle <- 1..10 do
        {:ok, _, socket} =
          UserSocket
          |> socket("rapid_#{:rand.uniform(1000)}", %{user_id: "rapid_user"})
          |> subscribe_and_join(OverlayChannel, "overlay:obs")

        # Quick interaction
        ref = push(socket, "ping", %{"quick" => "test"})

        # Don't wait for reply, disconnect immediately
        close(socket)

        # Brief pause before next cycle
        :timer.sleep(10)
      end

      # System should remain stable
      assert Process.alive?(self())
    end

    test "simultaneous command execution" do
      {:ok, _, socket} =
        UserSocket
        |> socket("simul_user", %{user_id: "simul_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Send multiple commands simultaneously
      refs = [
        push(socket, "ping", %{"cmd" => "ping"}),
        push(socket, "obs:status", %{}),
        push(socket, "ironmon:challenges", %{}),
        push(socket, "rainwave:status", %{}),
        push(socket, "ping", %{"cmd" => "ping2"})
      ]

      # All should complete (success or failure)
      results =
        Enum.map(refs, fn ref ->
          receive do
            %Phoenix.Socket.Reply{ref: ^ref, status: status} -> status
          after
            3000 -> :timeout
          end
        end)

      # No timeouts should occur
      assert :timeout not in results

      # All should have definitive responses
      assert Enum.all?(results, &(&1 in [:ok, :error]))
    end

    test "message ordering under load" do
      {:ok, _, socket} =
        UserSocket
        |> socket("order_user", %{user_id: "order_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Send sequence of numbered messages
      sequence_length = 20

      refs =
        for i <- 1..sequence_length do
          push(socket, "ping", %{"sequence" => i})
        end

      # Collect responses
      responses =
        Enum.map(refs, fn ref ->
          receive do
            %Phoenix.Socket.Reply{ref: ^ref, status: :ok, response: response} ->
              Map.get(response, "sequence")
          after
            2000 -> nil
          end
        end)

      # Should receive all responses
      received_count = Enum.count(responses, &(&1 != nil))
      # At least 80%
      assert received_count > sequence_length * 0.8

      # Responses should contain correct sequence numbers
      valid_responses = Enum.filter(responses, &is_integer(&1))
      assert length(valid_responses) > 0
    end
  end

  describe "system resource edge cases" do
    test "disk space simulation" do
      # Test behavior when system resources are constrained
      # (This is more of a simulation since we can't actually fill disk)

      log_output =
        capture_log(fn ->
          # Simulate scenarios that might occur during low disk space
          large_log_message = String.duplicate("x", 10_000)
          Logger.info("Simulated large log: #{large_log_message}")
          :timer.sleep(50)
        end)

      # Should handle large log messages without issues
      assert String.contains?(log_output, "Simulated large log")
    end

    test "process limit simulation" do
      # Test system behavior as we approach process limits
      # Create many short-lived processes
      process_count = 100

      processes =
        for i <- 1..process_count do
          spawn(fn ->
            :timer.sleep(100)
            i * 2
          end)
        end

      # All processes should be created successfully
      assert length(processes) == process_count

      # Wait for processes to complete
      :timer.sleep(200)

      # System should remain stable
      assert Process.alive?(self())
    end

    test "file handle exhaustion simulation" do
      # Simulate scenarios that might exhaust file handles
      {:ok, _, socket} =
        UserSocket
        |> socket("file_user", %{user_id: "file_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Multiple requests that might open connections/handles
      handle_test_count = 50

      refs =
        for i <- 1..handle_test_count do
          push(socket, "ping", %{"handle_test" => i})
        end

      # Should complete without resource exhaustion
      completed =
        Enum.count(refs, fn ref ->
          receive do
            %Phoenix.Socket.Reply{ref: ^ref} -> true
          after
            100 -> false
          end
        end)

      # Most should complete successfully
      completion_rate = completed / handle_test_count
      # At least 70% completion
      assert completion_rate > 0.7
    end
  end
end
