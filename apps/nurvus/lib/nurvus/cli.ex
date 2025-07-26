defmodule Nurvus.CLI do
  @moduledoc """
  Remote CLI for a running Nurvus node using distributed Erlang.

  This CLI connects to a running Nurvus release and executes commands via RPC.
  Designed to work with Burrito compilation and custom release commands.
  """

  require Logger

  @doc """
  Main entrypoint for the CLI. Called by the custom release command.
  """
  def main(args) do
    case args do
      [] ->
        print_help()

      ["--help"] ->
        print_help()

      ["status"] ->
        execute_remote_command(&get_status/1)

      ["list"] ->
        execute_remote_command(&list_processes/1)

      ["start", process_id] ->
        execute_remote_command(&start_process/2, [process_id])

      ["stop", process_id] ->
        execute_remote_command(&stop_process/2, [process_id])

      ["restart", process_id] ->
        execute_remote_command(&restart_process/2, [process_id])

      ["config", "get", key] ->
        execute_remote_command(&get_config/2, [key])

      ["config", "list"] ->
        execute_remote_command(&list_config/1)

      ["cluster", "info"] ->
        execute_remote_command(&cluster_info/1)

      _ ->
        IO.puts("Unknown command. Use --help for usage information.")
        System.halt(1)
    end
  end

  ## Command Functions (executed on remote node via RPC)

  defp get_status(target_node) do
    case :rpc.call(target_node, Nurvus.ProcessManager, :list_processes, []) do
      {:badrpc, reason} ->
        {:error, "Failed to get status: #{inspect(reason)}"}

      processes ->
        running = Enum.count(processes, &(&1.status == :running))
        stopped = Enum.count(processes, &(&1.status == :stopped))
        failed = Enum.count(processes, &(&1.status == :failed))

        status = %{
          total_processes: length(processes),
          running: running,
          stopped: stopped,
          failed: failed,
          node: target_node,
          cluster_nodes: :rpc.call(target_node, :erlang, :nodes, [:connected])
        }

        {:ok, status}
    end
  end

  defp list_processes(target_node) do
    case :rpc.call(target_node, Nurvus.ProcessManager, :list_processes, []) do
      {:badrpc, reason} ->
        {:error, "Failed to list processes: #{inspect(reason)}"}

      processes ->
        {:ok, processes}
    end
  end

  defp start_process(target_node, process_id) do
    case :rpc.call(target_node, Nurvus.ProcessManager, :start_process, [process_id]) do
      {:badrpc, reason} ->
        {:error, "Failed to start process: #{inspect(reason)}"}

      :ok ->
        {:ok, "Process #{process_id} started successfully"}

      {:error, reason} ->
        {:error, "Failed to start process #{process_id}: #{inspect(reason)}"}
    end
  end

  defp stop_process(target_node, process_id) do
    case :rpc.call(target_node, Nurvus.ProcessManager, :stop_process, [process_id]) do
      {:badrpc, reason} ->
        {:error, "Failed to stop process: #{inspect(reason)}"}

      :ok ->
        {:ok, "Process #{process_id} stopped successfully"}

      {:error, reason} ->
        {:error, "Failed to stop process #{process_id}: #{inspect(reason)}"}
    end
  end

  defp restart_process(target_node, process_id) do
    case :rpc.call(target_node, Nurvus.ProcessManager, :restart_process, [process_id]) do
      {:badrpc, reason} ->
        {:error, "Failed to restart process: #{inspect(reason)}"}

      :ok ->
        {:ok, "Process #{process_id} restarted successfully"}

      {:error, reason} ->
        {:error, "Failed to restart process #{process_id}: #{inspect(reason)}"}
    end
  end

  defp get_config(target_node, key) do
    case :rpc.call(target_node, Nurvus.Config, :get, [key]) do
      {:badrpc, reason} ->
        {:error, "Failed to get config: #{inspect(reason)}"}

      value ->
        {:ok, %{key: key, value: value}}
    end
  end

  defp list_config(target_node) do
    case :rpc.call(target_node, Nurvus.Config, :get_all, []) do
      {:badrpc, reason} ->
        {:error, "Failed to get config: #{inspect(reason)}"}

      config ->
        {:ok, config}
    end
  end

  defp cluster_info(target_node) do
    nodes = :rpc.call(target_node, :erlang, :nodes, [:connected])
    node_info = :rpc.call(target_node, :erlang, :node, [])

    case nodes do
      {:badrpc, reason} ->
        {:error, "Failed to get cluster info: #{inspect(reason)}"}

      connected_nodes ->
        {:ok,
         %{
           current_node: node_info,
           connected_nodes: connected_nodes,
           total_nodes: length(connected_nodes) + 1
         }}
    end
  end

  ## Helper Functions

  defp execute_remote_command(command_func, args \\ []) do
    target_node = get_target_node()

    case connect_to_node(target_node) do
      :ok ->
        case apply(command_func, [target_node | args]) do
          {:ok, result} ->
            print_result(result)
            System.halt(0)

          {:error, message} ->
            IO.puts("Error: #{message}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("Failed to connect to node #{target_node}: #{reason}")
        System.halt(1)
    end
  end

  defp get_target_node do
    # Try environment variable first, then default
    case System.get_env("NURVUS_TARGET_NODE") do
      nil ->
        # Default node name based on current hostname
        hostname = :inet.gethostname() |> elem(1) |> to_string()
        :"nurvus@#{hostname}"

      node_string ->
        String.to_atom(node_string)
    end
  end

  defp connect_to_node(target_node) do
    # Set up this CLI process as a distributed node
    {:ok, _} = :net_kernel.start([:nurvus_cli, :shortnames])

    # Set cookie (should match the target node)
    cookie = System.get_env("NURVUS_COOKIE", "nurvus_cookie") |> String.to_atom()
    :erlang.set_cookie(cookie)

    # Try to connect
    case Node.connect(target_node) do
      true -> :ok
      false -> {:error, "Connection failed - ensure target node is running"}
    end
  end

  defp print_result(result) when is_map(result) do
    result
    |> Jason.encode!(pretty: true)
    |> IO.puts()
  end

  defp print_result(result) when is_list(result) do
    result
    |> Jason.encode!(pretty: true)
    |> IO.puts()
  end

  defp print_result(result) do
    IO.puts(inspect(result, pretty: true))
  end

  defp print_help do
    IO.puts("""
    Nurvus CLI - Distributed Process Manager

    Usage:
      nurvus_cli [command] [options]

    Commands:
      status                    Show cluster and process status
      list                      List all processes
      start <process_id>        Start a process
      stop <process_id>         Stop a process
      restart <process_id>      Restart a process
      config get <key>          Get configuration value
      config list               List all configuration
      cluster info              Show cluster information
      --help                    Show this help message

    Environment Variables:
      NURVUS_TARGET_NODE        Target node to connect to (default: nurvus@<hostname>)
      NURVUS_COOKIE            Erlang cookie for authentication (default: nurvus_cookie)

    Examples:
      nurvus_cli status
      nurvus_cli start my_app
      nurvus_cli config get processes.my_app
      NURVUS_TARGET_NODE=nurvus@demi.local nurvus_cli cluster info
    """)
  end
end
