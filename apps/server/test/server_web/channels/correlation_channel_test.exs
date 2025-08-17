defmodule ServerWeb.CorrelationChannelTest do
  use ServerWeb.ChannelCase

  alias ServerWeb.CorrelationChannel
  alias ServerWeb.UserSocket

  setup do
    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{correlation_id: "test-123"})
      |> subscribe_and_join(CorrelationChannel, "correlation:monitoring")

    %{socket: socket}
  end

  describe "CorrelationChannel" do
    test "joins successfully", %{socket: socket} do
      assert socket.assigns.room_id == "monitoring"
    end

    test "responds to get_metrics command", %{socket: socket} do
      ref = push(socket, "get_metrics", %{})

      assert_reply ref, :ok, %{data: metrics}

      # Basic metric structure validation
      assert Map.has_key?(metrics, :correlation_metrics)
      assert Map.has_key?(metrics, :buffer_health)
      assert Map.has_key?(metrics, :database_metrics)
      assert Map.has_key?(metrics, :performance_metrics)
      assert Map.has_key?(metrics, :rate_metrics)
      assert Map.has_key?(metrics, :pattern_distribution)
      assert Map.has_key?(metrics, :uptime_seconds)
    end

    test "responds to get_correlations command", %{socket: socket} do
      ref = push(socket, "get_correlations", %{})

      assert_reply ref, :ok, %{data: response}
      assert Map.has_key?(response, :correlations)
      assert is_list(response.correlations)
    end

    test "responds to get_correlations with limit", %{socket: socket} do
      ref = push(socket, "get_correlations", %{"limit" => 5})

      assert_reply ref, :ok, %{data: response}
      assert Map.has_key?(response, :correlations)
      assert is_list(response.correlations)
    end

    test "responds to get_engine_status command", %{socket: socket} do
      ref = push(socket, "get_engine_status", %{})

      assert_reply ref, :ok, %{data: status}

      # Basic status structure validation
      assert Map.has_key?(status, :transcription_count)
      assert Map.has_key?(status, :chat_count)
      assert Map.has_key?(status, :correlation_count)
      assert Map.has_key?(status, :stream_active)
    end

    test "responds to get_pattern_distribution command", %{socket: socket} do
      ref = push(socket, "get_pattern_distribution", %{})

      assert_reply ref, :ok, %{data: response}
      assert Map.has_key?(response, :patterns)
    end

    test "responds to get_metric_history command", %{socket: socket} do
      ref = push(socket, "get_metric_history", %{})

      assert_reply ref, :ok, %{data: response}
      assert Map.has_key?(response, :history)
      assert is_list(response.history)
    end

    test "responds to get_metric_history with limit", %{socket: socket} do
      ref = push(socket, "get_metric_history", %{"limit" => 10})

      assert_reply ref, :ok, %{data: response}
      assert Map.has_key?(response, :history)
      assert is_list(response.history)
    end

    test "returns error for unknown command", %{socket: socket} do
      ref = push(socket, "unknown_command", %{})

      # The error response is structured with more detail
      assert_reply ref, :error, %{error: %{code: "unknown_command"}}
    end

    test "broadcasts new correlations", %{socket: _socket} do
      correlation_data = %{
        id: "test-123",
        pattern: :direct_quote,
        confidence: 0.9,
        transcription: "hello world",
        chat_user: "test_user",
        chat_message: "hello world",
        time_offset_ms: 4000
      }

      # Simulate a new correlation broadcast
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "correlation:insights",
        {:new_correlation, correlation_data}
      )

      # Should receive the correlation as a push
      assert_push "new_correlation", ^correlation_data
    end

    test "broadcasts correlation metrics updates", %{socket: _socket} do
      # Wait for initial metrics push to complete
      assert_push "correlation_metrics", %{data: _initial_data}

      # Structure the metrics update to match the monitor's actual format
      metrics_update = %{
        timestamp: System.system_time(:millisecond),
        correlation_metrics: %{total_count: 5, patterns: %{direct_quote: 2, keyword_echo: 3}},
        buffer_health: %{
          correlation_count: 5,
          transcription_size: 20,
          chat_size: 15,
          prune_rate: 2.5
        },
        database_metrics: %{
          success_rate: 0.95,
          circuit_breaker_status: :closed
        },
        performance_metrics: %{
          avg_processing_time_ms: 12.5
        },
        rate_metrics: %{
          correlations_per_minute: 2.3
        }
      }

      # Simulate a metrics update broadcast
      Phoenix.PubSub.broadcast(
        Server.PubSub,
        "dashboard:telemetry",
        {:correlation_metrics, metrics_update}
      )

      # Should receive formatted metrics update
      assert_push "correlation_metrics", %{data: data, timestamp: _timestamp}

      # The data structure is transformed by the channel handler
      assert data.correlation_count == 5
      assert data.correlations_per_minute == 2.3
      assert is_float(data.buffer_health_score)
      assert data.database_success_rate == 0.95
      assert data.avg_processing_time == 12.5
      assert data.circuit_breaker_status == :closed
    end
  end
end
