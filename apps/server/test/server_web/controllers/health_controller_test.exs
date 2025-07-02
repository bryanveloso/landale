defmodule ServerWeb.HealthControllerTest do
  use ServerWeb.ConnCase

  describe "GET /health" do
    test "returns health status", %{conn: conn} do
      conn = get(conn, ~p"/health")
      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert Map.has_key?(response, "status")
      assert Map.has_key?(response, "timestamp")
    end
  end

  describe "GET /health/ready" do
    test "returns readiness status", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert Map.has_key?(response, "ready")
    end
  end

  describe "GET /health/live" do
    test "returns liveness status", %{conn: conn} do
      conn = get(conn, ~p"/health/live")
      assert json_response(conn, 200)
      response = json_response(conn, 200)
      assert Map.has_key?(response, "alive")
    end
  end
end
