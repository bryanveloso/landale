defmodule ServerWeb.CatchAllHandlerTest do
  @moduledoc """
  Focused test suite to verify Phoenix channels have catch-all handlers
  that prevent crashes from unknown messages.
  """

  use ServerWeb.ChannelCase, async: false
  import Hammox

  setup :verify_on_exit!

  setup do
    # Stub any required mocks
    stub(Server.Mocks.OBSMock, :get_status, fn -> {:error, "not connected"} end)
    stub(Server.Mocks.TwitchMock, :get_status, fn -> {:error, "not connected"} end)

    # Start required processes if needed
    if !Process.whereis(Server.StreamProducer) do
      {:ok, _} = Server.StreamProducer.start_link([])
    end

    :ok
  end

  describe "Catch-all handler verification" do
    test "DashboardChannel survives unknown handle_info messages" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.DashboardChannel, "dashboard:main")

      # Send various unknown messages
      send(socket.channel_pid, :unknown_atom)
      send(socket.channel_pid, {:unknown_tuple, "data"})
      send(socket.channel_pid, %{unknown: "map"})
      send(socket.channel_pid, ["unknown", "list"])

      # Give time to process
      Process.sleep(50)

      # Channel should still be alive
      assert Process.alive?(socket.channel_pid)

      # Should still respond to known commands
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, response
      assert response.data.pong == true
    end

    test "EventsChannel survives unknown handle_info messages" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:all")

      # Send unknown messages
      send(socket.channel_pid, :random_event)
      send(socket.channel_pid, {:not_a_real_event, %{}})

      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)

      # Should still handle known events
      event =
        Server.Events.Event.new("channel.chat.message", :twitch, %{
          message: %{text: "test"},
          user_name: "TestUser"
        })

      send(socket.channel_pid, {:event, event})
      assert_push "chat_message", %{type: "channel.chat.message"}
    end

    test "OverlayChannel survives unknown handle_info messages" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.OverlayChannel, "overlay:system")

      # Send unknown messages
      send(socket.channel_pid, :unknown_overlay_event)
      send(socket.channel_pid, {:fake_event, "data"})

      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)

      # Should still handle ping
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, %{pong: true}
    end

    test "StreamChannel survives unknown handle_info messages" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.StreamChannel, "stream:overlays")

      # Send unknown messages
      send(socket.channel_pid, :unknown_stream_event)
      send(socket.channel_pid, {:not_real, %{data: "test"}})

      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)
    end

    test "TranscriptionChannel survives unknown handle_info messages" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.TranscriptionChannel, "transcription:live")

      # Send unknown messages
      send(socket.channel_pid, :unknown_transcription)
      send(socket.channel_pid, {:fake_transcript, "data"})

      Process.sleep(50)
      assert Process.alive?(socket.channel_pid)

      # Should still handle known events
      send(socket.channel_pid, {:new_transcription, %{id: "123", text: "test"}})
      assert_push "new_transcription", %{id: "123"}
    end
  end

  describe "Unknown handle_in commands" do
    test "channels handle unknown commands without crashing" do
      channels_to_test = [
        {ServerWeb.DashboardChannel, "dashboard:main", :noreply},
        {ServerWeb.EventsChannel, "events:all", :noreply},
        {ServerWeb.OverlayChannel, "overlay:system", :simple_error},
        {ServerWeb.StreamChannel, "stream:overlays", :noreply},
        {ServerWeb.ServicesChannel, "dashboard:services", :structured_error},
        {ServerWeb.TranscriptionChannel, "transcription:live", :simple_error}
      ]

      for {channel_module, topic, expected_response} <- channels_to_test do
        {:ok, socket} = connect(ServerWeb.UserSocket, %{})
        {:ok, _, socket} = subscribe_and_join(socket, channel_module, topic)

        # Send unknown command
        ref = push(socket, "totally_unknown_command", %{"data" => "test"})

        case expected_response do
          :noreply ->
            # Should not receive a reply for channels that just log
            refute_receive %Phoenix.Socket.Reply{ref: ^ref}, 100

          :simple_error ->
            # Should receive simple error reply (OverlayChannel, TranscriptionChannel)
            assert_reply ref, :error, %{message: "Unknown command: totally_unknown_command"}

          :structured_error ->
            # Should receive structured error reply (ServicesChannel uses ResponseBuilder)
            assert_reply ref, :error, %{
              success: false,
              error: %{
                code: "unknown_command",
                message: "Unknown command: totally_unknown_command"
              }
            }
        end

        # Channel should still be alive
        assert Process.alive?(socket.channel_pid)
      end
    end
  end

  describe "Stress testing with many unknown messages" do
    test "channels survive rapid unknown message bombardment" do
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.DashboardChannel, "dashboard:main")

      # Send 100 unknown messages rapidly
      for i <- 1..100 do
        send(socket.channel_pid, {:unknown, i})

        if rem(i, 10) == 0 do
          push(socket, "unknown_cmd_#{i}", %{})
        end
      end

      # Give time to process all messages
      Process.sleep(200)

      # Channel should still be alive
      assert Process.alive?(socket.channel_pid)

      # Should still work
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, response
      assert response.data.pong == true
    end
  end
end
