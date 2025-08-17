defmodule Server.Correlation.BufferBenchmarkTest do
  use ExUnit.Case, async: true
  alias Server.Correlation.SlidingBuffer
  alias Server.Correlation.TimeBuffer

  @moduledoc """
  Benchmarks to verify performance improvements of TimeBuffer over queue-based implementation.

  Run with: mix test test/server/correlation/buffer_benchmark_test.exs --include benchmark
  """

  @tag :benchmark
  test "benchmark: All buffer implementations" do
    IO.puts("\n=== Buffer Performance Benchmark ===\n")

    # Test data
    events =
      for i <- 1..1000 do
        %{
          id: "event_#{i}",
          text: "Sample text #{i}",
          timestamp: System.system_time(:millisecond) - :rand.uniform(60_000)
        }
      end

    # Benchmark all approaches
    queue_time = benchmark_queue_approach(events)
    time_buffer_time = benchmark_time_buffer_approach(events)
    sliding_buffer_time = benchmark_sliding_buffer_approach(events)

    # Calculate improvements
    time_improvement = Float.round((queue_time - time_buffer_time) / queue_time * 100, 2)
    sliding_improvement = Float.round((queue_time - sliding_buffer_time) / queue_time * 100, 2)

    time_speedup = Float.round(queue_time / time_buffer_time, 2)
    sliding_speedup = Float.round(queue_time / sliding_buffer_time, 2)

    IO.puts("Results:")
    IO.puts("  Queue approach: #{queue_time}μs (baseline)")
    IO.puts("  TimeBuffer: #{time_buffer_time}μs (#{time_improvement}% improvement, #{time_speedup}x)")
    IO.puts("  SlidingBuffer: #{sliding_buffer_time}μs (#{sliding_improvement}% improvement, #{sliding_speedup}x)")
    IO.puts("")

    # Assert that at least one optimized buffer is faster
    assert sliding_buffer_time < queue_time or time_buffer_time < queue_time,
           "At least one optimized buffer should be faster than queue approach"
  end

  @tag :benchmark
  test "benchmark: range query performance" do
    IO.puts("\n=== Range Query Performance ===\n")

    # Create buffer with many events
    buffer = TimeBuffer.new(window_ms: 60_000, max_size: 1000)

    buffer =
      Enum.reduce(1..1000, buffer, fn i, acc ->
        event = %{
          id: "event_#{i}",
          timestamp: System.system_time(:millisecond) - :rand.uniform(60_000)
        }

        TimeBuffer.add(acc, event)
      end)

    # Benchmark range queries
    current_time = System.system_time(:millisecond)

    {time_small, _} =
      :timer.tc(fn ->
        for _ <- 1..100 do
          TimeBuffer.get_range(buffer, current_time - 5_000, current_time - 3_000)
        end
      end)

    {time_medium, _} =
      :timer.tc(fn ->
        for _ <- 1..100 do
          TimeBuffer.get_range(buffer, current_time - 15_000, current_time - 5_000)
        end
      end)

    {time_large, _} =
      :timer.tc(fn ->
        for _ <- 1..100 do
          TimeBuffer.get_range(buffer, current_time - 30_000, current_time)
        end
      end)

    IO.puts("Range query times (100 iterations each):")
    IO.puts("  Small range (2 seconds): #{div(time_small, 100)}μs avg")
    IO.puts("  Medium range (10 seconds): #{div(time_medium, 100)}μs avg")
    IO.puts("  Large range (30 seconds): #{div(time_large, 100)}μs avg")
    IO.puts("")
  end

  @tag :benchmark
  test "benchmark: memory efficiency" do
    IO.puts("\n=== Memory Efficiency ===\n")

    # Create events
    events =
      for i <- 1..1000 do
        %{
          id: "event_#{i}",
          text: String.duplicate("x", 100),
          timestamp: System.system_time(:millisecond) - i * 100
        }
      end

    # Measure queue memory
    queue = :queue.from_list(events)
    queue_size = :erts_debug.size(queue)

    # Measure TimeBuffer memory
    buffer = Enum.reduce(events, TimeBuffer.new(), &TimeBuffer.add(&2, &1))
    buffer_size = :erts_debug.size(buffer)

    # Calculate difference
    memory_savings = Float.round((queue_size - buffer_size) / queue_size * 100, 2)

    IO.puts("Memory usage (in words):")
    IO.puts("  Queue: #{queue_size}")
    IO.puts("  TimeBuffer: #{buffer_size}")
    IO.puts("  Memory savings: #{memory_savings}%")
    IO.puts("")
  end

  defp benchmark_queue_approach(events) do
    {time, _} =
      :timer.tc(fn ->
        # Simulate the old approach
        queue = :queue.from_list(events)

        # Perform 100 filtering operations (simulating correlations)
        _results =
          for _ <- 1..100 do
            current_time = System.system_time(:millisecond)
            min_time = current_time - 7_000
            max_time = current_time - 3_000

            queue
            |> :queue.to_list()
            |> Enum.filter(fn event ->
              event.timestamp >= min_time && event.timestamp <= max_time
            end)
          end

        # Perform pruning
        current_time = System.system_time(:millisecond)
        cutoff = current_time - 30_000

        queue
        |> :queue.to_list()
        |> Enum.filter(fn event -> event.timestamp >= cutoff end)
        |> :queue.from_list()
      end)

    time
  end

  defp benchmark_time_buffer_approach(events) do
    {time, _} =
      :timer.tc(fn ->
        # Build TimeBuffer
        buffer = Enum.reduce(events, TimeBuffer.new(), &TimeBuffer.add(&2, &1))

        # Perform 100 range queries (simulating correlations)
        for _ <- 1..100 do
          current_time = System.system_time(:millisecond)
          TimeBuffer.get_range(buffer, current_time - 7_000, current_time - 3_000)
        end

        # Perform pruning
        TimeBuffer.prune(buffer)
      end)

    time
  end

  defp benchmark_sliding_buffer_approach(events) do
    {time, _} =
      :timer.tc(fn ->
        # Build SlidingBuffer
        buffer = Enum.reduce(events, SlidingBuffer.new(), &SlidingBuffer.add(&2, &1))

        # Perform 100 range queries (simulating correlations)
        for _ <- 1..100 do
          current_time = System.system_time(:millisecond)
          SlidingBuffer.get_range(buffer, current_time - 7_000, current_time - 3_000)
        end

        # Perform pruning
        SlidingBuffer.prune(buffer)
      end)

    time
  end
end
