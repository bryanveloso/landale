defmodule ServerWeb.Plugs.ApiAuth do
  @moduledoc """
  API authentication plug for securing process management and control endpoints.

  Validates API key from X-API-Key header or api_key query parameter.
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case authenticate(conn) do
      {:ok, :authenticated} ->
        conn

      {:error, reason} ->
        Logger.warning("API authentication failed", reason: reason, remote_ip: get_peer_data(conn).address)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized", message: "Valid API key required"}))
        |> halt()
    end
  end

  defp authenticate(conn) do
    api_key = get_api_key(conn)
    expected_key = System.get_env("API_KEY")

    cond do
      is_nil(expected_key) or expected_key == "" ->
        {:error, :no_api_key_configured}

      is_nil(api_key) or api_key == "" ->
        {:error, :no_api_key_provided}

      api_key == expected_key ->
        {:ok, :authenticated}

      true ->
        {:error, :invalid_api_key}
    end
  end

  defp get_api_key(conn) do
    # Try X-API-Key header first, then api_key query parameter
    case get_req_header(conn, "x-api-key") do
      [key] when is_binary(key) and key != "" ->
        key

      _ ->
        case conn.query_params["api_key"] do
          key when is_binary(key) and key != "" -> key
          _ -> nil
        end
    end
  end
end
