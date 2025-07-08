defmodule Server.ExternalCall do
  @moduledoc """
  Wrapper for external service calls with circuit breaker protection.

  Provides a consistent interface for making HTTP and WebSocket calls to external
  services while automatically applying circuit breaker patterns for resilience.

  ## Usage

      # HTTP calls with circuit breaker protection
      result = ExternalCall.http_request("twitch-api", fn ->
        :gun.get(conn, "/helix/users")
      end)

      # WebSocket calls with circuit breaker protection  
      result = ExternalCall.websocket_call("obs-websocket", fn ->
        WebSocketClient.send_message(client, message)
      end)

      # Custom circuit breaker configuration
      result = ExternalCall.http_request("custom-service", fn ->
        :gun.post(conn, "/api/endpoint", headers, body)
      end, %{failure_threshold: 3, timeout_ms: 30_000})
  """

  require Logger
  alias Server.{CircuitBreaker, CircuitBreakerRegistry}

  @doc """
  Makes an HTTP request with circuit breaker protection.
  
  The service name is used to identify the circuit breaker. Multiple calls
  to the same service will share the same circuit breaker state.
  """
  def http_request(service_name, request_fn, circuit_config \\ %{}) when is_function(request_fn, 0) do
    default_config = %{
      failure_threshold: 5,
      timeout_ms: 60_000,
      reset_timeout_ms: 30_000,
      success_threshold: 2
    }
    
    config = Map.merge(default_config, circuit_config)
    
    execute_with_circuit_breaker(service_name, request_fn, config, :http)
  end

  @doc """
  Makes a WebSocket call with circuit breaker protection.
  
  Uses more aggressive settings suitable for WebSocket connections which
  can fail more frequently than HTTP calls.
  """
  def websocket_call(service_name, request_fn, circuit_config \\ %{}) when is_function(request_fn, 0) do
    default_config = %{
      failure_threshold: 3,
      timeout_ms: 30_000,
      reset_timeout_ms: 15_000,
      success_threshold: 1
    }
    
    config = Map.merge(default_config, circuit_config)
    
    execute_with_circuit_breaker(service_name, request_fn, config, :websocket)
  end

  @doc """
  Makes a database call with circuit breaker protection.
  
  Uses conservative settings suitable for database connections.
  """
  def database_call(service_name, request_fn, circuit_config \\ %{}) when is_function(request_fn, 0) do
    default_config = %{
      failure_threshold: 10,
      timeout_ms: 120_000,
      reset_timeout_ms: 60_000,
      success_threshold: 3
    }
    
    config = Map.merge(default_config, circuit_config)
    
    execute_with_circuit_breaker(service_name, request_fn, config, :database)
  end

  @doc """
  Gets the current status of all circuit breakers.
  """
  def get_circuit_status do
    CircuitBreakerRegistry.get_all_metrics()
  end

  @doc """
  Gets the status of a specific circuit breaker.
  """
  def get_circuit_status(service_name) do
    case CircuitBreakerRegistry.get(service_name) do
      {:ok, circuit_breaker} ->
        {:ok, CircuitBreaker.get_metrics(circuit_breaker)}
      
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  ## Private Implementation

  defp execute_with_circuit_breaker(service_name, request_fn, config, call_type) do
    # Get or create circuit breaker for this service
    circuit_breaker = CircuitBreakerRegistry.get_or_create(service_name, config)
    
    # Add timing and telemetry
    start_time = System.monotonic_time(:millisecond)
    
    result = CircuitBreaker.call(circuit_breaker, fn ->
      measure_external_call(service_name, call_type, request_fn)
    end)
    
    duration_ms = System.monotonic_time(:millisecond) - start_time
    
    # Update circuit breaker state in registry
    case result do
      {:ok, _} ->
        # Success - update circuit breaker
        updated_circuit = handle_circuit_success(circuit_breaker)
        CircuitBreakerRegistry.update(updated_circuit)
        
        # Emit success telemetry
        emit_call_telemetry(service_name, call_type, :success, duration_ms)
        
      {:error, :circuit_open} ->
        # Circuit breaker blocked the call
        emit_call_telemetry(service_name, call_type, :circuit_open, duration_ms)
        
      {:error, _reason} ->
        # Call failed - update circuit breaker  
        updated_circuit = handle_circuit_failure(circuit_breaker)
        CircuitBreakerRegistry.update(updated_circuit)
        
        # Emit failure telemetry
        emit_call_telemetry(service_name, call_type, :failure, duration_ms)
    end
    
    result
  end

  defp measure_external_call(service_name, call_type, request_fn) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      result = request_fn.()
      duration_ms = System.monotonic_time(:millisecond) - start_time
      
      # Log successful external call
      Logger.debug("External call succeeded", %{
        service: service_name,
        type: call_type,
        duration_ms: duration_ms
      })
      
      result
    rescue
      error ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        
        # Log failed external call
        Logger.warning("External call failed", %{
          service: service_name,
          type: call_type,
          duration_ms: duration_ms,
          error: inspect(error)
        })
        
        reraise error, __STACKTRACE__
    end
  end

  defp handle_circuit_success(circuit_breaker) do
    case circuit_breaker.state do
      :closed ->
        # Reset failure count on success
        %{circuit_breaker | failure_count: 0}

      :half_open ->
        # Track successes in half-open state
        new_success_count = circuit_breaker.half_open_success_count + 1
        
        if new_success_count >= circuit_breaker.config.success_threshold do
          # Enough successes, close the circuit
          %{circuit_breaker |
            state: :closed,
            failure_count: 0,
            half_open_success_count: 0,
            last_failure_time: nil,
            state_changed_at: DateTime.utc_now()
          }
        else
          # Continue in half-open state
          %{circuit_breaker | half_open_success_count: new_success_count}
        end

      :open ->
        # This shouldn't happen, but handle gracefully
        circuit_breaker
    end
  end

  defp handle_circuit_failure(circuit_breaker) do
    new_failure_count = circuit_breaker.failure_count + 1
    now = DateTime.utc_now()
    
    updated_circuit = %{circuit_breaker | 
      failure_count: new_failure_count,
      last_failure_time: now
    }

    # Check if we should open the circuit
    if new_failure_count >= circuit_breaker.config.failure_threshold do
      %{updated_circuit |
        state: :open,
        state_changed_at: now
      }
    else
      updated_circuit
    end
  end

  defp emit_call_telemetry(service_name, call_type, status, duration_ms) do
    :telemetry.execute(
      [:external_call, call_type],
      %{
        duration_ms: duration_ms,
        count: 1
      },
      %{
        service: service_name,
        status: status
      }
    )
  end
end