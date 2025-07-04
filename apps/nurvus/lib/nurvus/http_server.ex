defmodule Nurvus.HttpServer do
  @moduledoc """
  HTTP server for the Nurvus process management API.

  Uses Bandit as the HTTP server with Plug for routing.
  """

  use GenServer
  require Logger

  @default_port 4001

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_port() :: integer()
  def get_port do
    GenServer.call(__MODULE__, :get_port)
  end

  @spec get_status() :: map()
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    port = get_port_config(opts)

    # Start the Bandit server
    case start_bandit_server(port) do
      {:ok, pid} ->
        Logger.info("Nurvus HTTP API started on port #{port}")

        state = %{
          port: port,
          server_pid: pid,
          start_time: DateTime.utc_now()
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start HTTP server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    status = %{
      port: state.port,
      uptime_seconds: uptime_seconds,
      server_pid: state.server_pid,
      status: :running
    }

    {:reply, status, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Shutting down HTTP server: #{inspect(reason)}")

    if state.server_pid do
      GenServer.stop(state.server_pid)
    end

    :ok
  end

  ## Private Functions

  defp get_port_config(opts) do
    cond do
      port = Keyword.get(opts, :port) -> port
      port = Application.get_env(:nurvus, :http_port) -> port
      port = System.get_env("NURVUS_PORT") -> String.to_integer(port)
      true -> @default_port
    end
  end

  defp start_bandit_server(port) do
    server_opts = [
      plug: Nurvus.Router,
      port: port
    ]

    Bandit.start_link(server_opts)
  end
end
