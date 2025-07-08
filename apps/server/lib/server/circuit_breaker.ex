defmodule Server.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern implementation for external service calls.

  Prevents cascading failures by temporarily blocking calls to failing services
  and providing fast failure responses. Automatically attempts to restore service
  when the failure threshold reset period expires.

  ## States

  - `:closed` - Normal operation, all requests are allowed
  - `:open` - Service is failing, all requests fail fast 
  - `:half_open` - Testing service recovery, limited requests allowed

  ## Configuration

  - `:failure_threshold` - Number of failures before opening circuit (default: 5)
  - `:timeout_ms` - Time circuit stays open before attempting recovery (default: 60_000)
  - `:reset_timeout_ms` - Time to wait for recovery in half-open state (default: 30_000)

  ## Usage

      # Create circuit breaker for a service
      circuit_breaker = CircuitBreaker.new("twitch-api", %{
        failure_threshold: 3,
        timeout_ms: 30_000
      })

      # Execute function with circuit breaker protection
      case CircuitBreaker.call(circuit_breaker, fn ->
        :gun.get(conn, "/api/endpoint")
      end) do
        {:ok, result} -> 
          # Success
        {:error, :circuit_open} ->
          # Circuit is open, service unavailable
        {:error, reason} ->
          # Function failed, circuit may open soon
      end
  """

  require Logger

  @default_config %{
    failure_threshold: 5,
    timeout_ms: 60_000,
    reset_timeout_ms: 30_000,
    success_threshold: 2
  }

  defstruct [
    :name,
    :config,
    :state,
    :failure_count,
    :last_failure_time,
    :half_open_success_count,
    :state_changed_at
  ]

  @type circuit_state :: :closed | :open | :half_open
  @type result :: {:ok, any()} | {:error, any()}

  ## Public API

  @doc """
  Creates a new circuit breaker with the given name and configuration.
  """
  def new(name, config \\ %{}) do
    full_config = Map.merge(@default_config, config)

    %__MODULE__{
      name: name,
      config: full_config,
      state: :closed,
      failure_count: 0,
      last_failure_time: nil,
      half_open_success_count: 0,
      state_changed_at: DateTime.utc_now()
    }
  end

  @doc """
  Executes a function with circuit breaker protection.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
  If the circuit is open, returns `{:error, :circuit_open}` without executing the function.
  """
  def call(%__MODULE__{} = circuit_breaker, fun) when is_function(fun, 0) do
    case can_execute?(circuit_breaker) do
      {:ok, updated_circuit} ->
        execute_with_protection(updated_circuit, fun)

      {:error, :circuit_open} = error ->
        log_circuit_blocked(circuit_breaker)
        error
    end
  end

  @doc """
  Gets the current state of the circuit breaker.
  """
  def get_state(%__MODULE__{state: state}), do: state

  @doc """
  Gets circuit breaker metrics for monitoring.
  """
  def get_metrics(%__MODULE__{} = circuit_breaker) do
    %{
      name: circuit_breaker.name,
      state: circuit_breaker.state,
      failure_count: circuit_breaker.failure_count,
      last_failure_time: circuit_breaker.last_failure_time,
      state_changed_at: circuit_breaker.state_changed_at,
      uptime_ms: uptime_ms(circuit_breaker)
    }
  end

  ## Private Implementation

  defp can_execute?(%__MODULE__{state: :closed} = circuit_breaker) do
    {:ok, circuit_breaker}
  end

  defp can_execute?(%__MODULE__{state: :half_open} = circuit_breaker) do
    {:ok, circuit_breaker}
  end

  defp can_execute?(%__MODULE__{state: :open} = circuit_breaker) do
    if should_attempt_reset?(circuit_breaker) do
      new_circuit = transition_to_half_open(circuit_breaker)
      {:ok, new_circuit}
    else
      {:error, :circuit_open}
    end
  end

  defp execute_with_protection(circuit_breaker, fun) do
    try do
      result = fun.()
      handle_success(circuit_breaker, result)
    rescue
      error ->
        handle_failure(circuit_breaker, {:error, error})
    catch
      :exit, reason ->
        handle_failure(circuit_breaker, {:error, {:exit, reason}})

      :throw, value ->
        handle_failure(circuit_breaker, {:error, {:throw, value}})
    end
  end

  defp handle_success(circuit_breaker, result) do
    case circuit_breaker.state do
      :closed ->
        # Reset failure count on success
        updated_circuit = %{circuit_breaker | failure_count: 0}
        log_success(updated_circuit)
        {:ok, result}

      :half_open ->
        # Track successes in half-open state
        new_success_count = circuit_breaker.half_open_success_count + 1

        if new_success_count >= circuit_breaker.config.success_threshold do
          # Enough successes, close the circuit
          updated_circuit = transition_to_closed(circuit_breaker)
          log_circuit_closed(updated_circuit)
          {:ok, result}
        else
          # Continue in half-open state
          _updated_circuit = %{circuit_breaker | half_open_success_count: new_success_count}
          {:ok, result}
        end

      :open ->
        # This shouldn't happen, but handle gracefully
        {:ok, result}
    end
  end

  defp handle_failure(circuit_breaker, error) do
    new_failure_count = circuit_breaker.failure_count + 1
    now = DateTime.utc_now()

    updated_circuit = %{circuit_breaker | failure_count: new_failure_count, last_failure_time: now}

    # Check if we should open the circuit
    if new_failure_count >= circuit_breaker.config.failure_threshold do
      final_circuit = transition_to_open(updated_circuit)
      log_circuit_opened(final_circuit, error)
      error
    else
      log_failure(updated_circuit, error)
      error
    end
  end

  defp should_attempt_reset?(%__MODULE__{state: :open} = circuit_breaker) do
    if circuit_breaker.last_failure_time do
      elapsed_ms = DateTime.diff(DateTime.utc_now(), circuit_breaker.last_failure_time, :millisecond)
      elapsed_ms >= circuit_breaker.config.timeout_ms
    else
      false
    end
  end

  defp transition_to_open(circuit_breaker) do
    now = DateTime.utc_now()

    # Emit telemetry
    :telemetry.execute(
      [:circuit_breaker, :state_change],
      %{count: 1},
      %{
        name: circuit_breaker.name,
        from_state: circuit_breaker.state,
        to_state: :open,
        failure_count: circuit_breaker.failure_count
      }
    )

    %{circuit_breaker | state: :open, state_changed_at: now}
  end

  defp transition_to_half_open(circuit_breaker) do
    now = DateTime.utc_now()

    # Emit telemetry
    :telemetry.execute(
      [:circuit_breaker, :state_change],
      %{count: 1},
      %{
        name: circuit_breaker.name,
        from_state: circuit_breaker.state,
        to_state: :half_open,
        failure_count: circuit_breaker.failure_count
      }
    )

    %{circuit_breaker | state: :half_open, half_open_success_count: 0, state_changed_at: now}
  end

  defp transition_to_closed(circuit_breaker) do
    now = DateTime.utc_now()

    # Emit telemetry
    :telemetry.execute(
      [:circuit_breaker, :state_change],
      %{count: 1},
      %{
        name: circuit_breaker.name,
        from_state: circuit_breaker.state,
        to_state: :closed,
        failure_count: 0
      }
    )

    %{
      circuit_breaker
      | state: :closed,
        failure_count: 0,
        half_open_success_count: 0,
        last_failure_time: nil,
        state_changed_at: now
    }
  end

  defp uptime_ms(circuit_breaker) do
    DateTime.diff(DateTime.utc_now(), circuit_breaker.state_changed_at, :millisecond)
  end

  ## Logging

  defp log_success(circuit_breaker) do
    Logger.debug("Circuit breaker call succeeded", %{
      circuit_breaker: circuit_breaker.name,
      state: circuit_breaker.state,
      failure_count: circuit_breaker.failure_count
    })
  end

  defp log_failure(circuit_breaker, error) do
    Logger.warning("Circuit breaker call failed", %{
      circuit_breaker: circuit_breaker.name,
      state: circuit_breaker.state,
      failure_count: circuit_breaker.failure_count,
      threshold: circuit_breaker.config.failure_threshold,
      error: inspect(error)
    })
  end

  defp log_circuit_opened(circuit_breaker, error) do
    Logger.error("Circuit breaker opened due to failures", %{
      circuit_breaker: circuit_breaker.name,
      failure_count: circuit_breaker.failure_count,
      threshold: circuit_breaker.config.failure_threshold,
      timeout_ms: circuit_breaker.config.timeout_ms,
      error: inspect(error)
    })
  end

  defp log_circuit_closed(circuit_breaker) do
    Logger.info("Circuit breaker closed - service recovered", %{
      circuit_breaker: circuit_breaker.name,
      success_count: circuit_breaker.half_open_success_count,
      threshold: circuit_breaker.config.success_threshold
    })
  end

  defp log_circuit_blocked(circuit_breaker) do
    Logger.debug("Circuit breaker blocked call - circuit is open", %{
      circuit_breaker: circuit_breaker.name,
      state: circuit_breaker.state,
      last_failure: circuit_breaker.last_failure_time,
      timeout_ms: circuit_breaker.config.timeout_ms
    })
  end
end
