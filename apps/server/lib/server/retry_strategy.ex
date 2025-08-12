defmodule Server.RetryStrategy do
  @moduledoc """
  Retry strategy implementation with exponential backoff for handling API rate limits and failures.

  Provides configurable retry logic with exponential backoff, jitter, and specific
  handling for different types of failures (rate limits, network errors, etc.).

  ## Features

  - Exponential backoff with configurable base delay and maximum delay
  - Jitter to prevent thundering herd problems
  - Rate limit detection and appropriate backoff
  - Configurable retry predicates for different error types
  - Telemetry integration for monitoring retry patterns
  - Circuit breaker pattern support

  ## Usage

      # Basic retry with default exponential backoff
      {:ok, result} = RetryStrategy.retry(fn ->
        :httpc.request(:get, {"https://api.example.com/data", []}, [], [])
      end)

      # Custom retry configuration
      opts = [
        max_attempts: 5,
        base_delay: 1000,
        max_delay: 30_000,
        backoff_factor: 2.0,
        jitter: true
      ]

      {:ok, result} = RetryStrategy.retry(fn ->
        SomeAPI.call()
      end, opts)

      # Rate limit aware retry
      {:ok, result} = RetryStrategy.retry_with_rate_limit_detection(fn ->
        TwitchAPI.create_subscription(...)
      end)
  """

  require Logger

  @type retry_result :: {:ok, term()} | {:error, term()}
  @type retry_function :: (-> retry_result())
  @type retry_predicate :: (term() -> boolean())

  @type retry_opts :: [
          max_attempts: pos_integer(),
          base_delay: pos_integer(),
          max_delay: pos_integer(),
          backoff_factor: float(),
          jitter: boolean(),
          retry_predicate: retry_predicate(),
          telemetry_prefix: [atom()]
        ]

  # Default configuration
  @default_max_attempts 3
  @default_base_delay 1_000
  @default_max_delay 30_000
  @default_backoff_factor 2.0
  @default_jitter true

  @doc """
  Executes a function with retry logic and exponential backoff.

  ## Parameters
  - `fun` - Function to execute that returns `{:ok, result}` or `{:error, reason}`
  - `opts` - Retry configuration options

  ## Options
  - `:max_attempts` - Maximum number of attempts (default: 3)
  - `:base_delay` - Base delay in milliseconds (default: 1000)
  - `:max_delay` - Maximum delay in milliseconds (default: 30000)
  - `:backoff_factor` - Exponential backoff multiplier (default: 2.0)
  - `:jitter` - Add random jitter to delays (default: true)
  - `:retry_predicate` - Function to determine if error should be retried
  - `:telemetry_prefix` - Telemetry event prefix (default: [:server, :retry])

  ## Returns
  - `{:ok, result}` - Function succeeded
  - `{:error, reason}` - All attempts failed
  """
  @spec retry(retry_function(), retry_opts()) :: retry_result()
  def retry(fun, opts \\ []) when is_function(fun, 0) do
    config = build_config(opts)

    emit_telemetry(config, [:attempt, :start])

    case do_retry(fun, config, 1) do
      {:ok, result} ->
        emit_telemetry(config, [:success], %{attempts: 1})
        {:ok, result}

      {:error, reason, attempts} ->
        emit_telemetry(config, [:failure], %{attempts: attempts, reason: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Retry function with specific rate limit detection and handling.

  Automatically detects rate limit responses and applies appropriate backoff delays.
  Common for API services like Twitch, Discord, etc.

  ## Parameters
  - `fun` - Function to execute
  - `opts` - Additional retry options (merged with rate limit defaults)

  ## Returns
  - `{:ok, result}` - Function succeeded
  - `{:error, reason}` - All attempts failed
  """
  @spec retry_with_rate_limit_detection(retry_function(), retry_opts()) :: retry_result()
  def retry_with_rate_limit_detection(fun, opts \\ []) do
    rate_limit_opts = [
      max_attempts: 5,
      base_delay: 5_000,
      max_delay: 300_000,
      backoff_factor: 2.0,
      retry_predicate: &retryable_error?/1,
      telemetry_prefix: [:server, :retry, :rate_limit]
    ]

    merged_opts = Keyword.merge(rate_limit_opts, opts)
    retry(fun, merged_opts)
  end

  @doc """
  Retry function with circuit breaker pattern for external service calls.

  Tracks failure rates and temporarily stops attempting calls if failure rate
  exceeds threshold, preventing cascade failures.

  ## Parameters
  - `service_name` - Unique identifier for the service
  - `fun` - Function to execute
  - `opts` - Circuit breaker and retry options

  ## Returns
  - `{:ok, result}` - Function succeeded
  - `{:error, :circuit_open}` - Circuit breaker is open
  - `{:error, reason}` - Function failed
  """
  @spec retry_with_circuit_breaker(atom(), retry_function(), retry_opts()) :: retry_result()
  def retry_with_circuit_breaker(service_name, fun, opts \\ []) do
    # Use CircuitBreakerServer instead of ETS-based implementation
    circuit_config = %{
      failure_threshold: Keyword.get(opts, :circuit_failure_threshold, 5),
      timeout_ms: Keyword.get(opts, :circuit_timeout_ms, 60_000),
      reset_timeout_ms: Keyword.get(opts, :circuit_reset_timeout_ms, 30_000),
      success_threshold: Keyword.get(opts, :circuit_success_threshold, 2)
    }

    Server.CircuitBreakerServer.call(
      service_name,
      fn -> retry(fun, opts) end,
      circuit_config
    )
  end

  # Private functions

  defp do_retry(fun, config, attempt) when attempt <= config.max_attempts do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        if attempt < config.max_attempts and should_retry?(reason, config) do
          delay = calculate_delay(attempt, config)

          Logger.debug("Retrying after failure",
            attempt: attempt,
            max_attempts: config.max_attempts,
            delay: delay,
            reason: inspect(reason)
          )

          emit_telemetry(config, [:retry], %{
            attempt: attempt,
            delay: delay,
            reason: inspect(reason)
          })

          :timer.sleep(delay)
          do_retry(fun, config, attempt + 1)
        else
          {:error, reason, attempt}
        end

      result ->
        Logger.warning("Unexpected return value from retry function", result: inspect(result))
        {:error, {:unexpected_return, result}, attempt}
    end
  rescue
    exception ->
      reason = {exception.__struct__, Exception.message(exception)}

      if attempt < config.max_attempts and should_retry?(reason, config) do
        delay = calculate_delay(attempt, config)

        Logger.debug("Retrying after exception",
          attempt: attempt,
          max_attempts: config.max_attempts,
          delay: delay,
          exception: inspect(exception)
        )

        emit_telemetry(config, [:retry], %{
          attempt: attempt,
          delay: delay,
          exception: inspect(exception)
        })

        :timer.sleep(delay)
        do_retry(fun, config, attempt + 1)
      else
        {:error, reason, attempt}
      end
  end

  defp do_retry(_fun, _config, attempt) do
    {:error, :max_attempts_exceeded, attempt - 1}
  end

  defp build_config(opts) do
    %{
      max_attempts: Keyword.get(opts, :max_attempts, @default_max_attempts),
      base_delay: Keyword.get(opts, :base_delay, @default_base_delay),
      max_delay: Keyword.get(opts, :max_delay, @default_max_delay),
      backoff_factor: Keyword.get(opts, :backoff_factor, @default_backoff_factor),
      jitter: Keyword.get(opts, :jitter, @default_jitter),
      retry_predicate: Keyword.get(opts, :retry_predicate, &default_retry_predicate/1),
      telemetry_prefix: Keyword.get(opts, :telemetry_prefix, [:server, :retry])
    }
  end

  defp should_retry?(reason, config) do
    config.retry_predicate.(reason)
  end

  defp calculate_delay(attempt, config) do
    # Calculate exponential backoff: base_delay * (backoff_factor ^ (attempt - 1))
    delay_ms = round(config.base_delay * :math.pow(config.backoff_factor, attempt - 1))

    # Apply maximum delay limit
    capped_delay = min(delay_ms, config.max_delay)

    # Add jitter if enabled
    if config.jitter do
      add_jitter(capped_delay)
    else
      capped_delay
    end
  end

  defp add_jitter(delay) do
    # Add ±25% jitter to prevent thundering herd
    jitter_range = div(delay, 4)
    jitter = :rand.uniform(2 * jitter_range) - jitter_range
    max(delay + jitter, 0)
  end

  defp default_retry_predicate(reason) do
    case reason do
      # Network-level errors that should be retried
      :timeout ->
        true

      :econnrefused ->
        true

      :econnreset ->
        true

      :ehostunreach ->
        true

      :nxdomain ->
        true

      # HTTP status codes that should be retried (with or without message)
      {:http_error, status} when status in [429, 500, 502, 503, 504] ->
        true

      {:http_error, status, _message} when status in [429, 500, 502, 503, 504] ->
        true

      # String-based error detection
      reason when is_binary(reason) ->
        String.contains?(String.downcase(reason), ["timeout", "connection", "rate limit"])

      # Default: don't retry
      _ ->
        false
    end
  end

  defp retryable_error?(reason) do
    case reason do
      # Twitch-specific rate limit errors (with or without message)
      {:http_error, 429} ->
        true

      {:http_error, 429, _message} ->
        true

      reason when is_binary(reason) ->
        lower_reason = String.downcase(reason)
        String.contains?(lower_reason, ["rate limit", "too many requests", "429"])

      # Network errors
      :timeout ->
        true

      :econnrefused ->
        true

      :econnreset ->
        true

      # HTTP 5xx errors (server issues) - with or without message
      {:http_error, status} when status >= 500 and status < 600 ->
        true

      {:http_error, status, _message} when status >= 500 and status < 600 ->
        true

      _ ->
        false
    end
  end

  defp emit_telemetry(_config, _event_suffix, _metadata \\ %{}) do
    :ok
  end

  # Circuit breaker functionality has been moved to Server.CircuitBreakerServer
  # for better state management and atomic operations
end
