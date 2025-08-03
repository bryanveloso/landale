defmodule Server.Services.Twitch.SessionManager do
  @moduledoc """
  Manages Twitch EventSub session state and subscription lifecycle.

  This module extracts session management logic from the main Twitch service,
  handling:

  - Session state tracking (welcome, keepalive, reconnect)
  - Subscription creation timing and retries
  - User ID validation before subscription creation
  - Default subscription management

  ## Session Lifecycle

  1. Session welcome received -> Store session ID
  2. Check if user ID is available
     - If yes: Create subscriptions immediately
     - If no: Schedule retry with backoff
  3. Monitor session keepalive
  4. Handle session reconnect requests

  ## Critical Timing

  Twitch EventSub requires subscriptions to be created immediately after
  session_welcome. If user ID is not available (token validation pending),
  we retry with exponential backoff.
  """

  use GenServer
  require Logger

  alias Server.Services.Twitch.EventSubManager

  @type state :: %{
          session_id: String.t() | nil,
          user_id: String.t() | nil,
          connection_manager: pid() | nil,
          token_manager: map() | nil,
          scopes: MapSet.t() | nil,
          subscriptions: map(),
          default_subscriptions_created: boolean(),
          retry_timer: reference() | nil,
          owner: pid(),
          owner_ref: reference() | nil,
          event_sub_manager: module()
        }

  # Retry configuration for subscription creation
  @initial_retry_delay 500
  @max_retry_delay 5_000
  @retry_factor 2

  # Client API

  @doc """
  Starts the SessionManager.

  ## Options
  - `:owner` - Process to notify of session events (required)
  - `:connection_manager` - ConnectionManager pid
  - `:token_manager` - Token manager state
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Updates the user ID when token validation completes.
  """
  def set_user_id(manager \\ __MODULE__, user_id) do
    GenServer.cast(manager, {:set_user_id, user_id})
  end

  @doc """
  Updates the token manager reference.
  """
  def set_token_manager(manager \\ __MODULE__, token_manager) do
    GenServer.cast(manager, {:set_token_manager, token_manager})
  end

  @doc """
  Updates the available scopes.
  """
  def set_scopes(manager \\ __MODULE__, scopes) do
    GenServer.cast(manager, {:set_scopes, scopes})
  end

  @doc """
  Handles a new session welcome message.
  """
  def handle_session_welcome(manager \\ __MODULE__, session_id, session_data) do
    GenServer.cast(manager, {:session_welcome, session_id, session_data})
  end

  @doc """
  Handles a session reconnect request.
  """
  def handle_session_reconnect(manager \\ __MODULE__, reconnect_url) do
    GenServer.cast(manager, {:session_reconnect, reconnect_url})
  end

  @doc """
  Handles session end (disconnect/error).
  """
  def handle_session_end(manager \\ __MODULE__) do
    GenServer.cast(manager, :session_end)
  end

  @doc """
  Creates a subscription for the current session.
  """
  def create_subscription(manager \\ __MODULE__, event_type, condition, opts \\ []) do
    GenServer.call(manager, {:create_subscription, event_type, condition, opts})
  end

  @doc """
  Handles subscription revocation notification from Twitch.
  """
  def handle_subscription_revoked(manager \\ __MODULE__, subscription_id, subscription_data) do
    GenServer.cast(manager, {:subscription_revoked, subscription_id, subscription_data})
  end

  @doc """
  Gets current session state.
  """
  def get_state(manager \\ __MODULE__) do
    GenServer.call(manager, :get_state)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    owner = Keyword.fetch!(opts, :owner)
    connection_manager = Keyword.get(opts, :connection_manager)
    token_manager = Keyword.get(opts, :token_manager)
    event_sub_manager = Keyword.get(opts, :event_sub_manager, EventSubManager)

    state = %{
      session_id: nil,
      user_id: nil,
      connection_manager: connection_manager,
      token_manager: token_manager,
      scopes: nil,
      subscriptions: %{},
      default_subscriptions_created: false,
      retry_timer: nil,
      owner: owner,
      owner_ref: Process.monitor(owner),
      event_sub_manager: event_sub_manager
    }

    Logger.info("Twitch SessionManager initialized",
      owner: inspect(owner)
    )

    {:ok, state}
  end

  @impl true
  def handle_cast({:set_user_id, user_id}, state) do
    Logger.info("User ID updated in SessionManager",
      user_id: user_id,
      has_session: state.session_id != nil
    )

    state = %{state | user_id: user_id}

    # If we have an active session and haven't created subscriptions yet, do it now
    if state.session_id && !state.default_subscriptions_created && user_id do
      create_default_subscriptions(state)
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:set_token_manager, token_manager}, state) do
    {:noreply, %{state | token_manager: token_manager}}
  end

  @impl true
  def handle_cast({:set_scopes, scopes}, state) do
    {:noreply, %{state | scopes: scopes}}
  end

  @impl true
  def handle_cast({:session_welcome, session_id, session_data}, state) do
    Logger.info("Session welcome received",
      session_id: session_id,
      status: session_data["status"]
    )

    # Cancel any pending retry timer
    state = cancel_retry_timer(state)

    state = %{state | session_id: session_id, default_subscriptions_created: false, subscriptions: %{}}

    # Notify owner
    notify_owner(state, {:session_established, session_id, session_data})

    # Create subscriptions if we have user_id
    if state.user_id do
      create_default_subscriptions(state)
    else
      # Schedule retry - critical timing!
      Logger.warning("Session established but no user_id yet, scheduling retry",
        session_id: session_id
      )

      {:noreply, schedule_subscription_retry(state, @initial_retry_delay)}
    end
  end

  @impl true
  def handle_cast({:session_reconnect, reconnect_url}, state) do
    Logger.info("Session reconnect requested",
      current_session: state.session_id,
      reconnect_url: reconnect_url
    )

    # Notify owner to handle reconnection
    notify_owner(state, {:session_reconnect_requested, reconnect_url})

    {:noreply, state}
  end

  @impl true
  def handle_cast(:session_end, state) do
    Logger.info("Session ended",
      session_id: state.session_id,
      subscriptions_count: map_size(state.subscriptions)
    )

    # Cancel any pending retry
    state = cancel_retry_timer(state)

    # Clear session state
    state = %{state | session_id: nil, subscriptions: %{}, default_subscriptions_created: false}

    # Notify owner
    notify_owner(state, :session_ended)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:subscription_revoked, subscription_id, subscription_data}, state) do
    Logger.info("Subscription revoked notification received",
      subscription_id: subscription_id,
      subscription_type: subscription_data["type"],
      status: subscription_data["status"]
    )

    # Remove from tracked subscriptions
    state = %{state | subscriptions: Map.delete(state.subscriptions, subscription_id)}

    # Notify owner about the revocation
    notify_owner(state, {:subscription_revoked, subscription_id, subscription_data})

    {:noreply, state}
  end

  @impl true
  def handle_call({:create_subscription, event_type, condition, opts}, _from, state) do
    cond do
      state.session_id == nil ->
        {:reply, {:error, "No active session"}, state}

      state.user_id == nil ->
        {:reply, {:error, "User ID not available"}, state}

      state.token_manager == nil ->
        {:reply, {:error, "Token manager not configured"}, state}

      true ->
        manager_state = build_manager_state(state)

        case state.event_sub_manager.create_subscription(event_type, condition, manager_state, opts) do
          {:ok, subscription} ->
            state = track_subscription(state, subscription)
            {:reply, {:ok, subscription}, state}

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      session_id: state.session_id,
      user_id: state.user_id,
      has_session: state.session_id != nil,
      has_user_id: state.user_id != nil,
      default_subscriptions_created: state.default_subscriptions_created,
      subscription_count: map_size(state.subscriptions),
      retry_pending: state.retry_timer != nil
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info({:retry_subscription_creation, session_id, retry_delay}, state) do
    cond do
      state.session_id != session_id ->
        # Session changed, abandon retry
        Logger.info("Subscription retry abandoned - session changed",
          expected_session: session_id,
          current_session: state.session_id
        )

        {:noreply, %{state | retry_timer: nil}}

      state.user_id != nil ->
        # User ID now available, create subscriptions
        Logger.info("Subscription retry - user_id now available",
          user_id: state.user_id,
          session_id: session_id
        )

        create_default_subscriptions(%{state | retry_timer: nil})

      retry_delay >= @max_retry_delay ->
        # Max retries reached
        Logger.error("Subscription creation failed - max retries reached",
          session_id: session_id
        )

        notify_owner(state, {:subscription_creation_failed, "User ID not available"})
        {:noreply, %{state | retry_timer: nil}}

      true ->
        # Still no user_id, retry with backoff
        next_delay = min(retry_delay * @retry_factor, @max_retry_delay)

        Logger.info("Subscription retry scheduled",
          session_id: session_id,
          next_delay: next_delay
        )

        {:noreply, schedule_subscription_retry(state, next_delay)}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{owner_ref: ref} = state) do
    Logger.info("Owner process terminated",
      reason: inspect(reason)
    )

    {:stop, :normal, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("SessionManager terminating",
      reason: inspect(reason),
      session_id: state.session_id
    )

    cancel_retry_timer(state)
    :ok
  end

  # Private functions

  defp create_default_subscriptions(state) do
    Logger.info("Creating default subscriptions",
      session_id: state.session_id,
      user_id: state.user_id
    )

    if state.default_subscriptions_created do
      Logger.debug("Skipping - subscriptions already created")
      {:noreply, state}
    else
      manager_state = build_manager_state(state)

      {success_count, failed_count} = state.event_sub_manager.create_default_subscriptions(manager_state)

      Logger.info("Default subscriptions created",
        success: success_count,
        failed: failed_count
      )

      state =
        if success_count > 0 do
          %{state | default_subscriptions_created: true}
        else
          state
        end

      notify_owner(state, {:subscriptions_created, success_count, failed_count})

      {:noreply, state}
    end
  end

  defp build_manager_state(state) do
    %{
      session_id: state.session_id,
      token_manager: state.token_manager,
      oauth2_client: state.token_manager && state.token_manager.oauth2_client,
      scopes: state.scopes || MapSet.new(),
      user_id: state.user_id
    }
  end

  defp track_subscription(state, subscription) do
    subscription_id = subscription["id"]
    %{state | subscriptions: Map.put(state.subscriptions, subscription_id, subscription)}
  end

  defp schedule_subscription_retry(state, delay) do
    state = cancel_retry_timer(state)

    timer =
      Process.send_after(
        self(),
        {:retry_subscription_creation, state.session_id, delay},
        delay
      )

    %{state | retry_timer: timer}
  end

  defp cancel_retry_timer(%{retry_timer: nil} = state), do: state

  defp cancel_retry_timer(state) do
    Process.cancel_timer(state.retry_timer)
    %{state | retry_timer: nil}
  end

  defp notify_owner(state, message) do
    send(state.owner, {:twitch_session, message})
  end
end
