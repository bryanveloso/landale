defmodule Server.Services.CacheIntegrationTest do
  use ExUnit.Case, async: false

  alias Server.Cache

  setup do
    # Start required services for testing
    start_supervised!(Cache)

    # Clear any existing cache entries
    :ets.delete_all_objects(:server_cache)

    :ok
  end

  describe "cache behavior verification" do
    test "cache stores and retrieves values correctly" do
      # Test basic cache functionality
      test_data = %{
        connected: true,
        streaming: false,
        recording: false,
        current_scene: "Scene 1"
      }

      # Set cache entry
      assert :ok = Cache.set(:obs_service, :basic_status, test_data, ttl_seconds: 10)

      # Verify retrieval
      assert {:ok, retrieved_data} = Cache.get(:obs_service, :basic_status)
      assert retrieved_data == test_data

      # Test get_or_compute with cached value
      result =
        Cache.get_or_compute(
          :obs_service,
          :basic_status,
          fn ->
            # Should not be called
            %{different: "data"}
          end,
          ttl_seconds: 10
        )

      assert result == test_data
    end

    test "cache invalidation works correctly" do
      # Set up initial cache
      initial_data = %{
        connected: true,
        streaming: false,
        recording: false,
        current_scene: "Scene 1"
      }

      # Cache the initial state
      Cache.set(:obs_service, :basic_status, initial_data, ttl_seconds: 30)

      # Verify cache is populated
      assert {:ok, cached_data} = Cache.get(:obs_service, :basic_status)
      assert cached_data == initial_data

      # Simulate cache invalidation (as would happen on state update)
      Cache.invalidate(:obs_service, :basic_status)

      # Verify cache is cleared
      assert :error = Cache.get(:obs_service, :basic_status)
    end

    test "different service namespaces work independently" do
      obs_data = %{connected: true, streaming: false}
      twitch_data = %{subscription_count: 5, connected: true}

      # Set cache entries for different services
      Cache.set(:obs_service, :status, obs_data, ttl_seconds: 30)
      Cache.set(:twitch_service, :status, twitch_data, ttl_seconds: 30)

      # Verify both are cached correctly
      assert {:ok, ^obs_data} = Cache.get(:obs_service, :status)
      assert {:ok, ^twitch_data} = Cache.get(:twitch_service, :status)

      # Invalidate only OBS cache
      Cache.invalidate(:obs_service, :status)

      # OBS cache should be gone, Twitch cache should remain
      assert :error = Cache.get(:obs_service, :status)
      assert {:ok, ^twitch_data} = Cache.get(:twitch_service, :status)
    end

    test "namespace invalidation clears all entries in namespace" do
      # Set multiple entries in same namespace
      Cache.set(:test_service, :key1, "value1", ttl_seconds: 30)
      Cache.set(:test_service, :key2, "value2", ttl_seconds: 30)
      Cache.set(:other_service, :key3, "value3", ttl_seconds: 30)

      # Verify all are cached
      assert {:ok, "value1"} = Cache.get(:test_service, :key1)
      assert {:ok, "value2"} = Cache.get(:test_service, :key2)
      assert {:ok, "value3"} = Cache.get(:other_service, :key3)

      # Invalidate entire test_service namespace
      Cache.invalidate_namespace(:test_service)

      # test_service entries should be gone, other_service should remain
      assert :error = Cache.get(:test_service, :key1)
      assert :error = Cache.get(:test_service, :key2)
      assert {:ok, "value3"} = Cache.get(:other_service, :key3)
    end
  end

  describe "cache performance and load testing" do
    test "cache handles concurrent access efficiently" do
      # Set up cached value
      test_data = %{status: "active", timestamp: System.system_time()}
      Cache.set(:performance_test, :shared_data, test_data, ttl_seconds: 10)

      # Start multiple concurrent readers
      tasks =
        Enum.map(1..20, fn i ->
          Task.async(fn ->
            # Each task reads the cache multiple times
            results =
              Enum.map(1..10, fn _read ->
                case Cache.get(:performance_test, :shared_data) do
                  {:ok, data} -> {:hit, data}
                  :error -> :miss
                end
              end)

            {i, results}
          end)
        end)

      # Collect all results
      all_results = Task.await_many(tasks, 5000)

      # Verify all reads were successful
      Enum.each(all_results, fn {_task_id, results} ->
        Enum.each(results, fn result ->
          assert {:hit, ^test_data} = result
        end)
      end)

      # Verify cache is still functional
      assert {:ok, ^test_data} = Cache.get(:performance_test, :shared_data)
    end

    test "cache remains functional after TTL expiration" do
      # Set up cache entries with very short TTL
      Cache.set(:ttl_test, :short_lived, "expires_soon", ttl_seconds: 1)
      Cache.set(:ttl_test, :long_lived, "stays_long", ttl_seconds: 10)

      # Verify both are initially cached
      assert {:ok, "expires_soon"} = Cache.get(:ttl_test, :short_lived)
      assert {:ok, "stays_long"} = Cache.get(:ttl_test, :long_lived)

      # Wait for short TTL to expire
      Process.sleep(1100)

      # Short-lived entry should be expired, long-lived should remain
      assert :error = Cache.get(:ttl_test, :short_lived)
      assert {:ok, "stays_long"} = Cache.get(:ttl_test, :long_lived)

      # Cache should still be functional for new entries
      Cache.set(:ttl_test, :new_entry, "still_works", ttl_seconds: 10)
      assert {:ok, "still_works"} = Cache.get(:ttl_test, :new_entry)
    end
  end

  describe "cache resource management" do
    test "cache statistics track operations correctly" do
      # Perform some cache operations
      Cache.set(:stats_test, :key1, "value1", ttl_seconds: 10)
      Cache.set(:stats_test, :key2, "value2", ttl_seconds: 10)

      # Get cache statistics
      stats = Cache.stats()

      # Verify stats structure
      assert is_map(stats)
      assert Map.has_key?(stats, :current_size)
      assert Map.has_key?(stats, :hits)
      assert Map.has_key?(stats, :misses)
      assert Map.has_key?(stats, :entries_cleaned)

      # Size should reflect our additions
      assert stats.current_size >= 2
    end

    test "bulk operations work efficiently" do
      # Prepare bulk data
      bulk_entries =
        Enum.map(1..20, fn i ->
          {"bulk_key_#{i}", "bulk_value_#{i}"}
        end)

      # Perform bulk set
      assert :ok = Cache.bulk_set(:bulk_test, bulk_entries, ttl_seconds: 10)

      # Verify all entries were set
      Enum.each(bulk_entries, fn {key, expected_value} ->
        assert {:ok, ^expected_value} = Cache.get(:bulk_test, key)
      end)

      # Test bulk invalidation via namespace
      Cache.invalidate_namespace(:bulk_test)

      # Verify all entries are gone
      Enum.each(bulk_entries, fn {key, _value} ->
        assert :error = Cache.get(:bulk_test, key)
      end)
    end
  end
end

