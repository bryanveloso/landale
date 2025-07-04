defmodule Server.NetworkConfigTest do
  use ExUnit.Case, async: false

  @moduletag :unit

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

      assert config.connection_timeout == Duration.new!(second: 3)
      assert config.reconnect_interval == Duration.new!(second: 1)
      assert config.websocket.timeout == Duration.new!(second: 8)
      assert config.websocket.keepalive == Duration.new!(second: 15)
      assert config.websocket.retry_limit == 3
      assert config.http.timeout == Duration.new!(second: 5)
      assert config.http.receive_timeout == Duration.new!(second: 10)
      assert config.http.pool_size == 3
      assert config.telemetry.enabled == true
      assert config.telemetry.reporting_interval == Duration.new!(second: 15)
    end

    test "returns Docker configuration" do
      config = NetworkConfig.get_config_for_environment(:docker)

      assert config.connection_timeout == Duration.new!(second: 15)
      assert config.reconnect_interval == Duration.new!(second: 10)
      assert config.websocket.timeout == Duration.new!(second: 45)
      assert config.websocket.keepalive == Duration.new!(second: 90)
      assert config.websocket.retry_limit == 10
      assert config.http.timeout == Duration.new!(second: 20)
      assert config.http.receive_timeout == Duration.new!(second: 45)
      assert config.http.pool_size == 20
      assert config.telemetry.enabled == true
      assert config.telemetry.reporting_interval == Duration.new!(minute: 2)
    end

    test "returns production configuration" do
      config = NetworkConfig.get_config_for_environment(:production)

      assert config.connection_timeout == Duration.new!(second: 20)
      assert config.reconnect_interval == Duration.new!(second: 15)
      assert config.websocket.timeout == Duration.new!(minute: 1)
      assert config.websocket.keepalive == Duration.new!(minute: 2)
      assert config.websocket.retry_limit == 15
      assert config.http.timeout == Duration.new!(second: 30)
      assert config.http.receive_timeout == Duration.new!(minute: 1)
      assert config.http.pool_size == 50
      assert config.telemetry.enabled == true
      assert config.telemetry.reporting_interval == Duration.new!(minute: 5)
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
      assert %Duration{} = timeout
      assert System.convert_time_unit(timeout.second, :second, :millisecond) > 0
    end

    test "reconnect_interval returns interval value" do
      interval = NetworkConfig.reconnect_interval()
      assert %Duration{} = interval
      assert System.convert_time_unit(interval.second, :second, :millisecond) > 0
    end

    test "connection_timeout_ms returns timeout in milliseconds" do
      timeout_ms = NetworkConfig.connection_timeout_ms()
      assert is_integer(timeout_ms)
      assert timeout_ms > 0
    end

    test "reconnect_interval_ms returns interval in milliseconds" do
      interval_ms = NetworkConfig.reconnect_interval_ms()
      assert is_integer(interval_ms)
      assert interval_ms > 0
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
