defmodule ServerWeb.ResponseBuilder do
  @moduledoc """
  Standardized response builder for consistent API responses across channels and controllers.

  Provides a unified interface for building success and error responses with consistent
  structure, validation, and metadata tracking.

  ## Standards

  ### Success Responses
  - Always include `success: true`
  - Include `data` field for payload
  - Include `meta` field for optional metadata (timestamps, pagination, etc.)

  ### Error Responses  
  - Always include `success: false`
  - Always include `error` field with structured error information
  - Include `code` for programmatic error handling
  - Include `message` for human-readable description
  - Include `details` for additional context when helpful

  ## Usage

  ### Channel Responses
      # Success responses
      {:reply, ResponseBuilder.success(%{user_id: 123}), socket}
      {:reply, ResponseBuilder.success(%{items: []}, %{count: 0}), socket}

      # Error responses  
      {:reply, ResponseBuilder.error("invalid_payload", "Missing required field"), socket}
      {:reply, ResponseBuilder.error("service_unavailable", "External service down"), socket}

  ### Controller Responses
      conn |> ResponseBuilder.send_success(%{user_id: 123})
      conn |> ResponseBuilder.send_error("not_found", "Resource not found", 404)
  """

  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  @type success_response :: {:ok, map()}
  @type error_response :: {:error, map()}
  @type response :: success_response() | error_response()

  @type error_code :: binary() | atom()
  @type error_message :: binary()
  @type error_details :: map() | nil

  ## Channel Response Builders

  @doc """
  Builds a standardized success response for Phoenix channels.

  ## Examples
      ResponseBuilder.success(%{user_id: 123})
      # => {:ok, %{success: true, data: %{user_id: 123}, meta: %{timestamp: ...}}}

      ResponseBuilder.success(%{items: []}, %{count: 0, page: 1})
      # => {:ok, %{success: true, data: %{items: []}, meta: %{count: 0, page: 1, timestamp: ...}}}
  """
  @spec success(map(), map()) :: success_response()
  def success(data, meta \\ %{}) do
    response = %{
      success: true,
      data: data,
      meta:
        Map.merge(meta, %{
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          server_version: Application.spec(:server, :vsn) |> to_string()
        })
    }

    {:ok, response}
  end

  @doc """
  Builds a standardized error response for Phoenix channels.

  ## Examples
      ResponseBuilder.error("invalid_payload", "Missing required field 'type'")
      # => {:error, %{success: false, error: %{code: "invalid_payload", message: "...", timestamp: ...}}}

      ResponseBuilder.error("service_unavailable", "Twitch API unavailable", %{retry_after: 30})
      # => {:error, %{success: false, error: %{code: "...", message: "...", details: %{retry_after: 30}, ...}}}
  """
  @spec error(error_code(), error_message(), error_details()) :: error_response()
  def error(code, message, details \\ nil) do
    error_data = %{
      code: normalize_error_code(code),
      message: message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    error_data =
      case details do
        nil -> error_data
        details when is_map(details) -> Map.put(error_data, :details, details)
        _ -> Map.put(error_data, :details, %{raw: details})
      end

    response = %{
      success: false,
      error: error_data
    }

    {:error, response}
  end

  @doc """
  Builds a validation error response with field-specific errors.

  ## Examples
      ResponseBuilder.validation_error(%{email: "is required", age: "must be positive"})
      # => {:error, %{success: false, error: %{code: "validation_failed", fields: %{...}, ...}}}
  """
  @spec validation_error(map()) :: error_response()
  def validation_error(field_errors) do
    error("validation_failed", "Request validation failed", %{
      fields: field_errors
    })
  end

  @doc """
  Builds a service error response from a ServiceError struct.
  """
  @spec service_error(Server.ServiceError.t()) :: error_response()
  def service_error(%Server.ServiceError{} = service_error) do
    error(
      service_error.reason,
      service_error.message,
      Map.take(service_error, [:service, :operation, :details])
    )
  end

  ## Controller Response Helpers

  @doc """
  Sends a standardized success response via Phoenix controller.

  ## Examples
      conn |> ResponseBuilder.send_success(%{user_id: 123})
      conn |> ResponseBuilder.send_success(%{items: []}, %{count: 0}, 201)
  """
  @spec send_success(Plug.Conn.t(), map(), map(), integer()) :: Plug.Conn.t()
  def send_success(conn, data, meta \\ %{}, status_code \\ 200) do
    {:ok, response} = success(data, meta)

    conn
    |> put_status(status_code)
    |> json(response)
  end

  @doc """
  Sends a standardized error response via Phoenix controller.

  ## Examples
      conn |> ResponseBuilder.send_error("not_found", "User not found", 404)
      conn |> ResponseBuilder.send_error("invalid_payload", "Missing field", %{field: "email"}, 422)
  """
  @spec send_error(Plug.Conn.t(), error_code(), error_message(), error_details() | integer(), integer()) ::
          Plug.Conn.t()
  def send_error(conn, code, message, details_or_status \\ 400, status_code \\ nil)

  def send_error(conn, code, message, status_code, nil) when is_integer(status_code) do
    send_error(conn, code, message, nil, status_code)
  end

  def send_error(conn, code, message, details, status_code) do
    {:error, response} = error(code, message, details)
    final_status = status_code || determine_http_status(code)

    conn
    |> put_status(final_status)
    |> json(response)
  end

  @doc """
  Sends a validation error response via Phoenix controller.
  """
  @spec send_validation_error(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def send_validation_error(conn, field_errors) do
    {:error, response} = validation_error(field_errors)

    conn
    |> put_status(422)
    |> json(response)
  end

  ## Utility Functions

  @doc """
  Determines if a response is a success response.
  """
  @spec success?(map()) :: boolean()
  def success?(%{success: true}), do: true
  def success?(_), do: false

  @doc """
  Determines if a response is an error response.
  """
  @spec error?(map()) :: boolean()
  def error?(%{success: false}), do: true
  def error?(_), do: false

  @doc """
  Extracts error information from a response.
  """
  @spec get_error(map()) :: map() | nil
  def get_error(%{success: false, error: error}), do: error
  def get_error(_), do: nil

  @doc """
  Extracts data from a success response.
  """
  @spec get_data(map()) :: map() | nil
  def get_data(%{success: true, data: data}), do: data
  def get_data(_), do: nil

  ## Private Functions

  defp normalize_error_code(code) when is_atom(code), do: Atom.to_string(code)
  defp normalize_error_code(code) when is_binary(code), do: code
  defp normalize_error_code(code), do: inspect(code)

  defp determine_http_status("not_found"), do: 404
  defp determine_http_status("unauthorized"), do: 401
  defp determine_http_status("forbidden"), do: 403
  defp determine_http_status("invalid_payload"), do: 422
  defp determine_http_status("validation_failed"), do: 422
  defp determine_http_status("service_unavailable"), do: 503
  defp determine_http_status("timeout"), do: 504
  defp determine_http_status("rate_limited"), do: 429
  defp determine_http_status(_), do: 500
end
