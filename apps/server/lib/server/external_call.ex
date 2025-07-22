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
  alias Server.CircuitBreakerServer

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
    CircuitBreakerServer.get_all_metrics()
  end

  @doc """
  Gets the status of a specific circuit breaker.
  """
  def get_circuit_status(service_name) do
    case CircuitBreakerServer.get_state(service_name) do
      {:ok, state} ->
        {:ok, %{name: service_name, state: state}}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  ## Private Implementation

  defp execute_with_circuit_breaker(service_name, request_fn, config, call_type) do
    # Use new CircuitBreakerServer with timing
    start_time = System.monotonic_time(:millisecond)

    result =
      CircuitBreakerServer.call(
        service_name,
        fn ->
          measure_external_call(service_name, call_type, request_fn)
        end,
        config
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time

    # Emit telemetry based on result
    case result do
      {:ok, _} ->
        emit_call_telemetry(service_name, call_type, :success, duration_ms)

      {:error, :circuit_open} ->
        emit_call_telemetry(service_name, call_type, :circuit_open, duration_ms)

      {:error, _reason} ->
        emit_call_telemetry(service_name, call_type, :failure, duration_ms)
    end

    result
  end

  defp measure_external_call(_service_name, _call_type, request_fn) do
    try do
      request_fn.()
    rescue
      error ->
        reraise error, __STACKTRACE__
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
