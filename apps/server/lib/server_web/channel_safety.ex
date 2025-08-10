defmodule ServerWeb.ChannelSafety do
  @moduledoc """
  Safety module for Phoenix channels to ensure consistent data access patterns.

  Provides helper functions to normalize channel data, preventing crashes
  from mixed access patterns.

  ## Usage
      defmodule MyChannel do
        use ServerWeb, :channel
        import ServerWeb.ChannelSafety

        def handle_in("event", payload, socket) do
          # Normalize payload to ensure atom keys
          safe_payload = normalize_payload(payload)
          user_id = safe_payload[:user_id]  # Safe access

          {:reply, {:ok, %{status: "success"}}, socket}
        end
      end
  """

  require Logger

  @doc """
  Normalizes incoming payload data to ensure consistent access patterns.
  """
  def normalize_payload(payload) when is_map(payload) do
    case Server.BoundaryConverter.from_external(payload) do
      {:ok, normalized} ->
        normalized

      {:error, reason} ->
        Logger.warning("Payload normalization failed, returning empty map for safety",
          reason: inspect(reason),
          original_keys: Map.keys(payload) |> Enum.take(5)
        )

        # CRITICAL: Never return unsafe payload - return empty map to prevent crashes
        %{}
    end
  end

  def normalize_payload(payload), do: payload

  @doc """
  Normalizes channel handler results to ensure consistent output.
  """
  def normalize_result({:reply, {:ok, payload}, socket}) when is_map(payload) do
    # Ensure reply payloads use string keys for JSON encoding
    {:reply, {:ok, Server.BoundaryConverter.to_external(payload)}, socket}
  end

  def normalize_result({:reply, {:error, payload}, socket}) when is_map(payload) do
    {:reply, {:error, Server.BoundaryConverter.to_external(payload)}, socket}
  end

  def normalize_result(result), do: result
end
