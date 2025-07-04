defmodule Server.Context.Context do
  @moduledoc """
  Ecto schema for SEED memory contexts using TimescaleDB hypertables.

  This schema represents 2-minute aggregated contexts containing transcriptions,
  chat interactions, emotes, and AI-generated insights for training data.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {JSON.Encoder,
           only: [
             :started,
             :ended,
             :session,
             :transcript,
             :duration,
             :chat,
             :interactions,
             :emotes,
             :patterns,
             :sentiment,
             :topics
           ]}

  @type t :: %__MODULE__{
          started: DateTime.t(),
          ended: DateTime.t(),
          session: String.t(),
          transcript: String.t(),
          duration: float(),
          chat: map() | nil,
          interactions: map() | nil,
          emotes: map() | nil,
          patterns: map() | nil,
          sentiment: String.t() | nil,
          topics: [String.t()] | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "contexts" do
    field :started, :utc_datetime_usec
    field :ended, :utc_datetime_usec
    field :session, :string
    field :transcript, :string
    field :duration, :float
    field :chat, :map
    field :interactions, :map
    field :emotes, :map
    field :patterns, :map
    field :sentiment, :string
    field :topics, {:array, :string}

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for context validation.

  ## Examples

      iex> changeset(%Context{}, %{started: DateTime.utc_now(), ended: DateTime.utc_now(), session: "stream_2024_01_15", transcript: "Hello world", duration: 120.0})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Context{}, %{transcript: "", duration: -1.0})
      %Ecto.Changeset{valid?: false}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(context, attrs) do
    context
    |> cast(attrs, [
      :started,
      :ended,
      :session,
      :transcript,
      :duration,
      :chat,
      :interactions,
      :emotes,
      :patterns,
      :sentiment,
      :topics
    ])
    |> validate_required([:started, :ended, :session, :transcript, :duration])
    |> validate_number(:duration, greater_than: 0.0)
    |> validate_length(:transcript, min: 1, max: 50_000)
    |> validate_length(:session, min: 1, max: 100)
    |> validate_inclusion(:sentiment, ["positive", "negative", "neutral"])
    |> validate_time_order()
  end

  defp validate_time_order(changeset) do
    started = get_field(changeset, :started)
    ended = get_field(changeset, :ended)

    if started && ended && DateTime.compare(started, ended) != :lt do
      add_error(changeset, :ended, "must be after started time")
    else
      changeset
    end
  end
end
