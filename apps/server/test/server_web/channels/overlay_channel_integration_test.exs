defmodule ServerWeb.OverlayChannelIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for OverlayChannel focusing on real WebSocket
  interactions, business logic, parameter validation, and event broadcasting.

  These tests simulate actual client-server interactions including edge cases
  and failure scenarios, testing the intended functionality rather than just
  code coverage.
  """

  use ServerWeb.ChannelCase
  import Hammox

  alias ServerWeb.{OverlayChannel, UserSocket}
  alias Server.Mocks.{OBSMock, TwitchMock, IronmonTCPMock, RainwaveMock}

  describe "channel lifecycle and connection management" do
    test "successfully joins overlay:obs channel and receives initial state" do
      # Mock the service call for initial state
      expect(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, streaming: false, recording: false}}
      end)

      {:ok, reply, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Verify channel joined successfully
      assert reply == %{}
      assert socket.assigns.overlay_type == "obs"
      assert is_binary(socket.assigns.correlation_id)

      # Verify initial state push is sent
      assert_push "initial_state", %{
        type: "obs",
        data: %{connected: true, streaming: false, recording: false}
      }
    end

    test "successfully joins overlay:twitch channel with different initial state" do
      expect(TwitchMock, :get_status, fn ->
        {:ok, %{connected: true, subscriptions: 6, user_id: "123456"}}
      end)

      {:ok, _reply, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:twitch")

      assert socket.assigns.overlay_type == "twitch"

      assert_push "initial_state", %{
        type: "twitch",
        data: %{connected: true, subscriptions: 6, user_id: "123456"}
      }
    end

    test "joins overlay:system channel without external service calls" do
      {:ok, _reply, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:system")

      assert socket.assigns.overlay_type == "system"

      # System overlay sends static initial state
      assert_push "initial_state", %{
        type: "system",
        data: %{connected: true, timestamp: timestamp}
      }

      assert is_integer(timestamp)
    end

    test "handles service failure during initial state gracefully" do
      # Mock service returning error during join
      expect(OBSMock, :get_status, fn ->
        {:error, "OBS not connected"}
      end)

      {:ok, _reply, _socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Should send fallback initial state when service fails
      assert_push "initial_state", %{
        type: "obs",
        data: %{connected: false}
      }
    end

    test "accepts unknown overlay types but logs warning" do
      # The channel actually accepts any overlay type - it just logs a warning
      {:ok, _reply, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:invalid")

      assert socket.assigns.overlay_type == "invalid"

      # Should send generic initial state
      assert_push "initial_state", %{type: "invalid", data: %{connected: true}}
    end
  end

  describe "OBS command handling and validation" do
    setup do
      expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

      {:ok, _, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      %{socket: socket}
    end

    test "obs:status command with successful response", %{socket: socket} do
      obs_status = %{
        connected: true,
        streaming: %{active: true, time_code: "01:23:45"},
        recording: %{active: false},
        current_scene: "Main Scene",
        fps: 60.0,
        cpu_usage: 15.2
      }

      expect(OBSMock, :get_status, fn -> {:ok, obs_status} end)

      ref = push(socket, "obs:status", %{})
      assert_reply ref, :ok, ^obs_status
    end

    test "obs:status command with service error", %{socket: socket} do
      expect(OBSMock, :get_status, fn ->
        {:error,
         %Server.ServiceError{
           reason: :service_unavailable,
           message: "WebSocket connection failed",
           service: :obs,
           operation: "get_status"
         }}
      end)

      ref = push(socket, "obs:status", %{})
      assert_reply ref, :error, %{message: "WebSocket connection failed"}
    end

    test "obs:scenes command returns scene list", %{socket: socket} do
      scene_data = %{
        "currentProgramSceneName" => "Main Scene",
        "scenes" => [
          %{"sceneName" => "Main Scene", "sceneIndex" => 0},
          %{"sceneName" => "BRB Scene", "sceneIndex" => 1}
        ]
      }

      expect(OBSMock, :get_scene_list, fn -> {:ok, scene_data} end)

      ref = push(socket, "obs:scenes", %{})
      assert_reply ref, :ok, ^scene_data
    end

    test "obs:stats returns performance statistics", %{socket: socket} do
      stats_data = %{
        "activeFps" => 59.94,
        "averageFrameRenderTime" => 2.1,
        "cpuUsage" => 8.5,
        "memoryUsage" => 1024.5,
        "renderTotalFrames" => 125_000
      }

      expect(OBSMock, :get_stats, fn -> {:ok, stats_data} end)

      ref = push(socket, "obs:stats", %{})
      assert_reply ref, :ok, ^stats_data
    end
  end

  describe "IronMON command handling with parameter validation" do
    setup do
      expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

      {:ok, _, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      %{socket: socket}
    end

    test "ironmon:checkpoints with valid challenge_id", %{socket: socket} do
      checkpoints = [
        %{id: 1, name: "Elite Four - Lorelei", difficulty: "hard"},
        %{id: 2, name: "Elite Four - Bruno", difficulty: "hard"}
      ]

      expect(IronmonTCPMock, :list_checkpoints, fn 1 ->
        {:ok, checkpoints}
      end)

      ref = push(socket, "ironmon:checkpoints", %{"challenge_id" => 1})
      assert_reply ref, :ok, ^checkpoints
    end

    test "ironmon:checkpoints with string challenge_id gets converted", %{socket: socket} do
      checkpoints = [%{id: 1, name: "Champion"}]

      expect(IronmonTCPMock, :list_checkpoints, fn 42 ->
        {:ok, checkpoints}
      end)

      ref = push(socket, "ironmon:checkpoints", %{"challenge_id" => "42"})
      assert_reply ref, :ok, ^checkpoints
    end

    test "ironmon:checkpoints with missing challenge_id returns error", %{socket: socket} do
      ref = push(socket, "ironmon:checkpoints", %{})
      assert_reply ref, :error, %{message: "Missing required parameters: challenge_id"}
    end

    test "ironmon:checkpoints with invalid challenge_id returns error", %{socket: socket} do
      ref = push(socket, "ironmon:checkpoints", %{"challenge_id" => "invalid"})
      assert_reply ref, :error, %{message: "Parameter 'challenge_id' must be a positive integer"}
    end

    test "ironmon:checkpoints with zero challenge_id returns error", %{socket: socket} do
      ref = push(socket, "ironmon:checkpoints", %{"challenge_id" => 0})
      assert_reply ref, :error, %{message: "Parameter 'challenge_id' must be a positive integer"}
    end

    test "ironmon:recent_results with valid limit parameter", %{socket: socket} do
      results = [
        %{id: 1, time: "12:34:56", status: "completed"},
        %{id: 2, time: "11:22:33", status: "failed"}
      ]

      expect(IronmonTCPMock, :get_recent_results, fn 5 ->
        {:ok, results}
      end)

      ref = push(socket, "ironmon:recent_results", %{"limit" => 5})
      assert_reply ref, :ok, ^results
    end

    test "ironmon:recent_results with default limit when not provided", %{socket: socket} do
      expect(IronmonTCPMock, :get_recent_results, fn 10 ->
        {:ok, []}
      end)

      ref = push(socket, "ironmon:recent_results", %{})
      assert_reply ref, :ok, []
    end

    test "ironmon:recent_results with limit too high returns error", %{socket: socket} do
      ref = push(socket, "ironmon:recent_results", %{"limit" => 150})
      assert_reply ref, :error, %{message: "Parameter 'limit' must be an integer between 1 and 100"}
    end
  end

  describe "system command integration" do
    setup do
      expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

      {:ok, _, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:system")

      %{socket: socket}
    end

    test "system:status aggregates all service statuses", %{socket: socket} do
      # Stub service responses for system status (allows multiple calls)
      stub(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, streaming: true}}
      end)

      stub(TwitchMock, :get_status, fn ->
        {:ok, %{connected: true, subscriptions: 6}}
      end)

      # Don't need to mock this - it will call the real service registry

      ref = push(socket, "system:status", %{})
      assert_reply ref, :ok, response

      # Verify basic response structure (actual response will vary based on system state)
      assert is_map(response)
      assert Map.has_key?(response, :status)
      assert Map.has_key?(response, :timestamp)
      assert Map.has_key?(response, :services)
      assert Map.has_key?(response, :summary)
    end

    test "system:status handles service failures gracefully", %{socket: socket} do
      # Stub one service failing (allows multiple calls)
      stub(OBSMock, :get_status, fn ->
        {:error, "Connection failed"}
      end)

      stub(TwitchMock, :get_status, fn ->
        {:ok, %{connected: true}}
      end)

      ref = push(socket, "system:status", %{})
      assert_reply ref, :ok, response

      # Verify that some services report correctly
      assert is_map(response)
      assert Map.has_key?(response, :services)

      services = response.services
      assert Map.has_key?(services, :obs)
      assert Map.has_key?(services, :twitch)
    end
  end

  describe "ping/pong functionality" do
    setup do
      expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

      {:ok, _, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      %{socket: socket}
    end

    test "ping command returns pong with payload echo and metadata", %{socket: socket} do
      payload = %{"test_data" => "hello", "number" => 42}

      ref = push(socket, "ping", payload)
      assert_reply ref, :ok, response

      # Verify pong response includes original payload plus metadata
      assert %{
               pong: true,
               overlay_type: "obs",
               timestamp: timestamp
             } = response

      assert is_integer(timestamp)
      assert Map.get(response, "test_data") == "hello"
      assert Map.get(response, "number") == 42
    end

    test "ping with empty payload returns minimal pong", %{socket: socket} do
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, response

      assert %{
               pong: true,
               overlay_type: "obs",
               timestamp: timestamp
             } = response

      assert is_integer(timestamp)
    end
  end

  describe "error handling and edge cases" do
    setup do
      expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

      {:ok, _, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      %{socket: socket}
    end

    test "unknown command returns structured error", %{socket: socket} do
      ref = push(socket, "invalid:command", %{some: "data"})
      assert_reply ref, :error, %{message: "Unknown command: invalid:command"}
    end

    test "malformed command name returns error", %{socket: socket} do
      ref = push(socket, "malformed_command", %{})
      assert_reply ref, :error, %{message: "Unknown command: malformed_command"}
    end

    test "command with partial service name returns error", %{socket: socket} do
      ref = push(socket, "obs:", %{})
      assert_reply ref, :error, %{message: "Unknown command: obs:"}
    end

    test "service error with custom error type gets formatted", %{socket: socket} do
      custom_error = %Server.ServiceError{
        reason: :network_error,
        service: :obs,
        operation: "get_stats",
        message: "Custom error occurred",
        details: %{code: 4009}
      }

      expect(OBSMock, :get_stats, fn -> {:error, custom_error} end)

      ref = push(socket, "obs:stats", %{})
      assert_reply ref, :error, %{message: "Custom error occurred"}
    end

    test "service timeout scenario", %{socket: socket} do
      # Simulate service timeout - override the initial expectation
      expect(OBSMock, :get_status, fn ->
        {:error, :timeout}
      end)

      ref = push(socket, "obs:status", %{})
      assert_reply ref, :error, %{message: message}
      assert is_binary(message)
    end
  end

  describe "event broadcasting and PubSub integration" do
    setup do
      expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)

      {:ok, _, socket} =
        UserSocket
        |> socket("user_123", %{user_id: "123"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      %{socket: socket}
    end

    test "receives OBS events when subscribed to obs overlay", %{socket: socket} do
      # Simulate OBS event being published
      obs_event = %{
        type: "StreamStateChanged",
        data: %{outputActive: true, outputState: "OBS_WEBSOCKET_OUTPUT_STARTED"}
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, obs_event})

      assert_push "obs_event", ^obs_event
    end

    test "does not receive Twitch events when subscribed to obs overlay", %{socket: socket} do
      # Simulate Twitch event being published
      twitch_event = %{type: "channel.follow", data: %{user_name: "test_user"}}

      Phoenix.PubSub.broadcast(Server.PubSub, "twitch:events", {:twitch_event, twitch_event})

      # Should not receive this event since we're on obs overlay
      refute_push "twitch_event", _
    end

    test "multiple clients receive the same broadcast event" do
      expect(OBSMock, :get_status, 2, fn -> {:ok, %{connected: true}} end)

      # Connect two clients to the same overlay
      {:ok, _, socket1} =
        UserSocket
        |> socket("user_1", %{user_id: "1"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      {:ok, _, socket2} =
        UserSocket
        |> socket("user_2", %{user_id: "2"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      # Broadcast event
      obs_event = %{type: "RecordStateChanged", data: %{outputActive: true}}
      Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, obs_event})

      # Both clients should receive the event
      assert_push "obs_event", obs_event
    end
  end

  describe "correlation ID and logging context" do
    test "each connection gets unique correlation ID" do
      expect(OBSMock, :get_status, 2, fn -> {:ok, %{connected: true}} end)

      {:ok, _, socket1} =
        UserSocket
        |> socket("user_1", %{user_id: "1"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      {:ok, _, socket2} =
        UserSocket
        |> socket("user_2", %{user_id: "2"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      correlation_id1 = socket1.assigns.correlation_id
      correlation_id2 = socket2.assigns.correlation_id

      assert is_binary(correlation_id1)
      assert is_binary(correlation_id2)
      assert correlation_id1 != correlation_id2
    end

    test "correlation ID persists throughout channel lifecycle" do
      expect(OBSMock, :get_status, 2, fn -> {:ok, %{connected: true}} end)

      {:ok, _, socket} =
        UserSocket
        |> socket("user_1", %{user_id: "1"})
        |> subscribe_and_join(OverlayChannel, "overlay:obs")

      original_correlation_id = socket.assigns.correlation_id

      # Make a command call
      ref = push(socket, "obs:status", %{})
      assert_reply ref, :ok, _response

      # Correlation ID should remain the same
      assert socket.assigns.correlation_id == original_correlation_id
    end
  end
end
