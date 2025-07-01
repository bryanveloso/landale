defmodule Server.Performance do
  @moduledoc """
  Performance testing and benchmarking utilities for the Server application.

  Provides simple benchmarking functions for critical code paths and
  realistic load testing scenarios for a single-user streaming system.
  """

  require Logger

  @doc """
  Runs basic performance benchmarks for critical system operations.
  """
  def run_benchmarks do
    Logger.info("Starting performance benchmarks")

    Benchee.run(
      %{
        "WebSocket message handling" => fn ->
          benchmark_websocket_message()
        end,
        "Event publishing" => fn ->
          benchmark_event_publishing()
        end,
        "Database query" => fn ->
          benchmark_database_query()
        end,
        "Telemetry emission" => fn ->
          benchmark_telemetry_emission()
        end
      },
      time: 10,
      memory_time: 2,
      warmup: 2,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.HTML, file: "priv/benchmarks/results.html"}
      ]
    )
  end

  @doc """
  Simulates realistic load for a single-user streaming system.
  """
  def simulate_realistic_load(duration_seconds \\ 60) do
    Logger.info("Starting realistic load simulation for #{duration_seconds} seconds")

    # Start monitoring
    start_time = System.monotonic_time(:millisecond)
    metrics = start_metrics_collection()

    # Simulate concurrent activities
    tasks = [
      Task.async(fn -> simulate_dashboard_updates(duration_seconds) end),
      Task.async(fn -> simulate_obs_commands(duration_seconds) end),
      Task.async(fn -> simulate_twitch_events(duration_seconds) end),
      Task.async(fn -> simulate_database_operations(duration_seconds) end)
    ]

    # Wait for all tasks to complete
    Task.await_many(tasks, (duration_seconds + 10) * 1000)

    # Collect final metrics
    end_time = System.monotonic_time(:millisecond)
    final_metrics = stop_metrics_collection(metrics)

    Logger.info("Load simulation completed in #{end_time - start_time}ms")
    final_metrics
  end

  @doc """
  Tests WebSocket connection handling under load.
  """
  def test_websocket_load(concurrent_connections \\ 10) do
    Logger.info("Testing WebSocket load with #{concurrent_connections} connections")

    # This is a simplified test - in a real scenario you'd use a WebSocket client library
    tasks =
      for i <- 1..concurrent_connections do
        Task.async(fn ->
          simulate_websocket_client(i)
        end)
      end

    results = Task.await_many(tasks, 30_000)

    successful_connections = Enum.count(results, &(&1 == :ok))
    Logger.info("WebSocket load test: #{successful_connections}/#{concurrent_connections} successful")

    %{
      total_connections: concurrent_connections,
      successful_connections: successful_connections,
      success_rate: successful_connections / concurrent_connections * 100
    }
  end

  # Private benchmark functions

  defp benchmark_websocket_message do
    # Simulate processing a typical dashboard WebSocket message
    message = %{
      "type" => "obs:command",
      "data" => %{
        "action" => "switch_scene",
        "scene_name" => "Main Scene"
      }
    }

    # This would normally go through Phoenix Channel handling
    # For benchmark, we simulate the processing
    _processed = Jason.encode!(message)
    :ok
  end

  defp benchmark_event_publishing do
    # Simulate publishing an event through the Events system
    event_data = %{
      service: "obs",
      action: "scene_switched",
      data: %{scene: "Main Scene"}
    }

    Server.Events.publish_obs_event("scene_switched", event_data)
  end

  defp benchmark_database_query do
    # Simple database operation benchmark
    case Server.Repo.query("SELECT 1") do
      {:ok, _result} -> :ok
      {:error, _reason} -> :error
    end
  end

  defp benchmark_telemetry_emission do
    # Benchmark telemetry overhead
    :telemetry.execute(
      [:server, :performance, :benchmark],
      %{value: 1},
      %{operation: "test"}
    )
  end

  # Load simulation functions

  defp simulate_dashboard_updates(duration_seconds) do
    end_time = System.monotonic_time(:millisecond) + duration_seconds * 1000
    simulate_dashboard_loop(end_time, 0)
  end

  defp simulate_dashboard_loop(end_time, count) do
    if System.monotonic_time(:millisecond) < end_time do
      # Simulate dashboard requesting status updates
      case Server.Services.OBS.get_status() do
        {:ok, _status} -> :ok
        {:error, _reason} -> :ok
      end

      # Wait ~100ms between updates (simulating 10 FPS dashboard)
      Process.sleep(100)
      simulate_dashboard_loop(end_time, count + 1)
    else
      Logger.debug("Dashboard simulation: #{count} updates")
      count
    end
  end

  defp simulate_obs_commands(duration_seconds) do
    end_time = System.monotonic_time(:millisecond) + duration_seconds * 1000
    simulate_obs_loop(end_time, 0)
  end

  defp simulate_obs_loop(end_time, count) do
    if System.monotonic_time(:millisecond) < end_time do
      # Simulate occasional OBS commands (scene switching, etc.)
      # This is much less frequent than dashboard updates
      # Every 5 seconds
      Process.sleep(5000)

      # Simulate getting OBS status (lightweight operation)
      case Server.Services.OBS.get_status() do
        {:ok, _status} -> :ok
        {:error, _reason} -> :ok
      end

      simulate_obs_loop(end_time, count + 1)
    else
      Logger.debug("OBS simulation: #{count} commands")
      count
    end
  end

  defp simulate_twitch_events(duration_seconds) do
    end_time = System.monotonic_time(:millisecond) + duration_seconds * 1000
    simulate_twitch_loop(end_time, 0)
  end

  defp simulate_twitch_loop(end_time, count) do
    if System.monotonic_time(:millisecond) < end_time do
      # Simulate Twitch events arriving
      event_types = ["channel.follow", "channel.cheer", "stream.online"]
      event_type = Enum.random(event_types)

      event_data = %{
        user_name: "test_user_#{count}",
        timestamp: System.system_time(:second)
      }

      Server.Events.publish_twitch_event(event_type, event_data)

      # Events arrive irregularly, simulate with random intervals
      Process.sleep(Enum.random(1_000..10_000))
      simulate_twitch_loop(end_time, count + 1)
    else
      Logger.debug("Twitch simulation: #{count} events")
      count
    end
  end

  defp simulate_database_operations(duration_seconds) do
    end_time = System.monotonic_time(:millisecond) + duration_seconds * 1000
    simulate_db_loop(end_time, 0)
  end

  defp simulate_db_loop(end_time, count) do
    if System.monotonic_time(:millisecond) < end_time do
      # Simulate periodic database queries (health checks, etc.)
      case Server.Repo.query("SELECT COUNT(*) FROM ironmon_challenges") do
        {:ok, _result} -> :ok
        {:error, _reason} -> :ok
      end

      # Every 2 seconds
      Process.sleep(2000)
      simulate_db_loop(end_time, count + 1)
    else
      Logger.debug("Database simulation: #{count} queries")
      count
    end
  end

  defp simulate_websocket_client(client_id) do
    # Simulate a WebSocket client connection lifecycle
    # This is a simplified simulation since we can't easily create real WebSocket connections
    Logger.debug("Simulating WebSocket client #{client_id}")

    # Simulate connection time
    Process.sleep(Enum.random(100..500))

    # Simulate periodic status requests
    for _i <- 1..10 do
      # 1 second intervals
      Process.sleep(1000)
      # Simulate status request processing
      :ok
    end

    :ok
  end

  defp start_metrics_collection do
    initial_memory = :erlang.memory()
    initial_process_count = :erlang.system_info(:process_count)

    %{
      start_time: System.monotonic_time(:millisecond),
      initial_memory: initial_memory,
      initial_process_count: initial_process_count
    }
  end

  defp stop_metrics_collection(initial_metrics) do
    final_memory = :erlang.memory()
    final_process_count = :erlang.system_info(:process_count)
    end_time = System.monotonic_time(:millisecond)

    %{
      duration_ms: end_time - initial_metrics.start_time,
      memory_delta: %{
        total: final_memory[:total] - initial_metrics.initial_memory[:total],
        processes: final_memory[:processes] - initial_metrics.initial_memory[:processes]
      },
      process_count_delta: final_process_count - initial_metrics.initial_process_count
    }
  end
end
