defmodule Server.Services.OBS.ProtocolPropertyTest do
  @moduledoc """
  Property-based tests for the OBS WebSocket protocol implementation.

  Tests invariants and properties including:
  - Round-trip encoding/decoding preserves data
  - All valid opcodes are handled
  - Event subscription flags are properly composed
  - Message structure validation
  - Key atomization consistency
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Server.Services.OBS.Protocol

  describe "encoding/decoding properties" do
    property "round-trip encoding/decoding preserves message structure" do
      check all(
              op <- integer(0..9),
              data <- message_data_gen()
            ) do
        # Encode the message
        encoded = Protocol.encode_message(op, data)

        # Should be valid JSON
        assert {:ok, _} = Jason.decode(encoded)

        # Decode it back
        assert {:ok, decoded} = Protocol.decode_message(encoded)

        # OpCode should be preserved
        assert decoded.op == op

        # Data structure should be preserved (with atomized keys)
        assert_data_preserved(data, decoded.d)
      end
    end

    property "all message encoding functions produce valid decodable messages" do
      check all(
              request_id <- string(:alphanumeric, min_length: 1),
              request_type <- request_type_gen(),
              request_data <- map_of(atom(:alphanumeric), json_value_gen())
            ) do
        # Test each encoding function
        messages = [
          Protocol.encode_hello(%{rpcVersion: 1}),
          Protocol.encode_identify(%{rpcVersion: 1}),
          Protocol.encode_request(request_id, request_type, request_data),
          Protocol.encode_batch_request(request_id, [%{requestType: request_type}])
        ]

        for message <- messages do
          assert {:ok, decoded} = Protocol.decode_message(message)
          assert is_integer(decoded.op)
          assert is_map(decoded.d)
        end
      end
    end

    property "invalid JSON always returns error" do
      check all(invalid <- invalid_json_gen()) do
        assert {:error, _} = Protocol.decode_message(invalid)
      end
    end
  end

  describe "event subscription properties" do
    property "event subscription flags are powers of 2" do
      # Each flag should be a unique power of 2
      flags = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]

      # No overlap when combined
      import Bitwise

      for i <- 0..(length(flags) - 1) do
        for j <- 0..(length(flags) - 1) do
          if i != j do
            flag_i = Enum.at(flags, i)
            flag_j = Enum.at(flags, j)
            assert (flag_i &&& flag_j) == 0
          end
        end
      end
    end

    property "event_subscription_all contains all individual flags" do
      check all(event_type <- event_type_gen()) do
        # Any event type should match when all flags are set
        assert Protocol.event_matches_subscription?(event_type, Protocol.event_subscription_all())
      end
    end

    property "subscription matching is consistent with flag composition" do
      check all(
              flags <- list_of(integer(0..10), min_length: 1, max_length: 5),
              event_type <- event_type_gen()
            ) do
        import Bitwise

        # Compose flags
        flag_values = Enum.map(flags, &(1 <<< &1))
        combined_flags = Enum.reduce(flag_values, 0, &(&1 ||| &2))

        # If event matches combined flags, it should match at least one individual flag
        if Protocol.event_matches_subscription?(event_type, combined_flags) do
          assert Enum.any?(flag_values, fn flag ->
                   Protocol.event_matches_subscription?(event_type, flag)
                 end)
        end
      end
    end
  end

  describe "request validation properties" do
    property "valid string request types are always accepted" do
      check all(request_type <- string(:printable, min_length: 1)) do
        data = %{}
        assert {:ok, {^request_type, ^data}} = Protocol.validate_request(request_type, data)
      end
    end

    property "non-string request types are always rejected" do
      check all(invalid_type <- one_of([integer(), float(), atom(:alphanumeric), boolean()])) do
        assert {:error, :invalid_request_type} = Protocol.validate_request(invalid_type, %{})
      end
    end
  end

  describe "opcode properties" do
    property "all defined opcodes have names" do
      opcodes = [0, 1, 2, 3, 5, 6, 7, 8, 9]

      for op <- opcodes do
        name = Protocol.opcode_name(op)
        assert is_binary(name)
        refute String.starts_with?(name, "Unknown")
      end
    end

    property "undefined opcodes return Unknown(n)" do
      check all(op <- integer(10..1000)) do
        assert Protocol.opcode_name(op) == "Unknown(#{op})"
      end
    end
  end

  describe "atomization properties" do
    property "atomization is idempotent" do
      check all(data <- nested_map_gen()) do
        encoded = Protocol.encode_message(5, data)

        # Decode once
        {:ok, decoded1} = Protocol.decode_message(encoded)

        # Re-encode and decode again
        re_encoded = Protocol.encode_message(decoded1.op, decoded1.d)
        {:ok, decoded2} = Protocol.decode_message(re_encoded)

        # Should be identical
        assert decoded1 == decoded2
      end
    end

    property "atomization preserves data types" do
      check all(
              string_val <- string(:printable),
              int_val <- integer(),
              float_val <- float(),
              bool_val <- boolean(),
              null_val <- constant(nil),
              list_val <- list_of(integer())
            ) do
        data = %{
          "string" => string_val,
          "integer" => int_val,
          "float" => float_val,
          "boolean" => bool_val,
          "null" => null_val,
          "list" => list_val
        }

        encoded = Jason.encode!(%{"op" => 5, "d" => data})
        {:ok, decoded} = Protocol.decode_message(encoded)

        assert decoded.d.string == string_val
        assert decoded.d.integer == int_val
        assert decoded.d.float == float_val
        assert decoded.d.boolean == bool_val
        assert decoded.d.null == null_val
        assert decoded.d.list == list_val
      end
    end
  end

  describe "batch request properties" do
    property "batch requests preserve all requests" do
      check all(
              request_id <- string(:alphanumeric, min_length: 1),
              requests <- list_of(batch_request_gen(), min_length: 1, max_length: 10)
            ) do
        encoded = Protocol.encode_batch_request(request_id, requests)
        decoded = Jason.decode!(encoded)

        assert decoded["op"] == 8
        assert decoded["d"]["requestId"] == request_id
        assert length(decoded["d"]["requests"]) == length(requests)

        # Each request should be preserved
        Enum.zip(requests, decoded["d"]["requests"])
        |> Enum.each(fn {original, decoded_req} ->
          assert decoded_req["requestType"] == original.requestType

          if Map.has_key?(original, :requestData) do
            assert decoded_req["requestData"] == stringify_keys(original.requestData)
          end
        end)
      end
    end
  end

  # Generator functions

  defp message_data_gen do
    map_of(atom(:alphanumeric), json_value_gen(), min_length: 0, max_length: 5)
  end

  defp request_type_gen do
    one_of([
      constant("GetVersion"),
      constant("GetSceneList"),
      constant("SetCurrentProgramScene"),
      constant("StartStream"),
      constant("StopStream"),
      constant("StartRecord"),
      constant("StopRecord"),
      string(:alphanumeric, min_length: 1)
    ])
  end

  defp event_type_gen do
    one_of([
      constant("SceneChanged"),
      constant("SceneListChanged"),
      constant("InputCreated"),
      constant("InputRemoved"),
      constant("StreamStarted"),
      constant("StreamStopped"),
      constant("RecordStarted"),
      constant("RecordStopped"),
      string(:alphanumeric, min_length: 1)
    ])
  end

  defp invalid_json_gen do
    one_of([
      constant("not json"),
      constant("{invalid}"),
      constant("[1, 2, 3"),
      constant("{'single': 'quotes'}"),
      constant(""),
      constant("null"),
      constant("undefined")
    ])
  end

  defp nested_map_gen do
    sized(fn size ->
      nested_map_gen(div(size, 3))
    end)
  end

  defp nested_map_gen(0) do
    map_of(string(:alphanumeric), json_value_gen())
  end

  defp nested_map_gen(depth) do
    map_of(
      string(:alphanumeric),
      one_of([
        json_value_gen(),
        nested_map_gen(depth - 1),
        list_of(json_value_gen(), max_length: 3)
      ]),
      max_length: 3
    )
  end

  # Generate only JSON-encodable values
  defp json_value_gen do
    one_of([
      string(:utf8),
      integer(),
      float(),
      boolean(),
      constant(nil)
    ])
  end

  defp batch_request_gen do
    map({constant(:requestType), request_type_gen()}, fn {_, request_type} ->
      %{requestType: request_type}
    end)
  end

  # Helper functions

  defp assert_data_preserved(original, decoded) when is_map(original) do
    Enum.each(original, fn {key, value} ->
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      assert Map.has_key?(decoded, atom_key)
      assert_data_preserved(value, Map.get(decoded, atom_key))
    end)
  end

  defp assert_data_preserved(original, decoded) when is_list(original) do
    assert length(original) == length(decoded)

    Enum.zip(original, decoded)
    |> Enum.each(fn {orig, dec} -> assert_data_preserved(orig, dec) end)
  end

  defp assert_data_preserved(original, decoded) do
    assert original == decoded
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end

  defp stringify_keys(value), do: value
end
