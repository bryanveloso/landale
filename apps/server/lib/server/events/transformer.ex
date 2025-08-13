defmodule Server.Events.Transformer do
  @moduledoc """
  Transforms events at system boundaries.

  This is the ONLY place where event format conversion happens.
  All events entering or leaving the system pass through this module
  to ensure consistent data structures throughout Landale.

  ## Core Responsibility

  Transform events between external formats and the unified internal format:
  - **Input boundaries**: Convert external events → UnifiedEvent
  - **Output boundaries**: Convert UnifiedEvent → external formats

  ## Design Principles

  1. **Single Responsibility**: Only handles format transformation
  2. **Boundary Isolation**: External formats stay at boundaries
  3. **Lossless Conversion**: Preserve all relevant data during transformation
  4. **Schema Awareness**: Understand each external format's structure

  ## Usage

      # Transform incoming Twitch event
      event = Transformer.from_twitch("channel.follow", twitch_payload)

      # Transform for WebSocket output
      ws_data = Transformer.for_websocket(unified_event)

  """

  alias Server.Events.Event
  require Logger

  # Twitch EventSub Transformations

  @doc """
  Transforms incoming Twitch EventSub events into unified format.

  Handles all Twitch EventSub event types including:
  - Chat messages (channel.chat.message)
  - Subscriptions (channel.subscribe)
  - Follows (channel.follow)
  - Stream events (stream.online/offline)
  - And more...

  ## Parameters

  - `event_type` - Twitch EventSub event type
  - `event_data` - Raw EventSub payload

  ## Examples

      data = %{
        "user_id" => "12345",
        "user_name" => "viewer123",
        "followed_at" => "2025-08-13T12:00:00Z"
      }
      event = Transformer.from_twitch("channel.follow", data)

  """
  @spec from_twitch(String.t(), map()) :: Event.t()
  def from_twitch(event_type, event_data) do
    # Normalize the Twitch data based on event type
    normalized_data = normalize_twitch_data(event_type, event_data)

    # Extract event ID if available
    event_id = extract_twitch_event_id(event_type, event_data)

    # Extract timestamp if available
    timestamp = extract_twitch_timestamp(event_data)

    Event.new(
      event_type,
      :twitch,
      normalized_data,
      id: event_id,
      timestamp: timestamp
    )
  end

  @doc """
  Transforms incoming OBS WebSocket events into unified format.

  Handles OBS WebSocket events like:
  - Stream started/stopped
  - Scene changes
  - Source visibility changes
  - Recording events

  ## Parameters

  - `event_type` - OBS event type
  - `event_data` - Raw OBS event payload

  """
  @spec from_obs(String.t(), map()) :: Event.t()
  def from_obs(event_type, event_data) do
    # Prefix OBS events with "obs." for clarity
    unified_type = "obs.#{event_type}"

    Event.new(
      unified_type,
      :obs,
      event_data
    )
  end

  @doc """
  Transforms system events into unified format.

  Used for internal Landale events like:
  - Service startup/shutdown
  - Health check results
  - Performance metrics

  """
  @spec from_system(String.t(), map(), keyword()) :: Event.t()
  def from_system(event_type, event_data, opts \\ []) do
    # System events can include priority and correlation info
    priority = Keyword.get(opts, :priority, :normal)
    correlation_id = Keyword.get(opts, :correlation_id)

    Event.new(
      "system.#{event_type}",
      :system,
      event_data,
      priority: priority,
      correlation_id: correlation_id
    )
  end

  @doc """
  Transforms IronMON events into unified format.

  Handles Pokémon IronMON challenge tracking events.
  """
  @spec from_ironmon(String.t(), map()) :: Event.t()
  def from_ironmon(event_type, event_data) do
    Event.new(
      "ironmon.#{event_type}",
      :ironmon,
      event_data
    )
  end

  @doc """
  Transforms Rainwave music events into unified format.

  Handles music streaming events from Rainwave.
  """
  @spec from_rainwave(String.t(), map()) :: Event.t()
  def from_rainwave(event_type, event_data) do
    Event.new(
      "rainwave.#{event_type}",
      :rainwave,
      event_data
    )
  end

  # Output Transformations

  @doc """
  Transforms unified event for WebSocket output.

  Converts to the format expected by WebSocket clients.
  Maintains backward compatibility with existing client code.

  ## Output Format

      %{
        id: "evt_abc123",
        type: "channel.follow",
        data: %{user_name: "viewer123"},
        timestamp: 1691932800
      }

  """
  @spec for_websocket(Event.t()) :: map()
  def for_websocket(%Event{} = event) do
    %{
      id: event.id,
      type: event.type,
      data: event.data,
      timestamp: DateTime.to_unix(event.timestamp)
    }
  end

  @doc """
  Transforms unified event for database storage.

  Converts to format suitable for PostgreSQL storage,
  including JSON encoding of nested data.

  ## Output Format

  Suitable for insertion into the activity_log_events table.
  """
  @spec for_database(Event.t()) :: map()
  def for_database(%Event{} = event) do
    %{
      id: event.id,
      type: event.type,
      source: to_string(event.source),
      data: Jason.encode!(event.data),
      metadata: Jason.encode!(event.meta),
      occurred_at: event.timestamp,
      processed_at: event.meta.processed_at
    }
  end

  @doc """
  Transforms unified event for ActivityLog storage.

  Converts to format expected by ActivityLog.Event schema.
  """
  @spec for_activity_log(Event.t()) :: map()
  def for_activity_log(%Event{} = event) do
    %{
      timestamp: event.timestamp,
      event_type: event.type,
      user_id: extract_user_field(event.data, :user_id),
      user_login: extract_user_field(event.data, :user_login),
      user_name: extract_user_field(event.data, :user_name),
      data: event.data,
      correlation_id: event.meta.correlation_id
    }
  end

  # Extract user fields from event data (handles both string and atom keys)
  defp extract_user_field(data, field) when is_map(data) do
    Map.get(data, field) || Map.get(data, to_string(field))
  end

  defp extract_user_field(_data, _field), do: nil

  @doc """
  Transforms unified event for external API calls.

  Used when forwarding events to external services.
  """
  @spec for_external_api(Event.t()) :: map()
  def for_external_api(%Event{} = event) do
    %{
      event_id: event.id,
      event_type: event.type,
      source: event.source,
      payload: event.data,
      timestamp: DateTime.to_iso8601(event.timestamp),
      correlation_id: event.meta.correlation_id
    }
  end

  # Private Normalization Functions

  # Normalize Twitch EventSub data based on event type
  defp normalize_twitch_data("channel.chat.message", data) do
    %{
      user_id: Map.get(data, "chatter_user_id") || Map.get(data, "user_id"),
      user_name: Map.get(data, "chatter_user_name") || Map.get(data, "user_name"),
      user_login: Map.get(data, "chatter_user_login") || Map.get(data, "user_login"),
      message: Map.get(data, "message", %{}),
      message_id: Map.get(data, "message_id"),
      broadcaster_user_id: Map.get(data, "broadcaster_user_id"),
      broadcaster_user_name: Map.get(data, "broadcaster_user_name"),
      broadcaster_user_login: Map.get(data, "broadcaster_user_login"),
      # Extract emote data
      emotes: extract_emotes_from_message(data),
      native_emotes: extract_native_emotes_from_message(data),
      # Add any custom fields from the message
      color: get_in(data, ["message", "color"]),
      badges: get_in(data, ["message", "badges"]) || [],
      fragments: get_in(data, ["message", "fragments"]) || []
    }
  end

  defp normalize_twitch_data("channel.follow", data) do
    %{
      user_id: Map.get(data, "user_id"),
      user_name: Map.get(data, "user_name"),
      user_login: Map.get(data, "user_login"),
      broadcaster_user_id: Map.get(data, "broadcaster_user_id"),
      broadcaster_user_name: Map.get(data, "broadcaster_user_name"),
      broadcaster_user_login: Map.get(data, "broadcaster_user_login"),
      followed_at: Map.get(data, "followed_at")
    }
  end

  defp normalize_twitch_data("channel.subscribe", data) do
    %{
      user_id: Map.get(data, "user_id"),
      user_name: Map.get(data, "user_name"),
      user_login: Map.get(data, "user_login"),
      broadcaster_user_id: Map.get(data, "broadcaster_user_id"),
      broadcaster_user_name: Map.get(data, "broadcaster_user_name"),
      broadcaster_user_login: Map.get(data, "broadcaster_user_login"),
      tier: Map.get(data, "tier"),
      is_gift: Map.get(data, "is_gift", false),
      cumulative_months: Map.get(data, "cumulative_months"),
      streak_months: Map.get(data, "streak_months"),
      duration_months: Map.get(data, "duration_months")
    }
  end

  defp normalize_twitch_data("channel.subscription.gift", data) do
    %{
      user_id: Map.get(data, "user_id"),
      user_name: Map.get(data, "user_name"),
      user_login: Map.get(data, "user_login"),
      broadcaster_user_id: Map.get(data, "broadcaster_user_id"),
      broadcaster_user_name: Map.get(data, "broadcaster_user_name"),
      broadcaster_user_login: Map.get(data, "broadcaster_user_login"),
      total: Map.get(data, "total"),
      tier: Map.get(data, "tier"),
      cumulative_total: Map.get(data, "cumulative_total"),
      is_anonymous: Map.get(data, "is_anonymous", false)
    }
  end

  defp normalize_twitch_data("channel.cheer", data) do
    %{
      user_id: Map.get(data, "user_id"),
      user_name: Map.get(data, "user_name"),
      user_login: Map.get(data, "user_login"),
      broadcaster_user_id: Map.get(data, "broadcaster_user_id"),
      broadcaster_user_name: Map.get(data, "broadcaster_user_name"),
      broadcaster_user_login: Map.get(data, "broadcaster_user_login"),
      is_anonymous: Map.get(data, "is_anonymous", false),
      message: Map.get(data, "message"),
      bits: Map.get(data, "bits")
    }
  end

  defp normalize_twitch_data("stream.online", data) do
    %{
      id: Map.get(data, "id"),
      broadcaster_user_id: Map.get(data, "broadcaster_user_id"),
      broadcaster_user_name: Map.get(data, "broadcaster_user_name"),
      broadcaster_user_login: Map.get(data, "broadcaster_user_login"),
      type: Map.get(data, "type"),
      started_at: Map.get(data, "started_at")
    }
  end

  defp normalize_twitch_data("stream.offline", data) do
    %{
      broadcaster_user_id: Map.get(data, "broadcaster_user_id"),
      broadcaster_user_name: Map.get(data, "broadcaster_user_name"),
      broadcaster_user_login: Map.get(data, "broadcaster_user_login")
    }
  end

  defp normalize_twitch_data("channel.update", data) do
    %{
      broadcaster_user_id: Map.get(data, "broadcaster_user_id"),
      broadcaster_user_name: Map.get(data, "broadcaster_user_name"),
      broadcaster_user_login: Map.get(data, "broadcaster_user_login"),
      title: Map.get(data, "title"),
      language: Map.get(data, "language"),
      category_id: Map.get(data, "category_id"),
      category_name: Map.get(data, "category_name"),
      content_classification_labels: Map.get(data, "content_classification_labels", [])
    }
  end

  # Fallback for unknown Twitch event types
  defp normalize_twitch_data(event_type, data) do
    Logger.warning("Unknown Twitch event type, using raw data",
      event_type: event_type,
      data_keys: Map.keys(data)
    )

    data
  end

  # Extract event ID from Twitch data
  defp extract_twitch_event_id("channel.chat.message", data) do
    Map.get(data, "message_id")
  end

  defp extract_twitch_event_id("stream.online", data) do
    Map.get(data, "id")
  end

  defp extract_twitch_event_id(_event_type, data) do
    Map.get(data, "id") || Map.get(data, "user_id")
  end

  # Extract timestamp from Twitch data
  defp extract_twitch_timestamp(data) do
    # Try various timestamp fields that Twitch uses
    timestamp_value =
      Map.get(data, "followed_at") ||
        Map.get(data, "started_at") ||
        Map.get(data, "created_at") ||
        Map.get(data, "timestamp")

    case timestamp_value do
      nil ->
        DateTime.utc_now()

      timestamp_str when is_binary(timestamp_str) ->
        case DateTime.from_iso8601(timestamp_str) do
          {:ok, datetime, _} -> datetime
          {:error, _} -> DateTime.utc_now()
        end

      timestamp_int when is_integer(timestamp_int) ->
        DateTime.from_unix!(timestamp_int)

      %DateTime{} = dt ->
        dt

      _ ->
        DateTime.utc_now()
    end
  end

  # Extract emote information from chat messages
  defp extract_emotes_from_message(data) do
    case get_in(data, ["message", "emotes"]) do
      emotes when is_list(emotes) ->
        Enum.map(emotes, fn emote ->
          %{
            id: Map.get(emote, "id"),
            name: Map.get(emote, "name"),
            format: Map.get(emote, "format", ["static"])
          }
        end)

      _ ->
        []
    end
  end

  defp extract_native_emotes_from_message(data) do
    # Extract native Twitch emotes from fragments
    case get_in(data, ["message", "fragments"]) do
      fragments when is_list(fragments) ->
        fragments
        |> Enum.filter(fn fragment ->
          fragment["type"] == "emote"
        end)
        |> Enum.map(fn emote_fragment ->
          Map.get(emote_fragment, "text")
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end
end
