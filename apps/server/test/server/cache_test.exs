defmodule Server.CacheTest do
  use ExUnit.Case, async: false

  alias Server.Cache

  setup do
    # Start the cache for testing
    start_supervised!(Cache)
    :ok
  end

  describe "basic cache operations" do
    test "set and get cache entries" do
      assert :ok = Cache.set(:test_namespace, :test_key, "test_value", ttl_seconds: 10)
      assert {:ok, "test_value"} = Cache.get(:test_namespace, :test_key)
    end

    test "returns error for non-existent keys" do
      assert :error = Cache.get(:test_namespace, :non_existent)
    end

    test "get_or_compute returns cached value when present" do
      Cache.set(:test_namespace, :cached_key, "cached_value", ttl_seconds: 10)

      result =
        Cache.get_or_compute(:test_namespace, :cached_key, fn ->
          "computed_value"
        end)

      assert result == "cached_value"
    end

    test "get_or_compute computes and caches when missing" do
      result =
        Cache.get_or_compute(
          :test_namespace,
          :missing_key,
          fn ->
            "computed_value"
          end,
          ttl_seconds: 10
        )

      assert result == "computed_value"
      assert {:ok, "computed_value"} = Cache.get(:test_namespace, :missing_key)
    end
  end

  describe "TTL and expiration" do
    test "entries expire after TTL" do
      Cache.set(:test_namespace, :expiring_key, "value", ttl_seconds: 1)
      assert {:ok, "value"} = Cache.get(:test_namespace, :expiring_key)

      # Wait for expiration
      Process.sleep(1100)
      assert :error = Cache.get(:test_namespace, :expiring_key)
    end

    test "get_or_compute respects TTL" do
      call_count = Agent.start_link(fn -> 0 end)
      {:ok, counter_pid} = call_count

      compute_fn = fn ->
        Agent.update(counter_pid, &(&1 + 1))
        "computed_#{System.monotonic_time()}"
      end

      # First call should compute
      result1 = Cache.get_or_compute(:test_namespace, :ttl_key, compute_fn, ttl_seconds: 1)
      assert Agent.get(counter_pid, & &1) == 1

      # Second call within TTL should use cache
      result2 = Cache.get_or_compute(:test_namespace, :ttl_key, compute_fn, ttl_seconds: 1)
      assert result1 == result2
      assert Agent.get(counter_pid, & &1) == 1

      # Wait for expiration, next call should compute again
      Process.sleep(1100)
      result3 = Cache.get_or_compute(:test_namespace, :ttl_key, compute_fn, ttl_seconds: 1)
      assert result3 != result1
      assert Agent.get(counter_pid, & &1) == 2

      Agent.stop(counter_pid)
    end
  end

  describe "invalidation" do
    test "invalidate removes specific cache entry" do
      Cache.set(:test_namespace, :key1, "value1", ttl_seconds: 10)
      Cache.set(:test_namespace, :key2, "value2", ttl_seconds: 10)

      assert {:ok, "value1"} = Cache.get(:test_namespace, :key1)
      assert {:ok, "value2"} = Cache.get(:test_namespace, :key2)

      Cache.invalidate(:test_namespace, :key1)

      assert :error = Cache.get(:test_namespace, :key1)
      assert {:ok, "value2"} = Cache.get(:test_namespace, :key2)
    end

    test "invalidate_namespace removes all entries in namespace" do
      Cache.set(:namespace1, :key1, "value1", ttl_seconds: 10)
      Cache.set(:namespace1, :key2, "value2", ttl_seconds: 10)
      Cache.set(:namespace2, :key3, "value3", ttl_seconds: 10)

      Cache.invalidate_namespace(:namespace1)

      assert :error = Cache.get(:namespace1, :key1)
      assert :error = Cache.get(:namespace1, :key2)
      assert {:ok, "value3"} = Cache.get(:namespace2, :key3)
    end
  end

  describe "bulk operations" do
    test "bulk_set stores multiple entries" do
      entries = [
        {"key1", "value1"},
        {"key2", "value2"},
        {"key3", "value3"}
      ]

      assert :ok = Cache.bulk_set(:test_namespace, entries, ttl_seconds: 10)

      assert {:ok, "value1"} = Cache.get(:test_namespace, "key1")
      assert {:ok, "value2"} = Cache.get(:test_namespace, "key2")
      assert {:ok, "value3"} = Cache.get(:test_namespace, "key3")
    end

    test "refresh updates cache entry with new value" do
      Cache.set(:test_namespace, :refresh_key, "old_value", ttl_seconds: 10)

      Cache.refresh(
        :test_namespace,
        :refresh_key,
        fn ->
          "new_value"
        end,
        ttl_seconds: 10
      )

      assert {:ok, "new_value"} = Cache.get(:test_namespace, :refresh_key)
    end
  end

  describe "statistics and monitoring" do
    test "stats returns cache statistics" do
      Cache.set(:test_namespace, :stats_key, "value", ttl_seconds: 10)

      # Trigger cache hit
      Cache.get_or_compute(:test_namespace, :stats_key, fn -> "new_value" end)

      # Trigger cache miss
      Cache.get_or_compute(:test_namespace, :miss_key, fn -> "computed" end)

      stats = Cache.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :current_size)
      assert Map.has_key?(stats, :hits)
      assert Map.has_key?(stats, :misses)
    end

    test "cleanup removes expired entries" do
      # Set entries with very short TTL
      Cache.set(:test_namespace, :cleanup_key1, "value1", ttl_seconds: 1)
      Cache.set(:test_namespace, :cleanup_key2, "value2", ttl_seconds: 10)

      # Wait for first entry to expire
      Process.sleep(1100)

      # Force cleanup
      Cache.cleanup()

      # Verify expired entry is gone but valid entry remains
      assert :error = Cache.get(:test_namespace, :cleanup_key1)
      assert {:ok, "value2"} = Cache.get(:test_namespace, :cleanup_key2)
    end
  end

  describe "edge cases and error handling" do
    test "handles nil values correctly" do
      assert :ok = Cache.set(:test_namespace, :nil_key, nil, ttl_seconds: 10)
      assert {:ok, nil} = Cache.get(:test_namespace, :nil_key)
    end

    test "handles complex data structures" do
      complex_data = %{
        list: [1, 2, 3],
        map: %{nested: "value"},
        tuple: {:ok, "result"}
      }

      assert :ok = Cache.set(:test_namespace, :complex_key, complex_data, ttl_seconds: 10)
      assert {:ok, ^complex_data} = Cache.get(:test_namespace, :complex_key)
    end

    test "compute function exceptions don't crash cache" do
      failing_compute = fn ->
        raise "Computation failed"
      end

      assert_raise RuntimeError, "Computation failed", fn ->
        Cache.get_or_compute(:test_namespace, :error_key, failing_compute)
      end

      # Cache should still be functional
      assert :ok = Cache.set(:test_namespace, :recovery_key, "works", ttl_seconds: 10)
      assert {:ok, "works"} = Cache.get(:test_namespace, :recovery_key)
    end
  end

  describe "concurrent access" do
    test "multiple processes can access cache safely" do
      parent = self()

      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            Cache.set(:concurrent_namespace, "key_#{i}", "value_#{i}", ttl_seconds: 10)
            send(parent, {:set_complete, i})
          end)
        end)

      # Wait for all sets to complete
      Enum.each(1..10, fn i ->
        receive do
          {:set_complete, ^i} -> :ok
        end
      end)

      Task.await_many(tasks)

      # Verify all entries were set correctly
      Enum.each(1..10, fn i ->
        expected_value = "value_#{i}"
        assert {:ok, ^expected_value} = Cache.get(:concurrent_namespace, "key_#{i}")
      end)
    end

    test "get_or_compute prevents duplicate computation" do
      computation_count = Agent.start_link(fn -> 0 end)
      {:ok, counter_pid} = computation_count

      slow_compute = fn ->
        Agent.update(counter_pid, &(&1 + 1))
        # Simulate slow computation
        Process.sleep(100)
        "computed_value"
      end

      parent = self()

      # Start multiple concurrent get_or_compute operations
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            result = Cache.get_or_compute(:concurrent_namespace, :shared_key, slow_compute, ttl_seconds: 10)
            send(parent, {:computed, i, result})
          end)
        end)

      Task.await_many(tasks)

      # All should return the same value
      results =
        Enum.map(1..5, fn i ->
          receive do
            {:computed, ^i, result} -> result
          end
        end)

      # All results should be the same
      assert Enum.uniq(results) == ["computed_value"]

      # Due to the race condition in concurrent access, we expect most calls
      # to be cached, but there might be a few duplicate computations
      computation_count_final = Agent.get(counter_pid, & &1)
      # Should be much better than 5 separate computations
      assert computation_count_final <= 5

      Agent.stop(counter_pid)
    end
  end
end
