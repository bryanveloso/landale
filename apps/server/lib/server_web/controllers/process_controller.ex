defmodule ServerWeb.ProcessController do
  @moduledoc """
  REST API controller for distributed process management.

  Provides endpoints for controlling processes across the Elixir cluster,
  enabling Stream Deck and other external systems to manage processes
  on any node in the distributed system.
  """

  use ServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Server.Services.ProcessSupervisor
  alias ServerWeb.Schemas

  tags(["Process Management"])

  operation(:cluster_status,
    summary: "Get cluster-wide process status",
    description: "Returns the status of all managed processes across all nodes in the distributed cluster",
    responses: [
      ok: {"Cluster status", "application/json", Schemas.ClusterStatus},
      internal_server_error: {"Server error", "application/json", Schemas.ErrorResponse}
    ]
  )

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

  operation(:node_processes,
    summary: "Get processes for a specific node",
    description: "Returns all managed processes on the specified cluster node",
    parameters: [
      node: [in: :path, description: "Node name (e.g. 'demi', 'alys', 'saya', 'zelan')", type: :string, example: "demi"]
    ],
    responses: [
      ok: {"Node processes", "application/json", Schemas.NodeProcesses},
      not_found: {"Node not found", "application/json", Schemas.ErrorResponse},
      internal_server_error: {"Server error", "application/json", Schemas.ErrorResponse}
    ]
  )

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

  operation(:process_status,
    summary: "Get status of a specific process",
    description: "Returns detailed status information for a specific process on a specific node",
    parameters: [
      node: [in: :path, description: "Node name", type: :string, example: "demi"],
      process: [in: :path, description: "Process name", type: :string, example: "obs-studio"]
    ],
    responses: [
      ok: {"Process status", "application/json", Schemas.ProcessStatus},
      not_found: {"Process or node not found", "application/json", Schemas.ErrorResponse},
      service_unavailable: {"Node unavailable", "application/json", Schemas.ErrorResponse}
    ]
  )

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

  operation(:start_process,
    summary: "Start a process on a node",
    description: "Starts the specified process on the specified cluster node",
    parameters: [
      node: [in: :path, description: "Node name", type: :string, example: "demi"],
      process: [in: :path, description: "Process name", type: :string, example: "obs-studio"]
    ],
    responses: [
      ok: {"Process started", "application/json", Schemas.ProcessActionResponse},
      not_found: {"Process or node not found", "application/json", Schemas.ErrorResponse},
      service_unavailable: {"Node unavailable", "application/json", Schemas.ErrorResponse},
      internal_server_error: {"Start failed", "application/json", Schemas.ErrorResponse}
    ]
  )

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

  operation(:stop_process,
    summary: "Stop a process on a node",
    description: "Stops the specified process on the specified cluster node",
    parameters: [
      node: [in: :path, description: "Node name", type: :string, example: "demi"],
      process: [in: :path, description: "Process name", type: :string, example: "obs-studio"]
    ],
    responses: [
      ok: {"Process stopped", "application/json", Schemas.ProcessActionResponse},
      not_found: {"Process or node not found", "application/json", Schemas.ErrorResponse},
      service_unavailable: {"Node unavailable", "application/json", Schemas.ErrorResponse},
      internal_server_error: {"Stop failed", "application/json", Schemas.ErrorResponse}
    ]
  )

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

  operation(:restart_process,
    summary: "Restart a process on a node",
    description: "Stops and then starts the specified process on the specified cluster node",
    parameters: [
      node: [in: :path, description: "Node name", type: :string, example: "demi"],
      process: [in: :path, description: "Process name", type: :string, example: "obs-studio"]
    ],
    responses: [
      ok: {"Process restarted", "application/json", Schemas.ProcessActionResponse},
      not_found: {"Process or node not found", "application/json", Schemas.ErrorResponse},
      service_unavailable: {"Node unavailable", "application/json", Schemas.ErrorResponse},
      internal_server_error: {"Restart failed", "application/json", Schemas.ErrorResponse}
    ]
  )

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
