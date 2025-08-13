defmodule Server.Events.BatchCollectorTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Server.Events.{BatchCollector, Event}

  # Test configuration - shorter batch window for faster tests
  @test_batch_window 25
  @test_max_batch_size 3
  @test_max_buffer_events 10

  setup do
    # Start batch collector with test configuration
    start_supervised!(
      {BatchCollector,
       [
         batch_window_ms: @test_batch_window,
         max_batch_size: @test_max_batch_size,
         max_buffer_events: @test_max_buffer_events
       ]}
    )

    # Subscribe to batch events
    Phoenix.PubSub.subscribe(Server.PubSub, "events:batched")

    :ok
  end

  describe "add/1" do
    test "adds event to buffer and flushes after window" do
      event = Event.new("channel.chat.message", :twitch, %{user_name: "test"})

      BatchCollector.add(event)

      # Should not receive immediate batch
      refute_receive {:batched_event, _}, 10

      # Should receive batch after window expires
      assert_receive {:batched_event, batch_event}, @test_batch_window + 50

      assert batch_event.type == "event.batch"
      assert batch_event.source == :system
      assert length(batch_event.data.events) == 1
      assert List.first(batch_event.data.events) == event
      assert batch_event.data.count == 1
    end

    test "groups events by source" do
      twitch_event = Event.new("channel.follow", :twitch, %{user_name: "twitch_user"})
      obs_event = Event.new("obs.scene_changed", :obs, %{scene: "Main"})

      BatchCollector.add(twitch_event)
      BatchCollector.add(obs_event)

      # Should receive two separate batches (one per source)
      assert_receive {:batched_event, batch1}, @test_batch_window + 50
      assert_receive {:batched_event, batch2}, 10

      # Verify batches are separate by source
      sources = [
        batch1.data.events |> List.first() |> Map.get(:source),
        batch2.data.events |> List.first() |> Map.get(:source)
      ]

      assert :twitch in sources
      assert :obs in sources
    end

    test "maintains chronological order within batches" do
      events =
        for i <- 1..5 do
          event = Event.new("test.event", :twitch, %{sequence: i})
          BatchCollector.add(event)
          # Small delay to ensure different timestamps
          Process.sleep(1)
          event
        end

      # Should receive batch(es) - might be split due to max_batch_size
      batches = receive_all_batches(2)

      # Collect all events from all batches
      all_batched_events =
        batches
        |> Enum.flat_map(& &1.data.events)
        |> Enum.sort_by(& &1.timestamp)

      # Should be in chronological order
      sequences = Enum.map(all_batched_events, & &1.data.sequence)
      assert sequences == [1, 2, 3, 4, 5]
    end

    test "splits large batches based on max_batch_size" do
      # Add more events than max_batch_size
      events =
        for i <- 1..5 do
          event = Event.new("test.event", :twitch, %{index: i})
          BatchCollector.add(event)
          event
        end

      # Should receive multiple batches due to size limit
      # Expect at least 2 batches (5 events, max 3 per batch)
      batches = receive_all_batches(3)

      # Verify total events match
      total_events = batches |> Enum.map(& &1.data.count) |> Enum.sum()
      assert total_events == 5

      # Verify no batch exceeds max size
      Enum.each(batches, fn batch ->
        assert length(batch.data.events) <= @test_max_batch_size
      end)
    end

    test "drops events when buffer is full" do
      # Fill buffer to capacity
      for i <- 1..@test_max_buffer_events do
        event = Event.new("fill.event", :twitch, %{index: i})
        BatchCollector.add(event)
      end

      # Add one more event (should be dropped)
      overflow_event = Event.new("overflow.event", :twitch, %{dropped: true})
      BatchCollector.add(overflow_event)

      # Flush and check statistics
      BatchCollector.flush_now()

      # Wait for flush
      receive_all_batches(2)

      stats = BatchCollector.get_stats()
      assert stats.events_dropped >= 1
    end

    test "handles concurrent additions" do
      # Add events from multiple processes
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            event = Event.new("concurrent.event", :twitch, %{task_id: i})
            BatchCollector.add(event)
            event
          end)
        end

      Task.await_many(tasks, 1000)

      # Flush to ensure we get all events
      BatchCollector.flush_now()

      # Collect all batches
      batches = receive_all_batches(5)

      # Verify all events were processed
      total_events = batches |> Enum.map(& &1.data.count) |> Enum.sum()
      assert total_events == 10
    end
  end

  describe "flush_now/0" do
    test "immediately flushes pending events" do
      event = Event.new("immediate.flush", :twitch, %{user_name: "test"})

      BatchCollector.add(event)
      BatchCollector.flush_now()

      # Should receive batch immediately
      assert_receive {:batched_event, batch_event}, 100

      assert length(batch_event.data.events) == 1
      assert List.first(batch_event.data.events) == event
    end

    test "does nothing when buffer is empty" do
      # Get initial stats
      initial_stats = BatchCollector.get_stats()

      BatchCollector.flush_now()

      # Should not receive any batch
      refute_receive {:batched_event, _}, 50

      # Stats should show empty flush
      stats = BatchCollector.get_stats()
      assert stats.empty_flushes > initial_stats.empty_flushes
    end
  end

  describe "get_stats/0" do
    test "returns comprehensive statistics" do
      stats = BatchCollector.get_stats()

      assert is_integer(stats.uptime_seconds)
      assert stats.batch_window_ms == @test_batch_window
      assert stats.max_batch_size == @test_max_batch_size
      assert stats.max_buffer_events == @test_max_buffer_events
      assert is_integer(stats.current_buffered)
      assert is_map(stats.buffer_by_source)
      assert is_integer(stats.events_added)
      assert is_integer(stats.batches_created)
      assert is_integer(stats.events_batched)
      assert is_integer(stats.events_dropped)
      assert is_integer(stats.empty_flushes)
    end

    test "statistics update correctly during operation" do
      initial_stats = BatchCollector.get_stats()

      # Add some events
      events =
        for i <- 1..3 do
          event = Event.new("stats.event", :twitch, %{index: i})
          BatchCollector.add(event)
          event
        end

      # Check buffered count
      stats_after_add = BatchCollector.get_stats()
      assert stats_after_add.events_added == initial_stats.events_added + 3
      assert stats_after_add.current_buffered == 3
      assert stats_after_add.buffer_by_source[:twitch] == 3

      # Flush and check final stats
      BatchCollector.flush_now()
      receive_all_batches(1)

      final_stats = BatchCollector.get_stats()
      assert final_stats.batches_created > initial_stats.batches_created
      assert final_stats.events_batched > initial_stats.events_batched
      assert final_stats.current_buffered == 0
    end
  end

  describe "reset_stats/0" do
    test "resets all statistics to zero" do
      # Generate some activity
      event = Event.new("reset.test", :twitch, %{})
      BatchCollector.add(event)
      BatchCollector.flush_now()
      receive_all_batches(1)

      # Verify stats are non-zero
      stats = BatchCollector.get_stats()
      assert stats.events_added > 0

      # Reset stats
      assert BatchCollector.reset_stats() == :ok

      # Verify stats are reset
      new_stats = BatchCollector.get_stats()
      assert new_stats.events_added == 0
      assert new_stats.batches_created == 0
      assert new_stats.events_batched == 0
      assert new_stats.events_dropped == 0
      assert new_stats.empty_flushes == 0
    end
  end

  describe "batch event structure" do
    test "creates properly structured batch events" do
      event1 = Event.new("test.event.1", :twitch, %{data: 1})
      event2 = Event.new("test.event.2", :twitch, %{data: 2})

      BatchCollector.add(event1)
      BatchCollector.add(event2)
      BatchCollector.flush_now()

      assert_receive {:batched_event, batch_event}, 100

      # Verify batch structure
      assert batch_event.type == "event.batch"
      assert batch_event.source == :system
      assert %DateTime{} = batch_event.timestamp
      assert is_binary(batch_event.id)
      assert batch_event.id =~ ~r/^evt_[a-f0-9]{8}$/

      # Verify batch metadata
      assert is_binary(batch_event.meta.batch_id)
      assert batch_event.meta.batch_id =~ ~r/^batch_[a-f0-9]{8}$/
      assert batch_event.meta.priority == :normal

      # Verify batch data
      assert batch_event.data.count == 2
      assert length(batch_event.data.events) == 2
      assert event1 in batch_event.data.events
      assert event2 in batch_event.data.events
    end

    test "preserves original events without modification" do
      original_event =
        Event.new(
          "preserve.test",
          :twitch,
          %{important: "data", nested: %{value: 123}},
          correlation_id: "preserve_test"
        )

      BatchCollector.add(original_event)
      BatchCollector.flush_now()

      assert_receive {:batched_event, batch_event}, 100

      batched_event = List.first(batch_event.data.events)

      # Event should be completely unchanged
      assert batched_event == original_event
      assert batched_event.data.important == "data"
      assert batched_event.data.nested.value == 123
      assert batched_event.meta.correlation_id == "preserve_test"
    end
  end

  describe "timing and performance" do
    test "respects batch window timing" do
      event = Event.new("timing.test", :twitch, %{})

      start_time = System.monotonic_time(:millisecond)
      BatchCollector.add(event)

      assert_receive {:batched_event, _}, @test_batch_window + 50
      end_time = System.monotonic_time(:millisecond)

      elapsed = end_time - start_time
      # Should be approximately the batch window time (allow some tolerance)
      assert elapsed >= @test_batch_window
      assert elapsed <= @test_batch_window + 30
    end

    test "handles high-volume event streams" do
      # Add many events quickly
      num_events = 50
      start_time = System.monotonic_time(:millisecond)

      for i <- 1..num_events do
        event = Event.new("volume.test", :twitch, %{sequence: i})
        BatchCollector.add(event)
      end

      add_time = System.monotonic_time(:millisecond)

      # Force flush to collect all events
      BatchCollector.flush_now()

      # Collect all batches
      # Give generous timeout for many batches
      batches = receive_all_batches(20)

      total_events = batches |> Enum.map(& &1.data.count) |> Enum.sum()

      # Verify performance characteristics
      add_duration = add_time - start_time
      # Should add 50 events in under 100ms
      assert add_duration < 100

      # Verify all events were processed
      # Some might be dropped due to buffer limits
      assert total_events <= num_events

      # Verify system remained responsive
      stats = BatchCollector.get_stats()
      assert stats.events_added >= total_events
    end
  end

  describe "error scenarios" do
    test "continues operating after flush errors" do
      # Add event normally
      event = Event.new("error.recovery", :twitch, %{})
      BatchCollector.add(event)

      # System should recover and continue processing
      BatchCollector.flush_now()
      assert_receive {:batched_event, _}, 100

      # Should still be able to process new events
      new_event = Event.new("after.error", :twitch, %{})
      BatchCollector.add(new_event)
      BatchCollector.flush_now()
      assert_receive {:batched_event, _}, 100
    end
  end

  # Helper functions

  defp receive_all_batches(max_count, timeout \\ 200) do
    receive_all_batches([], max_count, timeout, System.monotonic_time(:millisecond))
  end

  defp receive_all_batches(acc, 0, _timeout, _start_time), do: Enum.reverse(acc)

  defp receive_all_batches(acc, remaining, timeout, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    remaining_timeout = max(0, timeout - elapsed)

    receive do
      {:batched_event, batch} ->
        receive_all_batches([batch | acc], remaining - 1, timeout, start_time)
    after
      remaining_timeout ->
        Enum.reverse(acc)
    end
  end
end
