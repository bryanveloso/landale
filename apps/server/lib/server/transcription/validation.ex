defmodule Server.Transcription.Validation do
  @moduledoc """
  Shared validation logic for transcription data.

  This module provides consistent validation for transcription payloads
  across different transport methods (HTTP and WebSocket).
  """

  @required_fields [:timestamp, :duration, :text]
  @optional_fields [:source_id, :stream_session_id, :confidence, :metadata]
  @all_fields @required_fields ++ @optional_fields

  @doc """
  Validates transcription payload data.

  Returns {:ok, validated_attrs} or {:error, errors} where errors
  is a map of field => [error_messages].

  ## Examples

      iex> validate(%{"timestamp" => "2024-01-01T00:00:00Z", "duration" => 1.5, "text" => "Hello"})
      {:ok, %{timestamp: ~U[2024-01-01 00:00:00Z], duration: 1.5, text: "Hello"}}

      iex> validate(%{"text" => ""})
      {:error, %{timestamp: ["is required"], duration: ["is required"], text: ["can't be blank"]}}
  """
  @spec validate(map()) :: {:ok, map()} | {:error, map()}
  def validate(params) when is_map(params) do
    params
    |> normalize_params()
    |> validate_required_fields()
    |> validate_field_types()
    |> validate_field_constraints()
    |> format_result()
  end

  # Convert string keys to atoms and filter allowed fields
  defp normalize_params(params) do
    params
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      atom_key = to_atom_key(key)

      if atom_key in @all_fields do
        Map.put(acc, atom_key, value)
      else
        acc
      end
    end)
  end

  defp to_atom_key(key) when is_atom(key), do: key

  defp to_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  # Validate all required fields are present
  defp validate_required_fields(params) do
    errors =
      @required_fields
      |> Enum.reduce(%{}, fn field, acc ->
        if Map.has_key?(params, field) && params[field] not in [nil, ""] do
          acc
        else
          Map.put(acc, field, ["is required"])
        end
      end)

    {params, errors}
  end

  # Validate field types and parse where needed
  defp validate_field_types({params, errors}) do
    params_with_types =
      params
      |> Enum.reduce(%{}, fn {field, value}, acc ->
        case validate_field_type(field, value) do
          {:ok, parsed_value} ->
            Map.put(acc, field, parsed_value)

          {:error, _error_msg} ->
            acc
        end
      end)

    type_errors =
      params
      |> Enum.reduce(%{}, fn {field, value}, acc ->
        case validate_field_type(field, value) do
          {:ok, _} ->
            acc

          {:error, error_msg} ->
            existing = Map.get(acc, field, [])
            Map.put(acc, field, existing ++ [error_msg])
        end
      end)

    merged_errors = Map.merge(errors, type_errors, fn _k, v1, v2 -> v1 ++ v2 end)
    {params_with_types, merged_errors}
  end

  defp validate_field_type(:timestamp, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, "must be a valid ISO 8601 datetime"}
    end
  end

  defp validate_field_type(:timestamp, %DateTime{} = value), do: {:ok, value}
  defp validate_field_type(:timestamp, _), do: {:error, "must be a datetime string or DateTime"}

  defp validate_field_type(:duration, value) when is_number(value), do: {:ok, value / 1}

  defp validate_field_type(:duration, value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, ""} -> {:ok, float_val}
      _ -> {:error, "must be a valid number"}
    end
  end

  defp validate_field_type(:duration, _), do: {:error, "must be a number"}

  defp validate_field_type(:text, value) when is_binary(value), do: {:ok, value}
  defp validate_field_type(:text, _), do: {:error, "must be a string"}

  defp validate_field_type(:confidence, nil), do: {:ok, nil}
  defp validate_field_type(:confidence, value) when is_number(value), do: {:ok, value / 1}

  defp validate_field_type(:confidence, value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, ""} -> {:ok, float_val}
      _ -> {:error, "must be a valid number"}
    end
  end

  defp validate_field_type(:confidence, _), do: {:error, "must be a number"}

  defp validate_field_type(:metadata, value) when is_map(value), do: {:ok, value}
  defp validate_field_type(:metadata, nil), do: {:ok, %{}}
  defp validate_field_type(:metadata, _), do: {:error, "must be a map"}

  defp validate_field_type(field, value) when field in [:source_id, :stream_session_id] do
    cond do
      is_binary(value) -> {:ok, value}
      is_nil(value) -> {:ok, nil}
      true -> {:error, "must be a string"}
    end
  end

  defp validate_field_type(_, value), do: {:ok, value}

  # Validate field constraints (ranges, lengths, etc.)
  defp validate_field_constraints({params, errors}) do
    constraint_errors =
      params
      |> Enum.reduce(%{}, fn {field, value}, acc ->
        case validate_constraint(field, value) do
          :ok ->
            acc

          {:error, error_msg} ->
            existing = Map.get(acc, field, [])
            Map.put(acc, field, existing ++ [error_msg])
        end
      end)

    merged_errors = Map.merge(errors, constraint_errors, fn _k, v1, v2 -> v1 ++ v2 end)
    {params, merged_errors}
  end

  defp validate_constraint(:duration, value) when is_number(value) do
    if value > 0.0, do: :ok, else: {:error, "must be greater than 0"}
  end

  defp validate_constraint(:text, value) when is_binary(value) do
    length = String.length(value)

    if length > 10_000 do
      {:error, "is too long (maximum is 10000 characters)"}
    else
      :ok
    end
  end

  defp validate_constraint(:confidence, nil), do: :ok

  defp validate_constraint(:confidence, value) when is_number(value) do
    if value >= 0.0 and value <= 1.0,
      do: :ok,
      else: {:error, "must be between 0.0 and 1.0"}
  end

  defp validate_constraint(_, _), do: :ok

  # Format the final result
  defp format_result({params, errors}) when map_size(errors) == 0 do
    {:ok, params}
  end

  defp format_result({_params, errors}) do
    {:error, errors}
  end

  @doc """
  Formats validation errors for consistent API responses.

  ## Examples

      iex> format_errors(%{text: ["can't be blank"], duration: ["is required"]})
      [
        %{field: "text", messages: ["can't be blank"]},
        %{field: "duration", messages: ["is required"]}
      ]
  """
  @spec format_errors(map()) :: [map()]
  def format_errors(errors) when is_map(errors) do
    errors
    |> Enum.map(fn {field, messages} ->
      %{field: to_string(field), messages: messages}
    end)
    |> Enum.sort_by(& &1.field)
  end
end
