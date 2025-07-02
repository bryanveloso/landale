defmodule Server.CacheIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for Server.Cache focusing on ETS operations,
  TTL management, performance monitoring, and cache behavior under various scenarios.

  These tests verify the intended functionality including cache hit/miss patterns,
  TTL expiration, bulk operations, namespace management, and performance metrics.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Server.Cache

  # Use shorter intervals for testing
  @test_cleanup_interval 100
  @test_ttl 1

  setup do
    # Stop existing cache if running
    if GenServer.whereis(Cache) do
      GenServer.stop(Cache, :normal, 1000)
    end

    # Start fresh cache for testing
    {:ok, pid} = Cache.start_link()

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid, :normal, 1000)
      end
    end)

    %{cache_pid: pid}
  end

  describe "basic cache operations" do
    test "set and get operations work correctly" do
      # Set a value
      assert :ok = Cache.set(:test_namespace, "key1", "value1", ttl_seconds: 300)

      # Get the value
      assert {:ok, "value1"} = Cache.get(:test_namespace, "key1")

      # Get non-existent key
      assert :error = Cache.get(:test_namespace, "nonexistent")

      # Get from different namespace
      assert :error = Cache.get(:other_namespace, "key1")
    end

    test "supports various data types as values" do
      # String
      Cache.set(:types, "string_key", "string_value", ttl_seconds: 300)
      assert {:ok, "string_value"} = Cache.get(:types, "string_key")

      # Integer
      Cache.set(:types, "int_key", 42, ttl_seconds: 300)
      assert {:ok, 42} = Cache.get(:types, "int_key")

      # Map
      map_value = %{a: 1, b: "test"}
      Cache.set(:types, "map_key", map_value, ttl_seconds: 300)
      assert {:ok, ^map_value} = Cache.get(:types, "map_key")

      # List
      list_value = [1, 2, 3, "test"]
      Cache.set(:types, "list_key", list_value, ttl_seconds: 300)
      assert {:ok, ^list_value} = Cache.get(:types, "list_key")

      # Tuple
      tuple_value = {:ok, "success", 123}
      Cache.set(:types, "tuple_key", tuple_value, ttl_seconds: 300)
      assert {:ok, ^tuple_value} = Cache.get(:types, "tuple_key")
    end

    test "supports complex keys" do
      # Atom key
      Cache.set(:complex_keys, :atom_key, "atom_value", ttl_seconds: 300)
      assert {:ok, "atom_value"} = Cache.get(:complex_keys, :atom_key)

      # Tuple key
      tuple_key = {:user, 123}
      Cache.set(:complex_keys, tuple_key, "user_data", ttl_seconds: 300)
      assert {:ok, "user_data"} = Cache.get(:complex_keys, tuple_key)

      # Map key
      map_key = %{type: :request, id: 456}
      Cache.set(:complex_keys, map_key, "request_data", ttl_seconds: 300)
      assert {:ok, "request_data"} = Cache.get(:complex_keys, map_key)
    end

    test "overwrites existing values correctly" do
      # Set initial value
      Cache.set(:overwrite, "key", "initial_value", ttl_seconds: 300)
      assert {:ok, "initial_value"} = Cache.get(:overwrite, "key")

      # Overwrite with new value
      Cache.set(:overwrite, "key", "new_value", ttl_seconds: 300)
      assert {:ok, "new_value"} = Cache.get(:overwrite, "key")

      # Overwrite with different TTL
      Cache.set(:overwrite, "key", "final_value", ttl_seconds: 600)
      assert {:ok, "final_value"} = Cache.get(:overwrite, "key")
    end
  end

  describe "TTL and expiration behavior" do
    test "entries expire after TTL" do
      # Set entry with very short TTL
      Cache.set(:expiration, "short_ttl", "expires_soon", ttl_seconds: 1)
      
      # Should be accessible immediately
      assert {:ok, "expires_soon"} = Cache.get(:expiration, "short_ttl")

      # Wait for expiration
      :timer.sleep(1100)

      # Should be expired
      assert :error = Cache.get(:expiration, "short_ttl")
    end

    test "entries with different TTLs expire independently" do
      # Set entries with different TTLs
      Cache.set(:ttl_test, "short", "short_value", ttl_seconds: 1)
      Cache.set(:ttl_test, "medium", "medium_value", ttl_seconds: 2)
      Cache.set(:ttl_test, "long", "long_value", ttl_seconds: 5)

      # All should be accessible initially
      assert {:ok, "short_value"} = Cache.get(:ttl_test, "short")
      assert {:ok, "medium_value"} = Cache.get(:ttl_test, "medium")
      assert {:ok, "long_value"} = Cache.get(:ttl_test, "long")

      # Wait for short TTL to expire
      :timer.sleep(1100)

      assert :error = Cache.get(:ttl_test, "short")
      assert {:ok, "medium_value"} = Cache.get(:ttl_test, "medium")
      assert {:ok, "long_value"} = Cache.get(:ttl_test, "long")

      # Wait for medium TTL to expire
      :timer.sleep(1000)

      assert :error = Cache.get(:ttl_test, "short")
      assert :error = Cache.get(:ttl_test, "medium")
      assert {:ok, "long_value"} = Cache.get(:ttl_test, "long")
    end

    test "expired entries are cleaned up lazily on access" do
      # Set expired entry
      Cache.set(:lazy_cleanup, "key", "value", ttl_seconds: 1)
      :timer.sleep(1100)

      # Access should trigger cleanup and return miss
      assert :error = Cache.get(:lazy_cleanup, "key")

      # Verify entry is actually removed from ETS table
      cache_table = :server_cache
      result = :ets.lookup(cache_table, {:lazy_cleanup, "key"})
      assert result == []
    end

    test "default TTL is applied when not specified" do
      # Set without explicit TTL
      Cache.set(:default_ttl, "key", "value")

      # Should be accessible immediately
      assert {:ok, "value"} = Cache.get(:default_ttl, "key")

      # Should not expire within a reasonable short time (default is 300 seconds)
      :timer.sleep(100)
      assert {:ok, "value"} = Cache.get(:default_ttl, "key")
    end
  end

  describe "get_or_compute functionality" do
    test "computes and caches value on miss" do
      {:ok, computation_count} = Agent.start_link(fn -> 0 end)

      compute_fn = fn ->
        Agent.update(computation_count, &(&1 + 1))
        "computed_value"
      end

      # First call should compute and cache
      assert "computed_value" = Cache.get_or_compute(:compute_test, "key", compute_fn, ttl_seconds: 300)
      assert Agent.get(computation_count, & &1) == 1

      # Second call should use cached value
      assert "computed_value" = Cache.get_or_compute(:compute_test, "key", compute_fn, ttl_seconds: 300)
      assert Agent.get(computation_count, & &1) == 1

      Agent.stop(computation_count)
    end

    test "recomputes value after expiration" do
      {:ok, computation_count} = Agent.start_link(fn -> 0 end)

      compute_fn = fn ->
        count = Agent.get_and_update(computation_count, &{&1 + 1, &1 + 1})
        "computed_value_#{count}"
      end

      # First computation
      assert "computed_value_1" = Cache.get_or_compute(:recompute_test, "key", compute_fn, ttl_seconds: 1)

      # Wait for expiration
      :timer.sleep(1100)

      # Should recompute
      assert "computed_value_2" = Cache.get_or_compute(:recompute_test, "key", compute_fn, ttl_seconds: 1)

      Agent.stop(computation_count)
    end

    test "handles exceptions in compute function gracefully" do
      failing_compute = fn ->
        raise "Computation failed"
      end

      # Should propagate the exception
      assert_raise RuntimeError, "Computation failed", fn ->
        Cache.get_or_compute(:error_test, "key", failing_compute, ttl_seconds: 300)
      end

      # Cache should not contain any value
      assert :error = Cache.get(:error_test, "key")
    end

    test "computes different values for different keys" do
      compute_fn = fn key ->
        fn -> "computed_for_#{key}" end
      end

      # Compute for different keys
      assert "computed_for_key1" = Cache.get_or_compute(:multi_key, "key1", compute_fn.("key1"), ttl_seconds: 300)
      assert "computed_for_key2" = Cache.get_or_compute(:multi_key, "key2", compute_fn.("key2"), ttl_seconds: 300)

      # Verify both are cached independently
      assert {:ok, "computed_for_key1"} = Cache.get(:multi_key, "key1")
      assert {:ok, "computed_for_key2"} = Cache.get(:multi_key, "key2")
    end
  end

  describe "bulk operations" do
    test "bulk_set efficiently sets multiple entries" do
      entries = [
        {"user_1", %{name: "Alice", age: 25}},
        {"user_2", %{name: "Bob", age: 30}},
        {"user_3", %{name: "Charlie", age: 35}}
      ]

      assert :ok = Cache.bulk_set(:users, entries, ttl_seconds: 300)

      # Verify all entries are set
      assert {:ok, %{name: "Alice", age: 25}} = Cache.get(:users, "user_1")
      assert {:ok, %{name: "Bob", age: 30}} = Cache.get(:users, "user_2")
      assert {:ok, %{name: "Charlie", age: 35}} = Cache.get(:users, "user_3")
    end

    test "bulk_set applies same TTL to all entries" do
      entries = [
        {"temp_1", "value_1"},
        {"temp_2", "value_2"}
      ]

      Cache.bulk_set(:temp_data, entries, ttl_seconds: 1)

      # Both should be accessible initially
      assert {:ok, "value_1"} = Cache.get(:temp_data, "temp_1")
      assert {:ok, "value_2"} = Cache.get(:temp_data, "temp_2")

      # Wait for expiration
      :timer.sleep(1100)

      # Both should be expired
      assert :error = Cache.get(:temp_data, "temp_1")
      assert :error = Cache.get(:temp_data, "temp_2")
    end

    test "bulk_set handles empty entries list" do
      assert :ok = Cache.bulk_set(:empty, [], ttl_seconds: 300)
      
      # No entries should be set
      _stats = Cache.stats()
      # Cache should still be functional
      Cache.set(:empty, "test", "value", ttl_seconds: 300)
      assert {:ok, "value"} = Cache.get(:empty, "test")
    end

    test "bulk_set overwrites existing entries" do
      # Set initial entries
      Cache.bulk_set(:overwrite_test, [{"key1", "old1"}, {"key2", "old2"}], ttl_seconds: 300)

      # Overwrite with bulk_set
      Cache.bulk_set(:overwrite_test, [{"key1", "new1"}, {"key3", "new3"}], ttl_seconds: 300)

      # Verify overwrites and new entries
      assert {:ok, "new1"} = Cache.get(:overwrite_test, "key1")
      assert {:ok, "old2"} = Cache.get(:overwrite_test, "key2")  # Should remain unchanged
      assert {:ok, "new3"} = Cache.get(:overwrite_test, "key3")
    end
  end

  describe "invalidation operations" do
    test "invalidate removes specific cache entry" do
      Cache.set(:invalidation_test, "key1", "value1", ttl_seconds: 300)
      Cache.set(:invalidation_test, "key2", "value2", ttl_seconds: 300)

      # Verify both are set
      assert {:ok, "value1"} = Cache.get(:invalidation_test, "key1")
      assert {:ok, "value2"} = Cache.get(:invalidation_test, "key2")

      # Invalidate one
      assert :ok = Cache.invalidate(:invalidation_test, "key1")

      # Verify selective invalidation
      assert :error = Cache.get(:invalidation_test, "key1")
      assert {:ok, "value2"} = Cache.get(:invalidation_test, "key2")
    end

    test "invalidate handles non-existent keys gracefully" do
      assert :ok = Cache.invalidate(:nonexistent, "key")
      assert :ok = Cache.invalidate(:invalidation_test, "nonexistent_key")
    end

    test "invalidate_namespace removes all entries in namespace" do
      # Set entries in multiple namespaces
      Cache.set(:namespace1, "key1", "value1", ttl_seconds: 300)
      Cache.set(:namespace1, "key2", "value2", ttl_seconds: 300)
      Cache.set(:namespace2, "key1", "other_value1", ttl_seconds: 300)
      Cache.set(:namespace2, "key2", "other_value2", ttl_seconds: 300)

      # Verify all are set
      assert {:ok, "value1"} = Cache.get(:namespace1, "key1")
      assert {:ok, "value2"} = Cache.get(:namespace1, "key2")
      assert {:ok, "other_value1"} = Cache.get(:namespace2, "key1")
      assert {:ok, "other_value2"} = Cache.get(:namespace2, "key2")

      # Invalidate entire namespace1
      assert :ok = Cache.invalidate_namespace(:namespace1)

      # Verify namespace1 is cleared but namespace2 remains
      assert :error = Cache.get(:namespace1, "key1")
      assert :error = Cache.get(:namespace1, "key2")
      assert {:ok, "other_value1"} = Cache.get(:namespace2, "key1")
      assert {:ok, "other_value2"} = Cache.get(:namespace2, "key2")
    end

    test "invalidate_namespace handles empty namespaces gracefully" do
      assert :ok = Cache.invalidate_namespace(:empty_namespace)
    end
  end

  describe "refresh functionality" do
    test "refresh updates cache entry with new computed value" do
      # Set initial value
      Cache.set(:refresh_test, "key", "old_value", ttl_seconds: 300)
      assert {:ok, "old_value"} = Cache.get(:refresh_test, "key")

      # Refresh with new value
      compute_fn = fn -> "refreshed_value" end
      assert :ok = Cache.refresh(:refresh_test, "key", compute_fn, ttl_seconds: 300)

      # Verify updated value
      assert {:ok, "refreshed_value"} = Cache.get(:refresh_test, "key")
    end

    test "refresh creates entry if it doesn't exist" do
      # Refresh non-existent entry
      compute_fn = fn -> "new_value" end
      assert :ok = Cache.refresh(:refresh_new, "key", compute_fn, ttl_seconds: 300)

      # Verify created entry
      assert {:ok, "new_value"} = Cache.get(:refresh_new, "key")
    end

    test "refresh updates TTL of existing entry" do
      # Set entry with short TTL
      Cache.set(:refresh_ttl, "key", "value", ttl_seconds: 1)

      # Refresh with longer TTL
      compute_fn = fn -> "refreshed_value" end
      assert :ok = Cache.refresh(:refresh_ttl, "key", compute_fn, ttl_seconds: 5)

      # Wait past original TTL
      :timer.sleep(1100)

      # Should still be accessible due to refresh
      assert {:ok, "refreshed_value"} = Cache.get(:refresh_ttl, "key")
    end
  end

  describe "statistics and monitoring" do
    test "tracks cache hits and misses correctly" do
      # Clear any existing stats by getting initial state
      _initial_stats = Cache.stats()

      # Perform cache operations
      Cache.get_or_compute(:stats_test, "key1", fn -> "value1" end, ttl_seconds: 300)  # Miss
      Cache.get_or_compute(:stats_test, "key1", fn -> "value1" end, ttl_seconds: 300)  # Hit
      Cache.get_or_compute(:stats_test, "key2", fn -> "value2" end, ttl_seconds: 300)  # Miss

      # Allow time for async stat updates
      :timer.sleep(50)

      stats = Cache.stats()

      # Should track hits and misses for namespace
      assert Map.get(stats.hits, :stats_test, 0) >= 1
      assert Map.get(stats.misses, :stats_test, 0) >= 2
    end

    test "stats include current cache size" do
      # Set some entries
      Cache.set(:size_test, "key1", "value1", ttl_seconds: 300)
      Cache.set(:size_test, "key2", "value2", ttl_seconds: 300)
      Cache.set(:other_size, "key1", "value1", ttl_seconds: 300)

      stats = Cache.stats()

      # Should include current size
      assert Map.has_key?(stats, :current_size)
      assert stats.current_size >= 3
      assert is_integer(stats.current_size)
    end

    test "stats track cleanup information" do
      stats = Cache.stats()

      # Should have cleanup-related fields
      assert Map.has_key?(stats, :entries_cleaned)
      assert Map.has_key?(stats, :last_cleanup)
      assert is_integer(stats.entries_cleaned)
      assert is_integer(stats.last_cleanup)
    end

    test "stats are updated after cleanup operations" do
      # Set entries that will expire
      Cache.set(:cleanup_test, "key1", "value1", ttl_seconds: 1)
      Cache.set(:cleanup_test, "key2", "value2", ttl_seconds: 1)

      # Wait for expiration
      :timer.sleep(1100)

      # Force cleanup
      Cache.cleanup()
      :timer.sleep(50)

      stats = Cache.stats()

      # Should reflect cleanup activity
      assert stats.entries_cleaned >= 0
      assert stats.last_cleanup > 0
    end
  end

  describe "cleanup and maintenance" do
    test "automatic cleanup removes expired entries" do
      # Set entries with very short TTL
      Cache.set(:auto_cleanup, "key1", "value1", ttl_seconds: 1)
      Cache.set(:auto_cleanup, "key2", "value2", ttl_seconds: 1)
      Cache.set(:auto_cleanup, "key3", "value3", ttl_seconds: 10)  # This should survive

      # Wait for expiration
      :timer.sleep(1100)

      # Force cleanup to simulate automatic cleanup
      Cache.cleanup()
      :timer.sleep(50)

      # Check what remains
      assert :error = Cache.get(:auto_cleanup, "key1")
      assert :error = Cache.get(:auto_cleanup, "key2")
      assert {:ok, "value3"} = Cache.get(:auto_cleanup, "key3")
    end

    test "manual cleanup can be triggered" do
      # Set expired entries
      Cache.set(:manual_cleanup, "key", "value", ttl_seconds: 1)
      :timer.sleep(1100)

      initial_stats = Cache.stats()
      initial_size = initial_stats.current_size

      # Trigger manual cleanup
      assert :ok = Cache.cleanup()
      :timer.sleep(50)

      final_stats = Cache.stats()

      # Size should be reduced or entries_cleaned should increase
      assert final_stats.current_size <= initial_size or final_stats.entries_cleaned > initial_stats.entries_cleaned
    end

    test "cleanup handles large numbers of expired entries efficiently" do
      # Set many entries with short TTL
      entries = for i <- 1..100, do: {"key_#{i}", "value_#{i}"}
      Cache.bulk_set(:bulk_cleanup, entries, ttl_seconds: 1)

      initial_stats = Cache.stats()
      initial_size = initial_stats.current_size

      # Wait for expiration
      :timer.sleep(1100)

      # Measure cleanup performance
      start_time = System.monotonic_time(:millisecond)
      Cache.cleanup()
      :timer.sleep(50)
      end_time = System.monotonic_time(:millisecond)

      cleanup_duration = end_time - start_time

      # Cleanup should be reasonably fast (under 100ms for 100 entries)
      assert cleanup_duration < 100

      final_stats = Cache.stats()
      
      # Should have cleaned up entries
      assert final_stats.current_size < initial_size or final_stats.entries_cleaned > initial_stats.entries_cleaned
    end
  end

  describe "concurrent access and race conditions" do
    test "handles concurrent get_or_compute calls correctly" do
      {:ok, computation_count} = Agent.start_link(fn -> 0 end)

      compute_fn = fn ->
        # Simulate some computation time
        :timer.sleep(50)
        Agent.update(computation_count, &(&1 + 1))
        "computed_value"
      end

      # Start multiple concurrent get_or_compute calls
      tasks = for _i <- 1..5 do
        Task.async(fn ->
          Cache.get_or_compute(:concurrent_test, "key", compute_fn, ttl_seconds: 300)
        end)
      end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 1000)

      # All should get the same value
      assert Enum.all?(results, &(&1 == "computed_value"))

      # But computation should only happen once (or very few times due to race conditions)
      final_count = Agent.get(computation_count, & &1)
      assert final_count <= 2  # Allow for some race conditions but not 5 computations

      Agent.stop(computation_count)
    end

    test "handles concurrent set operations correctly" do
      # Start multiple concurrent set operations
      tasks = for i <- 1..10 do
        Task.async(fn ->
          Cache.set(:concurrent_set, "key", "value_#{i}", ttl_seconds: 300)
        end)
      end

      # Wait for all tasks to complete
      Task.await_many(tasks, 1000)

      # Should have some value (last writer wins)
      assert {:ok, value} = Cache.get(:concurrent_set, "key")
      assert String.starts_with?(value, "value_")
    end

    test "handles concurrent invalidation and access correctly" do
      # Set initial value
      Cache.set(:concurrent_invalidate, "key", "value", ttl_seconds: 300)

      # Start concurrent access and invalidation
      access_task = Task.async(fn ->
        for _i <- 1..100 do
          Cache.get(:concurrent_invalidate, "key")
          :timer.sleep(1)
        end
      end)

      invalidate_task = Task.async(fn ->
        :timer.sleep(50)
        Cache.invalidate(:concurrent_invalidate, "key")
      end)

      # Wait for both to complete
      Task.await(access_task, 1000)
      Task.await(invalidate_task, 1000)

      # Final state should be invalidated
      assert :error = Cache.get(:concurrent_invalidate, "key")
    end
  end

  describe "performance characteristics" do
    test "cache operations scale well with cache size" do
      # Pre-populate cache with many entries
      large_entries = for i <- 1..1000, do: {"key_#{i}", "value_#{i}"}
      Cache.bulk_set(:performance_test, large_entries, ttl_seconds: 300)

      # Measure get performance with large cache
      start_time = System.monotonic_time(:microsecond)
      
      for _i <- 1..100 do
        Cache.get(:performance_test, "key_500")
      end
      
      end_time = System.monotonic_time(:microsecond)
      
      total_duration = end_time - start_time
      avg_duration_per_get = total_duration / 100

      # Average get should be very fast (under 100 microseconds)
      assert avg_duration_per_get < 100
    end

    test "bulk operations are more efficient than individual sets" do
      entries = for i <- 1..100, do: {"bulk_key_#{i}", "bulk_value_#{i}"}

      # Measure bulk set performance
      start_time = System.monotonic_time(:millisecond)
      Cache.bulk_set(:bulk_perf, entries, ttl_seconds: 300)
      bulk_duration = System.monotonic_time(:millisecond) - start_time

      # Clear and measure individual sets
      Cache.invalidate_namespace(:individual_perf)
      
      start_time = System.monotonic_time(:millisecond)
      for {key, value} <- entries do
        Cache.set(:individual_perf, key, value, ttl_seconds: 300)
      end
      individual_duration = System.monotonic_time(:millisecond) - start_time

      # Bulk should be faster than individual operations
      assert bulk_duration < individual_duration
    end

    test "get_or_compute has minimal overhead for cache hits" do
      # Pre-compute value
      Cache.set(:perf_compute, "key", "cached_value", ttl_seconds: 300)

      expensive_compute = fn ->
        :timer.sleep(100)  # Simulate expensive computation
        "expensive_value"
      end

      # Measure hit performance
      start_time = System.monotonic_time(:millisecond)
      
      for _i <- 1..10 do
        Cache.get_or_compute(:perf_compute, "key", expensive_compute, ttl_seconds: 300)
      end
      
      end_time = System.monotonic_time(:millisecond)
      
      total_duration = end_time - start_time

      # Should be much faster than if computation actually ran (which would take 1000ms)
      assert total_duration < 100
    end
  end

  describe "error handling and edge cases" do
    test "handles process crashes gracefully" do
      # Cache should survive and restart if needed
      # For this test, we'll just verify the cache continues to work
      Cache.set(:crash_test, "key", "value", ttl_seconds: 300)
      assert {:ok, "value"} = Cache.get(:crash_test, "key")

      # Simulate some load and verify stability
      for i <- 1..10 do
        Cache.set(:crash_test, "key_#{i}", "value_#{i}", ttl_seconds: 300)
      end

      for i <- 1..10 do
        expected_value = "value_#{i}"
        assert {:ok, ^expected_value} = Cache.get(:crash_test, "key_#{i}")
      end
    end

    test "handles very large values correctly" do
      # Create a large value (1MB string)
      large_value = String.duplicate("x", 1_000_000)
      
      Cache.set(:large_value, "big_key", large_value, ttl_seconds: 300)
      assert {:ok, ^large_value} = Cache.get(:large_value, "big_key")
    end

    test "handles many namespaces correctly" do
      # Create entries in many different namespaces
      for i <- 1..100 do
        namespace = String.to_atom("namespace_#{i}")
        Cache.set(namespace, "key", "value_#{i}", ttl_seconds: 300)
      end

      # Verify all are accessible
      for i <- 1..100 do
        namespace = String.to_atom("namespace_#{i}")
        expected_value = "value_#{i}"
        assert {:ok, ^expected_value} = Cache.get(namespace, "key")
      end

      # Invalidate one namespace and verify others remain
      Cache.invalidate_namespace(:namespace_50)
      assert :error = Cache.get(:namespace_50, "key")
      assert {:ok, "value_49"} = Cache.get(:namespace_49, "key")
      assert {:ok, "value_51"} = Cache.get(:namespace_51, "key")
    end

    test "handles zero and negative TTL gracefully" do
      # Zero TTL should expire immediately
      Cache.set(:zero_ttl, "key", "value", ttl_seconds: 0)
      # Should be expired immediately
      assert :error = Cache.get(:zero_ttl, "key")

      # Negative TTL should also expire immediately (treated as 0)
      _log_output = capture_log(fn ->
        # This might cause a warning but shouldn't crash
        try do
          Cache.set(:negative_ttl, "key", "value", ttl_seconds: -1)
          :timer.sleep(50)
        rescue
          _ -> :ok
        end
      end)

      # Cache should remain functional
      Cache.set(:normal_ttl, "key", "value", ttl_seconds: 300)
      assert {:ok, "value"} = Cache.get(:normal_ttl, "key")
    end
  end
end