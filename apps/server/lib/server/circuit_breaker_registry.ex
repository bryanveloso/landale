defmodule Server.CircuitBreakerRegistry do
  @moduledoc """
  Registry for managing circuit breakers across the application.

  Provides a centralized way to create, retrieve, and monitor circuit breakers
  for different external services. Uses ETS for fast access and GenServer for
  coordination.

  ## Usage

      # Get or create a circuit breaker for a service
      circuit_breaker = CircuitBreakerRegistry.get_or_create("twitch-api", %{
        failure_threshold: 3,
        timeout_ms: 30_000
      })

      # Use circuit breaker
      CircuitBreaker.call(circuit_breaker, fn ->
        # External service call
      end)

      # Get all circuit breaker metrics
      metrics = CircuitBreakerRegistry.get_all_metrics()
  """

  use GenServer
  require Logger

  alias Server.CircuitBreaker

  @table_name :circuit_breaker_registry
  # 1 minute
  @cleanup_interval 60_000

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets an existing circuit breaker or creates a new one with the given configuration.
  """
  def get_or_create(name, config \\ %{}) do
    GenServer.call(__MODULE__, {:get_or_create, name, config})
  end

  @doc """
  Gets an existing circuit breaker by name.
  """
  def get(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, circuit_breaker}] -> {:ok, circuit_breaker}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Updates a circuit breaker in the registry.
  """
  def update(circuit_breaker) do
    GenServer.call(__MODULE__, {:update, circuit_breaker})
  end

  @doc """
  Gets metrics for all circuit breakers.
  """
  def get_all_metrics do
    GenServer.call(__MODULE__, :get_all_metrics)
  end

  @doc """
  Removes a circuit breaker from the registry.
  """
  def remove(name) do
    GenServer.call(__MODULE__, {:remove, name})
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    # Create ETS table for fast circuit breaker access
    :ets.new(@table_name, [:named_table, :public, read_concurrency: true])

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("Circuit breaker registry started", %{
      table: @table_name,
      cleanup_interval_ms: @cleanup_interval
    })

    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_or_create, name, config}, _from, state) do
    circuit_breaker =
      case :ets.lookup(@table_name, name) do
        [{^name, existing_circuit}] ->
          existing_circuit

        [] ->
          new_circuit = CircuitBreaker.new(name, config)
          :ets.insert(@table_name, {name, new_circuit})

          Logger.debug("Created new circuit breaker", %{
            name: name,
            config: config
          })

          new_circuit
      end

    {:reply, circuit_breaker, state}
  end

  @impl true
  def handle_call({:update, circuit_breaker}, _from, state) do
    name = circuit_breaker.name
    :ets.insert(@table_name, {name, circuit_breaker})

    # Emit telemetry for circuit breaker updates
    :telemetry.execute(
      [:circuit_breaker, :updated],
      %{count: 1},
      %{
        name: name,
        state: circuit_breaker.state,
        failure_count: circuit_breaker.failure_count
      }
    )

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_all_metrics, _from, state) do
    metrics =
      @table_name
      |> :ets.tab2list()
      |> Enum.map(fn {_name, circuit_breaker} ->
        CircuitBreaker.get_metrics(circuit_breaker)
      end)

    {:reply, metrics, state}
  end

  @impl true
  def handle_call({:remove, name}, _from, state) do
    result =
      case :ets.lookup(@table_name, name) do
        [{^name, _circuit_breaker}] ->
          :ets.delete(@table_name, name)
          Logger.debug("Removed circuit breaker", %{name: name})
          :ok

        [] ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    perform_cleanup()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp perform_cleanup do
    # Find circuit breakers that haven't been used recently and are in closed state
    cutoff_time = DateTime.add(DateTime.utc_now(), -@cleanup_interval * 5, :millisecond)

    circuits_to_remove =
      @table_name
      |> :ets.tab2list()
      |> Enum.filter(fn {_name, circuit_breaker} ->
        circuit_breaker.state == :closed and
          circuit_breaker.failure_count == 0 and
          DateTime.compare(circuit_breaker.state_changed_at, cutoff_time) == :lt
      end)
      |> Enum.map(fn {name, _circuit_breaker} -> name end)

    if length(circuits_to_remove) > 0 do
      Enum.each(circuits_to_remove, fn name ->
        :ets.delete(@table_name, name)
      end)

      Logger.debug("Cleaned up unused circuit breakers", %{
        removed_count: length(circuits_to_remove),
        names: circuits_to_remove
      })
    end
  end
end
