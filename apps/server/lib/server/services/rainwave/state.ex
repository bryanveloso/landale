defmodule Server.Services.Rainwave.State do
  @moduledoc """
  Defines the internal state for the Rainwave service.

  Tracks API configuration, current playing song, health metrics,
  and user listening status.
  """

  defstruct [
    # Configuration
    :api_key,
    :user_id,
    :api_base_url,
    :poll_interval,

    # Station info
    :station_id,
    :station_name,

    # Current state
    :current_song,
    :is_enabled,
    :is_listening,

    # Health tracking
    # :ok | :degraded | :down
    :api_health_status,
    :last_api_call_at,
    :last_successful_at,
    :api_error_count,
    :consecutive_errors,

    # Internal
    :poll_timer
  ]

  @type health_status :: :ok | :degraded | :down

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          user_id: String.t() | nil,
          api_base_url: String.t(),
          poll_interval: pos_integer(),
          station_id: integer(),
          station_name: String.t(),
          current_song: map() | nil,
          is_enabled: boolean(),
          is_listening: boolean(),
          api_health_status: health_status(),
          last_api_call_at: DateTime.t() | nil,
          last_successful_at: DateTime.t() | nil,
          api_error_count: non_neg_integer(),
          consecutive_errors: non_neg_integer(),
          poll_timer: reference() | nil
        }

  @doc """
  Creates a new state with default values.
  """
  def new(opts \\ []) do
    %__MODULE__{
      api_key: Keyword.get(opts, :api_key),
      user_id: Keyword.get(opts, :user_id),
      api_base_url: Keyword.get(opts, :api_base_url, "https://rainwave.cc/api4"),
      poll_interval: Keyword.get(opts, :poll_interval, 10_000),
      # Default to Covers
      station_id: Keyword.get(opts, :station_id, 3),
      station_name: "Covers",
      current_song: nil,
      is_enabled: false,
      is_listening: false,
      api_health_status: :ok,
      last_api_call_at: nil,
      last_successful_at: nil,
      api_error_count: 0,
      consecutive_errors: 0,
      poll_timer: nil
    }
  end

  @doc """
  Records a successful API call.
  """
  def record_success(state) do
    now = DateTime.utc_now()

    %{state | api_health_status: :ok, last_api_call_at: now, last_successful_at: now, consecutive_errors: 0}
  end

  @doc """
  Records a failed API call and updates health status.
  """
  def record_failure(state) do
    now = DateTime.utc_now()
    new_consecutive_errors = state.consecutive_errors + 1
    new_error_count = state.api_error_count + 1

    health_status =
      cond do
        new_consecutive_errors >= 5 -> :down
        new_consecutive_errors >= 2 -> :degraded
        true -> :ok
      end

    %{
      state
      | api_health_status: health_status,
        last_api_call_at: now,
        api_error_count: new_error_count,
        consecutive_errors: new_consecutive_errors
    }
  end

  @doc """
  Checks if the service has valid credentials.
  """
  def has_credentials?(%__MODULE__{api_key: key, user_id: id}) do
    not is_nil(key) and not is_nil(id)
  end

  @doc """
  Calculates error rate for monitoring.
  """
  def error_rate(%__MODULE__{api_error_count: 0}), do: 0.0

  def error_rate(%__MODULE__{api_error_count: errors, last_api_call_at: nil})
      when errors > 0,
      do: 100.0

  def error_rate(%__MODULE__{api_error_count: errors, last_successful_at: last_success}) do
    # Simple ratio for now - could be enhanced with time windows
    case last_success do
      nil ->
        100.0

      _ ->
        # When there's at least one successful call, we know the minimum total attempts
        # If we had 1 success followed by 5 errors, total = 6, error rate = 5/6 = 83.33%
        total = errors + 1
        Float.round(errors / total * 100, 2)
    end
  end
end
