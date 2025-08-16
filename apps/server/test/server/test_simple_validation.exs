defmodule Server.SimpleValidationTest do
  @moduledoc """
  Simple P0 validation test to check basic unified event routing.
  """

  use ServerWeb.ChannelCase, async: true

  alias Server.Events

  describe "Basic Unified Event Routing" do
    @tag :p0_critical
    test "single event routes through unified system" do
      # Setup monitoring
      {:ok, socket} = connect(ServerWeb.UserSocket, %{})
      {:ok, _, socket} = subscribe_and_join(socket, ServerWeb.EventsChannel, "events:all")

      # Process a simple event
      assert :ok = Events.process_event("channel.follow", %{
        "user_id" => "123456",
        "user_login" => "testuser",
        "broadcaster_user_id" => "789012",
        "broadcaster_user_login" => "teststreamer"
      })

      # Verify the event is received
      assert_receive %Phoenix.Socket.Message{
        topic: "events:all",
        event: "follower",
        payload: payload
      }

      assert payload.type == "channel.follow"
      assert payload.source == :twitch
      assert is_binary(payload.correlation_id)
    end
  end
end