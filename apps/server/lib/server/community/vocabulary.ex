defmodule Server.Community.Vocabulary do
  @moduledoc """
  Ecto schema for community vocabulary tracking.

  Stores community-specific phrases, inside jokes, memes, and catchphrases
  for context analysis and stream interaction insights.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @categories ["meme", "inside_joke", "catchphrase", "emote_phrase", "reference", "slang"]

  schema "community_vocabulary" do
    field :phrase, :string
    field :category, :string
    field :definition, :string
    field :context, :string
    field :first_used, :utc_datetime_usec
    field :usage_count, :integer, default: 1
    field :tags, {:array, :string}, default: []
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(community_vocabulary, attrs) do
    community_vocabulary
    |> cast(attrs, [
      :phrase,
      :category,
      :definition,
      :context,
      :first_used,
      :usage_count,
      :tags,
      :active
    ])
    |> validate_required([:phrase, :category])
    |> validate_length(:phrase, min: 1, max: 500)
    |> validate_inclusion(:category, @categories)
    |> validate_length(:definition, max: 1000)
    |> validate_length(:context, max: 1000)
    |> validate_number(:usage_count, greater_than: 0)
    |> validate_tags()
    |> normalize_phrase()
    |> unique_constraint(:phrase)
  end

  @doc """
  Creates a changeset for a new vocabulary entry.
  """
  def create_changeset(attrs) do
    attrs_with_defaults =
      attrs
      |> Map.put_new(:first_used, DateTime.utc_now())
      |> Map.put_new(:usage_count, 1)
      |> Map.put_new(:active, true)

    %__MODULE__{}
    |> changeset(attrs_with_defaults)
  end

  @doc """
  Creates a changeset for incrementing usage count.
  """
  def increment_usage_changeset(vocabulary) do
    vocabulary
    |> cast(%{usage_count: vocabulary.usage_count + 1}, [:usage_count])
    |> validate_number(:usage_count, greater_than: 0)
  end

  @doc """
  Creates a changeset for updating definition and context.
  """
  def update_definition_changeset(vocabulary, attrs) do
    vocabulary
    |> cast(attrs, [:definition, :context, :tags])
    |> validate_length(:definition, max: 1000)
    |> validate_length(:context, max: 1000)
    |> validate_tags()
  end

  @doc """
  Gets all valid categories.
  """
  def categories, do: @categories

  @doc """
  Normalizes phrase for consistent storage and searching.
  """
  def normalize_phrase_text(phrase) when is_binary(phrase) do
    phrase
    |> String.trim()
    |> String.downcase()
  end

  def normalize_phrase_text(_), do: nil

  @doc """
  Validates if a phrase might be community vocabulary.
  """
  def potential_vocabulary?(phrase) when is_binary(phrase) do
    normalized = normalize_phrase_text(phrase)
    # Basic heuristics for potential community vocab
    String.length(normalized) >= 2 and
      String.length(normalized) <= 100 and
      not boring_phrase?(normalized)
  end

  def potential_vocabulary?(_), do: false

  # Private validation functions

  defp validate_tags(changeset) do
    case get_field(changeset, :tags) do
      nil ->
        changeset

      tags when is_list(tags) ->
        if Enum.all?(tags, &valid_tag?/1) do
          changeset
        else
          add_error(changeset, :tags, "contains invalid tags")
        end

      _ ->
        add_error(changeset, :tags, "must be a list of strings")
    end
  end

  defp valid_tag?(tag) when is_binary(tag) do
    String.length(String.trim(tag)) >= 1 and String.length(tag) <= 50
  end

  defp valid_tag?(_), do: false

  defp normalize_phrase(changeset) do
    case get_field(changeset, :phrase) do
      phrase when is_binary(phrase) ->
        put_change(changeset, :phrase, normalize_phrase_text(phrase))

      _ ->
        changeset
    end
  end

  defp boring_phrase?(phrase) do
    # Filter out common words that aren't interesting vocabulary
    boring_words = [
      "the",
      "and",
      "or",
      "but",
      "is",
      "are",
      "was",
      "were",
      "a",
      "an",
      "to",
      "for",
      "of",
      "in",
      "on",
      "at",
      "by",
      "yes",
      "no",
      "ok",
      "okay",
      "sure",
      "thanks",
      "thank you"
    ]

    phrase in boring_words
  end
end
