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
  - `channel.goal.begin` - Goal creation
  - `channel.goal.progress` - Goal progress updates
  - `channel.goal.end` - Goal completion
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
    # Use BoundaryConverter for consistent logging access
    {:ok, data} = Server.BoundaryConverter.from_external(event_data || %{})
    event_id = Map.get(data, :id) || Map.get(data, :message_id)

    Logger.debug("Processing EventSub event",
      event_type: event_type,
      event_id: event_id,
      event_data_keys: Map.keys(event_data || %{}),
      event_size: byte_size(:erlang.term_to_binary(event_data))
    )

    # Process event with separate handling for critical and non-critical operations
    with normalized_event <- normalize_event(event_type, event_data),
         :ok <- store_event_in_activity_log(event_type, normalized_event),
         :ok <- publish_event(event_type, normalized_event) do
      # Telemetry is important but non-critical - its failure shouldn't fail the whole event
      try do
        emit_telemetry(event_type, normalized_event)
      rescue
        error ->
          Logger.warning("Telemetry emission failed (non-critical)",
            error: inspect(error),
            event_type: event_type,
            event_id: Map.get(data, :id) || Map.get(data, :message_id),
            stacktrace: Exception.format_stacktrace(__STACKTRACE__)
          )
      end

      Logger.debug("EventSub event processed successfully",
        event_type: event_type,
        event_id: Map.get(data, :id) || Map.get(data, :message_id)
      )

      :ok
    else
      {:error, reason} = error ->
        Logger.error("Critical event processing failed",
          reason: inspect(reason),
          event_type: event_type,
          event_id: Map.get(data, :id) || Map.get(data, :message_id)
        )

        error
    end
  rescue
    error ->
      # Use BoundaryConverter for consistent logging access in error handler
      {:ok, data} = Server.BoundaryConverter.from_external(event_data || %{})

      Logger.error("Unexpected error in event processing",
        error: inspect(error),
        event_type: event_type,
        event_id: Map.get(data, :id) || Map.get(data, :message_id),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Processing failed: #{inspect(error)}"}
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
    # Use BoundaryConverter for consistent atom access
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    base_event = %{
      type: event_type,
      id: Map.get(data, :id),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      timestamp: DateTime.utc_now()
    }

    Map.merge(base_event, get_event_specific_data(event_type, event_data))
  end

  defp get_event_specific_data("stream.online", event_data) do
    # Use BoundaryConverter for consistent atom access
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      stream_id: Map.get(data, :id),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      stream_type: Map.get(data, :type),
      started_at: parse_datetime(Map.get(data, :started_at))
    }
  end

  defp get_event_specific_data("stream.offline", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name)
    }
  end

  defp get_event_specific_data("channel.follow", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      user_id: Map.get(data, :user_id),
      user_login: Map.get(data, :user_login),
      user_name: Map.get(data, :user_name),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      followed_at: parse_datetime(Map.get(data, :followed_at))
    }
  end

  defp get_event_specific_data("channel.subscribe", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      user_id: Map.get(data, :user_id),
      user_login: Map.get(data, :user_login),
      user_name: Map.get(data, :user_name),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      tier: Map.get(data, :tier),
      is_gift: Map.get(data, :is_gift, false)
    }
  end

  defp get_event_specific_data("channel.subscription.gift", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      user_id: Map.get(data, :user_id),
      user_login: Map.get(data, :user_login),
      user_name: Map.get(data, :user_name),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      tier: Map.get(data, :tier),
      total: Map.get(data, :total),
      cumulative_total: Map.get(data, :cumulative_total),
      is_anonymous: Map.get(data, :is_anonymous, false)
    }
  end

  defp get_event_specific_data("channel.cheer", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      user_id: Map.get(data, :user_id),
      user_login: Map.get(data, :user_login),
      user_name: Map.get(data, :user_name),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      is_anonymous: Map.get(data, :is_anonymous, false),
      bits: Map.get(data, :bits),
      message: Map.get(data, :message)
    }
  end

  defp get_event_specific_data("channel.update", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      title: Map.get(data, :title),
      language: Map.get(data, :language),
      category_id: Map.get(data, :category_id),
      category_name: Map.get(data, :category_name),
      content_classification_labels: Map.get(data, :content_classification_labels, [])
    }
  end

  defp get_event_specific_data("channel.chat.message", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    message_data = Map.get(data, :message, %{})
    fragments = Map.get(message_data, :fragments, [])
    {emotes, native_emotes} = extract_emotes_from_fragments(fragments)

    %{
      message_id: Map.get(data, :message_id),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      user_id: Map.get(data, :chatter_user_id),
      user_login: Map.get(data, :chatter_user_login),
      user_name: Map.get(data, :chatter_user_name),
      message: Map.get(message_data, :text),
      fragments: fragments,
      emotes: emotes,
      native_emotes: native_emotes,
      color: Map.get(data, :color),
      badges: extract_badges(Map.get(data, :badges)),
      message_type: Map.get(data, :message_type),
      cheer: Map.get(data, :cheer),
      reply: Map.get(data, :reply),
      channel_points_custom_reward_id: Map.get(data, :channel_points_custom_reward_id),
      source_broadcaster_user_id: Map.get(data, :source_broadcaster_user_id),
      source_broadcaster_user_login: Map.get(data, :source_broadcaster_user_login),
      source_broadcaster_user_name: Map.get(data, :source_broadcaster_user_name),
      source_message_id: Map.get(data, :source_message_id),
      source_badges: Map.get(data, :source_badges)
    }
  end

  defp get_event_specific_data("channel.chat.clear", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name)
    }
  end

  defp get_event_specific_data("channel.chat.message_delete", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      target_user_id: Map.get(data, :target_user_id),
      target_user_login: Map.get(data, :target_user_login),
      target_user_name: Map.get(data, :target_user_name),
      message_id: Map.get(data, :message_id)
    }
  end

  defp get_event_specific_data("channel.goal.begin", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      id: Map.get(data, :id),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      type: Map.get(data, :type),
      description: Map.get(data, :description),
      current_amount: Map.get(data, :current_amount) || 0,
      target_amount: Map.get(data, :target_amount),
      started_at: parse_datetime(Map.get(data, :started_at))
    }
  end

  defp get_event_specific_data("channel.goal.progress", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      id: Map.get(data, :id),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      type: Map.get(data, :type),
      description: Map.get(data, :description),
      current_amount: Map.get(data, :current_amount),
      target_amount: Map.get(data, :target_amount),
      started_at: parse_datetime(Map.get(data, :started_at))
    }
  end

  defp get_event_specific_data("channel.goal.end", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      id: Map.get(data, :id),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),
      type: Map.get(data, :type),
      description: Map.get(data, :description),
      is_achieved: Map.get(data, :is_achieved) || false,
      current_amount: Map.get(data, :current_amount),
      target_amount: Map.get(data, :target_amount),
      started_at: parse_datetime(Map.get(data, :started_at)),
      ended_at: parse_datetime(Map.get(data, :ended_at))
    }
  end

  defp get_event_specific_data(_event_type, event_data) do
    # For unknown event types, include all original data
    %{raw_data: event_data}
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
    publish_legacy_event(event_type, normalized_event)

    :ok
  end

  defp publish_legacy_event(event_type, normalized_event) do
    case legacy_event_mapping(event_type) do
      {topic, event_name} ->
        Phoenix.PubSub.broadcast(Server.PubSub, topic, {event_name, normalized_event})

      nil ->
        :ok
    end
  end

  defp legacy_event_mapping("stream.online"), do: {"stream_status", :stream_online}
  defp legacy_event_mapping("stream.offline"), do: {"stream_status", :stream_offline}
  defp legacy_event_mapping("channel.follow"), do: {"followers", :new_follower}
  defp legacy_event_mapping("channel.subscribe"), do: {"subscriptions", :new_subscription}
  defp legacy_event_mapping("channel.subscription.gift"), do: {"subscriptions", :gift_subscription}
  defp legacy_event_mapping("channel.cheer"), do: {"cheers", :new_cheer}
  defp legacy_event_mapping("channel.chat.message"), do: {"chat", :chat_message}
  defp legacy_event_mapping("channel.chat.clear"), do: {"chat", :chat_clear}
  defp legacy_event_mapping("channel.chat.message_delete"), do: {"chat", :message_delete}
  defp legacy_event_mapping("channel.update"), do: {"channel:updates", :channel_update}
  defp legacy_event_mapping("channel.goal.begin"), do: {"goals", :goal_begin}
  defp legacy_event_mapping("channel.goal.progress"), do: {"goals", :goal_progress}
  defp legacy_event_mapping("channel.goal.end"), do: {"goals", :goal_end}
  defp legacy_event_mapping(_), do: nil

  @doc """
  Emits telemetry events for monitoring.

  ## Parameters
  - `event_type` - The EventSub event type
  - `normalized_event` - Normalized event data

  ## Returns
  - `:ok`
  """
  @spec emit_telemetry(binary(), map()) :: :ok
  def emit_telemetry(_event_type, _normalized_event) do
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
      # Use BoundaryConverter for consistent access
      {:ok, badge_data} = Server.BoundaryConverter.from_external(badge)

      %{
        set_id: Map.get(badge_data, :set_id),
        id: Map.get(badge_data, :id),
        info: Map.get(badge_data, :info)
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
      |> Enum.filter(fn fragment ->
        # Use BoundaryConverter for consistent access
        {:ok, fragment_data} = Server.BoundaryConverter.from_external(fragment)
        Map.get(fragment_data, :type) == "emote"
      end)
      |> Enum.map(fn fragment ->
        {:ok, fragment_data} = Server.BoundaryConverter.from_external(fragment)
        Map.get(fragment_data, :text)
      end)
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
      # Use DynamicSupervisor to limit concurrent DB writes
      case DynamicSupervisor.start_child(
             Server.DBTaskSupervisor,
             {Task,
              fn ->
                store_event_async(event_attrs, event_type, normalized_event)
              end}
           ) do
        {:ok, _pid} ->
          :ok

        {:error, :max_children} ->
          Logger.warning("Max concurrent DB writes reached, dropping event",
            event_type: event_type,
            event_id: normalized_event[:id]
          )

        {:error, reason} ->
          Logger.error("Failed to start DB write task",
            event_type: event_type,
            reason: inspect(reason)
          )
      end
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
      "stream.offline",
      "channel.goal.begin",
      "channel.goal.progress",
      "channel.goal.end"
    ]

    event_type in valuable_events
  end

  # Async storage of event with user upsert - atomic transaction
  defp store_event_async(event_attrs, event_type, normalized_event) do
    Logger.debug("Starting async database storage",
      event_type: event_type,
      correlation_id: event_attrs[:correlation_id]
    )

    # Wrap both operations in a transaction for atomicity
    result =
      Server.Repo.transaction(fn ->
        store_event_with_user(event_attrs, event_type, normalized_event)
      end)

    log_transaction_result(result, event_type, event_attrs[:correlation_id])
  end

  defp store_event_with_user(event_attrs, event_type, normalized_event) do
    case ActivityLog.store_event(event_attrs) do
      {:ok, event} ->
        log_event_stored(event, event_type, normalized_event, event_attrs)
        handle_user_upsert(event, normalized_event)

      {:error, changeset} ->
        log_event_storage_failure(event_type, normalized_event, event_attrs, changeset)
        Server.Repo.rollback({:event_storage_failed, changeset})
    end
  end

  defp handle_user_upsert(event, normalized_event) do
    if normalized_event[:user_id] && normalized_event[:user_login] do
      upsert_user(event, normalized_event)
    else
      {event, nil}
    end
  end

  defp upsert_user(event, normalized_event) do
    user_attrs = %{
      twitch_id: normalized_event.user_id,
      login: normalized_event.user_login,
      display_name: normalized_event[:user_name]
    }

    case ActivityLog.upsert_user(user_attrs) do
      {:ok, user} ->
        Logger.debug("User upserted in ActivityLog",
          user_id: normalized_event.user_id,
          login: normalized_event.user_login
        )

        {event, user}

      {:error, changeset} ->
        Logger.error("FAILED: User upsert in ActivityLog",
          user_id: normalized_event.user_id,
          login: normalized_event.user_login,
          errors: inspect(changeset.errors)
        )

        Server.Repo.rollback({:user_upsert_failed, changeset})
    end
  end

  defp log_event_stored(event, event_type, normalized_event, event_attrs) do
    Logger.debug("Event stored in ActivityLog database",
      event_type: event_type,
      event_id: normalized_event.id,
      database_id: event.id,
      correlation_id: event_attrs[:correlation_id],
      timestamp: event_attrs[:timestamp]
    )
  end

  defp log_event_storage_failure(event_type, normalized_event, event_attrs, changeset) do
    Logger.error("FAILED: Event storage in ActivityLog database",
      event_type: event_type,
      event_id: normalized_event.id,
      correlation_id: event_attrs[:correlation_id],
      errors: inspect(changeset.errors),
      changeset_details: inspect(changeset, limit: :infinity)
    )
  end

  defp log_transaction_result({:ok, _}, event_type, correlation_id) do
    Logger.debug("Transaction completed successfully",
      event_type: event_type,
      correlation_id: correlation_id
    )
  end

  defp log_transaction_result({:error, reason}, event_type, correlation_id) do
    Logger.error("Transaction failed",
      event_type: event_type,
      correlation_id: correlation_id,
      reason: inspect(reason)
    )
  end

  # Simple correlation ID generation for events
  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
