defmodule Server.Services.OBS.BatchRequestTest do
  use ExUnit.Case, async: true

  alias Server.Services.OBS.Protocol

  describe "batch request encoding" do
    test "encode_batch_request creates valid batch request" do
      requests = [
        %{
          requestType: "GetSceneList",
          requestId: "1"
        },
        %{
          requestType: "GetVersion",
          requestId: "2"
        }
      ]

      encoded = Protocol.encode_batch_request("batch_test", requests)
      {:ok, decoded} = Jason.decode(encoded)

      assert decoded["op"] == 8
      assert decoded["d"]["requestId"] == "batch_test"
      assert length(decoded["d"]["requests"]) == 2
    end

    test "encode_batch_request with halt_on_failure option" do
      requests = [
        %{requestType: "GetSceneList", requestId: "1"}
      ]

      options = %{halt_on_failure: true}
      encoded = Protocol.encode_batch_request("batch_halt", requests, options)
      {:ok, decoded} = Jason.decode(encoded)

      assert decoded["d"]["haltOnFailure"] == true
    end

    test "encode_batch_request with execution_type option" do
      requests = [
        %{requestType: "GetSceneList", requestId: "1"}
      ]

      options = %{execution_type: "serial"}
      encoded = Protocol.encode_batch_request("batch_serial", requests, options)
      {:ok, decoded} = Jason.decode(encoded)

      assert decoded["d"]["executionType"] == "serial"
    end
  end
end
