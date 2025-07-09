defmodule Integration.WebSocketFlowTest do
  @moduledoc """
  Simple integration tests for WebSocket takeover flows.
  Validates dashboard → server → overlay communication works for streaming.
  """

  use ServerWeb.ChannelCase, async: false

  alias Server.StreamProducer

  @moduletag :integration

  # Test constants
  @takeover_payload %{
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

  describe "Takeover Flow" do
    test "dashboard can send takeover to overlays" do
      # Connect dashboard client
      dashboard_socket = socket(ServerWeb.UserSocket, "dashboard", %{correlation_id: "test-dashboard"})
      {:ok, _, dashboard} = subscribe_and_join(dashboard_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Connect overlay client
      overlay_socket = socket(ServerWeb.UserSocket, "overlay", %{correlation_id: "test-overlay"})
      {:ok, _, _overlay} = subscribe_and_join(overlay_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Send takeover from dashboard
      ref = push(dashboard, "takeover", @takeover_payload)

      # Verify dashboard gets acknowledgment
      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "takeover_sent", type: _},
        meta: %{timestamp: _, server_version: _}
      }

      # Verify overlay receives takeover push
      assert_push "takeover", broadcast_message

      # Validate takeover content
      assert broadcast_message.type == "technical-difficulties"
      assert broadcast_message.message == @takeover_payload["message"]
      assert broadcast_message.duration == @takeover_payload["duration"]
    end

    test "takeover clear works correctly" do
      # Connect clients
      dashboard_socket = socket(ServerWeb.UserSocket, "dashboard", %{correlation_id: "test-dashboard"})
      {:ok, _, dashboard} = subscribe_and_join(dashboard_socket, ServerWeb.StreamChannel, "stream:overlays")

      overlay_socket = socket(ServerWeb.UserSocket, "overlay", %{correlation_id: "test-overlay"})
      {:ok, _, _overlay} = subscribe_and_join(overlay_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Send takeover first
      push(dashboard, "takeover", @takeover_payload)
      assert_push "takeover", _takeover_msg

      # Clear takeover
      ref = push(dashboard, "takeover_clear", %{})

      # Verify dashboard gets acknowledgment
      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "takeover_cleared"},
        meta: %{timestamp: _, server_version: _}
      }

      # Verify overlay receives clear push
      assert_push "takeover_clear", clear_message
      assert Map.has_key?(clear_message, :timestamp)
    end

    test "queue client does not receive overlay takeovers" do
      # Connect dashboard and queue clients
      dashboard_socket = socket(ServerWeb.UserSocket, "dashboard", %{correlation_id: "test-dashboard"})
      {:ok, _, dashboard} = subscribe_and_join(dashboard_socket, ServerWeb.StreamChannel, "stream:overlays")

      queue_socket = socket(ServerWeb.UserSocket, "queue", %{correlation_id: "test-queue"})
      {:ok, _, _queue} = subscribe_and_join(queue_socket, ServerWeb.StreamChannel, "stream:queue")

      # Send takeover from dashboard
      ref = push(dashboard, "takeover", @takeover_payload)

      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "takeover_sent", type: _},
        meta: %{timestamp: _, server_version: _}
      }

      # Verify queue does NOT receive takeover
      refute_push "takeover", 100
    end
  end

  describe "Multi-Client Connection" do
    test "multiple overlays can connect and receive takeovers" do
      # Connect dashboard
      dashboard_socket = socket(ServerWeb.UserSocket, "dashboard", %{correlation_id: "test-dashboard"})
      {:ok, _, dashboard} = subscribe_and_join(dashboard_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Connect multiple overlays
      overlay1_socket = socket(ServerWeb.UserSocket, "overlay1", %{correlation_id: "test-overlay-1"})
      {:ok, _, _overlay1} = subscribe_and_join(overlay1_socket, ServerWeb.StreamChannel, "stream:overlays")

      overlay2_socket = socket(ServerWeb.UserSocket, "overlay2", %{correlation_id: "test-overlay-2"})
      {:ok, _, _overlay2} = subscribe_and_join(overlay2_socket, ServerWeb.StreamChannel, "stream:overlays")

      # Send takeover
      ref = push(dashboard, "takeover", @takeover_payload)

      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "takeover_sent", type: _},
        meta: %{timestamp: _, server_version: _}
      }

      # Both overlays should receive takeover
      assert_push "takeover", msg1
      assert_push "takeover", msg2

      # Validate both messages
      assert msg1.type == "technical-difficulties"
      assert msg2.type == "technical-difficulties"
    end
  end
end
