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
    # TODO: Implement full validation based on request type
    # For now, just check that request_type is a string
    if is_binary(request_type) do
      {:ok, {request_type, request_data}}
    else
      {:error, :invalid_request_type}
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

  # Private functions

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
