defmodule ServerWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms with initial startup delay to prevent early database access
      {:telemetry_poller, 
       measurements: periodic_measurements(), 
       period: 10_000,
       initial_delay: 15_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("server.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("server.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("server.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("server.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("server.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # OBS Service Metrics
      counter("server.obs.connection.attempts"),
      counter("server.obs.connection.successes"),
      counter("server.obs.connection.failures"),
      summary("server.obs.connection.duration", unit: {:native, :millisecond}),
      counter("server.obs.requests.total", tags: [:request_type]),
      counter("server.obs.requests.success", tags: [:request_type]),
      counter("server.obs.requests.failure", tags: [:request_type]),
      summary("server.obs.requests.duration", tags: [:request_type], unit: {:native, :millisecond}),
      last_value("server.obs.connection.status", tags: [:state]),

      # Twitch Service Metrics
      counter("server.twitch.connection.attempts"),
      counter("server.twitch.connection.successes"),
      counter("server.twitch.connection.failures"),
      summary("server.twitch.connection.duration", unit: {:native, :millisecond}),
      counter("server.twitch.subscriptions.created", tags: [:event_type]),
      counter("server.twitch.subscriptions.deleted", tags: [:event_type]),
      counter("server.twitch.subscriptions.failed", tags: [:event_type, :reason]),
      last_value("server.twitch.subscriptions.active"),
      last_value("server.twitch.subscriptions.cost"),
      counter("server.twitch.events.received", tags: [:event_type]),
      counter("server.twitch.oauth.refresh.attempts"),
      counter("server.twitch.oauth.refresh.successes"),
      counter("server.twitch.oauth.refresh.failures"),

      # Event System Metrics
      counter("server.events.published", tags: [:event_type, :topic]),
      counter("server.events.subscribers", tags: [:topic]),

      # Health Check Metrics
      counter("server.health.checks", tags: [:endpoint]),
      summary("server.health.response_time", tags: [:endpoint], unit: {:native, :millisecond}),
      last_value("server.health.status", tags: [:service])
    ]
  end

  defp periodic_measurements do
    # Only measure services in non-test environments
    if Application.get_env(:server, :env, :dev) == :test do
      []
    else
      [
        # Service status measurements
        {Server.Telemetry, :measure_obs_status, []},
        {Server.Telemetry, :measure_twitch_status, []},
        {Server.Telemetry, :measure_system_health, []}
      ]
    end
  end
end
