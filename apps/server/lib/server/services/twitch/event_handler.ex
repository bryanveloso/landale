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
    Logger.debug("Event processing started",
      event_type: event_type,
      event_id: event_data["id"],
      broadcaster_id: event_data["broadcaster_user_id"]
    )

    try do
      normalized_event = normalize_event(event_type, event_data)
      publish_event(event_type, normalized_event)
      emit_telemetry(event_type, normalized_event)

      Logger.info("Event processing completed",
        event_type: event_type,
        event_id: event_data["id"]
      )

      :ok
    rescue
      error ->
        Logger.error("Event processing failed",
          error: inspect(error),
          event_type: event_type,
          event_id: event_data["id"],
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
          stream_type: event_data["type"],
          started_at: parse_datetime(event_data["started_at"])
        })

      "stream.offline" ->
        base_event

      "channel.follow" ->
        Map.merge(base_event, %{
          user_id: event_data["user_id"],
          user_login: event_data["user_login"],
          user_name: event_data["user_name"],
          followed_at: parse_datetime(event_data["followed_at"])
        })

      "channel.subscribe" ->
        Map.merge(base_event, %{
          user_id: event_data["user_id"],
          user_login: event_data["user_login"],
          user_name: event_data["user_name"],
          tier: event_data["tier"],
          is_gift: event_data["is_gift"] || false
        })

      "channel.subscription.gift" ->
        Map.merge(base_event, %{
          user_id: event_data["user_id"],
          user_login: event_data["user_login"],
          user_name: event_data["user_name"],
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
          is_anonymous: event_data["is_anonymous"] || false,
          bits: event_data["bits"],
          message: event_data["message"]
        })

      "channel.update" ->
        Map.merge(base_event, %{
          title: event_data["title"],
          language: event_data["language"],
          category_id: event_data["category_id"],
          category_name: event_data["category_name"]
        })

      "channel.chat.message" ->
        Map.merge(base_event, %{
          message_id: event_data["message_id"],
          user_id: event_data["chatter_user_id"],
          user_login: event_data["chatter_user_login"],
          user_name: event_data["chatter_user_name"],
          message: event_data["message"]["text"],
          fragments: event_data["message"]["fragments"] || [],
          color: event_data["color"],
          badges: extract_badges(event_data["badges"]),
          message_type: event_data["message_type"],
          cheer: event_data["cheer"],
          reply: event_data["reply"],
          channel_points_custom_reward_id: event_data["channel_points_custom_reward_id"]
        })

      "channel.chat.clear" ->
        base_event

      "channel.chat.message_delete" ->
        Map.merge(base_event, %{
          target_user_id: event_data["target_user_id"],
          target_user_login: event_data["target_user_login"],
          target_user_name: event_data["target_user_name"],
          target_message_id: event_data["target_message_id"],
          target_message_body: event_data["target_message_body"]
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

      _ ->
        # For other events, just use the general topic
        :ok
    end

    Logger.debug("Event published to PubSub",
      event_type: event_type,
      event_id: normalized_event.id
    )

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
end
