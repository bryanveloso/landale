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
          connection_timeout: Duration.t(),
          reconnect_interval: Duration.t(),
          websocket: %{
            timeout: Duration.t(),
            keepalive: Duration.t(),
            retry_limit: integer()
          },
          http: %{
            timeout: Duration.t(),
            receive_timeout: Duration.t(),
            pool_size: integer()
          },
          telemetry: %{
            enabled: boolean(),
            reporting_interval: Duration.t()
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
  - Connection timeout as Duration struct
  """
  @spec connection_timeout() :: Duration.t()
  def connection_timeout do
    get_config().connection_timeout
  end

  @doc """
  Gets reconnect interval for the current environment.

  ## Returns
  - Reconnect interval as Duration struct
  """
  @spec reconnect_interval() :: Duration.t()
  def reconnect_interval do
    get_config().reconnect_interval
  end

  @doc """
  Gets connection timeout in milliseconds for Process functions.

  ## Returns
  - Connection timeout in milliseconds as integer
  """
  @spec connection_timeout_ms() :: integer()
  def connection_timeout_ms do
    connection_timeout() |> duration_to_millisecond()
  end

  @doc """
  Gets reconnect interval in milliseconds for Process functions.

  ## Returns
  - Reconnect interval in milliseconds as integer
  """
  @spec reconnect_interval_ms() :: integer()
  def reconnect_interval_ms do
    reconnect_interval() |> duration_to_millisecond()
  end

  @doc """
  Gets websocket timeout in milliseconds for :gun functions.

  ## Returns
  - WebSocket timeout in milliseconds as integer
  """
  @spec websocket_timeout_ms() :: integer()
  def websocket_timeout_ms do
    websocket_config().timeout |> duration_to_millisecond()
  end

  @doc """
  Gets HTTP timeout in milliseconds for :gun functions.

  ## Returns
  - HTTP timeout in milliseconds as integer
  """
  @spec http_timeout_ms() :: integer()
  def http_timeout_ms do
    http_config().timeout |> duration_to_millisecond()
  end

  @doc """
  Gets HTTP receive timeout in milliseconds for :gun functions.

  ## Returns
  - HTTP receive timeout in milliseconds as integer
  """
  @spec http_receive_timeout_ms() :: integer()
  def http_receive_timeout_ms do
    http_config().receive_timeout |> duration_to_millisecond()
  end

  # Helper function to convert Duration to milliseconds
  defp duration_to_millisecond(%Duration{} = duration) do
    System.convert_time_unit(duration.second, :second, :millisecond)
  end

  # Private functions

  defp base_config do
    %{
      connection_timeout: Duration.new!(second: 10),
      reconnect_interval: Duration.new!(second: 5),
      websocket: %{
        timeout: Duration.new!(second: 30),
        keepalive: Duration.new!(minute: 1),
        retry_limit: 5
      },
      http: %{
        timeout: Duration.new!(second: 15),
        receive_timeout: Duration.new!(second: 30),
        pool_size: 10
      },
      telemetry: %{
        enabled: true,
        reporting_interval: Duration.new!(minute: 1)
      }
    }
  end

  defp environment_overrides(:development) do
    %{
      # More aggressive timeouts for local environment
      connection_timeout: Duration.new!(second: 3),
      reconnect_interval: Duration.new!(second: 1),
      websocket: %{
        # Faster timeouts for local OBS/Twitch connections
        timeout: Duration.new!(second: 8),
        keepalive: Duration.new!(second: 15),
        retry_limit: 3
      },
      http: %{
        # Local API calls should be very fast
        timeout: Duration.new!(second: 5),
        receive_timeout: Duration.new!(second: 10),
        pool_size: 3
      },
      telemetry: %{
        # More frequent telemetry for development monitoring
        reporting_interval: Duration.new!(second: 15)
      }
    }
  end

  defp environment_overrides(:docker) do
    %{
      connection_timeout: Duration.new!(second: 15),
      reconnect_interval: Duration.new!(second: 10),
      websocket: %{
        timeout: Duration.new!(second: 45),
        keepalive: Duration.new!(second: 90),
        retry_limit: 10
      },
      http: %{
        timeout: Duration.new!(second: 20),
        receive_timeout: Duration.new!(second: 45),
        pool_size: 20
      },
      telemetry: %{
        reporting_interval: Duration.new!(minute: 2)
      }
    }
  end

  defp environment_overrides(:production) do
    %{
      connection_timeout: Duration.new!(second: 20),
      reconnect_interval: Duration.new!(second: 15),
      websocket: %{
        timeout: Duration.new!(minute: 1),
        keepalive: Duration.new!(minute: 2),
        retry_limit: 15
      },
      http: %{
        timeout: Duration.new!(second: 30),
        receive_timeout: Duration.new!(minute: 1),
        pool_size: 50
      },
      telemetry: %{
        reporting_interval: Duration.new!(minute: 5)
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
