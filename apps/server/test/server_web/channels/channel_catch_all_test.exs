defmodule ServerWeb.ChannelCatchAllTest do
  @moduledoc """
  Test suite to verify all Phoenix channels handle unknown messages gracefully
  without crashing. Tests for both handle_in and handle_info catch-all handlers.
  """

  use ServerWeb.ChannelCase, async: true

  # Test data for unknown messages
  @unknown_handle_in_msg "unknown_command"
  @unknown_handle_info_msg {:unknown_event, %{data: "test"}}
  @test_payload %{"test" => "data"}

  describe "DashboardChannel catch-all handlers" do
    setup do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.DashboardChannel, "dashboard:main")
      {:ok, socket: socket}
    end

    test "handle_in returns noreply for unknown commands", %{socket: socket} do
      # Send unknown command - should not crash
      ref = push(socket, @unknown_handle_in_msg, @test_payload)
      # Should receive noreply (no response)
      assert_no_reply(ref)
    end

    test "handle_info logs and continues for unknown messages", %{socket: socket} do
      # Send unknown info message directly to channel process
      send(socket.channel_pid, @unknown_handle_info_msg)
      # Process should still be alive
      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end

    test "still handles known commands after unknown message", %{socket: socket} do
      # Send unknown message first
      send(socket.channel_pid, @unknown_handle_info_msg)

      # Should still handle ping correctly
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, response
      assert response.data.pong == true
    end
  end

  describe "EventsChannel catch-all handlers" do
    setup do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:all")
      {:ok, socket: socket}
    end

    test "handle_in returns noreply for unknown commands", %{socket: socket} do
      ref = push(socket, @unknown_handle_in_msg, @test_payload)
      assert_no_reply(ref)
    end

    test "handle_info logs and continues for unknown messages", %{socket: socket} do
      send(socket.channel_pid, @unknown_handle_info_msg)
      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end

    test "still receives events after unknown message", %{socket: socket} do
      # Send unknown message
      send(socket.channel_pid, @unknown_handle_info_msg)

      # Should still receive proper events
      event = %{
        type: "channel.chat.message",
        user_name: "TestUser",
        message: "test",
        timestamp: DateTime.utc_now()
      }

      send(socket.channel_pid, {:twitch_event, event})
      assert_push "chat_message", %{type: "channel.chat.message"}
    end
  end

  describe "OverlayChannel catch-all handlers" do
    setup do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.OverlayChannel, "overlay:obs")
      {:ok, socket: socket}
    end

    test "handle_in returns error for unknown commands", %{socket: socket} do
      ref = push(socket, @unknown_handle_in_msg, @test_payload)
      assert_reply ref, :error, %{message: "Unknown command: " <> @unknown_handle_in_msg}
    end

    test "handle_info logs and continues for unknown messages", %{socket: socket} do
      send(socket.channel_pid, @unknown_handle_info_msg)
      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end

    test "still handles overlay commands after unknown message", %{socket: socket} do
      send(socket.channel_pid, @unknown_handle_info_msg)

      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, response
      # OverlayChannel has a custom ping handler that doesn't use ResponseBuilder
      assert response.pong == true
      assert response.overlay_type == "obs"
    end
  end

  describe "StreamChannel catch-all handlers" do
    setup do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.StreamChannel, "stream:overlays")
      {:ok, socket: socket}
    end

    test "handle_in returns noreply for unknown commands", %{socket: socket} do
      ref = push(socket, @unknown_handle_in_msg, @test_payload)
      assert_no_reply(ref)
    end

    test "handle_info logs and continues for unknown messages", %{socket: socket} do
      send(socket.channel_pid, @unknown_handle_info_msg)
      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end

    test "still pushes stream updates after unknown message", %{socket: socket} do
      send(socket.channel_pid, @unknown_handle_info_msg)

      # Should still handle stream updates
      send(socket.channel_pid, {:show_change, %{show: "variety", game: "test", changed_at: DateTime.utc_now()}})
      assert_push "show_changed", %{show: "variety"}
    end
  end

  describe "TranscriptionChannel catch-all handlers" do
    setup do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.TranscriptionChannel, "transcription:live")
      {:ok, socket: socket}
    end

    test "handle_in returns error for unknown commands", %{socket: socket} do
      ref = push(socket, @unknown_handle_in_msg, @test_payload)
      assert_reply ref, :error, %{message: "Unknown command: " <> @unknown_handle_in_msg}
    end

    test "handle_info logs and continues for unknown messages", %{socket: socket} do
      send(socket.channel_pid, @unknown_handle_info_msg)
      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end

    test "still handles transcription events after unknown message", %{socket: socket} do
      send(socket.channel_pid, @unknown_handle_info_msg)

      # Should still handle transcription events
      send(socket.channel_pid, {:new_transcription, %{id: "123", text: "test"}})
      assert_push "new_transcription", %{id: "123"}
    end
  end

  describe "Multiple unknown messages stress test" do
    setup do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, socket: socket}
    end

    test "channels survive bombardment of unknown messages", %{socket: socket} do
      # Test each channel type
      channels = [
        {"dashboard:main", ServerWeb.DashboardChannel},
        {"events:all", ServerWeb.EventsChannel},
        {"overlay:obs", ServerWeb.OverlayChannel},
        {"stream:overlays", ServerWeb.StreamChannel},
        {"dashboard:services", ServerWeb.ServicesChannel},
        {"transcription:live", ServerWeb.TranscriptionChannel}
      ]

      for {topic, channel_module} <- channels do
        {:ok, _, socket} = subscribe_and_join(socket, channel_module, topic)

        # Send multiple unknown messages rapidly
        for i <- 1..10 do
          send(socket.channel_pid, {:unknown_msg, i})
          push(socket, "unknown_#{i}", %{data: i})
        end

        # Give time for messages to process
        Process.sleep(100)

        # Channel should still be alive
        assert Process.alive?(socket.channel_pid)

        # Should still respond to ping
        ref = push(socket, "ping", %{})
        assert_reply ref, :ok, response
        # Check for pong in different response formats
        assert response[:pong] == true || response[:data][:pong] == true
      end
    end
  end

  describe "Edge case message handling" do
    setup do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.DashboardChannel, "dashboard:main")
      {:ok, socket: socket}
    end

    test "handles nil messages", %{socket: socket} do
      send(socket.channel_pid, nil)
      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end

    test "handles atom messages", %{socket: socket} do
      send(socket.channel_pid, :random_atom)
      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end

    test "handles deeply nested messages", %{socket: socket} do
      nested = %{a: %{b: %{c: %{d: %{e: "deep"}}}}}
      send(socket.channel_pid, {:nested, nested})
      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end

    test "handles large messages", %{socket: socket} do
      large_data = String.duplicate("x", 10_000)
      send(socket.channel_pid, {:large, large_data})
      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end
  end

  # Helper to assert no reply is sent
  defp assert_no_reply(ref, timeout \\ 100) do
    refute_receive %Phoenix.Socket.Reply{ref: ^ref}, timeout
  end
end
