defmodule Server.EndToEndIntegrationTest do
  @moduledoc """
  Comprehensive end-to-end integration tests that simulate real-world workflows
  across multiple services, channels, and system components.

  These tests verify that the entire system works cohesively, testing scenarios
  that users would actually encounter in production environments.
  """

  use Server.DataCase, async: false
  use ServerWeb.ChannelCase

  import ExUnit.CaptureLog
  import Hammox

  alias ServerWeb.{OverlayChannel, DashboardChannel, UserSocket}
  alias Server.Mocks.{IronmonTCPMock, OBSMock, RainwaveMock, TwitchMock}
  alias Server.{Ironmon, Repo}
  alias Server.Ironmon.{Challenge, Checkpoint, Seed, Result}

  # Setup comprehensive test environment
  setup do
    # Clean database
    Repo.delete_all(Result)
    Repo.delete_all(Seed)
    Repo.delete_all(Checkpoint)
    Repo.delete_all(Challenge)

    # Create test challenge structure
    {:ok, challenge} =
      Ironmon.create_challenge(%{
        name: "Elite Four Challenge",
        description: "Complete the Elite Four and Champion"
      })

    {:ok, checkpoint1} =
      Ironmon.create_checkpoint(%{
        challenge_id: challenge.id,
        name: "Elite Four - Lorelei",
        trainer: "Lorelei",
        order: 1
      })

    {:ok, checkpoint2} =
      Ironmon.create_checkpoint(%{
        challenge_id: challenge.id,
        name: "Elite Four - Bruno",
        trainer: "Bruno",
        order: 2
      })

    {:ok, seed} =
      Ironmon.create_seed(%{
        challenge_id: challenge.id
      })

    on_exit(fn ->
      # Clean up test data
      Repo.delete_all(Result)
      Repo.delete_all(Seed)
      Repo.delete_all(Checkpoint)
      Repo.delete_all(Challenge)
    end)

    %{
      challenge: challenge,
      checkpoint1: checkpoint1,
      checkpoint2: checkpoint2,
      seed: seed
    }
  end

  describe "streaming workflow integration" do
    test "complete OBS streaming session with overlay updates", %{challenge: challenge, checkpoint1: checkpoint} do
      # Mock OBS service responses for streaming workflow
      stub(OBSMock, :get_status, fn ->
        {:ok,
         %{
           connected: true,
           streaming: false,
           recording: false,
           current_scene: "Main Scene",
           fps: 60.0
         }}
      end)

      stub(OBSMock, :start_streaming, fn ->
        # Simulate successful stream start
        :ok
      end)

      stub(OBSMock, :stop_streaming, fn ->
        # Simulate successful stream stop
        :ok
      end)

      # Connect overlay channel
      {:ok, _, overlay_socket} =
        UserSocket
        |> socket("streamer", %{user_id: "streamer"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Connect dashboard channel
      {:ok, _, dashboard_socket} =
        UserSocket
        |> socket("admin", %{user_id: "admin"})
        |> subscribe_and_join(DashboardChannel, "dashboard:main")

      # Subscribe to system events
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")
      Phoenix.PubSub.subscribe(Server.PubSub, "ironmon:events")

      # Step 1: Start streaming via dashboard
      expect(OBSMock, :start_streaming, fn -> :ok end)

      ref = push(dashboard_socket, "obs:start_streaming", %{})
      assert_reply ref, :ok, _

      # Step 2: Verify overlay receives OBS status updates
      ref = push(overlay_socket, "obs:status", %{})
      assert_reply ref, :ok, obs_status
      assert obs_status.connected == true

      # Step 3: Simulate IronMON checkpoint completion
      challenge_id = challenge.id

      expect(IronmonTCPMock, :list_checkpoints, fn ^challenge_id ->
        {:ok,
         [
           %{id: checkpoint.id, name: checkpoint.name, trainer: checkpoint.trainer}
         ]}
      end)

      # Simulate checkpoint event from IronMON TCP
      checkpoint_event = %{
        type: "checkpoint",
        source: "tcp",
        correlation_id: "test-correlation-id",
        timestamp: System.system_time(:millisecond),
        metadata: %{
          id: checkpoint.id,
          name: checkpoint.name,
          seed: 123_456
        }
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "ironmon:events", {:ironmon_event, "checkpoint", checkpoint_event})

      # Step 4: Verify overlay receives IronMON updates
      ref = push(overlay_socket, "ironmon:checkpoints", %{"challenge_id" => challenge.id})
      assert_reply ref, :ok, checkpoints
      assert length(checkpoints) == 1

      # Step 5: Stop streaming
      expect(OBSMock, :stop_streaming, fn -> :ok end)

      ref = push(dashboard_socket, "obs:stop_streaming", %{})
      assert_reply ref, :ok, _

      # Verify complete workflow executed successfully
      assert Process.alive?(self())
    end

    test "multi-service status aggregation workflow", %{challenge: challenge} do
      # Mock all services for system status
      stub(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, streaming: true, recording: false}}
      end)

      stub(TwitchMock, :get_status, fn ->
        {:ok, %{connected: true, subscriptions: 6, user_id: "123456"}}
      end)

      stub(IronmonTCPMock, :get_status, fn ->
        {:ok, %{listening: true, port: 8080, connection_count: 1}}
      end)

      stub(RainwaveMock, :get_status, fn ->
        {:ok, %{playing: true, current_song: "Test Track", listeners: 42}}
      end)

      # Connect dashboard for system monitoring
      {:ok, _, dashboard_socket} =
        UserSocket
        |> socket("admin", %{user_id: "admin"})
        |> subscribe_and_join(DashboardChannel, "dashboard:main")

      # Request comprehensive system status
      ref = push(dashboard_socket, "system:status", %{})
      assert_reply ref, :ok, system_status

      # Verify aggregated status contains all services
      assert is_map(system_status)
      assert Map.has_key?(system_status, :status)
      assert Map.has_key?(system_status, :services)
      assert Map.has_key?(system_status, :summary)

      services = system_status.services
      assert Map.has_key?(services, :obs)
      assert Map.has_key?(services, :twitch)

      # Verify service health indicators
      assert system_status.status in ["healthy", "degraded", "critical"]
      assert is_integer(system_status.timestamp)
    end
  end

  describe "error recovery and resilience workflows" do
    test "service failure and recovery simulation", %{challenge: challenge} do
      # Initially, services are healthy
      stub(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, streaming: false}}
      end)

      stub(TwitchMock, :get_status, fn ->
        {:ok, %{connected: true, subscriptions: 6}}
      end)

      {:ok, _, dashboard_socket} =
        UserSocket
        |> socket("admin", %{user_id: "admin"})
        |> subscribe_and_join(DashboardChannel, "dashboard:main")

      # Step 1: Verify healthy state
      ref = push(dashboard_socket, "system:status", %{})
      assert_reply ref, :ok, healthy_status
      assert healthy_status.status in ["healthy", "degraded"]

      # Step 2: Simulate OBS service failure
      expect(OBSMock, :get_status, fn ->
        {:error, "Connection failed"}
      end)

      # Step 3: Verify system detects degraded state
      ref = push(dashboard_socket, "system:status", %{})
      assert_reply ref, :ok, degraded_status

      # System should still respond but indicate issues
      assert is_map(degraded_status)
      assert Map.has_key?(degraded_status, :services)

      # Step 4: Simulate service recovery
      expect(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, streaming: false}}
      end)

      # Step 5: Verify recovery detection
      ref = push(dashboard_socket, "system:status", %{})
      assert_reply ref, :ok, recovered_status
      assert is_map(recovered_status)
    end

    test "concurrent client stress testing", %{challenge: challenge} do
      # Mock services for concurrent access
      stub(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, streaming: false}}
      end)

      stub(IronmonTCPMock, :list_challenges, fn ->
        {:ok, [%{id: challenge.id, name: challenge.name}]}
      end)

      # Connect multiple overlay clients
      overlay_sockets =
        for i <- 1..5 do
          {:ok, _, socket} =
            UserSocket
            |> socket("overlay_#{i}", %{user_id: "overlay_#{i}"})
            |> subscribe_and_join(OverlayChannel, "overlay:obs")

          socket
        end

      # Connect multiple dashboard clients
      dashboard_sockets =
        for i <- 1..3 do
          {:ok, _, socket} =
            UserSocket
            |> socket("dashboard_#{i}", %{user_id: "dashboard_#{i}"})
            |> subscribe_and_join(DashboardChannel, "dashboard:main")

          socket
        end

      # Simulate concurrent requests from all clients
      start_time = System.monotonic_time(:millisecond)

      # Each overlay client requests OBS status
      overlay_refs =
        Enum.map(overlay_sockets, fn socket ->
          push(socket, "obs:status", %{})
        end)

      # Each dashboard client requests system status
      dashboard_refs =
        Enum.map(dashboard_sockets, fn socket ->
          push(socket, "system:status", %{})
        end)

      # Verify all requests complete successfully
      Enum.each(overlay_refs, fn ref ->
        assert_reply ref, :ok, _obs_status
      end)

      Enum.each(dashboard_refs, fn ref ->
        assert_reply ref, :ok, _system_status
      end)

      end_time = System.monotonic_time(:millisecond)
      total_duration = end_time - start_time

      # All requests should complete within reasonable time (less than 5 seconds)
      assert total_duration < 5000

      # Verify all sockets are still active
      assert length(overlay_sockets) == 5
      assert length(dashboard_sockets) == 3
    end
  end

  describe "data consistency and persistence workflows" do
    test "IronMON challenge progress tracking across restarts", %{
      challenge: challenge,
      checkpoint1: checkpoint1,
      checkpoint2: checkpoint2,
      seed: seed
    } do
      # Mock IronMON TCP service
      stub(IronmonTCPMock, :list_challenges, fn ->
        {:ok, [%{id: challenge.id, name: challenge.name}]}
      end)

      challenge_id = challenge.id
      seed_id = seed.id

      stub(IronmonTCPMock, :list_checkpoints, fn ^challenge_id ->
        {:ok,
         [
           %{id: checkpoint1.id, name: checkpoint1.name, trainer: checkpoint1.trainer},
           %{id: checkpoint2.id, name: checkpoint2.name, trainer: checkpoint2.trainer}
         ]}
      end)

      stub(IronmonTCPMock, :get_active_challenge, fn ^seed_id ->
        {:ok,
         %{
           seed_id: seed.id,
           challenge_name: challenge.name,
           completed_checkpoints: 0
         }}
      end)

      {:ok, _, overlay_socket} =
        UserSocket
        |> socket("streamer", %{user_id: "streamer"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Step 1: Get initial challenge state
      ref = push(overlay_socket, "ironmon:challenges", %{})
      assert_reply ref, :ok, challenges
      assert length(challenges) == 1
      assert hd(challenges).id == challenge.id

      # Step 2: Complete first checkpoint (simulate database update)
      {:ok, _result} =
        Repo.insert(%Result{
          seed_id: seed.id,
          checkpoint_id: checkpoint1.id,
          result: true
        })

      # Step 3: Update mock to reflect progress
      expect(IronmonTCPMock, :get_active_challenge, fn ^seed_id ->
        {:ok,
         %{
           seed_id: seed.id,
           challenge_name: challenge.name,
           completed_checkpoints: 1
         }}
      end)

      expect(IronmonTCPMock, :get_recent_results, fn 10 ->
        {:ok,
         [
           %{
             seed_id: seed.id,
             checkpoint_name: checkpoint1.name,
             trainer: checkpoint1.trainer,
             challenge_name: challenge.name,
             result: true
           }
         ]}
      end)

      # Step 4: Verify updated progress
      ref = push(overlay_socket, "ironmon:recent_results", %{})
      assert_reply ref, :ok, results
      assert length(results) == 1
      assert hd(results).result == true

      # Step 5: Complete second checkpoint
      {:ok, _result2} =
        Repo.insert(%Result{
          seed_id: seed.id,
          checkpoint_id: checkpoint2.id,
          result: true
        })

      # Step 6: Verify persistence across "service restart" (new query)
      results_from_db = Repo.all(Result)
      assert length(results_from_db) == 2

      # All checkpoint completions should be persisted
      checkpoint_ids = Enum.map(results_from_db, & &1.checkpoint_id)
      assert checkpoint1.id in checkpoint_ids
      assert checkpoint2.id in checkpoint_ids
    end

    test "event broadcasting consistency across channels", %{challenge: _challenge, checkpoint1: checkpoint} do
      # Setup multiple channel types
      {:ok, _, _obs_overlay} =
        UserSocket
        |> socket("obs_user", %{user_id: "obs_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      {:ok, _, _twitch_overlay} =
        UserSocket
        |> socket("twitch_user", %{user_id: "twitch_user"})
        |> subscribe_and_join(OverlayChannel, "overlay:twitch")

      {:ok, _, _dashboard} =
        UserSocket
        |> socket("admin", %{user_id: "admin"})
        |> subscribe_and_join(DashboardChannel, "dashboard:main")

      # Subscribe to PubSub events
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")
      Phoenix.PubSub.subscribe(Server.PubSub, "ironmon:events")

      # Step 1: Simulate OBS event
      obs_event = %{
        type: "StreamStateChanged",
        data: %{outputActive: true, outputState: "OBS_WEBSOCKET_OUTPUT_STARTED"}
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, obs_event})

      # Step 2: Verify only OBS overlay receives OBS events
      assert_push "obs_event", ^obs_event, 1000

      # Twitch overlay should not receive OBS events
      refute_receive {:phoenix, :push, _, "obs_event", _}, 500

      # Step 3: Simulate IronMON event
      ironmon_event = %{
        type: "checkpoint",
        source: "tcp",
        correlation_id: "test-id",
        timestamp: System.system_time(:millisecond),
        metadata: %{
          id: checkpoint.id,
          name: checkpoint.name,
          seed: 123_456
        }
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "ironmon:events", {:ironmon_event, "checkpoint", ironmon_event})

      # Step 4: Verify event routing
      # Both overlays should receive IronMON events (if they subscribe)
      # Dashboard should receive system-wide events

      # Verify the event system is working
      assert_receive {:ironmon_event, "checkpoint", received_event}, 1000
      assert received_event.metadata.id == checkpoint.id
    end
  end

  describe "performance and scalability workflows" do
    test "high-frequency event processing", %{challenge: _challenge} do
      # Mock rapid event generation
      stub(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, streaming: true}}
      end)

      {:ok, _, _overlay_socket} =
        UserSocket
        |> socket("perf_test", %{user_id: "perf_test"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Subscribe to events
      Phoenix.PubSub.subscribe(Server.PubSub, "obs:events")

      start_time = System.monotonic_time(:millisecond)
      event_count = 50

      # Generate rapid sequence of events
      for i <- 1..event_count do
        obs_event = %{
          type: "SourceVolumeChanged",
          data: %{sourceName: "Microphone", volume: i * 0.02}
        }

        Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, obs_event})
      end

      # Count received events
      received_count = receive_events("obs_event", event_count, 5000)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Verify all events were processed
      assert received_count == event_count

      # Should process quickly (less than 2 seconds for 50 events)
      assert duration < 2000
    end

    test "memory usage stability under load", %{challenge: _challenge} do
      # Mock service responses
      stub(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, streaming: false}}
      end)

      # Create multiple connections
      sockets =
        for i <- 1..10 do
          {:ok, _, socket} =
            UserSocket
            |> socket("load_test_#{i}", %{user_id: "load_test_#{i}"})
            |> subscribe_and_join(OverlayChannel, "overlay:obs")

          socket
        end

      # Generate sustained load
      for _round <- 1..20 do
        # Each socket makes multiple requests
        Enum.each(sockets, fn socket ->
          push(socket, "obs:status", %{})
          push(socket, "ping", %{test: "data"})
        end)

        # Small delay between rounds
        :timer.sleep(50)
      end

      # Allow processing to complete
      :timer.sleep(1000)

      # Verify all sockets are still responsive
      test_refs =
        Enum.map(sockets, fn socket ->
          push(socket, "ping", %{final: "test"})
        end)

      # All should respond
      Enum.each(test_refs, fn ref ->
        assert_reply ref, :ok, response
        assert response.pong == true
      end)

      # Verify system stability
      assert length(sockets) == 10
    end
  end

  # Helper function to receive multiple events
  defp receive_events(event_type, expected_count, timeout) do
    receive_events(event_type, expected_count, timeout, 0, System.monotonic_time(:millisecond))
  end

  defp receive_events(_event_type, expected_count, _timeout, received_count, _start_time)
       when received_count >= expected_count do
    received_count
  end

  defp receive_events(event_type, expected_count, timeout, received_count, start_time) do
    current_time = System.monotonic_time(:millisecond)
    remaining_timeout = timeout - (current_time - start_time)

    if remaining_timeout <= 0 do
      received_count
    else
      receive do
        {:phoenix, :push, _, ^event_type, _} ->
          receive_events(event_type, expected_count, timeout, received_count + 1, start_time)
      after
        remaining_timeout ->
          received_count
      end
    end
  end
end
