defmodule Server.Services.Twitch.EventHandler do
  @moduledoc """
  Twitch EventSub event processing and Phoenix PubSub publishing.

  Handles event type-specific processing of incoming Twitch EventSub notifications
  and publishes them to the Phoenix PubSub system for consumption by the dashboard
  and other subscribers.

  ## Features

  - Event type-specific processing and validation
  - Phoenix PubSub publishing for real-time updates
  - Telemetry integration for monitoring
  - Consistent event data normalization
  - Support for all common EventSub event types

  ## Event Types Handled

  - `stream.online` / `stream.offline` - Stream state changes
  - `channel.follow` - New followers
  - `channel.subscribe` - New subscribers
  - `channel.subscription.gift` - Gift subscriptions
  - `channel.cheer` - Bits cheered
  - `channel.update` - Channel information updates
  - `channel.chat.message` - Chat messages for correlation analysis
  - `channel.chat.clear` - Chat clearing events
  - `channel.chat.message_delete` - Message deletion events
  """

  require Logger
  alias Server.ActivityLog

  @doc """
  Processes an incoming EventSub notification event.

  ## Parameters
  - `event_type` - The EventSub event type (e.g. "stream.online")
  - `event_data` - The event payload data
  - `opts` - Processing options (currently unused)

  ## Returns
  - `:ok` - Event processed successfully
  - `{:error, reason}` - Processing failed
  """
  @spec process_event(binary(), map(), keyword()) :: :ok | {:error, term()}
  def process_event(event_type, event_data, _opts \\ []) do
    Logger.debug("Processing EventSub event",
      event_type: event_type,
      event_id: event_data["id"] || event_data["message_id"],
      event_data_keys: Map.keys(event_data || %{}),
      event_size: byte_size(:erlang.term_to_binary(event_data))
    )

    # Process event directly - Twitch validates their own data
    try do
      normalized_event = normalize_event(event_type, event_data)

      Logger.debug("Event normalized, storing in activity log", event_type: event_type)
      store_event_in_activity_log(event_type, normalized_event)

      Logger.debug("Event stored, publishing to PubSub", event_type: event_type)
      publish_event(event_type, normalized_event)

      Logger.debug("Event published, emitting telemetry", event_type: event_type)
      emit_telemetry(event_type, normalized_event)

      Logger.debug("EventSub event processed successfully",
        event_type: event_type,
        event_id: event_data["id"] || event_data["message_id"]
      )

      :ok
    rescue
      error ->
        Logger.error("Event processing failed",
          error: inspect(error),
          event_type: event_type,
          event_id: event_data["id"] || event_data["message_id"],
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        {:error, "Processing failed: #{inspect(error)}"}
    end
  end

  @doc """
  Normalizes event data into a consistent format.

  ## Parameters
  - `event_type` - The EventSub event type
  - `event_data` - Raw event data from Twitch

  ## Returns
  - Normalized event data map
  """
  @spec normalize_event(binary(), map()) :: map()
  def normalize_event(event_type, event_data) do
    base_event = %{
      type: event_type,
      id: event_data["id"],
      broadcaster_user_id: event_data["broadcaster_user_id"],
      broadcaster_user_login: event_data["broadcaster_user_login"],
      broadcaster_user_name: event_data["broadcaster_user_name"],
      timestamp: DateTime.utc_now()
    }

    case event_type do
      "stream.online" ->
        Map.merge(base_event, %{
          stream_id: event_data["id"],
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"],
          stream_type: event_data["type"],
          started_at: parse_datetime(event_data["started_at"])
        })

      "stream.offline" ->
        Map.merge(base_event, %{
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"]
        })

      "channel.follow" ->
        Map.merge(base_event, %{
          user_id: event_data["user_id"],
          user_login: event_data["user_login"],
          user_name: event_data["user_name"],
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"],
          followed_at: parse_datetime(event_data["followed_at"])
        })

      "channel.subscribe" ->
        Map.merge(base_event, %{
          user_id: event_data["user_id"],
          user_login: event_data["user_login"],
          user_name: event_data["user_name"],
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"],
          tier: event_data["tier"],
          is_gift: event_data["is_gift"] || false
        })

      "channel.subscription.gift" ->
        Map.merge(base_event, %{
          user_id: event_data["user_id"],
          user_login: event_data["user_login"],
          user_name: event_data["user_name"],
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"],
          tier: event_data["tier"],
          total: event_data["total"],
          cumulative_total: event_data["cumulative_total"],
          is_anonymous: event_data["is_anonymous"] || false
        })

      "channel.cheer" ->
        Map.merge(base_event, %{
          user_id: event_data["user_id"],
          user_login: event_data["user_login"],
          user_name: event_data["user_name"],
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"],
          is_anonymous: event_data["is_anonymous"] || false,
          bits: event_data["bits"],
          message: event_data["message"]
        })

      "channel.update" ->
        Map.merge(base_event, %{
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"],
          title: event_data["title"],
          language: event_data["language"],
          category_id: event_data["category_id"],
          category_name: event_data["category_name"],
          content_classification_labels: event_data["content_classification_labels"] || []
        })

      "channel.chat.message" ->
        fragments = event_data["message"]["fragments"] || []
        {emotes, native_emotes} = extract_emotes_from_fragments(fragments)

        Map.merge(base_event, %{
          message_id: event_data["message_id"],
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"],
          user_id: event_data["chatter_user_id"],
          user_login: event_data["chatter_user_login"],
          user_name: event_data["chatter_user_name"],
          message: event_data["message"]["text"],
          fragments: fragments,
          emotes: emotes,
          native_emotes: native_emotes,
          color: event_data["color"],
          badges: extract_badges(event_data["badges"]),
          message_type: event_data["message_type"],
          cheer: event_data["cheer"],
          reply: event_data["reply"],
          channel_points_custom_reward_id: event_data["channel_points_custom_reward_id"],
          source_broadcaster_user_id: event_data["source_broadcaster_user_id"],
          source_broadcaster_user_login: event_data["source_broadcaster_user_login"],
          source_broadcaster_user_name: event_data["source_broadcaster_user_name"],
          source_message_id: event_data["source_message_id"],
          source_badges: event_data["source_badges"]
        })

      "channel.chat.clear" ->
        Map.merge(base_event, %{
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"]
        })

      "channel.chat.message_delete" ->
        Map.merge(base_event, %{
          broadcaster_user_id: event_data["broadcaster_user_id"],
          broadcaster_user_login: event_data["broadcaster_user_login"],
          broadcaster_user_name: event_data["broadcaster_user_name"],
          target_user_id: event_data["target_user_id"],
          target_user_login: event_data["target_user_login"],
          target_user_name: event_data["target_user_name"],
          message_id: event_data["message_id"]
        })

      _ ->
        # For unknown event types, include all original data
        Map.merge(base_event, %{
          raw_data: event_data
        })
    end
  end

  @doc """
  Publishes a normalized event to Phoenix PubSub.

  ## Parameters
  - `event_type` - The EventSub event type
  - `normalized_event` - Normalized event data

  ## Returns
  - `:ok`
  """
  @spec publish_event(binary(), map()) :: :ok
  def publish_event(event_type, normalized_event) do
    # Publish to general dashboard topic
    Phoenix.PubSub.broadcast(Server.PubSub, "dashboard", {:twitch_event, normalized_event})

    # Publish to event-type-specific topic for targeted subscriptions
    Phoenix.PubSub.broadcast(Server.PubSub, "twitch:#{event_type}", {:event, normalized_event})

    # Publish to legacy topic structure for backward compatibility
    case event_type do
      "stream.online" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "stream_status", {:stream_online, normalized_event})

      "stream.offline" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "stream_status", {:stream_offline, normalized_event})

      "channel.follow" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "followers", {:new_follower, normalized_event})

      "channel.subscribe" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "subscriptions", {:new_subscription, normalized_event})

      "channel.subscription.gift" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "subscriptions", {:gift_subscription, normalized_event})

      "channel.cheer" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "cheers", {:new_cheer, normalized_event})

      "channel.chat.message" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "chat", {:chat_message, normalized_event})

      "channel.chat.clear" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "chat", {:chat_clear, normalized_event})

      "channel.chat.message_delete" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "chat", {:message_delete, normalized_event})

      "channel.update" ->
        Phoenix.PubSub.broadcast(Server.PubSub, "channel:updates", {:channel_update, normalized_event})

      _ ->
        # For other events, just use the general topic
        :ok
    end

    :ok
  end

  @doc """
  Emits telemetry events for monitoring.

  ## Parameters
  - `event_type` - The EventSub event type
  - `normalized_event` - Normalized event data

  ## Returns
  - `:ok`
  """
  @spec emit_telemetry(binary(), map()) :: :ok
  def emit_telemetry(event_type, normalized_event) do
    Server.Telemetry.twitch_event_received(event_type)

    # Emit specific telemetry for important events
    case event_type do
      "stream.online" ->
        :telemetry.execute([:server, :twitch, :stream, :online], %{count: 1}, %{
          broadcaster_id: normalized_event.broadcaster_user_id,
          stream_type: normalized_event.stream_type
        })

      "stream.offline" ->
        :telemetry.execute([:server, :twitch, :stream, :offline], %{count: 1}, %{
          broadcaster_id: normalized_event.broadcaster_user_id
        })

      "channel.follow" ->
        :telemetry.execute([:server, :twitch, :follow], %{count: 1}, %{
          broadcaster_id: normalized_event.broadcaster_user_id,
          follower_id: normalized_event.user_id
        })

      "channel.subscribe" ->
        :telemetry.execute([:server, :twitch, :subscription], %{count: 1}, %{
          broadcaster_id: normalized_event.broadcaster_user_id,
          subscriber_id: normalized_event.user_id,
          tier: normalized_event.tier,
          is_gift: normalized_event.is_gift
        })

      "channel.cheer" ->
        :telemetry.execute([:server, :twitch, :cheer], %{bits: normalized_event.bits}, %{
          broadcaster_id: normalized_event.broadcaster_user_id,
          user_id: normalized_event.user_id,
          is_anonymous: normalized_event.is_anonymous
        })

      "channel.chat.message" ->
        :telemetry.execute([:server, :twitch, :chat, :message], %{count: 1}, %{
          broadcaster_id: normalized_event.broadcaster_user_id,
          user_id: normalized_event.user_id,
          message_type: normalized_event.message_type,
          has_cheer: not is_nil(normalized_event.cheer),
          has_reply: not is_nil(normalized_event.reply)
        })

      "channel.chat.clear" ->
        :telemetry.execute([:server, :twitch, :chat, :clear], %{count: 1}, %{
          broadcaster_id: normalized_event.broadcaster_user_id
        })

      "channel.chat.message_delete" ->
        :telemetry.execute([:server, :twitch, :chat, :delete], %{count: 1}, %{
          broadcaster_id: normalized_event.broadcaster_user_id,
          target_user_id: normalized_event.target_user_id
        })

      _ ->
        :telemetry.execute([:server, :twitch, :event, :other], %{count: 1}, %{
          event_type: event_type,
          broadcaster_id: normalized_event.broadcaster_user_id
        })
    end

    :ok
  end

  # Private helper functions

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp extract_badges(nil), do: []

  defp extract_badges(badges) when is_list(badges) do
    Enum.map(badges, fn badge ->
      %{
        set_id: badge["set_id"],
        id: badge["id"],
        info: badge["info"]
      }
    end)
  end

  defp extract_badges(_), do: []

  # Extracts emotes and native emotes from Twitch message fragments.
  # Native emotes are those that start with "avalon" prefix.
  # Regular emotes are all other emotes.
  defp extract_emotes_from_fragments(fragments) when is_list(fragments) do
    emotes =
      fragments
      |> Enum.filter(fn fragment -> fragment["type"] == "emote" end)
      |> Enum.map(fn fragment -> fragment["text"] end)
      |> Enum.reject(&is_nil/1)

    {regular_emotes, native_emotes} =
      Enum.split_with(emotes, fn emote_text ->
        not String.starts_with?(emote_text, "avalon")
      end)

    {regular_emotes, native_emotes}
  end

  defp extract_emotes_from_fragments(_), do: {[], []}

  # Event processing helper functions

  # Stores an event in the ActivityLog database.
  # Only stores events that are valuable for the Activity Log interface.
  # Excludes ephemeral events that don't need long-term storage.
  @spec store_event_in_activity_log(binary(), map()) :: :ok
  defp store_event_in_activity_log(event_type, normalized_event) do
    Logger.debug("Checking if event should be stored",
      event_type: event_type,
      should_store: should_store_event?(event_type)
    )

    # Only store events that are valuable for the Activity Log
    if should_store_event?(event_type) do
      # Prepare event attributes for database storage
      event_attrs = %{
        timestamp: normalized_event.timestamp,
        event_type: event_type,
        user_id: normalized_event[:user_id],
        user_login: normalized_event[:user_login],
        user_name: normalized_event[:user_name],
        data: normalized_event,
        correlation_id: generate_correlation_id()
      }

      Logger.debug("Storing event in ActivityLog database",
        event_type: event_type,
        event_id: normalized_event[:id],
        user_id: event_attrs[:user_id],
        user_login: event_attrs[:user_login],
        correlation_id: event_attrs[:correlation_id],
        timestamp: event_attrs[:timestamp]
      )

      # Store the event asynchronously to avoid blocking the event pipeline
      Task.start(fn -> store_event_async(event_attrs, event_type, normalized_event) end)
    else
      Logger.debug("Event not stored - not in valuable_events list", event_type: event_type)
    end

    :ok
  end

  # Determine which events should be stored in the ActivityLog
  defp should_store_event?(event_type) do
    valuable_events = [
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

    event_type in valuable_events
  end

  # Upsert user information when we encounter them in events
  defp upsert_user_from_event(normalized_event) do
    if normalized_event[:user_id] && normalized_event[:user_login] do
      user_attrs = %{
        twitch_id: normalized_event.user_id,
        login: normalized_event.user_login,
        display_name: normalized_event[:user_name]
      }

      case ActivityLog.upsert_user(user_attrs) do
        {:ok, _user} ->
          Logger.debug("User upserted in ActivityLog",
            user_id: normalized_event.user_id,
            login: normalized_event.user_login
          )

        {:error, changeset} ->
          Logger.warning("Failed to upsert user in ActivityLog",
            user_id: normalized_event.user_id,
            login: normalized_event.user_login,
            errors: inspect(changeset.errors)
          )
      end
    end
  end

  # Async storage of event with user upsert
  defp store_event_async(event_attrs, event_type, normalized_event) do
    Logger.debug("Starting async database storage",
      event_type: event_type,
      correlation_id: event_attrs[:correlation_id]
    )

    case ActivityLog.store_event(event_attrs) do
      {:ok, event} ->
        Logger.debug("Event stored in ActivityLog database",
          event_type: event_type,
          event_id: normalized_event.id,
          database_id: event.id,
          correlation_id: event_attrs[:correlation_id],
          timestamp: event_attrs[:timestamp]
        )

        # Also upsert user information if we have user data
        if normalized_event[:user_id] do
          upsert_user_from_event(normalized_event)
        end

      {:error, changeset} ->
        Logger.error("FAILED: Event storage in ActivityLog database",
          event_type: event_type,
          event_id: normalized_event.id,
          correlation_id: event_attrs[:correlation_id],
          errors: inspect(changeset.errors),
          changeset_details: inspect(changeset, limit: :infinity)
        )
    end
  end

  # Simple correlation ID generation for events
  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
