defmodule Server.Community.Pronunciation do
  @moduledoc """
  Ecto schema for pronunciation overrides.

  Stores custom phonetic pronunciations for usernames to improve
  transcription accuracy when streamer mentions community members.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "pronunciation_overrides" do
    field :username, :string
    field :phonetic, :string
    field :confidence, :float, default: 1.0
    field :created_by, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(pronunciation_override, attrs) do
    pronunciation_override
    |> cast(attrs, [:username, :phonetic, :confidence, :created_by, :active])
    |> validate_required([:username, :phonetic])
    |> validate_length(:username, min: 1, max: 255)
    |> validate_length(:phonetic, min: 1, max: 500)
    |> validate_length(:created_by, max: 255)
    |> validate_number(:confidence, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> unique_constraint(:username)
  end

  @doc """
  Creates a changeset for a new pronunciation override.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Creates a changeset for updating an existing pronunciation override.
  """
  def update_changeset(pronunciation_override, attrs) do
    pronunciation_override
    |> changeset(attrs)
  end

  @doc """
  Formats phonetic text for consistency.
  """
  def format_phonetic(phonetic) when is_binary(phonetic) do
    phonetic
    |> String.trim()
    |> String.downcase()
  end

  def format_phonetic(_), do: nil

  @doc """
  Validates phonetic format (basic validation for common patterns).
  """
  def valid_phonetic?(phonetic) when is_binary(phonetic) do
    # Basic validation: check for reasonable length and characters
    formatted = format_phonetic(phonetic)
    String.length(formatted) >= 1 and String.length(formatted) <= 100
  end

  def valid_phonetic?(_), do: false
end
