defmodule Server.ServiceRegistry do
  @moduledoc """
  Registry for all services in the system.

  Provides unified service discovery and health checking for all services,
  regardless of their internal architecture (Server.Service, gen_statem, etc).

  All services must implement Server.ServiceBehaviour to be registered.
  """

  use GenServer
  require Logger

  @table_name :service_registry_table

  ## Client API

  @doc """
  Start the service registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a service with the registry.

  Services must implement Server.ServiceBehaviour.
  """
  @spec register(atom(), pid()) :: :ok
  def register(service_module, pid) when is_atom(service_module) and is_pid(pid) do
    GenServer.call(__MODULE__, {:register, service_module, pid})
  end

  @doc """
  List all registered services.
  """
  @spec list_services() :: [map()]
  def list_services do
    GenServer.call(__MODULE__, :list_services)
  end

  @doc """
  Get information about a specific service.
  """
  @spec get_service(atom()) :: {:ok, map()} | {:error, :not_found}
  def get_service(service_module) do
    GenServer.call(__MODULE__, {:get_service, service_module})
  end

  @doc """
  Get health status for all services.
  """
  @spec get_all_health() :: %{atom() => map()}
  def get_all_health do
    GenServer.call(__MODULE__, :get_all_health)
  end

  @doc """
  Get health status for a specific service.
  """
  @spec get_service_health(atom()) :: {:ok, map()} | {:error, term()}
  def get_service_health(service_module) do
    GenServer.call(__MODULE__, {:get_service_health, service_module})
  end

  @doc """
  Get overall system health based on all services.
  """
  @spec get_system_health() :: map()
  def get_system_health do
    GenServer.call(__MODULE__, :get_system_health)
  end

  ## Server Callbacks

  @impl GenServer
  def init(_opts) do
    # Create ETS table for fast lookups
    :ets.new(@table_name, [:named_table, :protected, :set])

    # Monitor all registered services
    Process.flag(:trap_exit, true)

    {:ok, %{monitors: %{}}}
  end

  @impl GenServer
  def handle_call({:register, service_module, pid}, _from, state) do
    # Verify the module implements ServiceBehaviour
    if function_exported?(service_module, :get_info, 0) and
         function_exported?(service_module, :get_health, 0) do
      # Get service info
      info = service_module.get_info()

      # Monitor the service process
      ref = Process.monitor(pid)

      # Store in ETS
      :ets.insert(@table_name, {service_module, pid, info})

      # Update monitors
      new_monitors = Map.put(state.monitors, ref, service_module)

      Logger.info("Service registered",
        service: info.name,
        module: service_module,
        pid: inspect(pid)
      )

      {:reply, :ok, %{state | monitors: new_monitors}}
    else
      {:reply, {:error, :not_service_behaviour}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_services, _from, state) do
    services =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {module, pid, info} ->
        %{
          module: module,
          pid: pid,
          name: info.name,
          version: info.version,
          capabilities: info.capabilities,
          description: info.description
        }
      end)

    {:reply, services, state}
  end

  @impl GenServer
  def handle_call({:get_service, service_module}, _from, state) do
    case :ets.lookup(@table_name, service_module) do
      [{^service_module, pid, info}] ->
        {:reply,
         {:ok,
          %{
            module: service_module,
            pid: pid,
            name: info.name,
            version: info.version,
            capabilities: info.capabilities,
            description: info.description
          }}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_all_health, _from, state) do
    health_map =
      :ets.tab2list(@table_name)
      |> Map.new(fn {module, _pid, info} ->
        health =
          case safe_call_health(module) do
            {:ok, health_data} ->
              health_data

            {:error, reason} ->
              %{
                status: :unhealthy,
                error: reason,
                details: %{}
              }
          end

        {info.name, health}
      end)

    {:reply, health_map, state}
  end

  @impl GenServer
  def handle_call({:get_service_health, service_module}, _from, state) do
    case :ets.lookup(@table_name, service_module) do
      [{^service_module, _pid, _info}] ->
        result = safe_call_health(service_module)
        {:reply, result, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_system_health, _from, state) do
    services = :ets.tab2list(@table_name)

    health_results =
      Enum.map(services, fn {module, _pid, info} ->
        {info.name, safe_call_health(module)}
      end)

    # Calculate overall system health
    {healthy_count, degraded_count, unhealthy_count} =
      Enum.reduce(health_results, {0, 0, 0}, fn {_name, health_result}, {h, d, u} ->
        case health_result do
          {:ok, %{status: :healthy}} -> {h + 1, d, u}
          {:ok, %{status: :degraded}} -> {h, d + 1, u}
          _ -> {h, d, u + 1}
        end
      end)

    total_services = length(services)

    system_status =
      cond do
        unhealthy_count > 0 -> :unhealthy
        degraded_count > total_services / 2 -> :unhealthy
        degraded_count > 0 -> :degraded
        true -> :healthy
      end

    system_health = %{
      status: system_status,
      services: Map.new(health_results),
      summary: %{
        total: total_services,
        healthy: healthy_count,
        degraded: degraded_count,
        unhealthy: unhealthy_count
      }
    }

    {:reply, system_health, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      service_module ->
        Logger.warning("Service process terminated",
          service: service_module,
          reason: inspect(reason)
        )

        # Remove from ETS
        :ets.delete(@table_name, service_module)

        # Remove monitor
        new_monitors = Map.delete(state.monitors, ref)

        {:noreply, %{state | monitors: new_monitors}}
    end
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp safe_call_health(service_module) do
    try do
      service_module.get_health()
    rescue
      error ->
        {:error, {:health_check_failed, inspect(error)}}
    catch
      :exit, reason ->
        {:error, {:service_dead, reason}}
    end
  end
end
