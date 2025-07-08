defmodule Integration.WebSocketFlowTest do
  @moduledoc """
  Simple integration tests for WebSocket emergency flows.
  Validates dashboard → server → overlay communication works for streaming.
  """

  use ServerWeb.ChannelCase, async: false

  alias Server.StreamProducer

  @moduletag :integration

  # Test constants
  @emergency_payload %{
    "type" => "technical-difficulties",
    "message" => "We're experiencing technical difficulties. Please stand by.",
    "duration" => 30_000
  }

  setup do
    # Ensure clean StreamProducer state
    case Process.whereis(StreamProducer) do
      nil ->
        {:ok, _} = StreamProducer.start_link([])

      pid ->
        GenServer.stop(pid)
        {:ok, _} = StreamProducer.start_link([])
    end

    :ok
  end

  describe "Emergency Override Flow" do
    test "dashboard can send emergency to overlays" do
      # Connect dashboard client
      dashboard_socket = socket(ServerWeb.UserSocket, "dashboard", %{correlation_id: "test-dashboard"})
      {:ok, _, dashboard} = subscribe_and_join(dashboard_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Connect overlay client
      overlay_socket = socket(ServerWeb.UserSocket, "overlay", %{correlation_id: "test-overlay"})
      {:ok, _, _overlay} = subscribe_and_join(overlay_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Send emergency from dashboard
      ref = push(dashboard, "emergency_override", @emergency_payload)

      # Verify dashboard gets acknowledgment
      assert_reply ref, :ok, %{status: "emergency_sent"}

      # Verify overlay receives emergency push
      assert_push "emergency_override", broadcast_message

      # Validate emergency content
      assert broadcast_message.type == "technical-difficulties"
      assert broadcast_message.message == @emergency_payload["message"]
      assert broadcast_message.duration == @emergency_payload["duration"]
    end

    test "emergency clear works correctly" do
      # Connect clients
      dashboard_socket = socket(ServerWeb.UserSocket, "dashboard", %{correlation_id: "test-dashboard"})
      {:ok, _, dashboard} = subscribe_and_join(dashboard_socket, ServerWeb.StreamChannel, "stream:overlays")

      overlay_socket = socket(ServerWeb.UserSocket, "overlay", %{correlation_id: "test-overlay"})
      {:ok, _, _overlay} = subscribe_and_join(overlay_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Send emergency first
      push(dashboard, "emergency_override", @emergency_payload)
      assert_push "emergency_override", _emergency_msg

      # Clear emergency
      ref = push(dashboard, "emergency_clear", %{})

      # Verify dashboard gets acknowledgment
      assert_reply ref, :ok, %{status: "emergency_cleared"}

      # Verify overlay receives clear push
      assert_push "emergency_clear", clear_message
      assert Map.has_key?(clear_message, :timestamp)
    end

    test "queue client does not receive overlay emergencies" do
      # Connect dashboard and queue clients
      dashboard_socket = socket(ServerWeb.UserSocket, "dashboard", %{correlation_id: "test-dashboard"})
      {:ok, _, dashboard} = subscribe_and_join(dashboard_socket, ServerWeb.StreamChannel, "stream:overlays")

      queue_socket = socket(ServerWeb.UserSocket, "queue", %{correlation_id: "test-queue"})
      {:ok, _, _queue} = subscribe_and_join(queue_socket, ServerWeb.StreamChannel, "stream:queue")

      # Send emergency from dashboard
      ref = push(dashboard, "emergency_override", @emergency_payload)
      assert_reply ref, :ok, %{status: "emergency_sent"}

      # Verify queue does NOT receive emergency
      refute_push "emergency_override", 100
    end
  end

  describe "Multi-Client Connection" do
    test "multiple overlays can connect and receive emergencies" do
      # Connect dashboard
      dashboard_socket = socket(ServerWeb.UserSocket, "dashboard", %{correlation_id: "test-dashboard"})
      {:ok, _, dashboard} = subscribe_and_join(dashboard_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Connect multiple overlays
      overlay1_socket = socket(ServerWeb.UserSocket, "overlay1", %{correlation_id: "test-overlay-1"})
      {:ok, _, _overlay1} = subscribe_and_join(overlay1_socket, ServerWeb.StreamChannel, "stream:overlays")

      overlay2_socket = socket(ServerWeb.UserSocket, "overlay2", %{correlation_id: "test-overlay-2"})
      {:ok, _, _overlay2} = subscribe_and_join(overlay2_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Send emergency
      ref = push(dashboard, "emergency_override", @emergency_payload)
      assert_reply ref, :ok, %{status: "emergency_sent"}

      # Both overlays should receive emergency
      assert_push "emergency_override", msg1
      assert_push "emergency_override", msg2

      # Validate both messages
      assert msg1.type == "technical-difficulties"
      assert msg2.type == "technical-difficulties"
    end
  end
end
