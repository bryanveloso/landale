defmodule Server.ServiceError do
  @moduledoc """
  Standardized error handling and context for all services.

  Provides consistent error types and context information across
  all services to improve debugging and error handling consistency.
  """

  @type error_reason ::
          :service_unavailable
          | :network_error
          | :auth_error
          | :rate_limit
          | :invalid_request
          | :configuration_error
          | :timeout_error

  @type service_error :: %__MODULE__{
          reason: error_reason(),
          message: binary(),
          service: atom(),
          operation: binary(),
          details: map(),
          timestamp: DateTime.t(),
          correlation_id: binary() | nil
        }

  @enforce_keys [:reason, :message, :service, :operation]
  defstruct [
    :reason,
    :message,
    :service,
    :operation,
    details: %{},
    timestamp: nil,
    correlation_id: nil
  ]

  @doc """
  Creates a new service error with standardized context.

  ## Parameters
  - `service` - The service that generated the error (e.g., `:obs`, `:twitch`)
  - `operation` - The operation that failed (e.g., "connect", "start_streaming")
  - `reason` - The error reason (see error_reason type)
  - `message` - Human-readable error message
  - `opts` - Additional options
    - `:details` - Map of additional error context
    - `:correlation_id` - Request correlation ID

  ## Examples

      iex> ServiceError.new(:obs, "connect", :network_error, "Connection refused")
      %ServiceError{
        service: :obs,
        operation: "connect", 
        reason: :network_error,
        message: "Connection refused",
        timestamp: ~U[2024-01-01 00:00:00Z]
      }
  """
  @spec new(atom(), binary(), error_reason(), binary(), keyword()) :: service_error()
  def new(service, operation, reason, message, opts \\ []) do
    correlation_id =
      Keyword.get(opts, :correlation_id) ||
        Server.CorrelationId.get_logger_metadata()

    %__MODULE__{
      service: service,
      operation: operation,
      reason: reason,
      message: message,
      details: Keyword.get(opts, :details, %{}),
      timestamp: DateTime.utc_now(),
      correlation_id: correlation_id
    }
  end

  @doc """
  Creates a service error from an exception.

  ## Parameters
  - `service` - The service that generated the error
  - `operation` - The operation that failed  
  - `exception` - The exception that was raised
  - `opts` - Additional options (see new/5)
  """
  @spec from_exception(atom(), binary(), Exception.t(), keyword()) :: service_error()
  def from_exception(service, operation, exception, opts \\ []) do
    reason = classify_exception(exception)
    message = Exception.message(exception)

    details =
      opts
      |> Keyword.get(:details, %{})
      |> Map.merge(%{
        exception_type: exception.__struct__
      })

    new(service, operation, reason, message, Keyword.put(opts, :details, details))
  end

  @doc """
  Creates a service error from a standard Elixir error tuple.

  ## Parameters
  - `service` - The service that generated the error
  - `operation` - The operation that failed
  - `error_tuple` - Standard `{:error, reason}` tuple
  - `opts` - Additional options (see new/5)
  """
  @spec from_error_tuple(atom(), binary(), {:error, term()}, keyword()) :: service_error()
  def from_error_tuple(service, operation, {:error, reason}, opts \\ []) do
    {error_reason, message} = classify_error_reason(reason)

    details =
      opts
      |> Keyword.get(:details, %{})
      |> Map.put(:original_reason, reason)

    new(service, operation, error_reason, message, Keyword.put(opts, :details, details))
  end

  @doc """
  Converts service error to a standard `{:error, reason}` tuple for API consistency.
  """
  @spec to_error_tuple(service_error()) :: {:error, binary()}
  def to_error_tuple(%__MODULE__{} = error) do
    {:error, "#{error.service} #{error.operation} failed: #{error.message}"}
  end

  @doc """
  Checks if an error indicates a temporary failure that should be retried.
  """
  @spec retryable?(service_error()) :: boolean()
  def retryable?(%__MODULE__{reason: reason}) do
    reason in [:network_error, :timeout_error, :rate_limit, :service_unavailable]
  end

  # Private functions

  defp classify_exception(%CaseClauseError{}), do: :invalid_request
  defp classify_exception(%MatchError{}), do: :invalid_request
  defp classify_exception(%ArgumentError{}), do: :invalid_request
  defp classify_exception(%FunctionClauseError{}), do: :invalid_request
  defp classify_exception(%KeyError{}), do: :invalid_request
  defp classify_exception(%File.Error{}), do: :configuration_error

  defp classify_exception(exception) do
    case exception.__struct__ do
      DBConnection.ConnectionError -> :service_unavailable
      _ -> :service_unavailable
    end
  end

  defp classify_error_reason(:timeout), do: {:timeout_error, "Operation timed out"}
  defp classify_error_reason(:econnrefused), do: {:network_error, "Connection refused"}
  defp classify_error_reason(:nxdomain), do: {:network_error, "Host not found"}
  defp classify_error_reason(:ehostunreach), do: {:network_error, "Host unreachable"}
  defp classify_error_reason(:enotconn), do: {:network_error, "Not connected"}
  defp classify_error_reason(:closed), do: {:network_error, "Connection closed"}
  defp classify_error_reason({:http_error, 401, _}), do: {:auth_error, "Unauthorized"}
  defp classify_error_reason({:http_error, 403, _}), do: {:auth_error, "Forbidden"}
  defp classify_error_reason({:http_error, 429, _}), do: {:rate_limit, "Rate limit exceeded"}
  defp classify_error_reason({:http_error, status, _}) when status >= 500, do: {:service_unavailable, "Server error"}
  defp classify_error_reason({:http_error, status, _}), do: {:invalid_request, "Client error (#{status})"}
  defp classify_error_reason(reason) when is_binary(reason), do: {:service_unavailable, reason}
  defp classify_error_reason(reason), do: {:service_unavailable, inspect(reason)}
end
