defmodule Nurvus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Local process registry using standard Elixir Registry
      {Registry, [keys: :unique, name: Nurvus.ProcessRegistry]},

      # Process supervision tree
      Nurvus.ProcessSupervisor,
      Nurvus.ProcessManager,
      Nurvus.ProcessMonitor,

      # HTTP API server
      Nurvus.HttpServer
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Nurvus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
