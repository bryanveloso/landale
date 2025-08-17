defmodule Server.Correlation.Correlation do
  @moduledoc """
  Schema for chat-transcription correlations.

  Represents a detected correlation between streamer speech and viewer chat responses.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @pattern_types ~w(direct_quote keyword_echo emote_reaction question_response temporal_only)

  schema "correlations" do
    field :transcription_id, :binary_id
    field :transcription_text, :string
    field :chat_message_id, :string
    field :chat_user, :string
    field :chat_text, :string
    field :pattern_type, :string
    field :confidence, :float
    field :time_offset_ms, :integer
    field :detected_keywords, {:array, :string}, default: []
    field :session_id, :binary_id
    field :created_at, :utc_datetime_usec
  end

  @required_fields ~w(transcription_id transcription_text chat_message_id
                      chat_user chat_text pattern_type confidence time_offset_ms)a
  @optional_fields ~w(detected_keywords session_id)a

  def changeset(correlation, attrs) do
    correlation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:pattern_type, @pattern_types)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:time_offset_ms, greater_than_or_equal_to: 0)
  end
end
