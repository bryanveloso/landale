defmodule Server.DataAccessGuard do
  @moduledoc """
  Runtime guards for safe data access with migration support.

  Provides validation against defined schemas with two modes:
  - `:strict` - Prevents access to invalid data (returns errors)
  - `:warn` - Logs issues but allows access (for gradual migration)

  ## Configuration

  ### Global Configuration
      config :server, Server.DataAccessGuard,
        default_mode: :warn,
        module_overrides: %{
          Server.Services.OAuth: :strict,
          Server.Legacy.Handler: :warn
        }

  ### Module-Level Configuration
      defmodule MyModule do
        @data_access_guard :strict  # Or :warn

        def process_data(data) do
          case DataAccessGuard.validate(data, MySchema) do
            {:ok, validated} -> # Safe to use
            {:error, reason} -> # Handle invalid data
          end
        end
      end

  ## Integration with PatternMonitor

  Emits telemetry events:
  - `[:server, :data_access_guard, :warn]` - Issues in warn mode
  - `[:server, :data_access_guard, :error]` - Issues in strict mode
  - `[:server, :data_access_guard, :validation]` - All validation attempts

  ## Migration Strategy

  1. Start with global `:warn` mode
  2. Monitor PatternMonitor for problematic locations
  3. Fix issues module by module
  4. Switch modules to `:strict` as they're cleaned
  5. Eventually switch global default to `:strict`
  """

  require Logger

  @type mode :: :strict | :warn
  @type validation_result :: {:ok, any()} | {:error, {:unsafe_data, any()}}

  # Default configuration
  @default_config [
    default_mode: :warn,
    module_overrides: %{},
    # Set to true to track all validations
    track_safe_accesses: false
  ]

  @doc """
  Validates data against the given schema module.

  The validation mode is determined by:
  1. Module attribute `@data_access_guard` (highest priority)
  2. Module-specific override in config
  3. Global default mode in config

  ## Returns
  - `{:ok, validated_data}` - Data is valid
  - `{:error, {:unsafe_data, reason}}` - Data invalid (strict mode)
  - `{:ok, original_data}` - Data invalid but allowed (warn mode)

  ## Examples
      case DataAccessGuard.validate(token_data, TokenSchema) do
        {:ok, validated} ->
          # Safe to access validated.access_token
        {:error, {:unsafe_data, reason}} ->
          # Handle validation failure
      end
  """
  @spec validate(any(), module()) :: validation_result()
  defmacro validate(data, schema_module) do
    quote do
      Server.DataAccessGuard.do_validate(
        unquote(data),
        unquote(schema_module),
        __ENV__
      )
    end
  end

  @doc """
  Safe field extraction with validation.

  Validates the entire data structure first, then extracts the field.
  Useful for gradual migration of specific field accesses.

  ## Examples
      # Instead of: data[:user_id] or data["user_id"]
      {:ok, user_id} = DataAccessGuard.get_field(data, :user_id, UserSchema)
  """
  @spec get_field(any(), atom() | String.t(), module()) :: {:ok, any()} | {:error, term()}
  defmacro get_field(data, field_name, schema_module) do
    quote do
      Server.DataAccessGuard.do_get_field(
        unquote(data),
        unquote(field_name),
        unquote(schema_module),
        __ENV__
      )
    end
  end

  @doc """
  Validates data with explicit mode override.

  Useful for testing or special cases where you need to override
  the configured mode.
  """
  @spec validate_with_mode(any(), module(), mode()) :: validation_result()
  def validate_with_mode(data, schema_module, mode) when mode in [:strict, :warn] do
    do_validate_internal(data, schema_module, mode, %{
      module: :manual,
      function: {:validate_with_mode, 3},
      file: "manual",
      line: 0
    })
  end

  # Public implementation functions (called by macros)

  @doc false
  def do_validate(data, schema_module, caller_env) do
    mode = get_effective_mode(caller_env)
    do_validate_internal(data, schema_module, mode, caller_env)
  end

  @doc false
  def do_get_field(data, field_name, schema_module, caller_env) do
    case do_validate(data, schema_module, caller_env) do
      {:ok, validated_data} ->
        # Convert field name to atom if string
        atom_field = if is_binary(field_name), do: String.to_atom(field_name), else: field_name
        {:ok, Map.get(validated_data, atom_field)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Internal implementation

  defp do_validate_internal(data, schema_module, mode, caller_env) do
    start_time = System.monotonic_time(:microsecond)

    # Attempt validation
    validation_result =
      try do
        # Ensure module is loaded before checking exports
        Code.ensure_loaded(schema_module)

        if function_exported?(schema_module, :validate, 1) do
          schema_module.validate(data)
        else
          {:error, {:schema_error, "#{inspect(schema_module)} does not export validate/1"}}
        end
      rescue
        error ->
          {:error, {:validation_crashed, error}}
      end

    duration = System.monotonic_time(:microsecond) - start_time

    # Process result based on mode
    case validation_result do
      {:ok, validated_data} ->
        emit_validation_telemetry(:success, schema_module, duration, mode, caller_env)
        {:ok, validated_data}

      {:error, reason} ->
        log_validation_issue(data, schema_module, reason, mode, caller_env)
        emit_validation_telemetry(:failure, schema_module, duration, mode, caller_env, reason)

        case mode do
          :warn ->
            # In warn mode, allow original data to pass
            {:ok, data}

          :strict ->
            # In strict mode, prevent access
            {:error, {:unsafe_data, reason}}
        end
    end
  end

  defp get_effective_mode(caller_env) do
    # Priority 1: Module attribute
    module_attribute =
      try do
        Module.get_attribute(caller_env.module, :data_access_guard)
      rescue
        _ -> nil
      end

    if module_attribute in [:strict, :warn] do
      module_attribute
    else
      # Priority 2: Module-specific override in config
      config = get_config()
      module_overrides = config[:module_overrides] || %{}

      case Map.get(module_overrides, caller_env.module) do
        mode when mode in [:strict, :warn] ->
          mode

        _ ->
          # Priority 3: Global default
          config[:default_mode] || :warn
      end
    end
  end

  defp log_validation_issue(data, schema_module, reason, mode, caller_env) do
    location = format_location(caller_env)
    data_preview = truncate_data(data)

    log_level = if mode == :warn, do: :warning, else: :error

    Logger.log(log_level, """
    DataAccessGuard: Unsafe data detected
    Location: #{location}
    Schema: #{inspect(schema_module)}
    Mode: #{mode}
    Reason: #{inspect(reason)}
    Data preview: #{data_preview}
    Action: #{if mode == :warn, do: "Allowing access (warn mode)", else: "Blocking access (strict mode)"}
    """)

    # Track in PatternMonitor for aggregation
    emit_location_telemetry(caller_env, schema_module, mode)
  end

  defp emit_validation_telemetry(result, schema_module, duration, mode, caller_env, reason \\ nil) do
    metadata = %{
      result: result,
      schema: schema_module,
      mode: mode,
      duration_us: duration,
      module: caller_env.module,
      function: caller_env.function,
      line: caller_env.line,
      file: caller_env.file
    }

    metadata = if reason, do: Map.put(metadata, :reason, inspect(reason)), else: metadata

    # Mode-specific event for failures
    if result == :failure do
      event_name =
        if mode == :warn,
          do: [:server, :data_access_guard, :warn],
          else: [:server, :data_access_guard, :error]
    end
  end

  defp emit_location_telemetry(_caller_env, _schema_module, _mode) do
    :ok
  end

  defp format_location(caller_env) do
    "#{caller_env.module}.#{elem(caller_env.function, 0)}/#{elem(caller_env.function, 1)} (#{caller_env.file}:#{caller_env.line})"
  end

  defp truncate_data(data) do
    # Safely truncate data for logging
    data_string = inspect(data, limit: 200, printable_limit: 200)

    if String.length(data_string) > 200 do
      String.slice(data_string, 0, 200) <> "..."
    else
      data_string
    end
  end

  defp get_config do
    Application.get_env(:server, __MODULE__, @default_config)
  end

  @doc """
  Updates the runtime configuration for DataAccessGuard.

  Useful for testing or dynamic reconfiguration.
  """
  @spec set_config(keyword()) :: :ok
  def set_config(config) do
    Application.put_env(:server, __MODULE__, Keyword.merge(@default_config, config))
  end

  @doc """
  Gets current statistics about data validation.

  Returns a summary of validation attempts, failures, and locations.
  This data is primarily collected by PatternMonitor.
  """
  @spec get_stats() :: map()
  def get_stats do
    # Delegate to PatternMonitor for aggregated stats
    if Process.whereis(Server.PatternMonitor) do
      Server.PatternMonitor.get_report()
      |> Map.get(:data_access_guard, %{})
    else
      %{error: "PatternMonitor not running"}
    end
  end
end
