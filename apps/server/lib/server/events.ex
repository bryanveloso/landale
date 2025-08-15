defmodule Server.Events do
  @moduledoc """
  Unified event processing and Phoenix PubSub publishing system.

  This module is the central event handler for ALL event processing in the system.
  Handles events from Twitch, OBS, IronMON, Rainwave, and System sources.

  ## Features

  - Event type-specific processing and validation
  - Phoenix PubSub publishing for real-time updates
  - Consistent event data normalization (flat format)
  - Activity log integration and correlation tracking
  - Unified "events" topic for all event consumers

  ## Event Types Handled

  ### Twitch Events
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

  ### OBS Events
  - `obs.connection_established` / `obs.connection_lost` - WebSocket connection state
  - `obs.scene_changed` - Scene transitions
  - `obs.stream_started` / `obs.stream_stopped` - Streaming state
  - `obs.recording_started` / `obs.recording_stopped` - Recording state

  ### IronMON Events
  - `ironmon.init` - Game initialization with version and difficulty
  - `ironmon.seed` - Seed count updates
  - `ironmon.checkpoint` - Checkpoint progress with location data
  - `ironmon.battle_start` / `ironmon.battle_end` - Battle encounters
  - `ironmon.pokemon_update` - Team composition changes

  ### Rainwave Events
  - `rainwave.song_changed` - Current song updates
  - `rainwave.station_changed` - Station switching
  - `rainwave.listening_started` / `rainwave.listening_stopped` - User listening state

  ### System Events
  - `system.service_started` / `system.service_stopped` - Service lifecycle
  - `system.health_check` - Health status updates
  - `system.performance_metric` - Performance monitoring data

  ## Event Format

  All events are normalized to a consistent flat format:

      %{
        # Core fields (always present)
        id: "evt_123abc",
        type: "obs.stream_started",
        timestamp: ~U[2023-01-01 12:00:00Z],
        correlation_id: "correlation_123",
        source: :obs,
        raw_type: "stream_started",

        # Event-specific fields (flattened)
        stream_status: "active",
        output_active: true,
        session_id: "default"
      }

  ## Publishing Strategy

  - All events publish to unified `"events"` topic with flat format
  - Dashboard gets all events for monitoring and control interfaces
  """

  require Logger
  alias Server.ActivityLog
  alias Server.Events.Validation

  @doc """
  Processes an incoming event.

  ## Parameters
  - `event_type` - The event type (e.g. "stream.online")
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

    Logger.debug("Processing event",
      event_type: event_type,
      event_id: event_id,
      event_data_keys: Map.keys(event_data || %{}),
      event_size: byte_size(:erlang.term_to_binary(event_data))
    )

    # SECURITY: Validate event data before processing to prevent malicious payloads
    case Validation.validate_event_data(event_type, event_data) do
      {:ok, validated_data} ->
        # Process event with validated data
        process_validated_event(event_type, validated_data, event_id)

      {:error, validation_errors} ->
        # Log validation failure and reject the event
        Logger.error(
          "Event validation failed - rejecting potentially malicious payload, validation_errors: #{inspect(validation_errors)}",
          event_type: event_type,
          event_id: event_id,
          validation_errors: validation_errors,
          data_sample: inspect(Map.take(event_data || %{}, ["id", "type", "user_id"]), limit: 200)
        )

        {:error, {:validation_failed, validation_errors}}
    end
  end

  defp process_validated_event(event_type, validated_data, event_id) do
    # Process event with separate handling for critical and non-critical operations
    with normalized_event <- normalize_event(event_type, validated_data),
         :ok <- store_event_in_activity_log(event_type, normalized_event),
         :ok <- publish_event(event_type, normalized_event) do
      Logger.debug("Event processed successfully",
        event_type: event_type,
        event_id: event_id
      )

      :ok
    else
      {:error, reason} = error ->
        Logger.error("Critical event processing failed",
          reason: inspect(reason),
          event_type: event_type,
          event_id: event_id
        )

        error
    end
  rescue
    error ->
      Logger.error("Unexpected error in event processing",
        error: inspect(error),
        event_type: event_type,
        event_id: event_id,
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Processing failed: #{inspect(error)}"}
  end

  @doc """
  Normalizes event data into a consistent format.

  ## Parameters
  - `event_type` - The event type
  - `event_data` - Raw event data

  ## Returns
  - Normalized event data map
  """
  @spec normalize_event(binary(), map()) :: map()
  def normalize_event(event_type, event_data) do
    # Use BoundaryConverter for consistent atom access
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    # Get correlation ID from pool, with fallback for tests or when pool isn't available
    correlation_id = get_safe_correlation_id()

    # Build base event with core fields that are always present
    base_event = %{
      # Core fields (always present)
      id: Map.get(data, :id) || Map.get(data, :message_id) || generate_event_id(),
      type: event_type,
      timestamp: DateTime.utc_now(),
      correlation_id: correlation_id,
      source: determine_event_source(event_type),

      # Metadata
      source_id: Map.get(data, :id) || Map.get(data, :message_id),
      raw_type: event_type
    }

    # Get event-specific fields (already flat)
    event_specific = get_event_specific_data(event_type, event_data)

    # Merge to create flat canonical structure
    Map.merge(base_event, event_specific)
  end

  defp get_event_specific_data("stream.online", event_data) do
    # Use BoundaryConverter for consistent atom access
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      # Stream-specific fields (flat)
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
      # User fields (flat)
      user_id: Map.get(data, :user_id),
      user_login: Map.get(data, :user_login),
      user_name: Map.get(data, :user_name),

      # Broadcaster fields (flat)
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),

      # Cheer-specific fields (flat)
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

    # Extract nested message data
    message_data = Map.get(data, :message, %{})
    fragments = Map.get(message_data, :fragments, [])
    {emotes, native_emotes} = extract_emotes_from_fragments(fragments)

    # Extract reply data if present (handle nil case)
    reply_data = Map.get(data, :reply) || %{}
    has_reply = reply_data != %{} and reply_data != nil

    # Extract cheer data if present (handle nil case)
    cheer_data = Map.get(data, :cheer) || %{}
    has_cheer = cheer_data != %{} and cheer_data != nil

    %{
      # Message fields (all flat, no nesting)
      message_id: Map.get(data, :message_id),
      broadcaster_user_id: Map.get(data, :broadcaster_user_id),
      broadcaster_user_login: Map.get(data, :broadcaster_user_login),
      broadcaster_user_name: Map.get(data, :broadcaster_user_name),

      # User fields (using consistent naming)
      user_id: Map.get(data, :chatter_user_id),
      user_login: Map.get(data, :chatter_user_login),
      user_name: Map.get(data, :chatter_user_name),

      # Message content (flat)
      message: Map.get(message_data, :text),
      fragments: fragments,
      emotes: emotes,
      native_emotes: native_emotes,

      # User attributes (flat)
      color: Map.get(data, :color),
      badges: extract_badges(Map.get(data, :badges)),

      # Message metadata (flat)
      message_type: Map.get(data, :message_type),

      # Flatten cheer data if present
      cheer_bits: if(has_cheer, do: Map.get(cheer_data, :bits), else: nil),

      # Flatten reply data if present
      reply_parent_message_id: if(has_reply, do: Map.get(reply_data, :parent_message_id), else: nil),
      reply_parent_user_id: if(has_reply, do: Map.get(reply_data, :parent_user_id), else: nil),
      reply_parent_user_login: if(has_reply, do: Map.get(reply_data, :parent_user_login), else: nil),
      reply_parent_user_name: if(has_reply, do: Map.get(reply_data, :parent_user_name), else: nil),
      reply_parent_message_body: if(has_reply, do: Map.get(reply_data, :parent_message_body), else: nil),
      reply_thread_message_id: if(has_reply, do: Map.get(reply_data, :thread_message_id), else: nil),
      reply_thread_user_id: if(has_reply, do: Map.get(reply_data, :thread_user_id), else: nil),
      reply_thread_user_login: if(has_reply, do: Map.get(reply_data, :thread_user_login), else: nil),
      reply_thread_user_name: if(has_reply, do: Map.get(reply_data, :thread_user_name), else: nil),

      # Channel points reward (flat)
      channel_points_custom_reward_id: Map.get(data, :channel_points_custom_reward_id),

      # Source data for shared messages (flat)
      source_broadcaster_user_id: Map.get(data, :source_broadcaster_user_id),
      source_broadcaster_user_login: Map.get(data, :source_broadcaster_user_login),
      source_broadcaster_user_name: Map.get(data, :source_broadcaster_user_name),
      source_message_id: Map.get(data, :source_message_id),
      source_badges: extract_badges(Map.get(data, :source_badges))
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

  # OBS Event Normalization

  defp get_event_specific_data("obs.connection_established", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      connection_state: "connected",
      session_id: Map.get(data, :session_id),
      websocket_version: Map.get(data, :websocket_version),
      rpc_version: Map.get(data, :rpc_version),
      authentication: Map.get(data, :authentication, false)
    }
  end

  defp get_event_specific_data("obs.connection_lost", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      connection_state: "disconnected",
      session_id: Map.get(data, :session_id),
      reason: Map.get(data, :reason),
      reconnecting: Map.get(data, :reconnecting, false)
    }
  end

  defp get_event_specific_data("obs.scene_changed", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      scene_name: Map.get(data, :scene_name) || Map.get(data, :sceneName),
      previous_scene: Map.get(data, :previous_scene),
      session_id: Map.get(data, :session_id)
    }
  end

  defp get_event_specific_data("obs.stream_started", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      stream_status: "active",
      output_active: Map.get(data, :output_active, true),
      output_state: Map.get(data, :output_state) || Map.get(data, :outputState),
      session_id: Map.get(data, :session_id)
    }
  end

  defp get_event_specific_data("obs.stream_stopped", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      stream_status: "inactive",
      output_active: Map.get(data, :output_active, false),
      output_state: Map.get(data, :output_state) || Map.get(data, :outputState),
      session_id: Map.get(data, :session_id)
    }
  end

  defp get_event_specific_data("obs.recording_started", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      recording_status: "active",
      output_active: Map.get(data, :output_active, true),
      output_state: Map.get(data, :output_state) || Map.get(data, :outputState),
      session_id: Map.get(data, :session_id)
    }
  end

  defp get_event_specific_data("obs.recording_stopped", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      recording_status: "inactive",
      output_active: Map.get(data, :output_active, false),
      output_state: Map.get(data, :output_state) || Map.get(data, :outputState),
      session_id: Map.get(data, :session_id)
    }
  end

  # IronMON Event Normalization

  defp get_event_specific_data("ironmon.init", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      game_type: Map.get(data, :game_type),
      game_name: Map.get(data, :game_name),
      version: Map.get(data, :version),
      difficulty: Map.get(data, :difficulty),
      run_id: Map.get(data, :run_id)
    }
  end

  defp get_event_specific_data("ironmon.seed", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      seed_count: Map.get(data, :seed_count),
      run_id: Map.get(data, :run_id)
    }
  end

  defp get_event_specific_data("ironmon.checkpoint", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      checkpoint_id: Map.get(data, :checkpoint_id),
      checkpoint_name: Map.get(data, :checkpoint_name),
      run_id: Map.get(data, :run_id),
      seed_count: Map.get(data, :seed_count),
      location_id: Map.get(data, :location_id),
      location_name: Map.get(data, :location_name)
    }
  end

  defp get_event_specific_data("ironmon.battle_start", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      battle_type: Map.get(data, :battle_type),
      trainer_name: Map.get(data, :trainer_name),
      opponent_pokemon: Map.get(data, :opponent_pokemon),
      run_id: Map.get(data, :run_id)
    }
  end

  defp get_event_specific_data("ironmon.battle_end", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      battle_result: Map.get(data, :battle_result),
      winner: Map.get(data, :winner),
      run_id: Map.get(data, :run_id)
    }
  end

  defp get_event_specific_data("ironmon.pokemon_update", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      pokemon_name: Map.get(data, :pokemon_name),
      pokemon_level: Map.get(data, :pokemon_level),
      pokemon_hp: Map.get(data, :pokemon_hp),
      pokemon_status: Map.get(data, :pokemon_status),
      run_id: Map.get(data, :run_id)
    }
  end

  # Rainwave Event Normalization

  defp get_event_specific_data("rainwave.song_changed", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    # Extract song data if nested
    current_song = Map.get(data, :current_song, %{})

    %{
      song_id: Map.get(current_song, :id) || Map.get(data, :song_id),
      song_title: Map.get(current_song, :title) || Map.get(data, :song_title),
      artist: Map.get(current_song, :artist) || Map.get(data, :artist),
      album: Map.get(current_song, :album) || Map.get(data, :album),
      station_id: Map.get(data, :station_id),
      station_name: Map.get(data, :station_name),
      listening: Map.get(data, :listening, false)
    }
  end

  defp get_event_specific_data("rainwave.update", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    # Extract song data if nested
    current_song = Map.get(data, :current_song, %{})

    %{
      # Station info
      station_id: Map.get(data, :station_id),
      station_name: Map.get(data, :station_name),
      listening: Map.get(data, :listening, false),

      # Song info (if available)
      song_id: Map.get(current_song, :id),
      song_title: Map.get(current_song, :title),
      artist: Map.get(current_song, :artist),
      album: Map.get(current_song, :album),

      # Service state
      enabled: Map.get(data, :enabled, false)
    }
  end

  defp get_event_specific_data("rainwave.station_changed", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      station_id: Map.get(data, :station_id),
      station_name: Map.get(data, :station_name),
      previous_station_id: Map.get(data, :previous_station_id),
      listening: Map.get(data, :listening, false)
    }
  end

  defp get_event_specific_data("rainwave.listening_started", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      listening: true,
      station_id: Map.get(data, :station_id),
      station_name: Map.get(data, :station_name)
    }
  end

  defp get_event_specific_data("rainwave.listening_stopped", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      listening: false,
      station_id: Map.get(data, :station_id),
      station_name: Map.get(data, :station_name)
    }
  end

  # System Event Normalization

  defp get_event_specific_data("system.service_started", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      service_name: Map.get(data, :service) || Map.get(data, :service_name),
      service_status: "started",
      version: Map.get(data, :version),
      pid: Map.get(data, :pid)
    }
  end

  defp get_event_specific_data("system.service_stopped", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    %{
      service_name: Map.get(data, :service) || Map.get(data, :service_name),
      service_status: "stopped",
      reason: Map.get(data, :reason)
    }
  end

  defp get_event_specific_data("system.health_check", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    # Extract details into flat fields instead of nested structure
    details = Map.get(data, :details, %{})

    %{
      service_name: Map.get(data, :service) || Map.get(data, :service_name),
      health_status: Map.get(data, :status) || Map.get(data, :health_status),
      checks_passed: Map.get(data, :checks_passed),
      checks_failed: Map.get(data, :checks_failed),
      # Flatten details into specific fields (flat format)
      uptime: Map.get(details, :uptime),
      memory_usage: Map.get(details, :memory_usage),
      cpu_usage: Map.get(details, :cpu_usage),
      disk_usage: Map.get(details, :disk_usage),
      error_count: Map.get(details, :error_count)
    }
  end

  defp get_event_specific_data("system.performance_metric", event_data) do
    {:ok, data} = Server.BoundaryConverter.from_external(event_data)

    # Extract metadata into flat fields instead of nested structure
    metadata = Map.get(data, :metadata, %{})

    %{
      metric_name: Map.get(data, :metric) || Map.get(data, :metric_name),
      metric_value: Map.get(data, :value) || Map.get(data, :metric_value),
      metric_unit: Map.get(data, :unit),
      # Flatten metadata into specific fields (flat format)
      component: Map.get(metadata, :component),
      process_id: Map.get(metadata, :process_id),
      hostname: Map.get(metadata, :hostname),
      environment: Map.get(metadata, :environment)
    }
  end

  defp get_event_specific_data(_event_type, event_data) do
    # For unknown event types, include all original data
    %{raw_data: event_data}
  end

  @doc """
  Publishes a normalized event to Phoenix PubSub.

  ## Parameters
  - `event_type` - The event type
  - `normalized_event` - Normalized event data

  ## Returns
  - `:ok`
  """
  @spec publish_event(binary(), map()) :: :ok
  def publish_event(event_type, normalized_event) do
    source = normalized_event.source

    # Only publish to unified topics now
    unified_topics = ["events", "dashboard"]

    Logger.info("Publishing event to unified topics",
      event_type: event_type,
      event_id: normalized_event.id,
      correlation_id: normalized_event.correlation_id,
      source: source,
      topics: unified_topics
    )

    # Publish to unified events topic (all events go here)
    Enum.each(unified_topics, fn topic ->
      result = Phoenix.PubSub.broadcast(Server.PubSub, topic, {:event, normalized_event})
      Logger.debug("Topic broadcast result", topic: topic, result: result)
    end)

    Logger.info("Event published successfully",
      event_type: event_type,
      event_id: normalized_event.id,
      source: source
    )

    :ok
  end

  # Private helper functions

  # Determines the source of an event based on its type
  defp determine_event_source(event_type) do
    cond do
      # Twitch events
      String.starts_with?(event_type, "stream.") -> :twitch
      String.starts_with?(event_type, "channel.") -> :twitch
      String.starts_with?(event_type, "user.") -> :twitch
      # OBS events
      String.starts_with?(event_type, "obs.") -> :obs
      # IronMON events
      String.starts_with?(event_type, "ironmon.") -> :ironmon
      # Rainwave events
      String.starts_with?(event_type, "rainwave.") -> :rainwave
      # System events
      String.starts_with?(event_type, "system.") -> :system
      # Default to twitch for backward compatibility
      true -> :twitch
    end
  end

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
    # Only store events that are valuable for the Activity Log
    if should_store_event?(event_type) do
      # Prepare event attributes for database storage
      # Use the correlation_id from the normalized event (already set during normalization)
      event_attrs = %{
        timestamp: normalized_event.timestamp,
        event_type: event_type,
        user_id: Map.get(normalized_event, :user_id),
        user_login: Map.get(normalized_event, :user_login),
        user_name: Map.get(normalized_event, :user_name),
        data: normalized_event,
        correlation_id: normalized_event.correlation_id
      }

      Logger.debug("Storing event in ActivityLog database",
        event_type: event_type,
        event_id: Map.get(normalized_event, :id),
        user_id: event_attrs[:user_id],
        user_login: event_attrs[:user_login],
        correlation_id: event_attrs[:correlation_id],
        timestamp: event_attrs[:timestamp]
      )

      # Store the event asynchronously to avoid blocking the event pipeline
      # Use Task.Supervisor for reliable async storage
      case Task.Supervisor.start_child(Server.TaskSupervisor, fn ->
             store_event_async(event_attrs, event_type, normalized_event)
           end) do
        {:ok, _pid} ->
          Logger.debug("Async storage task started successfully",
            event_type: event_type,
            correlation_id: event_attrs[:correlation_id]
          )

        {:error, reason} ->
          Logger.error("Failed to start async storage task",
            reason: inspect(reason),
            event_type: event_type,
            correlation_id: event_attrs[:correlation_id]
          )
      end
    else
      Logger.debug("Event not stored - not in valuable_events list", event_type: event_type)
    end

    :ok
  end

  # Determine which events should be stored in the ActivityLog
  @doc "Determines if an event should be stored in ActivityLog (public for testing)"
  def should_store_event?(event_type) do
    valuable_events = [
      # Twitch events (valuable for activity tracking)
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
      "channel.goal.end",

      # OBS events (valuable for stream analysis)
      "obs.stream_started",
      "obs.stream_stopped",
      "obs.recording_started",
      "obs.recording_stopped",
      "obs.scene_changed",

      # IronMON events (valuable for game tracking)
      "ironmon.init",
      "ironmon.checkpoint",
      "ironmon.battle_start",
      "ironmon.battle_end",

      # Rainwave events (valuable for music correlation)
      "rainwave.song_changed",
      "rainwave.station_changed",

      # System events (valuable for operational monitoring)
      "system.service_started",
      "system.service_stopped"

      # Note: Health checks and performance metrics are intentionally excluded
      # as they're too frequent and better suited for dedicated monitoring systems
    ]

    event_type in valuable_events
  end

  # Async storage of event with user upsert - atomic transaction
  defp store_event_async(event_attrs, event_type, normalized_event) do
    # Wrap both operations in a transaction for atomicity
    result =
      Server.Repo.transaction(fn ->
        store_event_with_user(event_attrs, event_type, normalized_event)
      end)

    log_transaction_result(result, event_type, event_attrs[:correlation_id])
  rescue
    error ->
      Logger.error("Database storage task crashed",
        event_type: event_type,
        correlation_id: event_attrs[:correlation_id],
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )
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
    if Map.get(normalized_event, :user_id) && Map.get(normalized_event, :user_login) do
      upsert_user(event, normalized_event)
    else
      {event, nil}
    end
  end

  defp upsert_user(event, normalized_event) do
    user_attrs = %{
      twitch_id: Map.get(normalized_event, :user_id),
      login: Map.get(normalized_event, :user_login),
      display_name: Map.get(normalized_event, :user_name)
    }

    case ActivityLog.upsert_user(user_attrs) do
      {:ok, user} ->
        Logger.debug("User upserted in ActivityLog",
          user_id: Map.get(normalized_event, :user_id),
          login: Map.get(normalized_event, :user_login)
        )

        {event, user}

      {:error, changeset} ->
        Logger.error("FAILED: User upsert in ActivityLog",
          user_id: Map.get(normalized_event, :user_id),
          login: Map.get(normalized_event, :user_login),
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

  # Get correlation ID safely, with fallback for when pool isn't available
  defp get_safe_correlation_id do
    try do
      Server.CorrelationIdPool.get()
    rescue
      ArgumentError ->
        # Pool not available (e.g., in tests), generate one directly
        generate_correlation_id()
    end
  end

  # Simple correlation ID generation for events (backup when pool is unavailable)
  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Generate a unique event ID when not provided by Twitch
  defp generate_event_id do
    "evt_" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end
end
