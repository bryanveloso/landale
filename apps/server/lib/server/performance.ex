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
        "Cache hit (ETS)" => fn ->
          benchmark_cache_hit()
        end,
        "Cache miss with computation" => fn ->
          benchmark_cache_miss()
        end,
        "Cache invalidation" => fn ->
          benchmark_cache_invalidation()
        end,
        "Bulk cache operations" => fn ->
          benchmark_bulk_cache_operations()
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
  Runs comprehensive cache performance benchmarks.

  Compares cached vs uncached operations to demonstrate performance gains.
  """
  def run_cache_benchmarks do
    Logger.info("Starting cache performance benchmarks")

    # Setup test data
    setup_cache_benchmarks()

    Benchee.run(
      %{
        "OBS status (cached)" => fn ->
          benchmark_obs_status_cached()
        end,
        "OBS status (uncached)" => fn ->
          benchmark_obs_status_uncached()
        end,
        "Twitch subscription data (cached)" => fn ->
          benchmark_twitch_data_cached()
        end,
        "Twitch subscription data (uncached)" => fn ->
          benchmark_twitch_data_uncached()
        end,
        "Pure ETS read" => fn ->
          benchmark_pure_ets_read()
        end,
        "Cache with TTL check" => fn ->
          benchmark_cache_with_ttl()
        end,
        "Concurrent cache access" => fn ->
          benchmark_concurrent_cache_access()
        end
      },
      time: 10,
      memory_time: 2,
      warmup: 2,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.HTML, file: "priv/benchmarks/cache_results.html"}
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
      for i <- 1..concurrent_connections//1 do
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
    _processed = JSON.encode!(message)
    :ok
  end

  defp benchmark_event_publishing do
    # Simulate publishing an event through the canonical EventHandler
    # Create properly structured test event data
    raw_event_data = %{
      "scene_name" => "Main Scene",
      "service" => "obs"
    }

    # Use EventHandler for canonical format (consistent with other benchmarks)
    normalized_event = %{
      type: "obs.scene_switched",
      timestamp: DateTime.utc_now(),
      correlation_id: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower),
      source: :obs,
      scene_name: raw_event_data["scene_name"],
      service: raw_event_data["service"]
    }

    # Publish using Phoenix PubSub directly (canonical pattern)
    Phoenix.PubSub.broadcast(Server.PubSub, "obs:events", {:obs_event, normalized_event})
  end

  defp benchmark_database_query do
    # Simple database operation benchmark
    try do
      case Server.Repo.query("SELECT 1", [], timeout: 5000) do
        {:ok, _result} -> :ok
        {:error, _reason} -> :error
      end
    rescue
      _error -> :error
    catch
      :exit, _reason -> :error
    end
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

      # Create properly structured test event data matching Twitch EventSub format
      raw_event_data = %{
        "user_name" => "test_user_#{count}",
        "user_id" => "#{count}",
        "broadcaster_user_id" => "12345",
        "broadcaster_user_name" => "avalonstar"
      }

      # Use EventHandler for canonical format (like real Twitch events)
      normalized_event = Server.Services.Twitch.EventHandler.normalize_event(event_type, raw_event_data)
      Server.Services.Twitch.EventHandler.publish_event(event_type, normalized_event)

      # Events arrive irregularly, simulate with random intervals
      Process.sleep(Enum.random(1_000..10_000//1))
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
      try do
        case Server.Repo.query("SELECT COUNT(*) FROM ironmon_challenges", [], timeout: 5000) do
          {:ok, _result} -> :ok
          {:error, _reason} -> :ok
        end
      rescue
        _error -> :ok
      catch
        :exit, _reason -> :ok
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
    Process.sleep(Enum.random(100..500//1))

    # Simulate periodic status requests
    for _i <- 1..10//1 do
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

  # Cache Benchmark Implementations

  defp setup_cache_benchmarks do
    # Ensure cache is running
    case Process.whereis(Server.Cache) do
      nil ->
        {:ok, _pid} = Server.Cache.start_link([])
        :ok

      _pid ->
        :ok
    end

    # Pre-populate cache with test data
    Server.Cache.set(:obs_service, :benchmark_status, sample_obs_status(), ttl_seconds: 300)
    Server.Cache.set(:twitch_service, :benchmark_subscriptions, sample_twitch_subscriptions(), ttl_seconds: 300)
    Server.Cache.set(:benchmark_namespace, :pure_ets_test, "benchmark_value", ttl_seconds: 300)
  end

  defp benchmark_cache_hit do
    Server.Cache.get(:obs_service, :benchmark_status)
  end

  defp benchmark_cache_miss do
    Server.Cache.get_or_compute(
      :test_namespace,
      :missing_key,
      fn ->
        # Simulate computation work
        Process.sleep(1)
        %{computed: true, timestamp: System.system_time()}
      end,
      ttl_seconds: 10
    )
  end

  defp benchmark_cache_invalidation do
    key = :random_key
    Server.Cache.set(:benchmark_namespace, key, "test_value", ttl_seconds: 60)
    Server.Cache.invalidate(:benchmark_namespace, key)
  end

  defp benchmark_bulk_cache_operations do
    entries = Enum.map(1..10//1, fn i -> {"key_#{i}", "value_#{i}"} end)
    Server.Cache.bulk_set(:bulk_benchmark, entries, ttl_seconds: 60)
  end

  defp benchmark_obs_status_cached do
    Server.Cache.get(:obs_service, :benchmark_status)
  end

  defp benchmark_obs_status_uncached do
    # Simulate the expensive OBS status call without cache
    simulate_obs_status_computation()
  end

  defp benchmark_twitch_data_cached do
    Server.Cache.get(:twitch_service, :benchmark_subscriptions)
  end

  defp benchmark_twitch_data_uncached do
    # Simulate expensive Twitch API call without cache
    simulate_twitch_computation()
  end

  defp benchmark_pure_ets_read do
    # Direct ETS access without Cache module overhead
    case :ets.lookup(:server_cache, {:benchmark_namespace, :pure_ets_test}) do
      [{_key, value, expires_at}] ->
        current_time = System.system_time(:second)
        if current_time < expires_at, do: {:ok, value}, else: :error

      [] ->
        :error
    end
  end

  defp benchmark_cache_with_ttl do
    Server.Cache.get(:benchmark_namespace, :pure_ets_test)
  end

  defp benchmark_concurrent_cache_access do
    # Spawn multiple processes to test concurrent access
    tasks =
      Enum.map(1..5//1, fn _i ->
        Task.async(fn ->
          Server.Cache.get(:obs_service, :benchmark_status)
        end)
      end)

    Task.await_many(tasks, 1000)
  end

  # Sample data generators
  defp sample_obs_status do
    %{
      connected: true,
      streaming: %{active: false, time_code: "00:00:00"},
      recording: %{active: true, time_code: "01:23:45"},
      current_scene: "Scene 1",
      stats: %{
        fps: 60.0,
        cpu_usage: 15.2,
        memory_usage: 512.0,
        available_disk_space: 50.0
      }
    }
  end

  defp sample_twitch_subscriptions do
    %{
      total_count: 12,
      max_total_cost: 100,
      data: [
        %{id: "sub-1", type: "channel.update", cost: 1},
        %{id: "sub-2", type: "stream.online", cost: 1},
        %{id: "sub-3", type: "stream.offline", cost: 1}
      ]
    }
  end

  defp simulate_obs_status_computation do
    # Simulate network latency and JSON parsing for OBS WebSocket call
    Process.sleep(2)
    sample_obs_status()
  end

  defp simulate_twitch_computation do
    # Simulate HTTP request latency and JSON parsing for Twitch API
    Process.sleep(5)
    sample_twitch_subscriptions()
  end
end
