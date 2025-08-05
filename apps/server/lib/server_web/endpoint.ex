defmodule ServerWeb.Endpoint do
  @moduledoc "Phoenix endpoint configuration for the server application."

  use Phoenix.Endpoint, otp_app: :server

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_server_key",
    signing_salt: "Hd846dm2",
    same_site: "Lax"
  ]

  # socket "/live", Phoenix.LiveView.Socket,
  #   websocket: [connect_info: [session: @session_options]],
  #   longpoll: [connect_info: [session: @session_options]]

  # WebSocket endpoint for dashboard and event clients
  socket "/socket", ServerWeb.UserSocket,
    websocket: [
      # 90 seconds (3x client heartbeat of 30s)
      timeout: 90_000,
      # Enable transport debugging to see heartbeats
      transport_log: :debug,
      compress: true,
      check_origin: [
        "http://localhost:*",
        "http://127.0.0.1:*",
        "http://saya:*",
        "http://zelan:*",
        "http://demi:*",
        "http://alys:*",
        "//localhost:*",
        "//127.0.0.1:*",
        "//saya:*",
        "//zelan:*",
        "//demi:*",
        "//alys:*"
      ]
    ],
    longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :server,
    gzip: false,
    only: ServerWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :server
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # CORS support for OpenAPI/Swagger and dashboard
  plug Corsica,
    origins: "*",
    allow_headers: :all,
    allow_methods: :all

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ServerWeb.Router
end
