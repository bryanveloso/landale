defmodule Nurvus.ProcessSupervisionTest do
  use ExUnit.Case, async: false
  require Logger

  @moduletag :process

  alias Nurvus.ProcessManager

  describe "process stop verification" do
    @tag :integration
    test "process stops and monitor is cleaned up correctly" do
      # Test the core fix: processes stop properly and monitors are cleaned up
      config = %{
        "id" => "test_stop_verification",
        "name" => "Stop Verification Test",
        "command" => "sleep",
        "args" => ["5"],
        "cwd" => nil,
        "env" => %{},
        "auto_restart" => false,
        "max_restarts" => 0,
        "restart_window" => 60
      }

      # Add and start process
      assert :ok = ProcessManager.add_process(config)
      assert :ok = ProcessManager.start_process("test_stop_verification")

      # Verify running
      assert {:ok, :running} = ProcessManager.get_process_status("test_stop_verification")

      # Stop process
      assert :ok = ProcessManager.stop_process("test_stop_verification")

      # Verify stopped
      assert {:ok, :stopped} = ProcessManager.get_process_status("test_stop_verification")

      # Remove should work without errors (tests monitor cleanup)
      assert :ok = ProcessManager.remove_process("test_stop_verification")
    end
  end

  describe "port conflict prevention" do
    @tag :integration
    test "second process fails when trying to use same port" do
      # Use a random port to avoid conflicts with system services
      test_port = 20_000 + :rand.uniform(9000)

      # Use a simple HTTP server that definitely binds to the port specified in env
      config_base = %{
        "command" => "python3",
        "args" => [
          "-c",
          "import os,http.server,socketserver; port=int(os.environ['PORT']); httpd=socketserver.TCPServer(('',port), http.server.SimpleHTTPRequestHandler); print(f'Server on port {port}'); httpd.serve_forever()"
        ],
        "cwd" => nil,
        "env" => %{"PORT" => to_string(test_port)},
        "auto_restart" => false,
        "max_restarts" => 0,
        "restart_window" => 60
      }

      config1 = Map.merge(config_base, %{"id" => "port_test_1", "name" => "Port Test 1"})
      config2 = Map.merge(config_base, %{"id" => "port_test_2", "name" => "Port Test 2"})

      # Add both
      assert :ok = ProcessManager.add_process(config1)
      assert :ok = ProcessManager.add_process(config2)

      # First should start
      assert :ok = ProcessManager.start_process("port_test_1")
      # Let it bind properly
      Process.sleep(500)

      # Second should fail due to port conflict
      # Give extra time for conflict detection to complete
      Process.sleep(100)
      result = ProcessManager.start_process("port_test_2")

      # Should either fail immediately or eventually fail due to port conflict
      case result do
        {:error, _reason} ->
          # Immediate failure - conflict detected upfront
          :ok

        :ok ->
          # Process started but should fail due to conflict, wait and verify it stops
          Process.sleep(200)
          assert {:ok, :stopped} = ProcessManager.get_process_status("port_test_2")
      end

      # Cleanup
      ProcessManager.stop_process("port_test_1")
      ProcessManager.remove_process("port_test_1")
      ProcessManager.remove_process("port_test_2")
    end
  end

  describe "process lifecycle robustness" do
    @tag :integration
    test "multiple start/stop cycles work reliably" do
      config = %{
        "id" => "lifecycle_test",
        "name" => "Lifecycle Test",
        "command" => "sleep",
        "args" => ["1"],
        "cwd" => nil,
        "env" => %{},
        "auto_restart" => false,
        "max_restarts" => 0,
        "restart_window" => 60
      }

      assert :ok = ProcessManager.add_process(config)

      # Test multiple cycles
      for _i <- 1..3 do
        assert :ok = ProcessManager.start_process("lifecycle_test")
        assert {:ok, :running} = ProcessManager.get_process_status("lifecycle_test")

        # Let it finish naturally
        Process.sleep(1200)
        assert {:ok, :stopped} = ProcessManager.get_process_status("lifecycle_test")
      end

      assert :ok = ProcessManager.remove_process("lifecycle_test")
    end
  end

  describe "list running processes with config" do
    @tag :integration
    test "returns running processes with their full configuration including health_check" do
      config_with_health_check = %{
        "id" => "test_with_health_check",
        "name" => "Test With Health Check",
        "command" => "sleep",
        "args" => ["3"],
        "cwd" => nil,
        "env" => %{},
        "auto_restart" => false,
        "max_restarts" => 0,
        "restart_window" => 60,
        "health_check" => %{
          "type" => "http",
          "url" => "http://localhost:8890/health",
          "interval" => 30,
          "timeout" => 10
        }
      }

      config_without_health_check = %{
        "id" => "test_without_health_check",
        "name" => "Test Without Health Check",
        "command" => "sleep",
        "args" => ["3"],
        "cwd" => nil,
        "env" => %{},
        "auto_restart" => false,
        "max_restarts" => 0,
        "restart_window" => 60
      }

      # Add both processes
      assert :ok = ProcessManager.add_process(config_with_health_check)
      assert :ok = ProcessManager.add_process(config_without_health_check)

      # Start both processes
      assert :ok = ProcessManager.start_process("test_with_health_check")
      assert :ok = ProcessManager.start_process("test_without_health_check")

      # Verify both are running
      assert {:ok, :running} = ProcessManager.get_process_status("test_with_health_check")
      assert {:ok, :running} = ProcessManager.get_process_status("test_without_health_check")

      # Get running processes with config
      running_processes = ProcessManager.list_running_processes_with_config()

      # Should have 2 running processes
      assert length(running_processes) == 2

      # Find our test processes
      process_with_health = Enum.find(running_processes, &(&1.id == "test_with_health_check"))

      process_without_health =
        Enum.find(running_processes, &(&1.id == "test_without_health_check"))

      # Verify structure and data
      assert process_with_health != nil
      assert process_with_health.name == "Test With Health Check"
      assert process_with_health.status == :running
      assert process_with_health.config.health_check != nil
      assert process_with_health.config.health_check["url"] == "http://localhost:8890/health"

      assert process_without_health != nil
      assert process_without_health.name == "Test Without Health Check"
      assert process_without_health.status == :running
      assert process_without_health.config.health_check == nil

      # Cleanup
      ProcessManager.stop_process("test_with_health_check")
      ProcessManager.stop_process("test_without_health_check")
      ProcessManager.remove_process("test_with_health_check")
      ProcessManager.remove_process("test_without_health_check")
    end

    @tag :integration
    test "returns empty list when no processes are running" do
      # Make sure no processes are running by stopping all
      all_processes = ProcessManager.list_processes()

      for process <- all_processes do
        ProcessManager.stop_process(process.id)
      end

      # Should return empty list
      running_processes = ProcessManager.list_running_processes_with_config()
      assert running_processes == []
    end
  end
end
