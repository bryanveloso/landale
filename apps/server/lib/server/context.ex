defmodule Server.Context do
  @moduledoc """
  The Context module for managing SEED memory contexts with TimescaleDB.

  This module provides functions for creating, querying, and analyzing context
  data optimized for time-series operations using TimescaleDB hypertables.
  Contexts represent 2-minute aggregated windows of transcriptions, chat, and interactions.
  """

  import Ecto.Query, warn: false
  alias Server.Context.Context
  alias Server.Repo

  @type context_opts :: [
          limit: pos_integer(),
          session: String.t() | nil
        ]

  ## Basic Operations

  @doc """
  Lists recent contexts with optional filtering.

  ## Options

    * `:limit` - Maximum number of results (default: 50, max: 500)
    * `:session` - Filter by session ID

  ## Examples

      iex> list_contexts(limit: 10)
      [%Context{}, ...]
      
      iex> list_contexts(session: "stream_2024_01_15")
      [%Context{}, ...]
  """
  @spec list_contexts(context_opts()) :: [Context.t()]
  def list_contexts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50) |> min(500)
    session = Keyword.get(opts, :session)

    query =
      from(c in Context,
        order_by: [desc: c.started],
        limit: ^limit
      )

    query =
      if session do
        from(q in query, where: q.session == ^session)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Creates a new context.

  ## Examples

      iex> create_context(%{started: DateTime.utc_now(), ended: DateTime.utc_now(), session: "stream_2024_01_15", transcript: "Hello world", duration: 120.0})
      {:ok, %Context{}}
      
      iex> create_context(%{transcript: ""})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_context(map()) :: {:ok, Context.t()} | {:error, Ecto.Changeset.t()}
  def create_context(attrs \\ %{}) do
    %Context{}
    |> Context.changeset(attrs)
    |> Repo.insert()
  end

  ## Time-based Queries

  @doc """
  Lists contexts within a specific time range.
  """
  @spec list_contexts_by_time_range(DateTime.t(), DateTime.t(), context_opts()) :: [Context.t()]
  def list_contexts_by_time_range(start_time, end_time, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    session = Keyword.get(opts, :session)

    query =
      from(c in Context,
        where: c.started >= ^start_time and c.started <= ^end_time,
        order_by: [asc: c.started],
        limit: ^limit
      )

    query =
      if session do
        from(q in query, where: q.session == ^session)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets recent contexts from the last N minutes.
  """
  @spec get_recent_contexts(pos_integer()) :: [Context.t()]
  def get_recent_contexts(minutes \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-minutes, :minute)

    from(c in Context,
      where: c.started >= ^cutoff,
      order_by: [desc: c.started]
    )
    |> Repo.all()
  end

  ## Search Operations

  @doc """
  Searches contexts using case-insensitive text matching on transcripts.

  ## Options

    * `:limit` - Maximum number of results (default: 25, max: 100)
    * `:session` - Filter by session

  ## Examples

      iex> search_contexts("hello world", limit: 10)
      [%Context{}, ...]
  """
  @spec search_contexts(String.t(), context_opts()) :: [Context.t()]
  def search_contexts(search_term, opts \\ []) when is_binary(search_term) do
    limit = Keyword.get(opts, :limit, 25) |> min(100)
    session = Keyword.get(opts, :session)

    # Sanitize search term to prevent injection
    sanitized_term = "%#{String.replace(search_term, ~r/[%_\\]/, "\\\\&")}%"

    query =
      from(c in Context,
        where: ilike(c.transcript, ^sanitized_term),
        order_by: [desc: c.started],
        limit: ^limit
      )

    query =
      if session do
        from(q in query, where: q.session == ^session)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Searches contexts by sentiment.
  """
  @spec list_contexts_by_sentiment(String.t(), context_opts()) :: [Context.t()]
  def list_contexts_by_sentiment(sentiment, opts \\ []) when sentiment in ["positive", "negative", "neutral"] do
    limit = Keyword.get(opts, :limit, 50) |> min(200)
    session = Keyword.get(opts, :session)

    query =
      from(c in Context,
        where: c.sentiment == ^sentiment,
        order_by: [desc: c.started],
        limit: ^limit
      )

    query =
      if session do
        from(q in query, where: q.session == ^session)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Searches contexts by topics (array contains search).
  """
  @spec list_contexts_by_topic(String.t(), context_opts()) :: [Context.t()]
  def list_contexts_by_topic(topic, opts \\ []) when is_binary(topic) do
    limit = Keyword.get(opts, :limit, 50) |> min(200)
    session = Keyword.get(opts, :session)

    query =
      from(c in Context,
        where: ^topic in c.topics,
        order_by: [desc: c.started],
        limit: ^limit
      )

    query =
      if session do
        from(q in query, where: q.session == ^session)
      else
        query
      end

    Repo.all(query)
  end

  ## Session Operations

  @doc """
  Gets all contexts for a specific session.
  """
  @spec get_session_contexts(String.t(), context_opts()) :: [Context.t()]
  def get_session_contexts(session, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)

    from(c in Context,
      where: c.session == ^session,
      order_by: [asc: c.started],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Gets session duration and stats.
  """
  @spec get_session_stats(String.t()) :: {:ok, map()} | {:error, :no_contexts}
  def get_session_stats(session) do
    case from(c in Context,
           where: c.session == ^session,
           select: {min(c.started), max(c.ended), count(c.started), sum(c.duration)}
         )
         |> Repo.one() do
      {nil, nil, 0, nil} ->
        {:error, :no_contexts}

      {start_time, end_time, context_count, total_duration} ->
        session_duration = DateTime.diff(end_time, start_time, :second)

        {:ok,
         %{
           start_time: start_time,
           end_time: end_time,
           session_duration_seconds: session_duration,
           context_count: context_count,
           total_content_duration: total_duration || 0.0
         }}
    end
  end

  ## Analytics

  @doc """
  Gets context analytics for the last N hours.
  """
  @spec get_context_stats(pos_integer()) :: map()
  def get_context_stats(hours \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours, :hour)

    from(c in Context,
      where: c.started >= ^cutoff,
      select: %{
        total_count: count(c.started),
        total_duration: sum(c.duration),
        unique_sessions: count(c.session, :distinct),
        avg_duration: avg(c.duration)
      }
    )
    |> Repo.one()
  end

  @doc """
  Gets sentiment distribution for recent contexts.
  """
  @spec get_sentiment_distribution(pos_integer()) :: [%{sentiment: String.t(), count: integer()}]
  def get_sentiment_distribution(hours \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours, :hour)

    from(c in Context,
      where: c.started >= ^cutoff and not is_nil(c.sentiment),
      group_by: c.sentiment,
      select: %{sentiment: c.sentiment, count: count(c.started)}
    )
    |> Repo.all()
  end

  @doc """
  Gets most common topics from recent contexts.
  """
  @spec get_popular_topics(pos_integer(), pos_integer()) :: [%{topic: String.t(), count: integer()}]
  def get_popular_topics(hours \\ 24, limit \\ 10) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours, :hour)

    # Use PostgreSQL array functions to unnest topics and count them
    from(c in Context,
      where: c.started >= ^cutoff and not is_nil(c.topics),
      select: %{
        topic: fragment("unnest(?)", c.topics),
        count: count(c.started)
      },
      group_by: fragment("unnest(?)", c.topics),
      order_by: [desc: count(c.started)],
      limit: ^limit
    )
    |> Repo.all()
  end

  ## AI Training Data Export

  @doc """
  Exports contexts for AI training in a structured format.
  """
  @spec export_training_data(context_opts()) :: [map()]
  def export_training_data(opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000) |> min(5000)
    session = Keyword.get(opts, :session)

    query =
      from(c in Context,
        select: %{
          timestamp: c.started,
          session: c.session,
          duration: c.duration,
          transcript: c.transcript,
          chat: c.chat,
          interactions: c.interactions,
          emotes: c.emotes,
          patterns: c.patterns,
          sentiment: c.sentiment,
          topics: c.topics
        },
        order_by: [asc: c.started],
        limit: ^limit
      )

    query =
      if session do
        from(q in query, where: q.session == ^session)
      else
        query
      end

    Repo.all(query)
  end

  ## Cleanup Operations

  @doc """
  Deletes old contexts beyond the retention period.
  """
  @spec delete_old_contexts(pos_integer()) :: {integer(), nil}
  def delete_old_contexts(days_to_keep \\ 90) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_to_keep, :day)

    from(c in Context,
      where: c.started < ^cutoff
    )
    |> Repo.delete_all()
  end
end
