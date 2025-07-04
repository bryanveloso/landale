defmodule Server.Transcription do
  @moduledoc """
  The Transcription context for managing audio transcriptions with TimescaleDB.

  This context provides functions for creating, querying, and analyzing transcription
  data optimized for time-series operations using TimescaleDB hypertables.
  """

  import Ecto.Query, warn: false
  alias Server.Repo
  alias Server.Transcription.Transcription

  @type transcription_opts :: [
          limit: pos_integer(),
          stream_session_id: String.t() | nil
        ]

  ## Basic Operations

  @doc """
  Lists recent transcriptions with optional filtering.

  ## Options

    * `:limit` - Maximum number of results (default: 50, max: 1000)
    * `:stream_session_id` - Filter by stream session

  ## Examples

      iex> list_transcriptions(limit: 10)
      [%Transcription{}, ...]
      
      iex> list_transcriptions(stream_session_id: "stream_2024_01_15")
      [%Transcription{}, ...]
  """
  @spec list_transcriptions(transcription_opts()) :: [Transcription.t()]
  def list_transcriptions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50) |> min(1000)
    stream_session_id = Keyword.get(opts, :stream_session_id)

    query =
      from(t in Transcription,
        order_by: [desc: t.timestamp],
        limit: ^limit
      )

    query =
      if stream_session_id do
        from(q in query, where: q.stream_session_id == ^stream_session_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single transcription by ID, raising if not found.
  """
  @spec get_transcription!(binary()) :: Transcription.t()
  def get_transcription!(id), do: Repo.get!(Transcription, id)

  @doc """
  Creates a new transcription.

  ## Examples

      iex> create_transcription(%{text: "Hello world", duration: 1.5, timestamp: DateTime.utc_now()})
      {:ok, %Transcription{}}
      
      iex> create_transcription(%{text: ""})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_transcription(map()) :: {:ok, Transcription.t()} | {:error, Ecto.Changeset.t()}
  def create_transcription(attrs \\ %{}) do
    %Transcription{}
    |> Transcription.changeset(attrs)
    |> Repo.insert()
  end

  ## Time-based Queries

  def list_transcriptions_by_time_range(start_time, end_time, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    stream_session_id = Keyword.get(opts, :stream_session_id)

    query =
      from(t in Transcription,
        where: t.timestamp >= ^start_time and t.timestamp <= ^end_time,
        order_by: [asc: t.timestamp],
        limit: ^limit
      )

    query =
      if stream_session_id do
        from(q in query, where: q.stream_session_id == ^stream_session_id)
      else
        query
      end

    Repo.all(query)
  end

  def get_recent_transcriptions(minutes \\ 5) do
    cutoff = DateTime.utc_now() |> DateTime.add(-minutes, :minute)

    from(t in Transcription,
      where: t.timestamp >= ^cutoff,
      order_by: [desc: t.timestamp]
    )
    |> Repo.all()
  end

  ## Search Operations

  @doc """
  Searches transcriptions using case-insensitive text matching.

  ## Options

    * `:limit` - Maximum number of results (default: 25, max: 100)
    * `:stream_session_id` - Filter by stream session

  ## Examples

      iex> search_transcriptions("hello world", limit: 10)
      [%Transcription{}, ...]
  """
  @spec search_transcriptions(String.t(), transcription_opts()) :: [Transcription.t()]
  def search_transcriptions(search_term, opts \\ []) when is_binary(search_term) do
    limit = Keyword.get(opts, :limit, 25) |> min(100)
    stream_session_id = Keyword.get(opts, :stream_session_id)

    # Sanitize search term to prevent injection
    sanitized_term = "%#{String.replace(search_term, ~r/[%_\\]/, "\\\\&")}%"

    query =
      from(t in Transcription,
        where: ilike(t.text, ^sanitized_term),
        order_by: [desc: t.timestamp],
        limit: ^limit
      )

    query =
      if stream_session_id do
        from(q in query, where: q.stream_session_id == ^stream_session_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Searches transcriptions using PostgreSQL full-text search with similarity ranking.

  Uses pg_trgm extension for fuzzy matching and similarity scoring.
  Falls back to basic search in test/dev environments.

  ## Options

    * `:limit` - Maximum number of results (default: 25, max: 100)
    * `:stream_session_id` - Filter by stream session

  ## Examples

      iex> search_transcriptions_full_text("hello wrld", limit: 5)
      [%Transcription{}, ...]
  """
  @spec search_transcriptions_full_text(String.t(), transcription_opts()) :: [Transcription.t()]
  def search_transcriptions_full_text(search_term, opts \\ []) when is_binary(search_term) do
    if Mix.env() == :prod do
      search_with_similarity(search_term, opts)
    else
      # Fall back to basic search in test/dev environments
      search_transcriptions(search_term, opts)
    end
  end

  defp search_with_similarity(search_term, opts) do
    limit = Keyword.get(opts, :limit, 25) |> min(100)
    stream_session_id = Keyword.get(opts, :stream_session_id)

    query =
      from(t in Transcription,
        where: fragment("? % ?", t.text, ^search_term),
        order_by: [desc: fragment("similarity(?, ?)", t.text, ^search_term), desc: t.timestamp],
        limit: ^limit
      )

    query =
      if stream_session_id do
        from(q in query, where: q.stream_session_id == ^stream_session_id)
      else
        query
      end

    Repo.all(query)
  end

  ## Session Operations

  def get_session_transcriptions(stream_session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    from(t in Transcription,
      where: t.stream_session_id == ^stream_session_id,
      order_by: [asc: t.timestamp],
      limit: ^limit
    )
    |> Repo.all()
  end

  def get_session_duration(stream_session_id) do
    case from(t in Transcription,
           where: t.stream_session_id == ^stream_session_id,
           select: {min(t.timestamp), max(t.timestamp)}
         )
         |> Repo.one() do
      {nil, nil} ->
        {:error, :no_transcriptions}

      {start_time, end_time} ->
        duration = DateTime.diff(end_time, start_time, :second)
        {:ok, %{start_time: start_time, end_time: end_time, duration_seconds: duration}}
    end
  end

  ## Analytics

  def get_transcription_stats(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    cutoff = DateTime.utc_now() |> DateTime.add(-hours, :hour)

    from(t in Transcription,
      where: t.timestamp >= ^cutoff,
      select: %{
        total_count: count(t.id),
        total_duration: sum(t.duration),
        unique_sessions: count(t.stream_session_id, :distinct),
        avg_confidence: avg(t.confidence)
      }
    )
    |> Repo.one()
  end

  ## Cleanup Operations

  def delete_old_transcriptions(days_to_keep \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_to_keep, :day)

    from(t in Transcription,
      where: t.timestamp < ^cutoff
    )
    |> Repo.delete_all()
  end
end
