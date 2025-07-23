defmodule Server.Services.OBS.ProtocolTest do
  @moduledoc """
  Unit tests for the OBS WebSocket v5 protocol implementation.

  Tests the stateless protocol module including:
  - Message encoding for all message types
  - Message decoding with key atomization
  - OpCode definitions and helpers
  - Event subscription flags
  - Request validation
  - Close code handling
  """
  use ExUnit.Case, async: true

  alias Server.Services.OBS.Protocol

  describe "opcodes" do
    test "exports all opcode constants" do
      assert Protocol.op_hello() == 0
      assert Protocol.op_hello_response() == 0
      assert Protocol.op_identify() == 1
      assert Protocol.op_identified() == 2
      assert Protocol.op_reidentify() == 3
      assert Protocol.op_event() == 5
      assert Protocol.op_request() == 6
      assert Protocol.op_request_response() == 7
      assert Protocol.op_request_batch() == 8
      assert Protocol.op_request_batch_response() == 9
    end

    test "opcode_name/1 returns human-readable names" do
      assert Protocol.opcode_name(0) == "Hello"
      assert Protocol.opcode_name(1) == "Identify"
      assert Protocol.opcode_name(2) == "Identified"
      assert Protocol.opcode_name(3) == "Reidentify"
      assert Protocol.opcode_name(5) == "Event"
      assert Protocol.opcode_name(6) == "Request"
      assert Protocol.opcode_name(7) == "RequestResponse"
      assert Protocol.opcode_name(8) == "RequestBatch"
      assert Protocol.opcode_name(9) == "RequestBatchResponse"
      assert Protocol.opcode_name(99) == "Unknown(99)"
    end
  end

  describe "event subscriptions" do
    test "event_subscription_all includes all non-high-volume subscriptions" do
      all_flags = Protocol.event_subscription_all()

      # Should be the bitwise OR of all flags (1 + 2 + 4 + ... + 1024 = 2047)
      assert all_flags == 2047

      # Verify it's composed of all individual flags
      import Bitwise
      # general
      assert (all_flags &&& 1) != 0
      # config
      assert (all_flags &&& 2) != 0
      # scenes
      assert (all_flags &&& 4) != 0
      # inputs
      assert (all_flags &&& 8) != 0
      # transitions
      assert (all_flags &&& 16) != 0
      # filters
      assert (all_flags &&& 32) != 0
      # outputs
      assert (all_flags &&& 64) != 0
      # scene_items
      assert (all_flags &&& 128) != 0
      # media_inputs
      assert (all_flags &&& 256) != 0
      # vendors
      assert (all_flags &&& 512) != 0
      # ui
      assert (all_flags &&& 1024) != 0
    end

    test "event_matches_subscription? correctly matches event types" do
      # Scene events require scenes flag (4)
      assert Protocol.event_matches_subscription?("SceneChanged", 4)
      assert Protocol.event_matches_subscription?("SceneListChanged", 4)
      # inputs flag
      refute Protocol.event_matches_subscription?("SceneChanged", 8)

      # Input events require inputs flag (8)
      assert Protocol.event_matches_subscription?("InputCreated", 8)
      assert Protocol.event_matches_subscription?("InputRemoved", 8)
      # scenes flag
      refute Protocol.event_matches_subscription?("InputCreated", 4)

      # Stream events require outputs flag (64)
      assert Protocol.event_matches_subscription?("StreamStarted", 64)
      assert Protocol.event_matches_subscription?("StreamStopped", 64)

      # Record events also use outputs flag
      assert Protocol.event_matches_subscription?("RecordStarted", 64)
      assert Protocol.event_matches_subscription?("RecordStopped", 64)

      # General events use general flag (1)
      assert Protocol.event_matches_subscription?("SomethingElse", 1)

      # All events match when all flags are set
      assert Protocol.event_matches_subscription?("SceneChanged", Protocol.event_subscription_all())
      assert Protocol.event_matches_subscription?("InputCreated", Protocol.event_subscription_all())
    end
  end

  describe "encode_hello/1" do
    test "encodes hello message with all fields" do
      data = %{
        rpcVersion: 1,
        eventSubscriptions: 2047
      }

      encoded = Protocol.encode_hello(data)
      decoded = Jason.decode!(encoded)

      assert decoded["op"] == 0
      assert decoded["d"]["rpcVersion"] == 1
      assert decoded["d"]["eventSubscriptions"] == 2047
    end
  end

  describe "encode_identify/1" do
    test "encodes identify message without authentication" do
      data = %{
        rpcVersion: 1,
        eventSubscriptions: 2047
      }

      encoded = Protocol.encode_identify(data)
      decoded = Jason.decode!(encoded)

      assert decoded["op"] == 1
      assert decoded["d"]["rpcVersion"] == 1
      assert decoded["d"]["eventSubscriptions"] == 2047
    end

    test "encodes identify message with authentication" do
      data = %{
        rpcVersion: 1,
        authentication: "base64_auth_string",
        eventSubscriptions: 2047
      }

      encoded = Protocol.encode_identify(data)
      decoded = Jason.decode!(encoded)

      assert decoded["op"] == 1
      assert decoded["d"]["authentication"] == "base64_auth_string"
    end
  end

  describe "encode_request/3" do
    test "encodes request with just type" do
      encoded = Protocol.encode_request("req_123", "GetVersion")
      decoded = Jason.decode!(encoded)

      assert decoded["op"] == 6
      assert decoded["d"]["requestId"] == "req_123"
      assert decoded["d"]["requestType"] == "GetVersion"
      assert decoded["d"]["requestData"] == %{}
    end

    test "encodes request with data" do
      request_data = %{sceneName: "Scene 1", sceneIndex: 0}
      encoded = Protocol.encode_request("req_456", "SetCurrentProgramScene", request_data)
      decoded = Jason.decode!(encoded)

      assert decoded["op"] == 6
      assert decoded["d"]["requestId"] == "req_456"
      assert decoded["d"]["requestType"] == "SetCurrentProgramScene"
      assert decoded["d"]["requestData"]["sceneName"] == "Scene 1"
      assert decoded["d"]["requestData"]["sceneIndex"] == 0
    end
  end

  describe "encode_batch_request/3" do
    test "encodes batch request with minimal fields" do
      requests = [
        %{requestType: "GetVersion"},
        %{requestType: "GetSceneList"}
      ]

      encoded = Protocol.encode_batch_request("batch_1", requests)
      decoded = Jason.decode!(encoded)

      assert decoded["op"] == 8
      assert decoded["d"]["requestId"] == "batch_1"
      assert length(decoded["d"]["requests"]) == 2
      assert Enum.at(decoded["d"]["requests"], 0)["requestType"] == "GetVersion"
      assert Enum.at(decoded["d"]["requests"], 1)["requestType"] == "GetSceneList"
    end

    test "encodes batch request with options" do
      requests = [
        %{requestType: "StartStream"},
        %{requestType: "StartRecord"}
      ]

      options = %{
        halt_on_failure: true,
        execution_type: "serial"
      }

      encoded = Protocol.encode_batch_request("batch_2", requests, options)
      decoded = Jason.decode!(encoded)

      assert decoded["op"] == 8
      assert decoded["d"]["haltOnFailure"] == true
      assert decoded["d"]["executionType"] == "serial"
    end

    test "omits nil options" do
      requests = [%{requestType: "GetVersion"}]
      options = %{halt_on_failure: nil, execution_type: nil}

      encoded = Protocol.encode_batch_request("batch_3", requests, options)
      decoded = Jason.decode!(encoded)

      refute Map.has_key?(decoded["d"], "haltOnFailure")
      refute Map.has_key?(decoded["d"], "executionType")
    end
  end

  describe "decode_message/1" do
    test "decodes valid message with atomized keys" do
      frame = ~s({"op": 5, "d": {"eventType": "SceneChanged", "eventData": {"sceneName": "New Scene"}}})

      assert {:ok, decoded} = Protocol.decode_message(frame)
      assert decoded.op == 5
      assert decoded.d.eventType == "SceneChanged"
      assert decoded.d.eventData.sceneName == "New Scene"
    end

    test "handles nested structures with atomization" do
      frame = ~s({
        "op": 7,
        "d": {
          "requestId": "req_123",
          "requestStatus": {
            "result": true,
            "code": 100
          },
          "responseData": {
            "scenes": [
              {"sceneName": "Scene 1", "sceneIndex": 0},
              {"sceneName": "Scene 2", "sceneIndex": 1}
            ]
          }
        }
      })

      assert {:ok, decoded} = Protocol.decode_message(frame)
      assert decoded.d.requestId == "req_123"
      assert decoded.d.requestStatus.result == true
      assert decoded.d.requestStatus.code == 100
      assert length(decoded.d.responseData.scenes) == 2
      assert hd(decoded.d.responseData.scenes).sceneName == "Scene 1"
    end

    test "returns error for invalid JSON" do
      assert {:error, {:decode_error, _}} = Protocol.decode_message("invalid json")
    end

    test "returns error for missing required fields" do
      assert {:error, :invalid_message_format} = Protocol.decode_message(~s({"data": "missing op"}))
    end

    test "preserves non-string keys during atomization" do
      frame = ~s({"op": 7, "d": {"mixed": {"string_key": "value", "already_atom": true}}})

      assert {:ok, decoded} = Protocol.decode_message(frame)
      assert decoded.d.mixed.string_key == "value"
      assert decoded.d.mixed.already_atom == true
    end
  end

  describe "validate_request/2" do
    test "validates request with string type" do
      assert {:ok, {"GetVersion", %{}}} = Protocol.validate_request("GetVersion", %{})

      assert {:ok, {"SetCurrentProgramScene", %{sceneName: "Scene 1"}}} =
               Protocol.validate_request("SetCurrentProgramScene", %{sceneName: "Scene 1"})
    end

    test "rejects non-string request types" do
      assert {:error, :invalid_request_type} = Protocol.validate_request(123, %{})
      assert {:error, :invalid_request_type} = Protocol.validate_request(:atom_type, %{})
      assert {:error, :invalid_request_type} = Protocol.validate_request(nil, %{})
    end
  end

  describe "unrecoverable_close_code?/1" do
    test "identifies unrecoverable close codes" do
      # Unrecoverable codes
      # Unsupported protocol version
      assert Protocol.unrecoverable_close_code?(4002)
      # Unsupported feature
      assert Protocol.unrecoverable_close_code?(4003)
      # Authentication failed
      assert Protocol.unrecoverable_close_code?(4008)

      # Recoverable codes
      # Normal closure
      refute Protocol.unrecoverable_close_code?(1000)
      # Going away
      refute Protocol.unrecoverable_close_code?(1001)
      # Already identified
      refute Protocol.unrecoverable_close_code?(4009)
      # Session invalidated
      refute Protocol.unrecoverable_close_code?(4010)
      # Unsupported feature
      refute Protocol.unrecoverable_close_code?(4011)
    end
  end

  describe "edge cases" do
    test "handles empty data in messages" do
      encoded = Protocol.encode_message(0, %{})
      decoded = Jason.decode!(encoded)

      assert decoded["op"] == 0
      assert decoded["d"] == %{}
    end

    test "preserves numeric values during encoding" do
      data = %{
        intValue: 42,
        floatValue: 3.14,
        bigValue: 9_999_999_999
      }

      encoded = Protocol.encode_request("req_num", "TestNumbers", data)
      decoded = Jason.decode!(encoded)

      assert decoded["d"]["requestData"]["intValue"] == 42
      assert decoded["d"]["requestData"]["floatValue"] == 3.14
      assert decoded["d"]["requestData"]["bigValue"] == 9_999_999_999
    end

    test "handles unicode in messages" do
      data = %{
        sceneName: "🎬 Scene with émojis",
        description: "日本語のテスト"
      }

      encoded = Protocol.encode_request("req_unicode", "CreateScene", data)
      decoded = Jason.decode!(encoded)

      assert decoded["d"]["requestData"]["sceneName"] == "🎬 Scene with émojis"
      assert decoded["d"]["requestData"]["description"] == "日本語のテスト"
    end
  end
end
