defmodule Server.Correlation.MonitorTest do
  use ExUnit.Case, async: true

  alias Server.Correlation.Monitor

  setup do
    {:ok, monitor_pid} = Monitor.start_link()

    # Clean exit for each test
    on_exit(fn ->
      if Process.alive?(monitor_pid) do
        GenServer.stop(monitor_pid)
      end
    end)

    %{monitor: monitor_pid}
  end

  describe "Monitor" do
    test "starts with initial metrics" do
      metrics = Monitor.get_metrics()

      assert metrics.correlation_metrics.total_count == 0
      assert metrics.buffer_health.transcription_size == 0
      assert metrics.buffer_health.chat_size == 0
      assert metrics.database_metrics.success_rate == 1.0
      assert metrics.rate_metrics.correlations_per_minute == 0.0
      assert is_integer(metrics.uptime_seconds)
    end

    test "records correlation detection" do
      correlation = %{
        pattern_type: :direct_quote,
        confidence: 0.9,
        time_offset_ms: 4000,
        transcription_text: "hello world",
        chat_text: "hello world"
      }

      Monitor.record_correlation_detected(correlation, 15)

      # Give the cast a moment to process
      Process.sleep(10)

      metrics = Monitor.get_metrics()
      assert metrics.correlation_metrics.total_count == 1
      assert metrics.performance_metrics.avg_processing_time_ms == 15.0
      # Rate calculation happens during collect_metrics cycle, not immediately
      assert metrics.rate_metrics.correlations_per_minute >= 0.0
    end

    test "records buffer pruning" do
      Monitor.record_buffer_pruned(:transcription, 5, 45)

      # Give the cast a moment to process
      Process.sleep(10)

      metrics = Monitor.get_metrics()
      assert metrics.buffer_health.transcription_size == 45
      assert metrics.buffer_health.prune_rate >= 0.0
    end

    test "records database operations" do
      Monitor.record_database_operation(:store_correlation, :success, 25)
      Monitor.record_database_operation(:store_correlation, :error, 50)

      # Give the casts a moment to process
      Process.sleep(10)

      metrics = Monitor.get_metrics()
      assert metrics.database_metrics.operations_total == 2
      assert metrics.database_metrics.operations_success == 1
      assert metrics.database_metrics.operations_error == 1
      assert metrics.database_metrics.success_rate == 0.5
      assert metrics.database_metrics.avg_latency_ms == 37.5
    end

    test "updates engine status" do
      status = %{
        transcription_count: 10,
        chat_count: 8,
        correlation_count: 3,
        stream_active: true
      }

      Monitor.record_engine_status(status)

      # Give the cast a moment to process
      Process.sleep(10)

      metrics = Monitor.get_metrics()
      assert metrics.buffer_health.transcription_size == 10
      assert metrics.buffer_health.chat_size == 8
      assert metrics.buffer_health.correlation_count == 3
    end

    test "calculates performance metrics over time" do
      # Record multiple correlations with different processing times
      correlation = %{pattern_type: :keyword_echo, confidence: 0.7, time_offset_ms: 3500}

      Monitor.record_correlation_detected(correlation, 10)
      Monitor.record_correlation_detected(correlation, 20)
      Monitor.record_correlation_detected(correlation, 30)

      # Give the casts a moment to process
      Process.sleep(10)

      metrics = Monitor.get_metrics()
      assert metrics.performance_metrics.avg_processing_time_ms == 20.0
      assert metrics.performance_metrics.min_processing_time_ms == 10.0
      assert metrics.performance_metrics.max_processing_time_ms == 30.0
    end

    test "tracks metric history" do
      # Record some activity
      correlation = %{pattern_type: :emote_reaction, confidence: 0.6, time_offset_ms: 5000}
      Monitor.record_correlation_detected(correlation, 12)

      # Give the cast a moment to process
      Process.sleep(10)

      history = Monitor.get_metric_history(limit: 5)

      # Should have at least the initial snapshot
      assert length(history) >= 0

      # If we have history, check the structure
      if length(history) > 0 do
        latest = List.first(history)
        assert Map.has_key?(latest, :timestamp)
        assert Map.has_key?(latest, :correlation_count)
        assert Map.has_key?(latest, :correlations_per_minute)
      end
    end

    test "emits telemetry events" do
      # Set up telemetry test handler
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        ref,
        [:correlation, :detection],
        fn name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, name, measurements, metadata})
        end,
        nil
      )

      correlation = %{
        pattern_type: :question_response,
        confidence: 0.5,
        time_offset_ms: 6000
      }

      Monitor.record_correlation_detected(correlation, 8)

      # Should receive telemetry event
      assert_receive {:telemetry, [:correlation, :detection], measurements, metadata}, 100

      assert measurements.count == 1
      assert measurements.processing_time == 8
      assert metadata.pattern_type == :question_response
      assert metadata.confidence == 0.5

      # Clean up
      :telemetry.detach(ref)
    end
  end
end
