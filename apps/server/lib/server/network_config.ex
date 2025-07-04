defmodule Server.NetworkConfig do
  @moduledoc """
  Network configuration management for local and Docker environments.

  Provides environment-aware network settings including timeouts, retry intervals,
  connection pools, and other network-related configurations that differ between
  development and production/Docker environments.

  ## Features

  - Environment detection (development vs Docker/production)
  - Configurable timeouts and retry intervals
  - WebSocket connection settings
  - HTTP client configuration
  - Network monitoring and telemetry settings
  """

  require Logger

  @type env_type :: :development | :docker | :production
  @type network_config :: %{
          connection_timeout: integer(),
          reconnect_interval: integer(),
          websocket: %{
            timeout: integer(),
            keepalive: integer(),
            retry_limit: integer()
          },
          http: %{
            timeout: integer(),
            receive_timeout: integer(),
            pool_size: integer()
          },
          telemetry: %{
            enabled: boolean(),
            reporting_interval: integer()
          }
        }

  @doc """
  Gets the network configuration for the current environment.

  ## Returns
  - Network configuration map with environment-specific settings
  """
  @spec get_config() :: network_config()
  def get_config do
    env_type = detect_environment()
    get_config_for_environment(env_type)
  end

  @doc """
  Gets network configuration for a specific environment.

  ## Parameters
  - `env_type` - The environment type to get configuration for

  ## Returns
  - Network configuration map for the specified environment
  """
  @spec get_config_for_environment(env_type()) :: network_config()
  def get_config_for_environment(env_type) do
    base_config = base_config()
    env_overrides = environment_overrides(env_type)

    deep_merge(base_config, env_overrides)
  end

  @doc """
  Detects the current environment type.

  ## Returns
  - `:development` - Local development environment
  - `:docker` - Running in Docker container 
  - `:production` - Production environment
  """
  @spec detect_environment() :: env_type()
  def detect_environment do
    cond do
      in_docker?() -> :docker
      Application.get_env(:server, :env, :dev) == :prod -> :production
      true -> :development
    end
  end

  @doc """
  Checks if running in a Docker container.

  ## Returns
  - `true` if running in Docker, `false` otherwise
  """
  @spec in_docker?() :: boolean()
  def in_docker? do
    # Check multiple indicators of Docker environment
    File.exists?("/.dockerenv") or
      System.get_env("DOCKER_CONTAINER") == "true" or
      (File.exists?("/proc/1/cgroup") and docker_cgroup?())
  end

  @doc """
  Gets WebSocket-specific configuration.

  ## Returns
  - WebSocket configuration map
  """
  @spec websocket_config() :: map()
  def websocket_config do
    get_config().websocket
  end

  @doc """
  Gets HTTP client configuration.

  ## Returns  
  - HTTP client configuration map
  """
  @spec http_config() :: map()
  def http_config do
    get_config().http
  end

  @doc """
  Gets connection timeout for the current environment.

  ## Returns
  - Connection timeout in milliseconds
  """
  @spec connection_timeout() :: integer()
  def connection_timeout do
    get_config().connection_timeout
  end

  @doc """
  Gets reconnect interval for the current environment.

  ## Returns
  - Reconnect interval in milliseconds
  """
  @spec reconnect_interval() :: integer()
  def reconnect_interval do
    get_config().reconnect_interval
  end

  # Private functions

  defp base_config do
    %{
      connection_timeout: 10_000,
      reconnect_interval: 5_000,
      websocket: %{
        timeout: 30_000,
        keepalive: 60_000,
        retry_limit: 5
      },
      http: %{
        timeout: 15_000,
        receive_timeout: 30_000,
        pool_size: 10
      },
      telemetry: %{
        enabled: true,
        reporting_interval: 60_000
      }
    }
  end

  defp environment_overrides(:development) do
    %{
      # More aggressive timeouts for local environment
      connection_timeout: 3_000,
      reconnect_interval: 1_000,
      websocket: %{
        # Faster timeouts for local OBS/Twitch connections
        timeout: 8_000,
        keepalive: 15_000,
        retry_limit: 3
      },
      http: %{
        # Local API calls should be very fast
        timeout: 5_000,
        receive_timeout: 10_000,
        pool_size: 3
      },
      telemetry: %{
        # More frequent telemetry for development monitoring
        reporting_interval: 15_000
      }
    }
  end

  defp environment_overrides(:docker) do
    %{
      connection_timeout: 15_000,
      reconnect_interval: 10_000,
      websocket: %{
        timeout: 45_000,
        keepalive: 90_000,
        retry_limit: 10
      },
      http: %{
        timeout: 20_000,
        receive_timeout: 45_000,
        pool_size: 20
      },
      telemetry: %{
        reporting_interval: 120_000
      }
    }
  end

  defp environment_overrides(:production) do
    %{
      connection_timeout: 20_000,
      reconnect_interval: 15_000,
      websocket: %{
        timeout: 60_000,
        keepalive: 120_000,
        retry_limit: 15
      },
      http: %{
        timeout: 30_000,
        receive_timeout: 60_000,
        pool_size: 50
      },
      telemetry: %{
        reporting_interval: 300_000
      }
    }
  end

  defp docker_cgroup? do
    case File.read("/proc/1/cgroup") do
      {:ok, content} ->
        String.contains?(content, "docker") or String.contains?(content, "containerd")

      {:error, _} ->
        false
    end
  end

  defp deep_merge(base, overrides) when is_non_struct_map(base) and is_non_struct_map(overrides) do
    Map.merge(base, overrides, fn
      _key, base_val, override_val when is_non_struct_map(base_val) and is_non_struct_map(override_val) ->
        deep_merge(base_val, override_val)

      _key, _base_val, override_val ->
        override_val
    end)
  end

  defp deep_merge(base, overrides), do: overrides || base
end
