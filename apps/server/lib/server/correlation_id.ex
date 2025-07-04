defmodule Server.CorrelationId do
  @moduledoc """
  Generates and manages correlation IDs for request tracing across services.

  Provides consistent correlation ID generation and context propagation
  for better debugging and observability across the streaming overlay system.
  """

  @doc """
  Generates a new correlation ID.

  Uses a short UUID format suitable for logging and tracing without being
  too verbose for single-user system logs.

  ## Returns
  - Short correlation ID string (8 characters)

  ## Examples

      iex> CorrelationId.generate()
      "a1b2c3d4"
  """
  @spec generate() :: binary()
  def generate do
    UUID.uuid4()
    |> String.replace("-", "")
    |> String.slice(0, 8)
  end

  @doc """
  Extracts correlation ID from various sources with fallback generation.

  ## Parameters
  - `opts` - Keyword list of potential sources
    - `:assigns` - Phoenix socket/conn assigns
    - `:headers` - HTTP headers map
    - `:metadata` - Logger metadata
    - `:default` - Default value if none found

  ## Returns
  - Correlation ID string

  ## Examples

      iex> CorrelationId.from_context(assigns: %{correlation_id: "abc123"})
      "abc123"

      iex> CorrelationId.from_context(headers: %{"x-correlation-id" => "def456"})
      "def456"

      iex> CorrelationId.from_context([])
      "a1b2c3d4"  # Generated
  """
  @spec from_context(keyword()) :: binary()
  def from_context(opts \\ []) do
    opts
    |> extract_from_sources()
    |> case do
      nil -> generate()
      id -> id
    end
  end

  @doc """
  Adds correlation ID to Logger metadata for automatic inclusion in logs.

  ## Parameters
  - `correlation_id` - The correlation ID to add to metadata

  ## Examples

      CorrelationId.put_logger_metadata("abc123")
      Logger.info("Something happened")  # Will include correlation_id: "abc123"
  """
  @spec put_logger_metadata(binary()) :: :ok
  def put_logger_metadata(correlation_id) when is_binary(correlation_id) do
    Logger.metadata(correlation_id: correlation_id)
  end

  @doc """
  Gets the current correlation ID from Logger metadata.

  ## Returns
  - Current correlation ID or nil if not set
  """
  @spec get_logger_metadata() :: binary() | nil
  def get_logger_metadata do
    Logger.metadata()
    |> Keyword.get(:correlation_id)
  end

  @doc """
  Creates a correlation ID context for a function execution.

  Sets Logger metadata for the duration of the function call and
  ensures cleanup afterwards.

  ## Parameters
  - `correlation_id` - The correlation ID to use
  - `fun` - Function to execute with correlation context

  ## Examples

      CorrelationId.with_context("abc123", fn ->
        Logger.info("This will have correlation_id: abc123")
        # Some work...
      end)
  """
  @spec with_context(binary(), function()) :: any()
  def with_context(correlation_id, fun) when is_binary(correlation_id) and is_function(fun) do
    previous_metadata = Logger.metadata()

    try do
      put_logger_metadata(correlation_id)
      fun.()
    after
      Logger.reset_metadata(previous_metadata)
    end
  end

  # Private functions

  defp extract_from_sources(opts) do
    Enum.find_value(
      [
        fn -> extract_from_assigns(opts[:assigns]) end,
        fn -> extract_from_headers(opts[:headers]) end,
        fn -> extract_from_metadata(opts[:metadata]) end,
        fn -> opts[:default] end
      ],
      & &1.()
    )
  end

  defp extract_from_assigns(%{correlation_id: id}) when is_binary(id), do: id
  defp extract_from_assigns(_), do: nil

  defp extract_from_headers(%{"x-correlation-id" => id}) when is_binary(id), do: id
  defp extract_from_headers(%{"X-Correlation-ID" => id}) when is_binary(id), do: id
  defp extract_from_headers(_), do: nil

  defp extract_from_metadata(metadata) when is_list(metadata) do
    Keyword.get(metadata, :correlation_id)
  end

  defp extract_from_metadata(_), do: nil
end
