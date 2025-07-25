defmodule Server.Services.Twitch.MessageRouterTest do
  use ExUnit.Case, async: true

  alias Server.Services.Twitch.{MessageRouter, SessionManager}

  defmodule MockEventHandler do
    @moduledoc false

    def process_event("test.success", _data), do: :ok
    def process_event("test.error", _data), do: {:error, "Test error"}
    def process_event(_type, _data), do: :ok
  end

  describe "MessageRouter initialization" do
    test "creates router with default state" do
      router_state = MessageRouter.new()

      assert router_state.session_manager == nil
      assert router_state.event_handler == Server.Services.Twitch.EventHandler
      assert router_state.metrics.messages_routed == 0
      assert router_state.metrics.messages_by_type == %{}
      assert router_state.metrics.errors == 0
    end

    test "creates router with custom options" do
      {:ok, session_manager} = SessionManager.start_link(owner: self(), name: nil)

      router_state =
        MessageRouter.new(
          session_manager: session_manager,
          event_handler: MockEventHandler
        )

      assert router_state.session_manager == session_manager
      assert router_state.event_handler == MockEventHandler
    end
  end

  describe "message routing" do
    setup do
      {:ok, session_manager} = SessionManager.start_link(owner: self(), name: nil)

      router_state =
        MessageRouter.new(
          session_manager: session_manager,
          event_handler: MockEventHandler
        )

      {:ok, router_state: router_state}
    end

    test "routes session_welcome message", %{router_state: router_state} do
      message = %{
        "metadata" => %{
          "message_id" => "test-123",
          "message_type" => "session_welcome",
          "message_timestamp" => "2024-01-01T00:00:00Z"
        },
        "payload" => %{
          "session" => %{
            "id" => "session-123",
            "status" => "connected",
            "keepalive_timeout_seconds" => 10
          }
        }
      }

      {:ok, updated_state} = MessageRouter.route_message(message, router_state)

      # Verify session manager received the message
      assert_receive {:twitch_session, {:session_established, "session-123", _}}

      # Check metrics
      assert updated_state.metrics.messages_routed == 1
      assert updated_state.metrics.messages_by_type["session_welcome"] == 1
    end

    test "routes session_keepalive message", %{router_state: router_state} do
      message = %{
        "metadata" => %{
          "message_id" => "test-456",
          "message_type" => "session_keepalive",
          "message_timestamp" => "2024-01-01T00:00:01Z"
        }
      }

      {:ok, updated_state} = MessageRouter.route_message(message, router_state)

      # Keepalive should not generate any messages
      refute_receive {:twitch_session, _}

      # Check metrics
      assert updated_state.metrics.messages_routed == 1
      assert updated_state.metrics.messages_by_type["session_keepalive"] == 1
    end

    test "routes session_reconnect message", %{router_state: router_state} do
      message = %{
        "metadata" => %{
          "message_id" => "test-789",
          "message_type" => "session_reconnect",
          "message_timestamp" => "2024-01-01T00:00:02Z"
        },
        "payload" => %{
          "session" => %{
            "id" => "session-456",
            "status" => "reconnecting",
            "keepalive_timeout_seconds" => 10,
            "reconnect_url" => "wss://example.twitch.tv/reconnect"
          }
        }
      }

      {:ok, updated_state} = MessageRouter.route_message(message, router_state)

      # Verify session manager received the reconnect request
      assert_receive {:twitch_session, {:session_reconnect_requested, "wss://example.twitch.tv/reconnect"}}

      # Check metrics
      assert updated_state.metrics.messages_routed == 1
      assert updated_state.metrics.messages_by_type["session_reconnect"] == 1
    end

    test "routes notification message", %{router_state: router_state} do
      message = %{
        "metadata" => %{
          "message_id" => "test-001",
          "message_type" => "notification",
          "message_timestamp" => "2024-01-01T00:00:03Z",
          "subscription_type" => "test.success",
          "subscription_version" => "1"
        },
        "payload" => %{
          "subscription" => %{
            "id" => "sub-123",
            "type" => "test.success",
            "version" => "1"
          },
          "event" => %{
            "id" => "event-123",
            "data" => "test"
          }
        }
      }

      {:ok, updated_state} = MessageRouter.route_message(message, router_state)

      # Check metrics
      assert updated_state.metrics.messages_routed == 1
      assert updated_state.metrics.messages_by_type["notification"] == 1
    end

    test "handles event handler error", %{router_state: router_state} do
      message = %{
        "metadata" => %{
          "message_id" => "test-002",
          "message_type" => "notification",
          "message_timestamp" => "2024-01-01T00:00:04Z",
          "subscription_type" => "test.error",
          "subscription_version" => "1"
        },
        "payload" => %{
          "event" => %{
            "id" => "event-456",
            "data" => "test"
          }
        }
      }

      {:error, {:event_processing_failed, "Test error"}, updated_state} =
        MessageRouter.route_message(message, router_state)

      # Metrics should still be updated
      assert updated_state.metrics.messages_routed == 1
      assert updated_state.metrics.messages_by_type["notification"] == 1
    end

    test "routes revocation message", %{router_state: router_state} do
      message = %{
        "metadata" => %{
          "message_id" => "test-003",
          "message_type" => "revocation",
          "message_timestamp" => "2024-01-01T00:00:05Z"
        },
        "payload" => %{
          "subscription" => %{
            "id" => "sub-789",
            "type" => "channel.follow",
            "version" => "1",
            "status" => "authorization_revoked",
            "condition" => %{
              "broadcaster_user_id" => "12345"
            }
          }
        }
      }

      {:ok, updated_state} = MessageRouter.route_message(message, router_state)

      # Check metrics
      assert updated_state.metrics.messages_routed == 1
      assert updated_state.metrics.messages_by_type["revocation"] == 1
    end

    test "handles unknown message type", %{router_state: router_state} do
      message = %{
        "metadata" => %{
          "message_id" => "test-999",
          "message_type" => "unknown_type",
          "message_timestamp" => "2024-01-01T00:00:06Z"
        }
      }

      {:ok, updated_state} = MessageRouter.route_message(message, router_state)

      # Check metrics
      assert updated_state.metrics.messages_routed == 1
      assert updated_state.metrics.messages_by_type["unknown_type"] == 1
    end
  end

  describe "frame routing" do
    setup do
      router_state = MessageRouter.new(event_handler: MockEventHandler)
      {:ok, router_state: router_state}
    end

    test "routes valid JSON frame", %{router_state: router_state} do
      frame =
        Jason.encode!(%{
          "metadata" => %{
            "message_id" => "test-frame",
            "message_type" => "session_keepalive",
            "message_timestamp" => "2024-01-01T00:00:00Z"
          }
        })

      {:ok, updated_state} = MessageRouter.route_frame(frame, router_state)

      assert updated_state.metrics.messages_routed == 1
      assert updated_state.metrics.messages_by_type["session_keepalive"] == 1
    end

    test "handles invalid JSON frame", %{router_state: router_state} do
      frame = "invalid json {"

      {:error, {:decode_error, _}, updated_state} = MessageRouter.route_frame(frame, router_state)

      assert updated_state.metrics.errors == 1
      assert updated_state.metrics.messages_routed == 0
    end
  end

  describe "metrics" do
    test "tracks multiple messages" do
      router_state = MessageRouter.new(event_handler: MockEventHandler)

      messages = [
        %{
          "metadata" => %{
            "message_type" => "session_keepalive",
            "message_id" => "1",
            "message_timestamp" => "2024-01-01T00:00:00Z"
          }
        },
        %{
          "metadata" => %{
            "message_type" => "session_keepalive",
            "message_id" => "2",
            "message_timestamp" => "2024-01-01T00:00:01Z"
          }
        },
        %{
          "metadata" => %{
            "message_type" => "notification",
            "message_id" => "3",
            "message_timestamp" => "2024-01-01T00:00:02Z",
            "subscription_type" => "test"
          },
          "payload" => %{"event" => %{}}
        },
        %{
          "metadata" => %{
            "message_type" => "unknown",
            "message_id" => "4",
            "message_timestamp" => "2024-01-01T00:00:03Z"
          }
        }
      ]

      final_state =
        Enum.reduce(messages, router_state, fn message, state ->
          {:ok, new_state} = MessageRouter.route_message(message, state)
          new_state
        end)

      metrics = MessageRouter.get_metrics(final_state)
      assert metrics.messages_routed == 4
      assert metrics.messages_by_type["session_keepalive"] == 2
      assert metrics.messages_by_type["notification"] == 1
      assert metrics.messages_by_type["unknown"] == 1
    end

    test "resets metrics" do
      router_state = MessageRouter.new()

      # Route some messages
      message = %{
        "metadata" => %{
          "message_type" => "session_keepalive",
          "message_id" => "1",
          "message_timestamp" => "2024-01-01T00:00:00Z"
        }
      }

      {:ok, state_with_metrics} = MessageRouter.route_message(message, router_state)

      # Reset metrics
      reset_state = MessageRouter.reset_metrics(state_with_metrics)

      assert reset_state.metrics.messages_routed == 0
      assert reset_state.metrics.messages_by_type == %{}
      assert reset_state.metrics.errors == 0
    end
  end

  describe "error handling" do
    test "handles missing session manager" do
      # No session_manager
      router_state = MessageRouter.new()

      message = %{
        "metadata" => %{
          "message_id" => "test-no-sm",
          "message_type" => "session_welcome",
          "message_timestamp" => "2024-01-01T00:00:00Z"
        },
        "payload" => %{
          "session" => %{"id" => "session-123"}
        }
      }

      {:error, :no_session_manager, updated_state} = MessageRouter.route_message(message, router_state)

      # Metrics should still be updated
      assert updated_state.metrics.messages_routed == 1
    end
  end
end
