defmodule ServerWeb.Helpers.SystemHelpers do
  @moduledoc """
  Shared utility functions for system status and formatting.
  """

  @doc """
  Formats uptime seconds into a human-readable string.
  """
  @spec format_uptime(float() | integer()) :: String.t()
  def format_uptime(seconds) when is_float(seconds) do
    format_uptime(round(seconds))
  end

  def format_uptime(seconds) when is_integer(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3_600)
    minutes = div(rem(seconds, 3_600), 60)
    secs = rem(seconds, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m #{secs}s"
      minutes > 0 -> "#{minutes}m #{secs}s"
      true -> "#{secs}s"
    end
  end

  @doc """
  Formats bytes into a human-readable string.
  """
  @spec format_bytes(integer() | nil) :: String.t()
  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  def format_bytes(_), do: "0 B"

  @doc """
  Gets basic system status information.
  """
  @spec get_system_status() :: map()
  def get_system_status do
    # Calculate uptime since app start (fallback to 0 if start time not set)
    start_time = Application.get_env(:server, :start_time, System.system_time(:second))
    uptime_seconds = System.system_time(:second) - start_time
    memory = :erlang.memory()

    %{
      uptime: %{
        seconds: round(uptime_seconds),
        formatted: format_uptime(uptime_seconds)
      },
      memory: %{
        total: format_bytes(memory[:total]),
        processes: format_bytes(memory[:processes]),
        system: format_bytes(memory[:system])
      }
    }
  end
end
