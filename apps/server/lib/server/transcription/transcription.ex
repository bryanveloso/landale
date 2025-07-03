defmodule Server.Transcription.Transcription do
  @moduledoc """
  Ecto schema for audio transcriptions using TimescaleDB hypertables.

  This schema represents individual transcription events from the AI audio processing
  pipeline, optimized for time-series queries with TimescaleDB.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [:id, :timestamp, :duration, :text, :source_id, :stream_session_id, :confidence, :metadata]}

  @type t :: %__MODULE__{
          id: binary(),
          timestamp: DateTime.t(),
          duration: float(),
          text: String.t(),
          source_id: String.t() | nil,
          stream_session_id: String.t() | nil,
          confidence: float() | nil,
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "transcriptions" do
    field :timestamp, :utc_datetime_usec
    field :duration, :float
    field :text, :string
    field :source_id, :string
    field :stream_session_id, :string
    field :confidence, :float
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for transcription validation.

  ## Examples

      iex> changeset(%Transcription{}, %{text: "Hello", duration: 1.5, timestamp: DateTime.utc_now()})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Transcription{}, %{text: "", duration: -1.0})
      %Ecto.Changeset{valid?: false}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(transcription, attrs) do
    transcription
    |> cast(attrs, [:timestamp, :duration, :text, :source_id, :stream_session_id, :confidence, :metadata])
    |> validate_required([:timestamp, :duration, :text])
    |> validate_number(:duration, greater_than: 0.0)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_length(:text, min: 1, max: 10_000)
  end
end
