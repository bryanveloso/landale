defmodule Server.Services.Twitch.ApiClient do
  @moduledoc """
  Twitch API client for making outbound API calls.

  Provides functions for modifying channel information, managing stream settings,
  and other channel management operations via the Twitch API.

  ## Features

  - Modify channel information (game category, title, language)
  - OAuth token management and automatic refresh
  - Circuit breaker pattern for API resilience
  - Telemetry integration for monitoring
  - Comprehensive error handling and logging

  ## Authentication

  Uses the existing OAuthTokenManager for token management and authentication.
  Requires appropriate scopes for channel management operations.
  """

  use GenServer
  require Logger

  alias Server.Telemetry

  # Twitch API constants
  @api_base_url "https://api.twitch.tv/helix"
  @user_agent "Landale/1.0 (https://github.com/bryanveloso/landale)"

  # Required scopes for channel management
  @required_scopes ["channel:manage:broadcast", "channel:read:goals"]

  defstruct [
    :user_id,
    :circuit_breaker,
    last_api_call: nil,
    rate_limit_remaining: nil,
    rate_limit_reset: nil
  ]

  ## Client API

  @doc """
  Starts the Twitch API client GenServer.

  ## Options
  - `:user_id` - Twitch user ID for API calls (required)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Modifies channel information (game category, title, language).

  ## Parameters
  - `opts` - Keyword list of channel information to update
    - `:game_id` - Game category ID (optional)
    - `:broadcaster_language` - Language code (optional)
    - `:title` - Stream title (optional)
    - `:delay` - Stream delay in seconds (optional)
    - `:tags` - List of tag IDs (optional)
    - `:branded_content` - Boolean for branded content (optional)

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure

  ## Examples

      # Change game to Pokemon FireRed/LeafGreen
      ApiClient.modify_channel_information(game_id: "490100")

      # Change title and game
      ApiClient.modify_channel_information(
        title: "IronMON attempt #42",
        game_id: "490100"
      )
  """
  @spec modify_channel_information(keyword()) :: :ok | {:error, term()}
  def modify_channel_information(opts \\ []) do
    GenServer.call(__MODULE__, {:modify_channel_information, opts})
  end

  @doc """
  Gets current channel information.

  ## Returns
  - `{:ok, channel_info}` on success
  - `{:error, reason}` on failure
  """
  @spec get_channel_information() :: {:ok, map()} | {:error, term()}
  def get_channel_information do
    GenServer.call(__MODULE__, :get_channel_information)
  end

  @doc """
  Gets creator goals for the broadcaster.

  ## Returns
  - `{:ok, goals}` on success with list of active goals
  - `{:error, reason}` on failure

  ## Examples

      ApiClient.get_creator_goals()
      # => {:ok, %{"data" => [%{
      #      "id" => "12345",
      #      "broadcaster_id" => "141981764",
      #      "broadcaster_name" => "avalonstar",
      #      "broadcaster_login" => "avalonstar",
      #      "type" => "follower",
      #      "description" => "500 followers by end of stream!",
      #      "current_amount" => 476,
      #      "target_amount" => 500,
      #      "created_at" => "2024-01-15T10:30:00Z"
      #    }]}}
  """
  @spec get_creator_goals() :: {:ok, map()} | {:error, term()}
  def get_creator_goals do
    GenServer.call(__MODULE__, :get_creator_goals)
  end

  @doc """
  Gets available game categories by name search.

  ## Parameters
  - `query` - Search query string

  ## Returns
  - `{:ok, categories}` on success
  - `{:error, reason}` on failure
  """
  @spec search_categories(binary()) :: {:ok, list(map())} | {:error, term()}
  def search_categories(query) when is_binary(query) do
    GenServer.call(__MODULE__, {:search_categories, query})
  end

  @doc """
  Gets the current API client state and metrics.

  ## Returns
  - Map with rate limit info and last API call timestamp
  """
  @spec get_status() :: map()
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  ## GenServer Implementation

  @impl GenServer
  def init(opts) do
    user_id = Keyword.get(opts, :user_id)

    unless user_id do
      {:stop, "user_id is required"}
    end

    # Initialize circuit breaker for API resilience
    circuit_breaker = %{
      failures: 0,
      last_failure: nil,
      # :closed, :open, :half_open
      state: :closed
    }

    state = %__MODULE__{
      user_id: user_id,
      circuit_breaker: circuit_breaker
    }

    # Verify OAuth service is registered
    case Server.OAuthService.get_token_info(:twitch) do
      {:ok, _} ->
        Logger.info("Twitch API client started", user_id: user_id)
        {:ok, state}

      {:error, :service_not_registered} ->
        Logger.error("Twitch OAuth service not registered",
          service: "twitch_api"
        )

        {:stop, "Twitch OAuth service not registered"}

      {:error, :no_tokens} ->
        # No tokens yet, but service is registered - that's OK
        Logger.info("Twitch API client started (no tokens yet)", user_id: user_id)
        {:ok, state}
    end
  end

  @impl GenServer
  def handle_call({:modify_channel_information, opts}, _from, state) do
    case check_circuit_breaker(state.circuit_breaker) do
      :ok ->
        result = do_modify_channel_information(state, opts)
        new_state = update_circuit_breaker(state, result)
        {:reply, result, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_channel_information, _from, state) do
    case check_circuit_breaker(state.circuit_breaker) do
      :ok ->
        result = do_get_channel_information(state)
        new_state = update_circuit_breaker(state, result)
        {:reply, result, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_creator_goals, _from, state) do
    case check_circuit_breaker(state.circuit_breaker) do
      :ok ->
        result = do_get_creator_goals(state)
        new_state = update_circuit_breaker(state, result)
        {:reply, result, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:search_categories, query}, _from, state) do
    case check_circuit_breaker(state.circuit_breaker) do
      :ok ->
        result = do_search_categories(state, query)
        new_state = update_circuit_breaker(state, result)
        {:reply, result, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      user_id: state.user_id,
      last_api_call: state.last_api_call,
      rate_limit_remaining: state.rate_limit_remaining,
      rate_limit_reset: state.rate_limit_reset,
      circuit_breaker: %{
        state: state.circuit_breaker.state,
        failures: state.circuit_breaker.failures,
        last_failure: state.circuit_breaker.last_failure
      }
    }

    {:reply, status, state}
  end

  ## Private Implementation

  defp do_modify_channel_information(state, opts) do
    Logger.info("Modifying channel information", opts: opts)

    # Validate required scopes
    case validate_scopes() do
      :ok ->
        make_api_request(state, :patch, "/channels", %{
          "broadcaster_id" => state.user_id,
          "game_id" => Keyword.get(opts, :game_id),
          "broadcaster_language" => Keyword.get(opts, :broadcaster_language),
          "title" => Keyword.get(opts, :title),
          "delay" => Keyword.get(opts, :delay),
          "tags" => Keyword.get(opts, :tags),
          "branded_content" => Keyword.get(opts, :branded_content)
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_get_channel_information(state) do
    Logger.debug("Getting channel information", user_id: state.user_id)

    make_api_request(state, :get, "/channels", %{
      "broadcaster_id" => state.user_id
    })
  end

  defp do_get_creator_goals(state) do
    Logger.debug("Getting creator goals", user_id: state.user_id)

    make_api_request(state, :get, "/goals", %{
      "broadcaster_id" => state.user_id
    })
  end

  defp do_search_categories(state, query) do
    Logger.debug("Searching categories", query: query)

    make_api_request(state, :get, "/search/categories", %{
      "query" => query,
      "first" => "20"
    })
  end

  defp check_rate_limit(state) do
    case state.rate_limit_remaining do
      nil ->
        # No rate limit info available yet, allow request
        :ok

      remaining when remaining <= 0 ->
        # Check if reset time has passed
        case state.rate_limit_reset do
          nil ->
            # No reset time info, allow request
            :ok

          reset_time ->
            now = DateTime.utc_now()

            if DateTime.compare(now, reset_time) == :gt do
              # Reset time has passed, allow request
              :ok
            else
              # Rate limit still active
              reset_seconds = DateTime.diff(reset_time, now, :second)

              Logger.warning("Rate limit exceeded, waiting for reset",
                remaining: remaining,
                reset_in_seconds: reset_seconds
              )

              Telemetry.twitch_api_call_rate_limited(reset_seconds)
              {:error, "Rate limit exceeded. Resets in #{reset_seconds} seconds"}
            end
        end

      remaining when remaining > 0 ->
        # Rate limit available, allow request
        :ok
    end
  end

  defp make_api_request(state, method, path, params) do
    with :ok <- check_rate_limit(state),
         {:ok, token} <- Server.OAuthService.get_valid_token(:twitch),
         {:ok, response} <- send_http_request(method, path, params, token) do
      # Update last API call time
      send(self(), {:update_last_api_call, DateTime.utc_now()})

      # Parse response
      case response do
        %{status: 200, body: body} ->
          Telemetry.twitch_api_call_success(method, path)
          {:ok, body}

        %{status: 204} ->
          # No content response (successful for PATCH requests)
          Telemetry.twitch_api_call_success(method, path)
          :ok

        %{status: status, body: body} ->
          Logger.warning("Twitch API error response",
            status: status,
            body: body,
            method: method,
            path: path
          )

          Telemetry.twitch_api_call_error(method, path, status)
          {:error, "API error: #{status} - #{inspect(body)}"}
      end
    else
      {:error, reason} ->
        Logger.error("Twitch API request failed",
          error: reason,
          method: method,
          path: path
        )

        Telemetry.twitch_api_call_error(method, path, :token_error)
        {:error, reason}
    end
  end

  defp send_http_request(method, path, params, %{access_token: access_token} = _token) do
    client_id = Application.get_env(:server, :twitch_client_id)
    url = @api_base_url <> path

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Client-ID", client_id},
      {"Content-Type", "application/json"},
      {"User-Agent", @user_agent}
    ]

    case method do
      :get ->
        query_string = URI.encode_query(params |> Enum.reject(fn {_k, v} -> is_nil(v) end))
        full_url = if query_string == "", do: url, else: "#{url}?#{query_string}"

        HTTPoison.get(full_url, headers, timeout: 10_000, recv_timeout: 10_000)

      :patch ->
        body = params |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Jason.encode!()

        HTTPoison.patch(url, body, headers, timeout: 10_000, recv_timeout: 10_000)

      :post ->
        body = params |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Jason.encode!()

        HTTPoison.post(url, body, headers, timeout: 10_000, recv_timeout: 10_000)
    end
    |> case do
      {:ok, %HTTPoison.Response{status_code: status, body: body, headers: response_headers}} ->
        parsed_body =
          case Jason.decode(body) do
            {:ok, decoded} -> decoded
            {:error, _} -> body
          end

        # Extract rate limit information
        rate_limit_remaining = get_header_value(response_headers, "ratelimit-remaining")
        rate_limit_reset = get_header_value(response_headers, "ratelimit-reset")

        # Update rate limit state
        if rate_limit_remaining do
          send(self(), {:update_rate_limit, rate_limit_remaining, rate_limit_reset})
        end

        {:ok, %{status: status, body: parsed_body, headers: response_headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_scopes do
    case Server.OAuthService.get_valid_token(:twitch) do
      {:ok, token} ->
        token_scopes = MapSet.new(token.scopes || [])
        required_scopes = MapSet.new(@required_scopes)

        if MapSet.subset?(required_scopes, token_scopes) do
          :ok
        else
          missing_scopes = MapSet.difference(required_scopes, token_scopes)
          {:error, "Missing required scopes: #{MapSet.to_list(missing_scopes) |> Enum.join(", ")}"}
        end

      {:error, reason} ->
        {:error, "Token validation failed: #{reason}"}
    end
  end

  defp get_header_value(headers, key) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(k) == String.downcase(key) end)
    |> case do
      {_k, v} -> v
      nil -> nil
    end
  end

  defp check_circuit_breaker(circuit_breaker) do
    case circuit_breaker.state do
      :closed ->
        :ok

      :open ->
        # Check if we should transition to half-open
        if circuit_breaker.last_failure &&
             DateTime.diff(DateTime.utc_now(), circuit_breaker.last_failure, :second) > 60 do
          # Allow one request to test if service is back
          :ok
        else
          {:error, "Circuit breaker is open - API temporarily unavailable"}
        end

      :half_open ->
        :ok
    end
  end

  defp update_circuit_breaker(state, result) do
    new_circuit_breaker =
      case result do
        {:ok, _} ->
          # Success - reset circuit breaker
          %{state.circuit_breaker | failures: 0, last_failure: nil, state: :closed}

        :ok ->
          # Success - reset circuit breaker
          %{state.circuit_breaker | failures: 0, last_failure: nil, state: :closed}

        {:error, _reason} ->
          # Failure - increment counter
          failures = state.circuit_breaker.failures + 1
          now = DateTime.utc_now()

          new_state =
            if failures >= 3 do
              Logger.warning("Circuit breaker opened due to repeated failures", failures: failures)
              :open
            else
              state.circuit_breaker.state
            end

          %{state.circuit_breaker | failures: failures, last_failure: now, state: new_state}
      end

    %{state | circuit_breaker: new_circuit_breaker, last_api_call: DateTime.utc_now()}
  end

  ## GenServer Info Handlers

  # Token manager updates are now handled by OAuthService internally

  @impl GenServer
  def handle_info({:update_last_api_call, timestamp}, state) do
    {:noreply, %{state | last_api_call: timestamp}}
  end

  @impl GenServer
  def handle_info({:update_rate_limit, remaining, reset}, state) do
    remaining_int =
      case Integer.parse(remaining || "0") do
        {n, _} -> n
        :error -> nil
      end

    reset_timestamp =
      case Integer.parse(reset || "0") do
        {n, _} -> DateTime.from_unix!(n)
        :error -> nil
      end

    new_state = %{state | rate_limit_remaining: remaining_int, rate_limit_reset: reset_timestamp}

    {:noreply, new_state}
  end
end
