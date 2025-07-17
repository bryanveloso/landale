defmodule ServerWeb.StreamChannelTest do
  use ServerWeb.ChannelCase, async: false

  @moduletag :web

  alias Server.StreamProducer
  alias ServerWeb.{StreamChannel, UserSocket}

  # Test constants
  @test_correlation_id "test-correlation-id"
  @valid_takeover_types ["technical-difficulties", "screen-cover", "please-stand-by", "custom"]
  @default_takeover_payload %{
    "type" => "technical-difficulties",
    "message" => "We'll be right back!",
    "duration" => 30_000
  }
  @default_force_content_payload %{
    "type" => "manual_override",
    "data" => %{"message" => "Test override", "source" => "test"},
    "duration" => 5000
  }
  @broadcast_takeover_payload %{
    "type" => "please-stand-by",
    "message" => "Broadcast test",
    "duration" => 5000
  }

  # Global setup for process management
  setup do
    ensure_clean_stream_producer()
    :ok
  end

  describe "stream:overlays channel" do
    setup do
      socket = setup_overlay_socket("user_id")
      %{socket: socket}
    end

    test "ping replies with pong and timestamp", %{socket: socket} do
      ref = push(socket, "ping", %{"hello" => "there"})
      assert_reply ref, :ok, response

      assert %{
               success: true,
               data: %{pong: true, timestamp: timestamp},
               meta: %{timestamp: _, server_version: _}
             } = response

      assert is_integer(timestamp)
    end

    test "takeover with valid payload succeeds", %{socket: socket} do
      ref = push(socket, "takeover", @default_takeover_payload)

      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "takeover_sent", type: "technical-difficulties"},
        meta: %{timestamp: _, server_version: _}
      }
    end

    test "takeover with invalid payload fails", %{socket: socket} do
      ref = push(socket, "takeover", %{"invalid" => "payload"})

      assert_reply ref, :error, %{
        success: false,
        error: %{code: "validation_failed", message: _, timestamp: _}
      }
    end

    test "takeover_clear succeeds", %{socket: socket} do
      ref = push(socket, "takeover_clear", %{})

      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "takeover_cleared"},
        meta: %{timestamp: _, server_version: _}
      }
    end

    test "force_content adds manual override", %{socket: socket} do
      ref = push(socket, "force_content", @default_force_content_payload)

      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "override_sent", type: "manual_override"},
        meta: %{timestamp: _, server_version: _}
      }
    end
  end

  describe "stream:queue channel" do
    setup do
      socket = setup_queue_socket("user_id")
      %{socket: socket}
    end

    test "ping replies with pong and timestamp", %{socket: socket} do
      ref = push(socket, "ping", %{"test" => "data"})
      assert_reply ref, :ok, response

      assert %{
               success: true,
               data: %{pong: true, timestamp: timestamp},
               meta: %{timestamp: _, server_version: _}
             } = response

      assert is_integer(timestamp)
    end

    test "remove_queue_item with valid ID succeeds", %{socket: socket} do
      ref = push(socket, "remove_queue_item", %{"id" => "test-item"})

      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "item_removed", id: "test-item"},
        meta: %{timestamp: _, server_version: _}
      }
    end
  end

  describe "takeover broadcasting" do
    test "takeover broadcasts to all overlay clients" do
      # Connect multiple overlay clients
      socket1 = setup_overlay_socket("client_1", %{correlation_id: "test-1"})
      _socket2 = setup_overlay_socket("client_2", %{correlation_id: "test-2"})

      # Send takeover from first client
      ref = push(socket1, "takeover", @broadcast_takeover_payload)

      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "takeover_sent", type: _},
        meta: %{timestamp: _, server_version: _}
      }

      # Both clients should receive the broadcast
      assert_push "takeover", broadcast1
      assert_push "takeover", broadcast2

      # Verify broadcast content
      assert broadcast1.message == "Broadcast test"
      assert broadcast2.message == "Broadcast test"
      assert broadcast1.type == "please-stand-by"
      assert broadcast2.type == "please-stand-by"
    end

    test "takeover_clear broadcasts to all overlay clients" do
      # Connect multiple overlay clients
      socket1 = setup_overlay_socket("client_1", %{correlation_id: "test-1"})
      _socket2 = setup_overlay_socket("client_2", %{correlation_id: "test-2"})

      ref = push(socket1, "takeover_clear", %{})

      assert_reply ref, :ok, %{
        success: true,
        data: %{operation: "takeover_cleared"},
        meta: %{timestamp: _, server_version: _}
      }

      # Both clients should receive the clear broadcast
      assert_push "takeover_clear", _clear1
      assert_push "takeover_clear", _clear2
    end
  end

  describe "message validation" do
    setup do
      socket = setup_overlay_socket("user_id")
      %{socket: socket}
    end

    test "takeover requires type field", %{socket: socket} do
      ref = push(socket, "takeover", %{"message" => "test"})

      assert_reply ref, :error, %{
        success: false,
        error: %{code: "validation_failed", message: _, timestamp: _}
      }
    end

    test "takeover requires message field for most types", %{socket: socket} do
      ref = push(socket, "takeover", %{"type" => "technical-difficulties"})

      assert_reply ref, :error, %{
        success: false,
        error: %{code: "validation_failed", message: _, timestamp: _}
      }
    end

    test "takeover accepts all valid types", %{socket: socket} do
      for type <- @valid_takeover_types do
        ref = push(socket, "takeover", %{"type" => type, "message" => "test"})

        assert_reply ref, :ok, %{
          success: true,
          data: %{operation: "takeover_sent", type: ^type},
          meta: %{timestamp: _, server_version: _}
        }
      end
    end
  end

  describe "edge cases and error handling" do
    setup do
      socket = setup_overlay_socket("user_id")
      %{socket: socket}
    end

    test "handles nil correlation_id gracefully", %{} do
      nil_socket = setup_overlay_socket("test_user", %{correlation_id: nil})
      ref = push(nil_socket, "ping", %{})

      assert_reply ref, :ok, %{
        success: true,
        data: %{pong: true, timestamp: _},
        meta: %{timestamp: _, server_version: _}
      }
    end

    test "handles takeover override with missing required fields", %{socket: socket} do
      # Test completely empty payload
      ref = push(socket, "takeover", %{})

      assert_reply ref, :error, %{
        success: false,
        error: %{code: "validation_failed", message: _, timestamp: _}
      }

      # Test payload with only type (missing message)
      ref = push(socket, "takeover", %{"type" => "custom"})

      assert_reply ref, :error, %{
        success: false,
        error: %{code: "validation_failed", message: _, timestamp: _}
      }
    end

    test "request_state sends stream state", %{socket: socket} do
      push(socket, "request_state", %{})

      # Should receive a push message (no reply expected)
      assert_push "stream_state", state_data
      assert Map.has_key?(state_data, :current_show)
      assert Map.has_key?(state_data, :active_content)
    end

    test "request_queue_state returns queue format", %{} do
      socket = setup_queue_socket("queue_user")
      push(socket, "request_queue_state", %{})

      # Should receive a push message (no reply expected)
      assert_push "queue_state", queue_data
      assert Map.has_key?(queue_data, :queue)
      assert Map.has_key?(queue_data, :metrics)
      assert is_list(queue_data[:queue])
    end

    test "unhandled events are ignored gracefully", %{socket: socket} do
      ref = push(socket, "unknown_event", %{"data" => "test"})
      # Should not crash, but also should not reply
      refute_reply ref, :ok
      refute_reply ref, :error
    end
  end

  # Helper functions for process and socket management

  defp ensure_clean_stream_producer do
    case Process.whereis(StreamProducer) do
      nil ->
        {:ok, _} = StreamProducer.start_link([])

      pid ->
        GenServer.stop(pid)
        {:ok, _} = StreamProducer.start_link([])
    end

    on_exit(fn -> cleanup_stream_producer() end)
  end

  defp cleanup_stream_producer do
    case Process.whereis(StreamProducer) do
      nil ->
        :ok

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        else
          :ok
        end
    end
  end

  defp setup_overlay_socket(user_id, assigns \\ %{}) do
    default_assigns = %{correlation_id: @test_correlation_id}
    final_assigns = Map.merge(default_assigns, assigns)

    {:ok, _, socket} =
      UserSocket
      |> socket(user_id, final_assigns)
      |> subscribe_and_join(StreamChannel, "stream:overlays")

    socket
  end

  defp setup_queue_socket(user_id, assigns \\ %{}) do
    default_assigns = %{correlation_id: @test_correlation_id}
    final_assigns = Map.merge(default_assigns, assigns)

    {:ok, _, socket} =
      UserSocket
      |> socket(user_id, final_assigns)
      |> subscribe_and_join(StreamChannel, "stream:queue")

    socket
  end
end
