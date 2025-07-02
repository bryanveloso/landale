defmodule ServerWeb.DashboardChannelIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for DashboardChannel focusing on bidirectional
  communication, real-time updates, control operations, and business logic.

  These tests verify the intended functionality for dashboard management including
  OBS control, system monitoring, and event broadcasting.
  """

  use ServerWeb.ChannelCase
  import Hammox

  alias ServerWeb.{DashboardChannel, UserSocket}
  alias Server.Mocks.{OBSMock, RainwaveMock}

  describe "channel lifecycle and room management" do
    test "successfully joins dashboard:lobby and receives initial state" do
      {:ok, reply, socket} =
        UserSocket
        |> socket("dashboard_user_123", %{user_id: "123"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      # Verify successful join
      assert reply == %{}
      assert socket.assigns.room_id == "lobby"
      assert is_binary(socket.assigns.correlation_id)

      # Verify initial state push
      assert_push "initial_state", %{
        connected: true,
        timestamp: timestamp
      }

      assert is_integer(timestamp)
    end

    test "successfully joins different dashboard rooms" do
      {:ok, _reply, socket1} =
        UserSocket
        |> socket("user_1", %{user_id: "1"})
        |> subscribe_and_join(DashboardChannel, "dashboard:main")

      {:ok, _reply, socket2} =
        UserSocket
        |> socket("user_2", %{user_id: "2"})
        |> subscribe_and_join(DashboardChannel, "dashboard:secondary")

      assert socket1.assigns.room_id == "main"
      assert socket2.assigns.room_id == "secondary"

      # Both should receive initial state
      assert_receive %Phoenix.Socket.Message{event: "initial_state", payload: %{connected: true}}
      assert_receive %Phoenix.Socket.Message{event: "initial_state", payload: %{connected: true}}
    end

    test "assigns unique correlation IDs to different connections" do
      {:ok, _reply, socket1} =
        UserSocket
        |> socket("user_1", %{user_id: "1"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      {:ok, _reply, socket2} =
        UserSocket
        |> socket("user_2", %{user_id: "2"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      correlation_id1 = socket1.assigns.correlation_id
      correlation_id2 = socket2.assigns.correlation_id

      assert is_binary(correlation_id1)
      assert is_binary(correlation_id2)
      assert correlation_id1 != correlation_id2
    end
  end

  describe "OBS control operations" do
    setup do
      {:ok, _, socket} =
        UserSocket
        |> socket("dashboard_user", %{user_id: "dashboard"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      %{socket: socket}
    end

    test "obs:get_status returns current OBS status", %{socket: socket} do
      obs_status = %{
        connected: true,
        streaming: %{active: true, time_code: "01:30:45"},
        recording: %{active: false},
        current_scene: "Main Scene",
        fps: 60.0
      }

      expect(OBSMock, :get_status, fn -> {:ok, obs_status} end)

      ref = push(socket, "obs:get_status", %{})
      assert_reply ref, :ok, ^obs_status
    end

    test "obs:get_status handles service errors gracefully", %{socket: socket} do
      expect(OBSMock, :get_status, fn ->
        {:error,
         %Server.ServiceError{
           reason: :service_unavailable,
           service: :obs,
           operation: "get_status",
           message: "OBS WebSocket not connected"
         }}
      end)

      ref = push(socket, "obs:get_status", %{})
      assert_reply ref, :error, %{message: "OBS WebSocket not connected"}
    end

    test "obs:start_streaming initiates streaming", %{socket: socket} do
      expect(OBSMock, :start_streaming, fn -> :ok end)

      ref = push(socket, "obs:start_streaming", %{})
      assert_reply ref, :ok, %{success: true}
    end

    test "obs:start_streaming handles failures", %{socket: socket} do
      expect(OBSMock, :start_streaming, fn -> {:error, "Already streaming"} end)

      ref = push(socket, "obs:start_streaming", %{})
      assert_reply ref, :error, %{message: "Already streaming"}
    end

    test "obs:stop_streaming stops streaming", %{socket: socket} do
      expect(OBSMock, :stop_streaming, fn -> :ok end)

      ref = push(socket, "obs:stop_streaming", %{})
      assert_reply ref, :ok, %{success: true}
    end

    test "obs:stop_streaming handles failures", %{socket: socket} do
      expect(OBSMock, :stop_streaming, fn -> {:error, "Not streaming"} end)

      ref = push(socket, "obs:stop_streaming", %{})
      assert_reply ref, :error, %{message: "Not streaming"}
    end

    test "obs:start_recording initiates recording", %{socket: socket} do
      expect(OBSMock, :start_recording, fn -> :ok end)

      ref = push(socket, "obs:start_recording", %{})
      assert_reply ref, :ok, %{success: true}
    end

    test "obs:stop_recording stops recording", %{socket: socket} do
      expect(OBSMock, :stop_recording, fn -> :ok end)

      ref = push(socket, "obs:stop_recording", %{})
      assert_reply ref, :ok, %{success: true}
    end

    test "obs:set_current_scene changes scene", %{socket: socket} do
      expect(OBSMock, :set_current_scene, fn "BRB Scene" -> :ok end)

      ref = push(socket, "obs:set_current_scene", %{"scene_name" => "BRB Scene"})
      assert_reply ref, :ok, %{success: true}
    end

    test "obs:set_current_scene validates scene name parameter", %{socket: socket} do
      # Missing scene_name parameter
      ref = push(socket, "obs:set_current_scene", %{})
      assert_reply ref, :error, %{message: message}
      assert is_binary(message)
    end

    test "obs:set_current_scene handles invalid scenes", %{socket: socket} do
      expect(OBSMock, :set_current_scene, fn "InvalidScene" ->
        {:error, "Scene not found"}
      end)

      ref = push(socket, "obs:set_current_scene", %{"scene_name" => "InvalidScene"})
      assert_reply ref, :error, %{message: "Scene not found"}
    end
  end

  describe "Rainwave control operations" do
    setup do
      {:ok, _, socket} =
        UserSocket
        |> socket("dashboard_user", %{user_id: "dashboard"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      %{socket: socket}
    end

    test "rainwave:get_status returns current music status", %{socket: socket} do
      rainwave_status = %{
        connected: true,
        current_song: %{
          title: "Aquatic Ambiance",
          artist: "David Wise",
          album: "Donkey Kong Country OST"
        },
        station: %{id: 1, name: "Game"},
        listeners: 142
      }

      expect(RainwaveMock, :get_status, fn -> {:ok, rainwave_status} end)

      ref = push(socket, "rainwave:get_status", %{})
      assert_reply ref, :ok, ^rainwave_status
    end

    test "rainwave:get_status handles service errors", %{socket: socket} do
      expect(RainwaveMock, :get_status, fn ->
        {:error, "API temporarily unavailable"}
      end)

      ref = push(socket, "rainwave:get_status", %{})
      assert_reply ref, :error, %{message: "\"API temporarily unavailable\""}
    end

    test "rainwave:set_enabled controls service state", %{socket: socket} do
      expect(RainwaveMock, :set_enabled, fn true -> :ok end)

      ref = push(socket, "rainwave:set_enabled", %{"enabled" => true})
      assert_reply ref, :ok, %{success: true}
    end

    test "rainwave:set_enabled with false value", %{socket: socket} do
      expect(RainwaveMock, :set_enabled, fn false -> :ok end)

      ref = push(socket, "rainwave:set_enabled", %{"enabled" => false})
      assert_reply ref, :ok, %{success: true}
    end

    test "rainwave:set_station changes active station", %{socket: socket} do
      expect(RainwaveMock, :set_station, fn 2 -> :ok end)

      ref = push(socket, "rainwave:set_station", %{"station_id" => 2})
      assert_reply ref, :ok, %{success: true}
    end
  end

  describe "real-time event broadcasting" do
    setup do
      {:ok, _, socket} =
        UserSocket
        |> socket("dashboard_user", %{user_id: "dashboard"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      %{socket: socket}
    end

    test "receives OBS events when published", %{socket: socket} do
      obs_event = %{
        type: "StreamStateChanged",
        data: %{
          outputActive: true,
          outputState: "OBS_WEBSOCKET_OUTPUT_STARTED"
        }
      }

      # Simulate OBS event being published
      Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, obs_event})

      assert_push "obs_event", ^obs_event
    end

    test "receives Rainwave events when published", %{socket: socket} do
      rainwave_event = %{
        type: "song_changed",
        data: %{
          song: %{title: "New Song", artist: "Artist"},
          station_id: 1
        }
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "rainwave:events", {:rainwave_event, rainwave_event})

      assert_push "rainwave_event", ^rainwave_event
    end

    test "receives system health updates", %{socket: socket} do
      health_data = %{
        status: "degraded",
        services: %{
          obs: %{connected: false, error: "Connection lost"},
          twitch: %{connected: true}
        },
        timestamp: System.system_time(:second)
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "system:health", {:health_update, health_data})

      assert_push "health_update", ^health_data
    end

    test "receives system performance updates", %{socket: socket} do
      performance_data = %{
        cpu_usage: 25.4,
        memory_usage: %{
          used: 2_048_000_000,
          total: 8_192_000_000,
          percentage: 25.0
        },
        network: %{
          bytes_in: 1_024_000,
          bytes_out: 512_000
        }
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "system:performance", {:performance_update, performance_data})

      assert_push "performance_update", ^performance_data
    end

    test "receives batched events efficiently", %{socket: socket} do
      batch_data = %{
        events: [
          %{type: "obs", data: %{streaming: true}},
          %{type: "system", data: %{cpu: 15.2}},
          %{type: "rainwave", data: %{song_changed: true}}
        ],
        timestamp: System.system_time(:second),
        count: 3
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "system:events", {:event_batch, batch_data})

      assert_push "event_batch", ^batch_data
    end

    test "multiple clients receive the same broadcast" do
      # Connect two dashboard clients
      {:ok, _, socket1} =
        UserSocket
        |> socket("user_1", %{user_id: "1"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      {:ok, _, socket2} =
        UserSocket
        |> socket("user_2", %{user_id: "2"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      # Broadcast an event
      obs_event = %{type: "RecordStateChanged", data: %{outputActive: true}}
      Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, obs_event})

      # Both clients should receive the event
      assert_receive %Phoenix.Socket.Message{event: "obs_event", payload: ^obs_event}
      assert_receive %Phoenix.Socket.Message{event: "obs_event", payload: ^obs_event}
    end
  end

  describe "bidirectional communication patterns" do
    setup do
      {:ok, _, socket} =
        UserSocket
        |> socket("dashboard_user", %{user_id: "dashboard"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      %{socket: socket}
    end

    test "dashboard can request OBS status and receive immediate response", %{socket: socket} do
      # Set up the expectation
      expect(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, streaming: true}}
      end)

      # Request current status
      ref = push(socket, "obs:get_status", %{})
      assert_reply ref, :ok, %{connected: true, streaming: true}

      # Simulate OBS sending an update shortly after
      obs_event = %{type: "StreamStopped", data: %{outputActive: false}}
      Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, obs_event})

      # Should receive the real-time update
      assert_push "obs_event", ^obs_event
    end

    test "dashboard can control OBS and receive confirmation", %{socket: socket} do
      # Set up expectation for the control operation
      expect(OBSMock, :start_streaming, fn -> :ok end)

      # Send control command
      ref = push(socket, "obs:start_streaming", %{})
      assert_reply ref, :ok, %{success: true}

      # Simulate OBS confirming the state change via event
      confirmation_event = %{
        type: "StreamStateChanged",
        data: %{outputActive: true, outputState: "OBS_WEBSOCKET_OUTPUT_STARTED"}
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, confirmation_event})

      assert_push "obs_event", ^confirmation_event
    end

    test "dashboard receives updates while performing operations", %{socket: socket} do
      # Set up expectations for concurrent operations
      expect(OBSMock, :get_status, fn ->
        {:ok, %{connected: true, current_scene: "Scene 1"}}
      end)

      expect(OBSMock, :set_current_scene, fn "Scene 2" -> :ok end)

      # Request status
      ref1 = push(socket, "obs:get_status", %{})
      assert_reply ref1, :ok, %{connected: true, current_scene: "Scene 1"}

      # Change scene
      ref2 = push(socket, "obs:set_current_scene", %{"scene_name" => "Scene 2"})
      assert_reply ref2, :ok, %{success: true}

      # Receive real-time confirmation of scene change
      scene_change_event = %{
        type: "CurrentProgramSceneChanged",
        data: %{sceneName: "Scene 2"}
      }

      Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, scene_change_event})

      assert_push "obs_event", ^scene_change_event
    end
  end

  describe "error handling and edge cases" do
    setup do
      {:ok, _, socket} =
        UserSocket
        |> socket("dashboard_user", %{user_id: "dashboard"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      %{socket: socket}
    end

    test "unknown commands return structured errors", %{socket: socket} do
      ref = push(socket, "unknown:command", %{some: "data"})
      assert_reply ref, :error, %{message: "Unknown event: unknown:command"}
    end

    test "malformed OBS commands are handled gracefully", %{socket: socket} do
      ref = push(socket, "obs:invalid_command", %{})
      assert_reply ref, :error, %{message: "Unknown event: obs:invalid_command"}
    end

    test "service timeouts are handled appropriately", %{socket: socket} do
      expect(OBSMock, :get_status, fn ->
        # Simulate slow response
        Process.sleep(50)
        {:error, :timeout}
      end)

      ref = push(socket, "obs:get_status", %{})
      assert_reply ref, :error, %{message: ":timeout"}
    end

    test "concurrent command execution", %{socket: socket} do
      # Set up expectations for multiple concurrent operations
      expect(OBSMock, :get_status, fn ->
        # Simulate processing time
        Process.sleep(10)
        {:ok, %{connected: true}}
      end)

      expect(RainwaveMock, :get_status, fn ->
        # Simulate processing time
        Process.sleep(10)
        {:ok, %{playing: true}}
      end)

      # Send multiple commands concurrently
      ref1 = push(socket, "obs:get_status", %{})
      ref2 = push(socket, "rainwave:get_status", %{})

      # Both should complete successfully
      assert_reply ref1, :ok, %{connected: true}
      assert_reply ref2, :ok, %{playing: true}
    end
  end

  describe "legacy test compatibility" do
    setup do
      {:ok, _, socket} =
        UserSocket
        |> socket("user_id", %{some: :assign})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      %{socket: socket}
    end

    test "ping replies with payload echo", %{socket: socket} do
      ref = push(socket, "ping", %{"hello" => "there"})
      assert_reply ref, :ok, %{"hello" => "there"}
    end

    test "shout broadcasts to dashboard:lobby", %{socket: socket} do
      push(socket, "shout", %{"hello" => "all"})
      assert_broadcast "shout", %{"hello" => "all"}
    end

    test "broadcasts are pushed to the client", %{socket: socket} do
      broadcast_from!(socket, "broadcast", %{"some" => "data"})
      assert_push "broadcast", %{"some" => "data"}
    end
  end

  describe "correlation ID and logging context" do
    test "correlation ID persists across operations" do
      {:ok, _, socket} =
        UserSocket
        |> socket("dashboard_user", %{user_id: "dashboard"})
        |> subscribe_and_join(DashboardChannel, "dashboard:lobby")

      original_correlation_id = socket.assigns.correlation_id

      # Make a command call
      expect(OBSMock, :get_status, fn -> {:ok, %{connected: true}} end)
      ref = push(socket, "obs:get_status", %{})
      assert_reply ref, :ok, %{connected: true}

      # Correlation ID should remain the same
      assert socket.assigns.correlation_id == original_correlation_id
    end

    test "different rooms maintain separate correlation contexts" do
      {:ok, _, socket1} =
        UserSocket
        |> socket("user_1", %{user_id: "1"})
        |> subscribe_and_join(DashboardChannel, "dashboard:main")

      {:ok, _, socket2} =
        UserSocket
        |> socket("user_2", %{user_id: "2"})
        |> subscribe_and_join(DashboardChannel, "dashboard:control")

      assert socket1.assigns.room_id == "main"
      assert socket2.assigns.room_id == "control"
      assert socket1.assigns.correlation_id != socket2.assigns.correlation_id
    end
  end
end
