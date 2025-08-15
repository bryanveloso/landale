defmodule Server.Events.Validation do
  @moduledoc """
  Input validation schemas for event data processing.

  Provides validation for untrusted event_data before it reaches the
  normalize_event/2 function, preventing malicious payloads from
  propagating through the system.

  ## Security Considerations

  - Validates all required fields are present and properly typed
  - Sanitizes string inputs to prevent injection attacks
  - Limits string/list sizes to prevent memory exhaustion
  - Rejects unexpected data structures
  - Logs validation failures for security monitoring

  ## Event Type Priority

  Validation is implemented for the highest risk event types first:
  1. Twitch events (external webhooks - highest risk)
  2. OBS events (local WebSocket - medium risk)
  3. System events (internal - low risk)
  """

  require Logger
  import Ecto.Changeset

  @max_string_length 2000
  @max_list_length 100
  @max_data_keys 50

  @doc """
  Validates event data against the appropriate schema for the event type.

  ## Parameters
  - `event_type` - The event type string (e.g. "stream.online")
  - `event_data` - Raw, untrusted event data map

  ## Returns
  - `{:ok, validated_data}` - Data passed validation
  - `{:error, errors}` - Validation failed with specific errors
  """
  @spec validate_event_data(binary(), map()) :: {:ok, map()} | {:error, map()}
  def validate_event_data(event_type, event_data) do
    # Handle nil or invalid data early
    if is_nil(event_data) or not is_map(event_data) do
      data_type =
        if is_nil(event_data) do
          "nil"
        else
          event_data |> Map.get(:__struct__, :not_struct) |> inspect()
        end

      Logger.warning("Event validation failed - invalid data type",
        event_type: event_type,
        data_type: data_type,
        is_map: is_map(event_data)
      )

      {:error, %{data: ["must be a valid map"]}}
    else
      # Check data size early to prevent memory exhaustion
      data_size = byte_size(:erlang.term_to_binary(event_data))
      # 100KB limit
      if data_size > 100_000 do
        Logger.warning("Event validation failed - data too large",
          event_type: event_type,
          data_size: data_size,
          max_size: 100_000
        )

        {:error, %{data: ["event data too large (max 100KB)"]}}
      else
        do_validate_event_data(event_type, event_data, data_size)
      end
    end
  end

  defp do_validate_event_data(event_type, event_data, data_size) do
    Logger.debug("Validating event data",
      event_type: event_type,
      data_size: data_size,
      keys: Map.keys(event_data)
    )

    # Get the appropriate validation schema function
    schema_func = get_validation_schema(event_type)

    # Create a changeset with proper types and run validation
    changeset = schema_func.(event_data)

    if changeset.valid? do
      # Return the validated/sanitized data
      validated_data = Ecto.Changeset.apply_changes(changeset)
      Logger.debug("Event validation passed", event_type: event_type)
      {:ok, validated_data}
    else
      # Extract and log validation errors
      errors = format_validation_errors(changeset)

      Logger.warning("Event validation failed",
        event_type: event_type,
        validation_errors: errors,
        data_sample: inspect(Map.take(event_data, ["id", "type", "user_id"]), limit: 200)
      )

      {:error, errors}
    end
  end

  # Helper function to create a changeset from params with proper typing
  defp create_changeset(params, field_types) do
    {%{}, field_types}
    |> cast(params, Map.keys(field_types))
  end

  # Validation Schema Routing

  # Twitch Events (highest priority - external webhooks)
  defp get_validation_schema("stream.online"), do: &validate_twitch_stream_online/1
  defp get_validation_schema("stream.offline"), do: &validate_twitch_stream_offline/1
  defp get_validation_schema("channel.follow"), do: &validate_twitch_follow/1
  defp get_validation_schema("channel.subscribe"), do: &validate_twitch_subscribe/1
  defp get_validation_schema("channel.subscription.gift"), do: &validate_twitch_gift_sub/1
  defp get_validation_schema("channel.cheer"), do: &validate_twitch_cheer/1
  defp get_validation_schema("channel.update"), do: &validate_twitch_channel_update/1
  defp get_validation_schema("channel.chat.message"), do: &validate_twitch_chat_message/1
  defp get_validation_schema("channel.chat.clear"), do: &validate_twitch_chat_clear/1
  defp get_validation_schema("channel.chat.message_delete"), do: &validate_twitch_chat_delete/1
  defp get_validation_schema("channel.goal.begin"), do: &validate_twitch_goal_begin/1
  defp get_validation_schema("channel.goal.progress"), do: &validate_twitch_goal_progress/1
  defp get_validation_schema("channel.goal.end"), do: &validate_twitch_goal_end/1

  # OBS Events (medium priority - local WebSocket)
  defp get_validation_schema("obs.connection_established"), do: &validate_obs_connection_established/1
  defp get_validation_schema("obs.connection_lost"), do: &validate_obs_connection_lost/1
  defp get_validation_schema("obs.scene_changed"), do: &validate_obs_scene_changed/1
  defp get_validation_schema("obs.stream_started"), do: &validate_obs_stream_started/1
  defp get_validation_schema("obs.stream_stopped"), do: &validate_obs_stream_stopped/1
  defp get_validation_schema("obs.recording_started"), do: &validate_obs_recording_started/1
  defp get_validation_schema("obs.recording_stopped"), do: &validate_obs_recording_stopped/1
  defp get_validation_schema("obs.websocket_event"), do: &validate_obs_websocket_event/1

  # IronMON Events (medium priority - game data)
  defp get_validation_schema("ironmon.init"), do: &validate_ironmon_init/1
  defp get_validation_schema("ironmon.seed"), do: &validate_ironmon_seed/1
  defp get_validation_schema("ironmon.checkpoint"), do: &validate_ironmon_checkpoint/1
  defp get_validation_schema("ironmon.battle_start"), do: &validate_ironmon_battle_start/1
  defp get_validation_schema("ironmon.battle_end"), do: &validate_ironmon_battle_end/1
  defp get_validation_schema("ironmon.pokemon_update"), do: &validate_ironmon_pokemon_update/1

  # Rainwave Events (medium priority - music data)
  defp get_validation_schema("rainwave.song_changed"), do: &validate_rainwave_song_changed/1
  defp get_validation_schema("rainwave.update"), do: &validate_rainwave_update/1
  defp get_validation_schema("rainwave.station_changed"), do: &validate_rainwave_station_changed/1
  defp get_validation_schema("rainwave.listening_started"), do: &validate_rainwave_listening_started/1
  defp get_validation_schema("rainwave.listening_stopped"), do: &validate_rainwave_listening_stopped/1

  # System Events (low priority - internal)
  defp get_validation_schema("system.service_started"), do: &validate_system_service_started/1
  defp get_validation_schema("system.service_stopped"), do: &validate_system_service_stopped/1
  defp get_validation_schema("system.health_check"), do: &validate_system_health_check/1
  defp get_validation_schema("system.performance_metric"), do: &validate_system_performance_metric/1

  # Stream Events (internal stream system)
  defp get_validation_schema("stream.state_updated"), do: &validate_stream_state_updated/1
  defp get_validation_schema("stream.show_changed"), do: &validate_stream_show_changed/1
  defp get_validation_schema("stream.interrupt_removed"), do: &validate_stream_interrupt_removed/1
  defp get_validation_schema("stream.emote_increment"), do: &validate_stream_emote_increment/1
  defp get_validation_schema("stream.takeover_started"), do: &validate_stream_takeover_started/1
  defp get_validation_schema("stream.takeover_cleared"), do: &validate_stream_takeover_cleared/1
  defp get_validation_schema("stream.goals_updated"), do: &validate_stream_goals_updated/1

  # Default: pass-through validation for unknown event types (allows extensibility)
  defp get_validation_schema(_unknown_type), do: &validate_unknown_event/1

  # Twitch Event Validation Functions

  defp validate_twitch_stream_online(params) do
    field_types = %{
      id: :string,
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      type: :string,
      started_at: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:broadcaster_user_id, :broadcaster_user_login])
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_safe_string(:type)
    |> validate_iso8601_datetime(:started_at)
    |> validate_data_size()
  end

  defp validate_twitch_stream_offline(params) do
    field_types = %{
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:broadcaster_user_id, :broadcaster_user_login])
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_data_size()
  end

  defp validate_twitch_follow(params) do
    field_types = %{
      user_id: :string,
      user_login: :string,
      user_name: :string,
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      followed_at: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:user_id, :user_login, :broadcaster_user_id, :broadcaster_user_login])
    |> validate_twitch_user_id(:user_id)
    |> validate_twitch_username(:user_login)
    |> validate_safe_string(:user_name)
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_iso8601_datetime(:followed_at)
    |> validate_data_size()
  end

  defp validate_twitch_subscribe(params) do
    field_types = %{
      user_id: :string,
      user_login: :string,
      user_name: :string,
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      tier: :string,
      is_gift: :boolean
    }

    create_changeset(params, field_types)
    |> validate_required([:user_id, :user_login, :broadcaster_user_id, :broadcaster_user_login])
    |> validate_twitch_user_id(:user_id)
    |> validate_twitch_username(:user_login)
    |> validate_safe_string(:user_name)
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_twitch_tier(:tier)
    |> validate_data_size()
  end

  defp validate_twitch_gift_sub(params) do
    field_types = %{
      user_id: :string,
      user_login: :string,
      user_name: :string,
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      tier: :string,
      total: :integer,
      cumulative_total: :integer,
      is_anonymous: :boolean
    }

    create_changeset(params, field_types)
    |> validate_required([:broadcaster_user_id, :broadcaster_user_login])
    |> validate_twitch_user_id(:user_id)
    |> validate_twitch_username(:user_login)
    |> validate_safe_string(:user_name)
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_twitch_tier(:tier)
    |> validate_positive_integer(:total)
    |> validate_positive_integer(:cumulative_total)
    |> validate_data_size()
  end

  defp validate_twitch_cheer(params) do
    field_types = %{
      user_id: :string,
      user_login: :string,
      user_name: :string,
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      is_anonymous: :boolean,
      bits: :integer,
      message: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:broadcaster_user_id, :broadcaster_user_login, :bits])
    |> validate_twitch_user_id(:user_id)
    |> validate_twitch_username(:user_login)
    |> validate_safe_string(:user_name)
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_positive_integer(:bits)
    |> validate_safe_string(:message, max_length: 500)
    |> validate_data_size()
  end

  defp validate_twitch_channel_update(params) do
    field_types = %{
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      title: :string,
      language: :string,
      category_id: :string,
      category_name: :string,
      content_classification_labels: {:array, :string}
    }

    create_changeset(params, field_types)
    |> validate_required([:broadcaster_user_id, :broadcaster_user_login])
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_safe_string(:title)
    |> validate_safe_string(:language, max_length: 10)
    |> validate_safe_string(:category_id)
    |> validate_safe_string(:category_name)
    |> validate_string_list(:content_classification_labels)
    |> validate_data_size()
  end

  defp validate_twitch_chat_message(params) do
    field_types = %{
      message_id: :string,
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      chatter_user_id: :string,
      chatter_user_login: :string,
      chatter_user_name: :string,
      message: :map,
      color: :string,
      badges: {:array, :map},
      message_type: :string,
      cheer: :map,
      reply: :map,
      channel_points_custom_reward_id: :string,
      source_broadcaster_user_id: :string,
      source_broadcaster_user_login: :string,
      source_broadcaster_user_name: :string,
      source_message_id: :string,
      source_badges: {:array, :map}
    }

    create_changeset(params, field_types)
    |> validate_required([:message_id, :broadcaster_user_id, :chatter_user_id])
    |> validate_safe_string(:message_id)
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_twitch_user_id(:chatter_user_id)
    |> validate_twitch_username(:chatter_user_login)
    |> validate_safe_string(:chatter_user_name)
    |> validate_chat_message_content(:message)
    |> validate_safe_string(:color, max_length: 20)
    |> validate_safe_string(:message_type, max_length: 50)
    |> validate_data_size()
  end

  defp validate_twitch_chat_clear(params) do
    field_types = %{
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:broadcaster_user_id, :broadcaster_user_login])
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_data_size()
  end

  defp validate_twitch_chat_delete(params) do
    field_types = %{
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      target_user_id: :string,
      target_user_login: :string,
      target_user_name: :string,
      message_id: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:broadcaster_user_id, :target_user_id, :message_id])
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_twitch_user_id(:target_user_id)
    |> validate_twitch_username(:target_user_login)
    |> validate_safe_string(:target_user_name)
    |> validate_safe_string(:message_id)
    |> validate_data_size()
  end

  defp validate_twitch_goal_begin(params) do
    field_types = %{
      id: :string,
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      type: :string,
      description: :string,
      current_amount: :integer,
      target_amount: :integer,
      started_at: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:id, :broadcaster_user_id, :type, :target_amount])
    |> validate_safe_string(:id)
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_safe_string(:type)
    |> validate_safe_string(:description)
    |> validate_non_negative_integer(:current_amount)
    |> validate_positive_integer(:target_amount)
    |> validate_iso8601_datetime(:started_at)
    |> validate_data_size()
  end

  defp validate_twitch_goal_progress(params) do
    field_types = %{
      id: :string,
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      type: :string,
      description: :string,
      current_amount: :integer,
      target_amount: :integer,
      started_at: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:id, :broadcaster_user_id, :current_amount])
    |> validate_safe_string(:id)
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_safe_string(:type)
    |> validate_safe_string(:description)
    |> validate_non_negative_integer(:current_amount)
    |> validate_positive_integer(:target_amount)
    |> validate_iso8601_datetime(:started_at)
    |> validate_data_size()
  end

  defp validate_twitch_goal_end(params) do
    field_types = %{
      id: :string,
      broadcaster_user_id: :string,
      broadcaster_user_login: :string,
      broadcaster_user_name: :string,
      type: :string,
      description: :string,
      is_achieved: :boolean,
      current_amount: :integer,
      target_amount: :integer,
      started_at: :string,
      ended_at: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:id, :broadcaster_user_id])
    |> validate_safe_string(:id)
    |> validate_twitch_user_id(:broadcaster_user_id)
    |> validate_twitch_username(:broadcaster_user_login)
    |> validate_safe_string(:broadcaster_user_name)
    |> validate_safe_string(:type)
    |> validate_safe_string(:description)
    |> validate_non_negative_integer(:current_amount)
    |> validate_positive_integer(:target_amount)
    |> validate_iso8601_datetime(:started_at)
    |> validate_iso8601_datetime(:ended_at)
    |> validate_data_size()
  end

  # OBS Event Validation Functions

  defp validate_obs_connection_established(params) do
    field_types = %{
      session_id: :string,
      websocket_version: :string,
      rpc_version: :integer,
      authentication: :boolean
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:session_id)
    |> validate_safe_string(:websocket_version, max_length: 20)
    |> validate_positive_integer(:rpc_version)
    |> validate_data_size()
  end

  defp validate_obs_connection_lost(params) do
    field_types = %{
      session_id: :string,
      reason: :string,
      reconnecting: :boolean
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:session_id)
    |> validate_safe_string(:reason)
    |> validate_data_size()
  end

  defp validate_obs_scene_changed(params) do
    field_types = %{
      scene_name: :string,
      sceneName: :string,
      previous_scene: :string,
      session_id: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:scene_name)
    |> validate_safe_string(:sceneName)
    |> validate_safe_string(:previous_scene)
    |> validate_safe_string(:session_id)
    |> validate_data_size()
  end

  defp validate_obs_stream_started(params) do
    field_types = %{
      output_active: :boolean,
      output_state: :string,
      outputState: :string,
      session_id: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:output_state)
    |> validate_safe_string(:outputState)
    |> validate_safe_string(:session_id)
    |> validate_data_size()
  end

  defp validate_obs_stream_stopped(params) do
    field_types = %{
      output_active: :boolean,
      output_state: :string,
      outputState: :string,
      session_id: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:output_state)
    |> validate_safe_string(:outputState)
    |> validate_safe_string(:session_id)
    |> validate_data_size()
  end

  defp validate_obs_recording_started(params) do
    field_types = %{
      output_active: :boolean,
      output_state: :string,
      outputState: :string,
      session_id: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:output_state)
    |> validate_safe_string(:outputState)
    |> validate_safe_string(:session_id)
    |> validate_data_size()
  end

  defp validate_obs_recording_stopped(params) do
    field_types = %{
      output_active: :boolean,
      output_state: :string,
      outputState: :string,
      session_id: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:output_state)
    |> validate_safe_string(:outputState)
    |> validate_safe_string(:session_id)
    |> validate_data_size()
  end

  defp validate_obs_websocket_event(params) do
    field_types = %{
      eventType: :string,
      eventData: :map,
      session_id: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:eventType])
    |> validate_safe_string(:eventType)
    |> validate_safe_string(:session_id)
    |> validate_data_size()
  end

  # System Event Validation Functions

  defp validate_system_service_started(params) do
    field_types = %{
      service: :string,
      service_name: :string,
      version: :string,
      pid: :integer
    }

    create_changeset(params, field_types)
    |> validate_required([:service])
    |> validate_safe_string(:service)
    |> validate_safe_string(:service_name)
    |> validate_safe_string(:version)
    |> validate_positive_integer(:pid)
    |> validate_data_size()
  end

  defp validate_system_service_stopped(params) do
    field_types = %{
      service: :string,
      service_name: :string,
      reason: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:service])
    |> validate_safe_string(:service)
    |> validate_safe_string(:service_name)
    |> validate_safe_string(:reason)
    |> validate_data_size()
  end

  defp validate_system_health_check(params) do
    field_types = %{
      service: :string,
      service_name: :string,
      status: :string,
      health_status: :string,
      details: :map,
      checks_passed: :integer,
      checks_failed: :integer,
      # Flattened details fields
      uptime: :integer,
      memory_usage: :float,
      cpu_usage: :float,
      disk_usage: :float,
      error_count: :integer
    }

    create_changeset(params, field_types)
    |> validate_required([:service])
    |> validate_safe_string(:service)
    |> validate_safe_string(:service_name)
    |> validate_safe_string(:status)
    |> validate_safe_string(:health_status)
    |> validate_non_negative_integer(:checks_passed)
    |> validate_non_negative_integer(:checks_failed)
    |> validate_non_negative_integer(:uptime)
    |> validate_non_negative_integer(:error_count)
    |> validate_data_size()
  end

  defp validate_system_performance_metric(params) do
    field_types = %{
      metric: :string,
      metric_name: :string,
      value: :float,
      metric_value: :float,
      unit: :string,
      metadata: :map,
      # Flattened metadata fields
      component: :string,
      process_id: :integer,
      hostname: :string,
      environment: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:metric])
    |> validate_safe_string(:metric)
    |> validate_safe_string(:metric_name)
    |> validate_safe_string(:unit)
    |> validate_safe_string(:component)
    |> validate_positive_integer(:process_id)
    |> validate_safe_string(:hostname)
    |> validate_safe_string(:environment)
    |> validate_data_size()
  end

  # IronMON Event Validation Functions

  defp validate_ironmon_init(params) do
    field_types = %{
      game_type: :string,
      game_name: :string,
      version: :string,
      difficulty: :string,
      run_id: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:game_type)
    |> validate_safe_string(:game_name)
    |> validate_safe_string(:version, max_length: 50)
    |> validate_safe_string(:difficulty)
    |> validate_safe_string(:run_id)
    |> validate_data_size()
  end

  defp validate_ironmon_seed(params) do
    field_types = %{
      seed_count: :integer,
      run_id: :string
    }

    create_changeset(params, field_types)
    |> validate_non_negative_integer(:seed_count)
    |> validate_safe_string(:run_id)
    |> validate_data_size()
  end

  defp validate_ironmon_checkpoint(params) do
    field_types = %{
      checkpoint_id: :string,
      checkpoint_name: :string,
      run_id: :string,
      seed_count: :integer,
      location_id: :string,
      location_name: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:checkpoint_id)
    |> validate_safe_string(:checkpoint_name)
    |> validate_safe_string(:run_id)
    |> validate_non_negative_integer(:seed_count)
    |> validate_safe_string(:location_id)
    |> validate_safe_string(:location_name)
    |> validate_data_size()
  end

  defp validate_ironmon_battle_start(params) do
    field_types = %{
      battle_type: :string,
      trainer_name: :string,
      opponent_pokemon: :string,
      run_id: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:battle_type)
    |> validate_safe_string(:trainer_name)
    |> validate_safe_string(:opponent_pokemon)
    |> validate_safe_string(:run_id)
    |> validate_data_size()
  end

  defp validate_ironmon_battle_end(params) do
    field_types = %{
      battle_result: :string,
      winner: :string,
      run_id: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:battle_result)
    |> validate_safe_string(:winner)
    |> validate_safe_string(:run_id)
    |> validate_data_size()
  end

  defp validate_ironmon_pokemon_update(params) do
    field_types = %{
      pokemon_name: :string,
      pokemon_level: :integer,
      pokemon_hp: :integer,
      pokemon_status: :string,
      run_id: :string
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:pokemon_name)
    |> validate_positive_integer(:pokemon_level)
    |> validate_non_negative_integer(:pokemon_hp)
    |> validate_safe_string(:pokemon_status)
    |> validate_safe_string(:run_id)
    |> validate_data_size()
  end

  # Rainwave Event Validation Functions

  defp validate_rainwave_song_changed(params) do
    field_types = %{
      current_song: :map,
      song_id: :integer,
      song_title: :string,
      artist: :string,
      album: :string,
      station_id: :integer,
      station_name: :string,
      listening: :boolean
    }

    create_changeset(params, field_types)
    |> validate_positive_integer(:song_id)
    |> validate_safe_string(:song_title)
    |> validate_safe_string(:artist)
    |> validate_safe_string(:album)
    |> validate_positive_integer(:station_id)
    |> validate_safe_string(:station_name)
    |> validate_data_size()
  end

  defp validate_rainwave_update(params) do
    field_types = %{
      current_song: :map,
      station_id: :integer,
      station_name: :string,
      listening: :boolean,
      enabled: :boolean
    }

    create_changeset(params, field_types)
    |> validate_positive_integer(:station_id)
    |> validate_safe_string(:station_name)
    |> validate_data_size()
  end

  defp validate_rainwave_station_changed(params) do
    field_types = %{
      station_id: :integer,
      station_name: :string,
      previous_station_id: :integer,
      listening: :boolean
    }

    create_changeset(params, field_types)
    |> validate_positive_integer(:station_id)
    |> validate_safe_string(:station_name)
    |> validate_positive_integer(:previous_station_id)
    |> validate_data_size()
  end

  defp validate_rainwave_listening_started(params) do
    field_types = %{
      station_id: :integer,
      station_name: :string
    }

    create_changeset(params, field_types)
    |> validate_positive_integer(:station_id)
    |> validate_safe_string(:station_name)
    |> validate_data_size()
  end

  defp validate_rainwave_listening_stopped(params) do
    field_types = %{
      station_id: :integer,
      station_name: :string
    }

    create_changeset(params, field_types)
    |> validate_positive_integer(:station_id)
    |> validate_safe_string(:station_name)
    |> validate_data_size()
  end

  # Stream event validation functions
  defp validate_stream_state_updated(params) do
    field_types = %{
      current_show: :string,
      active_content: :map,
      interrupt_stack: {:array, :map},
      ticker_rotation: {:array, :string},
      version: :integer,
      metadata: :map
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:current_show)
    |> validate_data_size()
  end

  defp validate_stream_show_changed(params) do
    field_types = %{
      show: :string,
      game_id: :string,
      game_name: :string,
      title: :string,
      changed_at: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:show])
    |> validate_safe_string(:show)
    |> validate_safe_string(:game_id)
    |> validate_safe_string(:game_name)
    |> validate_safe_string(:title)
    |> validate_iso8601_datetime(:changed_at)
    |> validate_data_size()
  end

  defp validate_stream_interrupt_removed(params) do
    field_types = %{
      interrupt_id: :string,
      interrupt_type: :string,
      removed_at: :utc_datetime
    }

    create_changeset(params, field_types)
    |> validate_safe_string(:interrupt_id)
    |> validate_safe_string(:interrupt_type)
    |> validate_data_size()
  end

  defp validate_stream_emote_increment(params) do
    field_types = %{
      emotes: {:array, :string},
      native_emotes: {:array, :string},
      user_name: :string,
      timestamp: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:emotes, :user_name])
    |> validate_string_list(:emotes)
    |> validate_string_list(:native_emotes)
    |> validate_safe_string(:user_name)
    |> validate_iso8601_datetime(:timestamp)
    |> validate_data_size()
  end

  defp validate_stream_takeover_started(params) do
    field_types = %{
      takeover_type: :string,
      message: :string,
      duration: :integer,
      timestamp: :string
    }

    create_changeset(params, field_types)
    |> validate_required([:takeover_type])
    |> validate_safe_string(:takeover_type)
    |> validate_inclusion(:takeover_type, ["alert", "screen-cover", "manual_override"])
    |> validate_safe_string(:message)
    |> validate_positive_integer(:duration)
    |> validate_iso8601_datetime(:timestamp)
    |> validate_data_size()
  end

  defp validate_stream_takeover_cleared(params) do
    field_types = %{
      timestamp: :string
    }

    create_changeset(params, field_types)
    |> validate_iso8601_datetime(:timestamp)
    |> validate_data_size()
  end

  defp validate_stream_goals_updated(params) do
    field_types = %{
      follower_goal: :map,
      sub_goal: :map,
      new_sub_goal: :map,
      timestamp: :string
    }

    create_changeset(params, field_types)
    |> validate_iso8601_datetime(:timestamp)
    |> validate_data_size()
  end

  # Unknown event types - basic validation to allow extensibility
  defp validate_unknown_event(params) do
    Logger.info("Validating unknown event type with basic validation",
      keys: Map.keys(params),
      data_size: byte_size(:erlang.term_to_binary(params))
    )

    # Basic validation - just ensure data is reasonable size and structure
    if map_size(params) > @max_data_keys do
      {%{}, %{data: :string}}
      |> cast(%{}, [])
      |> add_error(:data, "too many keys (max #{@max_data_keys})")
    else
      {%{}, %{raw_data: :map}}
      |> cast(%{raw_data: params}, [:raw_data])
    end
    |> validate_data_size()
  end

  # Custom Validation Functions

  defp validate_twitch_user_id(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and String.match?(value, ~r/^\d+$/) and
           byte_size(value) <= 50 do
        []
      else
        [{field, "must be a numeric string (Twitch user ID)"}]
      end
    end)
  end

  defp validate_twitch_username(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and String.match?(value, ~r/^[a-zA-Z0-9_]{1,25}$/) do
        []
      else
        [{field, "must be a valid Twitch username (alphanumeric + underscore, 1-25 chars)"}]
      end
    end)
  end

  defp validate_twitch_tier(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if value in ["1000", "2000", "3000"] do
        []
      else
        [{field, "must be a valid Twitch subscription tier (1000, 2000, or 3000)"}]
      end
    end)
  end

  defp validate_safe_string(changeset, field, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, @max_string_length)

    validate_change(changeset, field, fn ^field, value ->
      cond do
        not is_binary(value) ->
          [{field, "must be a string"}]

        byte_size(value) > max_length ->
          [{field, "too long (max #{max_length} bytes)"}]

        String.contains?(value, ["\x00", "\x01", "\x02", "\x03", "\x04"]) ->
          [{field, "contains invalid control characters"}]

        true ->
          []
      end
    end)
  end

  defp validate_chat_message_content(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      cond do
        not is_map(value) ->
          [{field, "message content must be a map"}]

        not is_binary(Map.get(value, "text")) ->
          [{field, "message text must be a string"}]

        byte_size(Map.get(value, "text", "")) > 500 ->
          [{field, "message text too long (max 500 bytes)"}]

        true ->
          []
      end
    end)
  end

  defp validate_string_list(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      cond do
        not is_list(value) ->
          [{field, "must be a list"}]

        length(value) > @max_list_length ->
          [{field, "list too long (max #{@max_list_length} items)"}]

        not Enum.all?(value, &is_binary/1) ->
          [{field, "all list items must be strings"}]

        Enum.any?(value, fn item -> byte_size(item) > 100 end) ->
          [{field, "list items too long (max 100 bytes each)"}]

        true ->
          []
      end
    end)
  end

  defp validate_positive_integer(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_integer(value) and value > 0 do
        []
      else
        [{field, "must be a positive integer"}]
      end
    end)
  end

  defp validate_non_negative_integer(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_integer(value) and value >= 0 do
        []
      else
        [{field, "must be a non-negative integer"}]
      end
    end)
  end

  defp validate_iso8601_datetime(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) do
        case DateTime.from_iso8601(value) do
          {:ok, _, _} -> []
          {:error, _} -> [{field, "must be a valid ISO8601 datetime"}]
        end
      else
        [{field, "must be a string"}]
      end
    end)
  end

  defp validate_data_size(changeset) do
    # Validate overall data size to prevent memory exhaustion
    data_size = byte_size(:erlang.term_to_binary(changeset.changes))

    # 100KB limit
    if data_size > 100_000 do
      add_error(changeset, :data, "event data too large (max 100KB)")
    else
      changeset
    end
  end

  # Helper function to format validation errors for logging
  defp format_validation_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
