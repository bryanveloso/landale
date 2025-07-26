defmodule Nurvus.ProcessRegistry do
  @moduledoc """
  Simple wrapper around Elixir's Registry for local process discovery.

  Provides a clean API for process registration and lookup within
  a single node, perfect for single-machine deployments.
  """

  require Logger

  @registry Nurvus.ProcessRegistry
  @process_key_prefix :process

  ## Client API

  @doc """
  Register a process in the registry.
  """
  @spec register(String.t(), pid()) :: {:ok, pid()} | {:error, term()}
  def register(process_id, pid) when is_binary(process_id) and is_pid(pid) do
    key = {@process_key_prefix, process_id}

    case Registry.register(@registry, key, nil) do
      {:ok, _owner} ->
        Logger.debug("Registered process #{process_id} in registry")
        {:ok, pid}

      {:error, {:already_registered, _pid}} = error ->
        Logger.warning("Process #{process_id} already registered")
        error
    end
  end

  @doc """
  Unregister a process from the registry.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(process_id) when is_binary(process_id) do
    key = {@process_key_prefix, process_id}
    Registry.unregister(@registry, key)
    Logger.debug("Unregistered process #{process_id} from registry")
    :ok
  end

  @doc """
  Look up a process in the registry.
  Returns the pid if found.
  """
  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(process_id) when is_binary(process_id) do
    key = {@process_key_prefix, process_id}

    case Registry.lookup(@registry, key) do
      [] ->
        {:error, :not_found}

      [{pid, _value}] ->
        {:ok, pid}

      multiple when is_list(multiple) ->
        # Should not happen with unique keys, but handle gracefully
        Logger.warning("Multiple registrations found for #{process_id}: #{inspect(multiple)}")
        [{pid, _value} | _] = multiple
        {:ok, pid}
    end
  end

  @doc """
  List all processes registered in the registry.
  """
  @spec list_processes() :: [%{id: String.t(), pid: pid()}]
  def list_processes do
    Registry.select(@registry, [
      {{{@process_key_prefix, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.map(fn {process_id, pid} ->
      %{
        id: to_string(process_id),
        pid: pid
      }
    end)
  end

  @doc """
  Get process count in the registry.
  """
  @spec process_count() :: non_neg_integer()
  def process_count do
    length(list_processes())
  end
end
