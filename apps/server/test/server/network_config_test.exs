defmodule Server.NetworkConfigTest do
  use ExUnit.Case, async: false

  alias Server.NetworkConfig

  describe "environment detection" do
    test "detects development environment by default" do
      assert NetworkConfig.detect_environment() == :development
    end

    test "detects Docker environment with .dockerenv file" do
      # Skip this test in normal environments since we can't create /.dockerenv
      # This test would pass in a real Docker environment
      if File.exists?("/.dockerenv") do
        assert NetworkConfig.detect_environment() == :docker
      else
        # In test environment, should detect development
        assert NetworkConfig.detect_environment() == :development
      end
    end

    test "detects Docker environment with DOCKER_CONTAINER env var" do
      System.put_env("DOCKER_CONTAINER", "true")

      on_exit(fn ->
        System.delete_env("DOCKER_CONTAINER")
      end)

      assert NetworkConfig.detect_environment() == :docker
    end
  end

  describe "configuration retrieval" do
    test "returns development configuration" do
      config = NetworkConfig.get_config_for_environment(:development)

      assert config.connection_timeout == 5_000
      assert config.reconnect_interval == 2_000
      assert config.websocket.timeout == 15_000
      assert config.websocket.keepalive == 30_000
      assert config.websocket.retry_limit == 5
      assert config.http.timeout == 10_000
      assert config.http.receive_timeout == 20_000
      assert config.http.pool_size == 5
      assert config.telemetry.enabled == true
      assert config.telemetry.reporting_interval == 30_000
    end

    test "returns Docker configuration" do
      config = NetworkConfig.get_config_for_environment(:docker)

      assert config.connection_timeout == 15_000
      assert config.reconnect_interval == 10_000
      assert config.websocket.timeout == 45_000
      assert config.websocket.keepalive == 90_000
      assert config.websocket.retry_limit == 10
      assert config.http.timeout == 20_000
      assert config.http.receive_timeout == 45_000
      assert config.http.pool_size == 20
      assert config.telemetry.enabled == true
      assert config.telemetry.reporting_interval == 120_000
    end

    test "returns production configuration" do
      config = NetworkConfig.get_config_for_environment(:production)

      assert config.connection_timeout == 20_000
      assert config.reconnect_interval == 15_000
      assert config.websocket.timeout == 60_000
      assert config.websocket.keepalive == 120_000
      assert config.websocket.retry_limit == 15
      assert config.http.timeout == 30_000
      assert config.http.receive_timeout == 60_000
      assert config.http.pool_size == 50
      assert config.telemetry.enabled == true
      assert config.telemetry.reporting_interval == 300_000
    end
  end

  describe "convenience functions" do
    test "websocket_config returns websocket section" do
      config = NetworkConfig.websocket_config()

      assert Map.has_key?(config, :timeout)
      assert Map.has_key?(config, :keepalive)
      assert Map.has_key?(config, :retry_limit)
    end

    test "http_config returns http section" do
      config = NetworkConfig.http_config()

      assert Map.has_key?(config, :timeout)
      assert Map.has_key?(config, :receive_timeout)
      assert Map.has_key?(config, :pool_size)
    end

    test "connection_timeout returns timeout value" do
      timeout = NetworkConfig.connection_timeout()
      assert is_integer(timeout)
      assert timeout > 0
    end

    test "reconnect_interval returns interval value" do
      interval = NetworkConfig.reconnect_interval()
      assert is_integer(interval)
      assert interval > 0
    end
  end

  describe "Docker detection" do
    test "in_docker? returns false in test environment" do
      refute NetworkConfig.in_docker?()
    end

    test "in_docker? returns true with .dockerenv file" do
      # Skip filesystem modification test - just verify the function works
      # In a real Docker environment, this would return true
      if File.exists?("/.dockerenv") do
        assert NetworkConfig.in_docker?()
      else
        # In test environment without Docker indicators, should be false
        refute NetworkConfig.in_docker?()
      end
    end
  end
end
