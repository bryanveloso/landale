defmodule Server.Services.OBS.Protocol do
  @moduledoc """
  OBS WebSocket v5 protocol implementation.

  This is a stateless module that handles:
  - Message encoding/decoding
  - Request validation
  - OpCode definitions
  - Event subscription flags

  All functions are pure and have no side effects.
  """

  import Bitwise
  require Logger

  # OBS WebSocket v5 OpCodes
  # These constants document the protocol opcodes.
  # The Connection module pattern matches on numeric values directly.
  @op_hello 0
  @op_hello_response 0
  @op_identify 1
  @op_identified 2
  @op_reidentify 3
  @op_event 5
  @op_request 6
  @op_request_response 7
  @op_request_batch 8
  @op_request_batch_response 9

  # Export opcodes for external use
  def op_hello, do: @op_hello
  def op_hello_response, do: @op_hello_response
  def op_identify, do: @op_identify
  def op_identified, do: @op_identified
  def op_reidentify, do: @op_reidentify
  def op_event, do: @op_event
  def op_request, do: @op_request
  def op_request_response, do: @op_request_response
  def op_request_batch, do: @op_request_batch
  def op_request_batch_response, do: @op_request_batch_response

  # Event subscription flags
  @event_subscription_general 1
  @event_subscription_config 2
  @event_subscription_scenes 4
  @event_subscription_inputs 8
  @event_subscription_transitions 16
  @event_subscription_filters 32
  @event_subscription_outputs 64
  @event_subscription_scene_items 128
  @event_subscription_media_inputs 256
  @event_subscription_vendors 512
  @event_subscription_ui 1024

  @doc """
  Get all non-high-volume event subscriptions.
  """
  def event_subscription_all do
    import Bitwise

    @event_subscription_general |||
      @event_subscription_config |||
      @event_subscription_scenes |||
      @event_subscription_inputs |||
      @event_subscription_transitions |||
      @event_subscription_filters |||
      @event_subscription_outputs |||
      @event_subscription_scene_items |||
      @event_subscription_media_inputs |||
      @event_subscription_vendors |||
      @event_subscription_ui
  end

  @doc """
  Encode a Hello message (OpCode 0).
  """
  def encode_hello(data) do
    encode_message(@op_hello, data)
  end

  @doc """
  Encode an Identify message (OpCode 1).
  """
  def encode_identify(data) do
    encode_message(@op_identify, data)
  end

  @doc """
  Encode a Request message (OpCode 6).
  """
  def encode_request(request_id, request_type, request_data \\ %{}) do
    data = %{
      requestId: request_id,
      requestType: request_type,
      requestData: request_data
    }

    encode_message(@op_request, data)
  end

  @doc """
  Encode a Batch Request message (OpCode 8).
  """
  def encode_batch_request(request_id, requests, options \\ %{}) do
    data = %{
      requestId: request_id,
      requests: requests
    }

    # Add optional fields if present
    data =
      if options[:halt_on_failure] != nil do
        Map.put(data, :haltOnFailure, options.halt_on_failure)
      else
        data
      end

    data =
      if options[:execution_type] do
        Map.put(data, :executionType, options.execution_type)
      else
        data
      end

    encode_message(@op_request_batch, data)
  end

  @doc """
  Encode any OBS WebSocket message.
  """
  def encode_message(op_code, data) do
    message = %{
      op: op_code,
      d: data
    }

    Jason.encode!(message)
  end

  @doc """
  Decode an OBS WebSocket message.
  """
  def decode_message(frame) when is_binary(frame) do
    case Jason.decode(frame) do
      {:ok, %{"op" => op, "d" => data}} ->
        {:ok, %{op: op, d: atomize_keys(data)}}

      {:ok, _} ->
        {:error, :invalid_message_format}

      {:error, reason} ->
        {:error, {:decode_error, reason}}
    end
  end

  @doc """
  Validate a request type and data according to OBS WebSocket v5 spec.
  """
  def validate_request(request_type, request_data) do
    cond do
      not is_binary(request_type) ->
        {:error, :invalid_request_type}

      not is_map(request_data) ->
        {:error, :invalid_request_data}

      true ->
        validate_request_by_type(request_type, request_data)
    end
  end

  @doc """
  Check if an event type matches the subscription flags.
  """
  def event_matches_subscription?(event_type, subscription_flags) do
    required_flag = event_type_to_flag(event_type)
    (subscription_flags &&& required_flag) != 0
  end

  @doc """
  Get the OpCode name for logging.
  """
  def opcode_name(0), do: "Hello"
  def opcode_name(1), do: "Identify"
  def opcode_name(2), do: "Identified"
  def opcode_name(3), do: "Reidentify"
  def opcode_name(5), do: "Event"
  def opcode_name(6), do: "Request"
  def opcode_name(7), do: "RequestResponse"
  def opcode_name(8), do: "RequestBatch"
  def opcode_name(9), do: "RequestBatchResponse"
  def opcode_name(op), do: "Unknown(#{op})"

  @doc """
  Check if a close code indicates an unrecoverable error.
  """
  # Unsupported protocol version
  def unrecoverable_close_code?(4002), do: true
  # Unsupported feature
  def unrecoverable_close_code?(4003), do: true
  # Authentication failed
  def unrecoverable_close_code?(4008), do: true
  def unrecoverable_close_code?(_), do: false

  @doc """
  Generate authentication response for OBS WebSocket v5.
  """
  def generate_auth_response(password, salt, challenge) do
    # OBS v5 auth: base64(sha256(base64(sha256(password + salt)) + challenge))
    password_salt = :crypto.hash(:sha256, password <> salt) |> Base.encode64()
    password_salt_challenge = :crypto.hash(:sha256, password_salt <> challenge) |> Base.encode64()

    password_salt_challenge
  end

  # Private functions

  # Validate specific request types based on OBS WebSocket v5 specification
  defp validate_request_by_type(request_type, request_data) do
    cond do
      scene_request?(request_type) ->
        validate_scene_request(request_type, request_data)

      input_request?(request_type) ->
        validate_input_request(request_type, request_data)

      scene_item_request?(request_type) ->
        validate_scene_item_request_type(request_type, request_data)

      filter_request?(request_type) ->
        validate_filter_request(request_type, request_data)

      stream_recording_request?(request_type) ->
        validate_stream_recording_request(request_type, request_data)

      transition_request?(request_type) ->
        validate_transition_request(request_type, request_data)

      studio_mode_request?(request_type) ->
        validate_studio_mode_request_type(request_type, request_data)

      general_request?(request_type) ->
        validate_general_request(request_type, request_data)

      virtual_cam_request?(request_type) ->
        validate_virtual_cam_request(request_type, request_data)

      true ->
        Logger.warning("Unknown OBS request type: #{request_type}")
        {:ok, {request_type, request_data}}
    end
  end

  # Request type categorization functions
  defp scene_request?(request_type) do
    request_type in [
      "GetSceneList",
      "GetCurrentProgramScene",
      "SetCurrentProgramScene",
      "GetCurrentPreviewScene",
      "SetCurrentPreviewScene"
    ]
  end

  defp input_request?(request_type) do
    request_type in [
      "GetInputList",
      "GetInputKindList",
      "GetInputSettings",
      "SetInputSettings",
      "GetInputMute",
      "SetInputMute",
      "ToggleInputMute",
      "GetInputVolume",
      "SetInputVolume"
    ]
  end

  defp scene_item_request?(request_type) do
    request_type in [
      "GetSceneItemList",
      "GetSceneItemId",
      "SetSceneItemEnabled",
      "GetSceneItemTransform",
      "SetSceneItemTransform"
    ]
  end

  defp filter_request?(request_type) do
    request_type in [
      "GetSourceFilterList",
      "GetSourceFilter",
      "SetSourceFilterEnabled"
    ]
  end

  defp stream_recording_request?(request_type) do
    request_type in [
      "GetStreamStatus",
      "ToggleStream",
      "StartStream",
      "StopStream",
      "GetRecordStatus",
      "ToggleRecord",
      "StartRecord",
      "StopRecord"
    ]
  end

  defp transition_request?(request_type) do
    request_type in [
      "GetCurrentSceneTransition",
      "SetCurrentSceneTransition",
      "TriggerStudioModeTransition"
    ]
  end

  defp studio_mode_request?(request_type) do
    request_type in [
      "GetStudioModeEnabled",
      "SetStudioModeEnabled"
    ]
  end

  defp general_request?(request_type) do
    request_type in [
      "GetVersion",
      "GetStats",
      "BroadcastCustomEvent",
      "Sleep"
    ]
  end

  defp virtual_cam_request?(request_type) do
    request_type in [
      "GetVirtualCamStatus",
      "ToggleVirtualCam",
      "StartVirtualCam",
      "StopVirtualCam"
    ]
  end

  # Category-specific validation functions
  defp validate_scene_request(request_type, request_data) do
    case request_type do
      "GetSceneList" -> validate_empty_request(request_type, request_data)
      "GetCurrentProgramScene" -> validate_empty_request(request_type, request_data)
      "SetCurrentProgramScene" -> validate_scene_name_request(request_type, request_data)
      "GetCurrentPreviewScene" -> validate_empty_request(request_type, request_data)
      "SetCurrentPreviewScene" -> validate_scene_name_request(request_type, request_data)
    end
  end

  defp validate_input_request(request_type, request_data) do
    case request_type do
      "GetInputList" -> validate_optional_input_kind_request(request_type, request_data)
      "GetInputKindList" -> validate_optional_unversioned_request(request_type, request_data)
      "GetInputSettings" -> validate_input_name_request(request_type, request_data)
      "SetInputSettings" -> validate_input_settings_request(request_type, request_data)
      "GetInputMute" -> validate_input_name_request(request_type, request_data)
      "SetInputMute" -> validate_input_mute_request(request_type, request_data)
      "ToggleInputMute" -> validate_input_name_request(request_type, request_data)
      "GetInputVolume" -> validate_input_name_request(request_type, request_data)
      "SetInputVolume" -> validate_input_volume_request(request_type, request_data)
    end
  end

  defp validate_scene_item_request_type(request_type, request_data) do
    case request_type do
      "GetSceneItemList" -> validate_scene_name_request(request_type, request_data)
      "GetSceneItemId" -> validate_scene_item_search_request(request_type, request_data)
      "SetSceneItemEnabled" -> validate_scene_item_enabled_request(request_type, request_data)
      "GetSceneItemTransform" -> validate_scene_item_request(request_type, request_data)
      "SetSceneItemTransform" -> validate_scene_item_transform_request(request_type, request_data)
    end
  end

  defp validate_filter_request(request_type, request_data) do
    case request_type do
      "GetSourceFilterList" -> validate_source_name_request(request_type, request_data)
      "GetSourceFilter" -> validate_source_filter_request(request_type, request_data)
      "SetSourceFilterEnabled" -> validate_source_filter_enabled_request(request_type, request_data)
    end
  end

  defp validate_stream_recording_request(request_type, request_data) do
    case request_type do
      "GetStreamStatus" -> validate_empty_request(request_type, request_data)
      "ToggleStream" -> validate_empty_request(request_type, request_data)
      "StartStream" -> validate_empty_request(request_type, request_data)
      "StopStream" -> validate_empty_request(request_type, request_data)
      "GetRecordStatus" -> validate_empty_request(request_type, request_data)
      "ToggleRecord" -> validate_empty_request(request_type, request_data)
      "StartRecord" -> validate_empty_request(request_type, request_data)
      "StopRecord" -> validate_empty_request(request_type, request_data)
    end
  end

  defp validate_transition_request(request_type, request_data) do
    case request_type do
      "GetCurrentSceneTransition" -> validate_empty_request(request_type, request_data)
      "SetCurrentSceneTransition" -> validate_transition_name_request(request_type, request_data)
      "TriggerStudioModeTransition" -> validate_empty_request(request_type, request_data)
    end
  end

  defp validate_studio_mode_request_type(request_type, request_data) do
    case request_type do
      "GetStudioModeEnabled" -> validate_empty_request(request_type, request_data)
      "SetStudioModeEnabled" -> validate_studio_mode_request(request_type, request_data)
    end
  end

  defp validate_general_request(request_type, request_data) do
    case request_type do
      "GetVersion" -> validate_empty_request(request_type, request_data)
      "GetStats" -> validate_empty_request(request_type, request_data)
      "BroadcastCustomEvent" -> validate_broadcast_event_request(request_type, request_data)
      "Sleep" -> validate_sleep_request(request_type, request_data)
    end
  end

  defp validate_virtual_cam_request(request_type, request_data) do
    case request_type do
      "GetVirtualCamStatus" -> validate_empty_request(request_type, request_data)
      "ToggleVirtualCam" -> validate_empty_request(request_type, request_data)
      "StartVirtualCam" -> validate_empty_request(request_type, request_data)
      "StopVirtualCam" -> validate_empty_request(request_type, request_data)
    end
  end

  # Validation helper functions for different request patterns

  defp validate_empty_request(request_type, request_data) do
    if map_size(request_data) == 0 do
      {:ok, {request_type, request_data}}
    else
      {:error, {:invalid_request_data, "Expected empty request data"}}
    end
  end

  defp validate_scene_name_request(request_type, request_data) do
    case Map.get(request_data, "sceneName") do
      scene_name when is_binary(scene_name) ->
        {:ok, {request_type, request_data}}

      _ ->
        {:error, {:invalid_request_data, "Missing or invalid sceneName"}}
    end
  end

  defp validate_input_name_request(request_type, request_data) do
    case Map.get(request_data, "inputName") do
      input_name when is_binary(input_name) ->
        {:ok, {request_type, request_data}}

      _ ->
        {:error, {:invalid_request_data, "Missing or invalid inputName"}}
    end
  end

  defp validate_source_name_request(request_type, request_data) do
    case Map.get(request_data, "sourceName") do
      source_name when is_binary(source_name) ->
        {:ok, {request_type, request_data}}

      _ ->
        {:error, {:invalid_request_data, "Missing or invalid sourceName"}}
    end
  end

  defp validate_optional_input_kind_request(_request_type, request_data) do
    case Map.get(request_data, "inputKind") do
      nil -> {:ok, {"", request_data}}
      input_kind when is_binary(input_kind) -> {:ok, {"", request_data}}
      _ -> {:error, {:invalid_request_data, "Invalid inputKind"}}
    end
  end

  defp validate_optional_unversioned_request(_request_type, request_data) do
    case Map.get(request_data, "unversioned") do
      nil -> {:ok, {"", request_data}}
      unversioned when is_boolean(unversioned) -> {:ok, {"", request_data}}
      _ -> {:error, {:invalid_request_data, "Invalid unversioned flag"}}
    end
  end

  defp validate_input_settings_request(_request_type, request_data) do
    with input_name when is_binary(input_name) <- Map.get(request_data, "inputName"),
         input_settings when is_map(input_settings) <- Map.get(request_data, "inputSettings") do
      {:ok, {"", request_data}}
    else
      _ -> {:error, {:invalid_request_data, "Missing or invalid inputName or inputSettings"}}
    end
  end

  defp validate_input_mute_request(_request_type, request_data) do
    with input_name when is_binary(input_name) <- Map.get(request_data, "inputName"),
         input_muted when is_boolean(input_muted) <- Map.get(request_data, "inputMuted") do
      {:ok, {"", request_data}}
    else
      _ -> {:error, {:invalid_request_data, "Missing or invalid inputName or inputMuted"}}
    end
  end

  defp validate_input_volume_request(request_type, request_data) do
    input_name = Map.get(request_data, "inputName")
    input_volume_mul = Map.get(request_data, "inputVolumeMul")
    input_volume_db = Map.get(request_data, "inputVolumeDb")

    cond do
      not is_binary(input_name) ->
        {:error, {:invalid_request_data, "Missing or invalid inputName"}}

      input_volume_mul != nil and not is_number(input_volume_mul) ->
        {:error, {:invalid_request_data, "Invalid inputVolumeMul"}}

      input_volume_db != nil and not is_number(input_volume_db) ->
        {:error, {:invalid_request_data, "Invalid inputVolumeDb"}}

      input_volume_mul == nil and input_volume_db == nil ->
        {:error, {:invalid_request_data, "Must specify either inputVolumeMul or inputVolumeDb"}}

      true ->
        {:ok, {request_type, request_data}}
    end
  end

  defp validate_scene_item_search_request(_request_type, request_data) do
    with scene_name when is_binary(scene_name) <- Map.get(request_data, "sceneName"),
         source_name when is_binary(source_name) <- Map.get(request_data, "sourceName") do
      {:ok, {"", request_data}}
    else
      _ -> {:error, {:invalid_request_data, "Missing or invalid sceneName or sourceName"}}
    end
  end

  defp validate_scene_item_request(_request_type, request_data) do
    with scene_name when is_binary(scene_name) <- Map.get(request_data, "sceneName"),
         scene_item_id when is_integer(scene_item_id) <- Map.get(request_data, "sceneItemId") do
      {:ok, {"", request_data}}
    else
      _ -> {:error, {:invalid_request_data, "Missing or invalid sceneName or sceneItemId"}}
    end
  end

  defp validate_scene_item_enabled_request(_request_type, request_data) do
    with scene_name when is_binary(scene_name) <- Map.get(request_data, "sceneName"),
         scene_item_id when is_integer(scene_item_id) <- Map.get(request_data, "sceneItemId"),
         scene_item_enabled when is_boolean(scene_item_enabled) <- Map.get(request_data, "sceneItemEnabled") do
      {:ok, {"", request_data}}
    else
      _ -> {:error, {:invalid_request_data, "Missing or invalid sceneName, sceneItemId, or sceneItemEnabled"}}
    end
  end

  defp validate_scene_item_transform_request(_request_type, request_data) do
    with scene_name when is_binary(scene_name) <- Map.get(request_data, "sceneName"),
         scene_item_id when is_integer(scene_item_id) <- Map.get(request_data, "sceneItemId"),
         scene_item_transform when is_map(scene_item_transform) <- Map.get(request_data, "sceneItemTransform") do
      {:ok, {"", request_data}}
    else
      _ -> {:error, {:invalid_request_data, "Missing or invalid sceneName, sceneItemId, or sceneItemTransform"}}
    end
  end

  defp validate_source_filter_request(_request_type, request_data) do
    with source_name when is_binary(source_name) <- Map.get(request_data, "sourceName"),
         filter_name when is_binary(filter_name) <- Map.get(request_data, "filterName") do
      {:ok, {"", request_data}}
    else
      _ -> {:error, {:invalid_request_data, "Missing or invalid sourceName or filterName"}}
    end
  end

  defp validate_source_filter_enabled_request(_request_type, request_data) do
    with source_name when is_binary(source_name) <- Map.get(request_data, "sourceName"),
         filter_name when is_binary(filter_name) <- Map.get(request_data, "filterName"),
         filter_enabled when is_boolean(filter_enabled) <- Map.get(request_data, "filterEnabled") do
      {:ok, {"", request_data}}
    else
      _ -> {:error, {:invalid_request_data, "Missing or invalid sourceName, filterName, or filterEnabled"}}
    end
  end

  defp validate_transition_name_request(request_type, request_data) do
    case Map.get(request_data, "transitionName") do
      transition_name when is_binary(transition_name) ->
        {:ok, {request_type, request_data}}

      _ ->
        {:error, {:invalid_request_data, "Missing or invalid transitionName"}}
    end
  end

  defp validate_studio_mode_request(request_type, request_data) do
    case Map.get(request_data, "studioModeEnabled") do
      studio_mode_enabled when is_boolean(studio_mode_enabled) ->
        {:ok, {request_type, request_data}}

      _ ->
        {:error, {:invalid_request_data, "Missing or invalid studioModeEnabled"}}
    end
  end

  defp validate_broadcast_event_request(request_type, request_data) do
    case Map.get(request_data, "eventData") do
      event_data when is_map(event_data) ->
        {:ok, {request_type, request_data}}

      _ ->
        {:error, {:invalid_request_data, "Missing or invalid eventData"}}
    end
  end

  defp validate_sleep_request(request_type, request_data) do
    case Map.get(request_data, "sleepMillis") do
      sleep_millis when is_integer(sleep_millis) and sleep_millis >= 0 ->
        if sleep_millis > 50_000 do
          {:error, {:invalid_request_data, "sleepMillis cannot exceed 50_000ms"}}
        else
          {:ok, {request_type, request_data}}
        end

      _ ->
        {:error, {:invalid_request_data, "Missing or invalid sleepMillis"}}
    end
  end

  defp event_type_to_flag(event_type) do
    # Map event types to their subscription flags
    # This is a simplified version - full implementation would
    # categorize all OBS events
    cond do
      String.contains?(event_type, "Scene") -> @event_subscription_scenes
      String.contains?(event_type, "Input") -> @event_subscription_inputs
      String.contains?(event_type, "Stream") -> @event_subscription_outputs
      String.contains?(event_type, "Record") -> @event_subscription_outputs
      true -> @event_subscription_general
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        {String.to_atom(key), atomize_keys(value)}

      {key, value} ->
        {key, atomize_keys(value)}
    end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value
end
