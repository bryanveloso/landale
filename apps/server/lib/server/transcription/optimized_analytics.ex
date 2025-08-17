defmodule Server.Transcription.OptimizedAnalytics do
  @moduledoc """
  Optimized analytics queries using TimescaleDB continuous aggregates and indexes.

  This module provides high-performance queries that leverage:
  - Continuous aggregates for pre-computed hourly/daily metrics
  - GIN indexes for fast text search
  - Chunk-aware query patterns for time-series data
  """

  alias Server.Repo
  import Ecto.Query

  @doc """
  Get hourly transcription metrics using continuous aggregates.
  Much faster than calculating on-the-fly.
  """
  @spec get_hourly_metrics(DateTime.t(), DateTime.t(), String.t() | nil) :: [map()]
  def get_hourly_metrics(start_time, end_time, session_id \\ nil) do
    query = """
    SELECT
      hour,
      count,
      avg_confidence,
      min_confidence,
      max_confidence,
      avg_duration,
      total_duration,
      high_confidence_count,
      medium_confidence_count,
      low_confidence_count
    FROM transcriptions_hourly
    WHERE hour >= $1 AND hour <= $2
    #{if session_id, do: "AND stream_session_id = $3", else: ""}
    ORDER BY hour DESC
    """

    params =
      if session_id do
        [start_time, end_time, session_id]
      else
        [start_time, end_time]
      end

    case Repo.query(query, params) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          Enum.zip(columns, row) |> Map.new()
        end)

      {:error, _} ->
        # Fallback to regular query if continuous aggregate not available
        get_hourly_metrics_fallback(start_time, end_time, session_id)
    end
  end

  @doc """
  Get daily transcription metrics using continuous aggregates.
  """
  @spec get_daily_metrics(DateTime.t(), DateTime.t(), String.t() | nil) :: [map()]
  def get_daily_metrics(start_time, end_time, session_id \\ nil) do
    query = """
    SELECT
      day,
      count,
      avg_confidence,
      min_confidence,
      max_confidence,
      avg_duration,
      total_duration,
      total_text_length
    FROM transcriptions_daily
    WHERE day >= $1 AND day <= $2
    #{if session_id, do: "AND stream_session_id = $3", else: ""}
    ORDER BY day DESC
    """

    params =
      if session_id do
        [start_time, end_time, session_id]
      else
        [start_time, end_time]
      end

    case Repo.query(query, params) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          Enum.zip(columns, row) |> Map.new()
        end)

      {:error, _} ->
        # Fallback to regular query if continuous aggregate not available
        get_daily_metrics_fallback(start_time, end_time, session_id)
    end
  end

  @doc """
  Fast text search in transcriptions using GIN indexes.
  Returns results with similarity scores.
  """
  @spec search_transcriptions(String.t(), keyword()) :: [map()]
  def search_transcriptions(search_term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    start_time = Keyword.get(opts, :start_time, DateTime.add(DateTime.utc_now(), -24, :hour))
    end_time = Keyword.get(opts, :end_time, DateTime.utc_now())
    min_similarity = Keyword.get(opts, :min_similarity, 0.3)

    # Use trigram similarity for fuzzy matching
    query = """
    SELECT
      id,
      timestamp,
      text,
      confidence,
      duration,
      source_id,
      similarity(text, $1) as similarity_score
    FROM transcriptions
    WHERE timestamp >= $2
      AND timestamp <= $3
      AND text % $1  -- Uses GIN trigram index
    ORDER BY similarity_score DESC, timestamp DESC
    LIMIT $4
    """

    case Repo.query(query, [search_term, start_time, end_time, limit]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, timestamp, text, confidence, duration, source_id, similarity] ->
          %{
            id: id,
            timestamp: timestamp,
            text: text,
            confidence: confidence,
            duration: duration,
            source_id: source_id,
            similarity_score: similarity
          }
        end)
        |> Enum.filter(&(&1.similarity_score >= min_similarity))

      {:error, _} ->
        []
    end
  end

  @doc """
  Fast full-text search using tsvector columns.
  Better for exact word matching and phrase queries.
  """
  @spec full_text_search(String.t(), keyword()) :: [map()]
  def full_text_search(search_query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    start_time = Keyword.get(opts, :start_time, DateTime.add(DateTime.utc_now(), -24, :hour))
    end_time = Keyword.get(opts, :end_time, DateTime.utc_now())

    query = """
    SELECT
      id,
      timestamp,
      text,
      confidence,
      duration,
      ts_rank(text_search_vector, plainto_tsquery('english', $1)) as rank
    FROM transcriptions
    WHERE timestamp >= $2
      AND timestamp <= $3
      AND text_search_vector @@ plainto_tsquery('english', $1)
    ORDER BY rank DESC, timestamp DESC
    LIMIT $4
    """

    case Repo.query(query, [search_query, start_time, end_time, limit]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, timestamp, text, confidence, duration, rank] ->
          %{
            id: id,
            timestamp: timestamp,
            text: text,
            confidence: confidence,
            duration: duration,
            relevance_score: rank
          }
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Search chat messages efficiently using optimized indexes.
  """
  @spec search_chat_messages(String.t(), keyword()) :: [map()]
  def search_chat_messages(search_term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    start_time = Keyword.get(opts, :start_time, DateTime.add(DateTime.utc_now(), -24, :hour))
    end_time = Keyword.get(opts, :end_time, DateTime.utc_now())

    # Use the optimized function we created in the migration
    query = """
    SELECT * FROM search_chat_messages($1, $2, $3, $4)
    """

    case Repo.query(query, [search_term, start_time, end_time, limit]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, timestamp, user_name, message, similarity] ->
          %{
            id: id,
            timestamp: timestamp,
            user_name: user_name,
            message: message,
            similarity_score: similarity
          }
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Get event statistics using continuous aggregates.
  """
  @spec get_event_stats(String.t(), DateTime.t(), DateTime.t()) :: map()
  def get_event_stats(event_type, start_time, end_time) do
    query = """
    SELECT
      SUM(count) as total_count,
      SUM(unique_users) as total_unique_users,
      COUNT(*) as total_hours
    FROM events_hourly
    WHERE hour >= $1
      AND hour <= $2
      AND event_type = $3
    """

    case Repo.query(query, [start_time, end_time, event_type]) do
      {:ok, %{rows: [[total_count, total_unique_users, total_hours]]}} ->
        %{
          total_count: total_count || 0,
          total_unique_users: total_unique_users || 0,
          total_hours: total_hours || 0,
          avg_per_hour: if(total_hours > 0, do: (total_count || 0) / total_hours, else: 0)
        }

      {:error, _} ->
        %{total_count: 0, total_unique_users: 0, total_hours: 0, avg_per_hour: 0}
    end
  end

  # Fallback functions for when continuous aggregates aren't available

  defp get_hourly_metrics_fallback(start_time, end_time, session_id) do
    Server.Transcription.Analytics.calculate_hourly_volume_db(end_time)
  end

  defp get_daily_metrics_fallback(start_time, end_time, session_id) do
    # Simple fallback using regular queries
    from(t in Server.Transcription.Transcription,
      where: t.timestamp >= ^start_time and t.timestamp <= ^end_time,
      group_by: fragment("date_trunc('day', ?)", t.timestamp),
      select: %{
        day: fragment("date_trunc('day', ?)", t.timestamp),
        count: count(t.id),
        avg_confidence: avg(t.confidence),
        total_duration: sum(t.duration)
      },
      order_by: [desc: fragment("date_trunc('day', ?)", t.timestamp)]
    )
    |> Repo.all()
  end
end
