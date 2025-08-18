defmodule Server.Community do
  @moduledoc """
  Community context for managing community members, pronunciation guides,
  username aliases, and community vocabulary.

  This module provides functions for tracking active community members,
  managing pronunciation overrides for transcription accuracy, and
  building a community vocabulary database for context analysis.
  """

  import Ecto.Query, warn: false
  alias Server.Repo

  alias Server.Community.{
    Member,
    Pronunciation,
    Vocabulary
  }

  ## Community Members

  @doc """
  Gets a community member by username.
  """
  def get_community_member(username) when is_binary(username) do
    normalized_username = String.downcase(String.trim(username))

    Repo.one(
      from m in Member,
        where: fragment("LOWER(?)", m.username) == ^normalized_username
    )
  end

  @doc """
  Gets a community member by ID.
  """
  def get_community_member!(id), do: Repo.get!(Member, id)

  @doc """
  Creates or updates a community member from a chat message.
  """
  def upsert_community_member(username, display_name \\ nil) do
    case get_community_member(username) do
      nil ->
        create_community_member(%{
          username: username,
          display_name: display_name
        })

      member ->
        update_member_activity(member, %{display_name: display_name})
    end
  end

  @doc """
  Creates a new community member.
  """
  def create_community_member(attrs \\ %{}) do
    Member.new_member_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates community member activity stats.
  """
  def update_member_activity(member, attrs \\ %{}) do
    Member.activity_changeset(member, attrs)
    |> Repo.update()
  end

  @doc """
  Updates community member pronunciation guide.
  """
  def update_member_pronunciation(member, pronunciation_guide) do
    Member.pronunciation_changeset(member, pronunciation_guide)
    |> Repo.update()
  end

  @doc """
  Lists active community members, ordered by recent activity.
  """
  def list_active_community_members(limit \\ 50) do
    Repo.all(
      from m in Member,
        where: m.active == true,
        order_by: [desc: m.last_seen],
        limit: ^limit
    )
  end

  @doc """
  Gets community member statistics.
  """
  def get_community_stats do
    active_count_query =
      from m in Member,
        where: m.active == true,
        select: count(m.id)

    total_messages_query =
      from m in Member,
        where: m.active == true,
        select: sum(m.message_count)

    recent_activity_query =
      from m in Member,
        where: m.active == true and m.last_seen >= ago(7, "day"),
        select: count(m.id)

    %{
      active_members: Repo.one(active_count_query) || 0,
      total_messages: Repo.one(total_messages_query) || 0,
      weekly_active: Repo.one(recent_activity_query) || 0
    }
  end

  ## Pronunciation Overrides

  @doc """
  Gets pronunciation override for a username.
  """
  def get_pronunciation_override(username) when is_binary(username) do
    normalized_username = String.downcase(String.trim(username))

    Repo.one(
      from p in Pronunciation,
        where: fragment("LOWER(?)", p.username) == ^normalized_username and p.active == true
    )
  end

  @doc """
  Creates a pronunciation override.
  """
  def create_pronunciation_override(attrs \\ %{}) do
    Pronunciation.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a pronunciation override.
  """
  def update_pronunciation_override(override, attrs) do
    Pronunciation.update_changeset(override, attrs)
    |> Repo.update()
  end

  @doc """
  Lists all active pronunciation overrides.
  """
  def list_pronunciation_overrides do
    Repo.all(
      from p in Pronunciation,
        where: p.active == true,
        order_by: [asc: p.username]
    )
  end

  @doc """
  Deletes a pronunciation override.
  """
  def delete_pronunciation_override(override) do
    Repo.delete(override)
  end

  ## Community Vocabulary

  @doc """
  Gets community vocabulary entry by phrase.
  """
  def get_vocabulary_entry(phrase) when is_binary(phrase) do
    normalized_phrase = Vocabulary.normalize_phrase_text(phrase)

    Repo.one(
      from v in Vocabulary,
        where: v.phrase == ^normalized_phrase and v.active == true
    )
  end

  @doc """
  Creates a community vocabulary entry.
  """
  def create_vocabulary_entry(attrs \\ %{}) do
    Vocabulary.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Increments vocabulary usage count.
  """
  def increment_vocabulary_usage(vocabulary) do
    Vocabulary.increment_usage_changeset(vocabulary)
    |> Repo.update()
  end

  @doc """
  Updates vocabulary definition and context.
  """
  def update_vocabulary_definition(vocabulary, attrs) do
    Vocabulary.update_definition_changeset(vocabulary, attrs)
    |> Repo.update()
  end

  @doc """
  Lists vocabulary entries by category.
  """
  def list_vocabulary_by_category(category, limit \\ 50) do
    Repo.all(
      from v in Vocabulary,
        where: v.category == ^category and v.active == true,
        order_by: [desc: v.usage_count],
        limit: ^limit
    )
  end

  @doc """
  Searches vocabulary entries by phrase or definition.
  """
  def search_vocabulary(query, limit \\ 25) do
    search_term = String.downcase(String.trim(query))

    Repo.all(
      from v in Vocabulary,
        where:
          v.active == true and
            (fragment("LOWER(?) LIKE ?", v.phrase, ^"%#{search_term}%") or
               fragment("LOWER(?) LIKE ?", v.definition, ^"%#{search_term}%")),
        order_by: [desc: v.usage_count],
        limit: ^limit
    )
  end

  @doc """
  Gets popular vocabulary entries.
  """
  def get_popular_vocabulary(limit \\ 20) do
    Repo.all(
      from v in Vocabulary,
        where: v.active == true,
        order_by: [desc: v.usage_count],
        limit: ^limit
    )
  end

  @doc """
  Gets recent vocabulary entries.
  """
  def get_recent_vocabulary(limit \\ 20) do
    Repo.all(
      from v in Vocabulary,
        where: v.active == true,
        order_by: [desc: v.first_used],
        limit: ^limit
    )
  end

  ## Utility Functions

  @doc """
  Processes a chat message for community tracking.

  Updates community member activity and detects potential vocabulary.
  """
  def process_chat_message(username, display_name, message) do
    # Update community member
    {:ok, member} = upsert_community_member(username, display_name)

    # Check for potential vocabulary in message
    potential_phrases = extract_potential_phrases(message)

    Enum.each(potential_phrases, fn phrase ->
      if Vocabulary.potential_vocabulary?(phrase) do
        case get_vocabulary_entry(phrase) do
          # Could create new entry based on frequency
          nil -> :ok
          vocab -> increment_vocabulary_usage(vocab)
        end
      end
    end)

    {:ok, member}
  end

  @doc """
  Gets pronunciation guide for a username.

  Checks pronunciation overrides first, then community member guides.
  """
  def get_pronunciation_guide(username) do
    case get_pronunciation_override(username) do
      %{phonetic: phonetic} ->
        phonetic

      nil ->
        case get_community_member(username) do
          %{pronunciation_guide: guide} when is_binary(guide) -> guide
          _ -> nil
        end
    end
  end

  # Private helper functions

  defp extract_potential_phrases(message) when is_binary(message) do
    # Simple phrase extraction - could be enhanced with NLP
    message
    |> String.downcase()
    |> String.split(~r/[^\w\s]/, trim: true)
    |> Enum.flat_map(&String.split(&1, " ", trim: true))
    |> Enum.filter(&(String.length(&1) >= 3))
    |> Enum.uniq()
  end

  defp extract_potential_phrases(_), do: []
end
