defmodule Server.ActivityLog.Event do
  @moduledoc """
  Ecto schema for activity log events using TimescaleDB hypertables.

  This schema represents individual events (chat messages, follows, subs, etc.)
  for the real-time Activity Log interface. Events are stored in TimescaleDB
  for optimal time-series performance.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {JSON.Encoder,
           only: [
             :id,
             :timestamp,
             :event_type,
             :user_id,
             :user_login,
             :user_name,
             :data,
             :correlation_id
           ]}

  @type t :: %__MODULE__{
          id: String.t(),
          timestamp: DateTime.t(),
          event_type: String.t(),
          user_id: String.t() | nil,
          user_login: String.t() | nil,
          user_name: String.t() | nil,
          data: map(),
          correlation_id: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "events" do
    field :timestamp, :utc_datetime_usec
    field :event_type, :string
    field :user_id, :string
    field :user_login, :string
    field :user_name, :string
    field :data, :map
    field :correlation_id, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for event validation.

  ## Examples

      iex> changeset(%Event{}, %{timestamp: DateTime.utc_now(), event_type: "channel.chat.message", data: %{}})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Event{}, %{event_type: "", data: nil})
      %Ecto.Changeset{valid?: false}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :timestamp,
      :event_type,
      :user_id,
      :user_login,
      :user_name,
      :data,
      :correlation_id
    ])
    |> validate_required([:timestamp, :event_type, :data])
    |> validate_length(:event_type, min: 1, max: 100)
    |> validate_length(:user_id, max: 50)
    |> validate_length(:user_login, max: 25)
    |> validate_length(:user_name, max: 25)
    |> validate_length(:correlation_id, max: 50)
    |> validate_event_type()
    |> validate_data_structure()
  end

  # Validate that event_type follows expected patterns
  defp validate_event_type(changeset) do
    event_type = get_field(changeset, :event_type)

    valid_event_types = [
      "channel.chat.message",
      "channel.chat.clear",
      "channel.chat.message_delete",
      "channel.follow",
      "channel.subscribe",
      "channel.subscription.gift",
      "channel.cheer",
      "channel.update",
      "stream.online",
      "stream.offline"
    ]

    if event_type && event_type not in valid_event_types do
      add_error(changeset, :event_type, "unsupported event type")
    else
      changeset
    end
  end

  # Validate that data is a proper map structure
  defp validate_data_structure(changeset) do
    data = get_field(changeset, :data)

    cond do
      not is_map(data) ->
        add_error(changeset, :data, "must be a map")

      map_size(data) == 0 ->
        add_error(changeset, :data, "cannot be empty")

      true ->
        changeset
    end
  end
end
