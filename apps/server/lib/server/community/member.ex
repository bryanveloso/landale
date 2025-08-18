defmodule Server.Community.Member do
  @moduledoc """
  Ecto schema for community members tracking.

  Tracks active community members with their display names, activity stats,
  and custom pronunciation guides for transcription accuracy.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_members" do
    field :username, :string
    field :display_name, :string
    field :first_seen, :utc_datetime_usec
    field :last_seen, :utc_datetime_usec
    field :message_count, :integer, default: 0
    field :active, :boolean, default: true
    field :pronunciation_guide, :string
    field :notes, :string
    field :preferred_name, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(community_member, attrs) do
    community_member
    |> cast(attrs, [
      :username,
      :display_name,
      :first_seen,
      :last_seen,
      :message_count,
      :active,
      :pronunciation_guide,
      :notes,
      :preferred_name
    ])
    |> validate_required([:username, :first_seen, :last_seen])
    |> validate_length(:username, min: 1, max: 255)
    |> validate_length(:display_name, max: 255)
    |> validate_length(:pronunciation_guide, max: 500)
    |> validate_length(:notes, max: 1000)
    |> validate_length(:preferred_name, max: 255)
    |> validate_number(:message_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:username)
  end

  @doc """
  Creates a changeset for a new community member from a chat message.
  """
  def new_member_changeset(attrs) do
    now = DateTime.utc_now()

    attrs_with_defaults =
      attrs
      |> Map.put_new(:first_seen, now)
      |> Map.put_new(:last_seen, now)
      |> Map.put_new(:message_count, 1)
      |> Map.put_new(:active, true)

    %__MODULE__{}
    |> changeset(attrs_with_defaults)
  end

  @doc """
  Creates a changeset for updating activity stats.
  """
  def activity_changeset(community_member, attrs \\ %{}) do
    attrs_with_defaults =
      attrs
      |> Map.put_new(:last_seen, DateTime.utc_now())
      |> Map.put(:message_count, (community_member.message_count || 0) + 1)

    community_member
    |> cast(attrs_with_defaults, [:last_seen, :message_count, :display_name])
    |> validate_required([:last_seen, :message_count])
    |> validate_number(:message_count, greater_than_or_equal_to: 0)
  end

  @doc """
  Creates a changeset for updating pronunciation guide.
  """
  def pronunciation_changeset(community_member, pronunciation_guide) do
    community_member
    |> cast(%{pronunciation_guide: pronunciation_guide}, [:pronunciation_guide])
    |> validate_length(:pronunciation_guide, max: 500)
  end

  @doc """
  Creates a changeset for updating preferred name.
  """
  def preferred_name_changeset(community_member, preferred_name) do
    community_member
    |> cast(%{preferred_name: preferred_name}, [:preferred_name])
    |> validate_length(:preferred_name, max: 255)
  end
end
