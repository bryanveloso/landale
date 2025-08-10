defmodule Server.Schemas.TokenSchema do
  @moduledoc """
  Schema definition for OAuth token data validation.

  Ensures consistent structure for token data across the application,
  preventing crashes from mixed access patterns.

  ## Valid Token Structure
      %{
        access_token: "token_string",
        refresh_token: "refresh_string" | nil,
        expires_at: ~U[2024-01-01 00:00:00Z] | nil,
        expires_in: 3600 | nil,
        user_id: "123456" | nil,
        client_id: "client_abc",
        scopes: MapSet.new(["read", "write"]) | ["read", "write"] | nil,
        token_type: "Bearer" | nil
      }
  """

  @required_fields [:access_token]
  @optional_fields [:refresh_token, :expires_at, :expires_in, :user_id, :client_id, :scopes, :scope, :token_type]
  @all_fields @required_fields ++ @optional_fields

  @doc """
  Validates token data structure.

  Normalizes the data to consistent atom keys and validates types.
  Handles both string and atom keys gracefully.

  ## Returns
  - `{:ok, normalized_token}` - Valid token with atom keys
  - `{:error, reason}` - Validation failure with details
  """
  @spec validate(any()) :: {:ok, map()} | {:error, term()}
  def validate(data) when is_map(data) do
    # First normalize to atom keys using SafeTokenHandler
    normalized = Server.SafeTokenHandler.normalize(data)

    # Check required fields
    case validate_required_fields(normalized) do
      :ok ->
        # Validate field types
        case validate_field_types(normalized) do
          :ok ->
            # Clean up and standardize the token
            cleaned = clean_token_data(normalized)
            {:ok, cleaned}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def validate(data) do
    {:error, {:invalid_type, "Expected map, got #{inspect(data)}"}}
  end

  # Private validation functions

  defp validate_required_fields(data) do
    missing_fields =
      @required_fields
      |> Enum.reject(&Map.has_key?(data, &1))

    case missing_fields do
      [] ->
        :ok

      fields ->
        {:error, {:missing_required_fields, fields}}
    end
  end

  defp validate_field_types(data) do
    errors =
      data
      |> Enum.reduce([], fn {key, value}, acc ->
        if key in @all_fields do
          case validate_field_type(key, value) do
            :ok -> acc
            {:error, reason} -> [{key, reason} | acc]
          end
        else
          # Unknown fields are allowed but not validated
          acc
        end
      end)

    case errors do
      [] ->
        :ok

      errors ->
        {:error, {:field_type_errors, Enum.reverse(errors)}}
    end
  end

  defp validate_field_type(:access_token, value) when is_binary(value), do: :ok
  defp validate_field_type(:access_token, value), do: {:error, "Expected string, got #{inspect(value)}"}

  defp validate_field_type(:refresh_token, nil), do: :ok
  defp validate_field_type(:refresh_token, value) when is_binary(value), do: :ok
  defp validate_field_type(:refresh_token, value), do: {:error, "Expected string or nil, got #{inspect(value)}"}

  defp validate_field_type(:expires_at, nil), do: :ok
  defp validate_field_type(:expires_at, %DateTime{} = _value), do: :ok
  # Unix timestamp
  defp validate_field_type(:expires_at, value) when is_integer(value), do: :ok
  defp validate_field_type(:expires_at, value), do: {:error, "Expected DateTime or integer, got #{inspect(value)}"}

  defp validate_field_type(:expires_in, nil), do: :ok
  defp validate_field_type(:expires_in, value) when is_integer(value) and value > 0, do: :ok
  defp validate_field_type(:expires_in, value), do: {:error, "Expected positive integer, got #{inspect(value)}"}

  defp validate_field_type(:user_id, nil), do: :ok
  defp validate_field_type(:user_id, value) when is_binary(value), do: :ok
  # Some APIs return numeric IDs
  defp validate_field_type(:user_id, value) when is_integer(value), do: :ok
  defp validate_field_type(:user_id, value), do: {:error, "Expected string or integer, got #{inspect(value)}"}

  defp validate_field_type(:client_id, nil), do: :ok
  defp validate_field_type(:client_id, value) when is_binary(value), do: :ok
  defp validate_field_type(:client_id, value), do: {:error, "Expected string, got #{inspect(value)}"}

  defp validate_field_type(:scopes, nil), do: :ok
  defp validate_field_type(:scopes, %MapSet{} = _value), do: :ok

  defp validate_field_type(:scopes, value) when is_list(value) do
    if Enum.all?(value, &is_binary/1), do: :ok, else: {:error, "Scope list contains non-strings"}
  end

  defp validate_field_type(:scopes, value), do: {:error, "Expected MapSet or list, got #{inspect(value)}"}

  defp validate_field_type(:scope, nil), do: :ok
  defp validate_field_type(:scope, value) when is_binary(value), do: :ok
  defp validate_field_type(:scope, value), do: {:error, "Expected string, got #{inspect(value)}"}

  defp validate_field_type(:token_type, nil), do: :ok
  defp validate_field_type(:token_type, value) when is_binary(value), do: :ok
  defp validate_field_type(:token_type, value), do: {:error, "Expected string, got #{inspect(value)}"}

  # Unknown fields pass through
  defp validate_field_type(_key, _value), do: :ok

  defp clean_token_data(data) do
    data
    |> normalize_scopes()
    |> normalize_expires_at()
    # Preserve unknown fields
    |> Map.take(@all_fields ++ Map.keys(data))
  end

  defp normalize_scopes(data) do
    cond do
      # If we have scopes as a list, convert to MapSet
      Map.has_key?(data, :scopes) and is_list(data.scopes) ->
        Map.put(data, :scopes, MapSet.new(data.scopes))

      # If we have scope as a string, parse and convert to scopes MapSet
      Map.has_key?(data, :scope) and is_binary(data.scope) and not Map.has_key?(data, :scopes) ->
        scopes = data.scope |> String.split(" ") |> MapSet.new()

        data
        |> Map.put(:scopes, scopes)
        |> Map.delete(:scope)

      true ->
        data
    end
  end

  defp normalize_expires_at(data) do
    cond do
      # If we have expires_at as an integer (Unix timestamp), convert to DateTime
      Map.has_key?(data, :expires_at) and is_integer(data.expires_at) ->
        Map.put(data, :expires_at, DateTime.from_unix!(data.expires_at))

      # If we only have expires_in, calculate expires_at
      Map.has_key?(data, :expires_in) and is_integer(data.expires_in) and not Map.has_key?(data, :expires_at) ->
        expires_at = DateTime.add(DateTime.utc_now(), data.expires_in, :second)
        Map.put(data, :expires_at, expires_at)

      true ->
        data
    end
  end

  @doc """
  Creates a sample valid token for testing.
  """
  @spec sample() :: map()
  def sample do
    %{
      access_token: "sample_access_token_abc123",
      refresh_token: "sample_refresh_token_xyz789",
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      user_id: "123456",
      client_id: "client_abc",
      scopes: MapSet.new(["read", "write"]),
      token_type: "Bearer"
    }
  end
end
