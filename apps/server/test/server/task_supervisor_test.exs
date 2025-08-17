defmodule Server.TaskSupervisorTest do
  use ExUnit.Case, async: true

  describe "Task supervision for async operations" do
    test "TaskSupervisor is available in the supervision tree" do
      # Verify the TaskSupervisor exists and is alive
      assert Process.whereis(Server.TaskSupervisor) != nil
      assert Process.alive?(Process.whereis(Server.TaskSupervisor))
    end

    test "TaskSupervisor can start supervised tasks" do
      # Start a simple task that completes successfully
      {:ok, task_pid} =
        Task.Supervisor.start_child(
          Server.TaskSupervisor,
          fn ->
            Process.sleep(10)
            :ok
          end
        )

      assert is_pid(task_pid)
      assert Process.alive?(task_pid)

      # Wait for task to complete
      Process.sleep(50)
      refute Process.alive?(task_pid)
    end

    test "TaskSupervisor handles task failures gracefully" do
      # Start a task that will crash
      {:ok, task_pid} =
        Task.Supervisor.start_child(
          Server.TaskSupervisor,
          fn ->
            Process.sleep(10)
            raise "Intentional test error"
          end
        )

      assert is_pid(task_pid)

      # Wait for task to crash
      Process.sleep(50)

      # The task should have crashed but the supervisor should still be alive
      refute Process.alive?(task_pid)
      assert Process.alive?(Process.whereis(Server.TaskSupervisor))
    end

    test "Multiple async tasks can run concurrently" do
      # Start multiple tasks
      tasks =
        for i <- 1..5 do
          Task.Supervisor.async(
            Server.TaskSupervisor,
            fn ->
              Process.sleep(10)
              {:ok, i}
            end
          )
        end

      # Await all tasks
      results = Enum.map(tasks, &Task.await(&1, 1000))

      assert results == [{:ok, 1}, {:ok, 2}, {:ok, 3}, {:ok, 4}, {:ok, 5}]
    end
  end
end
