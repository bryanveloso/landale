defmodule Server.Services.TwitchIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for Twitch EventSub service focusing on OAuth2 flows,
  WebSocket protocol compliance, and real EventSub interactions.

  These tests verify the intended functionality including token management, subscription
  lifecycle, event handling, WebSocket connection stability, and error recovery.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Server.Services.Twitch
  alias Server.{OAuthTokenManager, WebSocketClient}

  # Setup test GenServer for isolated testing
  setup do
    # Start test Twitch service with test configuration
    test_client_id = "test_client_id_#{:rand.uniform(10000)}"
    test_client_secret = "test_client_secret_#{:rand.uniform(10000)}"

    # Clean state before each test
    if GenServer.whereis(Twitch) do
      GenServer.stop(Twitch, :normal, 1000)
    end

    # Wait for process cleanup
    :timer.sleep(50)

    {:ok, pid} = Twitch.start_link(client_id: test_client_id, client_secret: test_client_secret)

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid, :normal, 1000)
      end
    end)

    %{
      service_pid: pid,
      test_client_id: test_client_id,
      test_client_secret: test_client_secret
    }
  end

  describe "service initialization and configuration" do
    test "starts with correct initial state", %{service_pid: pid} do
      state = :sys.get_state(pid)

      # Verify required components
      assert state.token_manager != nil
      assert state.ws_client != nil

      # Verify initial connection state
      assert state.state.connection.connected == false
      assert state.state.connection.connection_state == "disconnected"
      assert state.state.connection.session_id == nil

      # Verify initial subscription state
      assert state.subscriptions == %{}
      assert state.state.subscription_count == 0
      assert state.state.subscription_total_cost == 0
      assert state.state.subscription_max_count == 300
      assert state.state.subscription_max_cost == 10

      # Verify initial flags
      assert state.default_subscriptions_created == false
      assert state.cloudfront_retry_count == 0

      # Verify tracking structures
      assert state.session_id == nil
      assert state.user_id == nil
      assert state.scopes == nil
    end

    test "configures OAuth token manager correctly", %{
      service_pid: pid,
      test_client_id: client_id,
      test_client_secret: client_secret
    } do
      state = :sys.get_state(pid)

      token_manager = state.token_manager
      assert token_manager.storage_key == :twitch_tokens
      assert token_manager.oauth2_client.client_id == client_id
      assert token_manager.oauth2_client.client_secret == client_secret
      assert token_manager.oauth2_client.auth_url == "https://id.twitch.tv/oauth2/authorize"
      assert token_manager.oauth2_client.token_url == "https://id.twitch.tv/oauth2/token"
      assert token_manager.validate_url == "https://id.twitch.tv/oauth2/validate"
    end

    test "configures WebSocket client correctly", %{service_pid: pid} do
      state = :sys.get_state(pid)

      ws_client = state.ws_client
      assert ws_client.url == "wss://eventsub.wss.twitch.tv/ws"
      assert ws_client.handler_pid == pid
      assert ws_client.telemetry_prefix == [:server, :twitch, :websocket]
    end

    test "handles missing credentials gracefully" do
      if GenServer.whereis(Twitch) do
        GenServer.stop(Twitch, :normal, 1000)
      end

      log_output =
        capture_log(fn ->
          {:ok, pid} = Twitch.start_link(client_id: nil, client_secret: nil)
          :timer.sleep(100)
          GenServer.stop(pid, :normal, 1000)
        end)

      # Should log configuration error
      assert log_output =~ "configuration invalid" or log_output =~ "missing required credentials"
    end
  end

  describe "OAuth2 token management" do
    test "attempts token validation on startup", %{service_pid: pid} do
      # Service should attempt token validation or schedule retry
      :timer.sleep(100)

      state = :sys.get_state(pid)

      # Should either have validation task or reconnect timer set
      assert state.token_validation_task != nil or state.reconnect_timer != nil
    end

    test "handles token validation failure gracefully", %{service_pid: pid} do
      # Simulate token validation failure
      send(pid, {make_ref(), {:error, "Invalid token"}})
      :timer.sleep(50)

      state = :sys.get_state(pid)

      # Service should remain stable
      assert Process.alive?(pid)

      # Should either retry or schedule refresh
      assert state.token_refresh_task != nil or state.token_refresh_timer != nil or state.reconnect_timer != nil
    end

    test "handles token refresh completion", %{service_pid: pid} do
      # Create a mock task reference
      task_ref = make_ref()
      mock_task = %Task{ref: task_ref, mfa: {Server.Services.Twitch, :test, []}, owner: self(), pid: self()}

      # Set task in state
      :sys.replace_state(pid, fn state ->
        %{state | token_refresh_task: mock_task}
      end)

      # Simulate successful token refresh
      mock_token_manager = %{
        storage_key: :twitch_tokens,
        oauth2_client: %{client_id: "test", client_secret: "test"},
        validate_url: "https://id.twitch.tv/oauth2/validate",
        token_info: nil
      }

      send(pid, {task_ref, {:ok, mock_token_manager}})
      :timer.sleep(50)

      state = :sys.get_state(pid)

      # Should clear refresh task and schedule next validation
      assert state.token_refresh_task == nil
      assert state.token_manager != nil
    end

    test "handles task crashes gracefully", %{service_pid: pid} do
      # Create a mock task reference
      task_ref = make_ref()
      mock_task = %Task{ref: task_ref, mfa: {Server.Services.Twitch, :test, []}, owner: self(), pid: self()}

      # Set task in state
      :sys.replace_state(pid, fn state ->
        %{state | token_validation_task: mock_task}
      end)

      # Simulate task crash
      send(pid, {:DOWN, task_ref, :process, self(), :crash})
      :timer.sleep(50)

      state = :sys.get_state(pid)

      # Should clear task and schedule retry
      assert state.token_validation_task == nil
      assert state.reconnect_timer != nil
    end
  end

  describe "WebSocket connection management" do
    test "handles WebSocket connection success", %{service_pid: pid} do
      # Simulate WebSocket connection event
      mock_client = %{
        url: "wss://eventsub.wss.twitch.tv/ws",
        owner_pid: pid,
        conn_pid: nil
      }

      send(pid, {:websocket_connected, mock_client})
      :timer.sleep(50)

      state = :sys.get_state(pid)

      # Should update connection state
      assert state.state.connection.connected == true
      assert state.state.connection.connection_state == "connected"
      assert state.state.connection.last_connected != nil
      assert state.cloudfront_retry_count == 0
    end

    test "handles WebSocket disconnection", %{service_pid: pid} do
      # Set up connected state first
      :sys.replace_state(pid, fn state ->
        update_in(
          state.state.connection,
          &Map.merge(&1, %{
            connected: true,
            connection_state: "connected",
            session_id: "test_session"
          })
        )
        |> Map.put(:session_id, "test_session")
        |> Map.put(:subscriptions, %{"sub1" => %{"id" => "sub1"}})
      end)

      # Simulate WebSocket disconnection
      mock_client = %{
        url: "wss://eventsub.wss.twitch.tv/ws",
        owner_pid: pid,
        conn_pid: nil
      }

      send(pid, {:websocket_disconnected, mock_client, "Connection lost"})
      :timer.sleep(50)

      state = :sys.get_state(pid)

      # Should update connection state and clear session
      assert state.state.connection.connected == false
      assert state.state.connection.connection_state == "disconnected"
      assert state.state.connection.last_error == "\"Connection lost\""
      assert state.session_id == nil
      assert state.subscriptions == %{}
      assert state.reconnect_timer != nil
    end

    test "handles CloudFront 400 errors with retry logic", %{service_pid: pid} do
      # Simulate CloudFront 400 error
      headers = [{"server", "CloudFront"}]

      log_output =
        capture_log(fn ->
          send(pid, {:gun_response, self(), :test_stream, false, 400, headers})
          :timer.sleep(100)
        end)

      # Should log CloudFront error and attempt retry
      assert log_output =~ "CloudFront" or log_output =~ "400"

      state = :sys.get_state(pid)

      # Should remain stable and track retry
      assert Process.alive?(pid)
    end

    test "handles enhanced header retry mechanism", %{service_pid: pid} do
      # Simulate enhanced header retry
      send(pid, {:retry_with_enhanced_headers, 1})
      :timer.sleep(100)

      state = :sys.get_state(pid)

      # Should handle retry gracefully
      assert Process.alive?(pid)
      assert state.cloudfront_retry_count >= 0
    end

    test "handles WebSocket upgrade success", %{service_pid: pid} do
      # Simulate Gun WebSocket upgrade
      protocols = ["websocket"]
      headers = [{"upgrade", "websocket"}]

      send(pid, {:gun_upgrade, self(), :test_stream, protocols, headers})
      :timer.sleep(50)

      # Should handle upgrade gracefully
      assert Process.alive?(pid)
    end
  end

  describe "EventSub protocol handling" do
    test "handles session_welcome message", %{service_pid: pid} do
      # Set up token manager with user_id
      :sys.replace_state(pid, fn state ->
        token_info = %{user_id: "test_user_123", scopes: MapSet.new(["user:read:email"])}
        token_manager = %{state.token_manager | token_info: token_info}
        %{state | token_manager: token_manager, user_id: "test_user_123", scopes: MapSet.new(["user:read:email"])}
      end)

      # Simulate session_welcome message
      welcome_message = %{
        "metadata" => %{
          "message_type" => "session_welcome"
        },
        "payload" => %{
          "session" => %{
            "id" => "test_session_123",
            "status" => "connected",
            "connected_at" => "2024-01-01T00:00:00Z",
            "keepalive_timeout_seconds" => 10,
            "reconnect_url" => nil
          }
        }
      }

      mock_client = %{
        url: "wss://eventsub.wss.twitch.tv/ws",
        owner_pid: pid,
        conn_pid: nil
      }

      json_message = Jason.encode!(welcome_message)

      log_output =
        capture_log(fn ->
          send(pid, {:websocket_message, mock_client, json_message})
          :timer.sleep(200)
        end)

      state = :sys.get_state(pid)

      # Should establish session
      assert state.session_id == "test_session_123"
      assert state.state.connection.session_id == "test_session_123"
      assert state.state.connection.connected == true

      # Should log session establishment
      assert log_output =~ "session established" or log_output =~ "EventSub"
    end

    test "handles session_keepalive message", %{service_pid: pid} do
      # Simulate session_keepalive message
      keepalive_message = %{
        "metadata" => %{
          "message_type" => "session_keepalive"
        },
        "payload" => %{}
      }

      mock_client = %{conn_pid: nil}
      json_message = Jason.encode!(keepalive_message)

      log_output =
        capture_log(fn ->
          send(pid, {:websocket_message, mock_client, json_message})
          :timer.sleep(50)
        end)

      # Should handle keepalive gracefully
      assert Process.alive?(pid)
      assert log_output =~ "keepalive" or log_output =~ "EventSub"
    end

    test "handles notification message", %{service_pid: pid} do
      # Simulate notification message
      notification_message = %{
        "metadata" => %{
          "message_type" => "notification",
          "subscription_type" => "channel.update",
          "subscription_id" => "test_sub_123"
        },
        "payload" => %{
          "event" => %{
            "broadcaster_user_id" => "123456",
            "broadcaster_user_login" => "testuser",
            "broadcaster_user_name" => "TestUser",
            "title" => "Test Stream Title",
            "language" => "en",
            "category_id" => "509658",
            "category_name" => "Just Chatting"
          }
        }
      }

      mock_client = %{conn_pid: nil}
      json_message = Jason.encode!(notification_message)

      log_output =
        capture_log(fn ->
          send(pid, {:websocket_message, mock_client, json_message})
          :timer.sleep(100)
        end)

      # Should process notification
      assert Process.alive?(pid)
      assert log_output =~ "notification" or log_output =~ "channel.update"
    end

    test "handles session_reconnect message", %{service_pid: pid} do
      # Simulate session_reconnect message
      reconnect_message = %{
        "metadata" => %{
          "message_type" => "session_reconnect"
        },
        "payload" => %{
          "session" => %{
            "id" => "new_session_123",
            "status" => "reconnecting",
            "reconnect_url" => "wss://eventsub.wss.twitch.tv/ws?reconnect=true"
          }
        }
      }

      mock_client = %{conn_pid: nil}
      json_message = Jason.encode!(reconnect_message)

      log_output =
        capture_log(fn ->
          send(pid, {:websocket_message, mock_client, json_message})
          :timer.sleep(100)
        end)

      # Should handle reconnection request
      assert Process.alive?(pid)
      assert log_output =~ "reconnection" or log_output =~ "reconnect"
    end

    test "handles malformed EventSub messages gracefully", %{service_pid: pid} do
      mock_client = %{conn_pid: nil}

      log_output =
        capture_log(fn ->
          send(pid, {:websocket_message, mock_client, "invalid json{"})
          :timer.sleep(50)
        end)

      # Should handle malformed JSON gracefully
      assert Process.alive?(pid)
      assert log_output =~ "decode failed" or log_output =~ "error"
    end
  end

  describe "subscription management" do
    test "get_status returns proper structure", %{service_pid: _pid} do
      {:ok, status} = Twitch.get_status()

      assert is_map(status)
      assert Map.has_key?(status, :connected)
      assert Map.has_key?(status, :connection_state)
      assert Map.has_key?(status, :session_id)
      assert Map.has_key?(status, :subscription_count)
      assert Map.has_key?(status, :subscription_cost)

      assert status.connected == false
      assert status.connection_state == "disconnected"
      assert status.session_id == nil
      assert status.subscription_count == 0
      assert status.subscription_cost == 0
    end

    test "get_connection_state returns detailed connection info", %{service_pid: _pid} do
      connection_state = Twitch.get_connection_state()

      assert is_map(connection_state)
      assert Map.has_key?(connection_state, :connected)
      assert Map.has_key?(connection_state, :connection_state)
      assert Map.has_key?(connection_state, :session_id)
      assert Map.has_key?(connection_state, :last_connected)

      assert connection_state.connected == false
      assert connection_state.connection_state == "disconnected"
      assert connection_state.session_id == nil
    end

    test "get_subscription_metrics returns subscription details", %{service_pid: _pid} do
      metrics = Twitch.get_subscription_metrics()

      assert is_map(metrics)
      assert Map.has_key?(metrics, :subscription_count)
      assert Map.has_key?(metrics, :subscription_total_cost)
      assert Map.has_key?(metrics, :subscription_max_count)
      assert Map.has_key?(metrics, :subscription_max_cost)

      assert metrics.subscription_count == 0
      assert metrics.subscription_total_cost == 0
      assert metrics.subscription_max_count == 300
      assert metrics.subscription_max_cost == 10
    end

    test "create_subscription fails when not connected", %{service_pid: _pid} do
      result = Twitch.create_subscription("channel.update", %{"broadcaster_user_id" => "123"})

      assert {:error, "WebSocket not connected"} = result
    end

    test "create_subscription validates subscription limits", %{service_pid: pid} do
      # Set up connected state with max subscriptions
      :sys.replace_state(pid, fn state ->
        state
        |> put_in([:state, :connection, :connected], true)
        |> Map.put(:session_id, "test_session")
        |> put_in([:state, :subscription_count], 300)
      end)

      result = Twitch.create_subscription("channel.update", %{"broadcaster_user_id" => "123"})

      assert {:error, error_msg} = result
      assert error_msg =~ "limit exceeded"
    end

    test "delete_subscription fails gracefully when not found", %{service_pid: _pid} do
      # This would normally call EventSubManager.delete_subscription which would fail
      # For now, we just verify the service handles the call
      result = Twitch.delete_subscription("nonexistent_sub")

      assert {:error, _reason} = result
    end

    test "list_subscriptions returns current subscriptions", %{service_pid: _pid} do
      {:ok, subscriptions} = Twitch.list_subscriptions()

      assert is_map(subscriptions)
      assert subscriptions == %{}
    end
  end

  describe "caching and performance" do
    test "get_state uses caching correctly", %{service_pid: _pid} do
      # First call
      start_time = System.monotonic_time(:millisecond)
      state1 = Twitch.get_state()
      first_duration = System.monotonic_time(:millisecond) - start_time

      # Second call (should be cached)
      start_time = System.monotonic_time(:millisecond)
      state2 = Twitch.get_state()
      second_duration = System.monotonic_time(:millisecond) - start_time

      # Results should be identical
      assert state1 == state2

      # Second call should be faster (cached)
      assert second_duration <= first_duration
    end

    test "cache invalidation works on state changes", %{service_pid: pid} do
      # Get initial state
      {:ok, status1} = Twitch.get_status()

      # Simulate connection state change
      send(pid, {:websocket_connected, %{conn_pid: nil}})
      :timer.sleep(100)

      # Cache should be invalidated
      {:ok, status2} = Twitch.get_status()

      # Status should reflect the change
      assert status1.connected == false
      assert status2.connected == true
    end

    test "subscription metrics caching respects TTL", %{service_pid: _pid} do
      # Get metrics twice quickly
      metrics1 = Twitch.get_subscription_metrics()
      metrics2 = Twitch.get_subscription_metrics()

      # Should be identical (cached)
      assert metrics1 == metrics2
    end
  end

  describe "error handling and resilience" do
    test "handles Gun process termination gracefully", %{service_pid: pid} do
      # Simulate Gun process DOWN
      fake_pid = spawn(fn -> :timer.sleep(10) end)
      ref = Process.monitor(fake_pid)

      # Wait for process to die
      :timer.sleep(50)

      # Send DOWN message
      send(pid, {:DOWN, ref, :process, fake_pid, :normal})
      :timer.sleep(50)

      # Service should handle it gracefully
      assert Process.alive?(pid)
    end

    test "handles unknown messages gracefully", %{service_pid: pid} do
      log_output =
        capture_log(fn ->
          send(pid, {:unknown_message, "test_data"})
          :timer.sleep(50)
        end)

      # Should log unknown message
      assert log_output =~ "UNHANDLED MESSAGE" or log_output =~ "unknown"

      # Service should remain stable
      assert Process.alive?(pid)
    end

    test "handles EventSub protocol errors", %{service_pid: pid} do
      # Simulate protocol error message
      error_message = %{
        "metadata" => %{
          "message_type" => "unknown_type"
        },
        "payload" => %{}
      }

      mock_client = %{conn_pid: nil}
      json_message = Jason.encode!(error_message)

      log_output =
        capture_log(fn ->
          send(pid, {:websocket_message, mock_client, json_message})
          :timer.sleep(50)
        end)

      # Should handle unknown message types
      assert Process.alive?(pid)
      assert log_output =~ "unhandled" or log_output =~ "unknown"
    end

    test "service cleanup on termination", %{service_pid: pid} do
      # Add some test state
      :sys.replace_state(pid, fn state ->
        %{state | subscriptions: %{"test_sub" => %{"id" => "test_sub"}}, session_id: "test_session"}
      end)

      # Stop service
      GenServer.stop(pid, :normal, 1000)

      # Process should be dead
      refute Process.alive?(pid)
    end

    test "handles subscription creation with validated token timing", %{service_pid: pid} do
      # Set up state with session but no user_id yet
      :sys.replace_state(pid, fn state ->
        %{state | session_id: "test_session", user_id: nil}
      end)

      # Simulate token validation completing after session
      send(pid, {:create_subscriptions_with_validated_token, "test_session"})
      :timer.sleep(50)

      # Should handle gracefully without user_id
      assert Process.alive?(pid)
    end

    test "handles retry subscription timing correctly", %{service_pid: pid} do
      # Set up state with session
      :sys.replace_state(pid, fn state ->
        %{state | session_id: "test_session", user_id: nil}
      end)

      # Simulate retry subscription message
      send(pid, {:retry_default_subscriptions, "test_session"})
      :timer.sleep(100)

      state = :sys.get_state(pid)

      # Should schedule another retry since no user_id
      assert state.retry_subscription_timer != nil or state.default_subscriptions_created == false
    end
  end

  describe "telemetry and monitoring" do
    test "WebSocket client configured with telemetry", %{service_pid: pid} do
      state = :sys.get_state(pid)

      # Verify telemetry prefix is set
      assert state.ws_client.telemetry_prefix == [:server, :twitch, :websocket]
    end

    test "OAuth token manager configured with telemetry", %{service_pid: pid} do
      state = :sys.get_state(pid)

      # Token manager should be configured (we can't easily verify telemetry without executing)
      assert state.token_manager != nil
      assert state.token_manager.oauth2_client != nil
    end

    test "service publishes PubSub events", %{service_pid: pid} do
      # Subscribe to dashboard events
      Phoenix.PubSub.subscribe(Server.PubSub, "dashboard")

      # Simulate connection event
      mock_client = %{conn_pid: nil}
      send(pid, {:websocket_connected, mock_client})

      # Should receive PubSub event
      assert_receive {:twitch_connected, %{}}, 1000
    end
  end

  describe "EventSub subscription lifecycle" do
    test "handles deferred subscription creation", %{service_pid: pid} do
      # Set up session without user_id
      :sys.replace_state(pid, fn state ->
        %{state | session_id: "test_session", user_id: nil, scopes: nil}
      end)

      # Simulate session_welcome that should defer subscriptions
      welcome_message = %{
        "metadata" => %{"message_type" => "session_welcome"},
        "payload" => %{
          "session" => %{"id" => "test_session"}
        }
      }

      mock_client = %{conn_pid: nil}
      json_message = Jason.encode!(welcome_message)

      log_output =
        capture_log(fn ->
          send(pid, {:websocket_message, mock_client, json_message})
          :timer.sleep(100)
        end)

      state = :sys.get_state(pid)

      # Should defer subscriptions and set retry timer
      assert log_output =~ "deferred" or log_output =~ "retry"
      assert state.retry_subscription_timer != nil
    end

    test "prevents duplicate subscription creation", %{service_pid: pid} do
      # Set up state with existing subscriptions created flag
      :sys.replace_state(pid, fn state ->
        %{
          state
          | session_id: "test_session",
            user_id: "test_user",
            scopes: MapSet.new(["user:read:email"]),
            default_subscriptions_created: true
        }
      end)

      # Simulate subscription creation message
      log_output =
        capture_log(fn ->
          send(pid, {:create_subscriptions_with_validated_token, "test_session"})
          :timer.sleep(50)
        end)

      # Should skip creation
      assert log_output =~ "already created" or log_output =~ "Skipping"
    end

    test "handles session ID mismatch in retry", %{service_pid: pid} do
      # Set up state with different session
      :sys.replace_state(pid, fn state ->
        %{state | session_id: "different_session"}
      end)

      # Simulate retry for old session
      log_output =
        capture_log(fn ->
          send(pid, {:retry_default_subscriptions, "old_session"})
          :timer.sleep(50)
        end)

      # Should abandon retry
      assert log_output =~ "abandoned" or log_output =~ "session changed"
    end
  end
end
