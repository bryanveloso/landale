defmodule Server.Services.OBS.Supervisor do
  @moduledoc """
  Supervisor for individual OBS WebSocket sessions.

  Uses a one_for_all strategy because all child processes depend on
  the Connection process. If the connection dies, all other processes
  should restart together.
  """
  use Supervisor

  def start_link(opts) when is_list(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    name = via_tuple(session_id)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def start_link({session_id, opts}) do
    name = via_tuple(session_id)
    Supervisor.start_link(__MODULE__, {session_id, opts}, name: name)
  end

  @impl true
  def init(opts) when is_list(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    init({session_id, opts})
  end

  def init({session_id, opts}) do
    children = [
      # Core connection process using gen_statem
      {Server.Services.OBS.Connection,
       name: via_tuple(session_id, :connection), session_id: session_id, uri: opts[:uri]},

      # Event processing and routing
      {Server.Services.OBS.EventHandler, name: via_tuple(session_id, :event_handler), session_id: session_id},

      # Request tracking and timeout management
      {Server.Services.OBS.RequestTracker, name: via_tuple(session_id, :request_tracker), session_id: session_id},

      # Scene state management
      {Server.Services.OBS.SceneManager, name: via_tuple(session_id, :scene_manager), session_id: session_id},

      # Stream and recording state
      {Server.Services.OBS.StreamManager, name: via_tuple(session_id, :stream_manager), session_id: session_id},

      # Performance metrics collection (disabled due to timeout issues)
      # {Server.Services.OBS.StatsCollector, name: via_tuple(session_id, :stats_collector), session_id: session_id},

      # Task supervisor for async operations
      {Task.Supervisor, name: via_tuple(session_id, :task_supervisor)}
    ]

    # one_for_all - if connection dies, restart everything
    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Get the Registry name for a session and optional process type.
  """
  def via_tuple(session_id, process_type \\ nil) do
    name =
      if process_type do
        {session_id, process_type}
      else
        session_id
      end

    {:via, Registry, {Server.Services.OBS.SessionRegistry, name}}
  end

  @doc """
  Find a specific process within a session.
  """
  def get_process(session_id, process_type) do
    case Registry.lookup(Server.Services.OBS.SessionRegistry, {session_id, process_type}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Find supervisor pid by session ID.
  """
  def whereis(session_id) do
    case Registry.lookup(Server.Services.OBS.SessionRegistry, session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
