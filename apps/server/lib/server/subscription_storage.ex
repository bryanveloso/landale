defmodule Server.SubscriptionStorage do
  @moduledoc """
  Dedicated GenServer for owning and managing the ETS table for subscription data.

  This module follows Elixir best practices by separating storage concerns from business logic.
  The ETS table is owned by this GenServer and survives business logic crashes.

  ## Features

  - Owns ETS table with proper supervision
  - Protected table for controlled reads (security)
  - Synchronous writes through GenServer (consistency)
  - Testable with dependency injection
  """

  use GenServer
  require Logger

  @type subscription_data :: %{
          id: binary(),
          event_type: binary(),
          status: atom(),
          created_at: DateTime.t(),
          last_updated: DateTime.t(),
          last_event_at: DateTime.t() | nil,
          failure_count: integer(),
          metadata: map()
        }

  ## Client API

  @doc """
  Starts the storage GenServer with the given options.

  ## Options

  - `:name` - Required. Name for both the GenServer and ETS table
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, name, opts)
  end

  @doc """
  Looks up subscription data directly from ETS (fast read).

  Returns `{:ok, subscription}` if found, `:error` otherwise.
  """
  @spec lookup(atom() | pid(), binary()) :: {:ok, subscription_data()} | :error
  def lookup(table_name, subscription_id) do
    case :ets.lookup(table_name, subscription_id) do
      [{^subscription_id, subscription}] -> {:ok, subscription}
      [] -> :error
    end
  end

  @doc """
  Inserts or updates subscription data (synchronous write).
  """
  @spec put(GenServer.server(), binary(), subscription_data()) :: :ok
  def put(server, subscription_id, subscription_data) do
    GenServer.call(server, {:put, subscription_id, subscription_data})
  end

  @doc """
  Deletes subscription data (synchronous write).
  """
  @spec delete(GenServer.server(), binary()) :: :ok
  def delete(server, subscription_id) do
    GenServer.call(server, {:delete, subscription_id})
  end

  @doc """
  Lists all subscriptions (direct ETS read).
  """
  @spec list_all(atom() | pid()) :: [subscription_data()]
  def list_all(table_name) do
    table_name
    |> :ets.tab2list()
    |> Enum.map(fn {_id, subscription} -> subscription end)
  end

  @doc """
  Clears all subscription data (synchronous operation).
  """
  @spec clear_all(GenServer.server()) :: :ok
  def clear_all(server) do
    GenServer.call(server, :clear_all)
  end

  ## GenServer Implementation

  @impl true
  def init(table_name) do
    # Create protected ETS table for fast reads
    table =
      :ets.new(table_name, [
        :set,
        :protected,
        :named_table,
        {:keypos, 1},
        {:read_concurrency, true}
      ])

    Logger.debug("SubscriptionStorage started with table: #{inspect(table_name)}")
    {:ok, %{table: table, table_name: table_name}}
  end

  @impl true
  def handle_call({:put, subscription_id, subscription_data}, _from, state) do
    :ets.insert(state.table, {subscription_id, subscription_data})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, subscription_id}, _from, state) do
    :ets.delete(state.table, subscription_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:clear_all, _from, state) do
    :ets.delete_all_objects(state.table)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("SubscriptionStorage terminating", reason: reason, table: state.table_name)

    # ETS table will be automatically cleaned up when process terminates
    :ok
  end
end
