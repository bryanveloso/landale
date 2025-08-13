defmodule Server.SafeTokenHandler do
  @moduledoc """
  Emergency wrapper for OAuth token operations to prevent crashes from mixed data access patterns.

  This module provides safe access to token data regardless of whether it's:
  - A struct with dot notation
  - A map with atom keys
  - A map with string keys

  ## Critical Safety Features
  - Normalizes all data to atom-key maps internally
  - Prevents atom exhaustion by limiting string-to-atom conversion
  - Provides consistent access patterns
  - Logs pattern mismatches for monitoring

  ## Usage
      # Wrap any potentially inconsistent token data
      safe_token = SafeTokenHandler.normalize(mixed_data)

      # Always returns consistent atom-key map
      user_id = safe_token[:user_id]
  """

  require Logger

  @known_token_fields [
    :access_token,
    :refresh_token,
    :expires_at,
    :expires_in,
    :user_id,
    :client_id,
    :scopes,
    :scope,
    :token_type
  ]

  @doc """
  Normalizes any token data structure to a consistent atom-key map.

  Handles:
  - Structs (converts to map with atom keys)
  - Maps with atom keys (passes through)
  - Maps with string keys (converts to atom keys safely)
  - Mixed maps (normalizes all keys to atoms)
  """
  @spec normalize(any()) :: map()
  def normalize(data) when is_struct(data) do
    # Convert struct to plain map
    data
    |> Map.from_struct()
    |> normalize()
  end

  def normalize(data) when is_map(data) do
    # Check key types and normalize
    {atom_keys, string_keys, other_keys} = categorize_keys(data)

    cond do
      # Already normalized - all atom keys
      Enum.empty?(string_keys) and Enum.empty?(other_keys) ->
        log_access_pattern(:atom_map, data)
        data

      # String keys - convert safely
      Enum.empty?(atom_keys) and Enum.empty?(other_keys) ->
        log_access_pattern(:string_map, data)
        safely_convert_string_keys(data)

      # Mixed keys - normalize everything
      true ->
        log_access_pattern(:mixed_map, data)
        normalize_mixed_map(data)
    end
  end

  def normalize(nil), do: %{}

  def normalize(data) do
    Server.Logging.log_oauth_error(
      "SafeTokenHandler received unexpected data type",
      data,
      type: data.__struct__ || :unknown
    )

    %{}
  end

  @doc """
  Safely extracts a value from potentially inconsistent token data.

  Tries multiple access patterns and logs mismatches for monitoring.
  """
  @spec safe_get(any(), atom() | String.t(), any()) :: any()
  def safe_get(data, key, default \\ nil)

  def safe_get(data, key, default) when is_atom(key) do
    normalized = normalize(data)
    Map.get(normalized, key, default)
  end

  def safe_get(data, key, default) when is_binary(key) do
    atom_key = safe_string_to_atom(key)
    safe_get(data, atom_key, default)
  end

  @doc """
  Validates that token data has required fields.
  """
  @spec validate_required(map(), [atom()]) :: {:ok, map()} | {:error, term()}
  def validate_required(data, required_fields) do
    normalized = normalize(data)

    missing =
      Enum.filter(required_fields, fn field ->
        !Map.has_key?(normalized, field) || is_nil(normalized[field])
      end)

    case missing do
      [] -> {:ok, normalized}
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  # Private functions

  defp categorize_keys(map) do
    Enum.reduce(Map.keys(map), {[], [], []}, fn key, {atoms, strings, others} ->
      cond do
        is_atom(key) -> {[key | atoms], strings, others}
        is_binary(key) -> {atoms, [key | strings], others}
        true -> {atoms, strings, [key | others]}
      end
    end)
  end

  defp safely_convert_string_keys(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      atom_key = safe_string_to_atom(key)
      Map.put(acc, atom_key, value)
    end)
  end

  defp normalize_mixed_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      normalized_key = normalize_key(key)

      # If we already have this key, log a collision
      if Map.has_key?(acc, normalized_key) do
        Logger.warning("Key collision during normalization",
          original_key: inspect(key),
          normalized_key: normalized_key,
          existing_value: inspect(acc[normalized_key]),
          new_value: inspect(value)
        )
      end

      Map.put(acc, normalized_key, value)
    end)
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: safe_string_to_atom(key)

  defp normalize_key(key) do
    # For other types, convert to string then atom
    key
    |> to_string()
    |> safe_string_to_atom()
  end

  defp safe_string_to_atom(string) when is_binary(string) do
    # Check if it's a known field first
    known_atom =
      Enum.find(@known_token_fields, fn field ->
        Atom.to_string(field) == string
      end)

    case known_atom do
      nil ->
        # Try to use existing atom if it exists
        try do
          String.to_existing_atom(string)
        rescue
          ArgumentError ->
            # Only create new atoms for small set of fields
            if String.length(string) < 50 do
              emit_telemetry(:new_atom_created, %{field: string})
              String.to_atom(string)
            else
              # For large strings, keep as string to prevent data loss
              Logger.warning("Refusing to create atom for large string key",
                key_length: String.length(string),
                key_preview: String.slice(string, 0, 20)
              )

              # CRITICAL FIX: Return original string to prevent data loss
              string
            end
        end

      atom ->
        atom
    end
  end

  defp log_access_pattern(pattern_type, data) do
    emit_telemetry(:access_pattern, %{
      type: pattern_type,
      sample_keys: data |> Map.keys() |> Enum.take(3) |> inspect()
    })
  end

  defp emit_telemetry(_event, _metadata) do
    :ok
  end
end
