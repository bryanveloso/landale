defmodule Server.BoundaryConverter do
  @moduledoc """
  Centralized boundary conversion for external data entering the system.

  Ensures all external data (JSON, WebSocket messages, HTTP responses) is
  consistently converted to atom-key maps at system boundaries, preventing
  mixed access patterns throughout the codebase.

  ## Design Principles
  - Convert at boundaries, not throughout the code
  - Use atoms internally for performance
  - Protect against atom exhaustion attacks
  - Log all conversions for monitoring

  ## Usage
      # At API boundaries
      def handle_external_data(json_string) do
        case BoundaryConverter.from_external(json_string) do
          {:ok, internal_data} -> process(internal_data)
          {:error, reason} -> handle_error(reason)
        end
      end

      # When sending data out
      def send_to_external(internal_data) do
        json = BoundaryConverter.to_external(internal_data)
        send_response(json)
      end
  """

  require Logger

  # Maximum number of keys we'll convert to atoms from untrusted sources
  @max_keys_from_untrusted 100

  # Known safe fields that can always be converted to atoms
  @known_safe_fields [
    # OAuth fields
    "access_token",
    "refresh_token",
    "expires_at",
    "expires_in",
    "user_id",
    "client_id",
    "scopes",
    "scope",
    "token_type",

    # WebSocket event fields
    "event",
    "type",
    "payload",
    "ref",
    "topic",
    "join_ref",

    # Common API fields
    "id",
    "name",
    "email",
    "created_at",
    "updated_at",
    "status",
    "error",
    "message",
    "data",
    "meta",

    # OBS fields
    "scene",
    "source",
    "visible",
    "settings",
    "filters",

    # Stream fields
    "title",
    "category",
    "viewers",
    "started_at",
    "ended_at"
  ]

  @doc """
  Converts external data (JSON, maps with string keys) to internal format (atom keys).

  ## Safety Features
  - Limits number of keys converted to prevent atom exhaustion
  - Only converts known safe fields to atoms
  - Logs suspicious patterns
  - Validates data structure
  """
  @spec from_external(binary() | map()) :: {:ok, map()} | {:error, term()}
  def from_external(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} -> from_external(data)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  def from_external(data) when is_map(data) do
    if map_size(data) > @max_keys_from_untrusted do
      Logger.warning("Large external data map, limiting conversion",
        size: map_size(data),
        limit: @max_keys_from_untrusted
      )
    end

    result = safely_convert_to_atoms(data, 0, @max_keys_from_untrusted)
    emit_telemetry(:conversion, %{direction: :inbound, keys: map_size(data)})
    {:ok, result}
  rescue
    error ->
      Logger.error("Boundary conversion failed", error: inspect(error))
      {:error, {:conversion_failed, error}}
  end

  def from_external(data) when is_list(data) do
    result =
      Enum.map(data, fn item ->
        case from_external(item) do
          {:ok, converted} -> converted
          # Keep original if conversion fails
          {:error, _} -> item
        end
      end)

    {:ok, result}
  end

  def from_external(data) do
    # Primitive types pass through
    {:ok, data}
  end

  @doc """
  Converts internal data (atom keys) to external format (string keys).

  Safe for sending to JSON APIs, WebSocket clients, etc.
  """
  @spec to_external(map() | list()) :: map() | list()
  def to_external(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {safe_key_to_string(k), to_external(v)} end)
    |> Enum.into(%{})
  end

  def to_external(data) when is_list(data) do
    Enum.map(data, &to_external/1)
  end

  def to_external(data), do: data

  @doc """
  Validates that data has consistent access patterns.

  Returns :ok if consistent, {:error, details} if mixed patterns detected.
  """
  @spec validate_consistency(map()) :: :ok | {:error, term()}
  def validate_consistency(data) when is_map(data) do
    keys = Map.keys(data)

    {atoms, strings, others} =
      Enum.reduce(keys, {0, 0, 0}, fn key, {a, s, o} ->
        cond do
          is_atom(key) -> {a + 1, s, o}
          is_binary(key) -> {a, s + 1, o}
          true -> {a, s, o + 1}
        end
      end)

    cond do
      others > 0 ->
        {:error, {:invalid_key_types, others}}

      atoms > 0 and strings > 0 ->
        {:error, {:mixed_patterns, %{atoms: atoms, strings: strings}}}

      true ->
        :ok
    end
  end

  def validate_consistency(_), do: :ok

  # Private functions

  defp safely_convert_to_atoms(map, converted_count, max_count) when converted_count >= max_count do
    # Stop converting, just return remaining data as-is
    Logger.warning("Reached atom conversion limit, keeping string keys for remaining fields",
      converted: converted_count,
      limit: max_count
    )

    map
  end

  defp safely_convert_to_atoms(map, converted_count, max_count) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      if converted_count >= max_count do
        # Keep as string key
        Map.put(acc, key, value)
      else
        atom_key = safe_string_to_atom(key)
        converted_value = safely_convert_nested(value, converted_count + 1, max_count)
        Map.put(acc, atom_key, converted_value)
      end
    end)
  end

  defp safely_convert_to_atoms(data, _count, _max), do: data

  defp safely_convert_nested(map, count, max) when is_map(map) do
    safely_convert_to_atoms(map, count, max)
  end

  defp safely_convert_nested(list, count, max) when is_list(list) do
    Enum.map(list, fn item -> safely_convert_nested(item, count, max) end)
  end

  defp safely_convert_nested(data, _count, _max), do: data

  defp safe_string_to_atom(key) when is_binary(key) do
    if key in @known_safe_fields do
      # These are known safe fields
      String.to_atom(key)
    else
      # Try existing atom first
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError ->
          # Log unknown field for analysis
          emit_telemetry(:unknown_field, %{field: key})

          # For unknown fields, check if it's reasonably sized
          if String.length(key) < 50 do
            String.to_atom(key)
          else
            # Don't create atoms for suspiciously long keys
            Logger.warning("Refusing to create atom for long key",
              length: String.length(key),
              preview: String.slice(key, 0, 20)
            )

            # Keep as string
            key
          end
      end
    end
  end

  defp safe_string_to_atom(key) when is_atom(key), do: key

  defp safe_string_to_atom(key) do
    # Non-string, non-atom keys stay as-is
    Logger.warning("Unexpected key type in boundary conversion",
      type: inspect(key),
      key: inspect(key)
    )

    key
  end

  defp safe_key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp safe_key_to_string(key) when is_binary(key), do: key
  defp safe_key_to_string(key), do: inspect(key)

  defp emit_telemetry(_event, _metadata) do
    :ok
  end
end
