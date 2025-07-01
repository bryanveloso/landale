defmodule ServerWeb.ProcessController do
  @moduledoc """
  REST API controller for distributed process management.

  Provides endpoints for controlling processes across the Elixir cluster,
  enabling Stream Deck and other external systems to manage processes
  on any node in the distributed system.
  """

  use ServerWeb, :controller

  require Logger

  alias Server.Services.ProcessSupervisor

  @doc """
  Get the status of all processes across the entire cluster.

  ## Example Response

      {
        "status": "success",
        "cluster": {
          "zelan": [
            {
              "name": "terminal",
              "display_name": "Terminal",
              "status": "running", 
              "pid": 1234,
              "memory_mb": 45.2,
              "cpu_percent": 1.5
            }
          ],
          "demi": [
            {
              "name": "obs",
              "display_name": "OBS Studio",
              "status": "stopped",
              "pid": null,
              "memory_mb": 0,
              "cpu_percent": 0.0
            }
          ]
        },
        "nodes": ["zelan", "demi", "saya", "alys"]
      }
  """
  def cluster_status(conn, _params) do
    cluster_data = ProcessSupervisor.cluster_status()
    nodes = ProcessSupervisor.get_cluster_nodes()

    json(conn, %{
      status: "success",
      cluster: cluster_data,
      nodes: nodes,
      timestamp: DateTime.utc_now()
    })
  rescue
    error ->
      Logger.error("Failed to get cluster status", error: inspect(error))

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        status: "error",
        message: "Failed to retrieve cluster status",
        error: inspect(error)
      })
  end

  @doc """
  Get all processes for a specific node.

  ## Example Response

      {
        "status": "success",
        "node": "demi",
        "processes": [
          {
            "name": "obs",
            "display_name": "OBS Studio", 
            "status": "running",
            "pid": 5678,
            "memory_mb": 256.7,
            "cpu_percent": 12.3
          }
        ]
      }
  """
  def node_processes(conn, %{"node" => node_name}) do
    case ProcessSupervisor.list_processes(node_name) do
      {:ok, processes} ->
        json(conn, %{
          status: "success",
          node: node_name,
          processes: processes,
          timestamp: DateTime.utc_now()
        })

      {:error, :node_not_available} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Node not available",
          node: node_name
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          status: "error",
          message: "Failed to list processes",
          node: node_name,
          error: inspect(reason)
        })
    end
  rescue
    error ->
      Logger.error("Exception getting node processes",
        node: node_name,
        error: inspect(error)
      )

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        status: "error",
        message: "System error retrieving processes",
        node: node_name,
        error: inspect(error)
      })
  end

  @doc """
  Get status of a specific process on a specific node.

  ## Example Response

      {
        "status": "success",
        "node": "demi",
        "process": {
          "name": "obs",
          "display_name": "OBS Studio",
          "status": "running",
          "pid": 5678, 
          "memory_mb": 256.7,
          "cpu_percent": 12.3
        }
      }
  """
  def process_status(conn, %{"node" => node_name, "process" => process_name}) do
    case ProcessSupervisor.get_process_info(node_name, process_name) do
      {:ok, process_info} ->
        json(conn, %{
          status: "success",
          node: node_name,
          process: process_info,
          timestamp: DateTime.utc_now()
        })

      {:error, :node_not_available} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Node not available",
          node: node_name,
          process: process_name
        })

      {:error, :process_not_managed} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          message: "Process not managed by this node",
          node: node_name,
          process: process_name
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          status: "error",
          message: "Failed to get process info",
          node: node_name,
          process: process_name,
          error: inspect(reason)
        })
    end
  rescue
    error ->
      Logger.error("Exception getting process status",
        node: node_name,
        process: process_name,
        error: inspect(error)
      )

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        status: "error",
        message: "System error retrieving process status",
        node: node_name,
        process: process_name,
        error: inspect(error)
      })
  end

  @doc """
  Start a process on a specific node.

  ## Example Response

      {
        "status": "success",
        "message": "Process started successfully",
        "node": "demi",
        "process": "obs"
      }
  """
  def start_process(conn, %{"node" => node_name, "process" => process_name}) do
    Logger.info("Starting process via API",
      node: node_name,
      process: process_name
    )

    case ProcessSupervisor.start_process(node_name, process_name) do
      :ok ->
        json(conn, %{
          status: "success",
          message: "Process started successfully",
          node: node_name,
          process: process_name,
          timestamp: DateTime.utc_now()
        })

      {:error, :node_not_available} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Node not available",
          node: node_name,
          process: process_name
        })

      {:error, :process_not_managed} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          message: "Process not managed by this node",
          node: node_name,
          process: process_name
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          status: "error",
          message: "Failed to start process",
          node: node_name,
          process: process_name,
          error: inspect(reason)
        })
    end
  rescue
    error ->
      Logger.error("Exception starting process",
        node: node_name,
        process: process_name,
        error: inspect(error)
      )

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        status: "error",
        message: "System error starting process",
        node: node_name,
        process: process_name,
        error: inspect(error)
      })
  end

  @doc """
  Stop a process on a specific node.

  ## Example Response

      {
        "status": "success",
        "message": "Process stopped successfully",
        "node": "demi",
        "process": "obs"
      }
  """
  def stop_process(conn, %{"node" => node_name, "process" => process_name}) do
    Logger.info("Stopping process via API",
      node: node_name,
      process: process_name
    )

    case ProcessSupervisor.stop_process(node_name, process_name) do
      :ok ->
        json(conn, %{
          status: "success",
          message: "Process stopped successfully",
          node: node_name,
          process: process_name,
          timestamp: DateTime.utc_now()
        })

      {:error, :node_not_available} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Node not available",
          node: node_name,
          process: process_name
        })

      {:error, :process_not_managed} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          message: "Process not managed by this node",
          node: node_name,
          process: process_name
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          status: "error",
          message: "Failed to stop process",
          node: node_name,
          process: process_name,
          error: inspect(reason)
        })
    end
  rescue
    error ->
      Logger.error("Exception stopping process",
        node: node_name,
        process: process_name,
        error: inspect(error)
      )

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        status: "error",
        message: "System error stopping process",
        node: node_name,
        process: process_name,
        error: inspect(error)
      })
  end

  @doc """
  Restart a process on a specific node.

  ## Example Response

      {
        "status": "success",
        "message": "Process restarted successfully",
        "node": "demi",
        "process": "obs"
      }
  """
  def restart_process(conn, %{"node" => node_name, "process" => process_name}) do
    Logger.info("Restarting process via API",
      node: node_name,
      process: process_name
    )

    case ProcessSupervisor.restart_process(node_name, process_name) do
      :ok ->
        json(conn, %{
          status: "success",
          message: "Process restarted successfully",
          node: node_name,
          process: process_name,
          timestamp: DateTime.utc_now()
        })

      {:error, :node_not_available} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Node not available",
          node: node_name,
          process: process_name
        })

      {:error, :process_not_managed} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          message: "Process not managed by this node",
          node: node_name,
          process: process_name
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          status: "error",
          message: "Failed to restart process",
          node: node_name,
          process: process_name,
          error: inspect(reason)
        })
    end
  rescue
    error ->
      Logger.error("Exception restarting process",
        node: node_name,
        process: process_name,
        error: inspect(error)
      )

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        status: "error",
        message: "System error restarting process",
        node: node_name,
        process: process_name,
        error: inspect(error)
      })
  end
end
