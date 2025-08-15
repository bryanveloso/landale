defmodule Server.ActivityLog do
  @moduledoc """
  The ActivityLog module for managing activity events and user metadata.

  This module provides functions for storing and querying individual events
  (chat messages, follows, subs, etc.) and managing user metadata for the
  real-time Activity Log interface.
  """

  import Ecto.Query, warn: false
  alias Server.ActivityLog.{Event, User}
  alias Server.Repo

  @type event_opts :: [
          limit: pos_integer(),
          event_type: String.t() | nil,
          user_id: String.t() | nil
        ]

  ## Event Operations

  @doc """
  Stores a new event in the activity log.

  ## Parameters
  - `event_attrs` - Map containing event data from Server.Events

  ## Examples

      iex> store_event(%{
      ...>   timestamp: DateTime.utc_now(),
      ...>   event_type: "channel.chat.message",
      ...>   user_id: "123456",
      ...>   user_login: "testuser",
      ...>   user_name: "TestUser",
      ...>   data: %{message: "Hello world"},
      ...>   correlation_id: "abc123"
      ...> })
      {:ok, %Event{}}
  """
  @spec store_event(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def store_event(event_attrs) do
    %Event{}
    |> Event.changeset(event_attrs)
    |> Repo.insert()
  end

  @doc """
  Lists recent events with optional filtering.

  ## Options

    * `:limit` - Maximum number of results (default: 100, max: 1000)
    * `:event_type` - Filter by specific event type
    * `:user_id` - Filter by specific user ID

  ## Examples

      iex> list_recent_events(limit: 50)
      [%Event{}, ...]

      iex> list_recent_events(event_type: "channel.chat.message", limit: 25)
      [%Event{}, ...]
  """
  @spec list_recent_events(event_opts()) :: [Event.t()]
  def list_recent_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100) |> min(1000)
    event_type = Keyword.get(opts, :event_type)
    user_id = Keyword.get(opts, :user_id)

    query =
      from(e in Event,
        order_by: [desc: e.timestamp],
        limit: ^limit
      )

    query =
      if event_type do
        from(q in query, where: q.event_type == ^event_type)
      else
        query
      end

    query =
      if user_id do
        from(q in query, where: q.user_id == ^user_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Lists events within a specific time range.
  """
  @spec list_events_by_time_range(DateTime.t(), DateTime.t(), event_opts()) :: [Event.t()]
  def list_events_by_time_range(start_time, end_time, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)
    event_type = Keyword.get(opts, :event_type)

    query =
      from(e in Event,
        where: e.timestamp >= ^start_time and e.timestamp <= ^end_time,
        order_by: [asc: e.timestamp],
        limit: ^limit
      )

    query =
      if event_type do
        from(q in query, where: q.event_type == ^event_type)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets chat messages from the last N minutes.
  """
  @spec get_recent_chat_messages(pos_integer()) :: [Event.t()]
  def get_recent_chat_messages(minutes \\ 30) do
    current_time = DateTime.utc_now()
    cutoff = DateTime.add(current_time, -minutes, :minute)

    from(e in Event,
      where: e.timestamp >= ^cutoff and e.event_type == "channel.chat.message",
      order_by: [desc: e.timestamp]
    )
    |> Repo.all()
  end

  ## User Operations

  @doc """
  Creates or updates a user record.

  This function is called when we encounter a user in events to ensure
  we have their basic Twitch information stored.
  """
  @spec upsert_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def upsert_user(user_attrs) do
    %User{}
    |> User.changeset(user_attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:login, :display_name, :updated_at]},
      conflict_target: :twitch_id
    )
  end

  @doc """
  Gets a user by Twitch ID.
  """
  @spec get_user(String.t()) :: User.t() | nil
  def get_user(twitch_id) do
    Repo.get(User, twitch_id)
  end

  @doc """
  Gets a user by login.
  """
  @spec get_user_by_login(String.t()) :: User.t() | nil
  def get_user_by_login(login) do
    Repo.get_by(User, login: login)
  end

  @doc """
  Updates user metadata (nickname, pronouns, notes).
  This is used when Bryan manually assigns custom information.
  """
  @spec update_user_metadata(String.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_metadata(twitch_id, metadata_attrs) do
    case get_user(twitch_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        user
        |> User.metadata_changeset(metadata_attrs)
        |> Repo.update()
    end
  end

  @doc """
  Lists all users with custom metadata (nickname, pronouns, or notes).
  """
  @spec list_users_with_metadata() :: [User.t()]
  def list_users_with_metadata do
    from(u in User,
      where: not is_nil(u.nickname) or not is_nil(u.pronouns) or not is_nil(u.notes),
      order_by: [asc: u.login]
    )
    |> Repo.all()
  end

  ## Statistics and Analytics

  @doc """
  Gets activity statistics for the last N hours.
  """
  @spec get_activity_stats(pos_integer()) :: map()
  def get_activity_stats(hours \\ 24) do
    current_time = DateTime.utc_now()
    cutoff = DateTime.add(current_time, -hours, :hour)

    from(e in Event,
      where: e.timestamp >= ^cutoff,
      select: %{
        total_events: count(e.id),
        unique_users: count(e.user_id, :distinct),
        chat_messages: count(fragment("CASE WHEN ? = 'channel.chat.message' THEN 1 END", e.event_type)),
        follows: count(fragment("CASE WHEN ? = 'channel.follow' THEN 1 END", e.event_type)),
        subscriptions: count(fragment("CASE WHEN ? = 'channel.subscribe' THEN 1 END", e.event_type)),
        cheers: count(fragment("CASE WHEN ? = 'channel.cheer' THEN 1 END", e.event_type))
      }
    )
    |> Repo.one()
  end

  @doc """
  Gets the most active users by message count in the last N hours.
  """
  @spec get_most_active_users(pos_integer(), pos_integer()) :: [%{user_login: String.t(), message_count: integer()}]
  def get_most_active_users(hours \\ 24, limit \\ 10) do
    current_time = DateTime.utc_now()
    cutoff = DateTime.add(current_time, -hours, :hour)

    from(e in Event,
      where: e.timestamp >= ^cutoff and e.event_type == "channel.chat.message" and not is_nil(e.user_login),
      group_by: e.user_login,
      select: %{user_login: e.user_login, message_count: count(e.id)},
      order_by: [desc: count(e.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  ## Cleanup Operations

  @doc """
  Deletes old events beyond the retention period.
  """
  @spec delete_old_events(pos_integer()) :: {integer(), nil}
  def delete_old_events(days_to_keep \\ 90) do
    current_time = DateTime.utc_now()
    cutoff = DateTime.add(current_time, -days_to_keep, :day)

    from(e in Event,
      where: e.timestamp < ^cutoff
    )
    |> Repo.delete_all()
  end
end
