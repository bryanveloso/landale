defmodule Server.Schemas.EventSubSchema do
  @moduledoc """
  Schema definitions for Twitch EventSub event validation.

  Ensures consistent access patterns for event data across all event types,
  preventing crashes from mixed string/atom key access.
  """

  @doc """
  Validates and normalizes EventSub event data.

  Converts all string keys to atoms for consistent access patterns.
  """
  @spec validate(any()) :: {:ok, map()} | {:error, term()}
  def validate(event_data) when is_map(event_data) do
    # Use BoundaryConverter to normalize to atom keys
    case Server.BoundaryConverter.from_external(event_data) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(data) do
    {:error, {:invalid_type, "Expected map, got #{inspect(data)}"}}
  end

  @doc """
  Safely extracts a field from event data with consistent access.
  """
  @spec get_field(map(), String.t() | atom()) :: any()
  def get_field(event_data, field) when is_binary(field) do
    Map.get(event_data, String.to_existing_atom(field))
  rescue
    ArgumentError -> Map.get(event_data, field)
  end

  def get_field(event_data, field) when is_atom(field) do
    Map.get(event_data, field)
  end
end
