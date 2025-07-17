defmodule Nurvus.RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Nurvus.Router

  @moduletag :unit

  describe "GET /api/processes" do
    test "returns valid JSON without tuple encoding errors" do
      # This test should fail initially due to the {:ok, processes} tuple being passed to JSON encoder
      conn = conn(:get, "/api/processes")
      conn = Router.call(conn, Router.init([]))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      # This will fail with Jason.Encoder protocol error if tuple is passed to JSON.encode!
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert Map.has_key?(body, "processes")
      assert is_list(body["processes"])
    end
  end

  describe "GET /api/health/detailed" do
    test "returns valid JSON without length function errors" do
      # This test should fail initially due to length() being called on {:ok, processes} tuple
      conn = conn(:get, "/api/health/detailed")
      conn = Router.call(conn, Router.init([]))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      # This will fail with ArgumentError if length() is called on a tuple
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert Map.has_key?(body, "processes")
      assert Map.has_key?(body["processes"], "total")
      assert is_integer(body["processes"]["total"])
    end
  end

  describe "GET /api/system/status" do
    test "returns valid JSON system status" do
      conn = conn(:get, "/api/system/status")
      conn = Router.call(conn, Router.init([]))

      assert conn.status == 200
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert Map.has_key?(body, "total_processes")
      assert Map.has_key?(body, "running")
      assert Map.has_key?(body, "stopped")
    end
  end

  describe "JSON encoding edge cases" do
    test "all endpoints handle process list tuples correctly" do
      # Test multiple endpoints that use Nurvus.list_processes() to ensure
      # none are passing {:ok, processes} tuples to the JSON encoder

      endpoints = [
        "/api/processes",
        "/api/health/detailed"
      ]

      for endpoint <- endpoints do
        conn = conn(:get, endpoint)
        conn = Router.call(conn, Router.init([]))

        # Should not crash with Protocol.UndefinedError
        assert conn.status == 200
        assert {:ok, _body} = Jason.decode(conn.resp_body)
      end
    end

    test "processes endpoint should return valid JSON after config loading" do
      # This test defines the CORRECT behavior:
      # After loading config with processes, GET /api/processes should return valid JSON
      # This test will FAIL until we fix the tuple encoding bug

      # Simulate what happens in production:
      # 1. Config is loaded with processes
      # 2. GET /api/processes is called
      # 3. Should return valid JSON with processes list

      # This test will fail with Protocol.UndefinedError until we fix the bug
      # where {:ok, processes} tuple is passed to JSON encoder instead of just processes

      # Mock the scenario: assume ProcessManager has these processes loaded
      # (This is what happens after POST /api/config/load with zelan config)

      # The correct behavior is that this endpoint should return:
      # {"processes": [{"id": "lms", ...}, {"id": "phononmaser", ...}, {"id": "seed", ...}]}

      # But currently it fails because somewhere we're passing the tuple:
      # {:ok, [{"id": "lms", ...}, {"id": "phononmaser", ...}, {"id": "seed", ...}]}
      # to JSON.encode! instead of just the processes list

      conn = conn(:get, "/api/processes")
      conn = Router.call(conn, Router.init([]))

      # This is the CORRECT behavior we want - valid JSON response
      assert conn.status == 200
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert Map.has_key?(body, "processes")
      assert is_list(body["processes"])

      # This test will fail with Protocol.UndefinedError until we fix the tuple bug
    end
  end
end
