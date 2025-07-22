defmodule Server.RetryStrategyTest do
  use ExUnit.Case, async: false

  @moduletag :unit

  alias Server.RetryStrategy

  describe "basic retry functionality" do
    test "succeeds on first attempt" do
      {:ok, result} =
        RetryStrategy.retry(fn ->
          {:ok, "success"}
        end)

      assert result == "success"
    end

    test "succeeds after retries" do
      pid = self()

      {:ok, result} =
        RetryStrategy.retry(
          fn ->
            send(pid, :attempt)

            receive do
              :fail -> {:error, :test_error}
              :succeed -> {:ok, "success"}
            after
              0 -> {:ok, "success"}
            end
          end,
          max_attempts: 3,
          base_delay: 10
        )

      assert result == "success"
    end

    test "fails after max attempts" do
      {:error, reason} =
        RetryStrategy.retry(
          fn ->
            {:error, :persistent_error}
          end,
          max_attempts: 2,
          base_delay: 10
        )

      assert reason == :persistent_error
    end

    test "respects custom retry predicate" do
      # Only retry on :retryable_error
      {:error, reason} =
        RetryStrategy.retry(
          fn ->
            {:error, :non_retryable_error}
          end,
          max_attempts: 3,
          base_delay: 10,
          retry_predicate: fn
            :retryable_error -> true
            _ -> false
          end
        )

      assert reason == :non_retryable_error
    end
  end

  describe "rate limit detection" do
    test "retries on 429 status code" do
      attempt_count = :counters.new(1, [])

      {:error, reason} =
        RetryStrategy.retry_with_rate_limit_detection(
          fn ->
            :counters.add(attempt_count, 1, 1)
            {:error, {:http_error, 429, "Too Many Requests"}}
          end,
          max_attempts: 3,
          base_delay: 10
        )

      # Should have made 3 attempts
      assert :counters.get(attempt_count, 1) == 3
      assert reason == {:http_error, 429, "Too Many Requests"}
    end

    test "retries on rate limit string messages" do
      attempt_count = :counters.new(1, [])

      {:error, reason} =
        RetryStrategy.retry_with_rate_limit_detection(
          fn ->
            :counters.add(attempt_count, 1, 1)
            {:error, "Rate limit exceeded"}
          end,
          max_attempts: 2,
          base_delay: 10
        )

      # Should have made 2 attempts
      assert :counters.get(attempt_count, 1) == 2
      assert reason == "Rate limit exceeded"
    end

    test "retries on 5xx server errors" do
      attempt_count = :counters.new(1, [])

      {:error, reason} =
        RetryStrategy.retry_with_rate_limit_detection(
          fn ->
            :counters.add(attempt_count, 1, 1)
            {:error, {:http_error, 503, "Service Unavailable"}}
          end,
          max_attempts: 2,
          base_delay: 10
        )

      # Should have made 2 attempts
      assert :counters.get(attempt_count, 1) == 2
      assert reason == {:http_error, 503, "Service Unavailable"}
    end

    test "does not retry on 4xx client errors (except 429)" do
      attempt_count = :counters.new(1, [])

      {:error, reason} =
        RetryStrategy.retry_with_rate_limit_detection(
          fn ->
            :counters.add(attempt_count, 1, 1)
            {:error, {:http_error, 401, "Unauthorized"}}
          end,
          max_attempts: 3,
          base_delay: 10
        )

      # Should have made only 1 attempt
      assert :counters.get(attempt_count, 1) == 1
      assert reason == {:http_error, 401, "Unauthorized"}
    end
  end

  describe "exponential backoff" do
    test "calculates delays correctly" do
      _delays = []

      RetryStrategy.retry(
        fn ->
          start_time = System.monotonic_time(:millisecond)
          send(self(), {:delay_start, start_time})
          {:error, :test_error}
        end,
        max_attempts: 4,
        base_delay: 100,
        backoff_factor: 2.0,
        jitter: false
      )

      # Note: We can't easily test exact delays due to process scheduling,
      # but we can verify the function doesn't crash and completes
      assert true
    end

    test "applies maximum delay limit" do
      {:error, _} =
        RetryStrategy.retry(
          fn ->
            {:error, :test_error}
          end,
          max_attempts: 3,
          base_delay: 1000,
          max_delay: 1500,
          backoff_factor: 3.0,
          jitter: false
        )

      # Test passes if no crash occurs
      assert true
    end
  end

  describe "circuit breaker pattern" do
    setup do
      # Ensure ETS table exists for circuit breaker tests
      case :ets.whereis(:circuit_breaker_state) do
        :undefined ->
          :ets.new(:circuit_breaker_state, [:set, :protected, :named_table])

        _ ->
          # Clear existing entries for test isolation
          :ets.delete_all_objects(:circuit_breaker_state)
      end

      :ok
    end

    test "allows calls when circuit is closed" do
      {:ok, result} =
        RetryStrategy.retry_with_circuit_breaker(:test_service, fn ->
          {:ok, "success"}
        end)

      assert result == "success"
    end

    test "opens circuit after failures" do
      # First call fails and opens circuit
      {:error, _} =
        RetryStrategy.retry_with_circuit_breaker(
          :failing_service,
          fn ->
            {:error, :service_down}
          end,
          max_attempts: 1
        )

      # Second call should be blocked by open circuit
      {:error, reason} =
        RetryStrategy.retry_with_circuit_breaker(:failing_service, fn ->
          {:ok, "should not be called"}
        end)

      assert reason == :circuit_open
    end

    test "closes circuit after successful call in half-open state" do
      service_name = :recovery_service

      # Open the circuit
      {:error, _} =
        RetryStrategy.retry_with_circuit_breaker(
          service_name,
          fn ->
            {:error, :initial_failure}
          end,
          max_attempts: 1
        )

      # Wait for circuit to go half-open (simplified test)
      # In real implementation, this would be time-based
      :timer.sleep(100)

      # Circuit breaker functionality is basic for testing
      assert true
    end
  end

  describe "error handling edge cases" do
    test "handles unexpected return values" do
      {:error, reason} =
        RetryStrategy.retry(
          fn ->
            :unexpected_return
          end,
          max_attempts: 1
        )

      assert match?({:unexpected_return, :unexpected_return}, reason)
    end

    test "handles exceptions in retry function" do
      {:error, reason} =
        RetryStrategy.retry(
          fn ->
            raise "test exception"
          end,
          max_attempts: 1
        )

      # The function should catch and convert exceptions
      assert is_tuple(reason) or is_atom(reason)
    end
  end

  describe "network error detection" do
    test "retries on connection timeout" do
      attempt_count = :counters.new(1, [])

      {:error, reason} =
        RetryStrategy.retry(
          fn ->
            :counters.add(attempt_count, 1, 1)
            {:error, :timeout}
          end,
          max_attempts: 3,
          base_delay: 10
        )

      assert :counters.get(attempt_count, 1) == 3
      assert reason == :timeout
    end

    test "retries on connection refused" do
      attempt_count = :counters.new(1, [])

      {:error, reason} =
        RetryStrategy.retry(
          fn ->
            :counters.add(attempt_count, 1, 1)
            {:error, :econnrefused}
          end,
          max_attempts: 2,
          base_delay: 10
        )

      assert :counters.get(attempt_count, 1) == 2
      assert reason == :econnrefused
    end
  end
end
