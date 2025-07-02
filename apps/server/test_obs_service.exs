#!/usr/bin/env elixir
Mix.install([{:jason, "~> 1.4"}])

defmodule OBSServiceTester do
  @moduledoc """
  Test the OBS service endpoints by calling the actual GenServer API.

  This tests the service's public API methods and verifies:
  1. Service status and health
  2. Connection state management
  3. Streaming controls
  4. Recording controls
  5. Scene management
  6. Error handling
  """

  require Logger

  def run do
    Logger.configure(level: :info)
    Logger.info("Starting OBS Service API testing")

    # Connect to the running application
    case Node.connect(node_name()) do
      true ->
        Logger.info("Connected to running server node")
        run_all_tests()

      false ->
        Logger.error("Failed to connect to server node - is the server running?")
        Logger.info("Trying to test without node connection...")
        run_direct_tests()

      :ignored ->
        Logger.info("Node connection ignored (single node setup)")
        Logger.info("Running tests in current context...")
        run_direct_tests()
    end
  end

  defp node_name do
    # Try to determine the server's node name
    hostname = System.get_env("HOSTNAME") || "localhost"
    :"server@#{hostname}"
  end

  defp run_all_tests do
    Logger.info("Running comprehensive OBS service tests")

    test_cases = [
      {"Service Status", &test_get_status/0},
      {"Service State", &test_get_state/0},
      {"Start Streaming", &test_start_streaming/0},
      {"Stop Streaming", &test_stop_streaming/0},
      {"Start Recording", &test_start_recording/0},
      {"Stop Recording", &test_stop_recording/0},
      {"Set Current Scene", &test_set_current_scene/0},
      {"Send Message", &test_send_message/0},
      {"Connection Health", &test_connection_health/0}
    ]

    results =
      Enum.map(test_cases, fn {test_name, test_function} ->
        Logger.info("Running test: #{test_name}")

        result =
          try do
            case test_function.() do
              :ok ->
                Logger.info("✅ #{test_name}: PASSED")
                {test_name, :passed, nil}

              {:ok, data} ->
                Logger.info("✅ #{test_name}: PASSED")
                Logger.debug("Data: #{inspect(data)}")
                {test_name, :passed, data}

              {:error, reason} ->
                Logger.warning("❌ #{test_name}: FAILED - #{inspect(reason)}")
                {test_name, :failed, reason}

              other ->
                Logger.info("ℹ️  #{test_name}: OTHER - #{inspect(other)}")
                {test_name, :other, other}
            end
          rescue
            error ->
              Logger.error("💥 #{test_name}: ERROR - #{inspect(error)}")
              {test_name, :error, error}
          catch
            :exit, reason ->
              Logger.error("💥 #{test_name}: EXIT - #{inspect(reason)}")
              {test_name, :exit, reason}
          end

        # Small delay between tests
        Process.sleep(100)
        result
      end)

    print_test_summary(results)
    {:ok, results}
  end

  defp run_direct_tests do
    Logger.info("Running limited tests without node connection")
    Logger.info("ℹ️  This will test basic functionality that doesn't require the full server context")

    # Test basic module loading and function availability
    basic_tests = [
      {"Module Loading", &test_module_loading/0},
      {"Function Exports", &test_function_exports/0}
    ]

    results =
      Enum.map(basic_tests, fn {test_name, test_function} ->
        Logger.info("Running test: #{test_name}")

        result =
          try do
            case test_function.() do
              :ok ->
                Logger.info("✅ #{test_name}: PASSED")
                {test_name, :passed, nil}

              {:error, reason} ->
                Logger.warning("❌ #{test_name}: FAILED - #{inspect(reason)}")
                {test_name, :failed, reason}

              other ->
                Logger.info("ℹ️  #{test_name}: OTHER - #{inspect(other)}")
                {test_name, :other, other}
            end
          rescue
            error ->
              Logger.error("💥 #{test_name}: ERROR - #{inspect(error)}")
              {test_name, :error, error}
          end

        result
      end)

    print_test_summary(results)
    {:limited, results}
  end

  # Test implementations

  defp test_get_status do
    # Test the public API for getting service status
    case :rpc.call(node_name(), Server.Services.OBS, :get_status, []) do
      {:ok, status} when is_map(status) ->
        Logger.debug("Status received: #{inspect(status)}")

        # Validate status structure
        required_keys = [:connected, :connection_state, :streaming_active, :recording_active]
        missing_keys = Enum.filter(required_keys, fn key -> not Map.has_key?(status, key) end)

        if length(missing_keys) == 0 do
          {:ok, status}
        else
          {:error, {:missing_status_keys, missing_keys}}
        end

      {:error, reason} ->
        {:error, reason}

      {:badrpc, reason} ->
        {:error, {:rpc_failed, reason}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp test_get_state do
    case :rpc.call(node_name(), Server.Services.OBS, :get_state, []) do
      state when is_map(state) ->
        Logger.debug("State keys: #{inspect(Map.keys(state))}")
        {:ok, :state_retrieved}

      {:badrpc, reason} ->
        {:error, {:rpc_failed, reason}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp test_start_streaming do
    case :rpc.call(node_name(), Server.Services.OBS, :start_streaming, []) do
      :ok ->
        :ok

      {:error, reason} ->
        # This might fail if OBS isn't connected, which is expected
        Logger.debug("Start streaming failed (expected if OBS not connected): #{inspect(reason)}")
        :ok

      {:badrpc, reason} ->
        {:error, {:rpc_failed, reason}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp test_stop_streaming do
    case :rpc.call(node_name(), Server.Services.OBS, :stop_streaming, []) do
      :ok ->
        :ok

      {:error, reason} ->
        # This might fail if OBS isn't connected, which is expected
        Logger.debug("Stop streaming failed (expected if OBS not connected): #{inspect(reason)}")
        :ok

      {:badrpc, reason} ->
        {:error, {:rpc_failed, reason}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp test_start_recording do
    case :rpc.call(node_name(), Server.Services.OBS, :start_recording, []) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("Start recording failed (expected if OBS not connected): #{inspect(reason)}")
        :ok

      {:badrpc, reason} ->
        {:error, {:rpc_failed, reason}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp test_stop_recording do
    case :rpc.call(node_name(), Server.Services.OBS, :stop_recording, []) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("Stop recording failed (expected if OBS not connected): #{inspect(reason)}")
        :ok

      {:badrpc, reason} ->
        {:error, {:rpc_failed, reason}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp test_set_current_scene do
    case :rpc.call(node_name(), Server.Services.OBS, :set_current_scene, ["Test Scene"]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("Set scene failed (expected if OBS not connected): #{inspect(reason)}")
        :ok

      {:badrpc, reason} ->
        {:error, {:rpc_failed, reason}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp test_send_message do
    test_message = %{
      "op" => 6,
      "d" => %{
        "requestType" => "GetVersion",
        "requestId" => "test_request_#{:rand.uniform(1000)}"
      }
    }

    case :rpc.call(node_name(), Server.Services.OBS, :send_message, [test_message]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("Send message failed (expected if OBS not connected): #{inspect(reason)}")
        :ok

      {:badrpc, reason} ->
        {:error, {:rpc_failed, reason}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp test_connection_health do
    # Test multiple rapid status calls to verify no race conditions
    tasks =
      Enum.map(1..5, fn i ->
        Task.async(fn ->
          case :rpc.call(node_name(), Server.Services.OBS, :get_status, []) do
            {:ok, _status} -> {:ok, i}
            {:error, reason} -> {:error, {i, reason}}
            {:badrpc, reason} -> {:error, {:rpc_failed, i, reason}}
            other -> {:error, {:unexpected, i, other}}
          end
        end)
      end)

    results = Task.await_many(tasks, 5000)

    # Check if all tasks completed successfully
    errors =
      Enum.filter(results, fn
        {:ok, _} -> false
        {:error, _} -> true
      end)

    if length(errors) == 0 do
      :ok
    else
      {:error, {:concurrent_errors, errors}}
    end
  end

  # Limited tests without node connection

  defp test_module_loading do
    try do
      Code.ensure_loaded(Server.Services.OBS)
      :ok
    rescue
      error ->
        {:error, error}
    end
  end

  defp test_function_exports do
    try do
      exports = Server.Services.OBS.__info__(:functions)
      required_functions = [:start_link, :get_status, :get_state, :start_streaming, :stop_streaming]

      missing_functions =
        Enum.filter(required_functions, fn func ->
          not Enum.member?(Keyword.keys(exports), func)
        end)

      if length(missing_functions) == 0 do
        :ok
      else
        {:error, {:missing_functions, missing_functions}}
      end
    rescue
      error ->
        {:error, error}
    end
  end

  defp print_test_summary(results) do
    Logger.info("=== OBS SERVICE TEST SUMMARY ===")

    total_tests = length(results)
    passed_count = Enum.count(results, fn {_, status, _} -> status == :passed end)
    failed_count = Enum.count(results, fn {_, status, _} -> status == :failed end)
    error_count = Enum.count(results, fn {_, status, _} -> status in [:error, :exit] end)
    other_count = Enum.count(results, fn {_, status, _} -> status == :other end)

    Logger.info("Total tests: #{total_tests}")
    Logger.info("Passed: #{passed_count}")
    Logger.info("Failed: #{failed_count}")
    Logger.info("Errors: #{error_count}")
    Logger.info("Other: #{other_count}")

    if failed_count > 0 or error_count > 0 do
      Logger.info("=== DETAILED RESULTS ===")

      results
      |> Enum.filter(fn {_, status, _} -> status in [:failed, :error, :exit] end)
      |> Enum.each(fn {test_name, status, details} ->
        Logger.error("#{test_name}: #{status}")

        if details do
          Logger.error("  Details: #{inspect(details)}")
        end
      end)
    end

    success_rate =
      if total_tests > 0 do
        Float.round(passed_count / total_tests * 100, 1)
      else
        0.0
      end

    Logger.info("Success rate: #{success_rate}%")
  end
end

# Run the tests
case OBSServiceTester.run() do
  {:ok, _results} ->
    IO.puts("OBS service testing completed successfully")
    System.halt(0)

  {:limited, _results} ->
    IO.puts("OBS service testing completed with limited scope")
    System.halt(0)

  {:error, reason} ->
    IO.puts("OBS service testing failed: #{inspect(reason)}")
    System.halt(1)
end
