defmodule Server.CorrelationIdPoolConcurrencyTest do
  use ExUnit.Case, async: false
  require Logger

  @pool_table_name :correlation_id_pool
  @test_pool_size 10

  describe "concurrent access" do
    setup do
      # Ensure pool is not running
      if Process.whereis(Server.CorrelationIdPool), do: GenServer.stop(Server.CorrelationIdPool)

      # Start fresh pool - it will initialize itself with IDs
      {:ok, _pid} = Server.CorrelationIdPool.start_link()

      # Wait for pool to initialize
      Process.sleep(50)

      :ok
    end

    test "concurrent processes get unique IDs without race conditions" do
      # Spawn multiple processes to get IDs simultaneously
      num_processes = 20
      parent = self()

      # Collect IDs from concurrent processes
      tasks =
        for _ <- 1..num_processes do
          Task.async(fn ->
            id = Server.CorrelationIdPool.get()
            send(parent, {:got_id, id})
            id
          end)
        end

      # Wait for all tasks and collect results
      ids = Enum.map(tasks, &Task.await(&1, 5000))

      # Also collect via messages for verification
      received_ids =
        for _ <- 1..num_processes do
          receive do
            {:got_id, id} -> id
          after
            1000 -> nil
          end
        end
        |> Enum.reject(&is_nil/1)

      # Verify no duplicates
      unique_ids = Enum.uniq(ids)

      assert length(unique_ids) == length(ids),
             "Found duplicate IDs: #{inspect(ids -- unique_ids)}"

      # Verify we got the expected number of IDs
      assert length(ids) == num_processes

      # All IDs should be unique 8-character strings
      assert Enum.all?(ids, fn id ->
               is_binary(id) && String.length(id) == 8
             end)
    end

    test "pool refills correctly after concurrent depletion" do
      # Get initial pool size
      initial_stats = Server.CorrelationIdPool.stats()
      initial_size = initial_stats.pool_size

      # Deplete pool significantly by getting many IDs (more than pool size)
      num_to_get = min(initial_size + 30, 130)
      _ids = for _ <- 1..num_to_get, do: Server.CorrelationIdPool.get()

      # Check pool size decreased significantly
      stats = Server.CorrelationIdPool.stats()
      assert stats.pool_size < 20, "Pool should be nearly depleted, but has #{stats.pool_size} items"

      # Wait for refill message to be processed
      Process.sleep(300)

      # Check pool was refilled
      stats_after = Server.CorrelationIdPool.stats()
      assert stats_after.pool_size > 50, "Pool should be refilled, but only has #{stats_after.pool_size} items"
    end

    test "no race condition with rapid sequential access" do
      # Simulate rapid sequential access that could expose timing issues
      ids =
        for _ <- 1..50 do
          spawn(fn -> Server.CorrelationIdPool.get() end)
          Server.CorrelationIdPool.get()
        end

      # Check for duplicates
      unique_ids = Enum.uniq(ids)

      assert length(unique_ids) == length(ids),
             "Found duplicates in rapid access: #{inspect(ids -- unique_ids)}"
    end
  end
end
