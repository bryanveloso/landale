defmodule Server.Correlation.Repository do
  @moduledoc """
  Database operations for correlations.

  Handles storing correlations, aggregating hot phrases, and managing stream sessions.

  ## Error Recovery

  This module implements retry logic with exponential backoff and circuit breaker
  pattern for handling transient database failures:

  - Automatic retry with exponential backoff (up to 3 attempts)
  - Circuit breaker to prevent overwhelming a failing database
  - Comprehensive error logging for monitoring
  - Graceful degradation without data loss
  """

  import Ecto.Query
  alias Server.Correlation.Correlation
  alias Server.Correlation.Monitor
  alias Server.Repo

  require Logger

  # Retry configuration
  @max_retries 3
  @initial_backoff_ms 100
  @max_backoff_ms 5000
  @jitter_range 0.1

  # Circuit breaker configuration
  # Number of consecutive failures to open circuit
  @circuit_breaker_threshold 5
  # Time to wait before attempting to close circuit
  @circuit_breaker_timeout_ms 30_000

  # Circuit breaker state management
  use Agent

  def start_link(_) do
    Agent.start_link(
      fn ->
        %{
          failure_count: 0,
          # :closed, :open, :half_open
          state: :closed,
          last_failure_time: nil,
          last_opened_at: nil
        }
      end,
      name: __MODULE__
    )
  end

  @doc """
  Store a correlation in the database with retry logic and circuit breaker.
  """
  def store_correlation(correlation_data) do
    with_retry(
      fn -> do_store_correlation(correlation_data) end,
      "store_correlation",
      correlation_data
    )
  end

  # Original store_correlation logic moved to private function
  defp do_store_correlation(correlation_data) do
    # Extract session_id from correlation_data, it should be passed in
    session_id = correlation_data[:session_id] || correlation_data.session_id

    if session_id do
      attrs = %{
        transcription_id: correlation_data[:transcription_id] || correlation_data.transcription_id,
        transcription_text: correlation_data[:transcription_text] || correlation_data.transcription_text,
        chat_message_id: correlation_data[:chat_message_id] || correlation_data.chat_message_id,
        chat_user: correlation_data[:chat_user] || correlation_data.chat_user,
        chat_text: correlation_data[:chat_text] || correlation_data.chat_text,
        pattern_type: to_string(correlation_data[:pattern_type] || correlation_data.pattern_type),
        confidence: correlation_data[:confidence] || correlation_data.confidence,
        time_offset_ms: correlation_data[:time_offset_ms] || correlation_data.time_offset_ms,
        detected_keywords: correlation_data[:detected_keywords] || [],
        session_id: session_id,
        created_at: DateTime.utc_now()
      }

      %Correlation{}
      |> Correlation.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, correlation} ->
          update_hot_phrases(correlation)
          update_session_stats(correlation.session_id)
          {:ok, correlation}

        {:error, changeset} ->
          Logger.error("Failed to store correlation: #{inspect(changeset.errors)}")
          {:error, changeset}
      end
    else
      Logger.error("No session_id provided for correlation")
      {:error, :no_session_id}
    end
  end

  @doc """
  Get recent correlations with optional filters.
  """
  def get_recent_correlations(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    pattern_type = Keyword.get(opts, :pattern_type)
    min_confidence = Keyword.get(opts, :min_confidence, 0.0)
    session_id = Keyword.get(opts, :session_id)

    query =
      from c in Correlation,
        where: c.confidence >= ^min_confidence,
        order_by: [desc: c.created_at],
        limit: ^limit

    query =
      if pattern_type do
        where(query, [c], c.pattern_type == ^pattern_type)
      else
        query
      end

    query =
      if session_id do
        where(query, [c], c.session_id == ^session_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Get correlations within a time range.
  """
  def get_correlations_in_range(start_time, end_time, opts \\ []) do
    pattern_type = Keyword.get(opts, :pattern_type)
    min_confidence = Keyword.get(opts, :min_confidence, 0.0)

    query =
      from c in Correlation,
        where: c.created_at >= ^start_time and c.created_at <= ^end_time,
        where: c.confidence >= ^min_confidence,
        order_by: [asc: c.created_at]

    query =
      if pattern_type do
        where(query, [c], c.pattern_type == ^pattern_type)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Get correlation statistics for a session.
  """
  def get_session_stats(session_id) do
    pattern_stats =
      from(c in Correlation,
        where: c.session_id == ^session_id,
        group_by: c.pattern_type,
        select: %{
          pattern_type: c.pattern_type,
          count: count(c.id),
          avg_confidence: avg(c.confidence),
          max_confidence: max(c.confidence)
        }
      )
      |> Repo.all()

    total_stats =
      from(c in Correlation,
        where: c.session_id == ^session_id,
        select: %{
          total_count: count(c.id),
          avg_confidence: avg(c.confidence),
          avg_response_time: avg(c.time_offset_ms)
        }
      )
      |> Repo.one()

    %{
      total: total_stats,
      by_pattern: pattern_stats
    }
  end

  @doc """
  Get top hot phrases for a specific session.
  Session ID must be provided in opts.
  """
  def get_hot_phrases(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    session_id = Keyword.get(opts, :session_id)

    if session_id do
      query = """
        SELECT phrase, pattern_type, occurrence_count, avg_confidence
        FROM hot_phrases
        WHERE session_id = $1
        ORDER BY occurrence_count DESC
        LIMIT $2
      """

      case Repo.query(query, [session_id, limit]) do
        {:ok, result} ->
          Enum.map(result.rows, fn [phrase, pattern_type, count, confidence] ->
            %{
              phrase: phrase,
              pattern_type: pattern_type,
              count: count,
              confidence: Float.round(confidence, 2)
            }
          end)

        {:error, error} ->
          Logger.error("Failed to get hot phrases: #{inspect(error)}")
          []
      end
    else
      Logger.warning("No session_id provided for get_hot_phrases")
      []
    end
  end

  # Private functions

  defp update_hot_phrases(correlation) do
    # Extract key phrases from the correlation
    phrases = extract_key_phrases(correlation)

    Enum.each(phrases, fn phrase ->
      query = """
        INSERT INTO hot_phrases (phrase, pattern_type, occurrence_count, total_confidence, avg_confidence, last_seen_at, session_id, inserted_at, updated_at)
        VALUES ($1, $2, 1, $3, $3, $4, $5, $6, $7)
        ON CONFLICT (phrase, session_id) DO UPDATE
        SET occurrence_count = hot_phrases.occurrence_count + 1,
            total_confidence = hot_phrases.total_confidence + $3,
            avg_confidence = (hot_phrases.total_confidence + $3) / (hot_phrases.occurrence_count + 1),
            last_seen_at = $4,
            updated_at = $7
      """

      now = DateTime.utc_now()

      # Convert session_id to binary if it's a string UUID
      session_id_binary =
        case Ecto.UUID.dump(correlation.session_id) do
          {:ok, binary} -> binary
          # Already binary
          :error -> correlation.session_id
        end

      Repo.query(query, [
        phrase,
        correlation.pattern_type,
        correlation.confidence,
        now,
        session_id_binary,
        now,
        now
      ])
    end)
  end

  defp extract_key_phrases(correlation) do
    # For direct quotes and keyword echoes, extract significant phrases
    case correlation.pattern_type do
      "direct_quote" ->
        # Use the transcription text as the key phrase
        [normalize_phrase(correlation.transcription_text)]

      "keyword_echo" ->
        # Extract shared keywords between transcription and chat
        extract_shared_keywords(correlation.transcription_text, correlation.chat_text)

      _ ->
        []
    end
  end

  defp extract_shared_keywords(text1, text2) do
    common_words = ~w(the and but for with are was were been have has had is it to of in a an)

    words1 =
      text1
      |> String.downcase()
      |> String.split()
      |> Enum.filter(fn w -> String.length(w) > 2 && w not in common_words end)
      |> MapSet.new()

    words2 =
      text2
      |> String.downcase()
      |> String.split()
      |> Enum.filter(fn w -> String.length(w) > 2 && w not in common_words end)
      |> MapSet.new()

    MapSet.intersection(words1, words2)
    |> MapSet.to_list()
    # Limit to top 3 shared keywords
    |> Enum.take(3)
  end

  defp normalize_phrase(text) do
    text
    |> String.downcase()
    |> String.trim()
    # Limit phrase length
    |> String.slice(0, 100)
  end

  defp update_session_stats(session_id) do
    query = """
      UPDATE stream_sessions
      SET total_correlations = (
        SELECT COUNT(*) FROM correlations WHERE session_id = $1
      ),
      updated_at = $2
      WHERE id = $1
    """

    # Convert UUID string to binary for PostgreSQL if needed
    session_id_binary =
      case Ecto.UUID.dump(session_id) do
        {:ok, binary} -> binary
        # Already binary or handle error
        :error -> session_id
      end

    Repo.query(query, [session_id_binary, DateTime.utc_now()])
  end

  @doc """
  Start a new stream session with retry logic and circuit breaker.
  Returns the new session ID.
  """
  def start_stream_session do
    with_retry(
      fn -> do_start_stream_session() end,
      "start_stream_session",
      nil
    )
  end

  defp do_start_stream_session do
    session_id = Ecto.UUID.generate()

    query = """
      INSERT INTO stream_sessions (id, started_at, inserted_at, updated_at)
      VALUES ($1, $2::timestamptz, $3::timestamptz, $4::timestamptz)
    """

    now = DateTime.utc_now()

    # Convert UUID string to binary for PostgreSQL
    {:ok, session_id_binary} = Ecto.UUID.dump(session_id)

    case Repo.query(query, [session_id_binary, now, now, now]) do
      {:ok, _} ->
        Logger.info("Started new stream session: #{session_id}")
        {:ok, session_id}

      {:error, error} ->
        Logger.error("Failed to start stream session: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  End a specific stream session with retry logic and circuit breaker.
  """
  def end_stream_session(session_id) do
    if session_id do
      with_retry(
        fn -> do_end_stream_session(session_id) end,
        "end_stream_session",
        %{session_id: session_id}
      )
    else
      {:error, :no_session_id}
    end
  end

  defp do_end_stream_session(session_id) do
    query = """
      UPDATE stream_sessions
      SET ended_at = $1::timestamptz, updated_at = $2::timestamptz
      WHERE id = $3
    """

    now = DateTime.utc_now()

    # Convert UUID string to binary for PostgreSQL
    {:ok, session_id_binary} = Ecto.UUID.dump(session_id)

    case Repo.query(query, [now, now, session_id_binary]) do
      {:ok, _} ->
        Logger.info("Ended stream session: #{session_id}")
        {:ok, session_id}

      {:error, error} ->
        Logger.error("Failed to end stream session: #{inspect(error)}")
        {:error, error}
    end
  end

  # Retry and Circuit Breaker Implementation

  @doc false
  defp with_retry(operation, operation_name, context, attempt \\ 1) do
    start_time = System.system_time(:millisecond)

    # Check circuit breaker state first
    case get_circuit_state() do
      :open ->
        Logger.warning("Circuit breaker is open for #{operation_name}, rejecting operation",
          context: context
        )

        latency = System.system_time(:millisecond) - start_time
        Monitor.record_database_operation(operation_name, :error, latency)

        {:error, :circuit_breaker_open}

      state when state in [:closed, :half_open] ->
        # Attempt the operation
        case operation.() do
          {:ok, result} ->
            # Reset circuit breaker on success
            reset_circuit_breaker()

            latency = System.system_time(:millisecond) - start_time
            Monitor.record_database_operation(operation_name, :success, latency)

            {:ok, result}

          {:error, reason} = error ->
            latency = System.system_time(:millisecond) - start_time
            Monitor.record_database_operation(operation_name, :error, latency)

            handle_operation_failure(operation, operation_name, context, attempt, reason, error)
        end
    end
  end

  defp handle_operation_failure(operation, operation_name, context, attempt, reason, error) do
    # Increment failure count
    increment_failure_count()

    # Check if it's a retryable error
    if retryable_error?(reason) and attempt < @max_retries do
      backoff_ms = calculate_backoff(attempt)

      Logger.warning(
        "Database operation failed, retrying #{operation_name} (attempt #{attempt + 1}/#{@max_retries})",
        reason: inspect(reason),
        backoff_ms: backoff_ms,
        context: context
      )

      # Wait with exponential backoff
      Process.sleep(backoff_ms)

      # Retry the operation
      with_retry(operation, operation_name, context, attempt + 1)
    else
      # Max retries exceeded or non-retryable error
      Logger.error(
        "Database operation permanently failed: #{operation_name}",
        reason: inspect(reason),
        attempts: attempt,
        context: context,
        retryable: retryable_error?(reason)
      )

      # Check if circuit breaker should open
      maybe_open_circuit_breaker()

      error
    end
  end

  defp retryable_error?(reason) do
    case reason do
      %DBConnection.ConnectionError{} -> true
      %Postgrex.Error{postgres: %{code: code}} when code in ["08000", "08001", "08006", "57P01"] -> true
      :timeout -> true
      :connection_not_available -> true
      _ -> false
    end
  end

  defp calculate_backoff(attempt) do
    base_backoff = @initial_backoff_ms * :math.pow(2, attempt - 1)
    backoff = min(base_backoff, @max_backoff_ms)

    # Add jitter to prevent thundering herd
    jitter = backoff * @jitter_range * :rand.uniform()
    round(backoff + jitter)
  end

  # Circuit Breaker Functions

  defp get_circuit_state do
    ensure_agent_started()

    Agent.get(__MODULE__, fn state ->
      case state.state do
        :open ->
          check_circuit_transition(state)

        other ->
          other
      end
    end)
  end

  defp check_circuit_transition(state) do
    if state.last_opened_at &&
         DateTime.diff(DateTime.utc_now(), state.last_opened_at, :millisecond) >= @circuit_breaker_timeout_ms do
      Agent.update(__MODULE__, fn s -> %{s | state: :half_open} end)
      :half_open
    else
      :open
    end
  end

  @doc false
  def increment_failure_count do
    ensure_agent_started()

    Agent.update(__MODULE__, fn state ->
      %{state | failure_count: state.failure_count + 1, last_failure_time: DateTime.utc_now()}
    end)
  end

  defp reset_circuit_breaker do
    ensure_agent_started()

    Agent.update(__MODULE__, fn _state ->
      %{
        failure_count: 0,
        state: :closed,
        last_failure_time: nil,
        last_opened_at: nil
      }
    end)
  end

  @doc false
  def maybe_open_circuit_breaker do
    ensure_agent_started()

    Agent.get_and_update(__MODULE__, fn state ->
      if state.failure_count >= @circuit_breaker_threshold do
        now = DateTime.utc_now()

        Logger.error(
          "Circuit breaker opened after #{state.failure_count} consecutive failures",
          threshold: @circuit_breaker_threshold,
          will_retry_at: DateTime.add(now, @circuit_breaker_timeout_ms, :millisecond)
        )

        new_state = %{state | state: :open, last_opened_at: now}

        {new_state, new_state}
      else
        {state, state}
      end
    end)
  end

  defp ensure_agent_started do
    case Process.whereis(__MODULE__) do
      nil ->
        # Start the agent if it's not running
        {:ok, _pid} = start_link(nil)

      _pid ->
        :ok
    end
  end

  @doc """
  Get the current circuit breaker status for monitoring.
  """
  def get_circuit_breaker_status do
    ensure_agent_started()

    Agent.get(__MODULE__, fn state ->
      %{
        state: state.state,
        failure_count: state.failure_count,
        last_failure: state.last_failure_time,
        last_opened: state.last_opened_at,
        threshold: @circuit_breaker_threshold,
        timeout_ms: @circuit_breaker_timeout_ms
      }
    end)
  end

  @doc """
  Manually reset the circuit breaker (useful for testing or manual intervention).
  """
  def reset_circuit_breaker_manual do
    reset_circuit_breaker()
    Logger.info("Circuit breaker manually reset")
    :ok
  end
end
