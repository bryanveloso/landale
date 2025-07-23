defmodule Server.CircuitBreakerServerTest do
  use ExUnit.Case, async: false

  alias Server.CircuitBreakerServer

  setup do
    # Start the CircuitBreakerServer for tests
    start_supervised!(Server.CircuitBreakerServer)

    # Ensure clean state before each test
    on_exit(fn ->
      # Only clean up if the process is still alive
      if Process.whereis(Server.CircuitBreakerServer) do
        try do
          CircuitBreakerServer.remove("test-service")
          CircuitBreakerServer.remove("failing-service")
        rescue
          _ -> :ok
        end
      end
    end)
  end

  describe "circuit breaker functionality" do
    test "successful calls keep circuit closed" do
      # Multiple successful calls
      for i <- 1..5 do
        assert {:ok, ^i} = CircuitBreakerServer.call("test-service", fn -> i end)
      end

      # Circuit should remain closed
      assert {:ok, :closed} = CircuitBreakerServer.get_state("test-service")
    end

    test "failures open the circuit after threshold" do
      config = %{failure_threshold: 3}

      # First two failures don't open circuit
      for i <- 1..2 do
        expected_message = "failure #{i}"

        assert {:error, %RuntimeError{message: ^expected_message}} =
                 CircuitBreakerServer.call(
                   "failing-service",
                   fn ->
                     raise expected_message
                   end,
                   config
                 )
      end

      # Circuit still closed
      assert {:ok, :closed} = CircuitBreakerServer.get_state("failing-service")

      # Third failure opens circuit
      assert {:error, %RuntimeError{message: "failure 3"}} =
               CircuitBreakerServer.call(
                 "failing-service",
                 fn ->
                   raise "failure 3"
                 end,
                 config
               )

      # Circuit now open
      assert {:ok, :open} = CircuitBreakerServer.get_state("failing-service")

      # Subsequent calls fail immediately
      assert {:error, :circuit_open} =
               CircuitBreakerServer.call(
                 "failing-service",
                 fn ->
                   :should_not_execute
                 end,
                 config
               )
    end

    test "circuit transitions to half-open after timeout" do
      config = %{failure_threshold: 1, timeout_ms: 100}

      # Open the circuit
      assert {:error, %RuntimeError{}} =
               CircuitBreakerServer.call(
                 "test-service",
                 fn ->
                   raise "error"
                 end,
                 config
               )

      assert {:ok, :open} = CircuitBreakerServer.get_state("test-service")

      # Wait for timeout
      Process.sleep(150)

      # Next call should attempt execution (half-open state)
      assert {:ok, :success} =
               CircuitBreakerServer.call(
                 "test-service",
                 fn ->
                   :success
                 end,
                 config
               )

      # Circuit should still be in half-open state after one successful call
      # (implementation may require multiple successful calls to fully close)
      state = CircuitBreakerServer.get_state("test-service")
      assert {:ok, circuit_state} = state
      assert circuit_state in [:closed, :half_open]
    end

    test "get_all_metrics returns circuit breaker information" do
      # Create a few circuit breakers
      CircuitBreakerServer.call("service-1", fn -> :ok end)
      CircuitBreakerServer.call("service-2", fn -> :ok end)

      metrics = CircuitBreakerServer.get_all_metrics()

      assert length(metrics) >= 2
      assert Enum.any?(metrics, &(&1.name == "service-1"))
      assert Enum.any?(metrics, &(&1.name == "service-2"))

      # Check metric structure
      service_1_metrics = Enum.find(metrics, &(&1.name == "service-1"))
      assert service_1_metrics.state == :closed
      assert service_1_metrics.failure_count == 0
      assert is_integer(service_1_metrics.uptime_ms)
    end

    test "remove deletes circuit breaker" do
      # Create circuit breaker
      CircuitBreakerServer.call("temp-service", fn -> :ok end)
      assert {:ok, :closed} = CircuitBreakerServer.get_state("temp-service")

      # Remove it
      assert :ok = CircuitBreakerServer.remove("temp-service")

      # Should no longer exist
      assert {:error, :not_found} = CircuitBreakerServer.get_state("temp-service")
    end
  end

  describe "error handling" do
    test "handles different error types" do
      # Runtime error
      assert {:error, %RuntimeError{}} =
               CircuitBreakerServer.call("test", fn -> raise "error" end)

      # Exit signal
      assert {:error, {:exit, :boom}} =
               CircuitBreakerServer.call("test", fn -> exit(:boom) end)

      # Throw
      assert {:error, {:throw, :ball}} =
               CircuitBreakerServer.call("test", fn -> throw(:ball) end)
    end
  end
end
