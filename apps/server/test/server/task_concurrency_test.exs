defmodule Server.TaskConcurrencyTest do
  use Server.DataCase

  describe "DBTaskSupervisor concurrency limits" do
    setup do
      # Start DBTaskSupervisor for tests
      case start_supervised(
             {DynamicSupervisor, name: Server.DBTaskSupervisor, strategy: :one_for_one, max_children: 10}
           ) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    test "respects max_children limit of 10" do
      # Get initial child count
      initial_count = DynamicSupervisor.count_children(Server.DBTaskSupervisor).active

      # Try to start 15 tasks
      results =
        for i <- 1..15 do
          DynamicSupervisor.start_child(Server.DBTaskSupervisor, {Task,
           fn ->
             # Simulate work
             Process.sleep(100)
           end})
        end

      # Count successful starts
      successful =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      # Count max_children errors
      max_children_errors =
        Enum.count(results, fn
          {:error, :max_children} -> true
          _ -> false
        end)

      # Should have started exactly 10 tasks (or less if some were already running)
      assert successful <= 10 - initial_count
      assert successful + max_children_errors == 15

      # Wait for tasks to complete
      Process.sleep(150)
    end
  end
end
