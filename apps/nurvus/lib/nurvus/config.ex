defmodule Nurvus.Config do
  @moduledoc """
  Configuration management for Nurvus process definitions.

  Handles loading, validating, and managing process configurations
  from various sources (JSON files, environment variables, etc.).
  """

  require Logger

  @type process_config :: %{
          id: String.t(),
          name: String.t(),
          command: String.t(),
          args: [String.t()],
          cwd: String.t() | nil,
          env: %{String.t() => String.t()},
          auto_restart: boolean(),
          max_restarts: non_neg_integer(),
          restart_window: non_neg_integer(),
          platform: String.t() | nil,
          process_detection: map() | nil,
          health_check: map() | nil,
          stop_command: String.t() | nil,
          stop_args: [String.t()] | nil
        }

  ## Public API

  @doc """
  Loads process configurations from the specified file or default location.
  """
  @spec load_config(String.t() | nil) :: {:ok, [process_config()]} | {:error, term()}
  def load_config(config_file \\ nil) do
    file_path = config_file || get_config_file_path()

    case File.exists?(file_path) do
      true ->
        load_from_file(file_path)

      false ->
        # Try to initialize config from local processes.json on first run
        case initialize_config_from_local(file_path) do
          :ok ->
            load_from_file(file_path)

          :no_local_config ->
            Logger.info("No configuration file found at #{file_path}, starting with empty config")
            {:ok, []}

          {:error, reason} ->
            Logger.warning("Failed to copy local config: #{reason}, starting with empty config")
            {:ok, []}
        end
    end
  end

  @doc """
  Saves process configurations to the specified file.
  """
  @spec save_config([process_config()], String.t() | nil) :: :ok | {:error, term()}
  def save_config(processes, config_file \\ nil) do
    file_path = config_file || get_config_file_path()

    # Ensure directory exists
    case ensure_config_directory(file_path) do
      :ok ->
        try do
          json_data = JSON.encode!(processes)
          File.write!(file_path, json_data)
          Logger.info("Saved configuration to #{file_path}")
          :ok
        rescue
          error ->
            Logger.error("Failed to save configuration: #{inspect(error)}")
            {:error, error}
        end

      error ->
        error
    end
  end

  @doc """
  Validates a process configuration map.
  """
  @spec validate_process_config(map()) :: {:ok, process_config()} | {:error, term()}
  def validate_process_config(config) when is_non_struct_map(config) do
    with {:ok, required_fields} <- validate_required_fields(config),
         {:ok, optional_fields} <- validate_optional_fields(config) do
      validated_config = Map.merge(required_fields, optional_fields)
      {:ok, validated_config}
    else
      error -> error
    end
  end

  def validate_process_config(_), do: {:error, :invalid_config_format}

  @doc """
  Creates a sample configuration file for reference.
  """
  @spec create_sample_config(String.t() | nil) :: :ok | {:error, term()}
  def create_sample_config(config_file \\ nil) do
    file_path = config_file || Path.rootname(get_default_config_path()) <> ".sample.json"

    sample_processes = [
      %{
        "id" => "my_app",
        "name" => "My Application",
        "command" => "bun",
        "args" => ["run", "start"],
        "cwd" => "/path/to/my/app",
        "env" => %{
          "NODE_ENV" => "production",
          "PORT" => "3000"
        },
        "auto_restart" => true,
        "max_restarts" => 3,
        "restart_window" => 60
      },
      %{
        "id" => "worker",
        "name" => "Background Worker",
        "command" => "python",
        "args" => ["worker.py"],
        "cwd" => "/path/to/worker",
        "env" => %{},
        "auto_restart" => true,
        "max_restarts" => 5,
        "restart_window" => 120
      }
    ]

    save_config(sample_processes, file_path)
  end

  @doc """
  Gets the default configuration file path.
  """
  @spec get_config_file_path() :: String.t()
  def get_config_file_path do
    cond do
      path = Application.get_env(:nurvus, :config_file) -> path
      path = System.get_env("NURVUS_CONFIG_FILE") -> path
      true -> get_default_config_path()
    end
  end

  @doc """
  Gets the default configuration file path in ~/.nurvus directory.
  """
  @spec get_default_config_path() :: String.t()
  def get_default_config_path do
    home = System.get_env("HOME") || System.get_env("USERPROFILE") || "."
    Path.join([home, ".nurvus", "processes.json"])
  end

  ## Private Functions

  @spec initialize_config_from_local(String.t()) :: :ok | :no_local_config | {:error, term()}
  defp initialize_config_from_local(target_path) do
    local_config = "./processes.json"

    case File.exists?(local_config) do
      true ->
        try do
          # Ensure target directory exists
          case ensure_config_directory(target_path) do
            :ok ->
              File.cp!(local_config, target_path)
              Logger.info("Copied local config from #{local_config} to #{target_path}")
              :ok

            error ->
              error
          end
        rescue
          error ->
            {:error, "Failed to copy config: #{inspect(error)}"}
        end

      false ->
        :no_local_config
    end
  end

  defp validate_required_fields(config) do
    with {:ok, id} <- validate_required_string(config, "id"),
         {:ok, name} <- validate_required_string(config, "name"),
         {:ok, command} <- validate_required_string(config, "command"),
         {:ok, args} <- validate_args(config) do
      {:ok, %{id: id, name: name, command: command, args: args}}
    else
      error -> error
    end
  end

  defp validate_optional_fields(config) do
    with {:ok, basic_fields} <- validate_basic_fields(config),
         {:ok, advanced_fields} <- validate_advanced_fields(config) do
      {:ok, Map.merge(basic_fields, advanced_fields)}
    else
      error -> error
    end
  end

  defp validate_basic_fields(config) do
    with {:ok, cwd} <- validate_optional_string(config, "cwd"),
         {:ok, env} <- validate_env(config),
         {:ok, auto_restart} <- validate_boolean(config, "auto_restart", false),
         {:ok, max_restarts} <- validate_integer(config, "max_restarts", 3),
         {:ok, restart_window} <- validate_integer(config, "restart_window", 60) do
      {:ok,
       %{
         cwd: cwd,
         env: env,
         auto_restart: auto_restart,
         max_restarts: max_restarts,
         restart_window: restart_window
       }}
    else
      error -> error
    end
  end

  defp validate_advanced_fields(config) do
    with {:ok, platform} <- validate_platform_field(config),
         {:ok, process_detection} <- validate_process_detection_field(config),
         {:ok, health_check} <- validate_health_check_field(config),
         {:ok, stop_command} <- validate_optional_string(config, "stop_command"),
         {:ok, stop_args} <- validate_optional_args(config, "stop_args") do
      {:ok,
       %{
         platform: platform,
         process_detection: process_detection,
         health_check: health_check,
         stop_command: stop_command,
         stop_args: stop_args
       }}
    else
      error -> error
    end
  end

  defp load_from_file(file_path) do
    file_path
    |> File.read!()
    |> JSON.decode!()
    |> validate_process_list()
  rescue
    error in File.Error ->
      Logger.error("Failed to read config file #{file_path}: #{inspect(error)}")
      {:error, :file_read_error}

    error ->
      Logger.error("Invalid JSON or config format in #{file_path}: #{inspect(error)}")
      {:error, :invalid_format}
  end

  defp validate_process_list(json_data) when is_list(json_data) do
    results = Enum.map(json_data, &validate_process_config/1)

    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil ->
        processes = Enum.map(results, fn {:ok, process} -> process end)
        {:ok, processes}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_process_list(_), do: {:error, :config_must_be_array}

  defp validate_required_string(config, key) do
    case Map.get(config, key) do
      value when is_binary(value) and value != "" ->
        {:ok, String.trim(value)}

      _ ->
        {:error, "#{key} is required and must be a non-empty string"}
    end
  end

  defp validate_optional_string(config, key) do
    case Map.get(config, key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, String.trim(value)}
      _ -> {:error, "#{key} must be a string"}
    end
  end

  defp validate_args(config) do
    case Map.get(config, "args", []) do
      args when is_list(args) ->
        if Enum.all?(args, &is_binary/1) do
          {:ok, args}
        else
          {:error, "args must be a list of strings"}
        end

      _ ->
        {:error, "args must be a list"}
    end
  end

  defp validate_env(config) do
    case Map.get(config, "env", %{}) do
      env when is_non_struct_map(env) ->
        # Ensure all keys and values are strings
        string_env =
          env
          |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
          |> Enum.into(%{})

        {:ok, string_env}

      _ ->
        {:error, "env must be a map"}
    end
  end

  defp validate_boolean(config, key, default) do
    case Map.get(config, key, default) do
      value when is_boolean(value) -> {:ok, value}
      _ -> {:error, "#{key} must be a boolean"}
    end
  end

  defp validate_integer(config, key, default) do
    case Map.get(config, key, default) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> {:error, "#{key} must be a non-negative integer"}
    end
  end

  defp validate_optional_args(config, key) do
    case Map.get(config, key) do
      nil ->
        {:ok, []}

      args when is_list(args) ->
        if Enum.all?(args, &is_binary/1) do
          {:ok, args}
        else
          {:error, "#{key} must be a list of strings"}
        end

      _ ->
        {:error, "#{key} must be a list"}
    end
  end

  defp validate_platform_field(config) do
    case Map.get(config, "platform") do
      nil -> {:ok, nil}
      platform when platform in ["win32", "darwin", "linux"] -> {:ok, platform}
      _ -> {:error, "platform must be one of: win32, darwin, linux"}
    end
  end

  defp validate_process_detection_field(config) do
    case Map.get(config, "process_detection") do
      nil ->
        {:ok, nil}

      detection when is_non_struct_map(detection) ->
        with {:ok, _} <- validate_required_string(detection, "name"),
             {:ok, _} <- validate_optional_string(detection, "check_command"),
             {:ok, _} <- validate_optional_list(detection, "check_args"),
             {:ok, _} <- validate_optional_string(detection, "type") do
          {:ok, detection}
        else
          error -> error
        end

      _ ->
        {:error, "process_detection must be a map"}
    end
  end

  defp validate_health_check_field(config) do
    case Map.get(config, "health_check") do
      nil ->
        {:ok, nil}

      health_check when is_non_struct_map(health_check) ->
        with {:ok, _} <- validate_optional_string(health_check, "type"),
             {:ok, _} <- validate_optional_string(health_check, "url"),
             {:ok, _} <- validate_optional_integer(health_check, "interval"),
             {:ok, _} <- validate_optional_integer(health_check, "timeout") do
          {:ok, health_check}
        else
          error -> error
        end

      _ ->
        {:error, "health_check must be a map"}
    end
  end

  defp validate_optional_list(config, key) do
    case Map.get(config, key) do
      nil -> {:ok, nil}
      list when is_list(list) -> {:ok, list}
      _ -> {:error, "#{key} must be a list"}
    end
  end

  defp validate_optional_integer(config, key) do
    case Map.get(config, key) do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> {:error, "#{key} must be a positive integer"}
    end
  end

  defp ensure_config_directory(file_path) do
    dir = Path.dirname(file_path)

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to create config directory: #{reason}"}
    end
  end
end
