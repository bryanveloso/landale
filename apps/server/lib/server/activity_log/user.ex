defmodule Server.ActivityLog.User do
  @moduledoc """
  Ecto schema for user metadata in the activity log system.

  This schema stores user information from Twitch along with Bryan's custom
  metadata like nicknames, pronouns, and notes about community members.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {JSON.Encoder,
           only: [
             :twitch_id,
             :login,
             :display_name,
             :nickname,
             :pronouns,
             :notes
           ]}

  @type t :: %__MODULE__{
          twitch_id: String.t(),
          login: String.t(),
          display_name: String.t() | nil,
          nickname: String.t() | nil,
          pronouns: String.t() | nil,
          notes: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:twitch_id, :string, autogenerate: false}

  schema "users" do
    field :login, :string
    field :display_name, :string
    field :nickname, :string
    field :pronouns, :string
    field :notes, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for user validation.

  ## Examples

      iex> changeset(%User{}, %{twitch_id: "123456", login: "username"})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%User{}, %{twitch_id: "", login: ""})
      %Ecto.Changeset{valid?: false}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :twitch_id,
      :login,
      :display_name,
      :nickname,
      :pronouns,
      :notes
    ])
    |> validate_required([:twitch_id, :login])
    |> validate_length(:twitch_id, min: 1, max: 50)
    |> validate_length(:login, min: 1, max: 25)
    |> validate_length(:display_name, max: 25)
    |> validate_length(:nickname, max: 50)
    |> validate_length(:pronouns, max: 20)
    |> validate_length(:notes, max: 500)
    |> validate_format(:login, ~r/^[a-zA-Z0-9_]+$/, message: "must contain only alphanumeric characters and underscores")
    |> unique_constraint(:login)
    |> unique_constraint(:twitch_id, name: :users_pkey)
  end

  @doc """
  Creates a changeset for updating user metadata (nickname, pronouns, notes).
  This is used when Bryan manually assigns custom information to users.
  """
  @spec metadata_changeset(t(), map()) :: Ecto.Changeset.t()
  def metadata_changeset(user, attrs) do
    user
    |> cast(attrs, [:nickname, :pronouns, :notes])
    |> validate_length(:nickname, max: 50)
    |> validate_length(:pronouns, max: 20)
    |> validate_length(:notes, max: 500)
  end
end