defmodule Server.Services.OBS.ConnectionsSupervisor do
  @moduledoc """
  Supervises all OBS connection sessions.

  Each OBS connection gets its own supervision tree managed by OBS.Supervisor.
  This supervisor manages all of those session supervisors.
  """
  use DynamicSupervisor
  require Logger

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a new OBS session with the given ID.
  """
  def start_session(session_id, opts \\ []) do
    spec = {
      Server.Services.OBS.Supervisor,
      Keyword.put(opts, :session_id, session_id)
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        Logger.info("Started OBS session: #{session_id}",
          service: "obs",
          session_id: session_id
        )

        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("OBS session already exists: #{session_id}",
          service: "obs",
          session_id: session_id
        )

        {:ok, pid}

      error ->
        Logger.error("Failed to start OBS session: #{inspect(error)}",
          service: "obs",
          session_id: session_id
        )

        error
    end
  end

  @doc """
  Stop an OBS session.
  """
  def stop_session(session_id) do
    try do
      case Server.Services.OBS.Supervisor.whereis(session_id) do
        nil ->
          {:error, :not_found}

        pid ->
          DynamicSupervisor.terminate_child(__MODULE__, pid)
      end
    catch
      _type, _reason -> {:error, :not_found}
    end
  end

  @doc """
  List all active sessions.
  """
  def list_sessions do
    try do
      DynamicSupervisor.which_children(__MODULE__)
      |> Enum.map(fn {_, pid, _, _} -> pid end)
      |> Enum.filter(&is_pid/1)
    catch
      :exit, _ -> []
    end
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
