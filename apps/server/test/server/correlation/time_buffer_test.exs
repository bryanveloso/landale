defmodule Server.Correlation.TimeBufferTest do
  use ExUnit.Case, async: true
  alias Server.Correlation.TimeBuffer

  describe "new/1" do
    test "creates buffer with default settings" do
      buffer = TimeBuffer.new()
      assert TimeBuffer.size(buffer) == 0
    end

    test "creates buffer with custom settings" do
      buffer = TimeBuffer.new(window_ms: 60_000, max_size: 200)
      assert TimeBuffer.size(buffer) == 0
    end
  end

  describe "add/2" do
    test "adds items to buffer" do
      buffer = TimeBuffer.new()

      item = %{id: 1, timestamp: System.system_time(:millisecond)}
      buffer = TimeBuffer.add(buffer, item)

      assert TimeBuffer.size(buffer) == 1
    end

    test "respects max_size limit" do
      buffer = TimeBuffer.new(max_size: 3)

      # Add 5 items
      buffer =
        Enum.reduce(1..5, buffer, fn i, acc ->
          item = %{id: i, timestamp: System.system_time(:millisecond) + i}
          TimeBuffer.add(acc, item)
        end)

      # Should only have 3 items (newest ones)
      assert TimeBuffer.size(buffer) == 3
      items = TimeBuffer.to_list(buffer)
      assert length(items) == 3

      # Verify we kept the newest items (should be 3, 4, 5)
      ids = Enum.map(items, & &1.id) |> Enum.sort()
      assert ids == [3, 4, 5]
    end

    test "groups items into time chunks" do
      buffer = TimeBuffer.new()
      base_time = System.system_time(:millisecond)

      # Add items in same second
      buffer = TimeBuffer.add(buffer, %{id: 1, timestamp: base_time})
      buffer = TimeBuffer.add(buffer, %{id: 2, timestamp: base_time + 100})
      buffer = TimeBuffer.add(buffer, %{id: 3, timestamp: base_time + 200})

      # Add item in next second
      buffer = TimeBuffer.add(buffer, %{id: 4, timestamp: base_time + 1100})

      assert TimeBuffer.size(buffer) == 4
      # Internal structure should have 2 chunks
      assert length(buffer.chunks) <= 2
    end
  end

  describe "get_range/3" do
    test "returns items within specified time range" do
      buffer = TimeBuffer.new()
      base_time = System.system_time(:millisecond)

      # Add items across 10 seconds
      buffer =
        Enum.reduce(0..9, buffer, fn i, acc ->
          item = %{id: i, timestamp: base_time + i * 1000}
          TimeBuffer.add(acc, item)
        end)

      # Get items from seconds 3-6
      items = TimeBuffer.get_range(buffer, base_time + 3000, base_time + 6000)

      assert length(items) == 4
      ids = Enum.map(items, & &1.id)
      assert ids == [3, 4, 5, 6]
    end

    test "returns empty list for out-of-range query" do
      buffer = TimeBuffer.new()
      base_time = System.system_time(:millisecond)

      buffer = TimeBuffer.add(buffer, %{id: 1, timestamp: base_time})

      # Query for future time
      items = TimeBuffer.get_range(buffer, base_time + 10_000, base_time + 20_000)
      assert items == []

      # Query for past time
      items = TimeBuffer.get_range(buffer, base_time - 20_000, base_time - 10_000)
      assert items == []
    end

    test "handles overlapping chunks correctly" do
      buffer = TimeBuffer.new()
      # Round to second
      base_time = div(System.system_time(:millisecond), 1000) * 1000

      # Add items near chunk boundaries
      buffer = TimeBuffer.add(buffer, %{id: 1, timestamp: base_time + 900})
      buffer = TimeBuffer.add(buffer, %{id: 2, timestamp: base_time + 1100})
      buffer = TimeBuffer.add(buffer, %{id: 3, timestamp: base_time + 1900})

      # Query across chunk boundary
      items = TimeBuffer.get_range(buffer, base_time + 800, base_time + 1200)

      assert length(items) == 2
      ids = Enum.map(items, & &1.id)
      assert 1 in ids
      assert 2 in ids
    end
  end

  describe "to_list/2" do
    test "returns all items in order" do
      buffer = TimeBuffer.new()
      base_time = System.system_time(:millisecond)

      # Add items in random order
      items = [
        %{id: 3, timestamp: base_time + 300},
        %{id: 1, timestamp: base_time + 100},
        %{id: 2, timestamp: base_time + 200}
      ]

      buffer = Enum.reduce(items, buffer, &TimeBuffer.add(&2, &1))

      result = TimeBuffer.to_list(buffer)
      assert length(result) == 3

      # Should be sorted by timestamp
      ids = Enum.map(result, & &1.id)
      assert ids == [1, 2, 3]
    end

    test "filters by max_age_ms" do
      buffer = TimeBuffer.new()
      current_time = System.system_time(:millisecond)

      # Add old and new items
      buffer = TimeBuffer.add(buffer, %{id: 1, timestamp: current_time - 40_000})
      buffer = TimeBuffer.add(buffer, %{id: 2, timestamp: current_time - 20_000})
      buffer = TimeBuffer.add(buffer, %{id: 3, timestamp: current_time - 5_000})

      # Get items from last 30 seconds
      items = TimeBuffer.to_list(buffer, max_age_ms: 30_000)

      assert length(items) == 2
      ids = Enum.map(items, & &1.id)
      assert ids == [2, 3]
    end
  end

  describe "prune/1" do
    test "removes items beyond window" do
      buffer = TimeBuffer.new(window_ms: 5_000)
      current_time = System.system_time(:millisecond)

      # Add old and new items
      buffer = TimeBuffer.add(buffer, %{id: 1, timestamp: current_time - 10_000})
      buffer = TimeBuffer.add(buffer, %{id: 2, timestamp: current_time - 6_000})
      buffer = TimeBuffer.add(buffer, %{id: 3, timestamp: current_time - 4_000})
      buffer = TimeBuffer.add(buffer, %{id: 4, timestamp: current_time - 1_000})

      # Prune old items
      buffer = TimeBuffer.prune(buffer)

      # Should only have items within 5 second window
      assert TimeBuffer.size(buffer) == 2
      items = TimeBuffer.to_list(buffer)
      ids = Enum.map(items, & &1.id)
      assert ids == [3, 4]
    end

    test "removes empty chunks" do
      buffer = TimeBuffer.new(window_ms: 3_000)
      base_time = System.system_time(:millisecond)

      # Add items that will be in different chunks (force different chunks)
      buffer = TimeBuffer.add(buffer, %{id: 1, timestamp: base_time - 10_000})
      buffer = TimeBuffer.add(buffer, %{id: 2, timestamp: base_time - 5_000})
      buffer = TimeBuffer.add(buffer, %{id: 3, timestamp: base_time})

      # Before pruning - should have at least 1 chunk
      assert length(buffer.chunks) >= 1

      # After pruning
      buffer = TimeBuffer.prune(buffer)

      # Old chunks should be removed
      assert TimeBuffer.size(buffer) == 1
      assert length(buffer.chunks) == 1
    end
  end

  describe "size/1" do
    test "tracks size correctly through operations" do
      buffer = TimeBuffer.new(max_size: 5)

      assert TimeBuffer.size(buffer) == 0

      # Add items
      buffer =
        Enum.reduce(1..3, buffer, fn i, acc ->
          TimeBuffer.add(acc, %{id: i, timestamp: System.system_time(:millisecond) + i})
        end)

      assert TimeBuffer.size(buffer) == 3

      # Add more items to trigger size limit
      buffer =
        Enum.reduce(4..7, buffer, fn i, acc ->
          TimeBuffer.add(acc, %{id: i, timestamp: System.system_time(:millisecond) + i})
        end)

      assert TimeBuffer.size(buffer) == 5

      # Prune old items
      buffer =
        TimeBuffer.new(window_ms: 1_000)
        |> TimeBuffer.add(%{id: 1, timestamp: System.system_time(:millisecond) - 2_000})
        |> TimeBuffer.add(%{id: 2, timestamp: System.system_time(:millisecond)})
        |> TimeBuffer.prune()

      assert TimeBuffer.size(buffer) == 1
    end
  end

  describe "performance characteristics" do
    test "handles large buffers efficiently" do
      buffer = TimeBuffer.new(max_size: 1000, window_ms: 60_000)
      base_time = System.system_time(:millisecond)

      # Add 1000 items
      buffer =
        Enum.reduce(1..1000, buffer, fn i, acc ->
          item = %{
            id: i,
            timestamp: base_time - :rand.uniform(60_000),
            data: String.duplicate("x", 100)
          }

          TimeBuffer.add(acc, item)
        end)

      assert TimeBuffer.size(buffer) == 1000

      # Range queries should be fast
      {time, result} =
        :timer.tc(fn ->
          TimeBuffer.get_range(buffer, base_time - 5_000, base_time - 3_000)
        end)

      # Should complete in under 1ms even with 1000 items
      assert time < 1_000
      assert is_list(result)
    end

    test "maintains chunk organization under load" do
      buffer = TimeBuffer.new()
      base_time = div(System.system_time(:millisecond), 1000) * 1000

      # Add items across multiple seconds
      buffer =
        Enum.reduce(0..99, buffer, fn i, acc ->
          # Distribute across 10 seconds
          second = div(i, 10)
          item = %{id: i, timestamp: base_time + second * 1000 + rem(i, 100)}
          TimeBuffer.add(acc, item)
        end)

      # Should have approximately 10 chunks
      assert length(buffer.chunks) <= 10
      assert TimeBuffer.size(buffer) == 100

      # All items should be retrievable
      all_items = TimeBuffer.to_list(buffer)
      assert length(all_items) == 100
    end
  end
end
