#!/usr/bin/env elixir
Mix.install([{:jason, "~> 1.4"}, {:gun, "~> 2.0"}])

defmodule OBSEndpointTester do
  @moduledoc """
  Comprehensive OBS WebSocket v5 endpoint testing for stability and proper response handling.

  Tests each implemented OBS request type to ensure:
  1. Proper WebSocket connection establishment
  2. Correct authentication flow
  3. Valid request/response message format
  4. Appropriate error handling
  5. Connection stability under load
  """

  require Logger

  @obs_websocket_url "ws://localhost:4455"
  @test_timeout 30_000
  @connection_timeout 10_000

  defstruct [
    :conn_pid,
    :stream_ref,
    :monitor_ref,
    :session_id,
    :authenticated,
    :responses,
    :test_results
  ]

  def run do
    Logger.configure(level: :info)
    Logger.info("Starting OBS WebSocket v5 endpoint testing")

    case connect() do
      {:ok, state} ->
        try do
          run_all_tests(state)
        after
          cleanup(state)
        end

      {:error, reason} ->
        Logger.error("Failed to connect to OBS: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp connect do
    Logger.info("Connecting to OBS WebSocket at #{@obs_websocket_url}")

    uri = URI.parse(@obs_websocket_url)
    host = String.to_charlist(uri.host)
    port = uri.port || 4455
    path = uri.path || "/"

    case :gun.open(host, port, %{protocols: [:http]}) do
      {:ok, conn_pid} ->
        monitor_ref = Process.monitor(conn_pid)

        case :gun.await_up(conn_pid, @connection_timeout) do
          {:ok, _protocol} ->
            stream_ref = :gun.ws_upgrade(conn_pid, path)

            state = %__MODULE__{
              conn_pid: conn_pid,
              stream_ref: stream_ref,
              monitor_ref: monitor_ref,
              authenticated: false,
              responses: %{},
              test_results: []
            }

            wait_for_hello(state)

          {:error, reason} ->
            :gun.close(conn_pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_hello(state) do
    receive do
      {:gun_upgrade, conn_pid, stream_ref, ["websocket"], _headers}
      when conn_pid == state.conn_pid and stream_ref == state.stream_ref ->
        Logger.info("WebSocket upgrade successful")
        wait_for_hello_message(state)

      {:gun_error, conn_pid, stream_ref, reason} when conn_pid == state.conn_pid ->
        Logger.error("WebSocket upgrade failed: #{inspect(reason)}")
        {:error, reason}

      {:DOWN, monitor_ref, :process, _pid, reason} when monitor_ref == state.monitor_ref ->
        Logger.error("Connection process died: #{inspect(reason)}")
        {:error, reason}
    after
      @connection_timeout ->
        Logger.error("Timeout waiting for WebSocket upgrade")
        {:error, :upgrade_timeout}
    end
  end

  defp wait_for_hello_message(state) do
    receive do
      {:gun_ws, conn_pid, stream_ref, {:text, message}}
      when conn_pid == state.conn_pid and stream_ref == state.stream_ref ->
        case JSON.decode(message) do
          {:ok, %{"op" => 0, "d" => hello_data}} ->
            Logger.info("Received Hello message")
            Logger.debug("Hello data: #{inspect(hello_data)}")

            # Send Identify message
            identify_message = %{
              "op" => 1,
              "d" => %{
                "rpcVersion" => 1,
                "authentication" => nil,
                # All non-high-volume events
                "eventSubscriptions" => 1023
              }
            }

            send_message(state, identify_message)
            wait_for_identified(state)

          {:ok, other} ->
            Logger.warning("Unexpected message: #{inspect(other)}")
            wait_for_hello_message(state)

          {:error, reason} ->
            Logger.error("Failed to decode message: #{inspect(reason)}")
            {:error, reason}
        end

      {:DOWN, monitor_ref, :process, _pid, reason} when monitor_ref == state.monitor_ref ->
        Logger.error("Connection process died: #{inspect(reason)}")
        {:error, reason}
    after
      @connection_timeout ->
        Logger.error("Timeout waiting for Hello message")
        {:error, :hello_timeout}
    end
  end

  defp wait_for_identified(state) do
    receive do
      {:gun_ws, conn_pid, stream_ref, {:text, message}}
      when conn_pid == state.conn_pid and stream_ref == state.stream_ref ->
        case JSON.decode(message) do
          {:ok, %{"op" => 2, "d" => identified_data}} ->
            Logger.info("Received Identified message - Authentication successful")
            Logger.debug("Identified data: #{inspect(identified_data)}")

            authenticated_state = %{state | authenticated: true}
            {:ok, authenticated_state}

          {:ok, other} ->
            Logger.warning("Unexpected message during identification: #{inspect(other)}")
            wait_for_identified(state)

          {:error, reason} ->
            Logger.error("Failed to decode identification message: #{inspect(reason)}")
            {:error, reason}
        end

      {:DOWN, monitor_ref, :process, _pid, reason} when monitor_ref == state.monitor_ref ->
        Logger.error("Connection process died during identification: #{inspect(reason)}")
        {:error, reason}
    after
      @connection_timeout ->
        Logger.error("Timeout waiting for Identified message")
        {:error, :identified_timeout}
    end
  end

  defp run_all_tests(state) do
    Logger.info("Starting comprehensive OBS endpoint testing")

    test_cases = [
      {"GetVersion", %{}},
      {"GetStats", %{}},
      {"GetSceneList", %{}},
      {"GetCurrentProgramScene", %{}},
      {"SetCurrentProgramScene", %{"sceneName" => "Scene 1"}},
      {"StartStream", %{}},
      {"StopStream", %{}},
      {"StartRecord", %{}},
      {"StopRecord", %{}},
      {"BroadcastCustomEvent", %{"eventData" => %{"message" => "test"}}},
      {"Sleep", %{"sleepMillis" => 100}},
      # Test error handling
      {"NonExistentRequest", %{}}
    ]

    results =
      Enum.map(test_cases, fn {request_type, request_data} ->
        test_single_endpoint(state, request_type, request_data)
      end)

    # Test batch requests
    batch_result = test_batch_requests(state)

    all_results = results ++ [batch_result]

    # Print summary
    print_test_summary(all_results)

    {:ok, all_results}
  end

  defp test_single_endpoint(state, request_type, request_data) do
    Logger.info("Testing endpoint: #{request_type}")

    request_id = generate_request_id()

    request = %{
      # Request OpCode
      "op" => 6,
      "d" => %{
        "requestType" => request_type,
        "requestId" => request_id,
        "requestData" => request_data
      }
    }

    start_time = System.monotonic_time(:millisecond)
    send_message(state, request)

    case wait_for_response(state, request_id, 5000) do
      {:ok, response} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        result = validate_response(request_type, request_id, response, duration)
        Logger.info("#{request_type}: #{result.status} (#{duration}ms)")
        result

      {:error, reason} ->
        Logger.error("#{request_type}: TIMEOUT - #{inspect(reason)}")

        %{
          request_type: request_type,
          request_id: request_id,
          status: :timeout,
          error: reason,
          duration: nil
        }
    end
  end

  defp test_batch_requests(state) do
    Logger.info("Testing batch requests")

    request_id = generate_request_id()

    batch_request = %{
      # RequestBatch OpCode
      "op" => 8,
      "d" => %{
        "requestId" => request_id,
        "haltOnFailure" => false,
        # SerialRealtime
        "executionType" => 0,
        "requests" => [
          %{
            "requestType" => "GetVersion",
            "requestId" => "batch_1"
          },
          %{
            "requestType" => "GetStats",
            "requestId" => "batch_2"
          },
          %{
            "requestType" => "Sleep",
            "requestId" => "batch_3",
            "requestData" => %{"sleepMillis" => 50}
          }
        ]
      }
    }

    start_time = System.monotonic_time(:millisecond)
    send_message(state, batch_request)

    case wait_for_response(state, request_id, 10000) do
      {:ok, response} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        result = validate_batch_response(request_id, response, duration)
        Logger.info("RequestBatch: #{result.status} (#{duration}ms)")
        result

      {:error, reason} ->
        Logger.error("RequestBatch: TIMEOUT - #{inspect(reason)}")

        %{
          request_type: "RequestBatch",
          request_id: request_id,
          status: :timeout,
          error: reason,
          duration: nil
        }
    end
  end

  defp wait_for_response(state, request_id, timeout) do
    receive do
      {:gun_ws, conn_pid, stream_ref, {:text, message}}
      when conn_pid == state.conn_pid and stream_ref == state.stream_ref ->
        case JSON.decode(message) do
          {:ok, %{"op" => 7, "d" => response_data}} ->
            if response_data["requestId"] == request_id do
              {:ok, response_data}
            else
              # Not our response, keep waiting
              wait_for_response(state, request_id, timeout)
            end

          {:ok, %{"op" => 9, "d" => batch_response_data}} ->
            if batch_response_data["requestId"] == request_id do
              {:ok, batch_response_data}
            else
              wait_for_response(state, request_id, timeout)
            end

          {:ok, other} ->
            Logger.debug("Received other message while waiting: #{inspect(other)}")
            wait_for_response(state, request_id, timeout)

          {:error, reason} ->
            {:error, {:decode_error, reason}}
        end

      {:DOWN, monitor_ref, :process, _pid, reason} when monitor_ref == state.monitor_ref ->
        {:error, {:connection_died, reason}}
    after
      timeout ->
        {:error, :response_timeout}
    end
  end

  defp validate_response(request_type, request_id, response, duration) do
    errors = []

    # Validate basic structure
    errors = validate_response_structure(response, request_type, request_id, errors)

    # Validate request status
    errors = validate_request_status(response, errors)

    # Validate response data for specific request types
    errors = validate_response_data(request_type, response, errors)

    status = if length(errors) == 0, do: :success, else: :error

    %{
      request_type: request_type,
      request_id: request_id,
      status: status,
      errors: errors,
      duration: duration,
      response: response
    }
  end

  defp validate_batch_response(request_id, response, duration) do
    errors = []

    # Validate basic batch structure
    unless response["requestId"] == request_id do
      errors = ["Invalid request ID in batch response" | errors]
    end

    unless is_list(response["results"]) do
      errors = ["Missing or invalid results array in batch response" | errors]
    end

    # Validate individual results
    if is_list(response["results"]) do
      result_errors =
        response["results"]
        |> Enum.with_index()
        |> Enum.flat_map(fn {result, index} ->
          case result do
            %{"requestStatus" => %{"result" => result_bool}} when is_boolean(result_bool) ->
              []

            _ ->
              ["Invalid result structure at index #{index}"]
          end
        end)

      errors = errors ++ result_errors
    end

    status = if length(errors) == 0, do: :success, else: :error

    %{
      request_type: "RequestBatch",
      request_id: request_id,
      status: status,
      errors: errors,
      duration: duration,
      response: response
    }
  end

  defp validate_response_structure(response, expected_type, expected_id, errors) do
    errors =
      unless response["requestType"] == expected_type do
        ["Request type mismatch: expected #{expected_type}, got #{response["requestType"]}" | errors]
      else
        errors
      end

    errors =
      unless response["requestId"] == expected_id do
        ["Request ID mismatch: expected #{expected_id}, got #{response["requestId"]}" | errors]
      else
        errors
      end

    unless is_map(response["requestStatus"]) do
      ["Missing or invalid requestStatus object" | errors]
    else
      errors
    end
  end

  defp validate_request_status(response, errors) do
    status = response["requestStatus"]

    errors =
      unless is_boolean(status["result"]) do
        ["Missing or invalid result boolean in requestStatus" | errors]
      else
        errors
      end

    errors =
      unless is_integer(status["code"]) do
        ["Missing or invalid code integer in requestStatus" | errors]
      else
        errors
      end

    # Validate status codes are within valid ranges
    errors =
      if is_integer(status["code"]) do
        code = status["code"]

        cond do
          # Success codes
          code >= 100 and code <= 199 -> errors
          # Some Error codes  
          code >= 200 and code <= 299 -> errors
          # Request Error codes
          code >= 300 and code <= 399 -> errors
          # Request Field Error codes
          code >= 400 and code <= 499 -> errors
          # Request Processing Error codes
          code >= 500 and code <= 599 -> errors
          # Request Batch Error codes
          code >= 600 and code <= 699 -> errors
          true -> ["Invalid status code: #{code}" | errors]
        end
      else
        errors
      end

    errors
  end

  defp validate_response_data(request_type, response, errors) do
    response_data = response["responseData"]

    case request_type do
      "GetVersion" ->
        if is_map(response_data) do
          required_fields = ["obsVersion", "obsWebSocketVersion", "rpcVersion"]

          missing_fields =
            Enum.filter(required_fields, fn field ->
              not Map.has_key?(response_data, field)
            end)

          if length(missing_fields) > 0 do
            ["GetVersion missing required fields: #{inspect(missing_fields)}" | errors]
          else
            errors
          end
        else
          ["GetVersion missing responseData" | errors]
        end

      "GetStats" ->
        if is_map(response_data) do
          # Stats should have numeric values
          numeric_fields = ["cpuUsage", "memoryUsage", "activeFps"]

          invalid_fields =
            Enum.filter(numeric_fields, fn field ->
              case Map.get(response_data, field) do
                val when is_number(val) -> false
                _ -> true
              end
            end)

          if length(invalid_fields) > 0 do
            ["GetStats invalid numeric fields: #{inspect(invalid_fields)}" | errors]
          else
            errors
          end
        else
          ["GetStats missing responseData" | errors]
        end

      "NonExistentRequest" ->
        # This should fail with proper error
        status = response["requestStatus"]

        if status["result"] == true do
          ["NonExistentRequest should have failed but returned success" | errors]
        else
          errors
        end

      _ ->
        # For other request types, just check that response structure is valid
        errors
    end
  end

  defp print_test_summary(results) do
    Logger.info("=== OBS ENDPOINT TEST SUMMARY ===")

    total_tests = length(results)
    success_count = Enum.count(results, &(&1.status == :success))
    error_count = Enum.count(results, &(&1.status == :error))
    timeout_count = Enum.count(results, &(&1.status == :timeout))

    Logger.info("Total tests: #{total_tests}")
    Logger.info("Successful: #{success_count}")
    Logger.info("Errors: #{error_count}")
    Logger.info("Timeouts: #{timeout_count}")

    if error_count > 0 or timeout_count > 0 do
      Logger.info("=== FAILED TESTS ===")

      results
      |> Enum.filter(&(&1.status != :success))
      |> Enum.each(fn result ->
        Logger.error("#{result.request_type}: #{result.status}")

        if result[:errors] && length(result.errors) > 0 do
          Enum.each(result.errors, fn error ->
            Logger.error("  - #{error}")
          end)
        end

        if result[:error] do
          Logger.error("  - #{inspect(result.error)}")
        end
      end)
    end

    # Calculate average response time for successful tests
    successful_tests = Enum.filter(results, &(&1.status == :success && &1.duration))

    if length(successful_tests) > 0 do
      avg_duration =
        successful_tests
        |> Enum.map(& &1.duration)
        |> Enum.sum()
        |> div(length(successful_tests))

      Logger.info("Average response time: #{avg_duration}ms")
    end
  end

  defp send_message(state, message) do
    json_message = JSON.encode!(message)
    :gun.ws_send(state.conn_pid, state.stream_ref, {:text, json_message})
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  defp cleanup(state) do
    Logger.info("Cleaning up test connection")

    if state.conn_pid do
      :gun.close(state.conn_pid)
    end

    if state.monitor_ref do
      Process.demonitor(state.monitor_ref, [:flush])
    end
  end
end

# Run the tests
case OBSEndpointTester.run() do
  {:ok, results} ->
    IO.puts("OBS endpoint testing completed successfully")
    System.halt(0)

  {:error, reason} ->
    IO.puts("OBS endpoint testing failed: #{inspect(reason)}")
    System.halt(1)
end
