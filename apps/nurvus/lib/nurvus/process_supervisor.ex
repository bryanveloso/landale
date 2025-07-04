defmodule Nurvus.ProcessSupervisor do
  @moduledoc """
  Dynamic supervisor for managing individual processes.

  This module provides a clean interface for starting and stopping
  external processes under supervision.
  """

  use DynamicSupervisor
  require Logger

  alias Nurvus.ProcessRunner

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec start_process(map()) :: {:ok, pid()} | {:error, term()}
  def start_process(config) do
    child_spec = {ProcessRunner, config}

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.debug("Started process runner: #{config.id} (#{inspect(pid)})")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start process runner for #{config.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec stop_process(pid()) :: :ok
  def stop_process(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @spec count_children() :: map()
  def count_children do
    DynamicSupervisor.count_children(__MODULE__)
  end

  @spec which_children() :: [term()]
  def which_children do
    DynamicSupervisor.which_children(__MODULE__)
  end

  ## DynamicSupervisor Callbacks

  @impl true
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, :one_for_one)
    max_restarts = Keyword.get(opts, :max_restarts, 3)
    max_seconds = Keyword.get(opts, :max_seconds, 5)

    DynamicSupervisor.init(
      strategy: strategy,
      max_restarts: max_restarts,
      max_seconds: max_seconds
    )
  end
end
