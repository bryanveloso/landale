defmodule Server.Events.Event do
  @moduledoc """
  Event structure for Landale.

  All events use this format after entering the system.

  ## Fields

  - `id` - Unique event identifier
  - `type` - Event type string (e.g., "channel.follow", "obs.stream_started")
  - `source` - Source service (:twitch, :obs, :system, etc.)
  - `timestamp` - When the event occurred
  - `data` - Event payload
  - `meta` - Metadata (correlation_id, priority, etc.)

  ## Example

      event = Event.new("channel.follow", :twitch, %{user_name: "viewer123"})
      event.data.user_name  # => "viewer123"
      event.source          # => :twitch
  """

  @type source :: :twitch | :obs | :system | :ironmon | :rainwave | :test

  @type priority :: :critical | :normal

  @type meta :: %{
          correlation_id: String.t() | nil,
          batch_id: String.t() | nil,
          priority: priority(),
          processed_at: DateTime.t()
        }

  @type t :: %__MODULE__{
          # Core Fields (ALWAYS present)
          id: String.t(),
          type: String.t(),
          source: source(),
          timestamp: DateTime.t(),
          # Event Payload (ALWAYS at top level)
          data: map(),
          # Metadata (ALWAYS present)
          meta: meta()
        }

  defstruct [:id, :type, :source, :timestamp, :data, :meta]

  @doc """
  Creates a new event.

  ## Parameters

  - `type` - Event type string
  - `source` - Source service atom
  - `data` - Event payload
  - `opts` - Optional: :id, :timestamp, :correlation_id, :batch_id, :priority

  ## Examples

      Event.new("channel.follow", :twitch, %{user_name: "follower123"})

      Event.new("system.startup", :system, %{version: "1.0.0"},
        correlation_id: "req_123", priority: :critical)
  """
  @spec new(String.t(), source(), map(), keyword()) :: t()
  def new(type, source, data, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      type: type,
      source: source,
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now()),
      data: data,
      meta: build_metadata(opts)
    }
  end

  @doc """
  Converts legacy event formats to Event structure.

  Handles flat events (%{type: "...", user_name: "..."}) and
  nested events (%{type: "...", data: %{user_name: "..."}}).
  """
  @spec from_raw(map(), source(), keyword()) :: t()
  def from_raw(raw_event, source, opts \\ [])

  # Handle events that already have a :data field (nested structure)
  def from_raw(%{type: type, data: data} = raw, source, opts) when is_map(data) do
    # Extract timestamp if present
    timestamp =
      case Map.get(raw, :timestamp) do
        %DateTime{} = dt -> dt
        ts when is_integer(ts) -> DateTime.from_unix!(ts)
        _ -> DateTime.utc_now()
      end

    new(type, source, data, Keyword.merge([timestamp: timestamp], opts))
  end

  # Handle flat events (legacy format)
  def from_raw(%{type: type} = raw, source, opts) do
    # Remove type and other meta fields to create data payload
    data =
      raw
      |> Map.drop([:type, :timestamp, :correlation_id, :id])

    # Extract timestamp if present
    timestamp =
      case Map.get(raw, :timestamp) do
        %DateTime{} = dt -> dt
        ts when is_integer(ts) -> DateTime.from_unix!(ts)
        _ -> DateTime.utc_now()
      end

    new(type, source, data, Keyword.merge([timestamp: timestamp], opts))
  end

  # Handle events without explicit type (use provided type from opts)
  def from_raw(raw_event, source, opts) when is_map(raw_event) do
    type = Keyword.get(opts, :type, "unknown")
    new(type, source, raw_event, opts)
  end

  @doc "Returns true if event has critical priority."
  @spec critical?(t()) :: boolean()
  def critical?(%__MODULE__{meta: %{priority: :critical}}), do: true
  def critical?(_event), do: false

  @doc "Creates a batch event containing multiple events."
  @spec create_batch([t()], keyword()) :: t()
  def create_batch(events, opts \\ []) when is_list(events) do
    batch_id = Keyword.get(opts, :batch_id, generate_batch_id())

    new(
      "event.batch",
      :system,
      %{
        events: events,
        count: length(events)
      },
      Keyword.merge(opts, batch_id: batch_id, priority: :normal)
    )
  end

  # Private helper functions

  defp generate_id do
    "evt_" <> generate_uuid()
  end

  defp generate_batch_id do
    "batch_" <> generate_uuid()
  end

  defp generate_uuid do
    # Use the same UUID generation as correlation_id for consistency
    # This creates a short 8-character UUID suitable for Landale's single-user scale
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end

  defp build_metadata(opts) do
    %{
      correlation_id: Keyword.get(opts, :correlation_id),
      batch_id: Keyword.get(opts, :batch_id),
      priority: Keyword.get(opts, :priority, :normal),
      processed_at: DateTime.utc_now()
    }
  end
end
