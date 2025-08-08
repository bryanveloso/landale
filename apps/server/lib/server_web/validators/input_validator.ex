defmodule ServerWeb.Validators.InputValidator do
  @moduledoc """
  Input validation helpers for controllers.

  Provides common validation patterns to prevent injection attacks
  and ensure data integrity.
  """

  import Ecto.Changeset

  @doc """
  Validates and sanitizes common parameters.
  """
  def validate_params(params, types) do
    {%{}, types}
    |> cast(params, Map.keys(types))
    |> validate_required_fields()
    |> validate_string_length()
    |> sanitize_inputs()
    |> apply_action(:validate)
  end

  @doc """
  Validates scene name for OBS operations.
  """
  def validate_scene_name(name) when is_binary(name) do
    if String.match?(name, ~r/^[a-zA-Z0-9_\-\s]{1,100}$/) do
      {:ok, name}
    else
      {:error, "Invalid scene name format"}
    end
  end

  def validate_scene_name(_), do: {:error, "Scene name must be a string"}

  @doc """
  Validates subscription ID format.
  """
  def validate_subscription_id(id) when is_binary(id) do
    if String.match?(id, ~r/^[a-zA-Z0-9\-_]{1,100}$/) do
      {:ok, id}
    else
      {:error, "Invalid subscription ID format"}
    end
  end

  def validate_subscription_id(_), do: {:error, "Subscription ID must be a string"}

  @doc """
  Validates numeric ID.
  """
  def validate_numeric_id(id) when is_integer(id) and id > 0 do
    {:ok, id}
  end

  def validate_numeric_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} when num > 0 -> {:ok, num}
      _ -> {:error, "Invalid ID format"}
    end
  end

  def validate_numeric_id(_), do: {:error, "ID must be a positive integer"}

  @doc """
  Validates search query parameters.
  """
  def validate_search_query(query) when is_binary(query) do
    sanitized =
      query
      |> String.trim()
      # Limit length
      |> String.slice(0, 200)
      |> escape_sql_wildcards()

    if String.length(sanitized) > 0 do
      {:ok, sanitized}
    else
      {:error, "Search query cannot be empty"}
    end
  end

  def validate_search_query(_), do: {:error, "Search query must be a string"}

  @doc """
  Validates time range parameters.
  """
  def validate_time_range(start_time, end_time) do
    with {:ok, start_dt} <- parse_datetime(start_time),
         {:ok, end_dt} <- parse_datetime(end_time),
         :ok <- validate_time_order(start_dt, end_dt) do
      {:ok, {start_dt, end_dt}}
    end
  end

  # Private functions

  defp validate_required_fields(changeset) do
    # Add validation based on the changeset's required fields
    changeset
  end

  defp validate_string_length(changeset) do
    changeset
    |> validate_length(:name, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_length(:query, max: 200)
  end

  defp sanitize_inputs(changeset) do
    # Sanitize string inputs to prevent XSS
    Enum.reduce(changeset.changes, changeset, fn
      {key, value}, acc when is_binary(value) ->
        put_change(acc, key, sanitize_string(value))

      _, acc ->
        acc
    end)
  end

  defp sanitize_string(str) do
    str
    |> String.replace(~r/<script.*?>.*?<\/script>/i, "")
    |> String.replace(~r/<.*?>/i, "")
    |> String.trim()
  end

  defp escape_sql_wildcards(str) do
    str
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> {:ok, dt}
      {:error, _} -> {:error, "Invalid datetime format"}
    end
  end

  defp parse_datetime(_), do: {:error, "Datetime must be a string"}

  defp validate_time_order(start_dt, end_dt) do
    if DateTime.compare(start_dt, end_dt) == :lt do
      :ok
    else
      {:error, "Start time must be before end time"}
    end
  end
end
