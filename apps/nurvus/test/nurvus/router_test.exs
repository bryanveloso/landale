defmodule Nurvus.RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Nurvus.Router

  @moduletag :unit

  describe "GET /api/processes" do
    test "returns JSON with processes array" do
      # INTENDED BEHAVIOR: /api/processes should return {"processes": []} JSON
      conn = conn(:get, "/api/processes")
      conn = Router.call(conn, Router.init([]))

      # Should return 200 status
      assert conn.status == 200

      # Should have correct content type
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      # Should return valid JSON that can be decoded
      assert {:ok, body} = Jason.decode(conn.resp_body)

      # Should have processes key with a list value (the INTENDED behavior)
      assert Map.has_key?(body, "processes")
      assert is_list(body["processes"])
    end
  end

  describe "Health check" do
    test "basic health endpoint works" do
      conn = conn(:get, "/health")
      conn = Router.call(conn, Router.init([]))

      # Status can be 200 (healthy) or 503 (degraded/unhealthy) depending on process state
      assert conn.status in [200, 503]
      assert {:ok, body} = Jason.decode(conn.resp_body)
      assert body["status"] in ["healthy", "degraded", "unhealthy"]
      assert body["service"] == "nurvus"
      assert is_integer(body["uptime_seconds"])
    end
  end
end
