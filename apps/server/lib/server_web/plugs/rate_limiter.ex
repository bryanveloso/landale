defmodule ServerWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plug for API endpoints.

  Implements per-IP rate limiting with configurable limits.
  Personal scale: 100 requests per minute per IP.

  ## ETS Table Access Configuration

  **IMPORTANT**: This module uses `:public` access for its ETS table, which is an
  EXCEPTION to the general security guideline of using `:protected` tables.

  ### Why :public is Required Here

  The rate limiter ETS table MUST be `:public` because:
  1. Multiple concurrent processes need to perform atomic counter operations
  2. The Plug runs in different processes for each request
  3. `:ets.update_counter/3` requires the calling process to own the table or have write access

  ### Why This is Safe

  This security exception is acceptable because:
  - The table only stores temporary rate limit counters (IP -> count mappings)
  - No sensitive data is stored (no tokens, passwords, or user data)
  - All data expires automatically after 60 seconds
  - The system runs on a private Tailscale network

  ### Other :public Tables in the System

  For future reference, these tables also use `:public` access:
  - `correlation_id_pool` - Atomic ID generation across processes
  - `rate_limiter_buckets` - This module's rate limiting counters

  All other ETS tables should remain `:protected` unless they have similar
  requirements for atomic operations from multiple processes.
  """

  import Plug.Conn
  require Logger

  @default_limit 100
  @table_name :rate_limiter_buckets

  def init(opts) do
    # Ensure ETS table exists (created by application startup)
    ensure_table_exists()

    %{
      max_requests: Keyword.get(opts, :max_requests, @default_limit),
      window_ms: Keyword.get(opts, :interval_seconds, 60) * 1000,
      by: Keyword.get(opts, :by, [:ip_address])
    }
  end

  @doc false
  def ensure_table_exists do
    if :ets.whereis(@table_name) == :undefined do
      # EXCEPTION: Using :public access for atomic counter operations
      # Similar to correlation_id_pool, rate limiting requires atomic updates
      # from multiple concurrent processes. The table only stores temporary
      # rate limit counters (no sensitive data) that expire after 60 seconds.
      :ets.new(@table_name, [:set, :public, :named_table, {:read_concurrency, true}, {:write_concurrency, true}])
    end
  end

  def call(conn, %{max_requests: limit, window_ms: window, by: by_fields}) do
    key = build_key(conn, by_fields)
    now = System.system_time(:millisecond)

    case check_rate_limit(key, now, limit, window) do
      :ok ->
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", to_string(remaining_requests(key, now, limit, window)))
        |> put_resp_header("x-ratelimit-reset", to_string(reset_time(key, window)))

      {:error, retry_after} ->
        Logger.warning("Rate limit exceeded",
          key: key,
          path: conn.request_path,
          retry_after: retry_after
        )

        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_resp_header("x-ratelimit-limit", to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> Phoenix.Controller.put_view(json: ServerWeb.ErrorJSON)
        |> Phoenix.Controller.render(:"429")
        |> halt()
    end
  end

  defp build_key(conn, fields) do
    parts =
      Enum.map(fields, fn
        :ip_address ->
          conn.remote_ip |> :inet.ntoa() |> to_string()

        :user_id when is_map_key(conn.assigns, :current_user) ->
          conn.assigns.current_user[:id] || "anonymous"

        _ ->
          "unknown"
      end)

    Enum.join(parts, ":")
  end

  defp check_rate_limit(key, now, limit, window) do
    # Clean old entries periodically
    if :rand.uniform(100) == 1, do: cleanup_old_entries(now, window)

    case :ets.lookup(@table_name, key) do
      [] ->
        # First request from this key
        :ets.insert(@table_name, {key, now, 1})
        :ok

      [{^key, first_request_time, count}] ->
        if now - first_request_time > window do
          # Window has expired, reset counter
          :ets.insert(@table_name, {key, now, 1})
          :ok
        else
          if count >= limit do
            # Rate limit exceeded
            retry_after = div(window - (now - first_request_time), 1000)
            {:error, max(retry_after, 1)}
          else
            # Increment counter
            :ets.update_counter(@table_name, key, {3, 1})
            :ok
          end
        end
    end
  end

  defp remaining_requests(key, now, limit, window) do
    case :ets.lookup(@table_name, key) do
      [] ->
        limit

      [{^key, first_request_time, count}] ->
        if now - first_request_time > window do
          limit
        else
          max(limit - count, 0)
        end
    end
  end

  defp reset_time(key, window) do
    case :ets.lookup(@table_name, key) do
      [] ->
        System.system_time(:second) + div(window, 1000)

      [{^key, first_request_time, _count}] ->
        div(first_request_time + window, 1000)
    end
  end

  defp cleanup_old_entries(now, window) do
    cutoff = now - window * 2
    :ets.select_delete(@table_name, [{{:_, :"$1", :_}, [{:<, :"$1", cutoff}], [true]}])
  end
end
